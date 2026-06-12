-- VokexBrain_Data.lua
-- Combat AI data for Vokex bots.
-- The Vokex is the alien equivalent of the Fade. Its weapons:
--   * SwipeShadowStep ("swipeshadowstep") — melee swipe (primary) + ShadowStep
--     dash (secondary). Always carried.
--   * AcidRocket ("acidrocket")           — ranged projectile (primary), Tier-2 tech.
-- Movement is ShadowStep (a blink-style dash, triggered by Move.SecondaryAttack
-- while holding either weapon — costs energy) or plain walking when close / low energy.
-- This file defines kVokexBrainActions; kVokexBrainObjectives is reused from
-- kFadeBrainObjectives (retreat to hive, explore, respond to threats, etc.).

local kVokexMeleeRange       = 1.8    -- SwipeShadowStep.kRange = 1.6 + fuzzy margin
local kVokexEngageRange      = 50.0   -- maximum range at which a Vokex will engage
local kVokexAcidRange        = 18.0   -- max range at which the bot will use AcidRocket
local kVokexAcidMinRange     = 3.0    -- below this, prefer swipe over AcidRocket
local kVokexShadowStepDist   = 7.0    -- target farther than this → ShadowStep to close
local kVokexShadowStepCD     = 1.2    -- seconds between ShadowStep dashes
local kVokexWeaponSwitchCD   = 0.4    -- min seconds between weapon switches (anti-thrash)

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
-- Executor: perform the Vokex attack toward bestMem.
-- Picks AcidRocket (ranged) or SwipeShadowStep (melee) by distance, walks/dashes
-- toward the target via ShadowStep, and fires the chosen weapon.
-- ---------------------------------------------------------------------------
local kExecVokexAttackAction = function(move, bot, brain, vokex, action)
    PROFILE("VokexBrain_Data - ExecVokexAttack")

    local mem = action.bestMem
    if not mem then return end

    local now    = Shared.GetTime()
    local eyePos = vokex:GetEyePos()
    local target = Shared.GetEntity(mem.entId)
    local aimPos, movePos

    if target ~= nil then
        local sighted = not HasMixin(target, "LOS") or target:GetIsSighted()
        aimPos  = sighted and GetBestAimPoint(target) or (mem.lastSeenPos + Vector(0, 0.5, 0))
        -- Walk toward the target's ground origin, NOT the elevated aim point — moving
        -- toward a point in the air is what stalled the bot's pathing before.
        movePos = target:GetOrigin()
    else
        aimPos  = mem.lastSeenPos + Vector(0, 0.5, 0)
        movePos = mem.lastSeenPos
    end

    local distance = target and GetDistanceToTouch(eyePos, target)
                     or eyePos:GetDistance(movePos)

    -- ---- Choose weapon: AcidRocket for ranged, SwipeShadowStep for melee. ----
    local hasAcid      = vokex:GetWeapon("acidrocket") ~= nil
    local hasClearShot = target ~= nil and bot.GetBotCanSeeTarget and bot:GetBotCanSeeTarget(target)
    local useAcid      = hasAcid and target ~= nil and hasClearShot and
                         distance > kVokexAcidMinRange and distance <= kVokexAcidRange
    local desiredWeapon = useAcid and "acidrocket" or "swipeshadowstep"

    -- Switch only when needed, and rate-limited: re-issuing SetActiveWeapon every
    -- frame resets the draw and interrupts the swipe animation (why melee "didn't
    -- swipe"). The cooldown also stops weapon thrash near the range boundary.
    local active     = vokex:GetActiveWeapon()
    local activeName  = active and active:GetMapName()
    if activeName ~= desiredWeapon and
            (not bot.vokex_nextWeaponSwitch or now >= bot.vokex_nextWeaponSwitch) then
        vokex:SetActiveWeapon(desiredWeapon)
        bot.vokex_nextWeaponSwitch = now + kVokexWeaponSwitchCD
    end

    -- Face the target.
    bot:GetMotion():SetDesiredViewTarget(aimPos)
    if bot.aim then
        bot.aim:UpdateAim(target or nil, aimPos, kBotAccWeaponGroup.Swipe)
    end

    brain.teamBrain:UnassignBot(bot)
    brain.teamBrain:AssignBotToMemory(bot, mem)

    if useAcid then
        -- Ranged: fire, and only close in if beyond effective acid range.
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
        if distance > kVokexAcidRange * 0.9 then
            bot:GetMotion():SetDesiredMoveTarget(movePos)
        else
            bot:GetMotion():SetDesiredMoveTarget(nil)
        end
        return
    end

    -- ---- Melee path ----
    bot:GetMotion():SetDesiredMoveTarget(movePos)

    if distance <= kVokexMeleeRange + math.random() * 0.15 then
        -- In range: swipe.
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
    else
        -- Out of range: ShadowStep-dash to close when far enough, with energy to
        -- spare (keep a reserve so swipes still have energy), and not already mid-dash.
        local ssCost = kVokexShadowStepEnergyCost or 20
        local canDash =
            distance > kVokexShadowStepDist and
            vokex:GetEnergy() > ssCost * 2 and
            not vokex:GetIsShadowStepping() and
            (not bot.vokex_nextShadowStep or now >= bot.vokex_nextShadowStep)

        if canDash then
            -- SetDesiredMoveTarget already aims the bot's movement input at the
            -- target; ShadowStep (secondary attack) boosts along that direction.
            move.commands = AddMoveCommand(move.commands, Move.SecondaryAttack)
            bot.vokex_nextShadowStep = now + kVokexShadowStepCD
        end
    end
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

        -- Gate on the always-present swipe weapon existing in inventory; the executor
        -- chooses swipe vs AcidRocket and switches to it when firing. Checking the
        -- ACTIVE weapon caused a deadlock: if a different weapon was active the weight
        -- stayed 0, the executor never ran, and the weapon was never switched.
        local canAttack = vokex:GetWeapon("swipeshadowstep") ~= nil

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
