
function HydraStructureAbility:GetEnergyCost()
    return 30
end

function HydraStructureAbility:GetMaxStructures(biomass)
    return math.min(4, 2 + math.floor(biomass / 6))
end