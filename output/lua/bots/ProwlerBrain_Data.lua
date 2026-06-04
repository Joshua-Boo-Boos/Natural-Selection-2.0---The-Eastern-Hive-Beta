-- ProwlerBrain_Data.lua
-- Combat AI data for Prowler bots.
-- Prowler uses VolleyRappel (ranged spread projectile) as primary weapon.
-- This file defines kProwlerBrainActions (attack logic) and helper functions.
-- kProwlerBrainObjectives is re-used from kSkulkBrainObjectives since the Skulk
-- objectives (explore, defend hive, respond to threat, etc.) are identical for Prowler.
-- The Evolve objective inside kSkulkBrainObjectives is overridden globally by
-- TEHBotManager.lua so Prowler bots correctly handle their assigned lifeform.

local kProwlerFireRange    = 10.0   -- effective fire range for VolleyRappel
local kProwlerEngageRange  = 50.0   -- maximum range at which a Prowler will engage

-- ---------------------------------------------------------------------------
-- Per-Prowler attack urgency (local copy, similar to Skulk's but no bite-range bonus)
-- ---------------------------------------------------------------------------
local function GetProwlerAttackUrgency(bot, prowler, mem)
    PROFILE("ProwlerBrain_Data - GetProwlerAttackUrgency")

    local teamBrain = bot.brain.teamBrain

    local target = Shared.GetEntity(mem.entId)
    if not HasMixin(target, "Live") or not target:GetIsAlive() then
        return nil
    end
    if target.GetTeamNumber and target:GetTeamNumber() == prowler:GetTeamNumber() then
        return nil
    end

    local numOthers = teamBrain:GetNumOthersAssignedToEntity(prowler, mem.entId)
    local dist = prowler:GetOrigin():GetDistance(target:GetOrigin())

    local closeBonus = 0
    if dist < 20 then
        closeBonus = math.max(0, (dist * -0.1) + 2)
    end

    if target.GetHealthScalar and target:GetHealthScalar() < 0.3 then
        closeBonus = closeBonus + (0.3 - target:GetHealthScalar()) * 3
    end

    -- Passive targets (structures)
    local passiveUrgencies =
    {
        [kMinimapBlipType.ARC]              = numOthers >= 2 and 0.4 or 0.95,
        [kMinimapBlipType.InfantryPortal]   = numOthers >= 3 and 0.5 or 0.9,
        [kMinimapBlipType.PhaseGate]        = numOthers >= 3 and 0.8 or 0.9,
        [kMinimapBlipType.CommandStation]   = numOthers >= 4 and 0.3 or 0.85,
        [kMinimapBlipType.Observatory]      = numOthers >= 2 and 0.2 or 0.8,
        [kMinimapBlipType.ArmsLab]          = numOthers >= 3 and 0.2 or 0.6,
        [kMinimapBlipType.PrototypeLab]     = numOthers >= 1 and 0.2 or 0.55,
        [kMinimapBlipType.Extractor]        = numOthers >= 2 and 0.2 or 0.5,
        [kMinimapBlipType.Armory]           = numOthers >= 2 and 0.2 or 0.5,
        [kMinimapBlipType.RoboticsFactory]  = numOthers >= 2 and 0.2 or 0.5,
        [kMinimapBlipType.MAC]              = numOthers >= 1 and 0.2 or 0.4,
        [kMinimapBlipType.PowerPoint]       = numOthers >= 1 and 0.2 or 0.3,
    }

    if passiveUrgencies[mem.btype] ~= nil then
        if target.GetIsGhostStructure and target:GetIsGhostStructure() and
                (mem.btype ~= kMinimapBlipType.Extractor and mem.btype ~= kMinimapBlipType.CommandStation) then
            return nil
        end

        local nearestThreat = bot.brain:GetSenses():Get("nearestThreat")
        if nearestThreat and nearestThreat.distance and nearestThreat.distance <= 8 then
            return nil
        end

        return passiveUrgencies[mem.btype] + closeBonus
    end

    -- Active threats (players, Exo, Sentry)
    local activeUrgencies =
    {
        [kMinimapBlipType.Exo]          = numOthers >= 4 and 0.4 or 1.6,
        [kMinimapBlipType.Marine]       = numOthers >= 2 and 0.4 or 1.5,
        [kMinimapBlipType.JetpackMarine]= numOthers >= 1 and 0.4 or 1.4,
        [kMinimapBlipType.Sentry]       = numOthers >= 3 and 0.4 or 1.3,
    }

    if activeUrgencies[mem.btype] then
        local isInCombat = HasMixin(prowler, "Combat") and prowler:GetIsInCombat()
        if dist < 15 or isInCombat then
            numOthers = 0
        end
        -- re-evaluate with correct numOthers
        activeUrgencies =
        {
            [kMinimapBlipType.Exo]          = numOthers >= 4 and 0.4 or 1.6,
            [kMinimapBlipType.Marine]       = numOthers >= 2 and 0.4 or 1.5,
            [kMinimapBlipType.JetpackMarine]= numOthers >= 1 and 0.4 or 1.4,
            [kMinimapBlipType.Sentry]       = numOthers >= 3 and 0.4 or 1.3,
        }
        return activeUrgencies[mem.btype] + closeBonus + (dist < 20 and mem.threat or 0.0)
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Executor: perform the Prowler ranged attack
-- ---------------------------------------------------------------------------
local kExecProwlerAttackAction = function(move, bot, brain, prowler, action)
    PROFILE("ProwlerBrain_Data - ExecProwlerAttack")

    local mem = action.bestMem
    if not mem then return end

    local eyePos = prowler:GetEyePos()
    local target = Shared.GetEntity(mem.entId)

    local aimPos
    if target ~= nil then
        local sighted = not HasMixin(target, "LOS") or target:GetIsSighted()
        aimPos = sighted and GetBestAimPoint(target) or (mem.lastSeenPos + Vector(0, 0.5, 0))
    else
        aimPos = mem.lastSeenPos + Vector(0, 0.5, 0)
    end

    local distance = target and GetDistanceToTouch(eyePos, target) or 999.0

    -- Ensure VolleyRappel is the active weapon
    prowler:SetActiveWeapon("volley")

    -- Face the target
    bot:GetMotion():SetDesiredViewTarget(aimPos)

    if distance < kProwlerFireRange then
        -- Within effective range: fire and assign to this target for load-balancing
        brain.teamBrain:UnassignBot(bot)
        brain.teamBrain:AssignBotToMemory(bot, mem)
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
    end

    -- Always move toward the target
    bot:GetMotion():SetDesiredMoveTarget(aimPos)
end

-- ---------------------------------------------------------------------------
-- Actions table for ProwlerBrain
-- (replaces kSkulkBrainActions - fixes canAttack for VolleyRappel)
-- ---------------------------------------------------------------------------
kProwlerBrainActions =
{
    ------------------------------------------
    -- Attack
    ------------------------------------------
    function(bot, brain, prowler)
        PROFILE("ProwlerBrain_Data:attack")

        local name = "attack"
        local memories = GetTeamMemories(prowler:GetTeamNumber())

        local bestUrgency, bestMem = GetMaxTableEntry(memories,
            function(mem)
                return GetProwlerAttackUrgency(bot, prowler, mem)
            end)

        local weapon = prowler:GetActiveWeapon()
        -- Prowler attacks with VolleyRappel (mapName "volley")
        local canAttack = weapon ~= nil and weapon:GetMapName() == "volley"

        local weight = 0.0

        if canAttack and bestMem ~= nil then
            local dist = 0.0
            local attackTargetEnt = Shared.GetEntity(bestMem.entId)
            if attackTargetEnt ~= nil then
                dist = select(2, GetTunnelDistanceForAlien(prowler, attackTargetEnt))
            else
                dist = select(2, GetTunnelDistanceForAlien(prowler, bestMem.lastSeenPos))
            end

            if dist <= kProwlerEngageRange then
                weight = 8
            end

            local eHP = prowler:GetHealthScalar()
            if eHP < 0.4 and dist > 12 then
                weight = 0
            end

            weight = weight + weight * (bot.aggroAbility or 0)
        end

        return
        {
            name = name,
            weight = weight,
            bestMem = bestMem,
            perform = kExecProwlerAttackAction
        }
    end,

    CreateAlienInterruptAction()
}
