--[[
    ARCUS (ARC Upgrade System) - the ARC side.

    Loaded post lua/ARC.lua, after the mod's own ARC hook (CNBalance/Structures/Marine/ARC.lua), so every function here
    wraps the mod's version. A normal ARC (tech id kTechId.ARC) takes the original path in every function below.

    H.A.M.M.E.R. (hammer) - PvE, anti-structure
        The normal ARC: deploys, cannot move while deployed, shells through the vanilla targeting - so the mod's Shade ink
        rules (no firing into a cloud, auto-ink parry) apply unchanged. It targets EVERY alien structure (eggs, cysts,
        Hydras and spore mines included) and never alien players or Babblers. Its four upgrades change the shell.

    V.A.T. (vanguard) - PvP, anti-personnel tank
        Drives while deployed, fires only while deployed, never at structures.
          Machine gun (upgrade 1+)   1 alien lifeforms   2 Babblers
          Cannon (upgrade 2+)        alien lifeforms only. Charges (the ARC's own charge sound and effect at the muzzle),
                                     fires (the ARC's own fire effect), then goes on cooldown.

    H.E.L.L. (inferno) - PvPvE, flamethrower tank
        Drives while deployed, fires only while deployed.
          1 alien lifeforms   2 Babblers   3 any other alien structure
        A commander ATTACK order overrides the priority: the H.E.L.L. burns that target whenever it is in range.
        Pilot Flame (no research): no direct damage, only sets targets on fire.

    INK, for the tanks: nothing inside a Shade ink cloud can be targeted, and locking onto a new target gives a ready Shade
    near it the same auto-ink parry an ARC shot does (CNBalance AlienDetectionParry); if it inks, the lock is dropped.

    TURRET. The barrel snaps straight onto its target (the ARC's existing networked barrel angles), taking the short way
    round, so the shot effects - drawn by each client from the muzzle attach point, see ARCSpec_Shots.lua - always leave
    the barrel towards the target.

    Network: no network variable or class is added. Shots reach clients through one network message (ARCSpec_Shots.lua);
    the cannon's charge / fire effects are the ARC's own effects.
]]

-- Weapon numbers. Index = how many upgrades of that specialisation are researched (they can only be researched in order).
ARCSpec.kVanguard =
{
    mgRange = 30, mgInterval = 2, mgDamage = 10, mgDamageType = kDamageType.Normal,       -- from upgrade 1
    -- Before upgrade 1: the same machine gun (same damage, targets and turret) at half the fire rate and short range, a
    -- little more than the H.E.L.L.'s 4 m Pilot Flame.
    mgBaseRange = 6, mgBaseInterval = 4,
    cannonRange = 22.5, cannonInterval = 5, cannonChargeTime = 1,                           -- from upgrade 2
    cannon =
    {
        [2] = { damage = 25, damageType = kDamageType.Light },
        [3] = { damage = 30, damageType = kDamageType.Normal },
        [4] = { damage = 65, damageType = kDamageType.Heavy, railgun = true },
    },
}

ARCSpec.kInferno =
{
    -- pulses: how many 0.25 s pulses one burst lasts. igniteStacks: SetOnFire calls per pulse (the mod's fire system only
    -- lights a target once its burn stack reaches the burn rate - 5 per call against 8 per second for a player - so a lone
    -- Pilot Flame call never lit anything; two do).
    [0] = { range = 4,  interval = 3,   pulses = 1, damage = 0,  igniteStacks = 2 },
    [1] = { range = 6,  interval = 2,   pulses = 1, damage = 20, igniteStacks = 0 },
    [2] = { range = 10, interval = 2.5, pulses = 3, damage = 15, igniteStacks = 0 },
    [3] = { range = 10, interval = 2.5, pulses = 3, damage = 18, igniteStacks = 1 },
    [4] = { range = 14, interval = 2.5, pulses = 3, damage = 22, igniteStacks = 1 },
    pulseSpacing = 0.25,
    splash = 1.5,
}

ARCSpec.kHammer =
{
    hiveDamageScalar = 1.25,     -- upgrade 1
    upgradedSplashRadius = 10,   -- upgrade 2 (normal ARC: ARC.kSplashRadius, 7)
    damageTakenScalar = 0.75,    -- upgrade 3
    payloadDamageScalar = 1.2,   -- upgrade 4, plus setting everything in the blast on fire
}

local kRetargetInterval = 0.25
local kTierRefreshInterval = 1

--[[ ---------------------------------------------------------------------------------------------------------------------
    Upgrade tier: how many upgrades of this ARC's specialisation the team has RESEARCHED. A built specialised ARC keeps
    every level researched, even after every factory of its specialisation is destroyed - so the node's researched flag is
    read, not GetHasTech (which also needs the factory standing, the upgrade's prerequisite). Re-read once a second. Works
    on the server and on the commander's client (which has the team tech tree), where it sizes the range circle.
]] ---------------------------------------------------------------------------------------------------------------------
local function GetTeamTechTree(arc)
    if Server then
        local team = arc.GetTeam and arc:GetTeam()
        return team and team.GetTechTree and team:GetTechTree()
    end
    return GetTechTree and GetTechTree()
end

function ARCSpec.GetUpgradeTier(arc)

    local spec = ARCSpec.GetARCSpec(arc)
    if not spec then return 0 end

    local now = Shared.GetTime()
    if arc.arcSpecTierTime and now < arc.arcSpecTierTime then
        return arc.arcSpecTier or 0
    end

    local tier = 0
    local techTree = GetTeamTechTree(arc)
    if techTree then
        for i = #spec.upgrades, 1, -1 do
            local node = techTree:GetTechNode(spec.upgrades[i])
            if node and node:GetResearched() then
                tier = i
                break
            end
        end
    end

    arc.arcSpecTier = tier
    arc.arcSpecTierTime = now + kTierRefreshInterval
    return tier

end

-- Damage type for this ARC's current shot; otherwise exactly what DamageMixin would have looked up.
function ARC:GetDamageType()
    return self.arcSpecShotDamageType or LookupTechData(self:GetTechId(), kTechDataDamageType, kDamageType.Normal)
end

-- The commander's range circle: the tanks show the reach of the weapon they actually have.
local baseGetVisualRadius = ARC.GetVisualRadius
function ARC:GetVisualRadius()

    local spec = ARCSpec.GetARCSpec(self)

    -- Only a commander's client has the team tech tree. Anyone else (e.g. a spectator's overhead view) is shown the tank's
    -- longest reach from its tech data, rather than asking GetHasTech, which logs on every call without a tree.
    if spec and spec.mobile and Client and not (GetTechTree and GetTechTree()) then
        return LookupTechData(self:GetTechId(), kVisualRange, nil)
    end

    if spec == ARCSpec.kSpecs.inferno then
        return ARCSpec.kInferno[math.min(ARCSpec.GetUpgradeTier(self), 4)].range
    elseif spec == ARCSpec.kSpecs.vanguard then
        if ARCSpec.GetUpgradeTier(self) >= 1 then
            return ARCSpec.kVanguard.mgRange
        end
        return ARCSpec.kVanguard.mgBaseRange
    end

    if baseGetVisualRadius then
        return baseGetVisualRadius(self)
    end
    return LookupTechData(self:GetTechId(), kVisualRange, nil)

end

--[[ ---------------------------------------------------------------------------------------------------------------------
    H.A.M.M.E.R. targeting (vanilla ARC targeting with a PvE target list) and the tanks' opt-out of the siege cannon.
]] ---------------------------------------------------------------------------------------------------------------------

-- PvE: every alien structure, never an alien player or a Babbler.
local function GetIsHammerTarget(target)
    if target:isa("Player") or target:isa("Babbler") then
        return false
    end
    return target.GetReceivesStructuralDamage ~= nil and target:GetReceivesStructuralDamage()
end

local baseGetCanFireAtTargetActual = ARC.GetCanFireAtTargetActual
function ARC:GetCanFireAtTargetActual(target, targetPoint, manuallyTargeted)

    local spec = ARCSpec.GetARCSpec(self)

    if spec and spec.mobile then
        return false
    end

    if spec == ARCSpec.kSpecs.hammer then

        if not GetIsHammerTarget(target) then
            return false
        end

        if target.GetIsSighted and not target:GetIsSighted() and not GetIsTargetDetected(target) then
            return false
        end

        local distToTarget = (target:GetOrigin() - self:GetOrigin()):GetLengthXZ()
        return distToTarget <= ARC.kFireRange and distToTarget >= ARC.kMinFireRange

    end

    return baseGetCanFireAtTargetActual(self, target, targetPoint, manuallyTargeted)

end

-- Vanilla's pre-check also drops eggs and cysts; the H.A.M.M.E.R. takes them.
local baseGetCanFireAtTarget = ARC.GetCanFireAtTarget
function ARC:GetCanFireAtTarget(target, targetPoint)

    if ARCSpec.GetARCSpec(self) == ARCSpec.kSpecs.hammer then
        if target == nil or not HasMixin(target, "Live") or not target:GetIsAlive() or not GetAreEnemies(self, target) then
            return false
        end
        return self:GetCanFireAtTargetActual(target, targetPoint)
    end

    return baseGetCanFireAtTarget(self, target, targetPoint)

end

--[[ ---------------------------------------------------------------------------------------------------------------------
    Mobile tanks: can move while deployed, never sleep (their weapons run from OnUpdate). Only the H.E.L.L. takes Attack
    orders (they override its target priority).
]] ---------------------------------------------------------------------------------------------------------------------

local baseGetCanSleep = ARC.GetCanSleep
function ARC:GetCanSleep()
    if ARCSpec.GetIsMobileARC(self) then
        return false
    end
    return baseGetCanSleep(self)
end

local baseGetActivationTechAllowed = ARC.GetActivationTechAllowed
function ARC:GetActivationTechAllowed(techId)
    if techId == kTechId.Move and ARCSpec.GetIsMobileARC(self) then
        return self.deployMode == ARC.kDeployMode.Undeployed or self.deployMode == ARC.kDeployMode.Deployed
    end
    return baseGetActivationTechAllowed(self, techId)
end

local baseGetTechButtons = ARC.GetTechButtons
function ARC:GetTechButtons(techId)
    local spec = ARCSpec.GetARCSpec(self)
    if spec == ARCSpec.kSpecs.inferno then
        return { kTechId.Move, kTechId.Stop, kTechId.Attack, kTechId.None,
                 kTechId.ARCDeploy, kTechId.ARCUndeploy, kTechId.None, kTechId.None }
    elseif spec == ARCSpec.kSpecs.vanguard then
        return { kTechId.Move, kTechId.Stop, kTechId.None, kTechId.None,
                 kTechId.ARCDeploy, kTechId.ARCUndeploy, kTechId.None, kTechId.None }
    end
    return baseGetTechButtons(self, techId)
end

local function GetIsAttackableEnemy(self, target)
    return target ~= nil and HasMixin(target, "Live") and target:GetIsAlive() and GetAreEnemies(self, target)
           and (not target.GetCanTakeDamage or target:GetCanTakeDamage())
end

local baseOnOverrideOrder = ARC.OnOverrideOrder
function ARC:OnOverrideOrder(order)

    local spec = ARCSpec.GetARCSpec(self)
    if spec and spec.mobile then
        if order:GetType() == kTechId.Default then
            -- A H.E.L.L. right-clicked onto an enemy attacks it; anything else is a move.
            local target = spec == ARCSpec.kSpecs.inferno and Shared.GetEntity(order:GetParam()) or nil
            if target and GetIsAttackableEnemy(self, target) then
                order:SetType(kTechId.Attack)
            else
                order:SetType(kTechId.Move)
            end
        end
        return
    end

    return baseOnOverrideOrder(self, order)

end

local baseOnValidateOrder = ARC.OnValidateOrder
function ARC:OnValidateOrder(order)

    local spec = ARCSpec.GetARCSpec(self)
    if spec and spec.mobile and order:GetType() == kTechId.Attack then
        if spec ~= ARCSpec.kSpecs.inferno then
            return false
        end
        return GetIsAttackableEnemy(self, Shared.GetEntity(order:GetParam()))
    end

    return baseOnValidateOrder(self, order)

end

-- The tanks keep their own target state; vanilla's siege targeting must not be armed by their orders.
local baseOnOrderGiven = ARC.OnOrderGiven
function ARC:OnOrderGiven(order)
    if ARCSpec.GetIsMobileARC(self) then
        return
    end
    return baseOnOrderGiven(self, order)
end

local baseOnUpdateAnimationInput = ARC.OnUpdateAnimationInput
function ARC:OnUpdateAnimationInput(modelMixin)
    baseOnUpdateAnimationInput(self, modelMixin)
    if ARCSpec.GetIsMobileARC(self) and self.mode == ARC.kMode.Moving then
        modelMixin:SetAnimationInput("move", "run")
    end
end

-- H.A.M.M.E.R. Deflector Plating.
local baseModifyDamageTaken = ARC.ModifyDamageTaken
function ARC:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint, weapon)
    if baseModifyDamageTaken then
        baseModifyDamageTaken(self, damageTable, attacker, doer, damageType, hitPoint, weapon)
    end
    if ARCSpec.GetARCSpec(self) == ARCSpec.kSpecs.hammer and ARCSpec.GetUpgradeTier(self) >= 3 then
        damageTable.damage = damageTable.damage * ARCSpec.kHammer.damageTakenScalar
    end
end

if not Server then
    return
end

--[[ ---------------------------------------------------------------------------------------------------------------------
    SERVER
]] ---------------------------------------------------------------------------------------------------------------------

local baseUpdateOrders = ARC.UpdateOrders
function ARC:UpdateOrders(deltaTime)

    local spec = ARCSpec.GetARCSpec(self)

    if spec and spec.mobile then

        -- A H.E.L.L. attack order is held until its target dies (the burn itself happens in UpdateInferno). Vanilla's attack
        -- handling is skipped: it would arm the siege cannon's targeting and drop the order at the siege minimum range.
        local order = self:GetCurrentOrder()
        if order and order:GetType() == kTechId.Attack then
            if spec ~= ARCSpec.kSpecs.inferno or not GetIsAttackableEnemy(self, Shared.GetEntity(order:GetParam())) then
                self:CompletedCurrentOrder()
            end
            return
        end

    end

    baseUpdateOrders(self, deltaTime)

    -- Mobile tanks drive while deployed: vanilla UpdateOrders only moves an undeployed ARC, so do the move it skipped.
    if spec and spec.mobile and self.deployMode == ARC.kDeployMode.Deployed then
        local order = self:GetCurrentOrder()
        if order and order:GetType() == kTechId.Move then
            self:UpdateMoveOrder(deltaTime)
        end
    end

end

local function GetAimPoint(target)
    if target.GetEngagementPoint then
        return target:GetEngagementPoint()
    end
    return target:GetOrigin()
end

local function GetIsInked(self, position)
    local clouds = GetEntitiesForTeamWithinRange("ShadeInk", GetEnemyTeamNumber(self:GetTeamNumber()), position,
                                                 ShadeInk.kShadeInkDisorientRadius)
    return #clouds > 0
end

local function GetHasLineOfFire(self, target, fromPoint, toPoint)
    local trace = Shared.TraceRay(fromPoint, toPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
    return trace.fraction == 1 or trace.entity == target
end

-- Priority of a target for a weapon ("mg", "cannon" or "flame"), lower is better; nil if it may not be targeted at all.
local function GetTargetPriority(self, target, weapon)

    if not GetIsAttackableEnemy(self, target) then return nil end
    if target:isa("Commander") then return nil end
    if HasMixin(target, "Cloakable") and target:GetIsCloaked() and not GetIsTargetDetected(target) then return nil end

    local isPlayer = target:isa("Player")

    if weapon == "cannon" then
        return isPlayer and 1 or nil
    end

    if isPlayer then return 1 end
    if target:isa("Babbler") then return 2 end

    if weapon == "flame" then
        return 3
    end

    return nil

end

-- True if the target may be fired on from here (the priority check is done by the caller).
local function GetIsInReach(self, target, range, eye)
    local point = GetAimPoint(target)
    if (point - eye):GetLength() > range then return false end
    if GetIsInked(self, point) then return false end
    return GetHasLineOfFire(self, target, eye, point)
end

local function AcquireTarget(self, weapon, range, eye)

    local enemyTeam = GetEnemyTeamNumber(self:GetTeamNumber())
    local best, bestPriority, bestDistance

    for _, target in ipairs(GetEntitiesWithMixinForTeamWithinRange("Live", enemyTeam, eye, range)) do

        local priority = GetTargetPriority(self, target, weapon)
        if priority and (not bestPriority or priority <= bestPriority) then

            local distance = (GetAimPoint(target) - eye):GetLength()
            local better = not bestPriority or priority < bestPriority or distance < bestDistance

            if better and GetIsInReach(self, target, range, eye) then
                best, bestPriority, bestDistance = target, priority, distance
            end

        end

    end

    return best

end

-- Keeps a weapon's lock while it stays valid; otherwise looks for a new target every kRetargetInterval. A NEW lock offers the
-- aliens' Shades their auto-ink parry, exactly like an ARC shot, and is dropped if they ink.
local function UpdateLock(self, weapon, range, eye, now)

    local field = "arcSpecLock_" .. weapon
    local current = self[field] and Shared.GetEntity(self[field]) or nil

    if current and GetTargetPriority(self, current, weapon) and GetIsInReach(self, current, range, eye) then
        return current
    end
    self[field] = nil

    local timeField = "arcSpecNextAcquire_" .. weapon
    if self[timeField] and now < self[timeField] then
        return nil
    end
    self[timeField] = now + kRetargetInterval

    local target = AcquireTarget(self, weapon, range, eye)
    if not target then return nil end

    if AlienDetectionParry and AlienDetectionParry(GetEnemyTeamNumber(self:GetTeamNumber()), GetAimPoint(target),
                                                   ShadeInk.kShadeInkDisorientRadius) then
        return nil
    end

    self[field] = target:GetId()
    return target

end

--[[ ---------------------------------------------------------------------------------------------------------------------
    BILE BOMBS AND SPORE CLOUDS. Neither is a Live entity, so the target search above never sees them.
      - A spore cloud between a V.A.T.'s muzzle and its target BLOCKS that shot (a flamethrower must burn it away first).
      - A H.E.L.L. with a burst READY (never during its cooldown) burns bile bombs first of all, and spore clouds after
        lifeforms; and every flame pulse burns any spores or bombs its stream passes through - the vanilla flamethrower's
        own rule (Flamethrower:BurnSporesAndUmbra), with the same effects.
]] ---------------------------------------------------------------------------------------------------------------------

local kBombClasses = { "Bomb", "WhipBomb" }
local kBombBurnRadius = 1.6

local function GetSporeRadius(spore)
    return spore.GetDamageRadius and spore:GetDamageRadius() or kSporesDustCloudRadius
end

-- Shortest distance from a point to the segment a-b.
local function DistanceToSegment(point, a, b)
    local ab = b - a
    local lengthSquared = Math.DotProduct(ab, ab)
    if lengthSquared <= 0.0001 then
        return (point - a):GetLength()
    end
    local t = Clamp(Math.DotProduct(point - a, ab) / lengthSquared, 0, 1)
    return (point - (a + ab * t)):GetLength()
end

-- V.A.T.: is the line of fire to this point through a spore cloud?
local function GetIsSporeBlocked(fromPoint, toPoint)
    local reach = (toPoint - fromPoint):GetLength() + kSporesDustCloudRadius
    for _, spore in ipairs(GetEntitiesWithinRange("SporeCloud", fromPoint, reach)) do
        if DistanceToSegment(spore:GetOrigin(), fromPoint, toPoint) <= GetSporeRadius(spore) then
            return true
        end
    end
    return false
end

local function GetIsHazard(entity)
    return entity ~= nil and (entity:isa("SporeCloud") or entity:isa("Bomb") or entity:isa("WhipBomb"))
end

local function BurnHazard(self, hazard)
    if hazard:isa("SporeCloud") then
        self:TriggerEffects("burn_spore", { effecthostcoords = Coords.GetTranslation(hazard:GetOrigin()) })
    else
        hazard:TriggerEffects("burn_bomb", { effecthostcoords = Coords.GetTranslation(hazard:GetOrigin()) })
    end
    DestroyEntity(hazard)
end

-- H.E.L.L.: burns every spore cloud and bile bomb the flame stream from a to b passes through.
local function BurnHazardsAlongStream(self, fromPoint, toPoint)

    local reach = (toPoint - fromPoint):GetLength() + kSporesDustCloudRadius
    local burned = {}

    for _, spore in ipairs(GetEntitiesWithinRange("SporeCloud", fromPoint, reach)) do
        if DistanceToSegment(spore:GetOrigin(), fromPoint, toPoint) <= GetSporeRadius(spore) then
            burned[#burned + 1] = spore
        end
    end

    for _, className in ipairs(kBombClasses) do
        for _, bomb in ipairs(GetEntitiesWithinRange(className, fromPoint, reach)) do
            if DistanceToSegment(bomb:GetOrigin(), fromPoint, toPoint) <= kBombBurnRadius then
                burned[#burned + 1] = bomb
            end
        end
    end

    for _, hazard in ipairs(burned) do
        BurnHazard(self, hazard)
    end

end

-- H.E.L.L.: the nearest hazard of a kind within reach (bombs need a clear line, as they fly through open air).
local function FindNearestHazard(self, classNames, range, eye)
    local best, bestDistance
    for _, className in ipairs(classNames) do
        for _, entity in ipairs(GetEntitiesWithinRange(className, eye, range)) do
            local distance = (entity:GetOrigin() - eye):GetLength()
            if (not bestDistance or distance < bestDistance)
               and GetHasLineOfFire(self, entity, eye, entity:GetOrigin()) then
                best, bestDistance = entity, distance
            end
        end
    end
    return best
end

local function DoShot(self, damage, damageType, target, point, direction)
    self.arcSpecShotDamageType = damageType
    self:DoDamage(damage, target, point, direction, nil, false, false)
    self.arcSpecShotDamageType = nil
end

-- Snaps the turret onto a point (short way round), or eases it back to rest. The angles are the ARC's own networked barrel
-- angles; the sign conventions are vanilla ARC:UpdateAngles'.
local function AimBarrel(self, point, deltaTime)

    if point then
        local direction = GetNormalizedVector(point - self:GetOrigin())
        local angles = self:GetAngles()
        local yawDegrees = math.deg(GetAnglesDifference(GetYawFromVector(direction), angles.yaw))
        local pitchDegrees = math.deg(GetAnglesDifference(GetPitchFromVector(direction), angles.pitch))
        self.barrelYawDegrees = Clamp(yawDegrees, -ARC.kMaxYaw, ARC.kMaxYaw)
        self.barrelPitchDegrees = -Clamp(pitchDegrees, -ARC.kMaxPitch, ARC.kMaxPitch)
        return
    end

    self.barrelYawDegrees = Slerp(self.barrelYawDegrees, 0, ARC.kBarrelMoveRate * deltaTime)
    self.barrelPitchDegrees = Slerp(self.barrelPitchDegrees, 0, ARC.kBarrelMoveRate * deltaTime)

end

local function StopCannonCharge(self)
    if self.arcSpecChargeEnd then
        self.arcSpecChargeEnd = nil
        self.arcSpecChargeTarget = nil
        self:TriggerEffects("arc_stop_charge")
    end
end

local function UpdateVanguard(self, tier, eye, now, deltaTime)

    local stats = ARCSpec.kVanguard
    local mgRange = tier >= 1 and stats.mgRange or stats.mgBaseRange
    local mgInterval = tier >= 1 and stats.mgInterval or stats.mgBaseInterval
    local mgTarget = UpdateLock(self, "mg", mgRange, eye, now)
    local cannonTarget = tier >= 2 and UpdateLock(self, "cannon", stats.cannonRange, eye, now) or nil

    -- A charging cannon stays on the target it is charging at; losing it cancels the shot.
    local chargeTarget = self.arcSpecChargeTarget and Shared.GetEntity(self.arcSpecChargeTarget) or nil
    if self.arcSpecChargeEnd and (not chargeTarget or not GetTargetPriority(self, chargeTarget, "cannon")
                                  or not GetIsInReach(self, chargeTarget, stats.cannonRange, eye)) then
        StopCannonCharge(self)
        chargeTarget = nil
    end

    local aimTarget = chargeTarget or cannonTarget or mgTarget
    AimBarrel(self, aimTarget and GetAimPoint(aimTarget) or nil, deltaTime)

    -- A spore cloud on the line of fire blocks the shot until something burns it away.
    if mgTarget and now >= (self.arcSpecNextMG or 0) and not GetIsSporeBlocked(eye, GetAimPoint(mgTarget)) then
        self.arcSpecNextMG = now + mgInterval
        local point = GetAimPoint(mgTarget)
        DoShot(self, stats.mgDamage, stats.mgDamageType, mgTarget, point, GetNormalizedVector(point - eye))
        ARCSpec.SendShot(self, ARCSpec.kShotKind.mg, point)
    end

    if chargeTarget and now >= self.arcSpecChargeEnd and GetIsSporeBlocked(eye, GetAimPoint(chargeTarget)) then

        -- Spores drifted into the line of fire: the shot is lost (no cooldown - it charges again once clear).
        StopCannonCharge(self)

    elseif chargeTarget and now >= self.arcSpecChargeEnd then

        -- Fire, then the cooldown starts.
        self.arcSpecChargeEnd = nil
        self.arcSpecChargeTarget = nil
        self.arcSpecNextCannon = now + stats.cannonInterval

        local shell = stats.cannon[math.min(tier, 4)]
        if shell then
            local point = GetAimPoint(chargeTarget)
            DoShot(self, shell.damage, shell.damageType, chargeTarget, point, GetNormalizedVector(point - eye))
            self:TriggerEffects("arc_firing")
            ARCSpec.SendShot(self, shell.railgun and ARCSpec.kShotKind.railgun or ARCSpec.kShotKind.shell, point)
        else
            self:TriggerEffects("arc_stop_charge")
        end

    elseif not self.arcSpecChargeEnd and cannonTarget and now >= (self.arcSpecNextCannon or 0)
           and not GetIsSporeBlocked(eye, GetAimPoint(cannonTarget)) then

        self.arcSpecChargeEnd = now + stats.cannonChargeTime
        self.arcSpecChargeTarget = cannonTarget:GetId()
        self:TriggerEffects("arc_charge")

    end

end

-- The commander's attack-order target, if the H.E.L.L. can burn it from here right now.
local function GetForcedFlameTarget(self, range, eye)
    local order = self:GetCurrentOrder()
    if not order or order:GetType() ~= kTechId.Attack then return nil end
    local target = Shared.GetEntity(order:GetParam())
    if target and GetIsAttackableEnemy(self, target) and GetIsInReach(self, target, range, eye) then
        return target
    end
    return nil
end

local function BurnPulse(self, stats, target, eye)

    if not GetIsAttackableEnemy(self, target) or not GetIsInReach(self, target, stats.range, eye) then
        return false
    end

    local point = GetAimPoint(target)
    local direction = GetNormalizedVector(point - eye)
    local owner = self:GetOwner() or self

    -- The stream is drawn by every client from the muzzle straight to the target, at once, and burns any spores or bile
    -- bombs it passes through.
    ARCSpec.SendShot(self, ARCSpec.kShotKind.flame, point)
    BurnHazardsAlongStream(self, eye, point)

    -- The target, plus anything else of theirs in the flame at that point.
    local victims = { target }
    for _, ent in ipairs(GetEntitiesWithMixinForTeamWithinRange("Live", GetEnemyTeamNumber(self:GetTeamNumber()), point,
                                                                ARCSpec.kInferno.splash)) do
        if ent ~= target and GetIsAttackableEnemy(self, ent) then
            victims[#victims + 1] = ent
        end
    end

    for _, victim in ipairs(victims) do

        if stats.damage > 0 then
            DoShot(self, stats.damage, kDamageType.Flame, victim, GetAimPoint(victim), direction)
        end

        if stats.igniteStacks > 0 and victim:GetIsAlive() and HasMixin(victim, "Fire") then
            for _ = 1, stats.igniteStacks do
                victim:SetOnFire(owner, self)
            end
        end

    end

    return true

end

local function UpdateInferno(self, tier, eye, now, deltaTime)

    local stats = ARCSpec.kInferno[math.min(tier, 4)]
    local burstReady = (self.arcSpecPulsesLeft or 0) == 0 and now >= (self.arcSpecNextBurst or 0)

    --[[
        Target order when a burst is READY:
          1 bile bombs in flight   2 the commander's Attack-order target   3 alien lifeforms   4 spore clouds
          5 Babblers   6 any other alien structure
        During the cooldown the turret still tracks the lock, but bombs and spores are never chosen.
    ]]
    local target
    if burstReady then
        target = FindNearestHazard(self, kBombClasses, stats.range, eye) or GetForcedFlameTarget(self, stats.range, eye)
        if not target then
            local lock = UpdateLock(self, "flame", stats.range, eye, now)
            if lock and lock:isa("Player") then
                target = lock
            else
                target = FindNearestHazard(self, { "SporeCloud" }, stats.range, eye) or lock
            end
        end
    else
        target = GetForcedFlameTarget(self, stats.range, eye) or UpdateLock(self, "flame", stats.range, eye, now)
    end

    -- A burst in progress keeps pulsing at its target until it runs out or the target is lost.
    local burning = self.arcSpecBurstTarget and Shared.GetEntity(self.arcSpecBurstTarget) or nil
    local aimTarget = ((self.arcSpecPulsesLeft or 0) > 0 and burning) or target
    AimBarrel(self, aimTarget and GetAimPoint(aimTarget) or nil, deltaTime)

    if (self.arcSpecPulsesLeft or 0) > 0 and now >= (self.arcSpecNextPulse or 0) then
        if burning and BurnPulse(self, stats, burning, eye) then
            self.arcSpecPulsesLeft = self.arcSpecPulsesLeft - 1
            self.arcSpecNextPulse = now + ARCSpec.kInferno.pulseSpacing
        else
            self.arcSpecPulsesLeft = 0
        end
    end

    if target and burstReady and GetIsHazard(target) then

        -- A bile bomb or spore cloud takes one pulse: the stream reaches it at once and burns it (and anything else on
        -- the way). Then the normal cooldown.
        self.arcSpecNextBurst = now + stats.interval
        local point = target:GetOrigin()
        ARCSpec.SendShot(self, ARCSpec.kShotKind.flame, point)
        BurnHazardsAlongStream(self, eye, point)

    elseif target and burstReady then
        self.arcSpecNextBurst = now + stats.interval
        self.arcSpecBurstTarget = target:GetId()
        if BurnPulse(self, stats, target, eye) then
            self.arcSpecPulsesLeft = stats.pulses - 1
            self.arcSpecNextPulse = now + ARCSpec.kInferno.pulseSpacing
        end
    end

end

local baseOnUpdate = ARC.OnUpdate
function ARC:OnUpdate(deltaTime)

    baseOnUpdate(self, deltaTime)

    local spec = ARCSpec.GetARCSpec(self)
    if not spec or not spec.mobile or not self:GetIsAlive() then
        return
    end

    -- Weapons are live only while deployed (it can still drive then). Undeployed, the turret rests.
    if self.deployMode ~= ARC.kDeployMode.Deployed then
        self.arcSpecPulsesLeft = 0
        StopCannonCharge(self)
        AimBarrel(self, nil, deltaTime)
        return
    end

    local tier = ARCSpec.GetUpgradeTier(self)
    local eye = self:GetEyePos()
    local now = Shared.GetTime()

    if spec == ARCSpec.kSpecs.vanguard then
        UpdateVanguard(self, tier, eye, now, deltaTime)
    elseif spec == ARCSpec.kSpecs.inferno then
        UpdateInferno(self, tier, eye, now, deltaTime)
    end

end

--[[ ---------------------------------------------------------------------------------------------------------------------
    H.A.M.M.E.R. shell. Vanilla ARC:PerformAttack, with the Hammerworks upgrades applied; the mod's own wrapper (deadlock
    extension) is kept for every ARC.
]] ---------------------------------------------------------------------------------------------------------------------
local basePerformAttack = ARC.PerformAttack
function ARC:PerformAttack()

    if ARCSpec.GetARCSpec(self) ~= ARCSpec.kSpecs.hammer then
        return basePerformAttack(self)
    end

    local tier = ARCSpec.GetUpgradeTier(self)
    local stats = ARCSpec.kHammer
    local radius = tier >= 2 and stats.upgradedSplashRadius or ARC.kSplashRadius
    local damage = ARC.kAttackDamage * (tier >= 4 and stats.payloadDamageScalar or 1)

    local distToTarget = self.targetPosition and (self.targetPosition - self:GetOrigin()):GetLengthXZ()

    if distToTarget and distToTarget >= ARC.kMinFireRange and distToTarget <= ARC.kFireRange then

        self:TriggerEffects("arc_firing")
        GetEffectManager():TriggerEffects("arc_hit_primary", { effecthostcoords = Coords.GetTranslation(self.targetPosition) })

        local hitEntities = GetEntitiesWithMixinWithinRange("Live", self.targetPosition, radius)

        -- Hives take the Hivebreaker bonus; everything else the normal shell.
        local hives, others = {}, {}
        for _, target in ipairs(hitEntities) do
            if tier >= 1 and target:isa("Hive") then
                hives[#hives + 1] = target
            else
                others[#others + 1] = target
            end
        end

        RadiusDamage(others, self.targetPosition, radius, damage, self, true, nil, false)
        if #hives > 0 then
            RadiusDamage(hives, self.targetPosition, radius, damage * stats.hiveDamageScalar, self, true, nil, false)
        end

        local owner = self:GetOwner() or self
        for _, target in ipairs(hitEntities) do

            if HasMixin(target, "Effects") then
                target:TriggerEffects("arc_hit_secondary")
            end

            if tier >= 4 and target:GetIsAlive() and GetAreEnemies(self, target) and HasMixin(target, "Fire") then
                target:SetOnFire(owner, self)
            end

        end

    end

    local currentOrder = self:GetCurrentOrder()
    if not currentOrder or currentOrder:GetType() ~= kTechId.Attack then
        self.targetPosition = nil
        self.targetedEntity = Entity.invalidId
    end

    local team = self:GetTeam()
    if team and team.OnDeadlockExtend then
        team:OnDeadlockExtend(kTechId.ARCDeploy)
    end

end
