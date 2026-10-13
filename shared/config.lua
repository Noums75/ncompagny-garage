Config = {}

Config.Command = 'egarage'
Config.CommandDescription = 'Ouvrir la console staff des garages d’entreprise'
Config.RequestTimeoutMs = 15000 -- ms
Config.SessionDurationSeconds = 1800 -- secondes
Config.SyncOwnedVehicleStored = true -- false si la colonne stored est absente
Config.MarkerDistance = 32.0
Config.InteractDistance = 2.8
Config.SpawnCheckRadius = 4.5
Config.StoreDistance = 18.0
Config.RegisterDistance = 7.0
Config.MaxGarageName = 60
Config.MaxVehicleLabel = 60
Config.MaxFleetPerGarage = 150
Config.MaxPointLabel = 40
Config.MaxPointDistance = 250.0
Config.MaxPointsPerKind = 12
Config.MaxCategories = 30
Config.MaxCategoryName = 40

Config.MinGarageAccessDistance = 12.0
Config.MinCrossGaragePointDistance = 10.0
Config.GarageOpenDistance = 4.0
Config.ManagementDistance = 25.0
Config.PedRenderDistance = 70.0
Config.PedModelDefault = 's_m_m_security_01'
Config.PedScenarioDefault = 'WORLD_HUMAN_CLIPBOARD'
Config.PedModelsAllowed = { 's_m_m_security_01', 's_m_m_dockwork_01', 's_m_y_cop_01', 's_f_y_cop_01', 's_m_m_autoshop_01', 'a_m_m_business_01' }
Config.AdminGroups = { 'admin', 'superadmin' }
Config.AdminAce = 'enterprise_garage.admin'

Config.SocietyOwnerFormats = { 'society_%s', 'society:%s', '%s' }
Config.OkokGarageBridge = {
    Enabled = true,
    ResourceName = 'okokGarage',
    EventPrefix = 'okokGarage', -- Config.EventPrefix documenté côté okokGarage
    RevokeSourceKeys = true,
    AutoImportOnStore = true,
    -- Un employé ayant fleet_add peut confier son propre véhicule à la flotte.
    -- Le propriétaire reste inchangé et sera restauré lors du retrait.
    AllowEmployeeOwnedVehicles = true
}
Config.DefaultPermissions = {
    access = 0,
    withdraw = 0,
    store = 0,
    manage = 4,
    fleet_add = 3,
    fleet_remove = 4,
    categories = 4,
    assign_category = 3,
    rename = 3
}

Config.KeySyncIntervalSeconds = 180
Config.Locale = 'fr'

Config.Marker = {
    type = 36,
    scale = vector3(0.85, 0.85, 0.85),
    color = { r = 94, g = 162, b = 255, a = 165 }
}
