EnterpriseGarageBridge = {}

local columns
local function settings() return Config.OkokGarageBridge or {} end
function EnterpriseGarageBridge.enabled() return settings().Enabled == true end

-- Column names come from information_schema, never from a client request.
local function identifier(name)
    assert(type(name) == 'string' and name:match('^[%w_]+$'), 'Colonne owned_vehicles non prise en charge')
    return '`' .. name .. '`'
end

function EnterpriseGarageBridge.ensure(refresh)
    if not EnterpriseGarageBridge.enabled() and not refresh then return end
    if columns and not refresh then return end
    local unsafe = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME IN ('owned_vehicles', 'aegis_enterprise_fleet', 'aegis_enterprise_vehicle_bridges')
          AND ENGINE <> 'InnoDB'
    ]])
    if tonumber(unsafe) ~= 0 then error('La passerelle nécessite des tables InnoDB pour préserver les transferts atomiques.') end
    columns = MySQL.query.await([[
        SELECT COLUMN_NAME AS name, DATA_TYPE AS data_type, EXTRA AS extra
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'owned_vehicles'
        ORDER BY ORDINAL_POSITION
    ]]) or {}
    local found = {}
    for _, column in ipairs(columns) do
        identifier(column.name)
        found[column.name] = not (column.extra or ''):find('GENERATED', 1, true)
    end
    if not found.plate or not found.owner or not found.vehicle then
        columns = nil
        error('La passerelle okokGarage nécessite owned_vehicles avec plate, owner et vehicle.')
    end
end

function EnterpriseGarageBridge.owned(plate)
    local record = MySQL.single.await('SELECT original_record FROM aegis_enterprise_vehicle_bridges WHERE plate = ?', { plate })
    if not record then return nil end
    local ok, row = pcall(json.decode, record.original_record)
    if not ok or type(row) ~= 'table' then error('Sauvegarde de propriété du véhicule illisible : ' .. plate) end
    return row
end

function EnterpriseGarageBridge.canImport(player, jobName, ownership)
    for _, format in ipairs(Config.SocietyOwnerFormats) do
        if ownership.owner == format:format(jobName) then return true end
    end
    return EnterpriseGarageBridge.enabled() and settings().AllowEmployeeOwnedVehicles == true
        and player.identifier ~= nil and ownership.owner == player.identifier
end

function EnterpriseGarageBridge.captureQuery(plate, ownership)
    EnterpriseGarageBridge.ensure(true)
    local fields = {}
    for _, column in ipairs(columns) do
        if not (column.extra or ''):find('GENERATED', 1, true) then
            fields[#fields + 1] = "'" .. column.name .. "'"
            fields[#fields + 1] = 'o.' .. identifier(column.name)
        end
    end
    -- INSERT ... SELECT captures the current source row on the transaction's
    -- connection. The previous ownership/vehicle value is an optimistic guard.
    return {
        query = [[INSERT INTO aegis_enterprise_vehicle_bridges (plate, source_resource, original_record)
            SELECT ?, ?, JSON_OBJECT(]] .. table.concat(fields, ', ') .. [[)
            FROM owned_vehicles o
            WHERE UPPER(TRIM(o.plate)) = ? AND CAST(o.owner AS BINARY) = CAST(? AS BINARY)
                AND CAST(o.vehicle AS BINARY) = CAST(? AS BINARY)]],
        values = { plate, settings().ResourceName or 'okokGarage', plate, ownership.owner, ownership.vehicle }
    }
end

function EnterpriseGarageBridge.reserveQuery(plate)
    -- A reserved vehicle is absent from okokGarage's owned_vehicles listings.
    -- Its complete ownership row remains recoverable in the bridge table.
    return {
        query = [[DELETE o FROM owned_vehicles o
            JOIN aegis_enterprise_vehicle_bridges b ON CAST(UPPER(TRIM(o.plate)) AS BINARY) = CAST(b.plate AS BINARY)
            JOIN aegis_enterprise_fleet f ON CAST(f.plate AS BINARY) = CAST(b.plate AS BINARY)
            WHERE b.plate = ? AND CAST(o.owner AS BINARY) = CAST(JSON_UNQUOTE(JSON_EXTRACT(b.original_record, '$.owner')) AS BINARY)]],
        values = { plate }
    }
end

function EnterpriseGarageBridge.revokeSourceKeys(plate)
    local config = settings()
    if config.RevokeSourceKeys == false or GetResourceState(config.ResourceName or 'okokGarage') ~= 'started' then return end
    local event = (config.EventPrefix or 'okokGarage') .. ':RemoveKeys'
    -- Official okokGarage server API: TriggerEvent(event, plate, source).
    for _, online in ipairs(GetPlayers()) do
        local playerId = tonumber(online)
        if playerId and playerId > 0 then
            local ok, err = pcall(TriggerEvent, event, plate, playerId)
            if not ok then print('[aegis_garage] Révocation des clés okokGarage impossible : ' .. tostring(err)) end
        end
    end
end

function EnterpriseGarageBridge.releaseQueries(plate, properties)
    local row = EnterpriseGarageBridge.owned(plate)
    if not row then return {} end
    -- Also release old reservations if the operator later disables the bridge.
    EnterpriseGarageBridge.ensure(true)
    if MySQL.scalar.await('SELECT 1 FROM owned_vehicles WHERE UPPER(TRIM(plate)) = ? LIMIT 1', { plate }) then
        return nil, 'Une autre ligne owned_vehicles utilise déjà la plaque ' .. plate .. '. Retour annulé, sauvegarde conservée.'
    end
    if properties and properties ~= '' then row.vehicle = properties end
    local names, marks, values = {}, {}, {}
    for _, column in ipairs(columns) do
        if not (column.extra or ''):find('GENERATED', 1, true) then
            names[#names + 1] = identifier(column.name)
            local value = row[column.name]
            -- Preserve the original parking/garage, ownership and custom fields.
            if column.name == 'stored' then value = 1 end
            if value == nil then marks[#marks + 1] = 'NULL'
            else marks[#marks + 1] = '?'; values[#values + 1] = value end
        end
    end
    return {
        { query = 'INSERT INTO owned_vehicles (' .. table.concat(names, ', ') .. ') VALUES (' .. table.concat(marks, ', ') .. ')', values = values },
        { query = 'DELETE FROM aegis_enterprise_vehicle_bridges WHERE plate = ?', values = { plate } }
    }
end

exports('IsManagedPlate', function(plate)
    if type(plate) ~= 'string' then return false end
    plate = plate:match('^%s*(.-)%s*$'):upper()
    return MySQL.scalar.await('SELECT 1 FROM aegis_enterprise_fleet WHERE plate = ? LIMIT 1', { plate }) ~= nil
end)
