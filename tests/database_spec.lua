local file = assert(io.open('sql/install.sql', 'rb'))
local schema = file:read('*a')
file:close()

function GetCurrentResourceName() return 'aegis_enterprise_garages' end
function LoadResourceFile(_, path)
    assert(path == 'sql/install.sql')
    return schema
end

local tableNames = {
    'aegis_enterprise_garages', 'aegis_enterprise_fleet', 'aegis_enterprise_retired_keys',
    'aegis_enterprise_garage_points', 'aegis_enterprise_categories', 'aegis_enterprise_vehicle_categories'
}

local function database(version)
    local state = { tables = {}, alters = 0, connected = false, points = {}, garage = { id = 1 }, vehicle = { id = 1, stored = 0 } }
    if version then
        state.tables.aegis_enterprise_garages = { permissions = true, interaction = version >= 1.3 or nil }
        state.tables.aegis_enterprise_fleet = {}
        state.tables.aegis_enterprise_retired_keys = {}
        if version >= 1.1 then
            state.tables.aegis_enterprise_garage_points = {}
            state.tables.aegis_enterprise_categories = { store_grade = true, access_rules = version >= 1.2 or nil }
            state.tables.aegis_enterprise_vehicle_categories = {}
            state.points.store = 'Existing store point'
        end
    else
        state.garage, state.vehicle = nil, nil
    end
    MySQL = {
        ready = { await = function() state.connected = true end },
        scalar = { await = function(query, params)
            assert(state.connected)
            assert(query:find('TABLE_SCHEMA = DATABASE()', 1, true))
            return state.tables[params[1]][params[2]] and 1 or 0
        end },
        query = { await = function(query)
            assert(state.connected, 'SQL executed before oxmysql was ready')
            local tableName = query:match('^CREATE TABLE IF NOT EXISTS `([%w_]+)`')
            if tableName then
                if not state.tables[tableName] then
                    state.tables[tableName] = {}
                    for line in query:gmatch('[^\r\n]+') do
                        local column = line:match('^%s*`([%w_]+)`')
                        if column then state.tables[tableName][column] = true end
                    end
                end
                return {}
            end
            local column
            tableName, column = query:match('^ALTER TABLE `([%w_]+)` ADD COLUMN `([%w_]+)`')
            if tableName then
                assert(not state.tables[tableName][column], 'Duplicate ADD COLUMN')
                if state.failAlter then error('Database unavailable') end
                state.tables[tableName][column] = true
                state.alters = state.alters + 1
                return {}
            end
            if query:match('^INSERT INTO `aegis_enterprise_garage_points`') then
                assert(state.tables.aegis_enterprise_garages and state.tables.aegis_enterprise_garage_points)
                assert(state.tables.aegis_enterprise_garages.interaction)
                assert(state.tables.aegis_enterprise_categories.access_rules)
                assert(query:find('WHERE NOT EXISTS', 1, true), 'Backfill must preserve existing points')
                local kind = assert(query:match("SELECT g.id, '(%w+)'"))
                if state.garage and not state.points[kind] then state.points[kind] = 'Migrated point' end
                return {}
            end
            error('Unexpected SQL: ' .. query)
        end }
    }
    dofile('server/database.lua')
    return state
end

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write('FAIL ' .. name .. ': ' .. tostring(err) .. '\n'); os.exit(1) end
    passed = passed + 1
    print('PASS ' .. name)
end

test('first start creates all tables after connecting to oxmysql', function()
    local state = database()
    EnterpriseGarageDatabase.ensure()
    for _, name in ipairs(tableNames) do assert(state.tables[name], 'Missing table: ' .. name) end
    assert(state.tables.aegis_enterprise_garages.interaction)
    assert(state.tables.aegis_enterprise_categories.access_rules)
    assert(state.alters == 0 and next(state.points) == nil)
end)

test('existing versions upgrade without changing fleet data or duplicating points', function()
    for _, fixture in ipairs({ {1.0, 1}, {1.1, 2}, {1.2, 1}, {1.3, 0} }) do
        local state = database(fixture[1])
        local garage, vehicle, existingPoint = state.garage, state.vehicle, state.points.store
        EnterpriseGarageDatabase.ensure()
        for _, name in ipairs(tableNames) do assert(state.tables[name]) end
        assert(state.alters == fixture[2])
        assert(state.points.store and state.points.spawn)
        if existingPoint then assert(state.points.store == existingPoint) end
        assert(state.garage == garage and state.vehicle == vehicle and vehicle.stored == 0)
        local point, alters = state.points.spawn, state.alters
        dofile('server/database.lua')
        EnterpriseGarageDatabase.ensure()
        assert(state.points.spawn == point and state.alters == alters)
    end
end)

test('a failed migration can be retried before any point backfill', function()
    local state = database(1.1)
    state.failAlter = true
    assert(not pcall(EnterpriseGarageDatabase.ensure))
    assert(state.points.spawn == nil)
    state.failAlter = false
    EnterpriseGarageDatabase.ensure()
    assert(state.alters == 2 and state.points.spawn)
end)

test('missing schema prevents SQL execution', function()
    local state = database()
    local load = LoadResourceFile
    LoadResourceFile = function() return nil end
    assert(not pcall(EnterpriseGarageDatabase.ensure))
    assert(not state.connected and next(state.tables) == nil)
    LoadResourceFile = load
end)

print(('Database initialization: %d tests passed.'):format(passed))
