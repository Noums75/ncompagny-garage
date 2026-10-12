local passed = 0
local function runtime()
    local r = {requests={}, messages={}, timers={}, callbacks={}, commands={}, notices={}, focused=false}
    local esx = {
        TriggerServerCallback = function(_, cb, action, data)
            r.requests[#r.requests+1] = {cb=cb,action=action,data=data}
        end,
        ShowNotification = function(message) r.notices[#r.notices+1]=message end
    }
    exports = setmetatable({}, {__index=function() return {getSharedObject=function() return esx end} end})
    function RegisterCommand(name, fn) r.commands[name]=fn end
    function RegisterNUICallback(name, fn) r.callbacks[name]=fn end
    function RegisterNetEvent() end
    function AddEventHandler() end
    function AddStateBagChangeHandler() end
    function CreateThread() end
    function SetTimeout(ms, fn) r.timers[#r.timers+1]={ms=ms,fn=fn} end
    function SetNuiFocus(value) r.focused=value end
    function SetNuiFocusKeepInput() end
    function SendNUIMessage(value) r.messages[#r.messages+1]=value end
    function GetResourceState() return 'started' end
    function GetCurrentResourceName() return 'aegis_enterprise_garages' end
    function PlayerPedId() return 1 end
    function GetEntityCoords() return {x=0,y=0,z=0} end
    function GetEntityHeading() return 0 end
    function GetGameTimer() return 1000 end
    function vector3(x,y,z) return {x=x,y=y,z=z} end
    function Wait() end
    dofile('shared/config.lua')
    dofile('client/main.lua')
    function r.open()
        r.commands[Config.Command]()
        return r.messages[#r.messages].sessionId
    end
    function r.lastRequest(action)
        for i=#r.requests,1,-1 do if r.requests[i].action==action then return r.requests[i] end end
        error('Missing request: '..action)
    end
    function r.nui(name, data)
        local response
        r.callbacks[name](data or {}, function(value) response=value end)
        return response
    end
    return r
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write('FAIL '..name..': '..tostring(err)..'\n'); os.exit(1) end
    passed=passed+1
    print('PASS '..name)
end
local payload = {ok=true,isAdmin=true,garages={},playerName='Test',playerJob='police',playerGrade=4}
test('late bootstrap cannot overwrite a reopened NUI session', function()
    local r=runtime()
    local oldSession=r.open()
    local stale=r.lastRequest('bootstrap')
    assert(r.nui('close',{uiSession=oldSession}).ok)
    local newSession=r.open()
    assert(newSession ~= oldSession)
    local latest=r.lastRequest('bootstrap')
    local count=#r.messages
    stale.cb(payload)
    assert(#r.messages==count, 'stale bootstrap reached NUI')
    latest.cb(payload)
    assert(r.messages[#r.messages].type=='bootstrap' and r.focused)
end)
test('request timeout closes opening UI and ignores a later response', function()
    local r=runtime()
    r.open()
    local request=r.lastRequest('bootstrap')
    assert(#r.timers>0, 'request timeout missing')
    r.timers[#r.timers].fn()
    assert(not r.focused, 'timeout left mouse focus captured')
    assert(#r.notices==1)
    local count=#r.messages
    request.cb(payload)
    assert(#r.messages==count and not r.focused)
end)
test('duplicate ESX response is handled once', function()
    local r=runtime()
    r.open()
    local request=r.lastRequest('bootstrap')
    request.cb(payload)
    local count=#r.messages
    request.cb(payload)
    assert(#r.messages==count)
end)
test('closed NUI cannot fetch data', function()
    local r=runtime()
    local before=#r.requests
    local response=r.nui('fetchData')
    assert(response and response.ok==false)
    assert(#r.requests==before)
end)
test('stale close callback cannot close a newer interface', function()
    local r=runtime()
    local oldSession=r.open()
    r.nui('close',{uiSession=oldSession})
    local newSession=r.open()
    local response=r.nui('close',{uiSession=oldSession})
    assert(response and response.ok==false and r.focused)
    assert(r.nui('close',{uiSession=newSession}).ok and not r.focused)
end)
print(('Client lifecycle: %d tests passed.'):format(passed))
