local ESX = exports['es_extended']:getSharedObject()
local uiOpen = false
local uiReady = false
local uiSession = math.max(1, GetGameTimer())
local bootstrapVersion = 0
local stopping = false
local pendingRequests = {}
local requestId = 0
local activeCapture = nil
local markers = {}
local markerPoints = {}
local markerVersion = 0
local entranceAvailable = {}
local refreshing = false
local refreshQueued = false
local refreshRetry = 0
local selectedGarageId = nil
local spawnedPeds = {}
local loadingPeds = {}
local pedRetryAt = {}
local isStaff = false

local function notify(text)
    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(text)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function getCoords()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    return {
        x = tonumber(('%0.3f'):format(pos.x)),
        y = tonumber(('%0.3f'):format(pos.y)),
        z = tonumber(('%0.3f'):format(pos.z)),
        h = tonumber(('%0.2f'):format(GetEntityHeading(ped)))
    }
end

local function serverRequest(action, data, callback)
    requestId = requestId + 1
    local id, finished = requestId, false
    local function finish(result)
        if finished then return end
        finished = true
        pendingRequests[id] = nil
        if type(result) ~= 'table' or type(result.ok) ~= 'boolean' then
            result = { ok = false, error = 'Réponse du serveur invalide.' }
        end
        callback(result)
    end
    pendingRequests[id] = finish
    if stopping then
        finish({ ok = false, error = 'La ressource de garage est arrêtée.' })
        return
    end
    SetTimeout(math.max(1000, tonumber(Config.RequestTimeoutMs) or 15000), function()
        finish({ ok = false, error = 'Le serveur ne répond pas. Actualise avant de réessayer une opération.' })
    end)
    local ok = pcall(function()
        ESX.TriggerServerCallback('aegis_garage:request', finish, action, data or {})
    end)
    if not ok then finish({ ok = false, error = 'Impossible de contacter le serveur du garage.' }) end
end

local function deletePed(id)
    local ped = spawnedPeds[id]
    if not ped then return end
    if GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeLocalEntity(ped, 'aegis_garage_' .. id) end)
    end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    spawnedPeds[id] = nil
end

local function clearPeds()
    markerVersion = markerVersion + 1
    loadingPeds = {}
    pedRetryAt = {}
    for id in pairs(spawnedPeds) do deletePed(id) end
end

local function rebuildInteractions()
    markerPoints, entranceAvailable = {}, {}
    local reserved = {}
    local function reserve(coords, garageId)
        if type(coords) ~= 'table' or not tonumber(coords.x) or not tonumber(coords.y) or not tonumber(coords.z) then return false end
        local here = vector3(coords.x, coords.y, coords.z)
        for _, previous in ipairs(reserved) do
            if previous.garageId ~= garageId and #(here - previous.coords) < Config.MinCrossGaragePointDistance then return false end
        end
        reserved[#reserved + 1] = { garageId = garageId, coords = here }
        return true
    end
    for _, garage in ipairs(markers) do
        if reserve(garage.entrance, garage.id) then
            entranceAvailable[garage.id] = true
            markerPoints[#markerPoints + 1] = { garage = garage, coords = garage.entrance, label = garage.name, entrance = true }
        end
    end
    for _, garage in ipairs(markers) do
        for _, point in ipairs(garage.storePoints or {}) do
            local pos, access = point.coords, garage.entrance
            if pos and access and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z)
                and #(vector3(pos.x, pos.y, pos.z) - vector3(access.x, access.y, access.z)) > 3.0
                and reserve(pos, garage.id) then
                markerPoints[#markerPoints + 1] = { garage = garage, coords = pos, label = 'Rangement : ' .. (point.label or garage.name) }
            end
        end
    end
end

local function finishCapture(capture, result)
    if not capture or capture.finished then return end
    capture.finished = true
    if activeCapture == capture then activeCapture = nil end
    if uiOpen and uiSession == capture.session then
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'captureEnd', sessionId = capture.session })
    end
    capture.callback(result)
end

local function closeGarage()
    if not uiOpen then return end
    local closedSession = uiSession
    uiOpen, uiReady, isStaff = false, false, false
    selectedGarageId = nil
    uiSession = uiSession + 1
    bootstrapVersion = bootstrapVersion + 1
    SetNuiFocus(false, false)
    finishCapture(activeCapture, { ok = false, error = 'Sélection annulée.' })
    SendNUIMessage({ type = 'close', sessionId = closedSession })
    serverRequest('closeSession', { uiSession = closedSession }, function() end)
end

local function requestBootstrap(callback)
    local session = uiSession
    bootstrapVersion = bootstrapVersion + 1
    local version = bootstrapVersion
    serverRequest('bootstrap', { garageId = selectedGarageId, uiSession = session }, function(result)
        if not uiOpen or session ~= uiSession or version ~= bootstrapVersion then
            if callback then callback({ ok = false, stale = true, error = 'Cette session de garage est fermée.' }) end
            return
        end
        if result.ok then
            uiReady = true
            isStaff = result.isAdmin == true
            SendNUIMessage({ type = 'bootstrap', payload = result, sessionId = session })
        else
            closeGarage()
            notify(result.error or 'Le garage est indisponible.')
        end
        if callback then callback(result) end
    end)
end

local function refreshMarkers()
    if stopping then return end
    if refreshing then refreshQueued = true; return end
    refreshing = true
    serverRequest('listLocations', {}, function(result)
        refreshing = false
        if stopping then return end
        if result.ok then
            refreshRetry = 0
            clearPeds()
            markers = type(result.garages) == 'table' and result.garages or {}
            rebuildInteractions()
            if uiOpen then requestBootstrap() end
        else
            refreshRetry = math.min(refreshRetry + 1, 6)
            SetTimeout(refreshRetry * 5000, refreshMarkers)
        end
        if refreshQueued then
            refreshQueued = false
            SetTimeout(250, refreshMarkers)
        end
    end)
end

local function openGarage(garageId)
    if uiOpen then return end
    selectedGarageId = garageId and tonumber(garageId) or nil
    uiSession = uiSession + 1
    uiOpen, uiReady, isStaff = true, false, false
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', selectedId = selectedGarageId, sessionId = uiSession })
    requestBootstrap()
end

RegisterCommand(Config.Command, function() openGarage(nil) end, false)

local function canUseTarget(garage)
    return garage.interaction and garage.interaction.mode == 'ped'
        and GetResourceState('ox_target') == 'started'
end

local function makePed(garage)
    local id = garage.id
    if spawnedPeds[id] or loadingPeds[id] or not canUseTarget(garage)
        or (pedRetryAt[id] and GetGameTimer() < pedRetryAt[id]) then return end
    local loading = { version = markerVersion }
    loadingPeds[id] = loading
    CreateThread(function()
        local cfg = garage.interaction
        local hash = joaat(cfg.pedModel or Config.PedModelDefault)
        local function release()
            if loadingPeds[id] == loading then loadingPeds[id] = nil end
            SetModelAsNoLongerNeeded(hash)
        end
        if not IsModelInCdimage(hash) or not IsModelAPed(hash) then
            if markerVersion == loading.version then pedRetryAt[id] = GetGameTimer() + 30000 end
            release()
            return
        end
        RequestModel(hash)
        local expire = GetGameTimer() + 5000
        while not HasModelLoaded(hash) and GetGameTimer() < expire
            and not stopping and markerVersion == loading.version do Wait(50) end
        if not HasModelLoaded(hash) or stopping or markerVersion ~= loading.version or not canUseTarget(garage) then
            if markerVersion == loading.version then pedRetryAt[id] = GetGameTimer() + 5000 end
            release()
            return
        end
        local pos = garage.entrance
        if #(GetEntityCoords(PlayerPedId()) - vector3(pos.x, pos.y, pos.z)) > Config.PedRenderDistance + 35 then release(); return end
        local ped = CreatePed(4, hash, pos.x, pos.y, pos.z - 1.0, pos.h or 0.0, false, false)
        release()
        if ped == 0 or not DoesEntityExist(ped) then pedRetryAt[id] = GetGameTimer() + 5000; return end
        SetEntityAsMissionEntity(ped, true, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        local scenario = cfg.scenario
        if scenario and scenario ~= '' then TaskStartScenarioInPlace(ped, scenario, 0, true) end
        spawnedPeds[id] = ped
        local added = pcall(function()
            exports.ox_target:addLocalEntity(ped, {{
                name = 'aegis_garage_' .. id,
                icon = 'fa-solid fa-warehouse',
                label = 'Ouvrir : ' .. garage.name,
                distance = Config.InteractDistance,
                onSelect = function() openGarage(id) end
            }})
        end)
        if not added then deletePed(id); pedRetryAt[id] = GetGameTimer() + 5000 end
    end)
end

CreateThread(function()
    Wait(2000)
    refreshMarkers()
    while not stopping do
        local position = GetEntityCoords(PlayerPedId())
        for _, garage in ipairs(markers) do
            if entranceAvailable[garage.id] then
                local entrance = garage.entrance
                local distance = #(position - vector3(entrance.x, entrance.y, entrance.z))
                if spawnedPeds[garage.id] and not DoesEntityExist(spawnedPeds[garage.id]) then spawnedPeds[garage.id] = nil end
                if distance <= Config.PedRenderDistance and canUseTarget(garage) then
                    makePed(garage)
                elseif (distance > Config.PedRenderDistance + 35 or not canUseTarget(garage)) and spawnedPeds[garage.id] then
                    deletePed(garage.id)
                end
            end
        end
        Wait(750)
    end
end)

CreateThread(function()
    while not stopping do
        local sleep = 500
        local ped = PlayerPedId()
        local position = GetEntityCoords(ped)
        local closest, closestDistance = nil, 99999.0
        if not uiOpen then
            for _, point in ipairs(markerPoints) do
                local garage = point.garage
                local target = point.coords
                if not point.entrance or not canUseTarget(garage) or not spawnedPeds[garage.id] then
                    local distance = #(position - vector3(target.x, target.y, target.z))
                    if distance <= Config.MarkerDistance then
                        sleep = 0
                        local m = Config.Marker
                        DrawMarker(m.type, target.x, target.y, target.z + 0.10,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.scale.x, m.scale.y, m.scale.z,
                            m.color.r, m.color.g, m.color.b, m.color.a,
                            false, true, 2, false, nil, nil, false)
                        if distance <= Config.InteractDistance and distance < closestDistance then
                            closest = { garageId = garage.id, label = point.label }
                            closestDistance = distance
                        end
                    end
                end
            end
        end
        if closest then
            ESX.ShowHelpNotification(('Appuie sur ~INPUT_CONTEXT~ pour accéder à ~b~%s~s~'):format(closest.label))
            if IsControlJustReleased(0, 38) then openGarage(closest.garageId) end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('aegis_garage:reload', function()
    refreshMarkers()
end)

RegisterNetEvent('esx:playerLoaded', function()
    closeGarage()
    SetTimeout(1200, refreshMarkers)
end)

RegisterNetEvent('esx:setJob', function()
    closeGarage()
    clearPeds()
    markers, markerPoints, entranceAvailable = {}, {}, {}
    SetTimeout(650, refreshMarkers)
end)

local function validateUiRequest(data, cb, allowLoading)
    if not uiOpen or (type(data) == 'table' and data.uiSession ~= nil and tonumber(data.uiSession) ~= uiSession) then
        cb({ ok = false, stale = true, error = 'Cette session de garage est fermée.' })
        return nil
    end
    if not uiReady and not allowLoading then
        cb({ ok = false, error = 'Le garage est encore en cours de chargement.' })
        return nil
    end
    return uiSession
end

local function sessionCallback(session, cb)
    return function(result)
        if not uiOpen or uiSession ~= session then
            cb({ ok = false, stale = true, error = 'Cette session de garage est fermée.' })
        else
            cb(result)
        end
    end
end

RegisterNUICallback('close', function(data, cb)
    if not validateUiRequest(data, cb, true) then return end
    closeGarage()
    cb({ ok = true })
end)

RegisterNUICallback('fetchData', function(data, cb)
    if not validateUiRequest(data, cb, true) then return end
    requestBootstrap(cb)
end)

RegisterNUICallback('capturePosition', function(data, cb)
    if not validateUiRequest(data, cb) then return end
    if not isStaff then cb({ ok = false, error = 'La configuration des points est réservée au staff serveur.' }); return end
    cb({ ok = true, position = getCoords() })
end)

RegisterNUICallback('selectPosition', function(data, cb)
    local session = validateUiRequest(data, cb)
    if not session then return end
    if not isStaff then cb({ ok = false, error = 'La configuration des points est réservée au staff serveur.' }); return end
    if activeCapture then cb({ ok = false, error = 'Une sélection de position est déjà en cours.' }); return end
    local capture = { session = session, callback = cb }
    activeCapture = capture
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'captureStart', sessionId = session })
    CreateThread(function()
        local expiresAt = GetGameTimer() + 120000
        local result = { ok = false, error = 'Sélection annulée.' }
        while uiOpen and session == uiSession and not capture.finished and GetGameTimer() < expiresAt do
            Wait(0)
            if capture.finished or not uiOpen or session ~= uiSession then break end
            local pos = GetEntityCoords(PlayerPedId())
            DrawMarker(1, pos.x, pos.y, pos.z - 1.02, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.65, 0.65, 0.12, 100, 166, 255, 115,
                false, false, 2, false, nil, nil, false)
            ESX.ShowHelpNotification('Déplace-toi jusqu’au point désiré. ~INPUT_CONTEXT~ : capturer  |  ~INPUT_CELLPHONE_CANCEL~ : annuler')
            if IsControlJustReleased(0, 38) then
                result = { ok = true, position = getCoords() }
                break
            elseif IsControlJustReleased(0, 177) then
                break
            end
        end
        if GetGameTimer() >= expiresAt then
            result = { ok = false, error = 'Temps de sélection écoulé.' }
        end
        finishCapture(capture, result)
    end)
end)

RegisterNUICallback('captureVehicle', function(data, cb)
    if not validateUiRequest(data, cb) then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        vehicle = ESX.Game.GetClosestVehicle(coords)
        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or #(GetEntityCoords(vehicle) - coords) > Config.RegisterDistance then
            cb({ ok = false, error = 'Aucun véhicule à proximité. Approche-toi ou installe-toi au volant.' })
            return
        end
    end
    if not NetworkGetEntityIsNetworked(vehicle) then
        cb({ ok = false, error = 'Ce véhicule doit être synchronisé sur le réseau.' })
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId <= 0 then cb({ ok = false, error = 'Ce véhicule n’est pas encore synchronisé. Réessaie dans un instant.' }); return end
    local captured, properties = pcall(ESX.Game.GetVehicleProperties, vehicle)
    if not captured or type(properties) ~= 'table' then cb({ ok = false, error = 'Impossible de lire les propriétés de ce véhicule.' }); return end
    local vehicleClass = GetVehicleClass(vehicle)
    local vehicleType = 'automobile'
    if vehicleClass == 8 or vehicleClass == 13 then vehicleType = 'bike'
    elseif vehicleClass == 14 then vehicleType = 'boat'
    elseif vehicleClass == 15 then vehicleType = 'heli'
    elseif vehicleClass == 16 then vehicleType = 'plane'
    end
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local localized = GetLabelText(name)
    if not localized or localized == 'NULL' then localized = name end
    cb({
        ok = true, netId = netId,
        plate = ESX.Math.Trim(GetVehicleNumberPlateText(vehicle)),
        label = localized, vehicleType = vehicleType,
        props = properties
    })
end)

RegisterNUICallback('storeCurrent', function(data, cb)
    local session = validateUiRequest(data, cb)
    if not session then return end
    if type(data) ~= 'table' then cb({ ok = false, error = 'Requête invalide.' }); return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        cb({ ok = false, error = 'Installe-toi au volant du véhicule à ranger.' })
        return
    end
    if not NetworkGetEntityIsNetworked(vehicle) then cb({ ok = false, error = 'Ce véhicule doit être synchronisé sur le réseau.' }); return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId <= 0 then cb({ ok = false, error = 'Ce véhicule n’est pas encore synchronisé.' }); return end
    local captured, properties = pcall(ESX.Game.GetVehicleProperties, vehicle)
    if not captured or type(properties) ~= 'table' then cb({ ok = false, error = 'Impossible de lire les propriétés de ce véhicule.' }); return end
    serverRequest('store', {
        garageId = data.garageId,
        vehicleId = data.vehicleId,
        uiSession = session,
        netId = netId,
        props = properties
    }, sessionCallback(session, cb))
end)

RegisterNUICallback('execute', function(data, cb)
    local session = validateUiRequest(data, cb)
    if not session then return end
    if type(data) ~= 'table' or type(data.action) ~= 'string' then
        cb({ ok = false, error = 'Requête invalide.' })
        return
    end
    if data.action == 'bootstrap' or data.action == 'closeSession' or data.action == 'listLocations'
        or (data.data ~= nil and type(data.data) ~= 'table') then cb({ ok = false, error = 'Requête invalide.' }); return end
    local payload = data.data or {}
    payload.uiSession = session
    serverRequest(data.action, payload, sessionCallback(session, cb))
end)

RegisterNetEvent('aegis_garage:vehicleSpawned', function(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 or netId % 1 ~= 0 or stopping then return end
    CreateThread(function()
        local timeout = GetGameTimer() + 9000
        local vehicle = 0
        while GetGameTimer() < timeout and not stopping do
            vehicle = NetworkDoesEntityExistWithNetworkId(netId) and NetToVeh(netId) or 0
            if vehicle ~= 0 and DoesEntityExist(vehicle) and Entity(vehicle).state.aegisFleetId then break end
            Wait(150)
        end
        if stopping then return end
        if vehicle == 0 or not DoesEntityExist(vehicle) or not Entity(vehicle).state.aegisFleetId then
            notify('Le véhicule a été créé, mais il n’est pas encore visible.')
            return
        end
        local ped = PlayerPedId()
        if GetEntityType(vehicle) ~= 2 or not Entity(vehicle).state.aegisFleetId then return end
        local driver = GetPedInVehicleSeat(vehicle, -1)
        if not IsPedDeadOrDying(ped, true) and (driver == 0 or driver == ped) then
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
        end
    end)
end)

AddStateBagChangeHandler('aegisFleetInit', nil, function(bagName, key, payload)
    if stopping or type(payload) ~= 'table' or type(payload.props) ~= 'table' then return end
    CreateThread(function()
        for _ = 1, 80 do
            if stopping or not GetStateBagValue(bagName, key) then return end
            local vehicle = GetEntityFromStateBagName(bagName)
            if vehicle ~= 0 and DoesEntityExist(vehicle) and NetworkGetEntityOwner(vehicle) == PlayerId() then
                local data = GetStateBagValue(bagName, key)
                if not data or type(data.props) ~= 'table' then return end
                local applied = pcall(ESX.Game.SetVehicleProperties, vehicle, data.props)
                if not applied then return end
                if data.plate then SetVehicleNumberPlateText(vehicle, data.plate) end
                SetVehicleOnGroundProperly(vehicle)
                Entity(vehicle).state:set(key, nil, true)
                return
            end
            Wait(150)
        end
    end)
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then clearPeds() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == 'ox_target' then clearPeds(); return end
    if resource == GetCurrentResourceName() then
        stopping = true
        uiOpen, uiReady = false, false
        finishCapture(activeCapture, { ok = false, error = 'La ressource de garage est arrêtée.' })
        clearPeds()
        SetNuiFocus(false, false)
        SendNUIMessage({ type = 'close', sessionId = uiSession })
        local requests = pendingRequests
        pendingRequests = {}
        for _, finish in pairs(requests) do
            finish({ ok = false, error = 'La ressource de garage est arrêtée.' })
        end
    end
end)
