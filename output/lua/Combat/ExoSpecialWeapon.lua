-- ======= NS2.0-TEH-Beta: Combat/ExoSpecialWeapon.lua =======
--
-- NO new networked class here.  This file EXTENDS the existing Railgun class with
-- a weaponMode netvar that branches behaviour for the Flamethrower special exo-arm
-- mode.  When weaponMode == kExoSpecialMode.Railgun every wrapper calls the saved
-- base method so vanilla railgun behaviour is byte-for-byte preserved.
-- (The Welder and Grenade modes were removed entirely, including their enum values.)
--
-- Loaded via:
--   ModLoader.SetupFileHook("lua/Weapons/Marine/Railgun.lua",
--                           "lua/Combat/ExoSpecialWeapon.lua", "post")
--
-- NETWORK-CLASS BUDGET: ZERO new Shared.LinkClassToMap in this file.
-- The Railgun class is RE-LINKED (4th arg true) to add ONE netvar (weaponMode).

-- ── Mode enum ────────────────────────────────────────────────────────────────
kExoSpecialMode = enum({ 'Railgun', 'Flamethrower' })

-- ── Railgun Burst rework ──────────────────────────────────────────────────────
-- Per explicit request: true Railgun mode now fires a 3-round burst (mirroring
-- Combat/Cannon.lua's own Burst architecture) instead of vanilla's single shot,
-- charges in 2/3 of vanilla's charge time, and deals 2/3 of vanilla's total
-- charged damage overall (split evenly across the 3 rounds). Weapons-Level
-- scaling is NOT baked in here - each round's raw (unscaled) damage is passed
-- straight into DoDamage, letting the normal TakeDamage pipeline apply the
-- scalar exactly as vanilla's own ExecuteShot already did.
--
-- Vanilla Railgun.lua's kChargeTime (2s), kChargeForceShootTime (2.2s),
-- kRailgunRange (400) and kBulletSize (0.3) are all file-locals, unreachable
-- from this post-hook file, so their known values are re-declared below.
-- Vanilla's Shoot()/ExecuteShot() (the functions that actually fire) are ALSO
-- file-local and unreachable - the pierce-loop hit-detection reimplemented
-- below in ExecuteRailgunBurstShot is a faithful copy of ExecuteShot's own
-- TraceBox loop (the same technique Combat/Cannon.lua's own FireOnePellet
-- pierce branch already used, built from this exact vanilla function).
local kRailgunVanillaChargeTime = 2
Railgun.kChargeTime             = kRailgunVanillaChargeTime * (2 / 3)   -- ~1.3333s: 2/3 of vanilla's charge time
local kRailgunChargeForceShoot  = Railgun.kChargeTime * 1.1             -- same 1.1x proportion as vanilla's 2.2/2
Railgun.kBurstShots             = 3
Railgun.kBurstShotInterval      = 0.1     -- matches Cannon's own burst cadence
local kRailgunBulletSize        = 0.3     -- vanilla kBulletSize (file-local, re-declared)
local kRailgunRangeDist         = 400     -- vanilla kRailgunRange (file-local, re-declared)
local kRailgunSpreadAngle       = Math.Radians(0)  -- vanilla kRailgunSpread (file-local, re-declared; vanilla is 0)
-- Flamethrower: looping fire sound (same asset as the hand Flamethrower).
local kFlameLoopSound = PrecacheAsset("sound/NS2.fev/marine/flamethrower/attack_loop")

-- Flamethrower: cone damage while charged. NEEDS IN-GAME TUNING.
--
-- Capture the ADVANCED ARMORY (hand) flamethrower's globals (Balance.lua: range 9,
-- damage 9.918) before the local kFlamethrowerRange below shadows them. The Exo flamethrower
-- is defined RELATIVE to the hand FT so it stays a fixed % stronger at EVERY Weapons level
-- (both run through the same DoDamage pipeline).
local kArmouryFlamethrowerRange   = kFlamethrowerRange or 9
local kArmouryFlamethrowerDamage  = kFlamethrowerDamage or 9.918
-- RANGE (the flame box-sweep DEPTH): exactly 25% longer than the hand FT, then -1/3 -> 7.5. This
-- is the ONE Exo-specific value for the hit VOLUME; the cross-section (box width + splash radius)
-- is taken straight from the AA FT at runtime (Flamethrower.kConeWidth / .kDamageRadius) so it is
-- always identical to the hand FT - only the length differs (a cuboid has a constant cross-section,
-- so a shorter length does not change its cross-sectional area).
local kFlamethrowerRange          = kArmouryFlamethrowerRange * 1.25 * (2/3) * 1.1  -- 7.5, then +10% -> 8.25
-- DAMAGE per application: 30% more PURE weapon damage than the hand FT, at the SAME fire cadence
-- (kFlamethrowerDamageRate). Flame-pool DoT is separate and NOT part of this figure.
local kExoFlamethrowerDamage      = kArmouryFlamethrowerDamage * 1.1 * 1.15    -- 1.1x AA FT, then +15% -> 1.265x (9.918 * 1.265 = 12.546)
-- kExoFlamethrowerDamage is the damage for ONE application at this REFERENCE cadence. The actual
-- per-tick damage is scaled by (actual rate / base rate) so the DPS is IDENTICAL no matter how
-- fine the tick rate is: DPS = kExoFlamethrowerDamage / kExoFlamethrowerBaseRate, always.
local kExoFlamethrowerBaseRate    = 0.15
-- Tick FASTER (every 0.05s = 3x more ticks) for smoother, more responsive damage. Because the
-- per-tick amount scales with the rate above, 3x ticks each do 1/3 the damage -> same total DPS.
local kFlamethrowerDamageRate     = 0.05

-- kChargeTime in vanilla Railgun.lua = 2 seconds; we mirror it for arm-glow mapping.
local kExoFlameThrowerChargeTime = 2
-- Flamethrower: arm glow tracks _flameHeat directly (0→1 over 5 s) via override.

-- Heat accumulation: 6 seconds of continuous fire to reach 100% (overheat).
local kFlameHeatRate = 1.0 / 6.0   -- heat/second while firing (6 s from 0 to 100%)
-- Cool-down: 3 seconds from 100% heat back to 0%.
local kFlameCoolRate = 1.0 / 3.0   -- heat/second while cooling (3 s from 100% to 0)

-- Railgun-style attach-point names (same exo model bones, copied from Railgun.lua).
local kFirstPersonAttachPoints = {
    [ExoWeaponHolder.kSlotNames.Left]  = "fxnode_l_railgun_muzzle",
    [ExoWeaponHolder.kSlotNames.Right] = "fxnode_r_railgun_muzzle",
}
local kThirdPersonAttachPoints = {
    [ExoWeaponHolder.kSlotNames.Left]  = "fxnode_lrailgunmuzzle",
    [ExoWeaponHolder.kSlotNames.Right] = "fxnode_rrailgunmuzzle",
}

-- ── Flamethrower trail cinematic assets (copied from Flamethrower_Client.lua) ──
-- PrecacheAsset is shared, so these can live outside the Client block.
local kFlameThrower1PCinematics = {
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_1p_part1.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_1p_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_1p_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_1p_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_1p_part3.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_1p_part3.cinematic"),
}
local kFlamethrower3PCinematics = {
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part1.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part3.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_trail_part3.cinematic"),
}
local kFlameFadeOutCinematics = {
    PrecacheAsset("cinematics/marine/flamethrower/flame_residue_1p_part1.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_residue_1p_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_residue_1p_part2.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_residue_1p_part3.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_residue_1p_part3.cinematic"),
    PrecacheAsset("cinematics/marine/flamethrower/flame_residue_1p_part3.cinematic"),
}

-- ── Step 2: Reconstruct Railgun networkVars verbatim + weaponMode, then RE-LINK ──
local networkVars =
{
    timeChargeStarted = "time",
    railgunAttacking  = "boolean",
    lockCharging      = "boolean",
    timeOfLastShot    = "time",
    weaponMode        = "enum kExoSpecialMode",   -- ADDED: the special-mode field
    -- ADDED: Flamethrower heat (0→1). MUST be networked: GetChargeAmount returns it in
    -- Flamethrower mode, and the spectator charge bar (GUIInsight_PlayerHealthbars) reads
    -- GetChargeAmount on the SPECTATOR's client. _flameHeat was only updated in the predicted
    -- ProcessMoveOnWeapon (server + owner), so spectators - who never predict the exo's moves -
    -- always saw 0 and the bar never filled. Same rationale as railgunAttacking being networked.
    flameHeat         = "float (0 to 1 by 0.01)",
}

AddMixinNetworkVars(TechMixin,          networkVars)
AddMixinNetworkVars(TeamMixin,          networkVars)
AddMixinNetworkVars(ExoWeaponSlotMixin, networkVars)

Shared.LinkClassToMap("Railgun", Railgun.kMapName, networkVars, true)   -- RE-LINK existing class

-- ── Step 2 (cont.): OnCreate wrapper ─────────────────────────────────────────
local baseRGOnCreate = Railgun.OnCreate
function Railgun:OnCreate()
    baseRGOnCreate(self)
    self.weaponMode = kExoSpecialMode.Railgun
    self.timeLastFlameDamage = 0
    -- Flame-pool spawns are rate-limited SEPARATELY from damage (which ticks at 0.05s): pools
    -- keep the ORIGINAL 0.15s cadence so shrinking the damage tick doesn't triple the pools.
    self.timeLastFlamePool = 0
    self.flameHeat = 0
end

-- ── Mode accessors ────────────────────────────────────────────────────────────
Railgun.SetWeaponMode = function(self, mode)
    self.weaponMode = mode
end

Railgun.GetWeaponMode = function(self)
    local m = self.weaponMode
    if not m or m == 0 then return kExoSpecialMode.Railgun end
    return m
end

-- Damage TYPE per mode. The Exo flame arm MUST deal kDamageType.Flame (identical to the hand
-- Advanced Armory flamethrower) so it gets EXACTLY the same target/structure multipliers -
-- most importantly Flame's big bonus vs flammable structures (Clogs) and its bonus vs other
-- structures. Without this the arm dealt the Railgun's Structural type (no flammable bonus), so
-- vs a Clog it did LESS than the hand FT despite the higher base, instead of a clean +20%.
-- With matching types the multipliers cancel and ONE Exo flame arm = exactly 1.2x the hand FT
-- against EVERY target (aliens, structures, Clogs alike). Railgun mode is unchanged: it returns
-- the same value DamageMixin:DoDamage would have looked up itself (the weapon's TechData type,
-- kRailgunDamageType), so nothing about the actual railgun shot changes.
function Railgun:GetDamageType()
    if self:GetWeaponMode() == kExoSpecialMode.Flamethrower then
        return kDamageType.Flame
    end
    return LookupTechData(self:GetTechId(), kTechDataDamageType, kDamageType.Normal)
end

-- Override GetChargeAmount so the arm-glow / charge HUD reflects each mode correctly:
--   Railgun   → charge over Railgun.kChargeTime (2/3 of vanilla's 2s) while railgunAttacking
--   Flamethr. → _flameHeat (unchanged). NOTE: the exo's arm charge BARS are NOT driven off this
--               value; they're fed FUEL (1 - heat) directly in OnUpdateRender below, so the bars
--               read full when cool and empty at overheat WITHOUT changing the ammo % readout.
local baseGetChargeAmount = Railgun.GetChargeAmount
function Railgun:GetChargeAmount()
    local mode = self:GetWeaponMode()
    if mode == kExoSpecialMode.Railgun then
        -- Burst rework: do NOT fall through to vanilla's own GetChargeAmount,
        -- which divides by its own hardcoded (unreachable) file-local
        -- kChargeTime=2 - the charge bar/arm-glow must reflect the shortened
        -- Railgun.kChargeTime instead.
        return self.railgunAttacking
            and math.min(1, (Shared.GetTime() - self.timeChargeStarted) / Railgun.kChargeTime)
            or 0
    elseif mode == kExoSpecialMode.Flamethrower then
        return self.flameHeat or 0
    end
    return baseGetChargeAmount(self)
end

-- GetMeleeBase / GetMeleeOffset are required by TraceMeleeBox (NS2Utility.lua), which the
-- Flamethrower mode uses for its cone hit-detection (it calls weapon:GetMeleeOffset() and
-- weapon:GetMeleeBase()). Vanilla Railgun does not define them, so they must live here.
function Railgun:GetMeleeBase()
    return 2, 2
end

function Railgun:GetMeleeOffset()
    return 0.0
end

-- ── Flamethrower looping sound (server) — one per arm (left/right slot) ──────
if Server then

    function Railgun:StartExoFlameSound()
        if not self._flameSoundEnt then
            self._flameSoundEnt = Server.CreateEntity(SoundEffect.kMapName)
            self._flameSoundEnt:SetAsset(kFlameLoopSound)
            self._flameSoundEnt:SetParent(self)
        end
        if not self._flameSoundPlaying then
            self._flameSoundEnt:Start()
            self._flameSoundPlaying = true
        end
    end

    function Railgun:StopExoFlameSound()
        if self._flameSoundEnt and self._flameSoundPlaying then
            self._flameSoundEnt:Stop()
            self._flameSoundPlaying = false
        end
    end

end

-- ── Helper: CreateExoFlame (server) ──────────────────────────────────────────
-- Mirrors Flamethrower:CreateFlame — places a persistent Flame entity on the
-- ground below the hit point.  Skipped if a flame already exists within 1.7 units.
local function CreateExoFlame(player, position)
    if not Server then return end
    local nearbyFlames = GetEntitiesForTeamWithinRange("Flame", player:GetTeamNumber(), position, 1.7)
    if #nearbyFlames == 0 then
        local flame = CreateEntity(Flame.kMapName, position, player:GetTeamNumber())
        if flame then
            flame:SetOwner(player)
            -- Marks this ground fire-pool as an EXO flamethrower's, so a kill it
            -- scores (Flame:Detonate DoDamage, doer = the Flame itself) shows the
            -- Exo flamethrower killfeed entry instead of the vanilla hand
            -- Flamethrower's - see Flame:GetDeathIconIndex override below.
            flame.createdByExoFlamethrower = true
        end
    end
end

-- The Flame class is SHARED by the vanilla hand Flamethrower and the Exo
-- flamethrower, so this override must NOT blanket-return the Exo icon - it only
-- diverges for flames CreateExoFlame marked above, falling through to the
-- vanilla icon (kDeathMessageIcon.Flamethrower) for any hand-Flamethrower flame.
-- ExoFlamethrowerBurn renders the skull + flamethrower pairing and reads
-- "ExoFlamethrower" in the console (GUIDeathMessagesExo.lua). GetDeathIconIndex
-- is resolved server-side (TeamDeathMessageMixin), so a plain server field is
-- sufficient - no networking needed.
--
-- Railgun.lua (the file this posthook attaches to) does not itself load Flame -
-- only Flamethrower.lua does - so ensure the class exists before referencing it
-- (Script.Load is idempotent and a no-op if Flame is already loaded).
Script.Load("lua/Weapons/Marine/Flame.lua")
local baseFlameGetDeathIconIndex = Flame.GetDeathIconIndex
function Flame:GetDeathIconIndex()
    if self.createdByExoFlamethrower then
        return kDeathMessageIcon.ExoFlamethrowerBurn
    end
    if baseFlameGetDeathIconIndex then
        return baseFlameGetDeathIconIndex(self)
    end
    return kDeathMessageIcon.Flamethrower
end

-- ── Step 3: Wrap Railgun:OnPrimaryAttack ─────────────────────────────────────
local baseOnPrimaryAttack = Railgun.OnPrimaryAttack
function Railgun:OnPrimaryAttack(player)

    local mode = self:GetWeaponMode()

    if mode == kExoSpecialMode.Railgun then
        baseOnPrimaryAttack(self, player)

    elseif mode == kExoSpecialMode.Flamethrower then
        -- Allow firing only when not overheated and not already active.
        if not self.railgunAttacking and not self._flameOverheated then
            self.timeChargeStarted = Shared.GetTime()
            self.railgunAttacking  = true
            if Server then self:StartExoFlameSound() end
        end
    end

end

-- ── Railgun Burst helpers ──────────────────────────────────────────────────────
-- StartRailgunBurst captures the charge fraction ONCE, at the instant of
-- trigger release (mirroring Combat/Cannon.lua's StartBurst capturing
-- chargeMult at trigger time) - the 3 individual rounds fired afterwards by
-- ProcessMoveOnWeapon all deal an equal share of this same captured total, so
-- releasing the button never lets a shot's damage keep changing mid-burst.
function Railgun:GetIsRailgunBursting()
    return (self._railgunBurstShotsRemaining or 0) > 0
end

function Railgun:StartRailgunBurst(player)

    local chargeFrac = self.railgunAttacking
        and math.min(1, (Shared.GetTime() - self.timeChargeStarted) / Railgun.kChargeTime)
        or 0

    -- SINGLE shot with the ORIGINAL (vanilla) charged damage: flat base + charge-scaled
    -- bonus, fired in ONE hit. This restores the vanilla Railgun's own damage-vs-charge
    -- behaviour (the earlier 3-round-burst / 2/3-damage rework is gone). Weapons-Level
    -- scaling is applied downstream by DoDamage/TakeDamage, exactly like vanilla ExecuteShot.
    local totalDamage = kRailgunDamage + chargeFrac * kRailgunChargeDamage

    self._railgunBurstPerShotDamage  = totalDamage   -- the single shot carries the whole amount
    self._railgunBurstShotsRemaining = 1             -- one shot, not Railgun.kBurstShots
    self._railgunBurstNextShotTime   = 0   -- fire it on the very next ProcessMoveOnWeapon

    self.railgunAttacking = false
    self:LockGun()   -- vanilla method (not file-local): starts the fire-rate cooldown once per burst trigger

end

-- Faithful reimplementation of vanilla Railgun.lua's file-local ExecuteShot
-- (its own TraceBox pierce loop), parametrized on the per-round damage value
-- instead of computing it inline from kRailgunDamage/kRailgunChargeDamage.
function Railgun:ExecuteRailgunBurstShot(startPoint, endPoint, player, damage)

    local filter = EntityFilterTwo(player, self)
    local trace  = Shared.TraceRay(startPoint, endPoint, CollisionRep.Damage,
                                    PhysicsMask.Bullets, EntityFilterAllButIsa("Tunnel"))
    local hitPointOffset = trace.normal * 0.3
    local direction       = (endPoint - startPoint):GetUnit()
    local extents         = GetDirectedExtentsForDiameter(direction, kRailgunBulletSize)

    local hitEntities   = {}
    local pierceStart   = startPoint
    for _ = 1, 20 do

        local capsuleTrace = Shared.TraceBox(extents, pierceStart, trace.endPoint,
                                CollisionRep.Damage, PhysicsMask.Bullets, filter)

        if capsuleTrace.entity then
            if not table.find(hitEntities, capsuleTrace.entity) then
                table.insert(hitEntities, capsuleTrace.entity)
                self:DoDamage(damage, capsuleTrace.entity, capsuleTrace.endPoint + hitPointOffset,
                              direction, capsuleTrace.surface, false, false)
            end
        end

        if (capsuleTrace.endPoint - trace.endPoint):GetLength() <= extents.x then
            break
        end

        pierceStart = Vector(capsuleTrace.endPoint) + direction * extents.x * 3

    end

    local effectFrequency = self:GetTracerEffectFrequency()
    local showTracer      = (math.random() < effectFrequency)

    -- Broadcast tracer to other players via 0-damage DoDamage call (mirrors vanilla).
    self:DoDamage(0, nil, trace.endPoint + hitPointOffset, direction, trace.surface, false, showTracer)

    if Client and showTracer then
        TriggerFirstPersonTracer(self, trace.endPoint)
    end

end

-- Fires ONE round of the burst.
function Railgun:FireRailgunBurstShot(player)

    local perShot = self._railgunBurstPerShotDamage or 0

    local shootCoords     = player:GetViewAngles():GetCoords()
    local spreadDirection = CalculateSpread(shootCoords, kRailgunSpreadAngle, NetworkRandom)
    local startPoint      = player:GetEyePos()
    local endPoint        = startPoint + spreadDirection * kRailgunRangeDist

    self:ExecuteRailgunBurstShot(startPoint, endPoint, player, perShot)

    player:TriggerEffects("railgun_attack")
    if Client then
        if self:GetIsLeftSlot() then
            player:TriggerEffects("railgun_steam_left")
        elseif self:GetIsRightSlot() then
            player:TriggerEffects("railgun_steam_right")
        end
    end

end

-- ── Step 3: Wrap Railgun:OnPrimaryAttackEnd ───────────────────────────────────
local baseOnPrimaryAttackEnd = Railgun.OnPrimaryAttackEnd
function Railgun:OnPrimaryAttackEnd(player)

    local mode = self:GetWeaponMode()

    if mode == kExoSpecialMode.Railgun then
        -- Burst rework: releasing the trigger (or the force-shoot timeout in
        -- ProcessMoveOnWeapon calling this directly) starts a 3-round burst
        -- instead of vanilla's single animation-tag-driven shot.
        if self.railgunAttacking then
            self:StartRailgunBurst(player)
        end
        baseOnPrimaryAttackEnd(self, player)

    elseif mode == kExoSpecialMode.Flamethrower then
        -- Clear firing state. Do NOT set timeOfLastShot — that would trigger
        -- the railgun muzzle flash cinematic on every button release.
        if self.railgunAttacking then
            self.railgunAttacking = false
            if Server then self:StopExoFlameSound() end
        end
    end

end

-- ── Wrap Railgun:OnDamageDone (Server-only, matches vanilla's own scoping) ────
-- Vanilla Railgun:OnDamageDone (Weapons/Marine/Railgun.lua:312-332) bypasses
-- ragdoll on a kill ("obliterates" the corpse - RagdollMixin:OnTag then
-- SetModel(nil) instead of ragdolling, per RagdollMixin.lua:195-211), gated
-- only on `doer == self` - with no weaponMode check, this fired identically
-- for kills in ALL FOUR modes (Railgun/Flamethrower/Welder/Grenade), since
-- they all share this same underlying Railgun instance. Only true Railgun
-- mode should obliterate a kill.
if Server then
    local baseOnDamageDone = Railgun.OnDamageDone
    function Railgun:OnDamageDone(doer, target)
        if self:GetWeaponMode() == kExoSpecialMode.Railgun then
            baseOnDamageDone(self, doer, target)
        end
    end
end

-- ── Mode-aware killfeed icon ──────────────────────────────────────────────────
-- All four modes share this same underlying Railgun instance/class, so the
-- inherited Railgun:GetDeathIconIndex() (Weapons/Marine/Railgun.lua) returned
-- the same Railgun icon regardless of which mode actually scored the kill.
-- kDeathMessageIcon.ExoFlamethrower/ExoWelder/ExoGrenadeLauncher (appended in
-- CNBalance/Globals.lua) are redirected to the correct icon art in
-- CNBalance/GUI/GUIDeathMessagesExo.lua; console death-message text is
-- generated directly from those enum names, so this one override fixes both
-- the icon and the console text together.
local baseGetDeathIconIndex = Railgun.GetDeathIconIndex
function Railgun:GetDeathIconIndex()
    local mode = self:GetWeaponMode()
    if mode == kExoSpecialMode.Flamethrower then
        return kDeathMessageIcon.ExoFlamethrower
    end
    return baseGetDeathIconIndex(self)
end

-- ── Step 3: Wrap Railgun:OnTag ────────────────────────────────────────────────
-- Burst rework: even true Railgun mode no longer reaches vanilla's own OnTag -
-- firing is now driven entirely by OnPrimaryAttackEnd (StartRailgunBurst) +
-- ProcessMoveOnWeapon's burst timer, not by the animation "l_shoot"/"r_shoot"
-- tags (which would otherwise call vanilla's file-local Shoot()/ExecuteShot()
-- for a single un-nerfed shot). All tags suppressed for every mode, same as
-- Flamethrower/Welder/Grenade already were.
function Railgun:OnTag(tagName)
    return
end

-- ── Step 3: Wrap Railgun:ProcessMoveOnWeapon ──────────────────────────────────
local baseProcessMoveOnWeapon = Railgun.ProcessMoveOnWeapon
function Railgun:ProcessMoveOnWeapon(player, input)

    local mode = self:GetWeaponMode()
    local now  = Shared.GetTime()
    local dt   = input.time

    if mode == kExoSpecialMode.Railgun then

        -- Burst rework: do NOT delegate to vanilla's own ProcessMoveOnWeapon
        -- (which only force-clears railgunAttacking at kChargeForceShootTime
        -- with no shot fired) - force-shoot now genuinely fires a burst, via
        -- the same OnPrimaryAttackEnd path a normal release takes.
        if self.railgunAttacking then
            if (now - self.timeChargeStarted) >= kRailgunChargeForceShoot then
                self:OnPrimaryAttackEnd(player)
            end
        end

        -- Fire the pending shot (a single shot now; the loop simply drains the one
        -- queued round). kBurstShotInterval is irrelevant with one shot.
        if self:GetIsRailgunBursting() then
            if now >= (self._railgunBurstNextShotTime or 0) then
                self:FireRailgunBurstShot(player)
                self._railgunBurstShotsRemaining = self._railgunBurstShotsRemaining - 1
                self._railgunBurstNextShotTime   = now + Railgun.kBurstShotInterval
            end
        end

    elseif mode == kExoSpecialMode.Flamethrower then

        if self.railgunAttacking then

            -- Accumulate heat: 5 seconds of continuous fire reaches 100%.
            -- At 100% set _flameOverheated and stop firing; the railgunAttacking→false
            -- transition lets the FSM play the shoot-flourish animation (simulating
            -- a critical heat burst). Player cannot fire again until heat returns to 0.
            self.flameHeat = math.min(1.0, (self.flameHeat or 0) + dt * kFlameHeatRate)
            if self.flameHeat >= 1.0 then
                self._flameOverheated = true
                self.railgunAttacking = false
                -- Open a short, explicit window (_flameShootAnimEnd) during which
                -- OnUpdateAnimationInput lets the real (false) value through, producing
                -- the primary→none edge that plays the shoot flourish EXACTLY once,
                -- only at 100% heat.
                self._flameShootAnimEnd = now + 0.7
                if Server then self:StopExoFlameSound() end
            end

            -- Rate-limited cone damage + flame pool creation (server only).
            if Server and (self.timeLastFlameDamage + kFlamethrowerDamageRate) <= now then
                self.timeLastFlameDamage = now

                local viewCoords = player:GetViewCoords()
                local eyePos     = player:GetEyePos()
                local fireDir    = viewCoords.zAxis
                -- THIS arm's MUZZLE origin (same lateral offset as Minigun:GetBarrelPoint and the
                -- flame trail attach). xAxis is lateral; +0.65 = left arm, -0.65 = right arm; 0.9
                -- forward + 0.19 down place it at the barrel. It is used ONLY for (a) this arm's
                -- flame pool and (b) the per-arm line-of-sight fairness check below - NOT for
                -- detecting which targets are in the flame (that is done from the EYE, like the AA
                -- FT). Each arm runs THIS block independently, so a Dual-FT's two arms each gate
                -- their own damage on their own muzzle's visibility.
                local isLeft     = self:GetExoWeaponSlot() == ExoWeaponHolder.kSlotNames.Left
                local muzzle     = eyePos + fireDir * 0.9 + viewCoords.xAxis * (isLeft and 0.65 or -0.65) + viewCoords.yAxis * (-0.19)
                -- Filter EVERY entity belonging to this Exo: this arm, the player, the
                -- ExoWeaponHolder AND the OTHER arm. Previously only { self, player } was
                -- filtered, so on an FT + Claw combo the CLAW arm (a separate entity sitting in
                -- front of the player) could BLOCK this arm's flame trace at ~0 range. That
                -- collapsed trace.endPoint onto the player, which (a) crippled the cone damage and
                -- (b) made BurnSporesAndUmbra - which walks eyePos -> trace.endPoint in 2m steps -
                -- break out immediately and burn NOTHING (no Bilebomb / Corrode / Vortex / Spores).
                local filterEnts = { self, player }
                local holder = player.GetActiveWeapon and player:GetActiveWeapon()
                if holder then
                    table.insert(filterEnts, holder)
                    if holder.leftWeaponId then
                        local w = Shared.GetEntity(holder.leftWeaponId)
                        if w then table.insert(filterEnts, w) end
                    end
                    if holder.rightWeaponId then
                        local w = Shared.GetEntity(holder.rightWeaponId)
                        if w then table.insert(filterEnts, w) end
                    end
                end
                -- 1.4x the hand FT base. Also neutralise the Weapons-upgrade scaling MISMATCH:
                -- this weapon (Exo railgun) is upgrade-scaled at the DEFAULT rate (+0.1/level)
                -- while the hand FT uses the flamethrower rate (+0.07/level), so a flat base would
                -- drift to +29% by Weapons 3. Pre-scale by (FT scalar / this weapon's own scalar):
                -- the damage pipeline then re-applies THIS weapon's own scalar, leaving a net
                -- upgrade factor exactly equal to the hand FT's - so one Exo flame arm stays
                -- exactly 1.2x the hand FT at EVERY Weapons level. (Guarded: falls back to the flat
                -- base if the scalar lookups are unavailable.)
                -- Per-tick damage = the reference application scaled by (tick rate / base rate),
                -- so shrinking the tick interval keeps the DPS unchanged (see the constants above).
                local dmgAmount = kExoFlamethrowerDamage * (kFlamethrowerDamageRate / kExoFlamethrowerBaseRate)
                local ownScalar = NS2Gamerules_GetUpgradedDamageScalar(player, self:GetTechId())
                local ftScalar  = NS2Gamerules_GetUpgradedDamageScalar(player, kTechId.Flamethrower)
                if ownScalar and ftScalar and ownScalar > 0 then
                    dmgAmount = dmgAmount * (ftScalar / ownScalar)
                end

                -- ===== AA FT hit-check VOLUME (eye-based), at the Exo's OWN range =====
                -- EXACTLY the hand Flamethrower's ApplyConeDamage volume: a swept melee BOX of the
                -- AA FT's own cone width, cast from the EYE along the aim, then a splash to Live
                -- entities around where the flame lands (the AA FT's damage radius). The box has a
                -- CONSTANT cross-section (a cuboid, NOT a widening cone), so using the Exo's shorter
                -- range leaves that cross-sectional area exactly equal to the AA FT's - only the
                -- length differs. Starting from the eye (not the arm) removes the aim-low dead zone
                -- the old per-arm cylinders had. Damage/DPS, fire rate, range and pool cadence stay
                -- the Exo's own (see below) - only this hit VOLUME is borrowed from the AA FT.
                local coneExtent   = (Flamethrower and Flamethrower.kConeWidth) or 0.3
                local splashRadius = (Flamethrower and Flamethrower.kDamageRadius) or 1.8
                local extents = Vector(coneExtent, coneExtent, coneExtent)

                local trace = TraceMeleeBox(self, eyePos, fireDir, extents, kFlamethrowerRange,
                                            PhysicsMask.Flame, EntityFilterList(filterEnts))
                local endPoint = trace.endPoint

                -- Burn hazards (bile / whip / vortex / spores / umbra) along the flame, as before.
                Flamethrower.BurnSporesAndUmbra(self, eyePos, endPoint)

                -- Gather the AA FT candidate targets: the box-hit entity + the end splash (Live
                -- entities within the damage radius in XZ and half that in height of the landing pt).
                local ents = {}
                if trace.fraction ~= 1 then
                    local traceEnt = trace.entity
                    if traceEnt and HasMixin(traceEnt, "Live") and traceEnt:GetCanTakeDamage() then
                        ents[#ents + 1] = traceEnt
                    end
                    local hitEntities = GetEntitiesWithMixinWithinXZRange("Live", endPoint, splashRadius)
                    local damageHeight = splashRadius / 2
                    for i = 1, #hitEntities do
                        local ent = hitEntities[i]
                        if ent ~= traceEnt and ent:GetCanTakeDamage()
                           and math.abs(endPoint.y - ent:GetOrigin().y) <= damageHeight then
                            ents[#ents + 1] = ent
                        end
                    end
                end

                -- Per-arm flame pool (UNCHANGED Exo behaviour): trace THIS arm's own muzzle forward
                -- and, if it hits a wall / ground, drop a pool there - gated to the original 0.15s
                -- cadence so pools-per-second are unchanged. This is what lets an OBSTRUCTED arm still
                -- lay its pool against the wall in front of it even when its damage is suppressed by
                -- the per-arm line-of-sight check below.
                local poolTrace = Shared.TraceRay(muzzle, muzzle + fireDir * kFlamethrowerRange,
                                            CollisionRep.Damage, PhysicsMask.Flame, EntityFilterAll())
                if poolTrace.fraction ~= 1
                   and (self.timeLastFlamePool + kExoFlamethrowerBaseRate) <= now then
                    self.timeLastFlamePool = now
                    local hitPt = poolTrace.endPoint
                    local groundTrace = Shared.TraceRay(hitPt, hitPt + Vector(0, -2.6, 0),
                        CollisionRep.Default, PhysicsMask.CystBuild, EntityFilterAllButIsa("TechPoint"))
                    if groundTrace.fraction ~= 1 then
                        CreateExoFlame(player, groundTrace.endPoint)
                    end
                end

                -- Per-arm LINE-OF-SIGHT fairness. The candidate targets above were found from the
                -- EYE (so a Dual-FT's two arms, both tracing from the same eye, see the SAME
                -- targets). Before THIS arm damages a target, we require THIS arm's own muzzle to
                -- actually see it - a plain world trace muzzle -> target, blocked = skip. So a
                -- Dual-FT peeking a corner with only its eye + ONE arm exposed and the other arm
                -- behind the wall deals ONE arm's damage, not two: the hidden arm's trace is blocked
                -- and it skips every target (while still laying its pool against that wall, above).
                -- Each arm runs this on its OWN muzzle independently, so two genuinely-exposed arms
                -- both burn (the intended dual-wield damage). A small +0.35 slack absorbs the target
                -- origin sitting just inside its own hitbox.
                local function ArmCanSee(targetPoint)
                    local tr = Shared.TraceRay(muzzle, targetPoint, CollisionRep.Damage,
                                        PhysicsMask.Flame, EntityFilterAll())
                    if tr.fraction == 1 then return true end
                    return (targetPoint - muzzle):GetLength()
                           <= (tr.endPoint - muzzle):GetLength() + 0.35
                end

                for i = 1, #ents do
                    local ent = ents[i]
                    local enemyOrigin = ent.GetModelOrigin and ent:GetModelOrigin()
                    if ent ~= player and enemyOrigin and GetAreEnemies(player, ent)
                       and ArmCanSee(enemyOrigin) then
                        local toEnemy = GetNormalizedVector(enemyOrigin - eyePos)
                        local health = ent:GetHealth()
                        -- surface="none": skip the Railgun's organic-hit cinematic (flame, not rail).
                        self:DoDamage(dmgAmount, ent, enemyOrigin, toEnemy, "none", false, false)
                        -- Only ignite if damage actually landed (matches the hand Flamethrower).
                        if ent:GetHealth() ~= health and HasMixin(ent, "Fire") then
                            ent:SetOnFire(player, self)
                        end
                    end
                end
            end
        else
            -- Not firing: cool down the heat at kFlameCoolRate.
            self.flameHeat = math.max(0, (self.flameHeat or 0) - dt * kFlameCoolRate)
            -- Clear overheat only when heat reaches exactly 0 (not just below 1).
            if self._flameOverheated and self.flameHeat <= 0 then
                self._flameOverheated = false
            end
        end

    end

end

-- ── Step 3: Wrap Railgun:OnUpdateAnimationInput ───────────────────────────────
local baseOnUpdateAnimationInput = Railgun.OnUpdateAnimationInput
function Railgun:OnUpdateAnimationInput(modelMixin)
    local mode = self:GetWeaponMode()
    if mode == kExoSpecialMode.Flamethrower then
        -- Force "primary" every frame EXCEPT during the short _flameShootAnimEnd
        -- window opened only by the overheat transition in ProcessMoveOnWeapon.
        -- This is the same explicit-window idiom used for the grenade's shoot
        -- animation: it guarantees the shoot flourish can ONLY play during that
        -- window (i.e. only at 100% heat), never on an ordinary early release.
        if self._flameShootAnimEnd and Shared.GetTime() < self._flameShootAnimEnd then
            baseOnUpdateAnimationInput(self, modelMixin)  -- passes actual false → "none"
        else
            local saved = self.railgunAttacking
            self.railgunAttacking = true
            baseOnUpdateAnimationInput(self, modelMixin)
            self.railgunAttacking = saved
        end
    else
        baseOnUpdateAnimationInput(self, modelMixin)
    end
end

-- ── Client-only wrappers ───────────────────────────────────────────────────────
if Client then

    -- Helper: destroy flame trail cinematic if one exists.
    local function DestroyFlameTrail(self)
        if self._flameTrail then
            Client.DestroyTrailCinematic(self._flameTrail)
            self._flameTrail = nil
            self._flameTrailIsFirstPerson = nil
        end
    end

    local baseOnClientPrimaryAttackEnd = Railgun.OnClientPrimaryAttackEnd
    function Railgun:OnClientPrimaryAttackEnd()
        if self:GetWeaponMode() == kExoSpecialMode.Railgun then
            baseOnClientPrimaryAttackEnd(self)
        end
        -- All special modes: no shooting cinematic on release.
    end

    local baseGetPrimaryAttacking = Railgun.GetPrimaryAttacking
    function Railgun:GetPrimaryAttacking()
        local mode = self:GetWeaponMode()
        if mode == kExoSpecialMode.Railgun then
            return baseGetPrimaryAttacking(self)
        elseif mode == kExoSpecialMode.Flamethrower then
            return self.railgunAttacking
        end
        return false
    end

    -- Cleanup flame trail and weld info text on entity destruction.
    local baseRGOnDestroy = Railgun.OnDestroy
    function Railgun:OnDestroy()
        DestroyFlameTrail(self)
        if baseRGOnDestroy then baseRGOnDestroy(self) end
    end

    -- OnUpdateRender: grenade muzzle flash + welder muzzle cinematic + flamethrower trail.
    local baseRGOnUpdateRender = Railgun.OnUpdateRender
    function Railgun:OnUpdateRender()
        -- The vanilla Railgun's OnUpdateRender plays its electric charge glow and
        -- muzzle flash whenever railgunAttacking is true or timeOfLastShot changes.
        -- In Flamethrower/Welder/Grenade modes those effects look wrong (blue-green
        -- electric arc at the muzzle/target), so only forward to the base in Railgun mode.
        local mode = self:GetWeaponMode()
        if mode == kExoSpecialMode.Railgun then
            if baseRGOnUpdateRender then baseRGOnUpdateRender(self) end
        end

        -- Flamethrower: manage the looping flame trail cinematic.
        -- self:GetParent() returns the Exo PLAYER directly — the Railgun arm weapons
        -- are owned/parented by the player, not by the ExoWeaponHolder.
        if mode == kExoSpecialMode.Flamethrower then

            -- Drive THIS arm's charge-bar display (the gray portrait circle) to show FUEL = 1 - heat:
            -- full when cool, draining to empty as heat rises to 100% while firing. Because this is
            -- the FT (we branch on the weapon MODE here, where we actually know it - the isolated
            -- GUIView can't), we load our FLAMETHROWER display (GUIExoFTFuelDisplay) instead of the
            -- railgun one: identical circle, but it pulses red when EMPTY (overheated) rather than
            -- full. We update ONLY the GUIView (its "*exo_railgun_<slot>" texture), NOT the render
            -- model's charge material parameter - so the bar fills WITHOUT the railgun electric-arc
            -- glow. Local player only; cleaned up otherwise (mirrors vanilla).
            local chargeParent = self:GetParent()
            if chargeParent and chargeParent.GetIsLocalPlayer and chargeParent:GetIsLocalPlayer() then
                local slotName = self:GetExoWeaponSlotName()
                local chargeDisplayUI = self.chargeDisplayUI
                if not chargeDisplayUI then
                    chargeDisplayUI = Client.CreateGUIView(246, 256)
                    chargeDisplayUI:Load("lua/CNBalance/GUI/GUIExoFTFuelDisplay.lua")
                    chargeDisplayUI:SetTargetTexture("*exo_railgun_" .. slotName)
                    self.chargeDisplayUI = chargeDisplayUI
                end
                chargeDisplayUI:SetGlobal("chargeAmount", 1 - (self.flameHeat or 0))
            elseif self.chargeDisplayUI then
                Client.DestroyGUIView(self.chargeDisplayUI)
                self.chargeDisplayUI = nil
            end

            local exoPlayer = self:GetParent()
            local isFirstPerson = exoPlayer
                                  and exoPlayer:GetIsLocalPlayer()
                                  and not exoPlayer:GetIsThirdPerson()

            -- Destroy and recreate if the view mode (1P↔3P) changed.
            if self._flameTrail and (self._flameTrailIsFirstPerson ~= isFirstPerson) then
                DestroyFlameTrail(self)
            end

            -- Lazily create the trail cinematic.
            if not self._flameTrail and exoPlayer then
                local trail = Client.CreateTrailCinematic(RenderScene.Zone_Default)
                -- MUST repeat endlessly, exactly like the hand Flamethrower's trail
                -- (Flamethrower_Client.lua:InitTrailCinematic). Without this the trail plays a
                -- SINGLE pass and then stops, so it renders unreliably / not at all - which is
                -- why other players (e.g. an alien watching) could not see it. This is NOT related
                -- to the Weapon Tracers option: neither the hand FT nor this trail is gated on it.
                trail:SetRepeatStyle(Cinematic.Repeat_Endless)

                if isFirstPerson then
                    -- 1P: orient from the player's eye position in view direction.
                    -- The Exo does not use a separate ViewModel entity for the arms;
                    -- GetViewModelEntity() returns nil. Use AttachToFunc so the trail
                    -- origin tracks the camera exactly (same approach as vanilla Flamethrower).
                    trail:SetCinematicNames(kFlameThrower1PCinematics)
                    trail:SetFadeOutCinematicNames(kFlameFadeOutCinematics)
                    local isLeft = self:GetExoWeaponSlot() == ExoWeaponHolder.kSlotNames.Left
                    -- In Exo 1P view, xAxis points to the PLAYER'S LEFT.
                    -- Positive sideX = left arm; negative = right arm.
                    local sideX  = isLeft and 0.48 or -0.48
                    trail:AttachToFunc(self, TRAIL_ALIGN_Z, Vector(sideX, -0.10, 0.75),
                        function() return exoPlayer and exoPlayer:GetViewCoords() end)
                else
                    -- 3P: attach to the Exo player entity (carries the world model bones).
                    trail:SetCinematicNames(kFlamethrower3PCinematics)
                    trail:SetFadeOutCinematicNames(kFlameFadeOutCinematics)
                    local bone = kThirdPersonAttachPoints[self:GetExoWeaponSlot()]
                    trail:AttachTo(exoPlayer, TRAIL_ALIGN_X, Vector(0.3, 0, 0), bone)
                end

                -- View-dependent segment/hardening, EXACTLY like vanilla's InitTrailCinematic.
                -- Using the 1P values (6 segments / 0.5 hardening) for the 3P WORLD trail was the
                -- bug: too few segments + stiff hardening over the longer Exo trail rendered as a
                -- string of discrete cones instead of one smooth stream. The 3P trail needs MORE
                -- segments and MUCH softer hardening (0.1) so adjacent segments blend together.
                --   1P: 6 segments / 0.5 hardening  (matches the 6-entry 1P cinematic table)
                --   3P: 8 segments / 0.1 hardening  (matches the 8-entry 3P cinematic table)
                local numSegments  = isFirstPerson and 6 or 8
                local minHardening = isFirstPerson and 0.5 or 0.1

                trail:SetOptions({
                    numSegments              = numSegments,
                    collidesWithWorld        = true,
                    visibilityChangeDuration = 0.2,
                    fadeOutCinematics        = true,
                    stretchTrail             = false,
                    -- Length matched to the DAMAGE reach now that the hit-check starts at the eye
                    -- (reaches eye + kFlamethrowerRange). The trail starts ~0.75 forward at the arm,
                    -- so kFlamethrowerRange puts its 1P tip a touch PAST the damage (safe: the flame
                    -- never falls short of where it burns) and its 3P tip essentially on it. The old
                    -- +0.5 made the visible flame over-reach the eye-based damage by ~1.25m in 1P.
                    trailLength              = kFlamethrowerRange,
                    minHardening             = minHardening,
                    maxHardening             = 2,
                    hardeningModifier        = 0.8,
                    trailWeight              = 0.2,
                })
                trail:SetIsVisible(false)

                self._flameTrail = trail
                self._flameTrailIsFirstPerson = isFirstPerson
            end

            -- Show trail only while actively firing.
            if self._flameTrail then
                self._flameTrail:SetIsVisible(self.railgunAttacking == true)
            end

        else
            -- Not in Flamethrower mode: clean up any lingering trail.
            DestroyFlameTrail(self)
        end

    end

end
