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
--[[
    (2026-10-14) REBALANCE: every upgrade costs the same (ARCSpec.kUpgradeCosts) and adds about the same power, instead
    of weak early levels and one big jump at the end. Rough sustained damage per second against a lifeform:
      V.A.T.:  7.9 -> 14 -> 17.9 -> 23.6 -> 26.5 (railgun, heavy) - a machine gun; scaled to 70%, then 75% of that
      H.E.L.L.: 7.9 -> 14.2 -> 18.9 -> 23.6 -> 26.3 (level 4 a continuous stream; a flamethrower; scaled to 70%, then 75% of that), plus the burn of SetOnFire at EVERY level (the mod's fire DOT)
]]
ARCSpec.kVanguard =
{
    mgDamage = 10, mgDamageType = kDamageType.Normal,
    cannonRange = 22.5, cannonChargeTime = 1,
    -- Index = upgrades researched. mg: range / seconds between shots. cannon: from level 2.
    --[[
        (2026-10-14) A REAL MACHINE GUN: low damage per bullet, machine-gun fire rate (5 - 8 rounds a second). Sustained
        damage per second against a lifeform (after the 70% and then 75% scaling): 7.9 -> 14 -> 17.9 -> 23.6 -> 26.5 (railgun, heavy).
        mgDamage is per bullet at each level.
    ]]
    levels =
    {
        -- (2026-10-14) Every damage value was 70% of the first machine-gun balance (3 / 4 / 45 / 3.5 / 70); then scaled by a
        -- further 75% (Joshua) - 52.5% of that balance, the same as the H.E.L.L.
        [0] = { mgRange = 12, mgInterval = 0.2,   mgDamage = 1.575 },
        [1] = { mgRange = 20, mgInterval = 0.15,  mgDamage = 2.1 },
        [2] = { mgRange = 20, mgInterval = 0.15,  mgDamage = 2.1, cannon = { damage = 23.625, damageType = kDamageType.Normal, interval = 6 } },
        -- Autoloader: the machine gun's fire rate jumps to 10 rounds a second, 30 m, and the cannon reloads faster.
        [3] = { mgRange = 30, mgInterval = 0.1, mgDamage = 1.8375, cannon = { damage = 23.625, damageType = kDamageType.Normal, interval = 4.5 } },
        [4] = { mgRange = 30, mgInterval = 0.1, mgDamage = 1.8375, cannon = { damage = 36.75, damageType = kDamageType.Heavy, interval = 4.5, railgun = true } },
    },
}
ARCSpec.kVanguard.mgRange = ARCSpec.kVanguard.levels[4].mgRange   -- longest reach (tech data range circle)

ARCSpec.kInferno =
{
    -- pulses: how many 0.25 s pulses one burst lasts. igniteStacks: SetOnFire calls per pulse (the mod's fire system only
    -- lights a target once its burn stack reaches the burn rate - 5 per call against 8 per second for a player - so a lone
    -- call never lit anything; two do). Every level sets targets on fire.
    --[[
        (2026-10-14) A REAL FLAMETHROWER. The old bursts (every 2 - 3 s) needed 5 - 12 s of uninterrupted flame to kill a
        Skulk, which simply walked out of the short range - a level 2 H.E.L.L. could not solo one. Simulated against a
        Skulk (67 HP, 10 AP) with the real fire rules (each SetOnFire call delays the burn by 1 s, so the burn only adds
        damage between bursts), after the 70% scaling: 8 s -> 4.25 s -> 3.25 s -> 2.5 s -> 2.25 s from level 0 to 4.
        Direct damage per second 10.5 -> 18.9 -> 25.2 -> 31.5 -> 35, the same ladder as the V.A.T., for a much shorter range plus the burn,
        the splash and burning projectiles and clouds.
    ]]
    -- (2026-10-14) Every damage value was 70% of the flamethrower balance above (15 / 9 / 12 / 15 / 12.5); then scaled by
    -- a further 75% (Joshua) - 52.5% of that balance. Direct damage per second now 7.9 -> 14.2 -> 18.9 -> 23.6 -> 26.3.
    [0] = { range = 5,  interval = 1.0,  pulses = 1, damage = 7.875,  igniteStacks = 2 },
    [1] = { range = 7,  interval = 1.0,  pulses = 3, damage = 4.725,  igniteStacks = 2 },
    [2] = { range = 10, interval = 1.0,  pulses = 3, damage = 6.3,    igniteStacks = 2 },
    [3] = { range = 12, interval = 1.0,  pulses = 3, damage = 7.875,  igniteStacks = 2 },
    -- Level 4: a CONTINUOUS stream - a damage pulse every 0.25 s, no cooldown (4.5 x 4 = 18 damage per second, up from
    -- level 3's 13.2). One ignite call per pulse is already 4 a second, enough to keep targets lit. Separately, EVERY
    -- update it sweeps away every projectile and cloud in range it has a line of fire to (sweepHazards, UpdateInferno).
    [4] = { range = 14, interval = 0.25, pulses = 1, damage = 6.5625, igniteStacks = 1, sweepHazards = true },
    pulseSpacing = 0.25,
    splash = 1.5,
}

ARCSpec.kHammer =
{
    -- (2026-10-14) Level order: 1 armour, 2 radius, 3 damage + fire, 4 Hive damage.
    damageTakenScalar = 0.75,    -- upgrade 1
    upgradedSplashRadius = 10,   -- upgrade 2 (normal ARC: ARC.kSplashRadius, 7)
    payloadDamageScalar = 1.2,   -- upgrade 3, plus setting everything in the blast on fire
    hiveDamageScalar = 1.25,     -- upgrade 4
}
local kHammerArmourTier, kHammerRadiusTier, kHammerPayloadTier, kHammerHiveTier = 1, 2, 3, 4

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
--[[
    (2026-10-14) Kill feed: a specialised ARC's kills (its shells, machine gun, cannon, flame AND the fire it sets - the
    fire's damage is dealt with the ARC as the doer) show "H.A.M.M.E.R." / "V.A.T." / "H.E.L.L." instead of the vanilla
    ARC icon (CNBalance/GUI/GUIDeathMessagesExo.lua).
]]
local kSpecDeathIcons = { hammer = "ARCSpecHammer", vanguard = "ARCSpecVanguard", inferno = "ARCSpecInferno" }
local baseGetDeathIconIndex = ARC.GetDeathIconIndex
function ARC:GetDeathIconIndex()
    local spec = ARCSpec.GetARCSpec(self)
    local iconIndex = spec and kDeathMessageIcon and rawget(kDeathMessageIcon, kSpecDeathIcons[spec.key] or "")
    if iconIndex then return iconIndex end
    if baseGetDeathIconIndex then return baseGetDeathIconIndex(self) end
    return kDeathMessageIcon.ARC
end

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
        local level = ARCSpec.kVanguard.levels[Clamp(ARCSpec.GetUpgradeTier(self), 0, 4)]
        return math.max(level.mgRange, level.cannon and ARCSpec.kVanguard.cannonRange or 0)
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
    if ARCSpec.GetARCSpec(self) == ARCSpec.kSpecs.hammer and ARCSpec.GetUpgradeTier(self) >= kHammerArmourTier then
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

--[[
    (2026-10-14) Camouflage: exactly the Sentry's rule (vanilla CloakTargetFilter, TargetCache.lua) - a fully cloaked
    alien is never targeted, whatever the line of sight. Detection (Scan, Observatory) uncloaks it, which is what makes it
    targetable again. Used for target search, the H.E.L.L.'s attack order and every pulse of a burst, so a target that
    cloaks is dropped at once. (The flame's 1.5 m splash around a visible target is not targeting and still singes.)
]]
local function GetIsHiddenByCamo(target)
    return HasMixin(target, "Cloakable") and target:GetIsCloaked()
end

-- Priority of a target for a weapon ("mg", "cannon" or "flame"), lower is better; nil if it may not be targeted at all.
local function GetTargetPriority(self, target, weapon)

    if not GetIsAttackableEnemy(self, target) then return nil end
    if target:isa("Commander") then return nil end
    if GetIsHiddenByCamo(target) then return nil end

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

--[[
    (2026-10-14) The H.E.L.L. burns exactly what the Marine and Exo flamethrowers burn (CNBalance/Weapons/Marine/
    Flamethrower.lua): bile bombs, Whip bombs, Prowler Acid Spray (AcidMissile), Acid Rockets, Babbler pheromones, Spit and
    dot markers in flight, and Umbra, Storm, Mucous, Enzyme and Vortex clouds as well as spores.
]]
local kBombClasses = { "Bomb", "WhipBomb", "AcidMissile", "AcidRocketBomb", "BabblerPheromone", "Spit", "DotMarker" }
local kBombBurnRadius = 1.6
local kCloudClasses -- { className, radius }, built on first use so every class is loaded
local function GetCloudClasses()
    if not kCloudClasses then
        kCloudClasses = {}
        for _, name in ipairs({ "CragUmbra", "StormCloud", "MucousMembrane", "EnzymeCloud", "Vortex" }) do
            local cls = rawget(_G, name)
            if cls and cls.kRadius then
                kCloudClasses[#kCloudClasses + 1] = { name, cls.kRadius }
            end
        end
    end
    return kCloudClasses
end

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

local function GetIsCloud(entity)
    for _, entry in ipairs(GetCloudClasses()) do
        if entity:isa(entry[1]) then return true end
    end
    return false
end

local function GetIsHazard(entity)
    if entity == nil then return false end
    if entity:isa("SporeCloud") or GetIsCloud(entity) then return true end
    for _, className in ipairs(kBombClasses) do
        if entity:isa(className) then return true end
    end
    return false
end

local function BurnHazard(self, hazard)
    if hazard:isa("SporeCloud") then
        self:TriggerEffects("burn_spore", { effecthostcoords = Coords.GetTranslation(hazard:GetOrigin()) })
    elseif GetIsCloud(hazard) then
        self:TriggerEffects("burn_umbra", { effecthostcoords = Coords.GetTranslation(hazard:GetOrigin()) })
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

    for _, entry in ipairs(GetCloudClasses()) do
        for _, cloud in ipairs(GetEntitiesWithinRange(entry[1], fromPoint, reach + entry[2])) do
            if DistanceToSegment(cloud:GetOrigin(), fromPoint, toPoint) <= entry[2] then
                burned[#burned + 1] = cloud
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

--[[
    (2026-10-14) V.A.T. and H.E.L.L. damage scales LINEARLY with the lifeforms' HP and AP: Siege2.0-TEH gives every
    lifeform +20% (kSiegeAlienLifeformHPAPScalar = 1.2, its BalanceHealth.lua), so these weapons do +20% there too and
    kill in the same time as in NS2.0-TEH. Mods without the scalar use 1. (H.A.M.M.E.R. shells are anti-structure and
    do not use DoShot.)
]]
local function DoShot(self, damage, damageType, target, point, direction)
    damage = damage * (kSiegeAlienLifeformHPAPScalar or 1)
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
    local level = stats.levels[Clamp(tier, 0, 4)]
    local mgRange = level.mgRange
    local mgInterval = level.mgInterval
    local mgTarget = UpdateLock(self, "mg", mgRange, eye, now)
    local cannonTarget = level.cannon and UpdateLock(self, "cannon", stats.cannonRange, eye, now) or nil

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
        -- (2026-10-14) Machine-gun fire rate: every bullet due since the last update is fired (an ARC may update less
        -- often than its fire interval), as one hit of their combined damage and one tracer - at most 4 at once.
        local due = 1
        local last = self.arcSpecNextMG or now
        if now - last > mgInterval then due = math.min(4, 1 + math.floor((now - last) / mgInterval)) end
        self.arcSpecNextMG = now + mgInterval
        local point = GetAimPoint(mgTarget)
        DoShot(self, (level.mgDamage or stats.mgDamage) * due, stats.mgDamageType, mgTarget, point, GetNormalizedVector(point - eye))
        ARCSpec.SendShot(self, ARCSpec.kShotKind.mg, point)
    end

    if chargeTarget and now >= self.arcSpecChargeEnd and GetIsSporeBlocked(eye, GetAimPoint(chargeTarget)) then

        -- Spores drifted into the line of fire: the shot is lost (no cooldown - it charges again once clear).
        StopCannonCharge(self)

    elseif chargeTarget and now >= self.arcSpecChargeEnd then

        -- Fire, then the cooldown starts.
        self.arcSpecChargeEnd = nil
        self.arcSpecChargeTarget = nil
        local shell = level.cannon
        self.arcSpecNextCannon = now + (shell and shell.interval or 5)
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
    if target and GetIsAttackableEnemy(self, target) and not GetIsHiddenByCamo(target)
            and GetIsInReach(self, target, range, eye) then
        return target
    end
    return nil
end

local function BurnPulse(self, stats, target, eye)

    if not GetIsAttackableEnemy(self, target) or GetIsHiddenByCamo(target)
            or not GetIsInReach(self, target, stats.range, eye) then
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

--[[
    (2026-10-14) H.E.L.L. level 4: burn EVERY projectile and cloud within range that it has a line of fire to, each
    update (at most every kSweepInterval), independent of the damage stream. One flame visual per sweep that burned
    something, towards the nearest, so the network cost stays at one message per sweep.
]]
local kSweepInterval = 0.05
local function SweepHazards(self, range, eye, now)

    if now < (self.arcSpecNextSweep or 0) then return end
    self.arcSpecNextSweep = now + kSweepInterval

    local classNames = { "SporeCloud" }
    for _, className in ipairs(kBombClasses) do classNames[#classNames + 1] = className end
    for _, entry in ipairs(GetCloudClasses()) do classNames[#classNames + 1] = entry[1] end

    local burned, nearest, nearestDistance = {}, nil, nil
    for _, className in ipairs(classNames) do
        for _, hazard in ipairs(GetEntitiesWithinRange(className, eye, range)) do
            local origin = hazard:GetOrigin()
            if GetHasLineOfFire(self, hazard, eye, origin) then
                burned[#burned + 1] = hazard
                local distance = (origin - eye):GetLength()
                if not nearestDistance or distance < nearestDistance then
                    nearest, nearestDistance = origin, distance
                end
            end
        end
    end

    if nearest then
        ARCSpec.SendShot(self, ARCSpec.kShotKind.flame, nearest)
    end
    for _, hazard in ipairs(burned) do
        BurnHazard(self, hazard)
    end

end

local function UpdateInferno(self, tier, eye, now, deltaTime)

    local stats = ARCSpec.kInferno[math.min(tier, 4)]

    if stats.sweepHazards then
        SweepHazards(self, stats.range, eye, now)
    end
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
                local cloudNames = { "SporeCloud" }
                for _, entry in ipairs(GetCloudClasses()) do cloudNames[#cloudNames + 1] = entry[1] end
                target = FindNearestHazard(self, cloudNames, stats.range, eye) or lock
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
    local radius = tier >= kHammerRadiusTier and stats.upgradedSplashRadius or ARC.kSplashRadius
    local damage = ARC.kAttackDamage * (tier >= kHammerPayloadTier and stats.payloadDamageScalar or 1)

    local distToTarget = self.targetPosition and (self.targetPosition - self:GetOrigin()):GetLengthXZ()

    if distToTarget and distToTarget >= ARC.kMinFireRange and distToTarget <= ARC.kFireRange then

        self:TriggerEffects("arc_firing")
        GetEffectManager():TriggerEffects("arc_hit_primary", { effecthostcoords = Coords.GetTranslation(self.targetPosition) })

        local hitEntities = GetEntitiesWithMixinWithinRange("Live", self.targetPosition, radius)

        -- Hives take the Hivebreaker bonus; everything else the normal shell.
        local hives, others = {}, {}
        for _, target in ipairs(hitEntities) do
            if tier >= kHammerHiveTier and target:isa("Hive") then
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

            if tier >= kHammerPayloadTier and target:GetIsAlive() and GetAreEnemies(self, target) and HasMixin(target, "Fire") then
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
