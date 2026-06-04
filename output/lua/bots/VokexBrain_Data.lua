-- VokexBrain_Data.lua
-- Combat AI data for Vokex bots.
-- Vokex uses SwipeShadowStep (melee swipe + ShadowStep blink) as primary weapon.
-- This file defines kVokexBrainActions (attack logic overriding FadeBrain's SwipeBlink check).
-- kVokexBrainObjectives is re-used from kFadeBrainObjectives since the objectives
-- (retreat to hive, explore, respond to threats, etc.) are identical for Vokex.

local kVokexMeleeRange   = 1.8    -- SwipeShadowStep.kRange = 1.6 + fuzzy margin
local kVokexEngageRange  = 50.0   -- maximum range at which a Vokex will engage

-- ---------------------------------------------------------------------------
-- Per-Vokex attack urgency (mirrors Prowler urgency but tuned for a Fade-tier melee fighter)
-- ---------------------------------------------------------------------------
local function GetVokexAttackUrgency(bot, vokex, mem)
    PROFILE("VokexBrain_Data - GetVokexAttackUrgency")

    local teamBrain = bot.brain.teamBrain

    local target = Shared.GetEntity(mem.entId)
    if not HasMixin(target, "Live") or not target:GetIsAlive() then
        return nil
    end
    if target.GetTeamNumber and target:GetTeamNumber() == vokex:GetTeamNumber() then
        return nil
    end

    local numOthers = teamBrain:GetNumOthersAssignedToEntity(vokex, mem.entId)
    local dist = vokex:GetOrigin():GetDistance(target:GetOrigin())

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
        [kMinimapBlipType.Exo]           = numOthers >= 4 and 0.4 or 1.6,
        [kMinimapBlipType.Marine]        = numOthers >= 2 and 0.4 or 1.5,
        [kMinimapBlipType.JetpackMarine] = numOthers >= 1 and 0.4 or 1.4,
        [kMinimapBlipType.Sentry]        = numOthers >= 3 and 0.4 or 1.3,
    }

    if activeUrgencies[mem.btype] then
        local isInCombat = HasMixin(vokex, "Combat") and vokex:GetIsInCombat()
        if dist < 15 or isInCombat then
            numOthers = 0
        end
        activeUrgencies =
        {
            [kMinimapBlipType.Exo]           = numOthers >= 4 and 0.4 or 1.6,
            [kMinimapBlipType.Marine]        = numOthers >= 2 and 0.4 or 1.5,
            [kMinimapBlipType.JetpackMarine] = numOthers >= 1 and 0.4 or 1.4,
            [kMinimapBlipType.Sentry]        = numOthers >= 3 and 0.4 or 1.3,
        }
        return activeUrgencies[mem.btype] + closeBonus + (dist < 20 and mem.threat or 0.0)
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Executor: perform the Vokex melee attack toward bestMem
-- ---------------------------------------------------------------------------
local kExecVokexAttackAction = function(move, bot, brain, vokex, action)
    PROFILE("VokexBrain_Data - ExecVokexAttack")

    local mem = action.bestMem
    if not mem then return end

    local eyePos = vokex:GetEyePos()
    local target = Shared.GetEntity(mem.entId)
    local aimPos

    if target ~= nil then
        local sighted = not HasMixin(target, "LOS") or target:GetIsSighted()
        aimPos = sighted and GetBestAimPoint(target) or (mem.lastSeenPos + Vector(0, 0.5, 0))
    else
        aimPos = mem.lastSeenPos + Vector(0, 0.5, 0)
    end

    local distance = target and GetDistanceToTouch(eyePos, target) or 999.0

    -- Ensure SwipeShadowStep is the active weapon
    vokex:SetActiveWeapon("swipeshadowstep")

    -- Face the target
    bot:GetMotion():SetDesiredViewTarget(aimPos)

    if distance <= kVokexMeleeRange + math.random() * 0.15 then
        -- Within melee range: fire and assign to target for load-balancing
        brain.teamBrain:UnassignBot(bot)
        brain.teamBrain:AssignBotToMemory(bot, mem)
        if bot.aim then
            bot.aim:UpdateAim(target or nil, aimPos, kBotAccWeaponGroup.Swipe)
        end
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
    end

    -- Always move toward the target to close melee range
    bot:GetMotion():SetDesiredMoveTarget(aimPos)
end

-- ---------------------------------------------------------------------------
-- Actions table for VokexBrain (replaces kFadeBrainActions)
-- Key fix: checks weapon:isa("SwipeShadowStep") instead of weapon:isa("SwipeBlink")
-- ---------------------------------------------------------------------------
kVokexBrainActions =
{
    ------------------------------------------
    -- Attack
    ------------------------------------------
    function(bot, brain, vokex)
        PROFILE("VokexBrain_Data:attack")

        local name = "attack"
        local memories = GetTeamMemories(vokex:GetTeamNumber())
        local bestUrgency, bestMem = GetMaxTableEntry(memories,
            function(mem)
                return GetVokexAttackUrgency(bot, vokex, mem)
            end)

        local weapon = vokex:GetActiveWeapon()
        -- Vokex primary weapon is SwipeShadowStep (mapName "swipeshadowstep")
        local canAttack = weapon ~= nil and weapon:isa("SwipeShadowStep")

        local eHP = vokex:GetHealthScalar()

        -- Don't attack if we should be retreating
        local sdb = brain:GetSenses()
        local retreatInfo = sdb and sdb:Get("retreatThreshold")
        if retreatInfo and retreatInfo.retreat then
            canAttack = false
        end

        local weight = 0.0

        if canAttack and bestMem ~= nil then
            local dist = select(2, GetTunnelDistanceForAlien(vokex, bestMem.lastSeenPos))
            if dist <= kVokexEngageRange and eHP > 0.55 then
                weight = 60
            elseif dist <= 15 then
                weight = 60
            end
        end

        return
        {
            name       = name,
            weight     = weight,
            bestMem    = bestMem,
            fastUpdate = true,
            perform    = kExecVokexAttackAction,
        }
    end,

    CreateAlienInterruptAction(),
}
