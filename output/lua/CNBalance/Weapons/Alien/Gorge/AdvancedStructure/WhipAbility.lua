Script.Load("lua/CNBalance/Weapons/Alien/Gorge/AdvancedStructure/AdvancedStructureAbility.lua")

class 'WhipAbility' (AdvancedStructureAbility)

function WhipAbility:GetDropStructureId()
    return kTechId.Whip
end

function WhipAbility:OverrideInfestationCheck(_trace)
    return true
end

function WhipAbility:GetMaxStructures(biomass)
    if biomass >= 10 then return 3
    elseif biomass >= 5 then return 2
    else return 1
    end
end

function WhipAbility:GetStructurePlaceSide(player)
    return GetHasTech(player,kTechId.OriginForm)
            and AdvancedStructureAbility.kStructurePlaceSide.All
            or AdvancedStructureAbility.kStructurePlaceSide.Upward
end
