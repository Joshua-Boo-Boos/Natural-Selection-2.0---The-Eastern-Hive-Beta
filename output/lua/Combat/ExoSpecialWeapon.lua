-- ======= NS2.0-TEH-Beta: Combat/ExoSpecialWeapon.lua =======
--
-- NO new networked class here.  This file EXTENDS the existing Railgun class with
-- a weaponMode netvar that branches behaviour for three special exo-arm modes
-- (Flamethrower, Welder, Grenade).  When weaponMode == kExoSpecialMode.Railgun
-- every wrapper calls the saved base method so vanilla railgun behaviour is
-- byte-for-byte preserved.
--
-- Loaded via:
--   ModLoader.SetupFileHook("lua/Weapons/Marine/Railgun.lua",
--                           "lua/Combat/ExoSpecialWeapon.lua", "post")
--
-- NETWORK-CLASS BUDGET: ZERO new Shared.LinkClassToMap in this file.
-- The Railgun class is RE-LINKED (4th arg true) to add ONE netvar (weaponMode).

-- ── Mode enum ────────────────────────────────────────────────────────────────
kExoSpecialMode = enum({ 'Railgun', 'Flamethrower', 'Welder', 'Grenade' })

-- ── Tunable constants ─────────────────────────────────────────────────────────
local kGrenadeSpeed        = 40     -- units/s
local kGrenadeGravity      = 9      -- units/s² downward; grenade starts flat then arcs
local kGrenadeChargeTime   = 1.538  -- seconds to fire (2.0 / 1.3, 30% faster)

-- Welder: looping weld sound (same asset as the hand Welder, played while
-- repairing armour) + muzzle cinematic.
local kWeldSound           = PrecacheAsset("sound/NS2.fev/marine/welder/weld")
-- Builder scan sound: same looping asset the Builder tool plays while constructing.
local kBuilderScanSound    = PrecacheAsset("sound/NS2.fev/marine/welder/scan")
local kWelderRailgunCinematic = PrecacheAsset("cinematics/marine/welder/welder_muzzle.cinematic")
-- Builder scan cinematic: played while constructing (building) a structure.
-- This is the same cinematic used by the Builder tool when a marine is constructing.
local kBuilderScanCinematic   = PrecacheAsset("cinematics/marine/builder/builder_scan.cinematic")
-- kWelderRepairCount: when repairing armor the cinematic is spawned this many times
-- per pulse so the Exo welder looks visibly more powerful than a standard hand welder.
-- (Scaling the cinematic's Coords axes only moves emitter origins, not particle sizes,
-- so multiplying the count is the reliable way to increase visual intensity.)
local kWelderRepairCount   = 10
local kWeldPulseInterval = 0.25     -- cadence for the client muzzle weld cinematic
local kWelderChargeLoopTime = 1.4   -- loop charge anim below shoot tag (< kChargeForceShootTime)

-- Flamethrower: looping fire sound (same asset as the hand Flamethrower).
local kFlameLoopSound = PrecacheAsset("sound/NS2.fev/marine/flamethrower/attack_loop")

-- Flamethrower: cone damage while charged. NEEDS IN-GAME TUNING.
local kFlamethrowerRange          = 5.6 * 1.125  -- 70% of original 8, +12.5%; tune in-game
local kFlamethrowerConeWidth      = 0.6  -- TraceMeleeBox extents; tune in-game
local kFlamethrowerDamagePerSec   = 25   -- per second
local kFlamethrowerDamageRate     = 0.15 -- apply damage/flames every 0.15s (~6.7 Hz)

-- kChargeTime in vanilla Railgun.lua = 2 seconds; we mirror it for arm-glow mapping.
local kExoFlameThrowerChargeTime = 2
-- Grenade visual charge time: grenade fires at kGrenadeChargeTime but the ARM GLOW
-- should show 0→100% over that same duration (override GetChargeAmount below).
-- Flamethrower: arm glow tracks _flameHeat directly (0→1 over 5 s) via override.

-- Heat accumulation: 5 seconds of continuous fire to reach 100%, 3 seconds to cool.
local kFlameHeatRate = 1.0 / 5.0   -- heat/second while firing
local kFlameCoolRate = 1.0 / 5.0   -- heat/second while cooling (5 s from 100% to 0)

-- Welder
-- 60% of the original max range (2.8 * 0.6): the arm can only build/weld things
-- from up to 60% of its previous maximum distance away.
local kExoWeldRange = 2.8 * 0.6   -- 1.68
-- 1.5× the repair rate of a handheld Welder from an Armory.
-- kPlayerWeldRate/kStructureWeldRate are globals from BalanceMisc.lua (30/90 HP/s).
local kExoWelderPlayerRate    = kPlayerWeldRate * 1.5    -- 45 HP/s per arm
local kExoWelderStructureRate = kStructureWeldRate * 1.5  -- 135 HP/s per arm

-- GL fire sound
local kGLFireSound = PrecacheAsset("sound/NS2.fev/marine/rifle/fire_grenade")

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
    weaponMode        = "enum kExoSpecialMode",   -- ADDED: the only new field
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
    self._grenadeAttacking   = false
    self._grenadeMustRelease = false
    self._welderAttacking  = false
    self.timeLastWeld      = 0
    self.timeLastFlameDamage = 0
    -- Client render-side tracker for grenade muzzle flash.
    self._lastSeenShotTime = self.timeOfLastShot or 0
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

-- Override GetChargeAmount so the arm-glow / charge HUD reflects each mode correctly:
--   Railgun   → vanilla behaviour (charge over kChargeTime=2s while railgunAttacking)
--   Grenade   → 0→1 over kGrenadeChargeTime while railgunAttacking; 0 otherwise
--   Flamethr. → directly equals _flameHeat (0→1 while heating, 1→0 while cooling)
--   Welder    → 0→1 over kWelderChargeLoopTime while welding; 0 otherwise
local baseGetChargeAmount = Railgun.GetChargeAmount
function Railgun:GetChargeAmount()
    local mode = self:GetWeaponMode()
    if mode == kExoSpecialMode.Flamethrower then
        return self._flameHeat or 0
    elseif mode == kExoSpecialMode.Grenade then
        -- Charge progress derives from the networked railgunAttacking + timeChargeStarted
        -- (same source the vanilla railgun uses), so the bar/arm-glow stay correct
        -- under client-side prediction.
        return self.railgunAttacking
            and math.min(1, (Shared.GetTime() - self.timeChargeStarted) / kGrenadeChargeTime)
            or 0
    elseif mode == kExoSpecialMode.Welder then
        -- The welder charge bar reflects the CURRENT TARGET'S progress: the build
        -- fraction of a structure under construction, or the armour (weld) fraction
        -- of a damaged weldable.  It starts at 0 when there is no valid target.
        -- _welderChargeFrac is refreshed each render frame in OnUpdateRender (client).
        return self._welderChargeFrac or 0
    end
    return baseGetChargeAmount(self)
end

-- Override GetDamageType so the Welder's enemy-facing zap deals kWelderDamageType
-- (Flame) instead of inheriting the Railgun's own kRailgunDamageType (Structural).
-- Structural damage DOUBLES against anything that GetReceivesStructuralDamage()
-- (i.e. structures) — since the welder's enemy branch fires on ALIEN STRUCTURES
-- too (they're "enemies" the same as alien players), this was silently doubling
-- the intended 1.5× damage whenever the exo welded an enemy building.
--
-- Vanilla Railgun.lua never defines Railgun:GetDamageType — DamageMixin:DoDamage
-- falls back to `LookupTechData(self:GetTechId(), kTechDataDamageType, kDamageType.Normal)`
-- when self.GetDamageType is nil.  For every mode OTHER than Welder we must
-- replicate that exact fallback here (not just return kDamageType.Normal), or every
-- other mode (Railgun/Grenade/Flamethrower) would silently lose its Structural
-- damage type the moment we add ANY GetDamageType method to the class.
function Railgun:GetDamageType()
    if self:GetWeaponMode() == kExoSpecialMode.Welder then
        return kWelderDamageType
    end
    return LookupTechData(self:GetTechId(), kTechDataDamageType, kDamageType.Normal)
end

-- Welder mode uses CheckMeleeCapsule which calls GetMeleeBase/GetMeleeOffset.
function Railgun:GetMeleeBase()
    return 2, 2
end

function Railgun:GetMeleeOffset()
    return 0.0
end

-- ── Server-safe barrel point ─────────────────────────────────────────────────
local function GetExoArmBarrelPoint(self, player)
    local origin     = player:GetEyePos()
    local viewCoords = player:GetViewCoords()
    local side       = self:GetIsLeftSlot() and 0.65 or -0.65
    return origin + viewCoords.zAxis * 0.9 + viewCoords.xAxis * side + viewCoords.yAxis * -0.19
end

-- ── Welder looping sound (server) ─────────────────────────────────────────────
-- Two mutually-exclusive loops: the Builder tool's scan sound while constructing
-- a structure, and the standard welder sound while repairing armour (or as the
-- default when neither applies, e.g. aimed at nothing / damaging an enemy).
if Server then

    function Railgun:StartExoWeldSound(isConstructing)
        if isConstructing then
            if not self._scanSoundEnt then
                self._scanSoundEnt = Server.CreateEntity(SoundEffect.kMapName)
                self._scanSoundEnt:SetAsset(kBuilderScanSound)
                self._scanSoundEnt:SetParent(self)
            end
            if not self._scanSoundPlaying then
                self._scanSoundEnt:Start()
                self._scanSoundPlaying = true
            end
            if self._weldSoundEnt and self._weldSoundPlaying then
                self._weldSoundEnt:Stop()
                self._weldSoundPlaying = false
            end
        else
            if not self._weldSoundEnt then
                self._weldSoundEnt = Server.CreateEntity(SoundEffect.kMapName)
                self._weldSoundEnt:SetAsset(kWeldSound)
                self._weldSoundEnt:SetParent(self)
            end
            if not self._weldSoundPlaying then
                self._weldSoundEnt:Start()
                self._weldSoundPlaying = true
            end
            if self._scanSoundEnt and self._scanSoundPlaying then
                self._scanSoundEnt:Stop()
                self._scanSoundPlaying = false
            end
        end
    end

    function Railgun:StopExoWeldSound()
        if self._weldSoundEnt and self._weldSoundPlaying then
            self._weldSoundEnt:Stop()
            self._weldSoundPlaying = false
        end
        if self._scanSoundEnt and self._scanSoundPlaying then
            self._scanSoundEnt:Stop()
            self._scanSoundPlaying = false
        end
    end

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

-- Root cause of grenades sometimes detonating on their own firing Exo: the
-- default PhysicsMask.PredictedProjectileGroup only excludes
-- PhysicsGroup.MarinePlayerGroup from projectile collision, not
-- PhysicsGroup.BigPlayerControllersGroup (which is what Exo:GetControllerPhysicsGroup
-- actually returns) - so the grenade's own physics move can genuinely collide
-- with the firing Exo's (or any nearby friendly Exo's) controller hull,
-- especially right after firing if the Exo turns/moves. This custom mask is
-- PredictedProjectileGroup's own exclusion list (PhysicsGroups.lua:214-223)
-- plus BigPlayerControllersGroup, so the grenade behaves the same way toward
-- Exos as it already correctly does toward Marine players.
local kExoGrenadePhysicsMask = CreateMaskExcludingGroups(
    PhysicsGroup.CollisionGeometryGroup,
    PhysicsGroup.RagdollGroup,
    PhysicsGroup.ProjectileGroup,
    PhysicsGroup.BabblerGroup,
    PhysicsGroup.WeaponGroup,
    PhysicsGroup.DroppedWeaponGroup,
    PhysicsGroup.CommanderBuildGroup,
    PhysicsGroup.PathingGroup,
    PhysicsGroup.WebsGroup,
    PhysicsGroup.MarinePlayerGroup,
    PhysicsGroup.BigPlayerControllersGroup
)

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: FireGrenade
-- Flat trajectory: gravity=0 → straight path.
-- gExoHeavyGrenadePending flags the next Grenade:OnInitialized (GrenadeHeavyMode.lua).
-- ─────────────────────────────────────────────────────────────────────────────
local function FireGrenade(self)

    local player = self:GetParent()
    if not player then return end

    if Server or (Client and Client.GetIsControllingPlayer()) then

        local viewCoords = player:GetViewCoords()
        local startPoint = GetExoArmBarrelPoint(self, player)
        local dir        = viewCoords.zAxis

        _G.gExoHeavyGrenadePending  = true
        player.exoHeavyGrenadePending = true

        -- kGrenadeGravity causes the grenade to start flat then arc downward over time.
        -- kExoGrenadePhysicsMask (see above) additionally excludes the firing
        -- Exo's own collision group, fixing self-detonation on the Exo.
        player:CreatePredictedProjectile(
            "Grenade",
            startPoint,
            dir * kGrenadeSpeed,
            0,                 -- bounce
            0,                 -- friction
            kGrenadeGravity,   -- arc: starts linear, falls gradually
            kExoGrenadePhysicsMask
        )

        _G.gExoHeavyGrenadePending  = false
        player.exoHeavyGrenadePending = false

        -- Flag for the owning client: suppress muzzle flash except on actual fire.
        self._grenadeJustFired = true
    end

    if Server then
        local pos = GetExoArmBarrelPoint(self, player)
        StartSoundEffectAtOrigin(kGLFireSound, pos)
    end

    self.timeOfLastShot = Shared.GetTime()

end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: PerformExoWeld
-- ─────────────────────────────────────────────────────────────────────────────
local function PerformExoWeld(self, player, dt)

    if not Server then return end

    local viewAngles = player:GetViewAngles()
    local viewCoords = viewAngles:GetCoords()
    local startPoint = GetExoArmBarrelPoint(self, player)
    local endPoint   = startPoint + viewCoords.zAxis * kExoWeldRange

    -- Filter only the player; leaving the Railgun unfiltered avoids blocking the trace.
    local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Default,
                                  PhysicsMask.AllButPCsAndRagdolls, EntityFilterOne(player))

    local target = trace.entity
    if not target then
        -- Fallback melee capsule for targets too close for the ray.
        local didHit, capTarget = CheckMeleeCapsule(self, player, 0, kExoWeldRange, nil,
                                                    true, 1, nil, nil,
                                                    PhysicsMask.AllButPCsAndRagdolls)
        if didHit then target = capTarget end
    end

    -- Determine whether the current target is being CONSTRUCTED (not yet built) so
    -- the looping sound can switch to the Builder tool's scan sound for that case,
    -- and the standard weld sound for every other case (repairing, enemy, no target).
    local isConstructing = target and HasMixin(target, "Live")
        and player:GetTeamNumber() == target:GetTeamNumber()
        and HasMixin(target, "Construct") and not target:GetIsBuilt()
        and GetAreFriends(target, player) and target:GetIsAlive()
    self:StartExoWeldSound(isConstructing)

    if target and HasMixin(target, "Live") then

        if player:GetTeamNumber() == target:GetTeamNumber() then
            -- ── Friendly: repair / construct ─────────────────────────────────────
            if HasMixin(target, "Weldable") and target:GetWeldPercentage() < 1 then
                local weldRate = kExoWelderPlayerRate
                if target.GetReceivesStructuralDamage and target:GetReceivesStructuralDamage() then
                    weldRate = kExoWelderStructureRate
                end
                target:OnWeld(player, dt, player, weldRate)
                if not target.OnWeldOverride then
                    target:AddHealth(weldRate * dt)
                end
            end

            -- GetCanConstruct() rejects Exo players (only Marine/Gorge/MAC).
            if isConstructing then
                target:Construct(dt, player)
            end

        elseif GetAreEnemies(player, target) and target:GetCanTakeDamage() then
            -- ── Enemy: deal 1.5× hand-welder flame damage ────────────────────────
            -- kWelderDamagePerSecond = 30 HP/s (Balance.lua).  GetDamageType() is
            -- overridden below to return kWelderDamageType (Flame) for Welder mode,
            -- so this doesn't inherit the Railgun's own Structural damage type
            -- (which was doubling damage against alien STRUCTURES specifically).
            local dmg = kWelderDamagePerSecond * 1.5 * dt
            local dir = GetNormalizedVector(target:GetOrigin() - player:GetOrigin())
            self:DoDamage(dmg, target, target:GetModelOrigin(), dir, "none", false, false)
            if HasMixin(target, "Fire") then
                target:SetOnFire(player, self)
            end
        end

    end

end

-- ── Step 3: Wrap Railgun:OnPrimaryAttack ─────────────────────────────────────
local baseOnPrimaryAttack = Railgun.OnPrimaryAttack
function Railgun:OnPrimaryAttack(player)

    local mode = self:GetWeaponMode()

    if mode == kExoSpecialMode.Railgun then
        baseOnPrimaryAttack(self, player)

    elseif mode == kExoSpecialMode.Grenade then
        self._grenadeAttacking = true
        -- Charge state is tracked ENTIRELY through the vanilla railgun's networked
        -- fields (railgunAttacking + timeChargeStarted), exactly like the base
        -- railgun.  This is essential for client-side prediction: non-networked Lua
        -- flags are not rolled back/replayed during prediction, which caused the
        -- charge to stall at 0% while held and fire on low charge when spammed.
        --
        -- OnPrimaryAttack is level-triggered (called every held frame), so start the
        -- charge whenever railgunAttacking is false - including immediately after a
        -- grenade fires, while the button is still held. A full charge-to-100% is
        -- still required to fire again (ProcessMoveOnWeapon's kGrenadeChargeTime
        -- gate below, unchanged) - only the requirement to fully release the button
        -- between shots is removed, matching how the Flamethrower/Welder modes
        -- below already work.
        if not self.railgunAttacking then
            self.timeChargeStarted = Shared.GetTime()
            self.railgunAttacking  = true
        end

    elseif mode == kExoSpecialMode.Flamethrower then
        -- Allow firing only when not overheated and not already active.
        if not self.railgunAttacking and not self._flameOverheated then
            self.timeChargeStarted = Shared.GetTime()
            self.railgunAttacking  = true
            if Server then self:StartExoFlameSound() end
        end

    elseif mode == kExoSpecialMode.Welder then
        self._welderAttacking = true
        if not self.railgunAttacking then
            self.timeChargeStarted = Shared.GetTime()
            self.railgunAttacking  = true
        end
        -- Default to the weld sound on the initial press; PerformExoWeld
        -- (ProcessMoveOnWeapon) reclassifies and switches sounds every tick.
        if Server then self:StartExoWeldSound(false) end
    end

end

-- ── Step 3: Wrap Railgun:OnPrimaryAttackEnd ───────────────────────────────────
local baseOnPrimaryAttackEnd = Railgun.OnPrimaryAttackEnd
function Railgun:OnPrimaryAttackEnd(player)

    local mode = self:GetWeaponMode()

    if mode == kExoSpecialMode.Railgun then
        baseOnPrimaryAttackEnd(self, player)

    elseif mode == kExoSpecialMode.Grenade then
        self._grenadeAttacking = false
        -- Button released: stop charging. Releasing before full charge simply
        -- cancels the charge (railgunAttacking=false → GetChargeAmount reads 0)
        -- and, because no fire occurred, no _grenadeShootAnimEnd window is
        -- opened so the shoot animation does NOT play on an early release.
        self.railgunAttacking = false

    elseif mode == kExoSpecialMode.Flamethrower then
        -- Clear firing state. Do NOT set timeOfLastShot — that would trigger
        -- the railgun muzzle flash cinematic on every button release.
        if self.railgunAttacking then
            self.railgunAttacking = false
            if Server then self:StopExoFlameSound() end
        end

    elseif mode == kExoSpecialMode.Welder then
        self._welderAttacking = false
        self.railgunAttacking = false
        if Server then self:StopExoWeldSound() end
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
    elseif mode == kExoSpecialMode.Welder then
        return kDeathMessageIcon.ExoWelder
    elseif mode == kExoSpecialMode.Grenade then
        return kDeathMessageIcon.ExoGrenadeLauncher
    end
    return baseGetDeathIconIndex(self)
end

-- ── Step 3: Wrap Railgun:OnTag ────────────────────────────────────────────────
local baseOnTag = Railgun.OnTag
function Railgun:OnTag(tagName)

    local mode = self:GetWeaponMode()

    if mode == kExoSpecialMode.Railgun then
        baseOnTag(self, tagName)

    else
        -- Flamethrower / Welder: suppress all tags (no railgun slug, no lockCharging).
        return
    end

end

-- ── Step 3: Wrap Railgun:ProcessMoveOnWeapon ──────────────────────────────────
local baseProcessMoveOnWeapon = Railgun.ProcessMoveOnWeapon
function Railgun:ProcessMoveOnWeapon(player, input)

    local mode = self:GetWeaponMode()
    local now  = Shared.GetTime()
    local dt   = input.time

    if mode == kExoSpecialMode.Railgun then
        baseProcessMoveOnWeapon(self, player, input)

    elseif mode == kExoSpecialMode.Grenade then

        -- Fire when the charge (tracked via the networked railgunAttacking +
        -- timeChargeStarted) reaches full.  This is the ONLY path that fires a
        -- grenade — releasing the button never fires — so spam-clicking cannot
        -- launch low-charge grenades.
        if self.railgunAttacking and self.timeChargeStarted
           and (now - self.timeChargeStarted) >= kGrenadeChargeTime then
            FireGrenade(self)
            -- railgunAttacking true→false this frame makes the animation FSM see the
            -- primary→none transition, so the shoot animation plays IMMEDIATELY.
            -- OnPrimaryAttack (still called every held frame) will see
            -- railgunAttacking false on the next frame and start a fresh charge
            -- immediately if the button is still held - by design, so the next
            -- grenade can be queued up without releasing first.
            self.railgunAttacking     = false
            self._grenadeShootAnimEnd = now + 0.7
        end

    elseif mode == kExoSpecialMode.Flamethrower then

        if self.railgunAttacking then

            -- Accumulate heat: 5 seconds of continuous fire reaches 100%.
            -- At 100% set _flameOverheated and stop firing; the railgunAttacking→false
            -- transition lets the FSM play the shoot-flourish animation (simulating
            -- a critical heat burst). Player cannot fire again until heat returns to 0.
            self._flameHeat = math.min(1.0, (self._flameHeat or 0) + dt * kFlameHeatRate)
            if self._flameHeat >= 1.0 then
                self._flameOverheated = true
                self.railgunAttacking = false
                -- Open a short, explicit window (same idiom as the grenade's
                -- _grenadeShootAnimEnd) during which OnUpdateAnimationInput lets the
                -- real (false) value through, producing the primary→none edge that
                -- plays the shoot flourish EXACTLY once, only at 100% heat.
                self._flameShootAnimEnd = now + 0.7
                if Server then self:StopExoFlameSound() end
            end

            -- Rate-limited cone damage + flame pool creation (server only).
            if Server and (self.timeLastFlameDamage + kFlamethrowerDamageRate) <= now then
                self.timeLastFlameDamage = now

                local eyePos     = player:GetEyePos()
                local fireDir    = player:GetViewCoords().zAxis
                local extents    = Vector(kFlamethrowerConeWidth, kFlamethrowerConeWidth, kFlamethrowerConeWidth)
                local filterEnts = { self, player }
                local dmgAmount  = kFlamethrowerDamagePerSec * kFlamethrowerDamageRate

                local trace = TraceMeleeBox(self, eyePos, fireDir, extents, kFlamethrowerRange,
                                            PhysicsMask.Flame, EntityFilterList(filterEnts))

                -- Burn away hazards in the cone, exactly like the hand Flamethrower
                -- (CNBalance/Weapons/Marine/Flamethrower.lua:32). The Exo's flame mode
                -- is built on the Railgun class (not Flamethrower), so it never
                -- inherited this at all - the Exo flamethrower previously could not
                -- destroy Spores/Umbra/BileBomb/AcidSpray/etc.
                -- self here is a Railgun instance (kExoSpecialMode.Flamethrower), which
                -- has everything BurnSporesAndUmbra needs (DamageMixin's self:DoDamage,
                -- EffectsMixin's self:TriggerEffects, self:GetParent() returning the Exo
                -- player) - so the exact same function can just be called directly on
                -- it (Flamethrower.BurnSporesAndUmbra(self, ...), not self:BurnSporesAndUmbra(...),
                -- since Railgun does not inherit from Flamethrower).
                Flamethrower.BurnSporesAndUmbra(self, eyePos, trace.endPoint)

                -- Create a Flame entity on the ground below the hit point.
                if trace.fraction ~= 1 then
                    local hitPt = trace.endPoint
                    local groundTrace = Shared.TraceRay(hitPt, hitPt + Vector(0, -2.6, 0),
                        CollisionRep.Default, PhysicsMask.CystBuild, EntityFilterAllButIsa("TechPoint"))
                    if groundTrace.fraction ~= 1 then
                        CreateExoFlame(player, groundTrace.endPoint)
                    end
                end

                -- Damage directly traced entity.
                -- Pass surface="none" (not nil): DamageMixin:DoDamage only skips its
                -- "trigger damage effects" block when surface is EXACTLY the string
                -- "none" (`if surface ~= "none" then ... end`).  nil does NOT skip it —
                -- it falls through to `surface = GetIsAlienUnit(target) and "organic"`,
                -- which still fires the Railgun's organic-hit cinematic (the blue-green
                -- electric-arc splat), clashing with the flamethrower's own fire visuals.
                if trace.entity and HasMixin(trace.entity, "Live") and trace.entity:GetCanTakeDamage()
                   and GetAreEnemies(player, trace.entity) then
                    local hitEnt = trace.entity
                    self:DoDamage(dmgAmount, hitEnt, trace.endPoint, fireDir, "none", false, false)
                    if HasMixin(hitEnt, "Fire") then
                        hitEnt:SetOnFire(player, self)
                    end
                end

                -- Damage nearby entities in the cone (matches vanilla ApplyConeDamage).
                local dmgRadius = kFlamethrowerConeWidth * 2
                local nearbyEnts = GetEntitiesWithMixinWithinXZRange("Live", trace.endPoint, dmgRadius)
                for _, ent in ipairs(nearbyEnts) do
                    if ent ~= player and ent ~= trace.entity and ent:GetCanTakeDamage()
                       and GetAreEnemies(player, ent) then
                        local toEnt = GetNormalizedVector(ent:GetModelOrigin() - eyePos)
                        self:DoDamage(dmgAmount, ent, ent:GetModelOrigin(), toEnt, "none", false, false)
                        if HasMixin(ent, "Fire") then
                            ent:SetOnFire(player, self)
                        end
                    end
                end
            end
        else
            -- Not firing: cool down the heat at kFlameCoolRate.
            self._flameHeat = math.max(0, (self._flameHeat or 0) - dt * kFlameCoolRate)
            -- Clear overheat only when heat reaches exactly 0 (not just below 1).
            if self._flameOverheated and self._flameHeat <= 0 then
                self._flameOverheated = false
            end
        end

    elseif mode == kExoSpecialMode.Welder then

        if self._welderAttacking then
            -- Loop the charge animation below the shoot tag so it plays continuously.
            if self.railgunAttacking and (now - (self.timeChargeStarted or 0)) >= kWelderChargeLoopTime then
                self.timeChargeStarted = now
            end
            PerformExoWeld(self, player, dt)
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
    elseif mode == kExoSpecialMode.Welder then
        -- Force "primary" every frame so the animation FSM never sees a primary→none
        -- transition — that transition is what plays the shoot animation, which the
        -- welder must NEVER do (including when the fire button is released).  The
        -- charge animation still plays (driven by GetChargeAmount → the target's
        -- build/armour fraction); only the shoot flourish is suppressed.
        local saved = self.railgunAttacking
        self.railgunAttacking = true
        baseOnUpdateAnimationInput(self, modelMixin)
        self.railgunAttacking = saved
    elseif mode == kExoSpecialMode.Grenade then
        -- After a legitimate fire: allow "none" for 0.7s so the shoot animation plays.
        -- _grenadeShootAnimEnd is set only by ProcessMoveOnWeapon's flourish-end path
        -- (never by spam/early-release), so the shoot animation can't be triggered spuriously.
        -- All other times: force "primary" to keep the charge animation showing.
        if self._grenadeShootAnimEnd and Shared.GetTime() < self._grenadeShootAnimEnd then
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

    local kRailgunMuzzleCinematic = PrecacheAsset("cinematics/marine/railgun/muzzle_flash.cinematic")

    local function TriggerRailgunMuzzle(self)
        local parent = self:GetParent()
        if not parent then return end
        local attachPoint
        if parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson() then
            attachPoint = kFirstPersonAttachPoints[self:GetExoWeaponSlot()]
        else
            attachPoint = kThirdPersonAttachPoints[self:GetExoWeaponSlot()]
        end
        CreateMuzzleCinematic(self, kRailgunMuzzleCinematic, kRailgunMuzzleCinematic,
                              attachPoint, parent, nil, true)
    end

    -- Ten small offsets (attach-point local space) used to spread the welder repair
    -- cinematics out "near each other" so the arm reads as more powerful than a
    -- standard armoury welder.  Spreading copies is the reliable way to look bigger:
    -- scaling a cinematic's Coords axes only moves emitter origins, and particle
    -- sizes are baked into the .cinematic file, so a single copy can't be enlarged.
    local kWelderSpreadOffsets = {
        Vector( 0.00,  0.00, 0.00),
        Vector( 0.12,  0.00, 0.00), Vector(-0.12,  0.00, 0.00),
        Vector( 0.00,  0.12, 0.00), Vector( 0.00, -0.12, 0.00),
        Vector( 0.09,  0.09, 0.00), Vector(-0.09,  0.09, 0.00),
        Vector( 0.09, -0.09, 0.00), Vector(-0.09, -0.09, 0.00),
        Vector( 0.00,  0.00, 0.12),
    }

    -- Like CreateMuzzleCinematic, but places the cinematic at an offset from the
    -- attach point (and optionally scales its emitter space) so multiple copies can
    -- be spread around the muzzle.  Mirrors core/ParticleEffect.lua CreateMuzzleCinematic.
    local function CreateOffsetMuzzleCinematic(self, cinematicName, attachPoint, offset, scale)
        local parent = self:GetParent()
        if not parent then return end
        if not (parent:GetIsVisible() or (parent:isa("Player") and parent:GetIsLocalPlayer())) then return end

        local zone, attachTo
        if parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson() then
            zone     = RenderScene.Zone_ViewModel
            attachTo = parent:GetViewModelEntity()
        else
            zone     = RenderScene.Zone_Default
            attachTo = self
        end
        if not attachTo or not attachPoint then return end

        local cinematic = Client.CreateCinematic(zone)
        cinematic:SetCinematic(cinematicName)
        cinematic:SetParent(attachTo)

        local coords = Coords.GetIdentity()
        if scale and scale ~= 1 then
            coords.xAxis = coords.xAxis * scale
            coords.yAxis = coords.yAxis * scale
            coords.zAxis = coords.zAxis * scale
        end
        if offset then coords.origin = offset end
        cinematic:SetCoords(coords)
        cinematic:SetAttachPoint(attachTo:GetAttachPointIndex(attachPoint))
        return cinematic
    end

    -- Classify what the welder arm is aimed at (client-side).
    -- Returns: frac (0..1), isConstructing, isRepairing, target
    --   frac = build fraction (constructing) or armour/weld fraction (repairing),
    --          0 when there is no valid target.
    local function GetWelderTarget(parent)
        local startPt = parent:GetEyePos()
        local endPt   = startPt + parent:GetViewCoords().zAxis * kExoWeldRange
        local trace   = Shared.TraceRay(startPt, endPt, CollisionRep.Default,
                            PhysicsMask.AllButPCsAndRagdolls, EntityFilterOne(parent))
        local tgt = trace.entity
        if not tgt then return 0, false, false, nil end

        if HasMixin(tgt, "Construct") and not tgt:GetIsBuilt() then
            local frac = tgt.GetBuiltFraction and tgt:GetBuiltFraction() or 0
            return Clamp(frac, 0, 1), true, false, tgt
        end
        if HasMixin(tgt, "Weldable") and tgt.GetWeldPercentage and tgt:GetWeldPercentage() < 1 then
            return Clamp(tgt:GetWeldPercentage(), 0, 1), false, true, tgt
        end
        return 0, false, false, tgt
    end

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
        elseif mode == kExoSpecialMode.Grenade then
            return self._grenadeAttacking
        elseif mode == kExoSpecialMode.Welder then
            -- Use the NETWORKED railgunAttacking, not the plain Lua field
            -- _welderAttacking: this function is read by ClientWeaponEffectsMixin
            -- (and other generic weapon-effect code) on EVERY client watching this
            -- weapon, not just the owner.  _welderAttacking is only ever set true on
            -- the server and the controlling player's own client, so remote clients
            -- always saw it as false — which was the root cause of the welder's
            -- world-model cinematics never appearing for anyone but the pilot.
            return self.railgunAttacking
        end
        return false
    end

    -- Cleanup flame trail and weld info text on entity destruction.
    local baseRGOnDestroy = Railgun.OnDestroy
    function Railgun:OnDestroy()
        DestroyFlameTrail(self)
        if self._weldInfoText then
            GUI.DestroyItem(self._weldInfoText)
            self._weldInfoText = nil
        end
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

        -- Grenade mode: muzzle flash, charge sound, and arm-glow material.
        if mode == kExoSpecialMode.Grenade then
            local tls    = self.timeOfLastShot
            local parent = self:GetParent()
            local isOwner = parent and parent:GetIsLocalPlayer()

            -- Muzzle flash: owning client uses _grenadeJustFired (set only by FireGrenade)
            -- to avoid nil-vs-0 init spurious trigger and prediction artefacts.
            -- Other clients watch timeOfLastShot (networked) with nil-safe init.
            if isOwner then
                if self._grenadeJustFired then
                    self._grenadeJustFired = false
                    self._lastSeenShotTime = tls
                    TriggerRailgunMuzzle(self)
                end
            else
                if self._lastSeenShotTime == nil then
                    self._lastSeenShotTime = tls
                elseif self._lastSeenShotTime ~= tls then
                    self._lastSeenShotTime = tls
                    TriggerRailgunMuzzle(self)
                end
            end

            -- Charge sound: start when charging (chargeAmount > 0), stop when idle.
            local charge = self:GetChargeAmount()
            if self.chargeSound then
                local playing = self.chargeSound:GetIsPlaying()
                if not playing and charge > 0 then self.chargeSound:Start() end
                if playing  and charge <= 0 then self.chargeSound:Stop()  end
                self.chargeSound:SetParameter("charge", charge, 1)
            end

            -- NOTE: no arm-glow material parameter here (removed) - "chargeAmount"/
            -- "timeSinceLastShot" are the exact shader parameters that drive the
            -- Railgun's own blue-green electric-charge visual (Railgun.lua:359-360,
            -- only meant to apply in true Railgun mode via the mode-gated call at
            -- the top of this function). Setting them here for Grenade mode leaked
            -- that same blue-green glow onto the mesh while charging a grenade -
            -- everything else in this branch (charge sound, HUD charge bar via
            -- chargeDisplayUI where used) is untouched.
        end

        -- Welder mode: the charge bar/arm glow reflect the aimed target's progress
        -- (build % while constructing, armour/weld % while repairing), starting at 0
        -- when there is no valid target.
        if mode == kExoSpecialMode.Welder then
            local parent  = self:GetParent()

            -- Refresh the target fraction that GetChargeAmount() returns (drives the
            -- charge bar AND the arm pose).  Gated on the NETWORKED railgunAttacking
            -- (not the plain _welderAttacking field) so this actually runs for any
            -- client — third-person observers included — and not just the pilot.
            local frac = 0
            if parent and self.railgunAttacking then
                frac = GetWelderTarget(parent)
            end
            self._welderChargeFrac = frac

            local isOwner = parent and parent:GetIsLocalPlayer()
            if isOwner then
                -- NOTE: no arm-glow material parameter here (removed) - see the
                -- matching comment in the Grenade branch above; "chargeAmount"/
                -- "timeSinceLastShot" drive the Railgun-only blue-green electric
                -- charge shader and leaked onto the mesh while welding.
                -- Drive the on-screen charge display with the same target fraction.
                if self.chargeDisplayUI then
                    self.chargeDisplayUI:SetGlobal("chargeAmount" .. self:GetExoWeaponSlotName(), frac)
                    self.chargeDisplayUI:SetGlobal("timeSinceLastShot" .. self:GetExoWeaponSlotName(), Shared.GetTime() - self.timeOfLastShot)
                end
            end
        end

        -- Welder: pulse the muzzle cinematic while the button is held.
        -- Cinematic choice depends on what the arm is pointing at:
        --   • Constructing (building)   → Builder scan cinematic (same as the Builder tool)
        --   • Repairing armor (weldable) → welder_muzzle cinematic × kWelderRepairCount
        --     (spawning multiple copies per pulse is the only reliable way to increase
        --     visual intensity — scaling Coords axes only moves emitter origins, not
        --     particle sizes, which are baked in the cinematic file)
        --   • No valid target            → single welder_muzzle cinematic (idle/default)
        --
        -- Gated on the NETWORKED railgunAttacking, not the plain _welderAttacking
        -- field: OnUpdateRender runs on EVERY client that can see this weapon, but
        -- _welderAttacking is only ever set true on the server and the controlling
        -- player's own client.  Using it here meant remote/third-person observers
        -- never saw this branch execute at all, so the cinematics never appeared
        -- on the exo's world model for anyone but the pilot.
        if mode == kExoSpecialMode.Welder and self.railgunAttacking then
            local now = Shared.GetTime()
            if not self._nextWeldPulse or now >= self._nextWeldPulse then
                self._nextWeldPulse = now + kWeldPulseInterval
                local parent = self:GetParent()
                if parent then
                    local attachPoint
                    if parent:GetIsLocalPlayer() and not parent:GetIsThirdPerson() then
                        attachPoint = kFirstPersonAttachPoints[self:GetExoWeaponSlot()]
                    else
                        attachPoint = kThirdPersonAttachPoints[self:GetExoWeaponSlot()]
                    end

                    -- Classify the aimed target (same logic as the charge bar).
                    local _, isConstructing, isRepairing = GetWelderTarget(parent)

                    if isConstructing then
                        -- Building something: play the Builder tool's scan cinematic.
                        -- useFilter=false matches the Builder tool exactly (Builder.lua
                        -- passes no filter); a filtered variant of builder_scan may not
                        -- exist, which would silently render nothing.
                        CreateMuzzleCinematic(self, kBuilderScanCinematic, kBuilderScanCinematic,
                                              attachPoint, parent, nil, false)
                    elseif isRepairing then
                        -- Repairing armour (welding, not building): play the larger
                        -- Railgun muzzle cinematic instead of the small handheld welder
                        -- effect, so the arm reads as a powerful welding tool.
                        CreateMuzzleCinematic(self, kRailgunMuzzleCinematic, kRailgunMuzzleCinematic,
                                              attachPoint, parent, nil, true)
                    else
                        CreateMuzzleCinematic(self, kWelderRailgunCinematic, kWelderRailgunCinematic,
                                              attachPoint, parent, nil, true)
                    end
                end
            end
        end

        -- Welder: show build/armor progress near the crosshair for the aimed target.
        if mode == kExoSpecialMode.Welder and self._welderAttacking then
            local exoPlayer = self:GetParent()
            if exoPlayer and exoPlayer:GetIsLocalPlayer() then
                local startPt = exoPlayer:GetEyePos()
                local endPt   = startPt + exoPlayer:GetViewCoords().zAxis * kExoWeldRange
                local trace   = Shared.TraceRay(startPt, endPt, CollisionRep.Default,
                                                PhysicsMask.AllButPCsAndRagdolls,
                                                EntityFilterOne(exoPlayer))
                local tgt = trace.entity
                if tgt then
                    local lines = {}
                    if HasMixin(tgt, "Construct") and not tgt:GetIsBuilt() then
                        local pct = tgt.GetBuiltFraction and math.floor(tgt:GetBuiltFraction() * 100) or 0
                        table.insert(lines, string.format("Building: %d%%", pct))
                    elseif HasMixin(tgt, "Weldable") then
                        local pct = math.floor((tgt.GetWeldPercentage and tgt:GetWeldPercentage() or 1) * 100)
                        if pct < 100 then
                            table.insert(lines, string.format("Armour: %d%%", pct))
                        end
                    end
                    if #lines > 0 then
                        -- Lazy-create a screen-space text label.
                        if not self._weldInfoText then
                            self._weldInfoText = GetGUIManager():CreateTextItem()
                            self._weldInfoText:SetFontName(Fonts.kAgencyFB_Small)
                            self._weldInfoText:SetScale(GUIScale(Vector(1, 1, 0)))
                            self._weldInfoText:SetColor(Color(0.4, 0.85, 1.0, 1.0))
                            self._weldInfoText:SetAnchor(GUIItem.Middle, GUIItem.Center)
                            self._weldInfoText:SetTextAlignmentX(GUIItem.Align_Center)
                            self._weldInfoText:SetTextAlignmentY(GUIItem.Align_Center)
                            self._weldInfoText:SetPosition(GUIScale(Vector(0, 80, 0)))
                        end
                        self._weldInfoText:SetText(table.concat(lines, "\n"))
                        self._weldInfoText:SetIsVisible(true)
                    else
                        if self._weldInfoText then self._weldInfoText:SetIsVisible(false) end
                    end
                else
                    if self._weldInfoText then self._weldInfoText:SetIsVisible(false) end
                end
            end
        else
            if self._weldInfoText then self._weldInfoText:SetIsVisible(false) end
        end

        -- Flamethrower: manage the looping flame trail cinematic.
        -- self:GetParent() returns the Exo PLAYER directly — the Railgun arm weapons
        -- are owned/parented by the player, not by the ExoWeaponHolder.
        if mode == kExoSpecialMode.Flamethrower then
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

                trail:SetOptions({
                    numSegments              = 6,
                    collidesWithWorld        = true,
                    visibilityChangeDuration = 0.2,
                    fadeOutCinematics        = true,
                    stretchTrail             = false,
                    trailLength              = kFlamethrowerRange + 0.5,
                    minHardening             = 0.5,
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
