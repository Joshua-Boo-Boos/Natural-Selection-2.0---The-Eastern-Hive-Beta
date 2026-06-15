-- VokexBrain_Data.lua
-- Combat AI for Vokex bots. Defines kVokexBrainActions used by VokexBrain:GetActions().
--
-- Weapons used (in priority order):
--   SwipeShadowStep ("swipeshadowstep", slot 1) — melee swipe; secondary = ShadowStep dash.
--                                                  Always available.
--   AcidRocket      ("acidrocket",       slot 3) — ranged projectile (tier-2 unlock).
--   VortexShadowStep("VortexShadowStep", slot 4) — close-range stab that creates a Vortex
--                                                   pulling field (tier-3 unlock).
--
-- Weapon selection each frame:
--   ≤ 1.9 m  + hasVortex             → VortexShadowStep (stab + Vortex pull)
--   3–18 m   + hasAcid + clear shot  → AcidRocket
--   otherwise                        → SwipeShadowStep (swipe; ShadowStep dash to close)

local kVokexMeleeRange       = 1.8    -- SwipeShadowStep.kRange 1.6 + fuzzy margin
local kVokexVortexRange      = 1.9    -- VortexShadowStep effective range
local kVokexEngageRange      = 50.0   -- maximum range to engage any target
local kVokexAcidRange        = 18.0   -- max effective AcidRocket range
local kVokexAcidMinRange     = 3.0    -- below this prefer melee over acid
local kVokexShadowStepDist   = 7.0    -- dash when target is farther than this
local kVokexShadowStepCD     = 1.2    -- seconds between ShadowStep dashes
local kVokexWeaponSwitchCD   = 0.4    -- min seconds between weapon switches (stops thrash)

-- ---------------------------------------------------------------------------
-- Attack urgency: ranks known threats/targets for this Vokex bot to engage.
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
                (mem.btype ~= kMinimapBlipType.Extractor and
                 mem.btype ~= kMinimapBlipType.CommandStation) then
            return nil
        end
        local nearestThreat = bot.brain:GetSenses():Get("nearestThreat")
        if nearestThreat and nearestThreat.distance and nearestThreat.distance <= 8 then
            return nil
        end
        return passiveUrgencies[mem.btype] + closeBonus
    end

    -- Active threats (players / Exo / Sentry)
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
-- Executor: runs each frame while the attack action is highest-weight.
-- Selects weapon by distance, switches rate-limited, fires or dashes.
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
        -- Use ground origin for movement target — moving toward an elevated aim point
        -- stalls ground pathing.
        movePos = target:GetOrigin()
    else
        aimPos  = mem.lastSeenPos + Vector(0, 0.5, 0)
        movePos = mem.lastSeenPos
    end

    local distance = target and GetDistanceToTouch(eyePos, target)
                     or eyePos:GetDistance(movePos)

    -- Available weapons
    local hasSwipe  = vokex:GetWeapon("swipeshadowstep")          ~= nil
    local hasAcid   = vokex:GetWeapon("acidrocket")               ~= nil
    local hasVortex = vokex:GetWeapon(VortexShadowStep.kMapName)  ~= nil

    local hasClearShot = target ~= nil and
                         bot.GetBotCanSeeTarget and bot:GetBotCanSeeTarget(target)

    -- Weapon selection
    local desiredWeapon
    if distance <= kVokexVortexRange and hasVortex then
        -- Tier-3: stab + Vortex pull — highest value at point-blank
        desiredWeapon = VortexShadowStep.kMapName
    elseif hasAcid and hasClearShot
            and distance >= kVokexAcidMinRange and distance <= kVokexAcidRange then
        -- Tier-2: ranged projectile at medium distance
        desiredWeapon = "acidrocket"
    else
        -- Default: melee swipe; ShadowStep to close
        desiredWeapon = "swipeshadowstep"
    end

    -- Switch only when needed and cooldown elapsed — issuing SetActiveWeapon every frame
    -- resets the draw animation and interrupts the attack.
    local active     = vokex:GetActiveWeapon()
    local activeName = active and active:GetMapName()
    if activeName ~= desiredWeapon and
            (not bot.vokex_nextWeaponSwitch or now >= bot.vokex_nextWeaponSwitch) then
        vokex:SetActiveWeapon(desiredWeapon)
        bot.vokex_nextWeaponSwitch = now + kVokexWeaponSwitchCD
    end

    bot:GetMotion():SetDesiredViewTarget(aimPos)
    if bot.aim then
        bot.aim:UpdateAim(target or nil, aimPos, kBotAccWeaponGroup.Swipe)
    end

    brain.teamBrain:UnassignBot(bot)
    brain.teamBrain:AssignBotToMemory(bot, mem)

    -- ---- AcidRocket (ranged) path ----
    if desiredWeapon == "acidrocket" then
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
        -- Close in slightly only if at the very edge of effective range
        if distance > kVokexAcidRange * 0.9 then
            bot:GetMotion():SetDesiredMoveTarget(movePos)
        else
            bot:GetMotion():SetDesiredMoveTarget(nil)
        end
        return
    end

    -- ---- Melee path (SwipeShadowStep or VortexShadowStep) ----
    bot:GetMotion():SetDesiredMoveTarget(movePos)

    local meleeRange = (desiredWeapon == VortexShadowStep.kMapName)
                       and kVokexVortexRange or kVokexMeleeRange

    if distance <= meleeRange + math.random() * 0.15 then
        -- In range: attack
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
    else
        -- Out of range: ShadowStep-dash to close when far enough, with energy reserve
        -- (keep 2× cost so swipes still have energy after dashing).
        local ssCost = kVokexShadowStepEnergyCost or 20
        local canDash =
            distance > kVokexShadowStepDist and
            vokex:GetEnergy() > ssCost * 2 and
            not vokex:GetIsShadowStepping() and
            (not bot.vokex_nextShadowStep or now >= bot.vokex_nextShadowStep)

        if canDash then
            move.commands = AddMoveCommand(move.commands, Move.SecondaryAttack)
            bot.vokex_nextShadowStep = now + kVokexShadowStepCD
        end
    end
end

-- ---------------------------------------------------------------------------
-- Actions table — returned by VokexBrain:GetActions()
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

        -- Gate on the always-present SwipeShadowStep; executor picks the actual weapon.
        local canAttack = vokex:GetWeapon("swipeshadowstep") ~= nil

        local sdb = brain:GetSenses()
        local retreatInfo = sdb and sdb:Get("retreatThreshold")
        if retreatInfo and retreatInfo.retreat then
            canAttack = false
        end

        local eHP    = vokex:GetHealthScalar()
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
