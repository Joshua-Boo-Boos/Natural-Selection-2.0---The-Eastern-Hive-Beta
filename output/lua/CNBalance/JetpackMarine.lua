JetpackMarine.kBountyThreshold = kBountyClaimMinJetpack
JetpackMarine.kKDRatioMaxDamageReduction = 0.2

-- Task 8: Extra Fuel — override GetFuel to support +30% capacity (use rate / 1.3).
-- Reproduces vanilla math (NS2-Copy/ns2/lua/JetpackMarine.lua lines 160-178) exactly,
-- except the use rate is divided by 1.3 when PrototypeJetpackExtraFuel is active.
function JetpackMarine:GetFuel()

    local dt = Shared.GetTime() - self.timeJetpackingChanged

    -- more weight means the Jetpack has to provide more force to lift the marine
    -- and therefore consumes more fuel
    local weightFactor = math.max( self:GetWeaponsWeight() / kJetpackWeightLiftForce, kMinWeightJetpackFuelFactor )
    local useRate = kJetpackUseFuelRate
    if self:GetHasPrototypeUpgrade(kTechId.PrototypeJetpackExtraFuel) then
        useRate = kJetpackUseFuelRate / 1.3
    end

    local rate = -useRate * weightFactor
    if not self.jetpacking then
        if self:GetHasPrototypeUpgrade(kTechId.PrototypeBoost) then
            if not self:GetIsOnGround() then
                -- Airborne: freeze fuel; no drain (jetpack off), no replenish.
                rate = 0
            elseif not self._boostGroundedAt
                or (Shared.GetTime() - self._boostGroundedAt) < 0.4 then
                -- Just landed: wait 0.4 s of continuous ground contact before replenishing (was 0.66s/2/3s).
                rate = 0
            else
                -- Boost has ~4/3× the effective fuel capacity of a base Jetpack
                -- (3 boosts × 33% each = 99%), so scale the replenish rate down by
                -- 1/1.33 so a full 0→1 recharge takes proportionally longer (~4/3×).
                rate = kJetpackReplenishFuelRate * (1 / 1.33)
                dt   = math.max(0, dt - JetpackMarine.kJetpackFuelReplenishDelay)
            end
        else
            rate = kJetpackReplenishFuelRate
            dt   = math.max(0, dt - JetpackMarine.kJetpackFuelReplenishDelay)
        end
    end

    if self:GetDarwinMode() then
        return 1
    else
        return Clamp(self.jetpackFuelOnChange + rate * dt, 0, 1)
    end

end

-- Task 9: Boost constants
JetpackMarine.kPrototypeBoostCooldown = 0.75   -- 0.75 s cooldown
-- Was 0.20, then 0.10 (halved). Per this request, +20% on top of that 0.10:
-- 0.12 -> ~8.3 boosts per full tank without Extra Fuel (down from 10, since
-- each boost now costs more). Extra Fuel's existing /1.33 scaling still
-- applies on top automatically.
JetpackMarine.kPrototypeBoostFuelCost = 0.10 * 1.2  -- 12% of the normalized pool
-- kPrototypeBoostSpeedBase is the OLD (pre-this-change) horizontal impulse -
-- kept as the reference point for both the new burst AND the new settle speed
-- below, so "twice the thrust, +15% net distance" are both defined relative
-- to the previously-tuned feel rather than to each other.
local kPrototypeBoostSpeedBase = 6.072 * 1.10  -- horizontal impulse (8.096 × 0.75), +10%
-- Thrust progression across requests, each stage kept as its own named
-- reference (rather than overwriting the same variable) so later derivations
-- below can reference the value AT THE TIME they were solved:
--   base*1.5      (Task 9 "reduce 2x to 1.5x")
--   Pre50*1.5     (+50% thrust request, preserving old net distance)
--   Pre20*1.2     (THIS request: +20% thrust)
local kPrototypeBoostSpeedPre50 = kPrototypeBoostSpeedBase * 1.5
local kPrototypeBoostSpeedPre20 = kPrototypeBoostSpeedPre50 * 1.5
local kPrototypeBoostSpeed      = kPrototypeBoostSpeedPre20 * 1.2

-- Vertical impulse: previously tied to horizontal thrust (height = half of
-- distance), but per this request that made vertical height "too much" - it's
-- now an ABSOLUTE physics target instead, fully decoupled from horizontal:
-- exactly 2/3 of a baseline (unslowed) Marine's own jump HEIGHT.
-- Standard projectile kinematics: height = v^2/(2g)  =>  v = sqrt(2*g*h).
-- Marine's jump: h_marine = Player.kJumpHeight (1.25), g = -Player.kGravity (21.5).
-- Since height is proportional to v^2, targeting (2/3) of h_marine means
-- targeting sqrt(2/3) of the Marine's own jump VELOCITY.
local kMarineJumpGravity      = -Player.kGravity   -- positive magnitude (21.5)
local kMarineJumpHeight       = Player.kJumpHeight  -- baseline, unslowed (1.25)
local kMarineJumpVelocity     = math.sqrt(2 * kMarineJumpGravity * kMarineJumpHeight)
local kPrototypeBoostVertical = kMarineJumpVelocity * math.sqrt(2 / 3)

-- Post-boost drag: Player/JetpackMarine have ZERO ambient air friction
-- (Player:GetAirFriction/JetpackMarine's kFlyFriction are both 0), so without
-- this the boost's burst speed would simply glide unchanged for the whole
-- flight. Instead, for kPrototypeBoostDragDuration seconds after a boost, XZ
-- speed is actively pulled DOWN from the burst toward a lower "settle" cruise
-- speed - the player gets a strong initial kick (extra ground covered while
-- decaying) but then settles to a steady cruise pace instead of coasting at
-- the full burst speed forever. Applied every server tick in TryPrototypeBoost.
-- Settle speed progression (same "keep each stage's reference" pattern as
-- thrust above): base*1.15 (Task 9) -> *1.2 (THIS request: +20% max horizontal
-- distance - settle speed is the dominant driver of sustained distance, since
-- flight time is external/unaffected by these constants).
local kPrototypeBoostSettleSpeedPre20 = kPrototypeBoostSpeedBase * 1.15
local kPrototypeBoostSettleSpeed      = kPrototypeBoostSettleSpeedPre20 * 1.2

-- kPrototypeBoostDragDuration is DELIBERATELY left computed from the PRE-20%
-- burst/settle values (unchanged from the previous request) rather than
-- re-derived against the new +20% values. The decay is linear, so the extra
-- ground covered above settle speed during the decay window is the triangular
-- area 0.5*(burstSpeed - settleSpeed)*duration; leaving duration exactly as it
-- was while burst AND settle both scale by the same 1.2x makes that "extra"
-- area also scale by exactly 1.2x - so together with the 1.2x on settle*time,
-- TOTAL horizontal distance scales up by a clean, uniform 20%, matching this
-- request precisely (rather than solving a different distance-preservation
-- invariant, which was only what the PREVIOUS +50%-thrust request needed).
local kPrototypeBoostPreThrustBumpDuration = 0.35  -- the ORIGINAL (2 requests ago) duration
local kPrototypeBoostDragDuration = kPrototypeBoostPreThrustBumpDuration
    * (kPrototypeBoostSpeedPre50  - kPrototypeBoostSettleSpeedPre20)
    / (kPrototypeBoostSpeedPre20  - kPrototypeBoostSettleSpeedPre20)

-- Maximum XZ speed achievable through repeated boosts.  Uses the same weight
-- penalty formula as kFlySpeed so heavier loadouts have a lower cap.
-- Raised in proportion to the new SETTLE speed (1.15x), not the transient 2x
-- burst - chained boosts should compound toward the new sustainable cruise
-- ceiling, not the brief post-burst spike.
local kBoostMaxXZSpeed        = 13.0 * 1.15  -- design-px/s cap; tune in-game

JetpackMarine.kHealth = kJetpackHealth

function JetpackMarine:GetArmorAmount(armorLevels)

    local hasMP = GetHasTech(self,kTechId.MilitaryProtocol)
    if not armorLevels then

        armorLevels = 0

        if GetHasTech(self, kTechId.Armor3, true) then
            armorLevels = 3
        elseif GetHasTech(self, kTechId.Armor2, true) then
            armorLevels = 2
        elseif GetHasTech(self, kTechId.Armor1, true) then
            armorLevels = 1
        end

    end

    -- Task 7: Armour Plating — +20 AP when prototype upgrade is active.
    local armourPlatingBonus = self:GetHasPrototypeUpgrade(kTechId.PrototypeJetpackArmour) and 20 or 0

    return hasMP and (kMPJetpackMarineArmor + armorLevels * kMPJetpackArmorPerUpgradeLevel + armourPlatingBonus)
    or (kJetpackArmor + armorLevels * kJetpackArmorPerUpgradeLevel + armourPlatingBonus)

end

--function JetpackMarine:GetIsStunAllowed()
--    return false
--end

if Server then
    function JetpackMarine:GetAutoHealPerSecond(lifeSustainResearched)
        return lifeSustainResearched and kJetpackLifeSustainHPS or kJetpackLifeRegenHPS
    end
    
    function JetpackMarine:GetAutoWeldArmorPerSecond(nanoArmorResearched)
        return nanoArmorResearched and kJetpackMarineNanoArmorPerSecond or kJetpackMarineArmorPerSecond
    end
end

function JetpackMarine:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint) -- dud
    local reduction = kJetpackDamageReduction[doer:GetClassName()]
    if reduction then
        damageTable.damage = damageTable.damage * reduction
        return
    end
end

--function JetpackMarine:OnWebbed()   --突然离世
--    if not self:GetIsOnGround() then
--        self:SetStun(kDisruptMarineTime)
--    end
--end

local kFlySpeed = 9
local kFlyAcceleration = 28
function JetpackMarine:ModifyVelocity(input, velocity, deltaTime)

    if self:GetIsJetpacking() then

        local verticalAccel = 22

        if self:GetIsWebbed() then
            verticalAccel = 5
        elseif input.move:GetLength() == 0 then
            verticalAccel = 26
        end

        self.onGround = false
        local thrust = math.max(0, -velocity.y) / 6
        velocity.y = math.min(5, velocity.y + verticalAccel * deltaTime * (1 + thrust * 2.5))

    end

    if not self.onGround then

        -- do XZ acceleration
        local prevXZSpeed = velocity:GetLengthXZ()
        local maxSpeedTable = { maxSpeed = math.max(kFlySpeed - math.max(self:GetWeaponsWeight() - kRifleWeight , 0) * 33, prevXZSpeed) }       --multiplier per 0.01 weight above
        self:ModifyMaxSpeed(maxSpeedTable)
        local maxSpeed = maxSpeedTable.maxSpeed

        if not self:GetIsJetpacking() then
            maxSpeed = prevXZSpeed
        end

        local wishDir = self:GetViewCoords():TransformVector(input.move)
        local acceleration = 0
        wishDir.y = 0
        wishDir:Normalize()

        acceleration = kFlyAcceleration
        acceleration = acceleration

        velocity:Add(wishDir * acceleration * self:GetInventorySpeedScalar() * deltaTime)

        if velocity:GetLengthXZ() > maxSpeed then

            local yVel = velocity.y
            velocity.y = 0
            velocity:Normalize()
            velocity:Scale(maxSpeed)
            velocity.y = yVel

        end

        if self:GetIsJetpacking() then
            velocity:Add(wishDir * kJetpackingAccel * deltaTime)
        end

    end

end

-- Task 9: Boost — directional velocity impulse with 1.5s cooldown and 20% fuel cost.
if Server then

function JetpackMarine:TryPrototypeBoost(input, wasOnGround)

    if not self:GetHasPrototypeUpgrade(kTechId.PrototypeBoost) then return end

    -- Moved up from further below (was declared right before the cooldown gate)
    -- so the post-boost drag block, which also needs it, can run first.
    local now = Shared.GetTime()

    -- Post-boost drag: runs EVERY tick (not gated on a new jump press below),
    -- so a burst keeps decaying toward its settle speed on every frame after
    -- it fires, not just on frames with a fresh boost. Player/JetpackMarine
    -- have zero ambient air friction, so without this a boosted player would
    -- simply glide at the full burst speed for the whole flight.
    if self._boostDragStartTime then
        if wasOnGround then
            -- Landed: ground friction (Player:GetGroundFriction) takes over
            -- from here; stop managing airborne boost speed.
            self._boostDragStartTime = nil
        else
            local elapsed = now - self._boostDragStartTime
            if elapsed >= kPrototypeBoostDragDuration then
                self._boostDragStartTime = nil
            else
                local vel   = self:GetVelocity()
                local xzLen = math.sqrt(vel.x * vel.x + vel.z * vel.z)
                local frac  = elapsed / kPrototypeBoostDragDuration
                local target = self._boostDragStartXZSpeed
                    + (self._boostDragSettleXZSpeed - self._boostDragStartXZSpeed) * frac
                -- Only ever pull speed DOWN toward the decaying target - never push
                -- it back up, so this never fights normal air control/gravity.
                if xzLen > target and xzLen > 0.001 then
                    local s = target / xzLen
                    vel.x = vel.x * s
                    vel.z = vel.z * s
                    self:SetVelocity(vel)
                end
            end
        end
    end

    -- Trigger only on a fresh JUMP press (rising edge), NOT continuously every tick.
    local jumpDown = bit.band(input.commands, Move.Jump) ~= 0
    local jumpPressed = jumpDown and not self._boostJumpDownLastFrame
    self._boostJumpDownLastFrame = jumpDown

    -- Ground phase: arm boost when jump is held, disarm when jump is released.
    -- CRITICAL: if the player lands with jump ALREADY held (rapid spam-jumping),
    -- we must ARM (not disarm) — the old "disarm if no rising edge on ground"
    -- caused the boost to fail every second consecutive jump.
    if wasOnGround then
        self._boostArmed = jumpDown   -- arm on any ground+jump; disarm on ground+no-jump
        self._boostBecameAirborneAt = nil
        return                        -- never boost from ground regardless
    end

    -- Require a minimum of 0.15 s in the air before allowing the boost.
    -- This prevents GetIsOnGround() returning false on the same frame the
    -- player jumps (edge/slope edge cases) from triggering the boost immediately.
    if not self._boostBecameAirborneAt then
        self._boostBecameAirborneAt = now
    end
    if (now - self._boostBecameAirborneAt) < 0.15 then return end

    -- Airborne: require a fresh rising-edge press to activate.
    if not jumpPressed then return end

    -- Airborne jump press: boost only if a prior ground jump armed it.  Because the
    -- player must release the jump key to produce a new rising edge, this enforces
    -- the press → release → press-again sequence before a boost occurs.
    if not self._boostArmed then return end

    -- Cooldown gate.
    if now < (self.timePrototypeBoostNext or 0) then return end

    -- Horizontal movement direction: movement intent first, then current velocity.
    -- If no horizontal direction can be found (stationary), boost straight up.
    local vel  = self:GetVelocity()
    local wish = self:GetViewCoords():TransformVector(input.move)
    wish.y = 0
    local dir
    if wish:GetLength() > 0.01 then
        dir = GetNormalizedVector(wish)
    else
        local horiz = Vector(vel.x, 0, vel.z)
        if horiz:GetLength() > 0.5 then
            dir = GetNormalizedVector(horiz)
        end
    end
    -- dir is nil exactly when the player is stationary; the vertical-only
    -- branch below (else of "if dir then") relies on this.

    -- Effective cost: 10% of standard pool (1.0) → 10 boosts per full tank.
    -- With Extra Fuel the logical pool is 133% of standard, so we scale the
    -- cost down by the same factor so the player gets more boosts per tank.
    --   Standard:   floor(1.00 / 0.10  ) = 10 boosts
    --   Extra Fuel: floor(1.00 / 0.0752) = 13 boosts  (0.10 / 1.33 ≈ 0.0752)
    local boostCost = JetpackMarine.kPrototypeBoostFuelCost
    if self:GetHasPrototypeUpgrade(kTechId.PrototypeJetpackExtraFuel) then
        boostCost = boostCost / 1.33
    end
    if self:GetFuel() < boostCost then return end

    local newVel = vel
    if dir then
        newVel = newVel + dir * kPrototypeBoostSpeed
    else
        -- Vertical boost: ONLY given when the player is not moving (dir is nil
        -- here exactly when there's no movement intent AND negligible residual
        -- horizontal velocity - the same stationary check that already gates
        -- "boost straight up" below). Flat kPrototypeBoostVertical every time -
        -- no look-angle multiplier (removed per request), since that value is
        -- itself already derived to be exactly the amount needed for the
        -- height/distance relationship above.
        newVel.y = newVel.y + kPrototypeBoostVertical
    end

    -- Cap XZ speed so repeated boosts cannot accumulate speed indefinitely.
    -- The cap scales down with weapon weight (same 33× penalty as kFlySpeed).
    local maxXZ = math.max(
        kBoostMaxXZSpeed - math.max(self:GetWeaponsWeight() - kRifleWeight, 0) * 33,
        kFlySpeed)
    local xzLen = math.sqrt(newVel.x * newVel.x + newVel.z * newVel.z)
    if xzLen > maxXZ then
        local s = maxXZ / xzLen
        newVel.x = newVel.x * s
        newVel.z = newVel.z * s
    end

    self:SetVelocity(newVel)
    self:SetFuel(self:GetFuel() - boostCost)
    self.timePrototypeBoostNext = now + JetpackMarine.kPrototypeBoostCooldown

    -- Arm the post-boost drag decay (applied every tick at the top of this
    -- function - see above): starts at whatever XZ speed this burst actually
    -- reached (post-cap), decays down to the weight-scaled settle speed over
    -- kPrototypeBoostDragDuration seconds.
    self._boostDragStartTime     = now
    self._boostDragStartXZSpeed  = math.sqrt(newVel.x * newVel.x + newVel.z * newVel.z)
    self._boostDragSettleXZSpeed = math.max(
        kPrototypeBoostSettleSpeed - math.max(self:GetWeaponsWeight() - kRifleWeight, 0) * 33,
        kFlySpeed)

    -- Play the jetpack loop sound for the duration of the airborne period.
    -- The SoundEffect entity (jetpackLoopId) is always created in OnInitialized;
    -- we just start/stop it manually rather than via HandleJetPackStart/End.
    local loop = Shared.GetEntity(self.jetpackLoopId)
    if loop and not self._boostSoundPlaying then
        loop:Start()
        self._boostSoundPlaying = true
    end

end

end -- if Server

-- Task 9 (continued): When a player has the Boost upgrade, standard jetpack
-- flight (hold-jump-to-hover) is disabled entirely.  Only the normal ground
-- jump and the mid-air directional Boost (TryPrototypeBoost) are available.
-- We wrap UpdateJetpack (the method that calls HandleJetpackStart/End) and skip
-- it entirely for Boost owners, stopping any residual flight immediately.
local baseJPMUpdateJetpack = JetpackMarine.UpdateJetpack
function JetpackMarine:UpdateJetpack(input)
    if self:GetHasPrototypeUpgrade(kTechId.PrototypeBoost) then
        -- Stop any active jetpack flight that may have slipped through (e.g. the
        -- player purchased Boost while already airborne with jetpack on).
        if self.jetpacking then
            self:HandleJetPackEnd()
        end
        return  -- block all jetpack start/stop logic
    end
    baseJPMUpdateJetpack(self, input)
end

-- Hook Boost into the move processing path (post pattern: save base, call base, then try boost).
-- Capture the ground state BEFORE the base processes this move's jump — otherwise a
-- standing jump has already left the ground by the time TryPrototypeBoost runs, and
-- it would boost on the very first press.
local baseJPMOnProcessMove = JetpackMarine.OnProcessMove
function JetpackMarine:OnProcessMove(input)
    local wasOnGround = self:GetIsOnGround()
    -- Snapshot fuel before the move so we can commit it on ground-state transitions.
    local fuelBeforeMove = self:GetFuel()
    baseJPMOnProcessMove(self, input)

    local nowOnGround = self:GetIsOnGround()
    local now         = Shared.GetTime()

    if self:GetHasPrototypeUpgrade(kTechId.PrototypeBoost) then
        if wasOnGround and not nowOnGround then
            -- Lift-off: commit the replenished fuel NOW so that when rate drops to 0
            -- airborne, GetFuel() returns the correct value instead of snapping back
            -- to the old landing-time jetpackFuelOnChange.
            -- Run on BOTH client and server: jetpackFuelOnChange is a compensated
            -- netvar designed for client-side prediction; the server value will
            -- reconcile any small discrepancy on the next sync.
            self.jetpackFuelOnChange  = Clamp(fuelBeforeMove, 0, 1)
            self.timeJetpackingChanged = now
            self._boostGroundedAt = nil
        elseif not wasOnGround and nowOnGround then
            -- Landing: commit frozen fuel and start the ground-contact delay timer.
            self.jetpackFuelOnChange  = Clamp(fuelBeforeMove, 0, 1)
            self.timeJetpackingChanged = now
            self._boostGroundedAt = now
        end
    end

    if Server then
        self:TryPrototypeBoost(input, wasOnGround)
        -- Stop the jetpack loop sound when the player lands after a boost.
        if self._boostSoundPlaying and nowOnGround then
            local loop = Shared.GetEntity(self.jetpackLoopId)
            if loop then loop:Stop() end
            self._boostSoundPlaying = false
        end
    end
end

-- Reconstructed networkVars for JetpackMarine (verbatim from vanilla JetpackMarine.lua lines 48-71)
-- plus PrototypeUpgradesMixin netvar. Re-linked with true (4th arg) as per vanilla.
local networkVars =
{
    -- jetpack fuel is dervived from the three variables jetpacking, timeJetpackingChanged and jetpackFuelOnChange
    -- time since change has the kJetpackFuelReplenishDelay subtracted if not jetpacking
    -- jpFuel = Clamp(jetpackFuelOnChange + time since change * gain/loss rate, 0, 1)
    -- If jetpack is currently active and affecting our movement. If active, use loss rate, if inactive use gain rate
    jetpacking = "compensated boolean",
    -- when we last changed state of jetpack
    timeJetpackingChanged = "compensated time",
    -- amount of fuel when we last changed jetpacking state
    jetpackFuelOnChange = "compensated float (0 to 1 by 0.01)",

    startedFromGround = "boolean",

    equipmentId = "entityid",
    jetpackMode = "enum JetpackMarine.kJetpackMode",

    jetpackLoopId = "entityid",

    fuelWarningId = "private entityid",

    jumpedInAir = "private compensated boolean",

    -- Time at which the prototype Boost becomes available again. Networked
    -- (private = owner only) so the HUD can show the remaining cooldown.
    timePrototypeBoostNext = "private time",

    -- Skulk Parasite "Infection" meter state (mirrored from Marine.lua Task 2).
    -- JetpackMarine re-links with its own networkVars, so these must be declared here too.
    infectionHitCount = "private integer (0 to 3)",
    infectionWasFullyInfected = "private boolean",
    infectionLastHitTime = "private time",

}

AddMixinNetworkVars(PrototypeUpgradesMixin, networkVars)

Shared.LinkClassToMap("JetpackMarine", JetpackMarine.kMapName, networkVars, true)

local baseJPMOnCreate = JetpackMarine.OnCreate
function JetpackMarine:OnCreate()
    baseJPMOnCreate(self)
    InitMixin(self, PrototypeUpgradesMixin)
end

-- Restore the jetpack prototype upgrades (e.g. Boost) that were remembered by the
-- exosuit we ejected out of, so they are not lost across marine→exo→marine.
if Server then
    local baseJPMCopyPlayerDataFrom = JetpackMarine.CopyPlayerDataFrom
    function JetpackMarine:CopyPlayerDataFrom(player)
        baseJPMCopyPlayerDataFrom(self, player)
        if player and player:isa("Exo") and player.prevPrototypeUpgradeBits ~= nil and self.SetPrototypeUpgrade then
            self.prototypeUpgradeBits = player.prevPrototypeUpgradeBits
        end
        -- Buying a jetpack replaces the Marine entity outright (Replace() in
        -- GiveJetpack) - without this, the fresh JetpackMarine's OnCreate
        -- would reset Skulk Parasite Infection state to 0, silently curing
        -- it and voiding any pending kill credit. Only Marine/JetpackMarine
        -- carry these fields (nil on Exo), so this is a no-op coming from Exo.
        -- infectionHitTimestamps must be carried too (deep-copied, not just
        -- referenced) - the build-up phase (Marine.lua OnProcessMove) reads
        -- straight from that array each frame, so a Marine mid-build-up
        -- (1 or 2 hits, not yet Infected!) that buys a jetpack would
        -- otherwise get a copied infectionHitCount with an empty timestamps
        -- array behind it, silently freezing the count forever (the
        -- build-up branch no-ops whenever the array is empty).
        if player and player.infectionHitCount ~= nil then
            self.infectionHitCount = player.infectionHitCount
            self.infectionWasFullyInfected = player.infectionWasFullyInfected
            self.infectionLastHitTime = player.infectionLastHitTime
            self.infectionDamageTicksApplied = player.infectionDamageTicksApplied
            self.infectionCreditedIsCommander = player.infectionCreditedIsCommander
            self.infectionCreditedAttackerId = player.infectionCreditedAttackerId
            self.infectionHitTimestamps = {}
            if player.infectionHitTimestamps then
                for i, t in ipairs(player.infectionHitTimestamps) do
                    self.infectionHitTimestamps[i] = t
                end
            end
        end
    end
end