local callback
local player = { identifier = 'license:employee', job = { name = 'police', grade = 4 } }
player.getJob = function() return player.job end
player.getGroup = function() return 'user' end
local esx = {
    GetPlayerFromId = function(id) return id == 1 and player or nil end,
    RegisterServerCallback = function(_, fn) callback = fn end
}
exports = setmetatable({}, { __index = function() return { getSharedObject = function() return esx end } end })
function IsPlayerAceAllowed() return false end
function AddEventHandler() end
function RegisterNetEvent() end
local startupThread
function CreateThread(fn) startupThread = fn end
function SetTimeout() end
function GetPlayers() return {} end
function GetPlayerPed() return 0 end
function GetPlayerRoutingBucket() return 0 end
function GetResourceState() return 'started' end
function GetCurrentResourceName() return 'aegis_enterprise_garages' end
function GetGameTimer() return 1000 end
function TriggerClientEvent() end
function Wait() end
local vectorMeta = {}
function vectorMeta.__sub(a, b) return vector3(a.x-b.x, a.y-b.y, a.z-b.z) end
function vectorMeta.__len(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function vector3(x,y,z) return setmetatable({ x=x,y=y,z=z }, vectorMeta) end
MySQL = {}
for _, kind in ipairs({'query','single','scalar','insert','update','transaction'}) do
    MySQL[kind] = { await = function() error('Unexpected database call in validation test: '..kind) end }
end
json = { decode = function() error('Invalid JSON fixture') end, encode = function() return '{}' end }
dofile('shared/config.lua')
dofile('server/database.lua')
dofile('server/main.lua')
assert(type(callback) == 'function', 'ESX request callback must be registered')

local function findUpvalue(target)
    local seen = {}
    local function visit(value)
        if type(value) ~= 'function' and type(value) ~= 'table' then return end
        if seen[value] then return end
        seen[value] = true
        if type(value) == 'function' then
            for index = 1, 150 do
                local name, child = debug.getupvalue(value, index)
                if not name then break end
                if name == target then return child, value, index end
                if name ~= '_ENV' then
                    local found, owner, slot = visit(child)
                    if found ~= nil then return found, owner, slot end
                end
            end
        elseif type(value) == 'table' then
            for _, child in pairs(value) do
                local found, owner, slot = visit(child)
                if found ~= nil then return found, owner, slot end
            end
        end
    end
    return visit(callback)
end
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write('FAIL '..name..': '..tostring(err)..'\n'); os.exit(1) end
    passed = passed + 1
    print('PASS '..name)
end
local function helper(name)
    local value = findUpvalue(name)
    assert(type(value) == 'function', 'Helper unavailable: '..name)
    return value
end

test('coordinates reject NaN, infinity and out-of-map values', function()
    local validate = helper('validCoords')
    for _, coords in ipairs({ {x=0/0,y=0,z=0}, {x=math.huge,y=0,z=0},
        {x=0,y=0,z=0,h=math.huge}, {x=20001,y=0,z=0}, {x=0,y=0,z=5001} }) do
        assert(validate(coords) == nil)
    end
    local coords = assert(validate({x=10,y=-20,z=30,h=-90}))
    assert(coords.h == 270)
end)
test('plate normalization rejects SQL/metacharacter and oversize values', function()
    local validate = helper('validPlate')
    assert(validate('  ab 123  ') == 'AB 123')
    assert(validate("AB'123") == nil)
    assert(validate('123456789') == nil)
    assert(validate({}) == nil)
end)
test('French labels count characters and reject controls/invalid UTF-8', function()
    local validate = helper('limitText')
    assert(validate('Été', 3) == 'Été')
    assert(validate('Été!', 3) == nil)
    assert(validate('ab\ncd', 60) == nil)
    assert(validate(string.char(255)..'ab', 60) == nil)
end)
test('access lists require exact grades or a selected employee', function()
    local permitted = helper('permittedAccess')
    local rule = {mode='list',grades={1,3},identifiers={'license:chosen'}}
    assert(permitted({grade=3}, 'license:other', 0, rule))
    assert(not permitted({grade=4}, 'license:other', 0, rule))
    assert(permitted({grade=0}, 'license:chosen', 4, rule))
    assert(not permitted({grade=4}, 'license:other', 0, {mode='list',grades={},identifiers={}}))
end)
test('malformed lists and permissions are rejected', function()
    local validate = helper('validateAccessRule')
    for _, value in ipairs({{mode='list',grades={0/0},identifiers={}},
        {mode='list',grades={1.5},identifiers={}}, {mode='list',grades={},identifiers={'bad id'}},
        {mode='list',grades={},identifiers={}}, {mode='unknown'}}) do
        assert(validate(value) == nil)
    end
    local perms = {}
    for name, grade in pairs(Config.DefaultPermissions) do perms[name] = grade end
    assert(helper('validatePermissions')(perms))
    perms.withdraw = math.huge
    assert(helper('validatePermissions')(perms) == nil)
end)
test('company boss cannot acquire staff structure powers', function()
    local create = helper('canCreate')
    player.job.grade_name = 'boss'
    assert(not create(1, player, player.job, 'police'))
    local garage = {job='police',permissions={access=0,withdraw=0,manage=4}}
    assert(helper('can')(1, player, player.job, garage, 'manage'))
    assert(not helper('can')(1, player, {name='ambulance',grade=99}, garage, 'manage'))
end)
test('category access applies in addition to garage access', function()
    local allowed = helper('employeeAllowed')
    local garage = {job='police',permissions={access=4,access_rules={mode='all'}}}
    assert(not allowed(player,{name='police',grade=3},garage,{access_grade=0}))
    assert(not allowed(player,player.job,garage,{access_grade=5}))
    assert(allowed(player,player.job,garage,{access_grade=4}))
end)
test('forged mutation fails before any SQL call', function()
    local response
    callback(1, function(result) response=result end, 'renameVehicle', {garageId=1,vehicleId=1,label='Test'})
    assert(response and response.ok == false)
end)
test('uninitialized players receive a structured error', function()
    local response
    callback(99, function(result) response=result end, 'bootstrap', {})
    assert(response and response.ok == false and type(response.error) == 'string')
end)

test('failed schema initialization keeps garages unavailable and schedules a retry', function()
    local ensure, wait = EnterpriseGarageDatabase.ensure, Wait
    local attempted, delayed = false, false
    EnterpriseGarageDatabase.ensure = function() attempted = true; error('Schema unavailable') end
    Wait = function(ms) assert(ms == 10000); delayed = true; error('Stop startup fixture') end
    assert(not pcall(startupThread))
    EnterpriseGarageDatabase.ensure, Wait = ensure, wait
    assert(attempted and delayed)
    local response
    callback(1, function(result) response = result end, 'bootstrap', {})
    assert(response and response.ok == false)
    helper('syncKeysForPlayer')(1)
end)

local garages = assert(findUpvalue('Garages'))
local perms = {}
for name, grade in pairs(Config.DefaultPermissions) do perms[name]=grade end
perms.access_rules = {mode='all',grades={},identifiers={}}
garages[1] = {id=1,name='Mission Row',job='police',entrance={x=0,y=0,z=0,h=0},
    spawn={x=10,y=0,z=0,h=0},permissions=perms,interaction={mode='marker'},
    storePoints={{id=1,coords={x=0,y=0,z=0,h=0},label='Rangement'}},
    spawnPoints={{id=2,coords={x=10,y=0,z=0,h=0},label='Sortie'}}}
local position = vector3(0,0,0)
local bucket = 0
local sqlCalls = 0
function GetPlayerPed() return 1 end
function GetEntityCoords() return position end
function DoesEntityExist() return true end
function GetPlayerRoutingBucket() return bucket end
function GetPlayerName() return 'Employé Test' end
MySQL.query.await = function() sqlCalls=sqlCalls+1; return {} end
for _, name in ipairs({'Ready','ResourceReady','Initialized'}) do
    local value, owner, slot = findUpvalue(name)
    if type(value)=='boolean' then debug.setupvalue(owner,slot,true) end
end
local function request(action, data)
    local response
    callback(1,function(value) response=value end,action,data)
    return assert(response,'Missing callback response')
end
local function open(session)
    position=vector3(0,0,0); bucket=0; player.job.name='police'
    local response=request('bootstrap',{garageId=1,uiSession=session})
    assert(response.ok,response.error)
end
test('an employee can open only at the garage access point',function()
    position=vector3(1000,0,0)
    assert(not request('bootstrap',{garageId=1,uiSession=10}).ok)
    open(11)
end)
test('a remote employee mutation fails before querying the fleet',function()
    open(12)
    position=vector3(1000,0,0)
    local before=sqlCalls
    assert(not request('renameVehicle',{garageId=1,vehicleId=1,label='Test',uiSession=12}).ok)
    assert(sqlCalls==before)
end)
test('changing routing bucket invalidates an employee session',function()
    open(13)
    bucket=1
    local before=sqlCalls
    assert(not request('renameVehicle',{garageId=1,vehicleId=1,label='Test',uiSession=13}).ok)
    assert(sqlCalls==before)
end)
test('changing job invalidates an employee session',function()
    open(14)
    player.job.name='ambulance'
    local before=sqlCalls
    assert(not request('renameVehicle',{garageId=1,vehicleId=1,label='Test',uiSession=14}).ok)
    assert(sqlCalls==before)
end)
test('an old close cannot erase a newer server session',function()
    open(16)
    local sessions=assert(findUpvalue('GarageSessions'))
    local current=assert(sessions[1])
    request('closeSession',{uiSession=15})
    assert(sessions[1]==current)
    request('closeSession',{uiSession=16})
    assert(sessions[1]==nil)
end)
test('staff can capture separated garage points within the configured distance',function()
    player.getGroup=function() return 'admin' end
    player.job.name='police'
    position=vector3(1200,0,0)
    MySQL.scalar.await=function() return 1 end
    local enteredTransaction=false
    MySQL.transaction.await=function()
        enteredTransaction=true
        error('TEST_TRANSACTION_REACHED')
    end
    local actions=assert(findUpvalue('Actions'))
    local data={name='Garage test',job='police',entrance={x=1000,y=0,z=0,h=0},
        spawn={x=1200,y=0,z=0,h=0},permissions=perms,interaction={mode='marker'}}
    local ok=pcall(actions.createGarage,1,player,player.job,data)
    assert(not ok and enteredTransaction,'valid separated captures were rejected before persistence')
    enteredTransaction=false
    data.spawn.x=data.entrance.x+Config.MaxPointDistance+1
    position=vector3(data.spawn.x,0,0)
    local response=actions.createGarage(1,player,player.job,data)
    assert(response.ok==false and not enteredTransaction,'out-of-range spawn was accepted')
    player.getGroup=function() return 'user' end
end)
test('job change during SQL reservation cancels spawning and rolls back storage',function()
    open(17)
    local created, restored=false,false
    function GetAllVehicles() return {} end
    function CreateVehicleServerSetter() created=true; error('Unexpected physical spawn') end
    json.decode=function(value)
        if value=='owned-fixture' then return {model=123} end
        return {}
    end
    MySQL.query.await=function(query)
        if query:find('FROM owned_vehicles',1,true) then
            return {{owner='society_police',vehicle='owned-fixture'}}
        end
        return {}
    end
    MySQL.single.await=function(query)
        if query:find('SELECT * FROM aegis_enterprise_fleet',1,true) then
            return {id=1,garage_id=1,plate='AB123',model='123',stored=1,net_id=0,vehicle_type='automobile',props='{}'}
        end
        return nil
    end
    MySQL.update.await=function(query)
        if query:find('SET stored = 0, net_id = 0',1,true) then player.job.name='ambulance' end
        return 1
    end
    MySQL.transaction.await=function(queries)
        for _, entry in ipairs(queries) do
            if entry.query:find('SET stored = 1',1,true) then restored=true end
        end
        return true
    end
    local response=request('withdraw',{garageId=1,vehicleId=1,pointId=0,uiSession=17})
    assert(response.ok==false)
    assert(not created,'job change was ignored after SQL yield')
    assert(restored,'vehicle reservation was not rolled back')
end)
print(('Server validation: %d tests passed.'):format(passed))
