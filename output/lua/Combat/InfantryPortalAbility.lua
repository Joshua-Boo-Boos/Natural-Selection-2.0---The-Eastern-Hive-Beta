class 'InfantryPortalAbility' (Entity)

local kExtents = Vector(0.4, 0.5, 0.4)

local function IsPathable(position)
    local noBuild = Pathing.GetIsFlagSet(position, kExtents, Pathing.PolyFlag_NoBuild)
    local walk = Pathing.GetIsFlagSet(position, kExtents, Pathing.PolyFlag_Walk)
    return not noBuild and walk
end

local kUpVector = Vector(0, 1, 0)

function InfantryPortalAbility:GetIsPositionValid(position, player, surfaceNormal)
    local valid = false

    if surfaceNormal then
        if not IsPathable(position) then
            valid = false
        elseif surfaceNormal:DotProduct(kUpVector) > 0.9 then
            valid = true

            if #GetEntitiesWithMixinWithinRange("Construct", position, kMarineBuildBlockRadius) > 0 then
                valid = false
            end

            -- Require enough vertical clearance above the IP for marines to spawn
            if valid then
                local kMinClearance = 2.2  -- approximate marine standing height + margin
                local traceStart = position + Vector(0, 0.1, 0)
                local traceEnd = position + Vector(0, kMinClearance, 0)
                local trace = Shared.TraceRay(traceStart, traceEnd, CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, EntityFilterAll())
                if trace.fraction < 1 then
                    valid = false
                end
            end
        end
    end

    return valid
end

function InfantryPortalAbility:AllowBackfacing()
    return false
end

function InfantryPortalAbility:GetDropRange()
    return kMarineBuildRadius
end

function InfantryPortalAbility:GetStoreBuildId()
    return false
end

function InfantryPortalAbility:GetEnergyCost(player)
    return kDropStructureEnergyCost
end

function InfantryPortalAbility:GetGhostModelName(ability)
    return InfantryPortal.kModelName
end

function InfantryPortalAbility:GetDropStructureId()
    return kTechId.InfantryPortal
end

function InfantryPortalAbility:GetSuffixName()
    return "InfantryPortal"
end

function InfantryPortalAbility:GetDropClassName()
    return "InfantryPortal"
end

function InfantryPortalAbility:GetDropMapName()
    return InfantryPortal.kMapName
end

function InfantryPortalAbility:CreateStructure()
    return false
end

function InfantryPortalAbility:IsAllowed(player)
    return true
end

function InfantryPortalAbility:GetMaxStructures(player)
    return 2
end
