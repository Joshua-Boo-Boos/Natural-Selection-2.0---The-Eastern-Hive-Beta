
function WebsAbility:GetMaxStructures(biomass)
    if biomass >= 8 then return 4
    elseif biomass >= 4 then return 3
    else return 2
    end
end