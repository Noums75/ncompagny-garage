local ESX = exports['es_extended']:getSharedObject()
local Garages = {}
local Busy = {}
local ActiveSync = {}
local PendingSync = {}
local SpawnLocks = {}
local GarageSessions = {}
local SessionEpochs = {}
local FleetEntities = {}
local MutationLock
local Ready = false

local function integer(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number % 1 ~= 0 or number < (minimum or 0) or number > (maximum or 4294967295) then return nil end
    return number
end

local function samePlayer(sourceId, player)
    return player and ESX.GetPlayerFromId(sourceId) == player
end

local MAX_ALLOWED_STAFF = 120

local function fail(message) return { ok = false, error = message } end
local function success(payload)
    payload = payload or {}
    payload.ok = true
    return payload
end

local function trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function validPlate(value)
    if type(value) ~= 'string' then return nil end
    local plate = trim(value):upper()
    if #plate < 1 or #plate > 8 or not plate:match('^[A-Z0-9 ]+$') then return nil end
    return plate
end

local function limitText(value, max)
    if type(value) ~= 'string' then return nil end
    local v = trim(value)
    local ok, length = pcall(utf8.len, v)
    if not ok or not length or length < 2 or length > max or v:find('[%c]') then return nil end
    return v
end

local function playerInfo(sourceId)
    local player = ESX.GetPlayerFromId(sourceId)
    if not player then return nil end
    local job = player.getJob and player.getJob() or player.job
    return player, job or { name = 'unemployed', grade = 0 }
end

local function isAdmin(sourceId, player)
    if IsPlayerAceAllowed(sourceId, Config.AdminAce) then return true end
    if not player then return false end
    local group = player.getGroup and player.getGroup() or 'user'
    for _, value in ipairs(Config.AdminGroups) do
        if group == value then return true end
    end
    return false
end

local function canCreate(sourceId, player, job, selectedJob)
    return isAdmin(sourceId, player)
end

local function permittedAccess(job, identifier, minGrade, rule)
    if not job then return false end
    if type(rule) ~= 'table' or rule.mode ~= 'list' then
        return (tonumber(job.grade) or -1) >= (tonumber(minGrade) or 99)
    end
    for _, grade in ipairs(rule.grades or {}) do
        if tonumber(grade) == tonumber(job.grade) then return true end
    end
    if type(identifier) == 'string' then
        for _, selected in ipairs(rule.identifiers or {}) do
            if selected == identifier then return true end
        end
    end
    return false
end

local function employeeAllowed(player, job, garage, category)
    if not player or not job or job.name ~= garage.job then return false end
    if not permittedAccess(job, player.identifier, garage.permissions.access,
        garage.permissions.access_rules) then return false end
    if category and not permittedAccess(job, player.identifier, category.access_grade,
        category.access_rules) then return false end
    return true
end

local function can(sourceId, player, job, garage, action)
    if not garage then return false end
    if isAdmin(sourceId, player) then return true end
    if not job or job.name ~= garage.job then return false end
    if action == 'access' then return employeeAllowed(player, job, garage) end
    if not employeeAllowed(player, job, garage) then return false end
    local need = tonumber((garage.permissions or {})[action]) or 999
    return (tonumber(job.grade) or -1) >= need
end

local function isManager(sourceId, player, job, garage)
    return can(sourceId, player, job, garage, 'manage')
end

local function validCoords(input)
    if type(input) ~= 'table' then return nil end
    local x, y, z, h = tonumber(input.x), tonumber(input.y), tonumber(input.z), tonumber(input.h) or 0
    if not x or not y or not z or not h then return nil end
    if x ~= x or y ~= y or z ~= z or h ~= h or math.abs(h) == math.huge then return nil end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then return nil end
    return { x = x, y = y, z = z, h = h % 360 }
end

local function validateInteraction(input)
    if input == nil then return { mode = 'marker', pedModel = Config.PedModelDefault, scenario = Config.PedScenarioDefault } end
    if type(input) ~= 'table' then return nil end
    local mode = input.mode
    if mode ~= 'marker' and mode ~= 'ped' then return nil end
    local model = tostring(input.pedModel or Config.PedModelDefault):lower()
    local allowed = false
    for _, ped in ipairs(Config.PedModelsAllowed) do if ped == model then allowed = true; break end end
    if not allowed then return nil end
    local scenario = tostring(input.scenario or Config.PedScenarioDefault)
    if #scenario > 64 or not scenario:match('^[%w_]+$') then return nil end
    return { mode = mode, pedModel = model, scenario = scenario }
end

local function coordsDistance(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

local function locationConflict(coords, excludeGarageId, isEntrance, isSpawn)
    local minimum = isEntrance and Config.MinGarageAccessDistance or Config.MinCrossGaragePointDistance
    for _, g in pairs(Garages) do
        if g.id ~= excludeGarageId then
            if coordsDistance(coords, g.entrance) < minimum then return g.name end
            for _, point in ipairs(g.storePoints or {}) do
                if coordsDistance(coords, point.coords) < minimum then return g.name end
            end
            for _, point in ipairs(g.spawnPoints or {}) do
                if coordsDistance(coords, point.coords) < Config.MinCrossGaragePointDistance then return g.name end
            end
        end
    end
    return nil
end

local function nearPlayer(sourceId, position, radius)
    if not position or not validCoords(position) then return false end
    local ped = GetPlayerPed(sourceId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(position.x, position.y, position.z)) <= radius
end

local function validateAccessRule(input)
    if input == nil then return { mode = 'all', grades = {}, identifiers = {} } end
    if type(input) ~= 'table' or (input.mode ~= 'all' and input.mode ~= 'list') then return nil end
    local result = { mode = input.mode, grades = {}, identifiers = {} }
    if input.mode == 'all' then return result end
    if type(input.grades) ~= 'table' or type(input.identifiers) ~= 'table' then return nil end
    local function denseArray(values, maximum)
        local count = 0
        for key in pairs(values) do
            if type(key) ~= 'number' or not integer(key, 1, maximum) then return false end
            count = count + 1
        end
        return count == #values and count <= maximum
    end
    if not denseArray(input.grades, 100) or not denseArray(input.identifiers, MAX_ALLOWED_STAFF) then return nil end
    local seenGrades, seenUsers = {}, {}
    for _, number in ipairs(input.grades) do
        local grade = tonumber(number)
        if not integer(grade, 0, 99) then return nil end
        if not seenGrades[grade] then
            seenGrades[grade] = true; result.grades[#result.grades + 1] = grade
        end
    end
    for _, value in ipairs(input.identifiers) do
        if type(value) ~= 'string' or #value < 3 or #value > 100
            or value:find('[%c]') or value:find('%s') then return nil end
        if not seenUsers[value] then
            seenUsers[value] = true; result.identifiers[#result.identifiers + 1] = value
        end
    end
    if #result.grades == 0 and #result.identifiers == 0 then return nil end
    return result
end

local function validatePermissions(input)
    if type(input) ~= 'table' then return nil end
    local result = {}
    for _, key in ipairs({ 'access', 'withdraw', 'store', 'manage', 'fleet_add', 'fleet_remove', 'categories', 'assign_category', 'rename' }) do
        local value = tonumber(input[key])
        if not integer(value, 0, 99) then return nil end
        result[key] = value
    end
    result.access_rules = validateAccessRule(input.access_rules)
    if not result.access_rules then return nil end
    return result
end

local function safeDecode(data)
    if type(data) ~= 'string' or data == '' then return {} end
    local ok, value = pcall(json.decode, data)
    return ok and type(value) == 'table' and value or {}
end

local function persistedRule(data)
    if data == nil or data == '' then return validateAccessRule(nil) end
    local decoded = type(data) == 'table' and data or safeDecode(data)
    return validateAccessRule(decoded) or { mode = 'list', grades = {}, identifiers = {} }
end

local function transaction(queries)
    if not MySQL.transaction.await(queries) then error('Transaction SQL annulée') end
end

local function encodeProperties(input, plate, model)
    if type(input) ~= 'table' then return nil end
    local visited, count = {}, 0
    local function valid(value, depth)
        local kind = type(value)
        if kind == 'number' then return value == value and math.abs(value) ~= math.huge end
        if kind == 'boolean' then return true end
        if kind == 'string' then return #value <= 25000 end
        if kind ~= 'table' or depth > 8 or visited[value] then return false end
        visited[value] = true
        for key, child in pairs(value) do
            count = count + 1
            -- okokGarage's documented ESX properties include wheel arrays indexed from 0.
            if count > 1500 or (type(key) ~= 'string' and not integer(key, 0, 1500))
                or (type(key) == 'string' and #key > 64) or not valid(child, depth + 1) then return false end
        end
        return true
    end
    if not valid(input, 0) then return nil end
    input.plate, input.model = plate, model
    local ok, encoded = pcall(json.encode, input)
    if not ok or type(encoded) ~= 'string' or #encoded > 25000 then return nil end
    return encoded
end

local function validPointKind(value)
    return (value == 'store' or value == 'spawn') and value or nil
end

local function categoryPermitted(sourceId, player, job, garage, category, action)
    if not category then return true end
    if isAdmin(sourceId, player) then return true end
    if not job or job.name ~= garage.job then return false end
    if not permittedAccess(job, player and player.identifier, category.access_grade,
        category.access_rules) then return false end
    if action == 'access' then return true end
    local key = action .. '_grade'
    return (tonumber(job.grade) or -1) >= (tonumber(category[key]) or 99)
end

local function categoryOf(vehicleId, garageId)
    local category = MySQL.single.await([[
        SELECT c.* FROM aegis_enterprise_vehicle_categories vc
        JOIN aegis_enterprise_categories c ON c.id = vc.category_id
        WHERE vc.vehicle_id = ? AND c.garage_id = ?
    ]], { vehicleId, garageId })
    if category then category.access_rules = persistedRule(category.access_rules) end
    return category
end

local function atAnyPoint(sourceId, points, radius)
    for _, point in ipairs(points or {}) do
        if nearPlayer(sourceId, point.coords, radius) then return true end
    end
    return false
end

local function nearAnyStore(sourceId, garage, radius)
    return atAnyPoint(sourceId, garage.storePoints, radius)
end

local function categoryGrades(input)
    if type(input) ~= 'table' then return nil end
    local output = {}
    for _, kind in ipairs({ 'access', 'withdraw', 'store' }) do
        local value = tonumber(input[kind])
        if not integer(value, 0, 99) then return nil end
        output[kind] = value
    end
    if (not input.access_rules or input.access_rules.mode ~= 'list')
        and (output.withdraw < output.access or output.store < output.access) then return nil end
    output.access_rules = validateAccessRule(input.access_rules)
    if not output.access_rules then return nil end
    return output
end

local function reloadGarages()
    local rows = MySQL.query.await('SELECT * FROM aegis_enterprise_garages ORDER BY id ASC')
    local points = MySQL.query.await('SELECT * FROM aegis_enterprise_garage_points ORDER BY id ASC')
    if type(rows) ~= 'table' or type(points) ~= 'table' then error('Chargement SQL des garages impossible') end
    local loaded = {}
    for _, row in ipairs(rows) do
        local perms = safeDecode(row.permissions)
        for k, default in pairs(Config.DefaultPermissions) do
            if perms[k] == nil then perms[k] = default end
        end
        perms.access_rules = persistedRule(perms.access_rules)
        local id, entrance, spawn = integer(row.id, 1), validCoords(safeDecode(row.entrance)), validCoords(safeDecode(row.spawn))
        local name = limitText(row.name, Config.MaxGarageName)
        if id and entrance and spawn and name and type(row.job) == 'string' and validatePermissions(perms) then
        loaded[id] = {
            id = tonumber(row.id), name = row.name, job = row.job,
            entrance = entrance, spawn = spawn,
            interaction = validateInteraction(safeDecode(row.interaction)) or validateInteraction(nil),
            permissions = perms, spawnPoints = {}, storePoints = {}
        }
        else print(('[aegis_garage] Garage %s ignoré : données invalides.'):format(tostring(row.id))) end
    end
    for _, p in ipairs(points) do
        local g, coords, id = loaded[tonumber(p.garage_id)], validCoords(safeDecode(p.coords)), integer(p.id, 1)
        local point = { id = id, label = limitText(p.label, Config.MaxPointLabel) or 'Point', coords = coords }
        if g and coords and id and p.kind == 'spawn' then g.spawnPoints[#g.spawnPoints + 1] = point
        elseif g and coords and id and p.kind == 'store' then g.storePoints[#g.storePoints + 1] = point end
    end
    Garages = loaded
end

local function broadcastRefresh()
    TriggerClientEvent('aegis_garage:reload', -1)
end

local function giveOrRemove(id, plate, shouldHave)
    if GetResourceState('wasabi_carlock') ~= 'started' then return end
    local ok, err = pcall(function()
        local has = exports['wasabi_carlock']:HasKey(id, plate)
        if shouldHave and not has then
            exports['wasabi_carlock']:GiveKey(id, plate)
        elseif not shouldHave and has then
            exports['wasabi_carlock']:RemoveKey(id, plate)
        end
    end)
    if not ok then print(('[aegis_garage] Erreur Wasabi Carlock (%s): %s'):format(plate, tostring(err))) end
end

local function categoryRuleFromRow(row)
    if not row or not row.category_id then return nil end
    return {
        access_grade = tonumber(row.access_grade) or 0,
        access_rules = persistedRule(row.category_rules)
    }
end

local function syncKeysForPlayer(id)
    if not Ready then return end
    if ActiveSync[id] then PendingSync[id] = true; return end
    if not ESX.GetPlayerFromId(id) then return end
    local syncPlayer = ESX.GetPlayerFromId(id)
    ActiveSync[id] = syncPlayer
    local ok, err = pcall(function()
        local rows = MySQL.query.await([[
            SELECT f.plate, f.stored, g.id AS garage_id, c.id AS category_id,
                   c.access_grade, c.access_rules AS category_rules
            FROM aegis_enterprise_fleet f
            JOIN aegis_enterprise_garages g ON g.id = f.garage_id
            LEFT JOIN aegis_enterprise_vehicle_categories vc ON vc.vehicle_id = f.id
            LEFT JOIN aegis_enterprise_categories c ON c.id = vc.category_id
        ]]) or {}
        local player, job = playerInfo(id)
        if not player or not job then return end
        for _, v in ipairs(rows) do
            if not samePlayer(id, syncPlayer) then break end
            player, job = playerInfo(id)
            local garage = Garages[tonumber(v.garage_id)]
            local eligible = garage and tonumber(v.stored) == 0
                and employeeAllowed(player, job, garage, categoryRuleFromRow(v)) or false
            giveOrRemove(id, v.plate, eligible)
        end
        local retired = MySQL.query.await('SELECT plate FROM aegis_enterprise_retired_keys') or {}
        for _, v in ipairs(retired) do
            if not samePlayer(id, syncPlayer) then break end
            giveOrRemove(id, v.plate, false)
        end
    end)
    if ActiveSync[id] == syncPlayer then ActiveSync[id] = nil end
    if not ok then print('[aegis_garage] Synchronisation des clés : ' .. tostring(err)) end
    if PendingSync[id] then
        PendingSync[id] = nil
        if samePlayer(id, syncPlayer) then SetTimeout(0, function() syncKeysForPlayer(id) end) end
    end
end

local function syncKeysForAllPlayers()
    for _, online in ipairs(GetPlayers()) do syncKeysForPlayer(tonumber(online)) end
end

local function distributePlateInternal(jobName, plate, outside)
    local v = MySQL.single.await([[
        SELECT f.stored, g.id AS garage_id, c.id AS category_id,
               c.access_grade, c.access_rules AS category_rules
        FROM aegis_enterprise_fleet f
        JOIN aegis_enterprise_garages g ON g.id = f.garage_id
        LEFT JOIN aegis_enterprise_vehicle_categories vc ON vc.vehicle_id = f.id
        LEFT JOIN aegis_enterprise_categories c ON c.id = vc.category_id
        WHERE f.plate = ? LIMIT 1
    ]], { plate })
    for _, online in ipairs(GetPlayers()) do
        local id = tonumber(online)
        if ActiveSync[id] then PendingSync[id] = true end
        local player, job = playerInfo(id)
        local g = v and Garages[tonumber(v.garage_id)] or nil
        local allowed = outside and v and tonumber(v.stored) == 0 and g
            and employeeAllowed(player, job, g, categoryRuleFromRow(v)) or false
        giveOrRemove(id, plate, allowed)
    end
end

local function distributePlate(jobName, plate, outside)
    local ok, err = pcall(distributePlateInternal, jobName, plate, outside)
    if not ok then print('[aegis_garage] Distribution des clés différée : ' .. tostring(err)) end
end

local function companyEmployees(jobName)
    local ok, rows = pcall(function() return MySQL.query.await('SELECT identifier, firstname, lastname FROM users WHERE job = ? ORDER BY identifier ASC LIMIT 500', { jobName }) end)
    if not ok or not rows then rows = MySQL.query.await('SELECT identifier FROM users WHERE job = ? ORDER BY identifier ASC LIMIT 500', { jobName }) or {} end
    local employees, known = {}, {}
    for _, row in ipairs(rows) do
        local id = row.identifier
        if type(id) == 'string' and id ~= '' and not known[id] then
            known[id] = true
            local fullname = trim((row.firstname or '') .. ' ' .. (row.lastname or ''))
            employees[#employees + 1] = { identifier = id, name = fullname ~= '' and fullname or id, online = false }
        end
    end
    for _, source in ipairs(GetPlayers()) do
        local player, job = playerInfo(tonumber(source))
        if player and job and job.name == jobName and player.identifier then
            if not known[player.identifier] then
                known[player.identifier] = true
                employees[#employees + 1] = {
                    identifier = player.identifier, name = GetPlayerName(tonumber(source)) or player.identifier, online = true
                }
            else
                for _, employee in ipairs(employees) do
                    if employee.identifier == player.identifier then employee.online = true; break end
                end
            end
        end
    end
    return employees, known
end

local function validateCompanyAccess(jobName, rule, employees)
    if not rule or rule.mode ~= 'list' then return true end
    if #rule.identifiers == 0 then return true end
    local known = employees
    if not known then local ignored; ignored, known = companyEmployees(jobName) end
    for _, identifier in ipairs(rule.identifiers) do
        if not known[identifier] then return false end
    end
    return true
end

local function validVehicleType(value)
    local types = { automobile = true, bike = true, boat = true, heli = true,
        plane = true, trailer = true, train = true, submarine = true }
    return types[value] and value or nil
end

local function modelHash(model)
    return tonumber(model) or GetHashKey(model)
end

local function sameModel(a, b)
    local aa, bb = tonumber(a), tonumber(b)
    return aa ~= nil and bb ~= nil and (aa % 4294967296) == (bb % 4294967296)
end

local function fleetRow(id, garageId)
    if not integer(id, 1) or not integer(garageId, 1) then return nil end
    return MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE id = ? AND garage_id = ?', { id, garageId })
end

local function validModel(input)
    if type(input) ~= 'string' then return nil end
    local model = trim(input):lower()
    if #model < 2 or #model > 60 or not model:match('^[%w_]+$') then return nil end
    return model
end

local function nearGarageInteraction(sourceId, garage)
    return nearPlayer(sourceId, garage.entrance, Config.GarageOpenDistance)
        or atAnyPoint(sourceId, garage.storePoints, Config.GarageOpenDistance)
end

local function sessionValid(sourceId, player, job, garage, uiSession)
    local session = GarageSessions[sourceId]
    return session and session.id == garage.id and session.player == player
        and session.identifier == player.identifier and session.job == job.name
        and session.expires > os.time() and session.bucket == GetPlayerRoutingBucket(sourceId)
        and (uiSession == nil or session.uiSession == uiSession)
        and (nearPlayer(sourceId, garage.entrance, Config.ManagementDistance)
            or nearAnyStore(sourceId, garage, Config.ManagementDistance))
end

local function stillAuthorized(sourceId, originalPlayer, garage, action)
    local player, job = playerInfo(sourceId)
    if player ~= originalPlayer or not can(sourceId, player, job, garage, action) then return false end
    return isAdmin(sourceId, player) or sessionValid(sourceId, player, job, garage)
end

local function locationBootstrap(sourceId, player, job)
    local list = {}
    for _, g in pairs(Garages) do
        if can(sourceId, player, job, g, 'access') or isManager(sourceId, player, job, g) then
            list[#list + 1] = {
                id = g.id, name = g.name, entrance = g.entrance, interaction = g.interaction,
                storePoints = g.storePoints
            }
        end
    end
    table.sort(list, function(a,b) return a.id < b.id end)
    return success({ garages = list })
end

local function fleetBootstrap(sourceId, player, job, scope)
    scope = scope or {}
    local selected = scope.garageId ~= nil and integer(scope.garageId, 1) or nil
    if scope.garageId ~= nil and not selected then return fail('Garage invalide.') end
    local epoch = scope.uiSession ~= nil and integer(scope.uiSession, 1, 2147483647) or nil
    if scope.uiSession ~= nil and not epoch then return fail('Session invalide.') end
    local last = SessionEpochs[sourceId]
    if epoch and last and (epoch < last.value or (epoch == last.value and last.closed)) then return fail('Cette ouverture a été annulée.') end
    if epoch then SessionEpochs[sourceId] = { value = epoch } end
    local staff = isAdmin(sourceId, player)
    if not selected and not staff then return fail('Ouvre un garage depuis son propre point d’accès.') end
    local active = selected and sessionValid(sourceId, player, job, Garages[selected] or {}, epoch)
    if selected and (not Garages[selected] or (not staff and not active and not nearGarageInteraction(sourceId, Garages[selected]))) then
        return fail('Rapproche-toi du point d’accès de ce garage.')
    end
    if selected and not can(sourceId, player, job, Garages[selected], 'access') then return fail('Accès au garage refusé.') end
    local bucket = GetPlayerRoutingBucket(sourceId)
    local allowed, result, ids = {}, {}, {}
    for _, garage in pairs(Garages) do
        if (not selected or garage.id == selected)
            and (can(sourceId, player, job, garage, 'access') or isManager(sourceId, player, job, garage)) then
            result[#result + 1] = {
                id = garage.id, name = garage.name, job = garage.job,
                entrance = garage.entrance, spawn = garage.spawn, interaction = garage.interaction,
                spawnPoints = garage.spawnPoints, storePoints = garage.storePoints,
                permissions = isManager(sourceId, player, job, garage) and garage.permissions
                    or { access = garage.permissions.access, access_rules = { mode = garage.permissions.access_rules.mode } },
                categories = {},
                abilities = {
                    withdraw = can(sourceId, player, job, garage, 'withdraw'),
                    store = can(sourceId, player, job, garage, 'store'),
                    manage = isManager(sourceId, player, job, garage),
                    structure = staff,
                    fleet_add = can(sourceId, player, job, garage, 'fleet_add'),
                    fleet_remove = can(sourceId, player, job, garage, 'fleet_remove'),
                    categories = can(sourceId, player, job, garage, 'categories'),
                    assign_category = can(sourceId, player, job, garage, 'assign_category'),
                    rename = can(sourceId, player, job, garage, 'rename')
                }, vehicles = {}
            }
            allowed[garage.id] = result[#result]
            ids[#ids + 1] = garage.id
        end
    end
    if #ids > 0 then
        local marks, values = {}, {}
        for _, id in ipairs(ids) do marks[#marks + 1] = '?'; values[#values + 1] = id end
        local inList = table.concat(marks, ',')
        local categories = MySQL.query.await('SELECT * FROM aegis_enterprise_categories WHERE garage_id IN (' .. inList .. ') ORDER BY name ASC', values) or {}
        local categoryMap = {}
        for _, c in ipairs(categories) do
            c.access_rules = persistedRule(c.access_rules)
            categoryMap[tonumber(c.id)] = c
            local entry = allowed[tonumber(c.garage_id)]
            if entry and (categoryPermitted(sourceId, player, job, Garages[tonumber(c.garage_id)], c, 'access') or entry.abilities.manage or entry.abilities.categories) then
                entry.categories[#entry.categories + 1] = {
                    id = c.id, name = c.name, access_grade = tonumber(c.access_grade),
                    withdraw_grade = tonumber(c.withdraw_grade), store_grade = tonumber(c.store_grade),
                    access_rules = entry.abilities.categories and c.access_rules or { mode = c.access_rules.mode, grades = {}, identifiers = {} }
                }
            end
        end
        local query = [[SELECT f.id, f.garage_id, f.plate, f.model, f.label, f.vehicle_type, f.stored, vc.category_id
            FROM aegis_enterprise_fleet f LEFT JOIN aegis_enterprise_vehicle_categories vc ON vc.vehicle_id = f.id
            WHERE f.garage_id IN (]] .. inList .. ') ORDER BY f.id DESC'
        local vehicles = MySQL.query.await(query, values) or {}
        for _, v in ipairs(vehicles) do
            local entry = allowed[tonumber(v.garage_id)]
            local category = categoryMap[tonumber(v.category_id)]
            if entry and (not category or categoryPermitted(sourceId, player, job, Garages[tonumber(v.garage_id)], category, 'access') or entry.abilities.manage) then
                entry.vehicles[#entry.vehicles + 1] = {
                    id = v.id, plate = v.plate, model = v.model,
                    label = v.label, vehicle_type = v.vehicle_type,
                    stored = tonumber(v.stored) == 1, category_id = category and tonumber(category.id) or nil,
                    canWithdraw = entry.abilities.withdraw and categoryPermitted(sourceId, player, job, Garages[tonumber(v.garage_id)], category, 'withdraw'),
                    canStore = entry.abilities.store and categoryPermitted(sourceId, player, job, Garages[tonumber(v.garage_id)], category, 'store')
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.name:lower() < b.name:lower() end)
    local latest = SessionEpochs[sourceId]
    if not samePlayer(sourceId, player) or bucket ~= GetPlayerRoutingBucket(sourceId)
        or (epoch and (not latest or latest.value ~= epoch or latest.closed)) then return fail('Cette ouverture a été annulée.') end
    if selected and not staff then
        local currentPlayer, currentJob = playerInfo(sourceId)
        if not can(sourceId, currentPlayer, currentJob, Garages[selected], 'access')
            or (not active and not nearGarageInteraction(sourceId, Garages[selected])) then return fail('Accès au garage expiré.') end
        GarageSessions[sourceId] = { id = selected, player = player, identifier = player.identifier,
            job = currentJob.name, bucket = bucket, uiSession = epoch,
            expires = os.time() + (integer(Config.SessionDurationSeconds, 30, 86400) or 1800) }
    end
    return success({
        garages = result,
        isAdmin = isAdmin(sourceId, player),
        canCreate = staff,
        singleGarage = selected ~= nil,
        staffView = staff and selected == nil,
        playerJob = job.name,
        grade = tonumber(job.grade) or 0,
        bridge = { enabled = EnterpriseGarageBridge.enabled(),
            allowEmployeeOwned = EnterpriseGarageBridge.enabled() and Config.OkokGarageBridge.AllowEmployeeOwnedVehicles == true },
        playerLabel = GetPlayerName(sourceId) or 'Employé'
    })
end

local function jobExists(job)
    return MySQL.scalar.await('SELECT 1 FROM jobs WHERE name = ? LIMIT 1', { job }) ~= nil
end

local function societyOwned(jobName, plate)
    local rows = MySQL.query.await('SELECT owner, vehicle FROM owned_vehicles WHERE UPPER(TRIM(plate)) = ?', { plate })
    if type(rows) == 'table' and #rows == 0 then
        local archived = EnterpriseGarageBridge.owned(plate)
        if archived then rows = { archived } end
    end
    if type(rows) ~= 'table' or #rows ~= 1 then return false end
    local row = rows[1]
    for _, format in ipairs(Config.SocietyOwnerFormats) do
        if row.owner == format:format(jobName) then return true, row end
    end
    return false
end

local function ownedStoredQuery(jobName, plate, stored)
    if Config.SyncOwnedVehicleStored == false then return nil end
    if MySQL.scalar.await('SELECT 1 FROM aegis_enterprise_vehicle_bridges WHERE plate = ? LIMIT 1', { plate }) then return nil end
    local marks, values = {}, { stored, plate }
    for _, format in ipairs(Config.SocietyOwnerFormats) do
        marks[#marks + 1] = '?'; values[#values + 1] = format:format(jobName)
    end
    if #marks == 0 then error('SocietyOwnerFormats vide') end
    return { query = 'UPDATE owned_vehicles SET `stored` = ? WHERE UPPER(TRIM(plate)) = ? AND owner IN ('
        .. table.concat(marks, ',') .. ')', values = values }
end

local function commitFleet(queries, garage, plate, stored)
    local owned = ownedStoredQuery(garage.job, plate, stored)
    if owned then queries[#queries + 1] = owned end
    transaction(queries)
end

local function matchingEntities(plate, model)
    local found = {}
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) and validPlate(GetVehicleNumberPlateText(entity)) == plate
            and (not model or sameModel(GetEntityModel(entity), model)) then found[#found + 1] = entity end
    end
    return found
end

local function deleteVehicle(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return true end
    DeleteEntity(entity)
    for _ = 1, 20 do
        if not DoesEntityExist(entity) then return true end
        Wait(50)
    end
    return not DoesEntityExist(entity)
end

local function entityMatches(entity, vehicle, bucket)
    return entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
        and validPlate(GetVehicleNumberPlateText(entity)) == validPlate(vehicle.plate)
        and sameModel(GetEntityModel(entity), modelHash(vehicle.model))
        and (bucket == nil or GetEntityRoutingBucket(entity) == bucket)
end

local function actionCreate(sourceId, player, job, data)
    local name = limitText(data.name, Config.MaxGarageName)
    local selectedJob = validModel(data.job)
    local entrance, spawn = validCoords(data.entrance), validCoords(data.spawn)
    local perms = validatePermissions(data.permissions)
    local interaction = validateInteraction(data.interaction)
    if not name or not selectedJob or not entrance or not spawn or not perms or not interaction then return fail('Informations du garage invalides.') end
    if not canCreate(sourceId, player, job, selectedJob) then return fail('Création réservée au staff serveur.') end
    local conflict = locationConflict(entrance, nil, true) or locationConflict(spawn, nil, false, true)
    if conflict then return fail('Un emplacement de ce garage est déjà attribué à : ' .. conflict) end
    if not validateCompanyAccess(selectedJob, perms.access_rules) then return fail('Un des employés autorisés ne fait pas partie de cette entreprise.') end
    if not jobExists(selectedJob) then return fail('Ce métier n’existe pas dans ESX.') end
    if coordsDistance(entrance, spawn) > Config.MaxPointDistance then return fail('La sortie est trop éloignée de l’entrée du garage.') end
    if not nearPlayer(sourceId, entrance, 12.0) and not nearPlayer(sourceId, spawn, 12.0) then
        return fail('Rejoins un des emplacements capturés pour créer le garage.')
    end
    if not samePlayer(sourceId, player) or not isAdmin(sourceId, player) then return fail('Autorisation expirée.') end
    transaction({
        { query = [[INSERT INTO aegis_enterprise_garages (name, job, entrance, spawn, permissions, interaction, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?)]], values = { name, selectedJob, json.encode(entrance), json.encode(spawn), json.encode(perms), json.encode(interaction), player.identifier or 'inconnu' } },
        -- LAST_INSERT_ID doit rester sur la même connexion.
        { query = [[INSERT INTO aegis_enterprise_garage_points (garage_id, kind, label, coords)
            VALUES (LAST_INSERT_ID(), 'store', 'Rangement principal', ?),
                   (LAST_INSERT_ID(), 'spawn', 'Sortie principale', ?)]], values = { json.encode(entrance), json.encode(spawn) } }
    })
    local id = MySQL.scalar.await('SELECT id FROM aegis_enterprise_garages WHERE entrance = ? AND created_by = ? ORDER BY id DESC LIMIT 1',
        { json.encode(entrance), player.identifier or 'inconnu' })
    reloadGarages(); broadcastRefresh()
    return success({ id = id, message = 'Garage créé avec succès.' })
end

local function actionUpdate(sourceId, player, job, data)
    local garage = Garages[tonumber(data.id)]
    if not garage or not isAdmin(sourceId, player) then return fail('Configuration structurelle réservée au staff serveur.') end
    local name = limitText(data.name, Config.MaxGarageName)
    local selectedJob = validModel(data.job)
    local entrance, spawn = validCoords(data.entrance), validCoords(data.spawn)
    local perms = validatePermissions(data.permissions)
    local interaction = validateInteraction(data.interaction)
    if not name or not selectedJob or not entrance or not spawn or not perms or not interaction then return fail('Informations invalides.') end
    local conflict = locationConflict(entrance, garage.id, true) or locationConflict(spawn, garage.id, false, true)
    if conflict then return fail('Emplacement déjà utilisé par un autre garage : ' .. conflict) end
    if not isAdmin(sourceId, player) and selectedJob ~= garage.job then return fail('Changer le métier est réservé aux administrateurs.') end
    if not validateCompanyAccess(selectedJob, perms.access_rules) then return fail('La liste d’accès comprend une personne extérieure à l’entreprise.') end
    if selectedJob ~= garage.job then
        if not jobExists(selectedJob) then return fail('Métier ESX introuvable.') end
        local out = MySQL.scalar.await('SELECT 1 FROM aegis_enterprise_fleet WHERE garage_id = ? AND stored = 0 LIMIT 1', { garage.id })
        if out then return fail('Range ou récupère les véhicules sortis avant de changer le métier.') end
        local plates = MySQL.query.await('SELECT plate FROM aegis_enterprise_fleet WHERE garage_id = ?', { garage.id }) or {}
        for _, vehicle in ipairs(plates) do
            if not societyOwned(selectedJob, vehicle.plate) then
                return fail('Changement de métier refusé : un véhicule de la flotte n’appartient pas à la nouvelle société.')
            end
        end
    end
    if coordsDistance(entrance, spawn) > Config.MaxPointDistance then return fail('La sortie est trop éloignée de l’entrée du garage.') end
    local entranceChanged = coordsDistance(entrance, garage.entrance) > 0.001
    local spawnChanged = coordsDistance(spawn, garage.spawn) > 0.001
    if (entranceChanged or spawnChanged)
        and not ((entranceChanged and nearPlayer(sourceId, entrance, 12.0))
            or (spawnChanged and nearPlayer(sourceId, spawn, 12.0))) then
        return fail('Rejoins un des nouveaux emplacements capturés pour enregistrer le garage.')
    end
    if not samePlayer(sourceId, player) or not isAdmin(sourceId, player) then return fail('Autorisation expirée.') end
    local queries = { { query = [[UPDATE aegis_enterprise_garages SET name = ?, job = ?, entrance = ?, spawn = ?, permissions = ?, interaction = ? WHERE id = ?]],
        values = { name, selectedJob, json.encode(entrance), json.encode(spawn), json.encode(perms), json.encode(interaction), garage.id } } }
    for _, entry in ipairs({ { kind = 'store', old = garage.entrance, new = entrance }, { kind = 'spawn', old = garage.spawn, new = spawn } }) do
        for _, point in ipairs(entry.kind == 'store' and garage.storePoints or garage.spawnPoints) do
            if coordsDistance(point.coords, entry.old) < 0.01 then
                queries[#queries + 1] = { query = 'UPDATE aegis_enterprise_garage_points SET coords = ? WHERE id = ? AND garage_id = ?',
                    values = { json.encode(entry.new), point.id, garage.id } }
            end
        end
    end
    transaction(queries)
    reloadGarages(); broadcastRefresh()
    syncKeysForAllPlayers()
    return success({ message = 'Configuration enregistrée.' })
end

local function actionUpdatePermissions(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not isManager(sourceId, player, job, garage) then return fail('Droit de gestion des permissions requis.') end
    local perms = validatePermissions(data.permissions)
    if not perms or not validateCompanyAccess(garage.job, perms.access_rules) then return fail('Permissions invalides ou employés hors entreprise.') end
    if not stillAuthorized(sourceId, player, garage, 'manage') then return fail('Autorisation expirée.') end
    MySQL.update.await('UPDATE aegis_enterprise_garages SET permissions = ? WHERE id = ?', { json.encode(perms), garage.id })
    reloadGarages(); broadcastRefresh(); syncKeysForAllPlayers()
    return success({ message = 'Permissions enregistrées, clés recalculées.' })
end

local function actionDelete(sourceId, player, job, data)
    local garage = Garages[tonumber(data.id)]
    if not garage or not isAdmin(sourceId, player) then return fail('Suppression réservée au staff serveur.') end
    local out = MySQL.scalar.await('SELECT 1 FROM aegis_enterprise_fleet WHERE garage_id = ? AND stored = 0 LIMIT 1', { garage.id })
    if out then return fail('Tous les véhicules doivent être rangés avant suppression.') end
    local vehicles = MySQL.query.await('SELECT plate, props FROM aegis_enterprise_fleet WHERE garage_id = ?', { garage.id }) or {}
    if not samePlayer(sourceId, player) or not isAdmin(sourceId, player) then return fail('Autorisation expirée.') end
    local queries = {}
    for _, vehicle in ipairs(vehicles) do
        local restore, restoreError = EnterpriseGarageBridge.releaseQueries(vehicle.plate, vehicle.props)
        if not restore then return fail(restoreError) end
        for _, query in ipairs(restore) do queries[#queries + 1] = query end
    end
    queries[#queries + 1] =
        { query = 'INSERT IGNORE INTO aegis_enterprise_retired_keys (plate) SELECT plate FROM aegis_enterprise_fleet WHERE garage_id = ?', values = { garage.id } }
    queries[#queries + 1] = { query = 'DELETE FROM aegis_enterprise_garages WHERE id = ?', values = { garage.id } }
    if not samePlayer(sourceId, player) or not isAdmin(sourceId, player) then return fail('Autorisation expirée.') end
    transaction(queries)
    reloadGarages(); broadcastRefresh()
    for _, item in ipairs(vehicles) do distributePlate(garage.job, item.plate, false) end
    return success({ message = 'Garage et flotte supprimés.' })
end

local function actionRegister(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'fleet_add') then return fail('Ton grade ne permet pas l’ajout de véhicules.') end
    if not nearPlayer(sourceId, garage.entrance, 90.0) and not nearAnyStore(sourceId, garage, 90.0) then return fail('Rejoins le garage pour importer un véhicule.') end
    local netId = integer(data.netId, 1, 65535)
    if not netId then return fail('Véhicule introuvable.') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return fail('Véhicule invalide.') end
    local ped = GetPlayerPed(sourceId)
    local bucket = GetPlayerRoutingBucket(sourceId)
    if not ped or ped == 0 or GetEntityRoutingBucket(entity) ~= bucket then return fail('Véhicule hors de ton instance.') end
    if GetPedInVehicleSeat(entity, -1) ~= ped then return fail('Monte au volant du véhicule à importer.') end
    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > Config.RegisterDistance then return fail('Rapproche-toi du véhicule.') end
    local plate = validPlate(GetVehicleNumberPlateText(entity))
    local props = data.props
    local label = limitText(data.label, Config.MaxVehicleLabel)
    local vehicleType = validVehicleType(GetVehicleType(entity))
    if not plate or not label or not vehicleType then return fail('Véhicule ou nom invalide.') end
    if type(props) ~= 'table' or not sameModel(props.model, GetEntityModel(entity)) then return fail('Modèle non conforme au véhicule observé.') end
    if MySQL.scalar.await('SELECT 1 FROM aegis_enterprise_fleet WHERE plate = ?', { plate }) then return fail('Cette plaque est déjà associée à une flotte.') end
    local ownershipRows = MySQL.query.await('SELECT * FROM owned_vehicles WHERE UPPER(TRIM(plate)) = ?', { plate }) or {}
    local ownership = #ownershipRows == 1 and ownershipRows[1] or nil
    if not ownership or not EnterpriseGarageBridge.canImport(player, garage.job, ownership) then
        return fail('Ce véhicule doit appartenir à la société ou à toi dans owned_vehicles.')
    end
    local registeredModel = safeDecode(ownership.vehicle).model
    if not sameModel(registeredModel, GetEntityModel(entity)) then return fail('Le modèle ne correspond pas à owned_vehicles.') end
    if #matchingEntities(plate) ~= 1 then return fail('Une autre entité utilise déjà cette plaque. Corrige le doublon avant import.') end
    local serialized = encodeProperties(props, plate, GetEntityModel(entity))
    if not serialized then return fail('Personnalisation du véhicule invalide ou trop volumineuse.') end
    local total = MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_fleet WHERE garage_id = ?', { garage.id }) or 0
    if tonumber(total) >= Config.MaxFleetPerGarage then return fail('Capacité maximale de la flotte atteinte.') end
    local categoryId = integer(data.categoryId or 0, 0)
    if not categoryId then return fail('Catégorie invalide.') end
    if categoryId > 0 then
        if not can(sourceId, player, job, garage, 'assign_category') then return fail('Grade insuffisant pour classer un véhicule.') end
        if not MySQL.scalar.await('SELECT id FROM aegis_enterprise_categories WHERE id = ? AND garage_id = ?', { categoryId, garage.id }) then
            return fail('Catégorie invalide pour ce garage.')
        end
    end
    local model = GetEntityModel(entity)
    if not stillAuthorized(sourceId, player, garage, 'fleet_add') or GetPlayerRoutingBucket(sourceId) ~= bucket
        or not entityMatches(entity, { plate = plate, model = model }, bucket) or GetPedInVehicleSeat(entity, -1) ~= ped then return fail('Le véhicule ou ton autorisation a changé.') end
    local bridged = EnterpriseGarageBridge.enabled()
    local queries = {}
    if bridged then queries[#queries + 1] = EnterpriseGarageBridge.captureQuery(plate, ownership) end
    local insertValues = { garage.id, plate, tostring(model), vehicleType, label, serialized, netId }
    if bridged then insertValues[#insertValues + 1] = plate end
    queries[#queries + 1] = { query = [[INSERT INTO aegis_enterprise_fleet (garage_id, plate, model, vehicle_type, label, props, stored, net_id)
        ]] .. (bridged and [[SELECT ?, ?, ?, ?, ?, ?, 0, ? FROM aegis_enterprise_vehicle_bridges WHERE plate = ?]]
            or [[VALUES (?, ?, ?, ?, ?, ?, 0, ?)]]),
        values = insertValues }
    if categoryId > 0 then
        queries[#queries + 1] = { query = 'INSERT INTO aegis_enterprise_vehicle_categories (vehicle_id, category_id) SELECT id, ? FROM aegis_enterprise_fleet WHERE plate = ?', values = { categoryId, plate } }
    end
    if bridged then queries[#queries + 1] = EnterpriseGarageBridge.reserveQuery(plate) end
    queries[#queries + 1] = { query = 'DELETE FROM aegis_enterprise_retired_keys WHERE plate = ?', values = { plate } }
    if bridged then transaction(queries) else commitFleet(queries, garage, plate, 0) end
    local id = MySQL.scalar.await('SELECT id FROM aegis_enterprise_fleet WHERE plate = ?', { plate })
    if not id then return fail('La propriété du véhicule a changé pendant le transfert. Réessaie.') end
    if bridged then EnterpriseGarageBridge.revokeSourceKeys(plate) end
    FleetEntities[id] = entity
    if not entityMatches(entity, { plate = plate, model = model }, bucket) then return fail('Le véhicule a changé pendant l’import. Utilise la récupération si nécessaire.') end
    if not deleteVehicle(entity) then
        distributePlate(garage.job, plate, true); broadcastRefresh()
        return success({ id = id, message = 'Véhicule importé en sortie : suppression physique refusée, range-le normalement.' })
    end
    commitFleet({ { query = 'UPDATE aegis_enterprise_fleet SET stored = 1, net_id = 0 WHERE id = ?', values = { id } } }, garage, plate, 1)
    FleetEntities[id] = nil
    distributePlate(garage.job, plate, false)
    broadcastRefresh()
    return success({ id = id, message = bridged and 'Véhicule transféré depuis le garage externe et rangé dans la flotte.' or 'Véhicule importé et rangé dans la flotte.' })
end

local function spawnIsBlocked(coords, bucket)
    local target = vector3(coords.x, coords.y, coords.z)
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) and GetEntityRoutingBucket(entity) == bucket then
            if #(GetEntityCoords(entity) - target) <= Config.SpawnCheckRadius then return true end
        end
    end
    return false
end

local function withdrawInternal(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'withdraw') then return fail('Tu n’as pas le grade pour sortir ce véhicule.') end
    if not nearPlayer(sourceId, garage.entrance, 16.0) then return fail('Rejoins le point d’accès au garage.') end
    local vehicle = fleetRow(tonumber(data.vehicleId), garage.id)
    if not vehicle then return fail('Véhicule introuvable.') end
    if tonumber(vehicle.stored) ~= 1 then return fail('Ce véhicule est déjà sorti.') end
    local category = categoryOf(vehicle.id, garage.id)
    if not categoryPermitted(sourceId, player, job, garage, category, 'withdraw') then return fail('Ton grade ne permet pas de sortir un véhicule de cette catégorie.') end
    local bucket = GetPlayerRoutingBucket(sourceId)
    local chosen
    local pointId = integer(data.pointId or 0, 0)
    if not pointId then return fail('Point de sortie invalide.') end
    if pointId > 0 then
        for _, point in ipairs(garage.spawnPoints) do
            if point.id == pointId then chosen = point; break end
        end
        if not chosen then return fail('Point de sortie inconnu.') end
        if spawnIsBlocked(chosen.coords, bucket) then return fail('Ce point de sortie est occupé.') end
    else
        for _, point in ipairs(garage.spawnPoints) do
            if not spawnIsBlocked(point.coords, bucket) then chosen = point; break end
        end
        if not chosen then return fail('Tous les points de sortie sont occupés.') end
    end
    local owned, ownership = societyOwned(garage.job, vehicle.plate)
    if not owned then
        ownership = EnterpriseGarageBridge.owned(vehicle.plate)
        owned = ownership ~= nil
    end
    if not owned or not sameModel(safeDecode(ownership.vehicle).model, modelHash(vehicle.model)) then
        return fail('La propriété enregistrée de ce véhicule ne correspond plus à la flotte.')
    end
    if #matchingEntities(vehicle.plate) > 0 then return fail('Cette plaque existe déjà en jeu. Range le véhicule présent.') end
    if not stillAuthorized(sourceId, player, garage, 'withdraw') or GetPlayerRoutingBucket(sourceId) ~= bucket
        or not nearPlayer(sourceId, garage.entrance, 16.0) then return fail('Accès au garage expiré.') end
    local changed = MySQL.update.await([[
        UPDATE aegis_enterprise_fleet SET stored = 0, net_id = 0 WHERE id = ? AND stored = 1
    ]], { vehicle.id })
    if changed ~= 1 then return fail('Le véhicule vient d’être sorti par un autre employé.') end
    local hash = modelHash(vehicle.model)
    local p = chosen.coords
    local entity, netId
    local ok, err = pcall(function()
        if not stillAuthorized(sourceId, player, garage, 'withdraw') or GetPlayerRoutingBucket(sourceId) ~= bucket
            or not nearPlayer(sourceId, garage.entrance, 16.0) then error('Accès au garage expiré pendant la réservation') end
        if spawnIsBlocked(chosen.coords, bucket) then error('Point de sortie occupé pendant la réservation') end
        entity = CreateVehicleServerSetter(hash, validVehicleType(vehicle.vehicle_type) or 'automobile', p.x, p.y, p.z, p.h)
        if not entity or entity == 0 or not DoesEntityExist(entity) then error('Création du véhicule refusée') end
        FleetEntities[tonumber(vehicle.id)] = entity
        SetEntityOrphanMode(entity, 2)
        SetEntityRoutingBucket(entity, bucket)
        SetVehicleNumberPlateText(entity, vehicle.plate)
        netId = integer(NetworkGetNetworkIdFromEntity(entity), 1, 65535)
        if not netId then error('Identifiant réseau du véhicule invalide') end
        local props = safeDecode(vehicle.props)
        props.plate, props.model = vehicle.plate, hash
        Entity(entity).state:set('aegisFleetInit', { plate = vehicle.plate, props = props }, true)
        Entity(entity).state:set('aegisFleetId', tonumber(vehicle.id), true)
        if not stillAuthorized(sourceId, player, garage, 'withdraw') or GetPlayerRoutingBucket(sourceId) ~= bucket then
            error('Autorisation expirée ou instance modifiée')
        end
        commitFleet({ { query = 'UPDATE aegis_enterprise_fleet SET net_id = ? WHERE id = ? AND stored = 0', values = { netId, vehicle.id } } }, garage, vehicle.plate, 0)
    end)
    if not ok then
        print('[aegis_garage] Sortie annulée : ' .. tostring(err))
        if deleteVehicle(entity) then
            FleetEntities[tonumber(vehicle.id)] = nil
            commitFleet({ { query = 'UPDATE aegis_enterprise_fleet SET stored = 1, net_id = 0 WHERE id = ? AND stored = 0', values = { vehicle.id } } }, garage, vehicle.plate, 1)
        elseif netId then
            MySQL.update.await('UPDATE aegis_enterprise_fleet SET net_id = ? WHERE id = ? AND stored = 0', { netId, vehicle.id })
        end
        return fail('Sortie interrompue. Vérifie le véhicule présent ou utilise la récupération.')
    end
    distributePlate(garage.job, vehicle.plate, true)
    if samePlayer(sourceId, player) and GetPlayerRoutingBucket(sourceId) == bucket then
        TriggerClientEvent('aegis_garage:vehicleSpawned', sourceId, netId)
    end
    broadcastRefresh()
    return success({ message = ('Véhicule sorti via %s : clés partagées.'):format(chosen.label) })
end

local function actionWithdraw(sourceId, player, job, data)
    local garageId = tonumber(data.garageId)
    if not garageId or not Garages[garageId] then return fail('Garage introuvable.') end
    if SpawnLocks[garageId] then return fail('Une sortie est en cours sur ce garage, réessaie.') end
    SpawnLocks[garageId] = true
    local ok, result = pcall(withdrawInternal, sourceId, player, job, data)
    SpawnLocks[garageId] = nil
    if not ok then error(result) end
    return result
end

local function actionStore(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'store') then return fail('Rangement non autorisé.') end
    local netId = integer(data.netId, 1, 65535)
    if not netId then return fail('Monte au volant du véhicule à ranger.') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(sourceId)
    local bucket = GetPlayerRoutingBucket(sourceId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return fail('Véhicule introuvable.') end
    if GetEntityRoutingBucket(entity) ~= bucket then return fail('Véhicule hors de ton instance.') end
    if GetPedInVehicleSeat(entity, -1) ~= ped then return fail('Tu dois être au volant.') end
    local vehiclePosition = GetEntityCoords(entity)
    local inStoreZone = false
    for _, point in ipairs(garage.storePoints) do
        if #(vehiclePosition - vector3(point.coords.x, point.coords.y, point.coords.z)) <= Config.StoreDistance then
            inStoreZone = true; break
        end
    end
    if not inStoreZone then return fail('Rejoins un point de rangement configuré pour ce garage.') end
    local plate = validPlate(GetVehicleNumberPlateText(entity))
    if not plate then return fail('Plaque invalide.') end
    local vehicle = MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE garage_id = ? AND plate = ?', { garage.id, plate })
    if not vehicle and data.vehicleId == nil and EnterpriseGarageBridge.enabled()
        and Config.OkokGarageBridge.AutoImportOnStore == true then
        if not stillAuthorized(sourceId, player, garage, 'store') then return fail('Autorisation de rangement expirée.') end
        return actionRegister(sourceId, player, job, {
            garageId = garage.id, netId = netId, props = data.props,
            label = limitText(data.label, Config.MaxVehicleLabel) or ('Véhicule ' .. plate), categoryId = 0
        })
    end
    if not vehicle or tonumber(vehicle.stored) ~= 0 then return fail('Ce véhicule ne fait pas partie des véhicules sortis de ce garage.') end
    if data.vehicleId ~= nil and tonumber(data.vehicleId) ~= tonumber(vehicle.id) then return fail('Tu n’es pas au volant du véhicule sélectionné.') end
    if not categoryPermitted(sourceId, player, job, garage, categoryOf(vehicle.id, garage.id), 'store') then return fail('Ton grade ne permet pas de ranger cette catégorie.') end
    if tonumber(vehicle.net_id) ~= netId then return fail('Ce véhicule ne correspond pas à la sortie enregistrée.') end
    if FleetEntities[tonumber(vehicle.id)] and FleetEntities[tonumber(vehicle.id)] ~= entity then return fail('Entité de flotte non conforme.') end
    if not sameModel(GetEntityModel(entity), modelHash(vehicle.model)) then return fail('Modèle de véhicule non conforme.') end
    local serialized = encodeProperties(data.props, plate, GetEntityModel(entity))
    if not serialized then return fail('Personnalisation invalide ou trop volumineuse.') end
    if not stillAuthorized(sourceId, player, garage, 'store') or GetPlayerRoutingBucket(sourceId) ~= bucket
        or not entityMatches(entity, vehicle, bucket) or GetPedInVehicleSeat(entity, -1) ~= ped then return fail('Véhicule ou autorisation modifié.') end
    local changed = MySQL.update.await([[
        UPDATE aegis_enterprise_fleet SET props = ? WHERE id = ? AND stored = 0 AND net_id = ?
    ]], { serialized, vehicle.id, netId })
    if changed == nil then error('Enregistrement SQL des propriétés impossible') end
    if not stillAuthorized(sourceId, player, garage, 'store') or GetPlayerRoutingBucket(sourceId) ~= bucket
        or not entityMatches(entity, vehicle, bucket) or GetPedInVehicleSeat(entity, -1) ~= ped
        or not nearAnyStore(sourceId, garage, Config.StoreDistance) then return fail('Le véhicule ou ton autorisation a changé pendant le rangement.') end
    if not deleteVehicle(entity) then return fail('Suppression physique refusée : le véhicule reste sorti, réessaie.') end
    commitFleet({ { query = 'UPDATE aegis_enterprise_fleet SET stored = 1, net_id = 0 WHERE id = ? AND stored = 0 AND net_id = ?',
        values = { vehicle.id, netId } } }, garage, plate, 1)
    FleetEntities[tonumber(vehicle.id)] = nil
    distributePlate(garage.job, plate, false)
    broadcastRefresh()
    return success({ message = 'Véhicule rangé : clés d’entreprise retirées.' })
end

local function actionRecover(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not isManager(sourceId, player, job, garage) then return fail('Gestion non autorisée.') end
    local vehicle = fleetRow(tonumber(data.vehicleId), garage.id)
    if not vehicle or tonumber(vehicle.stored) == 1 then return fail('Véhicule déjà au garage.') end
    local tracked = FleetEntities[tonumber(vehicle.id)]
    if entityMatches(tracked, vehicle) or #matchingEntities(vehicle.plate) > 0 then
        return fail('Le véhicule est encore présent en jeu. Range-le normalement.')
    end
    if not stillAuthorized(sourceId, player, garage, 'manage') then return fail('Autorisation expirée.') end
    commitFleet({ { query = 'UPDATE aegis_enterprise_fleet SET stored = 1, net_id = 0 WHERE id = ? AND stored = 0', values = { vehicle.id } } }, garage, vehicle.plate, 1)
    FleetEntities[tonumber(vehicle.id)] = nil
    distributePlate(garage.job, vehicle.plate, false)
    broadcastRefresh()
    return success({ message = 'Véhicule absent récupéré dans le garage.' })
end

local function actionRemove(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'fleet_remove') then return fail('Ton grade ne permet pas de retirer des véhicules.') end
    local vehicle = fleetRow(tonumber(data.vehicleId), garage.id)
    if not vehicle then return fail('Véhicule introuvable.') end
    if tonumber(vehicle.stored) ~= 1 then return fail('Range ou récupère le véhicule avant sa suppression.') end
    if not stillAuthorized(sourceId, player, garage, 'fleet_remove') then return fail('Autorisation expirée.') end
    local queries, restoreError = EnterpriseGarageBridge.releaseQueries(vehicle.plate, vehicle.props)
    if not queries then return fail(restoreError) end
    queries[#queries + 1] = { query = 'INSERT IGNORE INTO aegis_enterprise_retired_keys (plate) VALUES (?)', values = { vehicle.plate } }
    queries[#queries + 1] = { query = 'DELETE FROM aegis_enterprise_fleet WHERE id = ? AND stored = 1', values = { vehicle.id } }
    if not stillAuthorized(sourceId, player, garage, 'fleet_remove') then return fail('Autorisation expirée.') end
    transaction(queries)
    FleetEntities[tonumber(vehicle.id)] = nil
    distributePlate(garage.job, vehicle.plate, false)
    broadcastRefresh()
    return success({ message = 'Véhicule retiré de la flotte et rendu à son garage d’origine si transféré.' })
end

local function actionAddPoint(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not isAdmin(sourceId, player) then return fail('Gestion des points réservée au staff serveur.') end
    local kind = validPointKind(data.kind)
    local label = limitText(data.label, Config.MaxPointLabel)
    local coords = validCoords(data.coords)
    if not kind or not label or not coords then return fail('Point ou coordonnées invalides.') end
    if not nearPlayer(sourceId, coords, 12.0) then return fail('Capture ce point directement sur place.') end
    local conflict = locationConflict(coords, garage.id, false, kind == 'spawn')
    if conflict then return fail('Ce point est déjà utilisé par un autre garage : ' .. conflict) end
    local entrance = vector3(garage.entrance.x, garage.entrance.y, garage.entrance.z)
    if #(entrance - vector3(coords.x, coords.y, coords.z)) > Config.MaxPointDistance then return fail('Point trop éloigné de l’entrée du garage.') end
    local list = kind == 'spawn' and garage.spawnPoints or garage.storePoints
    if #list >= Config.MaxPointsPerKind then return fail('Nombre maximal de points atteint.') end
    if not samePlayer(sourceId, player) or not isAdmin(sourceId, player) then return fail('Autorisation expirée.') end
    local id = MySQL.insert.await('INSERT INTO aegis_enterprise_garage_points (garage_id, kind, label, coords) VALUES (?, ?, ?, ?)',
        { garage.id, kind, label, json.encode(coords) })
    reloadGarages(); broadcastRefresh()
    return success({ id = id, message = 'Point ajouté au garage.' })
end

local function actionRemovePoint(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not isAdmin(sourceId, player) then return fail('Gestion des points réservée au staff serveur.') end
    local id = tonumber(data.pointId)
    if not id or id % 1 ~= 0 then return fail('Point invalide.') end
    local point = MySQL.single.await('SELECT id, kind FROM aegis_enterprise_garage_points WHERE id = ? AND garage_id = ?', { id, garage.id })
    if not point then return fail('Point introuvable.') end
    local list = point.kind == 'spawn' and garage.spawnPoints or garage.storePoints
    if #list <= 1 then return fail('Conserve au moins un point de chaque type.') end
    if not samePlayer(sourceId, player) or not isAdmin(sourceId, player) then return fail('Autorisation expirée.') end
    MySQL.update.await('DELETE FROM aegis_enterprise_garage_points WHERE id = ? AND garage_id = ?', { id, garage.id })
    reloadGarages(); broadcastRefresh()
    return success({ message = 'Point supprimé.' })
end

local function actionSaveCategory(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'categories') then return fail('Grade insuffisant pour gérer les catégories.') end
    local name = limitText(data.name, Config.MaxCategoryName)
    local grades = categoryGrades(data.grades)
    if not name or not grades then return fail('Nom ou permissions de catégorie invalides.') end
    if not validateCompanyAccess(garage.job, grades.access_rules) then return fail('La liste comprend une personne qui ne travaille pas dans cette entreprise.') end
    local id = tonumber(data.categoryId)
    if id and id > 0 then
        local row = MySQL.single.await('SELECT id FROM aegis_enterprise_categories WHERE id = ? AND garage_id = ?', { id, garage.id })
        if not row then return fail('Catégorie introuvable.') end
    else
        id = nil
        local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_categories WHERE garage_id = ?', { garage.id }) or 0)
        if count >= Config.MaxCategories then return fail('Nombre maximal de catégories atteint.') end
    end
    if MySQL.scalar.await('SELECT id FROM aegis_enterprise_categories WHERE garage_id = ? AND LOWER(name) = LOWER(?) AND id <> ? LIMIT 1',
        { garage.id, name, id or 0 }) then return fail('Une catégorie porte déjà ce nom.') end
    if not stillAuthorized(sourceId, player, garage, 'categories') then return fail('Autorisation expirée.') end
    if id then
        MySQL.update.await('UPDATE aegis_enterprise_categories SET name = ?, access_grade = ?, withdraw_grade = ?, store_grade = ?, access_rules = ? WHERE id = ? AND garage_id = ?',
            { name, grades.access, grades.withdraw, grades.store, json.encode(grades.access_rules), id, garage.id })
    else
        id = MySQL.insert.await('INSERT INTO aegis_enterprise_categories (garage_id, name, access_grade, withdraw_grade, store_grade, access_rules) VALUES (?, ?, ?, ?, ?, ?)',
            { garage.id, name, grades.access, grades.withdraw, grades.store, json.encode(grades.access_rules) })
    end
    broadcastRefresh()
    syncKeysForAllPlayers()
    return success({ id = id, message = 'Catégorie enregistrée : clés mises à jour.' })
end

local function actionDeleteCategory(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'categories') then return fail('Grade insuffisant pour gérer les catégories.') end
    local id = tonumber(data.categoryId)
    local changed = MySQL.update.await('DELETE FROM aegis_enterprise_categories WHERE id = ? AND garage_id = ?', { id or 0, garage.id })
    if changed ~= 1 then return fail('Catégorie introuvable.') end
    broadcastRefresh()
    syncKeysForAllPlayers()
    return success({ message = 'Catégorie supprimée. Ses véhicules sont désormais sans catégorie.' })
end

local function actionAssignCategory(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'assign_category') then return fail('Grade insuffisant pour classer les véhicules.') end
    local vehicle = fleetRow(tonumber(data.vehicleId), garage.id)
    if not vehicle then return fail('Véhicule inconnu.') end
    local categoryId = tonumber(data.categoryId) or 0
    if categoryId > 0 then
        local exists = MySQL.scalar.await('SELECT id FROM aegis_enterprise_categories WHERE id = ? AND garage_id = ?', { categoryId, garage.id })
        if not exists then return fail('Cette catégorie n’appartient pas au garage.') end
        if not stillAuthorized(sourceId, player, garage, 'assign_category') then return fail('Autorisation expirée.') end
        MySQL.query.await([[INSERT INTO aegis_enterprise_vehicle_categories (vehicle_id, category_id) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE category_id = VALUES(category_id)]], { vehicle.id, categoryId })
    else
        if not stillAuthorized(sourceId, player, garage, 'assign_category') then return fail('Autorisation expirée.') end
        MySQL.update.await('DELETE FROM aegis_enterprise_vehicle_categories WHERE vehicle_id = ?', { vehicle.id })
    end
    broadcastRefresh()
    syncKeysForAllPlayers()
    return success({ message = 'Catégorie du véhicule modifiée : clés recalculées.' })
end

local function actionRenameVehicle(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    if not garage or not can(sourceId, player, job, garage, 'rename') then return fail('Grade insuffisant pour renommer les véhicules.') end
    local vehicle = fleetRow(tonumber(data.vehicleId), garage.id)
    local label = limitText(data.label, Config.MaxVehicleLabel)
    if not vehicle or not label then return fail('Véhicule ou libellé invalide.') end
    if not stillAuthorized(sourceId, player, garage, 'rename') then return fail('Autorisation expirée.') end
    MySQL.update.await('UPDATE aegis_enterprise_fleet SET label = ? WHERE id = ? AND garage_id = ?', { label, vehicle.id, garage.id })
    broadcastRefresh()
    return success({ message = 'Libellé du véhicule mis à jour.' })
end

local function actionEmployees(sourceId, player, job, data)
    local garage = Garages[tonumber(data.garageId)]
    local jobName
    if garage then
        if not (isManager(sourceId, player, job, garage) or can(sourceId, player, job, garage, 'categories')) then
            return fail('Accès aux employés refusé.')
        end
        jobName = garage.job
    else
        jobName = validModel(data.job)
        if not jobName or not canCreate(sourceId, player, job, jobName) or not jobExists(jobName) then
            return fail('Consultation du personnel non autorisée.')
        end
    end
    local staff = companyEmployees(jobName)
    local grades = MySQL.query.await('SELECT grade, name, label FROM job_grades WHERE job_name = ? ORDER BY grade ASC', { jobName }) or {}
    return success({ employees = staff, grades = grades, job = jobName })
end

local Actions = {
    listEmployees = actionEmployees,
    createGarage = actionCreate, updateGarage = actionUpdate, updateGaragePermissions = actionUpdatePermissions, deleteGarage = actionDelete,
    registerVehicle = actionRegister,
    withdraw = actionWithdraw, store = actionStore, recover = actionRecover, removeVehicle = actionRemove,
    addPoint = actionAddPoint, removePoint = actionRemovePoint,
    saveCategory = actionSaveCategory, deleteCategory = actionDeleteCategory,
    assignCategory = actionAssignCategory, renameVehicle = actionRenameVehicle
}

ESX.RegisterServerCallback('aegis_garage:request', function(sourceId, cb, action, data)
    local player, job = playerInfo(sourceId)
    if not player then cb(fail('Joueur non initialisé.')); return end
    local ok, response = pcall(function()
        if not Ready then return fail('Les garages sont en cours de chargement. Réessaie dans quelques secondes.') end
        if type(action) ~= 'string' then return fail('Action invalide.') end
        if action == 'listLocations' then return locationBootstrap(sourceId, player, job) end
        if action == 'closeSession' then
            local epoch = type(data) == 'table' and integer(data.uiSession, 1, 2147483647) or nil
            if type(data) == 'table' and data.uiSession ~= nil and not epoch then return fail('Session invalide.') end
            local last = SessionEpochs[sourceId]
            if not epoch then
                if not last then GarageSessions[sourceId] = nil end
            elseif not last or epoch >= last.value then
                SessionEpochs[sourceId] = { value = epoch, closed = true }
                if not GarageSessions[sourceId] or not GarageSessions[sourceId].uiSession or GarageSessions[sourceId].uiSession <= epoch then
                    GarageSessions[sourceId] = nil
                end
            end
            return success()
        end
        if action == 'bootstrap' then return fleetBootstrap(sourceId, player, job, type(data) == 'table' and data or {}) end
        if type(data) ~= 'table' then return fail('Requête invalide.') end
        for _, key in ipairs({ 'id', 'garageId', 'vehicleId', 'pointId', 'categoryId', 'netId', 'uiSession' }) do
            if data[key] ~= nil and not integer(data[key], (key == 'categoryId' or key == 'pointId') and 0 or 1) then
                return fail('Identifiant invalide.')
            end
        end
        local handler = Actions[action]
        if not handler then return fail('Action inconnue.') end
        if not isAdmin(sourceId, player) then
            local id = tonumber(data.garageId or data.id)
            if not id then return fail('Garage ciblé obligatoire.') end
            if not Garages[id] or not sessionValid(sourceId, player, job, Garages[id], data.uiSession) then
                return fail('Accède à ce garage depuis son point dédié.')
            end
        end
        if Busy[sourceId] then return fail('Une opération est déjà en cours.') end
        if action ~= 'listEmployees' and MutationLock then return fail('Une opération de garage est en cours. Réessaie.') end
        local operation = {}
        Busy[sourceId] = operation
        if action ~= 'listEmployees' then MutationLock = operation end
        local completed, result = pcall(handler, sourceId, player, job, data)
        if Busy[sourceId] == operation then Busy[sourceId] = nil end
        if MutationLock == operation then MutationLock = nil end
        if not completed then error(result) end
        return result
    end)
    if not ok then
        print(('[aegis_garage] Erreur de requête %s / joueur %s: %s'):format(tostring(action), sourceId, tostring(response)))
        if samePlayer(sourceId, player) then cb(fail('Erreur interne : consulte la console du serveur.')) end
    else
        if samePlayer(sourceId, player) then cb(response) end
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    SetTimeout(3500, function() syncKeysForPlayer(tonumber(playerId)) end)
end)

AddEventHandler('esx:setJob', function(playerId)
    GarageSessions[tonumber(playerId)] = nil
    SetTimeout(800, function()
        syncKeysForPlayer(tonumber(playerId))
        TriggerClientEvent('aegis_garage:reload', tonumber(playerId))
    end)
end)

AddEventHandler('playerDropped', function()
    Busy[source] = nil
    ActiveSync[source] = nil
    PendingSync[source] = nil
    GarageSessions[source] = nil
    SessionEpochs[source] = nil
end)

CreateThread(function()
    while not Ready do
    local initialized, initializeError = pcall(function()
    EnterpriseGarageDatabase.ensure()
    EnterpriseGarageBridge.ensure()
    reloadGarages()
    local outside = MySQL.query.await('SELECT id, plate, model FROM aegis_enterprise_fleet WHERE stored = 0') or {}
    for _, vehicle in ipairs(outside) do
        local matches = matchingEntities(vehicle.plate, modelHash(vehicle.model))
        if #matches == 1 then
            local netId = integer(NetworkGetNetworkIdFromEntity(matches[1]), 1, 65535)
            if netId then
                MySQL.update.await('UPDATE aegis_enterprise_fleet SET net_id = ? WHERE id = ? AND stored = 0', { netId, vehicle.id })
                FleetEntities[tonumber(vehicle.id)] = matches[1]
            end
        end
    end
    for _, g in pairs(Garages) do
        local conflicting = locationConflict(g.entrance, g.id, true)
        if conflicting then print(('[aegis_garage] AVERTISSEMENT: accès en conflit (%s / %s). Déplacez un des garages via le staff.'):format(g.name, conflicting)) end
    end
    print(('[aegis_garage] %d garage(s) chargés.'):format((function() local n = 0; for _ in pairs(Garages) do n = n + 1 end; return n end)()))
    Ready = true
    end)
    if not initialized then
        print('[aegis_garage] Initialisation impossible, nouvel essai dans 10 secondes : ' .. tostring(initializeError))
        Wait(10000)
    end
    end
    Wait(3000)
    for _, online in ipairs(GetPlayers()) do syncKeysForPlayer(tonumber(online)) end
    while true do
        Wait((integer(Config.KeySyncIntervalSeconds, 60, 86400) or 180) * 1000)
        for _, online in ipairs(GetPlayers()) do syncKeysForPlayer(tonumber(online)) end
    end
end)
