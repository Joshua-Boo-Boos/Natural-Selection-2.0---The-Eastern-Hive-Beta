
Script.Load("lua/Weapons/Marine/ClipWeapon.lua")
Script.Load("lua/PickupableWeaponMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")
Script.Load("lua/PointGiverMixin.lua")
Script.Load("lua/Combat/CombatWeaponVariantMixin.lua")

class 'Cannon' (ClipWeapon)

Cannon.kMapName = "cannon"
Cannon.kModelName = PrecacheAsset("models/marine/heavy_cannon/heavy_cannon_world.model")
local kViewModelName = PrecacheAsset("models/marine/heavy_cannon/heavy_cannon_view.model")
local kAnimationGraph = PrecacheAsset("models/marine/heavy_cannon/heavy_cannon.animation_graph")

local kCannonBulletSize = 0.15

local kRange = 250
local kSpread = Math.Radians(1)
local kTracerCinematic = PrecacheAsset("cinematics/marine/cannon_tracer.cinematic")
local kTracerResidueCinematic = PrecacheAsset("cinematics/marine/cannon_tracer_residue.cinematic")

-- Task 12: Charge constants. Charge takes 60% of the original time (2 * 0.6 = 1.2).
Cannon.kChargeTime = 1.2
local kChargeForceShootTime = 1.32   -- 2.2 * 0.6
-- Charge-up loop sound (same sound the Railgun uses).  Driven as a controllable
-- client sound effect (created per-weapon) so it plays ONLY while charging and
-- stops the instant the shot fires / the weapon is holstered.
local kCannonChargeSound = PrecacheAsset("sound/NS2.fev/marine/heavy/railgun_charge")

-- Task 14: Shotgun constants
Cannon.kShotgunPellets  = 6
-- Doubled max spread angle (was 4.5 degrees) per design feedback.
Cannon.kShotgunMaxAngle = Math.Radians(4.5)

-- Task 13: Pierce second target gets FULL impact damage (1.0), but NO AOE.
-- AOE fires only at the first hit position; the pierce-through entity is excluded.
local kPierceDamageFraction = 1.0

-- AOE falloff stub — must be declared before any function that uses it
local function NoFalloff()
    return 0
end

local networkVars =
{
    -- Task 12: charge netvars — added before LinkClassToMap, no new class
    cannonChargeStart = "time",
    cannonCharging    = "boolean",
}

AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(CombatWeaponVariant, networkVars)
AddMixinNetworkVars(PrototypeUpgradesMixin, networkVars)


function Cannon:OnCreate()

    ClipWeapon.OnCreate(self)

    InitMixin(self, CombatWeaponVariant)
    InitMixin(self, PickupableWeaponMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, PointGiverMixin)
    InitMixin(self, PrototypeUpgradesMixin)

    if Client then
        InitMixin(self, ClientWeaponEffectsMixin)
    end

    -- Task 12: initialise charge netvars
    self.cannonChargeStart = 0
    self.cannonCharging    = false
    self._chargeAutoBlock  = false

end

function Cannon:OnInitialized()
    ClipWeapon.OnInitialized(self)
    if Client then
        -- Controllable charge-loop sound (started/stopped by UpdateChargeSound).
        self.chargeSound = Client.CreateSoundEffect(Shared.GetSoundIndex(kCannonChargeSound))
        self.chargeSound:SetParent(self:GetId())
    end
end

-- ============================================================
-- Charge sound lifecycle (client).  The loop plays ONLY while the cannon is
-- actually charging, and is stopped the instant the charge ends (shot fired) or
-- the weapon is holstered / destroyed.  Mirrors Railgun's chargeSound handling.
-- ============================================================
if Client then

    function Cannon:UpdateChargeSound()
        if not self.chargeSound then return end
        local chargeAmount = self:GetCannonChargeFraction()
        local playing = self.chargeSound:GetIsPlaying()
        if not playing and chargeAmount > 0 then
            self.chargeSound:Start()
        elseif playing and chargeAmount <= 0 then
            self.chargeSound:Stop()
        end
    end

    function Cannon:OnUpdateRender()
        -- Chain to the base Weapon:OnUpdateRender (via ClipWeapon) so the weapon
        -- view-model screen GUIView is created and rendered each frame.  Without
        -- this the screen stays black because GetUIDisplaySettings is never read.
        ClipWeapon.OnUpdateRender(self)
        self:UpdateChargeSound()
    end

    local baseCannonOnDestroyClient = Cannon.OnDestroy
    function Cannon:OnDestroy()
        if self.chargeSound then
            Client.DestroySoundEffect(self.chargeSound)
            self.chargeSound = nil
        end
        if baseCannonOnDestroyClient then
            baseCannonOnDestroyClient(self)
        else
            ClipWeapon.OnDestroy(self)
        end
    end

end

-- ============================================================
-- OnHolster — make sure a held charge does not persist (state + sound) when the
-- player switches away from the cannon mid-charge.
-- ============================================================
function Cannon:OnHolster(player)
    ClipWeapon.OnHolster(self, player)
    self.cannonCharging = false
    if Client and self.chargeSound and self.chargeSound:GetIsPlaying() then
        self.chargeSound:Stop()
    end
end

-- ============================================================
-- Task 10: Extended Magazine — dynamic clip and reserve size.
-- When the upgrade is absent this returns kCannonClipSize so
-- behaviour is exactly as before.  GetMaxAmmo() (from ClipWeapon)
-- = GetMaxClips()*GetClipSize(), so the reserve auto-scales.
-- ============================================================
function Cannon:GetClipSize()
    -- GetClipSize is called from ClipWeapon.OnCreate (base) BEFORE
    -- InitMixin(self, PrototypeUpgradesMixin) runs in Cannon:OnCreate, so the
    -- mixin method may not exist yet — guard against that to avoid a nil call.
    if self.GetHasPrototypeUpgrade and self:GetHasPrototypeUpgrade(kTechId.PrototypeExtendedMagazine) then
        return 9
    end
    return kCannonClipSize
end

-- Task 10: Called by PrototypeBuyServer after all upgrade flags are
-- set so that clip and ammo immediately reflect the new values.
function Cannon:OnPrototypeUpgradesApplied()
    self.clip = self:GetClipSize()
    self.ammo = self:GetMaxClips() * self:GetClipSize()
end

-- ============================================================
-- Task 12: Charge fraction (mirrors Railgun:GetChargeAmount,
-- Railgun.lua line 204).  Returns 0..1; 0 when not charging.
-- ============================================================
function Cannon:GetCannonChargeFraction()
    if self.cannonCharging then
        return math.min(1, (Shared.GetTime() - self.cannonChargeStart) / Cannon.kChargeTime)
    end
    return 0
end

-- ============================================================
-- Spread helpers.
-- CannonRandom is a local so it is in scope for both
-- CalculateSpreadDirection and ShotgunSpread.
-- ============================================================
local function CannonRandom()
    return math.max(0.2 + NetworkRandom())
end

function Cannon:CalculateSpreadDirection(shootCoords, player)
    local spread = self:GetSpread()
    -- Charge Shot fires a more accurate shot (0.7× spread angle).
    if self:GetHasPrototypeUpgrade(kTechId.PrototypeChargeShot) then
        spread = spread * 0.7
    end
    return CalculateSpread(shootCoords, spread * self:GetInaccuracyScalar(player), CannonRandom)
end

-- Task 14: wider spread cone for shotgun pellets
function Cannon:ShotgunSpread(shootCoords, player)
    return CalculateSpread(shootCoords, Cannon.kShotgunMaxAngle * self:GetInaccuracyScalar(player), CannonRandom)
end

-- ============================================================
-- Task 11 / Task 13: FireOnePellet
--
-- Traces one pellet along spreadDirection.
-- Non-pierce path mirrors ClipWeapon local FireBullets (lines 409-465).
-- Pierce path mirrors Railgun ExecuteShot TraceBox loop (lines 221-275).
--
-- applyAoe is true only for the first pellet per shot — AOE fires exactly
-- once regardless of numPellets or pierce targets.
-- ============================================================
function Cannon:FireOnePellet(player, spreadDirection, damage, doPierce, applyAoe, aoeScale)

    local startPoint = player:GetEyePos()
    local range      = self:GetRange()
    local bulletSize = self:GetBulletSize()
    local endPoint   = startPoint + spreadDirection * range

    -- Exclude player and weapon from traces (mirrors ClipWeapon FireBullets)
    local filter = EntityFilterTwo(player, self)

    local effectFrequency = self:GetTracerEffectFrequency()
    local showTracer      = math.random() < effectFrequency

    -- impactPoint is the position used for AOE; default to ray end.
    -- For pierce shots it is locked to the FIRST hit so AOE fires there.
    local impactPoint = endPoint

    if doPierce then

        -- -------------------------------------------------------
        -- Pierce loop — faithful to Railgun ExecuteShot (lines 221-275).
        -- TraceRay first to get max distance, then TraceBox loop
        -- to find entities along the capsule.  Cap at 2 damaged targets.
        -- Both targets take full impact damage.  AOE fires at target-1's
        -- position; target 2 gets AOE only if it is within AoE radius of
        -- that point (close targets share the blast, distant ones don't).
        -- -------------------------------------------------------
        local rayTrace = Shared.TraceRay(startPoint, endPoint,
                            CollisionRep.Damage, PhysicsMask.Bullets,
                            EntityFilterAllButIsa("Tunnel"))

        local direction      = (endPoint - startPoint):GetUnit()
        local extents        = GetDirectedExtentsForDiameter(direction, bulletSize)
        local traceHitPoint  = rayTrace.endPoint
        local hitPointOffset = rayTrace.normal * 0.3

        impactPoint = traceHitPoint

        HandleHitregAnalysis(player, startPoint, endPoint, rayTrace)

        local hitEntities = {}
        local targetsHit  = 0
        local pierceStart = startPoint

        for _ = 1, 20 do

            local capsuleTrace = Shared.TraceBox(extents, pierceStart, traceHitPoint,
                                    CollisionRep.Damage, PhysicsMask.Bullets, filter)

            if capsuleTrace.entity then

                if not table.find(hitEntities, capsuleTrace.entity) then

                    table.insert(hitEntities, capsuleTrace.entity)
                    targetsHit = targetsHit + 1

                    -- Both targets take full direct damage; second target skips AOE.
                    local pelletDamage = damage * kPierceDamageFraction

                    local hitPt = capsuleTrace.endPoint + hitPointOffset
                    -- Lock AOE origin to the first hit only.
                    if targetsHit == 1 then
                        impactPoint = hitPt
                    end

                    self:DoDamage(pelletDamage, capsuleTrace.entity, hitPt,
                                  direction, capsuleTrace.surface, false, false)

                    if targetsHit >= 2 then
                        break
                    end

                end

            end

            -- Stop when we've reached the end of the ray (mirrors Railgun line 256)
            if (capsuleTrace.endPoint - traceHitPoint):GetLength() <= extents.x then
                break
            end

            -- Advance start past this hit (mirrors Railgun line 261)
            pierceStart = Vector(capsuleTrace.endPoint) + direction * extents.x * 3

        end

        -- Broadcast tracer to other players via 0-damage DoDamage call
        -- (mirrors Railgun ExecuteShot line 268)
        self:DoDamage(0, nil, traceHitPoint + hitPointOffset,
                      direction, rayTrace.surface, false, showTracer)

        if Client and showTracer then
            TriggerFirstPersonTracer(self, traceHitPoint)
        end

    else

        -- -------------------------------------------------------
        -- Standard hitscan — mirrors ClipWeapon local FireBullets.
        -- -------------------------------------------------------
        local targets, trace, hitPoints = GetBulletTargets(startPoint, endPoint,
                                            spreadDirection, bulletSize, filter)

        HandleHitregAnalysis(player, startPoint, endPoint, trace)

        local direction  = (trace.endPoint - startPoint):GetUnit()
        local hitOffset  = direction * kHitEffectOffset
        impactPoint      = trace.endPoint - hitOffset

        local numTargets = #targets

        if numTargets == 0 then
            self:ApplyBulletGameplayEffects(player, nil, impactPoint, direction,
                                            0, trace.surface, showTracer)
        end

        if Client and showTracer then
            TriggerFirstPersonTracer(self, impactPoint)
        end

        for i = 1, numTargets do
            local target   = targets[i]
            local hitPoint = hitPoints[i]
            self:ApplyBulletGameplayEffects(player, target, hitPoint - hitOffset,
                                            direction, damage, "",
                                            showTracer and i == numTargets)

            local client = Server and player:GetClient() or Client
            if not Shared.GetIsRunningPrediction() and client.hitRegEnabled then
                RegisterHitEvent(player, 1, startPoint, trace, damage)
            end
        end

    end  -- end pierce / standard branch

    -- -------------------------------------------------------
    -- AOE — exactly once per trigger pull (applyAoe == true only
    -- for the first pellet, i == 1 in FirePrototype).
    -- aoeScale = chargeMult; 1.0 when Charge Shot not active.
    -- Mirrors original Cannon:OnBulletFirstHit call shape.
    -- -------------------------------------------------------
    if applyAoe then
        -- AOE fires at the first hit point (impactPoint set on targetsHit==1 above).
        -- Entities within kCannonAoeRadius take the blast; target 2 is only
        -- included if it happens to be close enough to that point, which
        -- naturally handles the "close together = both hit, far apart = only
        -- direct damage for target 2" case without explicit LOS logic.
        local hitEntitiesAoe = GetEntitiesWithMixinWithinRange("Live", impactPoint, kCannonAoeRadius)
        RadiusDamage(hitEntitiesAoe, impactPoint, kCannonAoeRadius,
                     kCannonAoeDamage * aoeScale, self, false, NoFalloff, false)
    end

end

-- ============================================================
-- Task 11/12/13/14: Composition function.
-- All upgrades compose through here.
-- With zero upgrades: 1 pellet, full kCannonDamage, no pierce,
-- chargeMult = 1, AOE once = kCannonAoeDamage. Identical to pre-
-- refactor behaviour.
-- ============================================================
function Cannon:FirePrototype(player)

    local hasShotgun = self:GetHasPrototypeUpgrade(kTechId.PrototypeShotgun)
    local hasPierce  = self:GetHasPrototypeUpgrade(kTechId.PrototypeTungstenPenetrator)
    local hasCharge  = self:GetHasPrototypeUpgrade(kTechId.PrototypeChargeShot)

    local numPellets = hasShotgun and Cannon.kShotgunPellets or 1
    -- chargeMult = 1 when Charge Shot not active, scales 1→1.35 at full charge
    local chargeMult = hasCharge and (1 + 0.35 * self:GetCannonChargeFraction()) or 1
    local shotDamage = kCannonDamage * chargeMult
    local perPellet  = shotDamage / numPellets

    local viewAngles  = player:GetViewAngles()
    local shootCoords = viewAngles:GetCoords()

    for i = 1, numPellets do

        local spreadDir
        if hasShotgun then
            spreadDir = self:ShotgunSpread(shootCoords, player)
        else
            spreadDir = self:CalculateSpreadDirection(shootCoords, player)
        end

        -- AOE only on first pellet (i == 1), aoeScale = chargeMult
        self:FireOnePellet(player, spreadDir, perPellet, hasPierce, (i == 1), chargeMult)

    end

    -- Charge state is cleared after firing (inside OnPrimaryAttackEnd or OnTag)
    -- so FirePrototype itself does not need to clear it; that keeps the fraction
    -- available for aoeScale and chargeMult already consumed above.

end

-- ============================================================
-- Task 11: FirePrimary — the entry point called by ClipWeapon:OnTag
-- when the "shoot" animation tag fires.  Routes to FirePrototype
-- for all upgrade combinations.  The charge path bypasses this
-- via OnTag override (see below) so FirePrimary is only reached
-- on the non-charge (normal fire) path.
-- ============================================================
function Cannon:FirePrimary(player)
    self:FirePrototype(player)
    self:TriggerEffects("cannon_attack")
end

-- ============================================================
-- Task 12: Charge state machine override of ClipWeapon:OnPrimaryAttack.
--
-- Charge Shot active:
--   Holding the trigger accumulates charge (cannonCharging = true).
--   No animation "shoot" tag fires during hold — we suppress the
--   normal ClipWeapon primaryAttacking → shoot → FirePrimary path
--   by NOT calling the base OnPrimaryAttack; instead we drive the
--   animation via primaryAttacking = true and fire on release.
--
-- Charge Shot NOT active:
--   Delegate entirely to ClipWeapon:OnPrimaryAttack so the normal
--   rapid-fire path (shoot tag → FirePrimary) is completely unchanged.
-- ============================================================
local baseOnPrimaryAttack    = ClipWeapon.OnPrimaryAttack
local baseOnPrimaryAttackEnd = ClipWeapon.OnPrimaryAttackEnd

function Cannon:OnPrimaryAttack(player)

    if self:GetHasPrototypeUpgrade(kTechId.PrototypeChargeShot) then

        if self:GetIsPrimaryAttackAllowed(player) then

            if self.clip > 0 then

                -- Start a new charge whenever not already charging.
                -- Rate limiting is enforced in OnPrimaryAttackEnd via _lastChargeShot.
                if not self.cannonCharging then
                    self.cannonChargeStart = Shared.GetTime()
                    self.cannonCharging    = true
                    self.cannonAnimUntil   = Shared.GetTime() + 0.3
                end

                if Shared.GetTime() < (self.cannonAnimUntil or 0) then
                    self.primaryAttacking    = true
                    self.attackLastRequested = Shared.GetTime()
                else
                    self.primaryAttacking    = false
                end

            elseif self.ammo > 0 then
                self:OnPrimaryAttackEnd(player)
                player:Reload()
            else
                self:OnPrimaryAttackEnd(player)
            end

            -- When fire rate is gating: don't call OnPrimaryAttackEnd — let the
            -- input system call it on genuine button release.  Calling it here was
            -- causing premature primaryAttacking clears and phantom end events.

        end

    else
        -- No Charge Shot — normal ClipWeapon rapid-fire behaviour
        baseOnPrimaryAttack(self, player)
    end

end

-- ============================================================
-- Task 12: OnPrimaryAttackEnd — fires the charged shot on release.
-- ============================================================
function Cannon:OnPrimaryAttackEnd(player)

    if self:GetHasPrototypeUpgrade(kTechId.PrototypeChargeShot) then

        local now   = Shared.GetTime()
        local fired = false
        -- Rate-limit: prevent spam-clicking from firing multiple shots per RoF window.
        local sinceLastShot = now - (self._lastChargeShot or 0)
        if self.cannonCharging and self.clip > 0
           and sinceLastShot >= kCannonRateOfFire then

            self:FirePrototype(player)
            self:TriggerEffects("cannon_attack")

            local p = self:GetParent()
            if not p or not p:GetDarwinMode() then
                self.clip = self.clip - 1
            end

            self.timeAttackFired  = now
            self._lastChargeShot  = now
            self.shooting         = true

            if self.clip == 0 and self.ammo > 0 then
                if p then p:Reload() end
            end

            fired = true
        end

        self.cannonCharging = false
        -- Delegate normal cleanup (primaryAttacking=false, timeAttackEnded, etc).
        baseOnPrimaryAttackEnd(self, player)

        -- After base cleared primaryAttacking, re-enable it for a brief window so
        -- the firing animation plays on the actual shot frame (not just at charge
        -- start).  ProcessMoveOnWeapon will clear it after cannonAnimUntil expires.
        if fired then
            self.primaryAttacking    = true
            self.attackLastRequested = Shared.GetTime()
            self.cannonAnimUntil     = Shared.GetTime() + 0.35
        end

    else
        baseOnPrimaryAttackEnd(self, player)
    end

end

-- ============================================================
-- Task 12: Force-fire when charge held too long.
-- Also clears the brief post-fire animation window set by OnPrimaryAttackEnd.
-- Mirrors Railgun:ProcessMoveOnWeapon (Railgun.lua lines 334-343).
-- ============================================================
function Cannon:ProcessMoveOnWeapon(player, input)

    ClipWeapon.ProcessMoveOnWeapon(self, player, input)

    if self.cannonCharging then
        if (Shared.GetTime() - self.cannonChargeStart) >= kChargeForceShootTime then
            self:OnPrimaryAttackEnd(player)
        end
    end

    -- Clear the fire-animation window opened in OnPrimaryAttackEnd once it expires.
    if not self.cannonCharging and self.primaryAttacking and self.cannonAnimUntil then
        if Shared.GetTime() >= self.cannonAnimUntil then
            self.primaryAttacking = false
            self.cannonAnimUntil  = nil
        end
    end

    -- (No _chargeAutoBlock: the cannon auto-recharges while the button is held.
    -- Spam-fire is prevented by the _lastChargeShot rate limit in OnPrimaryAttackEnd.)

end

-- ============================================================
-- Task 11/12: Cannon:OnTag — intercepts the "shoot" animation tag
-- when Charge Shot is active to prevent the base ClipWeapon path
-- (ClipWeapon:OnTag → FirePrimary) from firing during a charge hold.
-- All other tags (reload, deploy_end, etc.) pass through to the
-- base ClipWeapon:OnTag unchanged.
-- ============================================================
function Cannon:OnTag(tagName)

    PROFILE("Cannon:OnTag")

    if tagName == "shoot" and self:GetHasPrototypeUpgrade(kTechId.PrototypeChargeShot) then
        -- During charge mode the shot fires on release (OnPrimaryAttackEnd),
        -- not on the animation "shoot" tag.  Skip the base handler's fire+decrement.
        -- The animation still plays because primaryAttacking is kept true in
        -- OnPrimaryAttack; we just don't want to actually shoot here.
        return
    end

    ClipWeapon.OnTag(self, tagName)

end

-- ============================================================
-- Stub OnBulletFirstHit to no-op.
-- The original Cannon produced AOE here (called back from ClipWeapon
-- FireBullets via BulletsMixin).  AOE is now driven by FireOnePellet
-- (applyAoe flag), so this callback must not double-fire it.
-- The non-upgrade path no longer calls ClipWeapon.FirePrimary
-- (→ FireBullets), so this is defensive but explicit.
-- ============================================================
function Cannon:OnBulletFirstHit(spreadDirection, endPoint, target)
    -- AOE is applied inside FireOnePellet; this callback is intentionally empty.
end

if Client then

    function Cannon:OnClientPrimaryAttackStart()
        local player = self:GetParent()
    end

end

function Cannon:UpdateViewModelPoseParameters(viewModel)
end

function Cannon:GetAnimationGraphName()
    return kAnimationGraph
end

function Cannon:GetViewModelName()
    return kViewModelName
end

function Cannon:GetDeathIconIndex()
    return kDeathMessageIcon.Cannon
end

function Cannon:GetHUDSlot()
    return kPrimaryWeaponSlot
end

function Cannon:GetPrimaryMinFireDelay()
    -- Charge Shot uses the same rate-of-fire delay as the base cannon (0.88s).
    -- Spam-tapping at 0% charge should feel identical to the non-Charge-Shot cannon.
    -- The actual charge level determines bonus damage; the delay is not inflated.
    return kCannonRateOfFire
end

function Cannon:GetSpread()
    return kSpread
end

function Cannon:GetBulletDamage(target, endPoint)
    return kCannonDamage
end

function Cannon:GetBulletSize()
    return kCannonBulletSize
end

function Cannon:GetRange()
    return kRange
end

function Cannon:GetWeight()
    return kCannonWeight
end

function Cannon:GetPrimaryCanInterruptReload()
    return false
end

function Cannon:GetSecondaryCanInterruptReload()
    return false
end

function Cannon:GetHasSecondary(player)
    return false
end

function Cannon:GetCatalystSpeedBase()
    return 1
end

function Cannon:OnReload(player)

    if self:CanReload() then
        self.reloading = true

        --if player and player:GetHasCatPackBoost()then
        --    self:TriggerEffects("reload_speed1")
        --else
            self:TriggerEffects("reload_speed0")
        --end
    end

end


function Cannon:OnProcessMove(input)
    ClipWeapon.OnProcessMove(self, input)
end

function Cannon:GetAmmoPackMapName()
    return CannonAmmo.kMapName
end


function Cannon:OverrideWeaponName()
    return "rifle"
end

function Cannon:OnFireBullets(shootCoords)

    local player = self:GetParent()
    if not player then return end

    -- local onGround = player:GetIsOnGround()
    -- if onGround then
    --     local force = player:GetCrouching() and 5 or 8
    --     ApplyPushback(player, .3, -player:GetCoords().zAxis * force + Vector(0,2,0))
    -- else
    --     player:SetVelocity(player:GetVelocity() -shootCoords.zAxis * 10)
    -- end
    -- Disabled for now

end

if Client then

    function Cannon:GetBarrelPoint()

        local player = self:GetParent()
        if player then

            local origin     = player:GetEyePos()
            local viewCoords = player:GetViewCoords()

            return origin + viewCoords.zAxis * 0.4 + viewCoords.xAxis * -0.15 + viewCoords.yAxis * -0.10

        end

        return self:GetOrigin()

    end

    function Cannon:GetUIDisplaySettings()
        return { xSize = 256, ySize = 500, script = "lua/Combat/GUICannonDisplay.lua"}
    end

end

function Cannon:ModifyDamageTaken(damageTable, attacker, doer, damageType)

    if damageType ~= kDamageType.Corrode then
        damageTable.damage = 0
    end

end

function Cannon:GetCanTakeDamageOverride()
    return self:GetParent() == nil
end

function Cannon:GetTracerEffectName()
    return kTracerCinematic
end

function Cannon:GetTracerResidueEffectName()
    return kTracerResidueCinematic
end

function Cannon:GetTracerEffectFrequency()
    return 1
end

if Server then

    function Cannon:OnKill()
        DestroyEntity(self)
    end

    function Cannon:GetSendDeathMessageOverride()
        return false
    end

end


Shared.LinkClassToMap("Cannon", Cannon.kMapName, networkVars)
