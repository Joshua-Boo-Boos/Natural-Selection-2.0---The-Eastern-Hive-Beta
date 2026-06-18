-- VokexBrain_Data.lua
-- Combat/movement data for Vokex bots. Modelled on FadeBrain_Data but using the
-- Vokex API (GetIsShadowStepping / Metabolize / SwipeShadowStep / AcidRocket).
--
-- Weapons used:
--   SwipeShadowStep  - melee (primary). Always the fallback weapon.
--   AcidRocket       - ranged projectile, used at medium range with line of sight.
--   VortexShadowStep - NEVER used by the bot (deliberately excluded).
-- Movement: pathing + Metabolize (heal/energy) via the MovementModifier key, which
-- Vokex:MovementModifierChanged turns into a Metabolize. We deliberately avoid the
-- Fade-specific blink-jump sequence (Vokex lacks GetIsBlinking), keeping movement
-- simple and reliable.

Script.Load("lua/bots/CommonActions.lua")
Script.Load("lua/bots/BrainSenses.lua")

local kVokexBrainActionTypesOrderScale = 10
local kVokexBrainObjectiveTypesOrderScale = 100

local kVokexBrainHealthRetreatStart = 0.55
local kVokexBrainHealthRetreatStop  = 0.95
local kVokexBrainEnergyRetreatStart = 0.3
local kVokexBrainEnergyRetreatStop  = 0.9
local kVokexRetreatMinTime = 10.0

local kVokexMeleeRange    = 2.4
local kVokexAcidRange     = 18.0
local kVokexAcidMinRange  = 3.0
local kVokexWeaponSwitchCD = 0.4

local kVokexBrainPheromoneWeights =
{
    [kTechId.ThreatMarker] = 3.0,
    [kTechId.ExpandingMarker] = 1.0,
}

local kVokexRetreatType = enum({ "Health", "Energy", "Danger" })

local kVokexBrainActionTypes = enum({
    "Retreat", "Attack", "DefendHive", "Order", "Evolve", "Pheromone", "Explore"
})

local function GetVokexActionBaselineWeight( actionId )
    local totalActions = #kVokexBrainActionTypes
    local actionOrderId = kVokexBrainActionTypes[kVokexBrainActionTypes[actionId]]
    local actionWeightOrder = totalActions - (actionOrderId - 1)
    return actionWeightOrder * kVokexBrainActionTypesOrderScale
end

local function EstimateVokexResponseUtility(vokex, target)
    PROFILE("VokexBrain - EstimateVokexResponseUtility")
    if vokex:GetLocationName() == target:GetLocationName() then
        return 1.0
    end
    local dist = GetTunnelDistanceForAlien(vokex, target)
    return Clamp(1.0 - ( ( dist - 30.0 ) / 60.0 ), 0.0, 1.0)
end

-- Vokex-safe movement: path to target and Metabolize when it helps. No blink-jump.
local function PerformMove( alienPos, targetPos, bot, brain, move )

    local postIgnore = HandleAlienTunnelMove( alienPos, targetPos, bot, brain, move )
    if postIgnore then
        return
    end

    local vokex = bot:GetPlayer()
    if not vokex or not vokex:GetIsAlive() then
        return
    end

    bot:GetMotion():SetDesiredMoveTarget( targetPos )

    local time = Shared.GetTime()
    local isStepping = vokex.GetIsShadowStepping and vokex:GetIsShadowStepping()
    if not isStepping and (not brain.timeOfMetab or brain.timeOfMetab < time) then
        local maxEnergy = vokex:GetMaxEnergy()
        local eFrac = maxEnergy > 0 and (vokex:GetEnergy() / maxEnergy) or 1
        if eFrac <= 0.85 or vokex:GetHealthScalar() < 1 then
            -- MovementModifier -> Vokex:MovementModifierChanged triggers Metabolize
            move.commands = AddMoveCommand( move.commands, Move.MovementModifier )
            brain.timeOfMetab = time + (kMetabolizeDelay or 1.0) * 2
        end
    end
end

local function GetAttackUrgency( bot, mem )
    local ent = Shared.GetEntity(mem.entId)
    if (not HasMixin(ent, "Live") or not ent:GetIsAlive())
            or (ent.GetTeamNumber and ent:GetTeamNumber() == bot:GetTeamNumber()) then
        return nil
    end

    local botPos = bot:GetPlayer():GetOrigin()
    local distance = botPos:GetDistance(ent:GetOrigin())

    local immediateThreats =
    {
        [kMinimapBlipType.Marine] = true,
        [kMinimapBlipType.JetpackMarine] = true,
        [kMinimapBlipType.Exo] = true,
    }

    if distance < 15 and immediateThreats[mem.btype] then
        return 1 + 1 / math.max(distance, 1)
    end

    local numOthers = bot.brain.teamBrain:GetNumAssignedTo( mem,
        function(otherId)
            return otherId ~= bot:GetPlayer():GetId()
        end)

    local urgencies =
    {
        [kMinimapBlipType.Marine] =        numOthers >= 2 and 0.6 or 1,
        [kMinimapBlipType.JetpackMarine] = numOthers >= 2 and 0.7 or 1.1,
        [kMinimapBlipType.Exo] =           numOthers >= 2 and 0.8 or 1.2,
        [kMinimapBlipType.Sentry] =        numOthers >= 2 and 0.5 or 0.95,
        [kMinimapBlipType.ARC] =           numOthers >= 1 and 0.4 or 0.9,
        [kMinimapBlipType.CommandStation]= numOthers >= 2 and 0.3 or 0.75,
        [kMinimapBlipType.PhaseGate] =     numOthers >= 1 and 0.2 or 0.9,
        [kMinimapBlipType.Observatory] =   numOthers >= 1 and 0.2 or 0.8,
        [kMinimapBlipType.Extractor] =     numOthers >= 1 and 0.2 or 0.7,
        [kMinimapBlipType.InfantryPortal]= numOthers >= 1 and 0.2 or 0.6,
    }

    return urgencies[ mem.btype ]
end

-- Choose Vokex's weapon by range and fire. SwipeShadowStep melee, AcidRocket ranged.
local function PerformAttackEntity( eyePos, bestTarget, bot, brain, move )
    assert( bestTarget )

    local vokex = bot:GetPlayer()
    local now = Shared.GetTime()
    local aimPos = GetBestAimPoint( bestTarget )
    local dist = select(2, GetTunnelDistanceForAlien(vokex, bestTarget))
    local hasClearShot = dist < 20.0 and bot:GetBotCanSeeTarget( bestTarget )

    local meleeName = SwipeShadowStep.kMapName
    local acidName  = AcidRocket.kMapName
    local hasAcid   = vokex:GetWeapon(acidName) ~= nil

    -- Pick the desired weapon: AcidRocket at medium range with LOS, else melee.
    local desired = meleeName
    if hasAcid and hasClearShot and dist >= kVokexAcidMinRange and dist <= kVokexAcidRange then
        desired = acidName
    end

    -- Switch only when needed and rate-limited (switching every frame breaks the attack).
    local active = vokex:GetActiveWeapon()
    local activeName = active and active:GetMapName()
    if activeName ~= desired and (not bot.vokexNextSwitch or now >= bot.vokexNextSwitch) then
        vokex:SetActiveWeapon(desired)
        bot.vokexNextSwitch = now + kVokexWeaponSwitchCD
        activeName = desired
    end

    bot:GetMotion():SetDesiredViewTarget( aimPos )
    if bot.aim then
        bot.aim:UpdateAim(bestTarget, aimPos, kBotAccWeaponGroup.Swipe)
    end

    if activeName == acidName then
        -- Ranged: fire within range; close in slightly only at the very edge.
        if dist <= kVokexAcidRange then
            move.commands = AddMoveCommand( move.commands, Move.PrimaryAttack )
        end
        if dist > kVokexAcidRange * 0.9 then
            bot:GetMotion():SetDesiredMoveTarget( bestTarget:GetOrigin() )
        else
            bot:GetMotion():SetDesiredMoveTarget( nil )
        end
    else
        -- Melee: close and swipe.
        if dist <= kVokexMeleeRange + math.random(0.05, 0.125) then
            move.commands = AddMoveCommand( move.commands, Move.PrimaryAttack )
            bot:GetMotion():SetDesiredMoveTarget( nil )
        else
            local idealMoveTo = GetPositionBehindTarget( vokex, bestTarget, kVokexMeleeRange )
            PerformMove( eyePos, idealMoveTo or bestTarget:GetOrigin(), bot, brain, move )
        end
    end
end

local function PerformAttack( eyePos, mem, bot, brain, move )
    assert( mem )
    local target = Shared.GetEntity(mem.entId)
    if target ~= nil then
        PerformAttackEntity( eyePos, target, bot, brain, move )
    else
        PerformMove(eyePos, mem.lastSeenPos, bot, brain, move)
    end
    brain.teamBrain:AssignBotToMemory(bot, mem)
end

------------------------------------------
-- Objectives
------------------------------------------

local kValidateVokexRetreat = function(bot, brain, vokex, action)
    if not IsValid(action.hive) or not action.hive:GetIsAlive() then
        return false
    end
    if vokex:GetHealthScalar() >= kVokexBrainHealthRetreatStop
            and ( vokex:GetEnergy() / vokex:GetMaxEnergy() >= kVokexBrainEnergyRetreatStop ) then
        return false
    end
    return true
end

local kExecVokexRetreat = function(move, bot, brain, vokex, action)
    local hive = action.hive
    local inCombat = vokex:GetIsInCombat()
    local eHP = vokex:GetHealthScalar()
    local energy = vokex:GetEnergy() / vokex:GetMaxEnergy()

    brain.teamBrain:UnassignBot(bot)

    local touchDist = GetDistanceToTouch( vokex:GetEyePos(), hive )
    if touchDist > 3.25 or inCombat then
        local jitter = Vector(math.random()-0.5, math.random()-0.5, math.random()-0.5) * 3
        PerformMove(vokex:GetEyePos(), hive:GetEngagementPoint() + jitter, bot, brain, move)
    else
        if vokex:GetIsUnderFire() then
            local damageOrigin = vokex:GetLastTakenDamageOrigin()
            local hiveOrigin = hive:GetEngagementPoint()
            local retreatDir = (hiveOrigin - damageOrigin):GetUnit()
            local _, max = hive:GetModelExtents()
            local retreatPos = hiveOrigin + (retreatDir * max.x)
            bot:GetMotion():SetDesiredViewTarget( hive:GetEngagementPoint() )
            bot:GetMotion():SetDesiredMoveTarget( retreatPos )
        else
            bot:GetMotion():SetDesiredViewTarget( hive:GetEngagementPoint() )
            bot:GetMotion():SetDesiredMoveTarget( nil )
        end
    end

    local hasEnergy = energy > kVokexBrainEnergyRetreatStop
    local hasHealth = eHP > kVokexBrainHealthRetreatStop
    local timeSinceRetreat = (Shared.GetTime() - action.retreatStart)

    if action.retreatType == kVokexRetreatType.Health and hasHealth and hasEnergy then
        return kPlayerObjectiveComplete
    elseif action.retreatType == kVokexRetreatType.Energy and hasEnergy then
        return kPlayerObjectiveComplete
    elseif action.retreatType == kVokexRetreatType.Danger and not vokex:GetIsInCombat()
            and timeSinceRetreat > kVokexRetreatMinTime then
        return kPlayerObjectiveComplete
    end
end

local kVokexBrainObjectiveTypes = enum({
    "Retreat", "RespondToThreat", "Evolve", "GoToCommPing", "Pheromone", "Explore"
})

local VokexObjectiveWeights = MakeBotActionWeights(kVokexBrainObjectiveTypes, kVokexBrainObjectiveTypesOrderScale)

kVokexBrainObjectives =
{
    CreateAlienRespondToThreatAction(VokexObjectiveWeights, kVokexBrainObjectiveTypes.RespondToThreat, PerformMove),

    function(bot, brain, vokex)
        PROFILE("VokexBrain_Data:retreat")
        local name, weight = VokexObjectiveWeights:Get(kVokexBrainObjectiveTypes.Retreat)
        local sdb = brain:GetSenses()

        if vokex.isHallucination then
            return kNilAction
        end

        local hiveData = sdb:Get("nearestHive")
        local hive = hiveData.hive
        if not hive then
            return kNilAction
        end

        local retreatInfo = sdb:Get("retreatThreshold")
        if not retreatInfo.retreat then
            return kNilAction
        end

        return
        {
            name = name,
            weight = weight,
            hive = hive,
            retreatType = retreatInfo.type,
            retreatStart = Shared.GetTime(),
            validate = kValidateVokexRetreat,
            perform = kExecVokexRetreat
        }
    end,

    -- Evolve: handles chamber upgrades (and keeps the bot a Vokex). lifeformTechId
    -- is kTechId.Vokex; the 30s distributor sets the desired lifeform on Skulks.
    CreateAlienEvolveAction(VokexObjectiveWeights, kVokexBrainObjectiveTypes.Evolve, kTechId.Vokex),

    CreateAlienPheromoneAction(VokexObjectiveWeights, kVokexBrainObjectiveTypes.Pheromone, kVokexBrainPheromoneWeights, PerformMove),

    CreateAlienGoToCommPingAction(VokexObjectiveWeights, kVokexBrainObjectiveTypes.GoToCommPing, PerformMove),

    CreateExploreAction( VokexObjectiveWeights:GetWeight(kVokexBrainObjectiveTypes.Explore),
        function(pos, targetPos, bot, brain, move)
            PerformMove(bot:GetPlayer():GetEyePos(), targetPos, bot, brain, move)
        end),
}

local kExecAttackAction = function(move, bot, brain, vokex, action)
    brain.teamBrain:UnassignBot(bot)
    PerformAttack( vokex:GetEyePos(), action.bestMem, bot, brain, move )
end

kVokexBrainActions =
{
    ------------------------------------------
    -- Attack
    ------------------------------------------
    function(bot, brain, vokex)
        PROFILE("VokexBrain_Data:attack")
        local name = "attack"

        local memories = GetTeamMemories(bot:GetTeamNumber())
        local bestUrgency, bestMem =
            GetMaxTableEntry( memories,
                function( mem ) return GetAttackUrgency( bot, mem ) end )

        -- Vokex can attack if it owns the SwipeShadowStep weapon (always its melee).
        local canAttack = vokex:GetWeapon(SwipeShadowStep.kMapName) ~= nil
        canAttack = canAttack and (not brain:GetSenses():Get("retreatThreshold").retreat)

        local eHP = vokex:GetHealthScalar()
        local weight = 0.0

        if canAttack and bestMem ~= nil then
            local dist = select(2, GetTunnelDistanceForAlien(vokex, bestMem.lastSeenPos))
            if dist <= 50 and eHP > kVokexBrainHealthRetreatStop then
                weight = GetVokexActionBaselineWeight(kVokexBrainActionTypes.Attack)
            elseif dist <= 15 then
                weight = GetVokexActionBaselineWeight(kVokexBrainActionTypes.Attack)
            end
        end

        return
        {
            name = name,
            weight = weight,
            bestMem = bestMem,
            fastUpdate = true,
            perform = kExecAttackAction
        }
    end,

    CreateAlienInterruptAction(),
}
