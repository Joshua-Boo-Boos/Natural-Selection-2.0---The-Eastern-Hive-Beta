
function HydraStructureAbility:GetEnergyCost()
    return 30
end

function HydraStructureAbility:GetMaxStructures(biomass)
    if biomass >= 10 then return 4
    elseif biomass >= 6 then return 3
    else return 2
    end
end