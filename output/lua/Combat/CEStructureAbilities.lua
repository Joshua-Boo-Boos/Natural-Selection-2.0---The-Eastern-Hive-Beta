-- lua/Combat/CEStructureAbilities.lua
-- Combat Engineers: the structures a CE marine can place with the Combat Builder.
--
-- CombatBuilder's "structure ability" interface is a small set of lookups (SentryAbility and
-- ArmoryAbility are the originals). The ten CE structures differ only in tech id, placement rule and
-- cap, so they are produced by one factory instead of ten near-identical files.
--
-- IMPORTANT: CombatBuilder and GUIMarineBuildMenu call these inconsistently - sometimes with a colon
-- (`ability:GetDropStructureId()`) and sometimes with a dot (`ability.GetDropRange()`). The existing
-- abilities work only because none of them touch `self`. Every method here must obey the same rule:
-- NEVER reference self, take everything from the closure.

local kUpVector = Vector(0, 1, 0)
local kExtents  = Vector(0.4, 0.5, 0.4)

-- Snap radius for structures that must sit on a Resource Point or Tech Point. Generous enough that a
-- marine standing at a nozzle can place without pixel-hunting.
local kAttachSnapRadius = 3.0

-- CE structures are placed further out than the vanilla Combat structures (Sentry/Armory keep
-- kMarineBuildRadius): the ghost sat uncomfortably close to the marine's feet at that range,
-- especially for large structures like Command Station.
local kCombatEngineersDropRange = kMarineBuildRadius * 1.7

local function IsPathable(position)
    local noBuild = Pathing.GetIsFlagSet(position, kExtents, Pathing.PolyFlag_NoBuild)
    local walk    = Pathing.GetIsFlagSet(position, kExtents, Pathing.PolyFlag_Walk)
    return not noBuild and walk
end

-- Standard free-placement rule: level ground, walkable, clear of anything else constructible.
local function IsFreePlacementValid(position, surfaceNormal)

    if not surfaceNormal then return false end
    if not IsPathable(position) then return false end
    if surfaceNormal:DotProduct(kUpVector) <= 0.9 then return false end

    return #GetEntitiesWithMixinWithinRange("Construct", position, kMarineBuildBlockRadius) == 0
end

-- ============================================================
-- Structure definitions
-- ============================================================
-- attachClassTechId ~= nil means the structure must snap to a free attach entity (Resource Point for
-- an Extractor, Tech Point for a Command Station), read from kStructureAttachClass in its tech data.
-- Order here IS the build-menu order (see CombatBuilder.lua, which places the vanilla Sentry and
-- Supply Depot AFTER this whole list rather than before it). Sentry Battery and Command Station lead
-- so they land on page 1 where Sentry/Supply Depot used to be; Sentry/Supply Depot land on page 3
-- where these two used to be.
local kCEStructures =
{
    { techId = kTechId.SentryBattery                   },
    { techId = kTechId.CommandStation,  attach = true  },
    { techId = kTechId.Extractor,       attach = true  },
    { techId = kTechId.InfantryPortal                  },
    { techId = kTechId.Armory                          },
    { techId = kTechId.ArmsLab                         },
    { techId = kTechId.Observatory                     },
    { techId = kTechId.RoboticsFactory                 },
    { techId = kTechId.PhaseGate                       },
    { techId = kTechId.PrototypeLab                    },
}

-- Find the free attach entity (Resource Point / Tech Point) a position would snap to, or nil.
function GetCEAttachEntity(techId, position)
    return GetAttachEntity(techId, position, kAttachSnapRadius)
end

local function MakeAbility(def)

    local techId = def.techId

    -- Resolved LAZILY, not at construction. This file is loaded from CombatBuilder.lua, which hooks
    -- lua/Weapons/Marine/Welder.lua; the tech DATA table may not be built yet at that point, so a
    -- LookupTechData here could return nil and permanently bake it in.
    local function GetMapName()
        return LookupTechData(techId, kTechDataMapName)
    end

    local ability = {}

    function ability:GetDropStructureId() return techId end
    function ability:GetDropMapName()     return GetMapName() end
    function ability:GetDropClassName()   return GetMapName() end
    function ability:GetSuffixName()      return EnumToString(kTechId, techId) end
    function ability:GetDropRange()       return kCombatEngineersDropRange end
    function ability:GetStoreBuildId()    return false end
    function ability:AllowBackfacing()    return false end
    function ability:GetEnergyCost()      return kDropStructureEnergyCost end
    function ability:GetGhostModelName()  return LookupTechData(techId, kTechDataModel) end

    -- Only Sentry and Supply Depot have per-player caps. CE structures are either uncapped or capped
    -- at TEAM level (Arms Labs), which is enforced in IsAllowed rather than here, so that no new
    -- per-structure networked counter is needed on the Combat Builder.
    function ability:GetMaxStructures() return -1 end

    -- Free-placement CE structures use a two-click flow: the first click LOCKS the position (the
    -- ghost then only rotates as the player looks around, re-validated every frame); the second
    -- click confirms whatever orientation is showing at that moment. Attach structures (Extractor,
    -- Command Station) skip this - their orientation is always forced to match the attach point
    -- regardless of how the player is looking (see ModifyCoords below), so a rotation step would be
    -- a no-op click for no reason.
    function ability:GetRequiresOrientationClick()
        return not def.attach
    end

    function ability:GetIsPositionValid(position, player, surfaceNormal)

        if def.attach then
            -- Must sit on a FREE attach entity. Ground flatness is irrelevant: the structure snaps
            -- to the attach point's own origin.
            return GetCEAttachEntity(techId, position) ~= nil
        end

        return IsFreePlacementValid(position, surfaceNormal)
    end

    -- Attach structures (Extractor -> Resource Point, Command Station -> Tech Point) are the ONE
    -- case where the aim ray is EXPECTED to hit an entity (the attach point's own collision) and
    -- where standing close to that attach point is the point, not a foul. Without this,
    -- CombatBuilder:GetPositionForStructure's generic rules permanently invalidate the placement:
    --   1. it only accepts trace.entity == nil (a bare-world hit) as valid, and a tech point/nozzle
    --      IS an entity, so aiming anywhere near one currently guarantees an invalid placement;
    --   2. GetPointBlocksAttachEntities() independently vetoes any position NEAR an attach point,
    --      which is exactly backwards for the ability whose entire job is to BE at one.
    -- Both generic rules are skipped for attach abilities; GetIsPositionValid above (a free attach
    -- entity within snap range) is the sole authority instead.
    if def.attach then
        function ability:GetAllowsAttachEntityHit()
            return true
        end
    end

    -- Snap the ghost (and therefore the placed structure) onto the attach entity, so the preview
    -- shows exactly where it will end up - AND lock its orientation to the attach entity's own
    -- angles. Without this the structure's facing follows the player's camera as they orbit the
    -- point (Coords.GetLookIn derives it from the aim direction), which is both visually wrong and
    -- means the model can end up misaligned with the socket it is snapping into.
    if def.attach then
        function ability:ModifyCoords(coords)
            local attachEnt = GetCEAttachEntity(techId, coords.origin)
            if attachEnt then
                coords.origin = Vector(attachEnt:GetOrigin())
                local fixed = Angles(0, attachEnt:GetAngles().yaw, 0):GetCoords()
                coords.xAxis = fixed.xAxis
                coords.yAxis = fixed.yAxis
                coords.zAxis = fixed.zAxis
            end
        end
    end

    -- Called from BOTH sides (the build menu greys buttons with it, the server's drop path gates on
    -- it), so it must not touch server-only Team methods - everything here comes from the shared
    -- lookups in CombatEngineers_Shared.lua, which read networked state.
    function ability:IsAllowed(player)

        if not player or not GetCombatEngineersActive(player) then
            return false
        end

        -- The structure's OWN tech-tree prerequisites, so a CE marine can never place something the
        -- commander could not: Prototype Lab needs Advanced Armory, Phase Gate needs Phase Tech,
        -- Observatory needs an Infantry Portal and an Armory, Sentry Battery needs a Robotics
        -- Factory, Robotics Factory needs an Infantry Portal. Reading the node keeps all of that in
        -- one place (MarineTeam:InitTechTree) instead of duplicating it here to drift later.
        local node = GetTechNode and GetTechNode(techId)
        if node and not node:GetAvailable() then
            return false
        end

        return GetCombatEngineersCanBuild(techId, player:GetTeamNumber())
    end

    -- Attach structures need the attach entity wired up, which the generic CreateEntity fallback in
    -- CombatBuilder:CreateStructure does not do. Everything else uses that fallback.
    if def.attach then
        function ability:CreateStructure(coords, player)

            local attachEnt = GetCEAttachEntity(techId, coords.origin)
            if not attachEnt then
                return false
            end

            local structure = CreateEntity(GetMapName(), attachEnt:GetOrigin(), player:GetTeamNumber())
            if structure and structure.SetAttached then
                structure:SetAttached(attachEnt)
            end

            return structure
        end
    else
        function ability:CreateStructure()
            return false
        end
    end

    return ability
end

-- Built once. kCEStructureAbilities is keyed by tech id for lookups; kCEStructureAbilityOrder is the
-- ordered list CombatBuilder appends to kSupportedStructures.
--
-- Deliberately driven by this file's OWN kCEStructures rather than by a list in
-- CombatEngineers_Shared.lua: that file is hooked on lua/TechData.lua while this one is reached from
-- lua/Weapons/Marine/Welder.lua, and depending on the relative order of two unrelated file hooks to
-- avoid indexing a nil table is exactly the kind of load-order fault that only shows up on someone
-- else's machine.
kCEStructureAbilities     = {}
kCEStructureAbilityOrder  = {}

for _, def in ipairs(kCEStructures) do
    local ability = MakeAbility(def)
    kCEStructureAbilities[def.techId] = ability
    table.insert(kCEStructureAbilityOrder, ability)
end
