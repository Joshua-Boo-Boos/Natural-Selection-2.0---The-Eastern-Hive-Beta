-- ======= NS2.0-TEH-Beta: Combat/GrenadeHeavyMode.lua =======
--
-- Extends the existing vanilla Grenade class (post-hook, no new class,
-- no new Shared.LinkClassToMap) to support the exo grenade-launcher mode.
--
-- Loaded via:
--   ModLoader.SetupFileHook("lua/Weapons/Marine/Grenade.lua",
--                           "lua/Combat/GrenadeHeavyMode.lua", "post")
--
-- HOW HEAVY MODE IS FLAGGED
--   Railgun (grenade mode, via Combat/ExoSpecialWeapon.lua) sets
--   player.exoHeavyGrenadePending = true immediately before calling
--   player:CreatePredictedProjectile("Grenade", ...), then clears it to false
--   right after. Grenade:OnInitialized (Server-side) reads this flag from the
--   entity's owner and calls self:SetHeavyMode().
--   Normal GL grenades are fired without ever setting this flag, so heavyMode
--   remains nil (falsy) and every single code path below is skipped — they are
--   100% unchanged.
--
-- WHAT HEAVY MODE CHANGES
--   * Model      → keeps grenade launcher grenade model
--   * Damage     → 50 flat damage (kPulseGrenadeDamage) within kPulseGrenadeDamageRadius,
--                  no distance falloff (same as pulse grenade — every entity in radius
--                  takes the full 50).
--   * Damage type→ kDamageType.Normal (matches pulse grenade)
--   * Electrify  → all live entities within kPulseGrenadeEnergyDamageRadius are
--                  electrified for kElectrifiedDuration (5 s), same as pulse grenade.
--   * Explosion  → TriggerEffects("pulse_grenade_explode") for the electric arc VFX.
--   * Trajectory → arcing (gravity=kGrenadeGravity passed by ExoSpecialWeapon;
--                  starts flat, falls gradually over time).
--   * Contact det→ detonates on first surface/entity contact.
--     kNeedsHitEntity=true means ProcessHit never fires for world geometry,
--     so OnUpdate detects contact via speed-drop (bounce drops speed; gravity
--     only ever adds to speed so any decrease = wall hit) and look-ahead ray
--     (catches angled hits before they are processed by the engine).
--     The 2-second fuse is overridden in both cases.
-- =====================================================================

-- Camera-shake tunables.  Vanilla Grenade.lua declares these as FILE-LOCALS
-- (NS2-Copy lines 32-34), so they are NOT visible to this post-hook — referencing
-- the vanilla names here yields nil and crashes TriggerCameraShake with a nil
-- radius.  Re-declare local copies (pulse-grenade values, since heavy mode mimics
-- the pulse grenade).
local kGrenadeCameraShakeDistance = 15
local kGrenadeMinShakeIntensity   = 0.01
local kGrenadeMaxShakeIntensity   = 0.14

-- Exo Grenade Launcher damage - deliberately separate from kPulseGrenadeDamage
-- (the real Pulse Grenade weapon's own damage, 50) so tuning one never affects
-- the other.
local kHeavyGrenadeDamage = 30

-- ---------- SetHeavyMode / GetHeavyMode ----------

function Grenade:SetHeavyMode()
    self.heavyMode = true
end

function Grenade:GetIsHeavyMode()
    return self.heavyMode == true
end

-- ---------- Override GetDamageType ----------
-- Use Normal damage type to match pulse grenade behaviour.

local baseGetDamageType = Grenade.GetDamageType
function Grenade:GetDamageType()
    if self.heavyMode then
        return kDamageType.Normal
    end
    return baseGetDamageType(self)
end

-- ---------- Override GetWeaponTechId (Weapons-upgrade scaling fix) ----------
-- Grenade:GetWeaponTechId (vanilla Grenade.lua:68-70) is hardcoded to always
-- return kTechId.GrenadeLauncher, which NS2Gamerules_GetUpgradedDamageScalar
-- (CNBalance/DamageTypes.lua:70-80) keys to a GrenadeLauncher-specific scalar
-- table {1.08, 1.16, 1.25} - NOT the "Default" table {1.1, 1.2, 1.3} that
-- Minigun/Railgun (and Flamethrower/Welder, sharing the same underlying
-- Railgun instance) use, since neither of their techIds has a specific entry.
-- This is why 25 damage became 31 (25*1.25) at Weapons 3 instead of scaling
-- the same way the other Exo weapons do. Returning kTechId.None for heavy-mode
-- grenades falls through to the same Default table as Minigun/Railgun.
local baseGetWeaponTechId = Grenade.GetWeaponTechId
function Grenade:GetWeaponTechId()
    if self.heavyMode then
        return kTechId.None
    end
    return baseGetWeaponTechId(self)
end

-- ---------- Override GetDeathIconIndex (Exo killfeed routing) ----------
-- A grenade kill is credited to THIS Grenade projectile entity (self:DoDamage
-- in Detonate, doer = self), not the firing Railgun weapon - so the mode-aware
-- Railgun:GetDeathIconIndex (Combat/ExoSpecialWeapon.lua) never runs for a
-- grenade kill. Without this override a heavy-mode (Exo) grenade returned the
-- plain vanilla kDeathMessageIcon.Grenade, which is NOT a key in
-- GUIDeathMessagesExo.lua's kExoKillIcons, so it took the normal killfeed path
-- with no "EXO" prefix. Returning ExoGrenadeLauncher routes it through the Exo
-- row builder ("EXO" + the GL grenade icon). Hand-GL grenades (not heavyMode)
-- keep the vanilla icon.
local baseGrenadeGetDeathIconIndex = Grenade.GetDeathIconIndex
function Grenade:GetDeathIconIndex()
    if self.heavyMode then
        return kDeathMessageIcon.ExoGrenadeLauncher
    end
    return baseGrenadeGetDeathIconIndex(self)
end

-- ---------- Pick up heavy mode from the owner at creation (Server only) ----------
-- PredictedProjectile:OnInitialized runs on both client and server.
-- The owner flag is only set on Server (CreatePredictedProjectile sets owner
-- via projectile:SetOwner(self) on the server path, and OwnerMixin:GetOwner
-- returns that entity). We guard with "if Server" to be safe.

-- Heavy-mode grenades are meant to detonate on first contact (speed-drop /
-- look-ahead detection in OnUpdate below) - the vanilla 2-second kGrenadeLifetime
-- fallback timer (NS2-Copy/ns2/lua/Weapons/Marine/Grenade.lua:50-52) is only a
-- last-resort safety net for when neither contact check fires (e.g. a shallow
-- landing/settle that never crosses the speed-drop threshold and has nothing
-- for the look-ahead ray to catch). That vanilla timer is scheduled at OnCreate,
-- before heavy mode is even known, and can't easily be cancelled/rescheduled -
-- so a second, much shorter fallback is added below once heavy mode is
-- confirmed. Whichever fires first wins; self._hmDetonated (set inside
-- Detonate itself) guards against the other one double-processing.
local kHeavyGrenadeFallbackFuse = 1.0  -- seconds; tune to taste if it ever feels early/late

local baseOnInitialized = Grenade.OnInitialized
function Grenade:OnInitialized()
    if baseOnInitialized then
        baseOnInitialized(self)
    end
    if Server then
        -- The grenade-mode exo arm sets a global flag immediately before creating
        -- the projectile (OnInitialized runs during CreateEntity, BEFORE the owner
        -- is assigned, so the owner flag is not reliable here).  Check both.
        local owner = self.GetOwner and self:GetOwner()
        if _G.gExoHeavyGrenadePending or (owner and owner.exoHeavyGrenadePending) then
            self:SetHeavyMode()
            self:AddTimedCallback(function(grenade)
                if grenade.heavyMode and not grenade._hmDetonated then
                    grenade:Detonate(nil)
                end
            end, kHeavyGrenadeFallbackFuse)
        end
    end
end

-- ---------- Pulse-grenade-style Detonate for heavy mode ----------
-- Replaces the vanilla Grenade.Detonate for heavy-mode grenades.
-- Vanilla Grenade.Detonate is Server-only (inside "if Server then" block).

if Server then

    local baseDetonate = Grenade.Detonate
    function Grenade:Detonate(targetHit)
        if not self.heavyMode then
            return baseDetonate(self, targetHit)
        end
        -- Guard: base Grenade.OnUpdate (2-second fuse) and our own speed-drop /
        -- look-ahead code can both call Detonate in the same frame.  Only the
        -- first call should execute; subsequent calls are silently ignored.
        if self._hmDetonated then return end
        self._hmDetonated = true

        local origin  = self:GetOrigin()
        -- Heavy-mode (Exo Grenade Launcher) damage is its own value, distinct
        -- from the real Pulse Grenade's kPulseGrenadeDamage (50) - do not
        -- reuse that shared vanilla constant here, changing it would also
        -- change the actual Pulse Grenade weapon.
        local kDmg    = kHeavyGrenadeDamage              -- 25
        local kDmgR   = kPulseGrenadeDamageRadius        -- 4 m
        local kEleR   = kPulseGrenadeEnergyDamageRadius  -- 4 m

        -- Gather entities in damage and electrify radii.
        local dmgEnts = GetEntitiesWithMixinWithinRange("Live", origin, kDmgR)
        local eleEnts = GetEntitiesWithMixinWithinRange("Live", origin, kEleR)
        table.removevalue(dmgEnts, self)
        table.removevalue(eleEnts, self)

        -- Direct hit: full damage + immediate electrify.
        if targetHit then
            table.removevalue(dmgEnts, targetHit)
            table.removevalue(eleEnts, targetHit)
            self:DoDamage(kDmg, targetHit, origin,
                GetNormalizedVector(targetHit:GetOrigin() - origin), "none")
            if targetHit.SetElectrified then
                targetHit:SetElectrified(kElectrifiedDuration)
            end
        end

        -- Flat damage to all entities in damage radius (no distance falloff,
        -- identical to how PulseGrenade.Detonate applies damage).
        for _, entity in ipairs(dmgEnts) do
            local targetOrigin = GetTargetOrigin(entity)
            self:DoDamage(kDmg, entity, targetOrigin,
                GetNormalizedVector(entity:GetOrigin() - origin), "none")
        end

        -- Electrify all live entities in electrify radius.
        for _, entity in ipairs(eleEnts) do
            if entity.SetElectrified then
                entity:SetElectrified(kElectrifiedDuration)
            end
        end

        -- Electric arc explosion VFX (pulse grenade effect).
        local surface = GetSurfaceFromEntity(targetHit)
        local params  = { surface = surface }
        if not targetHit then
            params[kEffectHostCoords] = Coords.GetLookIn(origin, self:GetCoords().zAxis)
        end
        self:TriggerEffects("pulse_grenade_explode", params)
        CreateExplosionDecals(self)
        TriggerCameraShake(self, kGrenadeMinShakeIntensity, kGrenadeMaxShakeIntensity,
            kGrenadeCameraShakeDistance)

        DestroyEntity(self)
    end

    -- ---------- Contact detonation for heavy mode ----------
    -- Vanilla Grenade:ProcessHit is Server-only (defined inside "if Server then" block).

    local baseProcessHit = Grenade.ProcessHit
    function Grenade:ProcessHit(targetHit, surface, normal, endPoint)
        if self.heavyMode then
            -- The firing Exo has its own separate "hittable" physics body
            -- (PhysicsGroup.PlayerGroup, Player.lua:386) distinct from the
            -- movement-controller group excluded by FireGrenade's custom
            -- physics mask - a spawn point only ~0.9m from the Exo's eye can
            -- still overlap/collide with that body. Detonating unconditionally
            -- here (removing vanilla's own owner/enemy check) caused the
            -- grenade to explode on its own firing Exo. Skip (let it bounce)
            -- on the owner or any non-enemy; only actually detonate on a
            -- genuine enemy or world-geometry hit.
            local owner = self.GetOwner and self:GetOwner()
            if targetHit and (targetHit == owner or not GetAreEnemies(self, targetHit)) then
                return
            end
            self:Detonate(targetHit)
            return
        end
        if baseProcessHit then
            return baseProcessHit(self, targetHit, surface, normal, endPoint)
        end
    end

    -- Grenade.kNeedsHitEntity = true so ProcessHit is never called for world
    -- geometry.  Detect surface contact two ways:
    --
    --   1. Speed-drop between frames: the grenade uses gravity > 0, so gravity
    --      continuously ADDS speed (falling faster).  Any frame where speed
    --      DECREASES means the bounce has stolen momentum → detonate.
    --
    --   2. Look-ahead ray: catches the moment before an angled hit is processed
    --      so detonation is as early as physically possible.
    -- Grace window after spawn before Case 1/2 can fire at all - the spawn
    -- point (~0.9m from the firing Exo's eye, GetExoArmBarrelPoint) can still
    -- overlap the Exo's own PlayerGroup collision body, and the physics engine
    -- resolving that overlap on the very first Move() produces an artificial
    -- velocity change Case 1's owner-blind speed-drop check would misread as
    -- a wall hit. ProcessHit's owner check (above) covers genuine hit-entity
    -- cases; this covers the speed-drop heuristic, which never inspects an
    -- entity at all.
    local kHeavyGrenadeSpawnGraceSeconds = 0.1

    local baseGrenadeOnUpdate = Grenade.OnUpdate
    function Grenade:OnUpdate(deltaTime)
        if baseGrenadeOnUpdate then baseGrenadeOnUpdate(self, deltaTime) end
        if not self.heavyMode or self._hmDetonated then return end

        self._hmSpawnTime = self._hmSpawnTime or Shared.GetTime()
        if Shared.GetTime() - self._hmSpawnTime < kHeavyGrenadeSpawnGraceSeconds then
            return
        end

        local vel   = self:GetVelocity()
        local speed = vel:GetLength()

        -- Case 1: speed dropped since last frame (gravity only ever increases speed,
        -- so any decrease means a bounce absorbed momentum).
        local prev = self._hmPrevSpeed
        self._hmPrevSpeed = speed
        if prev and (prev - speed) > 5 then
            -- Do NOT pre-set _hmDetonated here: Detonate() sets it itself as its
            -- re-entry guard.  Setting it first would make Detonate() bail out
            -- immediately and the grenade would never explode.
            self:Detonate(nil)
            return
        end

        -- Case 2: still moving — look ahead to catch angled wall hits.
        if speed < 1 then return end
        local pos   = self:GetOrigin()
        local dir   = GetNormalizedVector(vel)
        local ahead = speed * (deltaTime + 0.025) + 0.40

        local owner  = self.GetOwner and self:GetOwner()
        local ignore = { self }
        if owner then table.insert(ignore, owner) end

        local trace = Shared.TraceRay(pos, pos + dir * ahead,
                                       CollisionRep.Default,
                                       PhysicsMask.Bullets,
                                       EntityFilterList(ignore))

        if trace.fraction < 1.0 then
            -- Detonate() sets _hmDetonated itself; pre-setting it would suppress
            -- the explosion (see speed-drop case above).
            self:Detonate(trace.entity)
        end
    end

end
