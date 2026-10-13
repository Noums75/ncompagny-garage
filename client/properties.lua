EnterpriseGarageProperties = {}

-- The ESX functions published by okokGarage use native wheel/window indices.
-- JSON persistence converts index 0 to an object key ("0"); restore numbers
-- before ESX applies these legacy properties, including under native OAL.
function EnterpriseGarageProperties.forApply(properties)
    local prepared = {}
    for key, value in pairs(properties) do prepared[key] = value end
    for _, field in ipairs({ 'tireHealth', 'tireBurstState', 'tireBurstCompletely', 'windowStatus', 'doorStatus' }) do
        if type(properties[field]) == 'table' then
            local indexed = {}
            for key, value in pairs(properties[field]) do
                local index = tonumber(key)
                if index and index >= 0 and index <= 1500 and index % 1 == 0 then
                    indexed[index] = value
                else indexed[key] = value end
            end
            prepared[field] = indexed
        end
    end
    return prepared
end
