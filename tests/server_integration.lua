-- Runs the actual server callbacks with FiveM natives supplied by a fixture.
-- Database operations are forwarded to a real MariaDB by server_test.py.
local function encode(value)
    local kind=type(value)
    if kind=='nil' then return 'null' end
    if kind=='boolean' or kind=='number' then return tostring(value) end
    if kind=='string' then
        return '"' .. value:gsub('[%z\1-\31\\"]',function(c)
            local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
            return escapes[c] or ('\\u%04x'):format(c:byte())
        end) .. '"'
    end
    local parts={}
    local length,array=#value,#value>0
    for k in pairs(value) do if type(k)~='number' or k<1 or k>length or k%1~=0 then array=false;break end end
    if array then for i=1,length do parts[#parts+1]=encode(value[i]) end;return '['..table.concat(parts,',')..']' end
    for k,v in pairs(value) do parts[#parts+1]=encode(tostring(k))..':'..encode(v) end
    return '{'..table.concat(parts,',')..'}'
end
local function rpc(method,payload)
    io.write(encode({method=method,payload=payload})..'\n');io.flush()
    local result=assert(load('return '..assert(io.read('*l')), 'database response', 't', {}))()
    if result.error then error(result.error) end
    return result.value
end
json={encode=encode,decode=function(value) return rpc('decode',value) end}
MySQL={ready={await=function() end}}
for _,method in ipairs({'query','scalar','single','update','insert'}) do
    MySQL[method]={await=function(query,values) return rpc(method,{query=query,values=values or {}}) end}
end
MySQL.transaction={await=function(queries) return rpc('transaction',queries) end}

local vectorMeta={__sub=function(a,b)return vector3(a.x-b.x,a.y-b.y,a.z-b.z) end,__len=function(a)return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z)end}
function vector3(x,y,z)return setmetatable({x=x,y=y,z=z},vectorMeta)end
local player={identifier='demo:alex',job={name='mechanic',grade=4}}
player.getJob=function()return player.job end
local admin=false
player.getGroup=function()return admin and 'admin' or 'user' end
local callbacks,threads={},{}
local ESX={GetPlayerFromId=function(id)return id==17 and player or nil end,RegisterServerCallback=function(name,callback)callbacks[name]=callback end}
exports=setmetatable({es_extended={getSharedObject=function()return ESX end}},{__call=function()end})
function IsPlayerAceAllowed()return admin end
function GetPlayerName()return 'Alex Martin' end
function GetPlayers()return {'17','18'} end
function GetPlayerRoutingBucket()return 0 end
function GetEntityRoutingBucket()return 0 end
function GetPlayerPed()return 1 end
function GetCurrentResourceName()return 'aegis_enterprise_garages' end
function LoadResourceFile(_,path)local file=assert(io.open(path));local value=file:read('*a');file:close();return value end
local sourceGarageStarted=true
function GetResourceState(resource)return sourceGarageStarted and resource=='okokGarage' and 'started' or 'missing' end
local sourceKeyEvents={}
function TriggerEvent(event,plate,sourceId)sourceKeyEvents[#sourceKeyEvents+1]={event=event,plate=plate,sourceId=sourceId} end
function TriggerClientEvent()end
function AddEventHandler()end
function SetTimeout()end
function CreateThread(callback)threads[#threads+1]=coroutine.create(callback)end
function Wait()if coroutine.isyieldable() then coroutine.yield() end end
local entity={plate='OKOK001',model=1234,alive=true,refuseDeletion=false}
function NetworkGetEntityFromNetworkId()return 101 end
function NetworkGetNetworkIdFromEntity()return 10 end
function GetEntityType(id)return id==101 and 2 or 1 end
function DoesEntityExist(id)return id==1 or (id==101 and entity.alive)end
function GetPedInVehicleSeat()return 1 end
function GetEntityCoords()return vector3(0,0,0)end
function GetVehicleNumberPlateText()return entity.plate end
function GetEntityModel()return entity.model end
function GetVehicleType()return 'automobile' end
function GetAllVehicles()return entity.alive and {101} or {} end
function DeleteEntity()if not entity.refuseDeletion then entity.alive=false end end
function CreateVehicleServerSetter(model)entity.model,entity.alive=model,true;return 101 end
function SetEntityOrphanMode()end
function SetEntityRoutingBucket()end
function SetVehicleNumberPlateText(_,plate)entity.plate=plate end
local replicated={}
function Entity()return {state={set=function(_,key,value)replicated[key]=value end}}end

dofile('shared/config.lua')
dofile('server/database.lua')
EnterpriseGarageDatabase.ensure()
local defaultPermissions=Config.DefaultPermissions
defaultPermissions.access_rules={mode='all',grades={},identifiers={}}
for id=1,2 do
    MySQL.insert.await([[INSERT INTO aegis_enterprise_garages (id,name,job,entrance,spawn,permissions,created_by)
        VALUES (?, ?, 'mechanic', ?, ?, ?, 'test')]],{id,'Garage test '..id,encode({x=0,y=0,z=0}),encode({x=8,y=0,z=0}),encode(defaultPermissions)})
end
-- The real startup seeding migrates legacy entrance/spawn fields to points.
dofile('server/database.lua')
dofile('server/bridge.lua')
print=function(...)io.stderr:write(table.concat({...},' ')..'\n')end
dofile('server/main.lua')
assert(coroutine.resume(threads[1]))
local checks=0
local function check(value,message)assert(value,message);checks=checks+1 end
local function request(action,payload)
    local response
    callbacks['aegis_garage:request'](17,function(value)response=value end,action,payload or {})
    return assert(response,'Server callback did not complete')
end
local function session(garageId)check(request('bootstrap',{garageId=garageId,uiSession=1}).ok,'bootstrap must open the garage')end
local function owned(plate,owner)
    entity.plate,entity.alive,entity.refuseDeletion=plate,true,false
    MySQL.insert.await([[INSERT INTO owned_vehicles (owner,plate,vehicle,stored,parking,impound,custom_note,nullable_field,
        doorcondition,windowcondition,tyrecondition,favourite,impoundTime,location,reason,sharedwith,vehiclename)
        VALUES (?, ?, ?, 0, 'Legion Square', 0, 'préserver les options okok', NULL,
        ?, ?, ?, 1, NULL, 'Legion Square', NULL, ?, 'Buffalo')]],
        {owner,plate,encode({model=1234,plate=plate,fuelLevel=50}),encode({['0']=false}),encode({['1']=true}),encode({['4']=false}),encode({'demo:lea'})})
end
local function store()
    return request('store',{garageId=1,netId=10,uiSession=1,label='Buffalo personnalisée',props={model=1234,plate=entity.plate,fuelLevel=87,engineHealth=945,modTurbo=true,
        doorsBroken={['0']=true},windowsBroken={['1']=true},tyreBurst={['4']=true},color1={22,133,244},color2={244,133,22},
        tireHealth={[0]=850,[1]=990},tireBurstState={[0]=false,[1]=true},windowStatus={[0]=true,[1]=false}}})
end
session(1)
owned('OKOK001','society_mechanic')
check(store().ok,'okok company vehicle must import through store')
check(#sourceKeyEvents==2 and sourceKeyEvents[1].event=='okokGarage:RemoveKeys' and sourceKeyEvents[1].plate=='OKOK001'
    and sourceKeyEvents[1].sourceId==17 and sourceKeyEvents[2].sourceId==18,'transfer must use the documented server key-removal event for online players')
local fleet=MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE plate = ?',{'OKOK001'})
check(fleet and fleet.stored==1 and fleet.net_id==0,'import must finish stored with no live network entity')
check(not entity.alive,'physical vehicle must be removed after persistence')
check(MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE plate = ?',{'OKOK001'})==0,'okok must not list a reserved vehicle')
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges WHERE plate = ?',{'OKOK001'})==1,'source row must have a durable backup')
check(json.decode(fleet.props).fuelLevel==87 and json.decode(fleet.props).modTurbo,'current properties must be saved')
local savedProps=json.decode(fleet.props)
check(savedProps.doorsBroken['0'] and savedProps.windowsBroken['1'] and savedProps.tyreBurst['4'],'ESX damage properties must survive the transfer')
check(savedProps.color1[2]==133 and savedProps.color2[3]==22,'documented RGB color arrays must survive the transfer')
check(savedProps.tireHealth['0']==850 and savedProps.tireHealth['1']==990 and savedProps.tireBurstState['1']
    and savedProps.windowStatus['0'],'documented zero-indexed ESX wheel and window properties must survive the transfer')
dofile('client/properties.lua')
local appliedProps=EnterpriseGarageProperties.forApply(savedProps)
check(appliedProps.tireHealth[0]==850 and appliedProps.tireBurstState[0]==false and appliedProps.windowStatus[0]==true
    and appliedProps.windowStatus[1]==false,'client application must restore numeric native indices and preserve false values after JSON roundtrip')
check(savedProps.tireHealth['0']==850 and savedProps.tireHealth[0]==nil and appliedProps.color1[2]==133
    and appliedProps.model==1234,'client preparation must preserve the replicated payload and unrelated properties')
local archived=EnterpriseGarageBridge.owned('OKOK001')
check(archived.favourite==1 and archived.vehiclename=='Buffalo' and json.decode(archived.sharedwith)[1]=='demo:lea','documented okok metadata must be captured in the bridge')
local returned=request('removeVehicle',{garageId=1,vehicleId=fleet.id,uiSession=1})
check(returned.ok,'removal must return ownership to okok')
local original=MySQL.single.await('SELECT * FROM owned_vehicles WHERE plate = ?',{'OKOK001'})
check(original.owner=='society_mechanic' and original.parking=='Legion Square' and original.custom_note=='préserver les options okok' and original.nullable_field==nil,'owner and custom source columns must survive')
check(original.stored==1 and json.decode(original.vehicle).fuelLevel==87,'returned vehicle must be stored with current properties')
check(original.favourite==1 and original.vehiclename=='Buffalo' and json.decode(original.sharedwith)[1]=='demo:lea'
    and original.location=='Legion Square' and original.impoundTime==nil and original.reason==nil,'documented favourite, sharing, name and impound metadata must be restored')
check(original.doorcondition==archived.doorcondition and original.windowcondition==archived.windowcondition
    and original.tyrecondition==archived.tyrecondition,'original vendor damage-column formats must remain unchanged')
sourceKeyEvents={};sourceGarageStarted=false;EnterpriseGarageBridge.revokeSourceKeys('OKOK001')
check(#sourceKeyEvents==0,'no key event should be dispatched to a missing source garage')
sourceGarageStarted=true;Config.OkokGarageBridge.RevokeSourceKeys=false;EnterpriseGarageBridge.revokeSourceKeys('OKOK001')
check(#sourceKeyEvents==0,'operator must be able to disable source key cleanup')
Config.OkokGarageBridge.RevokeSourceKeys=true
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges')==0,'successful release must clear its backup')
owned('NEGKEYS1','society_mechanic')
check(not request('store',{garageId=1,netId=10,uiSession=1,label='Test invalide',props={model=1234,tireHealth={[-1]=100}}}).ok,'negative property indices must remain rejected')
check(entity.alive and MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE plate = ?',{'NEGKEYS1'})==1,'invalid properties must not reserve ownership or delete the vehicle')

owned('PERSON01','demo:alex');check(store().ok,'owned personal vehicle must be transferable by a fleet manager')
local personalFleet=MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE plate = ?',{'PERSON01'})
check(request('withdraw',{garageId=1,vehicleId=personalFleet.id,pointId=0,uiSession=1}).ok,'an archived personal vehicle must be withdrawable by the fleet')
check(entity.alive and replicated.aegisFleetInit.props.fuelLevel==87,'withdrawal must apply the saved properties')
check(store().ok,'withdrawn personal fleet vehicle must return to the same garage')
owned('OTHER001','demo:someoneelse');check(not store().ok,'another player’s vehicle must be rejected')
check(MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE plate = ?',{'OTHER001'})==1 and entity.alive,'rejection must retain source ownership and physical vehicle')
player.job.grade=1;owned('GRADE001','society_mechanic');check(not store().ok,'store permission alone must not grant fleet import')
player.job.grade=4
Config.OkokGarageBridge.AllowEmployeeOwnedVehicles=false
owned('NOOWN001','demo:alex');check(not store().ok,'operator can forbid personal vehicle transfers')
Config.OkokGarageBridge.AllowEmployeeOwnedVehicles=true
owned('BADMODEL','society_mechanic');entity.model=9999;check(not store().ok,'observed and persisted models must match');entity.model=1234
owned('DELETE01','society_mechanic');entity.refuseDeletion=true
check(store().ok,'refused entity deletion must retain an imported outside vehicle')
local outside=MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE plate = ?',{'DELETE01'})
check(outside.stored==0 and outside.net_id==10 and entity.alive,'failed physical deletion must never mark the vehicle stored')
entity.refuseDeletion=false
check(store().ok,'outside tracked vehicle must be storable on retry')
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges WHERE plate = ?',{'DELETE01'})==1,'retry must not duplicate the reservation')
entity.plate,entity.alive='PERSON01',true
session(2)
check(not request('store',{garageId=2,netId=10,uiSession=1,props={model=1234},label='Test'}).ok,'a plate assigned to another garage must not be imported twice')
session(1)
local personal=MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE plate = ?',{'PERSON01'})
MySQL.insert.await('INSERT INTO owned_vehicles (owner,plate,vehicle) VALUES (?, ?, ?)',{'demo:conflict','PERSON01',encode({model=1234})})
check(not request('removeVehicle',{garageId=1,vehicleId=personal.id,uiSession=1}).ok,'normalized ownership conflicts must block release')
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges WHERE plate = ?',{'PERSON01'})==1,'failed release must retain the ownership backup')
MySQL.update.await('DELETE FROM owned_vehicles WHERE plate = ?',{'PERSON01'})
Config.OkokGarageBridge.Enabled=false
check(request('removeVehicle',{garageId=1,vehicleId=personal.id,uiSession=1}).ok,'reservations must remain releasable if the bridge is disabled')
Config.OkokGarageBridge.Enabled=true

owned('ROLLBACK','society_mechanic')
local row=MySQL.single.await('SELECT * FROM owned_vehicles WHERE plate = ?',{'ROLLBACK'})
local rolled=pcall(function()
    MySQL.transaction.await({EnterpriseGarageBridge.captureQuery('ROLLBACK',row),{query='INSERT INTO table_that_does_not_exist VALUES (1)',values={}}})
end)
check(not rolled,'an invalid SQL operation must abort the transaction')
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges WHERE plate = ?',{'ROLLBACK'})==0 and MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE plate = ?',{'ROLLBACK'})==1,'rollback must preserve the original row without a reservation')
owned('RACE0001','society_mechanic')
row=MySQL.single.await('SELECT * FROM owned_vehicles WHERE plate = ?',{'RACE0001'})
MySQL.update.await('UPDATE owned_vehicles SET vehicle = ? WHERE plate = ?',{encode({model=5678}),'RACE0001'})
MySQL.transaction.await({EnterpriseGarageBridge.captureQuery('RACE0001',row)})
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges WHERE plate = ?',{'RACE0001'})==0,'changed ownership properties must invalidate an optimistic capture')

MySQL.update.await('ALTER TABLE owned_vehicles DROP COLUMN stored')
entity.plate,entity.alive='NOSTORED',true
MySQL.insert.await('INSERT INTO owned_vehicles (owner,plate,vehicle) VALUES (?, ?, ?)',{'society_mechanic','NOSTORED',encode({model=1234})})
check(store().ok,'bridge import must support an ESX schema without stored')
local withoutStored=MySQL.single.await('SELECT * FROM aegis_enterprise_fleet WHERE plate = ?',{'NOSTORED'})
check(request('removeVehicle',{garageId=1,vehicleId=withoutStored.id,uiSession=1}).ok,'bridge release must support an ESX schema without stored')
check(MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE plate = ?',{'NOSTORED'})=='society_mechanic','source ownership must survive a schema without stored')
MySQL.update.await('ALTER TABLE owned_vehicles ADD COLUMN stored TINYINT DEFAULT 0')
MySQL.update.await('ALTER TABLE owned_vehicles ENGINE = MyISAM')
check(not pcall(EnterpriseGarageBridge.ensure,true),'nontransactional source tables must be rejected before reservation')
MySQL.update.await('ALTER TABLE owned_vehicles ENGINE = InnoDB')
check(pcall(EnterpriseGarageBridge.ensure,true),'transactional source tables must be accepted again')

entity.alive=false;admin=true
check(request('deleteGarage',{id=1}).ok,'garage deletion must return its reserved vehicles atomically')
check(MySQL.scalar.await('SELECT COUNT(*) FROM aegis_enterprise_vehicle_bridges')==0,'garage deletion must not leave ownership backups orphaned')
check(MySQL.scalar.await('SELECT stored FROM owned_vehicles WHERE plate = ?',{'DELETE01'})==1,'garage deletion must restore the original garage entry')
rpc('result',{checks=checks})
