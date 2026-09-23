Script.Load("lua/Weapons/Alien/StructureAbility.lua")

class 'AttachStructureAbility' (StructureAbility)

AttachStructureAbility.kDropRange = 6.5
AttachStructureAbility.kAttachToPoints = true

function AttachStructureAbility:GetDropRange()
    return AttachStructureAbility.kDropRange
end

function AttachStructureAbility:GetGhostModelName(ability)       --TD-FIXME Needs means to swap mat

    --local player = ability:GetParent()
    --if player and player:isa("Gorge") then
    --
    --    local clientVariants = GetAndSetVariantOptions()
    --    local variant = clientVariants.alienStructuresVariant
    --
    --    if variant == kAlienStructureVariants.Shadow or variant == kHydraVariants.Auric then
    --        return Hydra.kModelNameShadow
    --    elseif variant == kHydraVariants.Abyss then
    --        return Hydra.kModelNameAbyss
    --    end
    --
    --end

    return LookupTechData(self:GetDropStructureId(),kTechDataModel)

end

--[[
    THE TECH POINT THE PLAYER IS PLAINLY STANDING AT.

    This used to ask GetAttachEntity for a tech point within kStructureSnapRadius (4m) of the exact spot the
    ghost was resting on. A tech point is a big model: aim at it and the surface your view actually lands on
    is often further than 4m from its origin, and the floor around it always is. Nothing snapped, the ghost
    floated loose around the hive spot instead of sitting on it, and the Hive could not be dropped at all.

    So the search is the ability's own DROP RANGE, measured on the floor plane (XZ), and it takes the NEAREST
    FREE tech point - the same helper the Hive itself uses. Out of range is still out of range, and an
    occupied tech point is still refused, so nothing is placed anywhere it should not be.
]]
function AttachStructureAbility:GetAttachTarget(position)

    local techId = self:GetDropStructureId()
    local range = math.max(self:GetDropRange() or 0, kStructureSnapRadius)

    return GetNearestFreeAttachEntity(techId, position, range)
        or GetAttachEntity(techId, position, kStructureSnapRadius)

end

function AttachStructureAbility:GetIsPositionValid(position, player, surfaceNormal)
    return self:GetAttachTarget(position) ~= nil
end

function AttachStructureAbility:ModifyCoords(coords)
    local techId = self:GetDropStructureId()
    
    local entity = self:GetAttachTarget(coords.origin)
    if entity then
            
        local dstCoords = entity:GetCoords()
        coords.origin = dstCoords.origin
        coords.zAxis = dstCoords.zAxis
        coords.yAxis = dstCoords.yAxis
        coords.xAxis = dstCoords.xAxis
    end
    
    local spawnHeight = LookupTechData(techId, kTechDataSpawnHeightOffset, 0)
    if spawnHeight then
        coords.origin = coords.origin + Vector(0,spawnHeight,0)
    end
end


--[[
    THE THREE NAMES EVERY STRUCTURE ABILITY MUST ANSWER.

    StructureAbility's own versions of these are assert(false) - "a child class has to override me". This
    class never did, so anything that asked an attach ability (the Hives and the Harvester) for its map
    name asserted and spammed the log: lua/Weapons/Alien/StructureAbility.lua:75: assertion failed!, raised
    once per frame while the ghost was up. Other mods' placement code asks for exactly this.

    Answered from the tech data, the same way AdvancedStructureAbility answers it.
]]
function AttachStructureAbility:GetDropMapName()
    return LookupTechData(self:GetDropStructureId(), kTechDataMapName)
end

function AttachStructureAbility:GetDropClassName()
    local techId = self:GetDropStructureId()
    local ok, name = pcall(EnumToString, kTechId, techId)
    return (ok and name) or LookupTechData(techId, kTechDataMapName)
end

function AttachStructureAbility:GetSuffixName()
    return LookupTechData(self:GetDropStructureId(), kTechDataMapName) or "structure"
end

function AttachStructureAbility:GetDropStructureId()
    assert(false,"Override this please")
    --return kTechId.BuildMenu
end

function AttachStructureAbility:CreateStructure(coords, player, structureAbility)

    local techId = self:GetDropStructureId()
    local mapName = LookupTechData(techId, kTechDataMapName)
    local newEnt = nil
    if mapName then
        local origin = coords.origin
        newEnt = CreateEntity( mapName, origin, player:GetTeamNumber() )

        -- Hook it up to attach entity
        -- The same tech point the ghost snapped to, found the same way.
        local attachEntity = self:GetAttachTarget(origin)
        if attachEntity then
            newEnt:SetAttached(attachEntity)
        end
        self:PostOnCreate(newEnt)
    end
    return newEnt
end

function AttachStructureAbility:PostOnCreate(_ent)
    
end

function AttachStructureAbility:GetEnergyCost()
    return 40 -- Todo: Make a balance var
end

function AttachStructureAbility:IsAllowed(player)
    return true
end

function AttachStructureAbility:GetMaxStructures(biomass)
    return -1
end