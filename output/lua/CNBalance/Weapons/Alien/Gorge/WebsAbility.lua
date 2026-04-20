
function WebsAbility:GetMaxStructures(biomass)
    return math.min(4, 2 + math.floor(biomass / 6))
end