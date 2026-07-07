Exo.kBountyThreshold = kBountyClaimMinExo
Exo.kMaxProtectionDamageReduction = 0

-- Thruster/fuel constants — vanilla declares these as FILE-LOCALS in Exo.lua
-- (NS2-Copy/ns2/lua/Exo.lua lines 102-104), so they are NOT visible to this
-- post-hook file.  Our Exo:GetFuel override below reproduces the vanilla fuel
-- math, so we must re-declare local copies with the SAME values.
local kThrustersCooldownTime     = 2.5
local kThrusterDuration          = 1.5
local kThrusterRefuelCooldownTime = 0.75

-- ── Prototype Exo layout table ────────────────────────────────────────────────
-- GLOBAL (no local) so CNBalance/Weapons/ExoWeaponHolderModels.lua can read it.
-- Includes all 4 vanilla layouts (commander-drop / pickup paths) plus 10 new
-- prototype combos.  Each entry: chassis key, l = {mapName [,modeName]}, r = {mapName [,modeName]}.
--
-- IMPORTANT (load-order safety): this table is built at FILE-LOAD time, but the
-- weapon classes (Minigun/Railgun/Claw) and kExoSpecialMode are loaded LATER in
-- Shared.lua (lines 181-183 / Railgun post-hook) than Exo.lua (line 160).
-- Referencing Minigun.kMapName etc. here would index a nil global and abort the
-- whole Exo.lua hook.  So we store PURE DATA: literal map-name strings
-- ("minigun"/"railgun"/"claw" — these equal Minigun.kMapName etc.) and literal
-- mode-NAME strings ("Flamethrower"/"Welder"/"Grenade").  The mode string is
-- resolved to the kExoSpecialMode enum at RUNTIME inside InitWeapons (by which
-- point the enum exists).
kPrototypeExoLayouts = {
    -- ── Vanilla layouts (commander-drop / pickup — must keep working) ──────────
    MinigunMinigun = { chassis="mm", l={"minigun"},           r={"minigun"} },
    RailgunRailgun = { chassis="rr", l={"railgun"},           r={"railgun"} },
    ClawMinigun    = { chassis="cm", l={"claw"},              r={"minigun"} },
    ClawRailgun    = { chassis="cr", l={"claw"},              r={"railgun"} },
    -- ── Prototype combos (keys match kPrototypeExoCombos values) ─────────────
    -- Special arms use "railgun" + a mode name (resolved to kExoSpecialMode in InitWeapons).
    -- DualRailgun / RailgunClaw have no mode → defaults to kExoSpecialMode.Railgun.
    DualMinigun      = { chassis="mm", l={"minigun"},                    r={"minigun"} },
    DualRailgun      = { chassis="rr", l={"railgun"},                    r={"railgun"} },
    DualFlamethrower = { chassis="rr", l={"railgun", "Flamethrower"},    r={"railgun", "Flamethrower"} },
    DualGL           = { chassis="rr", l={"railgun", "Grenade"},         r={"railgun", "Grenade"} },
    DualWelder       = { chassis="rr", l={"railgun", "Welder"},          r={"railgun", "Welder"} },
    -- ONE-CLAW RULE: when exactly one claw is in the layout, it is ALWAYS on the LEFT.
    MinigunClaw      = { chassis="cm", l={"claw"},                       r={"minigun"} },
    RailgunClaw      = { chassis="cr", l={"claw"},                       r={"railgun"} },
    -- For claw+special combos the CLAW is on the LEFT arm (fires on left-click /
    -- primary) and the special weapon is on the RIGHT arm (fires on right-click /
    -- secondary).  This matches the vanilla ClawRailgun convention and lets the
    -- player swing the claw with their natural primary button while the special
    -- weapon fires independently on right-click.
    FlamethrowerClaw = { chassis="cr", l={"claw"}, r={"railgun", "Flamethrower"} },
    GLClaw           = { chassis="cr", l={"claw"}, r={"railgun", "Grenade"}      },
    WelderClaw       = { chassis="cr", l={"claw"}, r={"railgun", "Welder"}       },
}

-- ── Chassis asset tables ───────────────────────────────────────────────────────
-- GLOBAL so ExoWeaponHolderModels.lua can read them without re-defining.
kPrototypeChassisWorldModel = {
    mm = "models/marine/exosuit/exosuit_mm.model",
    cm = "models/marine/exosuit/exosuit_cm.model",
    rr = "models/marine/exosuit/exosuit_rr.model",
    cr = "models/marine/exosuit/exosuit_cr.model",
}
kPrototypeChassisWorldGraph = {
    mm = "models/marine/exosuit/exosuit_mm.animation_graph",
    cm = "models/marine/exosuit/exosuit_cm.animation_graph",
    rr = "models/marine/exosuit/exosuit_rr.animation_graph",
    cr = "models/marine/exosuit/exosuit_cr.animation_graph",
}
kPrototypeChassisViewModel = {
    mm = "models/marine/exosuit/exosuit_mm_view.model",
    cm = "models/marine/exosuit/exosuit_cm_view.model",
    rr = "models/marine/exosuit/exosuit_rr_view.model",
    cr = "models/marine/exosuit/exosuit_cr_view.model",
}
kPrototypeChassisViewGraph = {
    mm = "models/marine/exosuit/exosuit_mm_view.animation_graph",
    cm = "models/marine/exosuit/exosuit_cm_view.animation_graph",
    rr = "models/marine/exosuit/exosuit_rr_view.animation_graph",
    cr = "models/marine/exosuit/exosuit_cr_view.animation_graph",
}

-- PrecacheAsset all 16 chassis paths so they are always resident.
do
    local _allChassisAssets = {
        "models/marine/exosuit/exosuit_mm.model",
        "models/marine/exosuit/exosuit_cm.model",
        "models/marine/exosuit/exosuit_rr.model",
        "models/marine/exosuit/exosuit_cr.model",
        "models/marine/exosuit/exosuit_mm.animation_graph",
        "models/marine/exosuit/exosuit_cm.animation_graph",
        "models/marine/exosuit/exosuit_rr.animation_graph",
        "models/marine/exosuit/exosuit_cr.animation_graph",
        "models/marine/exosuit/exosuit_mm_view.model",
        "models/marine/exosuit/exosuit_cm_view.model",
        "models/marine/exosuit/exosuit_rr_view.model",
        "models/marine/exosuit/exosuit_cr_view.model",
        "models/marine/exosuit/exosuit_mm_view.animation_graph",
        "models/marine/exosuit/exosuit_cm_view.animation_graph",
        "models/marine/exosuit/exosuit_rr_view.animation_graph",
        "models/marine/exosuit/exosuit_cr_view.animation_graph",
    }
    for _, path in ipairs(_allChassisAssets) do
        PrecacheAsset(path)
    end
end

if Server then

    local kDeploy2DSound = PrecacheAsset("sound/NS2.fev/marine/heavy/deploy_2D")
    local kBoostKnockbackCheckRadius = 2.2
    local kBoostKnockbackExtents = Vector(1.1, 1.0, 1.25)
    local kBoostKnockbackCooldown = 0.6
    local kBoostKnockbackSpeed = 8

    local function GetBoostKnockbackDirection(self)
        local velocity = self:GetVelocity()
        local direction = Vector(velocity.x, 0, velocity.z)

        if direction:GetLengthSquared() < 0.01 then
            local viewDirection = self:GetViewCoords().zAxis
            direction = Vector(viewDirection.x, 0, viewDirection.z)
        end

        direction:Normalize()
        return direction
    end

    local function CanBoostKnockbackTarget(target)
        if not target or not target:GetIsAlive() then
            return false
        end

        return target:isa("Marine") or target:isa("JetpackMarine")
    end

    local function BoostKnockbackNearbyMarines(self)
        if not self.thrustersActive or self.thrusterMode == kExoThrusterMode.Vertical then
            return
        end

        local direction = GetBoostKnockbackDirection(self)
        local hitOrigin = self:GetOrigin() + Vector(0, 0.8, 0) + direction * kBoostKnockbackExtents.z
        local hitboxCoords = Coords.GetLookIn(hitOrigin, direction, Vector(0, 1, 0))
        local invHitboxCoords = hitboxCoords:GetInverse()
        local marines = GetEntitiesForTeamWithinRange("Player", self:GetTeamNumber(), hitOrigin, kBoostKnockbackCheckRadius)
        local now = Shared.GetTime()

        for i = 1, #marines do
            local marine = marines[i]
            if marine ~= self and CanBoostKnockbackTarget(marine) and (not marine.nextExoBoostKnockback or now >= marine.nextExoBoostKnockback) then
                local localSpacePosition = invHitboxCoords:TransformPoint(marine:GetEngagementPoint())
                local extents = marine:GetExtents()

                if math.abs(localSpacePosition.x) <= kBoostKnockbackExtents.x + extents.x
                        and math.abs(localSpacePosition.y) <= kBoostKnockbackExtents.y + extents.y
                        and math.abs(localSpacePosition.z) <= kBoostKnockbackExtents.z + extents.z then
                    marine.nextExoBoostKnockback = now + kBoostKnockbackCooldown
                    ApplyPushback(marine, 0.2, direction * kBoostKnockbackSpeed + Vector(0, 2.5, 0))
                end
            end
        end
    end

    local baseModifyVelocity = Exo.ModifyVelocity
    function Exo:ModifyVelocity(input, velocity, deltaTime)
        baseModifyVelocity(self, input, velocity, deltaTime)
        BoostKnockbackNearbyMarines(self)
    end

    function Exo:GetCanVampirismBeUsedOn()
        return true
    end

    -- ── Exo:InitExoModel override ─────────────────────────────────────────────
    -- Called by Exo:OnInitialized (Server) BEFORE Player.OnInitialized→InitWeapons,
    -- so self.comboChassis is set here and is readable when SetWeapons later calls
    -- GetViewModelName via the ExoWeaponHolderModels.lua override.
    -- Ordering guarantee: InitExoModel → SetModel → ... → InitWeapons → SetWeapons
    --                       → (holder.GetViewModelName reads self.comboChassis) ✓
    local baseInitExoModel = Exo.InitExoModel
    function Exo:InitExoModel()
        local entry = kPrototypeExoLayouts[self.layout]
        if entry then
            self:SetModel(
                kPrototypeChassisWorldModel[entry.chassis],
                kPrototypeChassisWorldGraph[entry.chassis]
            )
            self.hasDualGuns   = (entry.r[1] ~= "claw")
            self.comboChassis  = entry.chassis
            self.lastExoLayout = self.layout
        else
            -- Unknown layout: fall back to vanilla behaviour.
            baseInitExoModel(self)
            -- comboChassis stays nil so ExoWeaponHolderModels falls through to vanilla.
        end
    end

    -- ── Exo:InitWeapons override ──────────────────────────────────────────────
    -- Uses the unified layout table for all 14 layouts (4 vanilla + 10 prototype).
    -- Falls back to MinigunMinigun for any unrecognised layout (matches vanilla warn).
    -- Preserves the existing tail exactly: exo_login, inventoryWeight,
    -- SetActiveWeapon, StartSoundEffectForPlayer.
    function Exo:InitWeapons()

        Player.InitWeapons(self)

        local weaponHolder = self:GetWeapon(ExoWeaponHolder.kMapName)

        if not weaponHolder then
            weaponHolder = self:GiveItem(ExoWeaponHolder.kMapName, false)
        end

        -- Resolve layout entry; fall back to MinigunMinigun for unknown layouts.
        local entry = kPrototypeExoLayouts[self.layout]
        if not entry then
            Log("Warning: unrecognised exosuit layout '%s' — defaulting to MinigunMinigun", tostring(self.layout))
            entry = kPrototypeExoLayouts.MinigunMinigun
        end

        weaponHolder:SetWeapons(entry.l[1], entry.r[1])

        -- Apply weaponMode to special-arm Railgun entities where specified.
        -- entry.l[2]/entry.r[2] are mode-NAME strings ("Flamethrower"/"Welder"/
        -- "Grenade"); resolve to the kExoSpecialMode enum here at runtime (the enum
        -- exists by now — it is defined by the Railgun post-hook during Shared load).
        local function ApplyMode(weaponId, modeNameOrNil)
            local w = Shared.GetEntity(weaponId)
            if not w or not w.SetWeaponMode then return end
            if not modeNameOrNil then
                -- No special mode: explicitly reset to vanilla Railgun behaviour.
                -- This prevents any stale mode (e.g. Grenade) from a previous exo
                -- lifetime persisting into a fresh DualRailgun / RailgunClaw etc.
                w:SetWeaponMode(kExoSpecialMode.Railgun)
                return
            end
            local mode = kExoSpecialMode and kExoSpecialMode[modeNameOrNil]
            if not mode then return end
            w:SetWeaponMode(mode)
        end
        ApplyMode(weaponHolder.leftWeaponId,  entry.l[2])
        ApplyMode(weaponHolder.rightWeaponId, entry.r[2])

        -- ── Preserved tail (MUST match the original exactly) ─────────────────
        weaponHolder:TriggerEffects("exo_login")
        self.inventoryWeight = weaponHolder:GetInventoryWeight(self)
        self:SetActiveWeapon(ExoWeaponHolder.kMapName)
        StartSoundEffectForPlayer(kDeploy2DSound, self)

    end

    function Exo:GetAutoWeldArmorPerSecond(nanoArmorResearched)
        return nanoArmorResearched and kExoNanoArmorPerSecond or kExoArmorPerSecond
    end

    -- ── Task 23: Self-Destruct helper (declared BEFORE Task 22 on purpose) ────
    -- MUST be defined above Exo:AttemptToKill: Lua locals are only visible to code
    -- that textually follows their declaration.  AttemptToKill (Emergency Ejection)
    -- calls TriggerExoSelfDestruct, so if this were declared after AttemptToKill the
    -- name would resolve to a nil global there and calling it would error — aborting
    -- the eject (exo stuck at 0 HP) and never damaging nearby enemies.
    local kSelfDestructGLSound = PrecacheAsset("sound/NS2.fev/marine/common/explode")
    local kSelfDestructRange  = 5    -- AOE radius in metres
    local kSelfDestructDamage = 200

    -- Shared helper: 200 damage over a 5 m radius to all "Live" entities, applied
    -- EXACTLY like a grenade launcher grenade — LOS-checked (targets behind walls
    -- are spared) with distance falloff, and friendly-fire rules handled by DoDamage.
    -- Called from OnKill (normal death) AND AttemptToKill (Emergency Ejection path).
    --
    -- RadiusDamage asserts the doer has the "Damage" mixin.  The Exo PLAYER does NOT
    -- have it (only weapons carry DamageMixin — Weapon.lua InitMixin), so passing the
    -- exo itself was assertion-failing and no damage was ever applied.  Use the exo's
    -- active weapon (ExoWeaponHolder, a Weapon → has DamageMixin) as the doer.
    local function TriggerExoSelfDestruct(exo)
        local origin = exo:GetOrigin()
        for i = 1, 10 do
            local p = origin + Vector(
                (math.random() - 0.5) * 2.0,
                math.random() * 0.8,
                (math.random() - 0.5) * 2.0
            )
            StartSoundEffectAtOrigin(kSelfDestructGLSound, p)
        end

        -- Pick a doer that actually has the Damage mixin.  ExoWeaponHolder.kMapName
        -- is the exo's own always-present built-in weapon (added in Exo:InitWeapons
        -- and never dropped/removed for the exo's lifetime) — a far more direct and
        -- reliable source than GetActiveWeapon(), which reads a separate networked
        -- "currently selected" field that in principle could point elsewhere.
        local doer = exo.GetWeapon and exo:GetWeapon(ExoWeaponHolder.kMapName)
        if not (doer and HasMixin(doer, "Damage")) then
            doer = exo.GetActiveWeapon and exo:GetActiveWeapon()
        end
        if not (doer and HasMixin(doer, "Damage")) then
            doer = nil
            for i = 0, exo:GetNumChildren() - 1 do
                local child = exo:GetChildAtIndex(i)
                if child and HasMixin(child, "Damage") then
                    doer = child
                    break
                end
            end
        end

        -- Weapon (Damage mixin) used purely for kill attribution / killfeed icon;
        -- fall back to the exo itself if somehow none was found.
        local damageDoer = doer or exo

        -- The blast is ANTI-ENEMY ONLY. Marine-team entities are NEVER affected -
        -- this covers the ejected Emergency-Ejection pilot, teammates and marine
        -- structures - guaranteed by BOTH an explicit same-team skip below AND
        -- GetDamageByType/CanEntityDoDamageTo's own friendly-fire refusal, so it
        -- holds regardless of the server's friendly-fire setting.
        local exoTeam = exo.GetTeamNumber and exo:GetTeamNumber()

        -- Deal EXACTLY kSelfDestructDamage (200) of kDamageType.Normal, LOS-checked
        -- with linear distance falloff (same shape as a GL grenade). We drive the
        -- armour/health split ourselves (GetDamageByType -> TakeDamage) so the type
        -- is guaranteed Normal instead of inheriting whatever the doer weapon's own
        -- GetDamageType() returns (Railgun / Flame / Structural / ...).
        local ents = GetEntitiesWithMixinWithinRange("Live", origin, kSelfDestructRange)
        local radiusSquared = kSelfDestructRange * kSelfDestructRange
        for _, target in ipairs(ents) do
            if target ~= exo
               and not (exoTeam and target.GetTeamNumber and target:GetTeamNumber() == exoTeam) then

                local targetOrigin = GetTargetOrigin(target)
                local distSq = (targetOrigin - origin):GetLengthSquared()
                if distSq <= radiusSquared and not GetWallBetween(origin, targetOrigin, target) then
                    local frac = Clamp(distSq / radiusSquared, 0, 1)
                    local dmg  = kSelfDestructDamage * (1 - frac)
                    if dmg > 0 then
                        local dir = GetNormalizedVector(targetOrigin - origin)
                        local applied, armorUsed, healthUsed, overshield =
                            GetDamageByType(target, exo, damageDoer, dmg, kDamageType.Normal, targetOrigin, damageDoer)
                        applied    = applied    or 0
                        overshield = overshield or 0
                        if applied + overshield > 0 then
                            target:TakeDamage(applied + overshield, exo, damageDoer, targetOrigin, dir,
                                              armorUsed or 0, healthUsed or 0, kDamageType.Normal, nil)
                        end
                    end
                end
            end
        end
    end

    -- ── Task 22: Emergency Ejection ───────────────────────────────────────────
    -- When a lethal hit would kill the Exo and the upgrade is present, we
    -- intercept via AttemptToKill (called by LiveMixin:TakeDamage before Kill).
    -- We perform a FORCED eject (bypassing GetCanEject) and return false so
    -- the Kill path is skipped — the entity is already replaced by Replace().
    -- Without the upgrade, AttemptToKill is not defined here so LiveMixin falls
    -- through to Kill as normal (nil or no-method = vanilla behaviour).
    function Exo:AttemptToKill(damage, attacker, doer, point)

        if not self:GetHasPrototypeUpgrade(kTechId.PrototypeEmergencyEjection) then
            -- No upgrade: let vanilla kill proceed.
            return true
        end

        -- Self-Destruct fires BEFORE Replace() — self is still valid here.
        -- (AttemptToKill returns false to skip Kill/OnKill, so OnKill never runs;
        -- we must trigger the blast manually before the entity is replaced.)
        if self:GetHasPrototypeUpgrade(kTechId.PrototypeSelfDestruct) then
            TriggerExoSelfDestruct(self)
        end

        -- Upgrade present: forced eject.  Mirror Exo:PerformEject exactly
        -- (NS2-Copy/ns2/lua/Exo.lua ~763), but do NOT create an Exosuit pickup —
        -- the suit is destroyed (player destroyed the exo to survive).
        -- The Replace() call destroys this entity and creates a Marine.
        local reuseWeapons = self.storedWeaponsIds ~= nil

        local marine = self:Replace(
            self.prevPlayerMapName or Marine.kMapName,
            self:GetTeamNumber(),
            false,
            self:GetOrigin() + Vector(0, 0.2, 0),
            { preventWeapons = reuseWeapons }
        )

        if marine then
            -- Give the marine a small amount of health so they survive ejection.
            -- (Tunable: currently 30 HP — enough to live but weakened.)
            marine:SetHealth(math.min(30, marine:GetMaxHealth()))
            marine:SetMaxArmor(self.prevPlayerMaxArmor or kMarineArmor)
            marine:SetArmor(self.prevPlayerArmor or 0)

            marine.onGround = false
            local initialVelocity = self:GetViewCoords().zAxis
            initialVelocity:Scale(4)
            initialVelocity.y = math.max(0, initialVelocity.y) + 9
            marine:SetVelocity(initialVelocity)

            if reuseWeapons then
                for _, weaponId in ipairs(self.storedWeaponsIds) do
                    local weapon = Shared.GetEntity(weaponId)
                    if weapon then
                        marine:AddWeapon(weapon)
                    end
                end
            end

            marine:SetHUDSlotActive(1)

            if marine:isa("JetpackMarine") then
                marine:SetFuel(0.25)
            end
        end

        -- Return false: do NOT call Kill(); the entity was already replaced above.
        return false

    end

    -- ── Task 23: Self-Destruct on normal death ───────────────────────────────
    -- (TriggerExoSelfDestruct + its constants are declared above, before Task 22.)
    local baseExoOnKill = Exo.OnKill
    function Exo:OnKill(attacker, doer, point, direction)
        if self:GetHasPrototypeUpgrade(kTechId.PrototypeSelfDestruct) then
            TriggerExoSelfDestruct(self)
        end
        baseExoOnKill(self, attacker, doer, point, direction)
    end

    -- ── Task 24: Resupply (friendly marine presses E → ammo, 15 s cooldown) ──
    -- Exo already has UsableMixin (via ScriptActor.OnCreate) and GetCanBeUsed
    -- (from Player, returns false by default).  We override both here.

    local baseExoGetCanBeUsed = Exo.GetCanBeUsed
    function Exo:GetCanBeUsed(player, useSuccessTable)

        if self:GetHasPrototypeUpgrade(kTechId.PrototypeResupply)
                and player ~= self
                and (player:isa("Marine") or player:isa("JetpackMarine"))
                and player:GetTeamNumber() == self:GetTeamNumber()
                and Shared.GetTime() >= (self.timeNextResupply or 0)
                and (self.resupplyChargesRemaining or 0) > 0 then
            useSuccessTable.useSuccess = true
            return
        end

        -- Fall through to base (returns false by default for Player).
        if baseExoGetCanBeUsed then
            baseExoGetCanBeUsed(self, player, useSuccessTable)
        else
            useSuccessTable.useSuccess = false
        end

    end

    function Exo:OnUse(player, elapsedTime, useSuccessTable)

        if not self:GetHasPrototypeUpgrade(kTechId.PrototypeResupply) then
            return
        end
        if player == self then return end
        if not (player:isa("Marine") or player:isa("JetpackMarine")) then return end
        if player:GetTeamNumber() ~= self:GetTeamNumber() then return end
        if Shared.GetTime() < (self.timeNextResupply or 0) then return end
        if (self.resupplyChargesRemaining or 0) <= 0 then return end

        -- Give ammo to all clip weapons (mirrors AmmoPack:OnTouch,
        -- NS2-Copy/ns2/lua/AmmoPack.lua ~45).
        local gaveSomething = false
        for i = 0, player:GetNumChildren() - 1 do
            local child = player:GetChildAtIndex(i)
            if child:isa("ClipWeapon") then
                if child:GiveAmmo(AmmoPack.kNumClips, false) then
                    gaveSomething = true
                end
            end
        end

        if gaveSomething then
            self.timeNextResupply = Shared.GetTime() + 15
            -- Consume one of the 10 charges (like using up one ammopack).
            self.resupplyChargesRemaining = math.max(0, (self.resupplyChargesRemaining or 0) - 1)
            useSuccessTable.useSuccess = true
        end

    end

    -- ── Task 21: Lifeform Scanner — server scan method ────────────────────────
    local kScanRange    = 7.5
    local kScanInterval = 5.0   -- scan ping cadence (seconds)
    local kScanSound    = PrecacheAsset("sound/NS2.fev/marine/commander/scan_com")

    function Exo:UpdateLifeformScan()
        if not self:GetHasPrototypeUpgrade(kTechId.PrototypeLifeformScanner) then return end
        if Shared.GetTime() < (self.timeNextLifeformScan or 0) then return end
        self.timeNextLifeformScan = Shared.GetTime() + kScanInterval

        local counts = { Skulk=0, Gorge=0, Prowler=0, Lerk=0, Fade=0, Vokex=0, Onos=0 }
        local aliens = GetEntitiesForTeamWithinRange("Alien", GetEnemyTeamNumber(self:GetTeamNumber()), self:GetOrigin(), kScanRange)
        for _, a in ipairs(aliens) do
            local cloaked = HasMixin(a, "Cloakable") and a:GetCloakFraction() > 0
            if a:GetIsAlive() and not cloaked then
                local cn = a:GetClassName()
                if counts[cn] ~= nil then counts[cn] = counts[cn] + 1 end
            end
        end

        self.exoScanSkulk   = counts.Skulk
        self.exoScanGorge   = counts.Gorge
        self.exoScanProwler = counts.Prowler
        self.exoScanLerk    = counts.Lerk
        self.exoScanFade    = counts.Fade
        self.exoScanVokex   = counts.Vokex
        self.exoScanOnos    = counts.Onos
        self.exoHasScanned  = true

        -- Play the scan ping at the exo's position so ALL nearby entities can
        -- hear it (a 3D world sound), not just the owning player.
        StartSoundEffectAtOrigin(kScanSound, self:GetOrigin())
    end

    -- ── Skulk Parasite Infection continuation while piloting an Exo ──────────
    -- An Exo records no NEW Parasite hits itself (ParasiteMixin.lua's hook only
    -- fires for self:isa("Marine")/"JetpackMarine"), but it MUST still evaluate
    -- the hit timestamps carried over from the marine at entry: otherwise a
    -- marine who entered the exo with a 3/3 infection that hadn't yet been
    -- realized into the "fully infected" state would have that completion
    -- silently dropped, and a partial (1-2/3) infection would sit frozen forever
    -- instead of aging out. Once fully infected, ticks decrement
    -- infectionPilotHealth (carried over in CopyPlayerDataFrom above) instead of
    -- the Exo's own health - the Exo's real HP/armor is never touched by the DoT.
    local kInfectionDamageAmount       = 5
    local kInfectionDoTSeconds         = 5
    local kInfectionDamageTickInterval = kInfectionDoTSeconds / 2
    local kInfectionHitWindowSeconds   = 10   -- matches Marine.lua: a hit is forgotten after this
    local kInfectionHurtSound          = PrecacheAsset("sound/NS2.fev/marine/common/wound")
    local kInfectionAppliedSound       = PrecacheAsset("sound/NS2.fev/alien/skulk/taunt")  -- plays once on reaching 3/3

    local function TriggerInfectionExoDeath(exo)

        if not exo:GetIsAlive() then return end

        -- Mirrors vanilla Exo:PerformEject (NS2-Copy/ns2/lua/Exo.lua:763-810) -
        -- leaves an Exosuit behind with the exact same layout/loadout, exactly
        -- like a normal voluntary eject. Deliberately does NOT check
        -- GetCanEject() (this is an involuntary death, not a player choice),
        -- and - unlike PerformEject - kills the restored Marine immediately
        -- afterward instead of leaving them alive, so the Infection kill plays
        -- out as a completely normal Marine death (weapon drop, killfeed,
        -- respawn) credited to whoever the Infection DoT already credits.
        local exosuit = CreateEntity(Exosuit.kMapName, exo:GetOrigin(), exo:GetTeamNumber())
        exosuit:SetLayout(exo.layout)
        exosuit:SetCoords(exo:GetCoords())
        exosuit:SetMaxArmor(exo:GetMaxArmor())
        exosuit:SetArmor(exo:GetArmor())
        exosuit:SetExoVariant(exo:GetExoVariant())
        exosuit:SetFlashlightOn(exo:GetFlashlightOn())
        exosuit:TransferParasite(exo)

        local combatTimeEnd = math.max(exo:GetTimeLastDamageDealt(), exo:GetTimeLastDamageTaken()) + kCombatTimeOut
        local cooldownEnd = math.max(exo.timeNextWeld or 0, combatTimeEnd)
        local now = Shared.GetTime()
        exosuit.timeNextWeld = now + math.max(0, cooldownEnd - now)

        local reuseWeapons = exo.storedWeaponsIds ~= nil

        local marine = exo:Replace(exo.prevPlayerMapName or Marine.kMapName, exo:GetTeamNumber(), false,
            exo:GetOrigin() + Vector(0, 0.2, 0), { preventWeapons = reuseWeapons })

        if marine then

            marine:SetHealth(exo.prevPlayerHealth or kMarineHealth)
            marine:SetMaxArmor(exo.prevPlayerMaxArmor or kMarineArmor)
            marine:SetArmor(exo.prevPlayerArmor or kMarineArmor)

            exosuit:SetOwner(marine)

            if reuseWeapons then
                for _, weaponId in ipairs(exo.storedWeaponsIds) do
                    local weapon = Shared.GetEntity(weaponId)
                    if weapon then
                        marine:AddWeapon(weapon)
                    end
                end
            end

            local attacker
            local doer
            if exo.infectionCreditedIsCommander then
                local aliensTeam = GetGamerules() and GetGamerules():GetTeam(kAlienTeamType)
                attacker = aliensTeam and aliensTeam:GetCommander()
            else
                attacker = Shared.GetEntity(exo.infectionCreditedAttackerId)
                -- Real Parasite weapon as doer so the killfeed shows the
                -- correct killer + Parasite icon (doer:GetDeathIconIndex()
                -- needs a real instance, there is no icon-by-damage-type
                -- shortcut). Safe here without the suppressInfectionReinfect
                -- guard Marine.lua's DeductHealth calls need - LiveMixin:Kill
                -- sets health/armor directly and never calls TakeDamage/
                -- OnTakeDamage, so it cannot re-trigger ParasiteMixin's hook.
                if attacker and attacker.GetWeapon then
                    doer = attacker:GetWeapon("parasite")
                end
            end

            -- Normal death pipeline - weapon-drop, killfeed, and respawn all
            -- follow exactly as they would for any other Marine death.
            marine:Kill(attacker, doer, marine:GetOrigin(), Vector(0, 0, 0))

        end

    end

    -- Mirrors Marine:OnEntityChange's same safety net for infectionCreditedAttackerId.
    local baseExoOnEntityChange = Exo.OnEntityChange
    function Exo:OnEntityChange(oldId, newId)
        if baseExoOnEntityChange then
            baseExoOnEntityChange(self, oldId, newId)
        end
        if oldId == self.infectionCreditedAttackerId then
            self.infectionCreditedAttackerId = newId or Entity.invalidId
        end
    end

    -- ── Task 21: wrap OnProcessMove to call the scan each server frame ────────
    -- No existing mod wrapper exists; save & wrap the vanilla function.
    -- This wrapper is defined inside `if Server then` so it is server-only.
    local baseExoOnProcessMove = Exo.OnProcessMove
    function Exo:OnProcessMove(input)
        baseExoOnProcessMove(self, input)
        self:UpdateLifeformScan()

        if not self.infectionWasFullyInfected then

            -- Build-up phase: evaluate ONLY the timestamps carried over from the
            -- marine at exo entry (no new hits are ever recorded on an exo). Prune
            -- to the rolling window so partials age out, and realise a pending 3/3
            -- into the fully-infected DoT if it survived the transition.
            local timestamps = self.infectionHitTimestamps
            if timestamps and #timestamps > 0 then

                local now  = Shared.GetTime()
                local kept = {}
                for _, t in ipairs(timestamps) do
                    if now - t < kInfectionHitWindowSeconds then
                        table.insert(kept, t)
                    end
                end
                self.infectionHitTimestamps = kept
                self.infectionHitCount = #kept

                if self.infectionHitCount >= 3 then
                    self.infectionWasFullyInfected = true
                    self.infectionDamageTicksApplied = 0
                    self.infectionLastHitTime = now
                    StartSoundEffectAtOrigin(kInfectionAppliedSound, self:GetOrigin())
                end

            end

        else

            local elapsed = Shared.GetTime() - self.infectionLastHitTime
            local ticksDue = math.min(3, math.floor(elapsed / kInfectionDamageTickInterval) + 1)

            if ticksDue > (self.infectionDamageTicksApplied or 0) and self:GetIsAlive() then

                local ticksToApply = ticksDue - self.infectionDamageTicksApplied
                self.infectionDamageTicksApplied = ticksDue
                self.infectionHitCount = math.max(0, 3 - ticksDue)

                for _ = 1, ticksToApply do
                    self.infectionPilotHealth = (self.infectionPilotHealth or 0) - kInfectionDamageAmount
                    StartSoundEffectForPlayer(kInfectionHurtSound, self)
                end

                if self.infectionPilotHealth <= 0 then
                    TriggerInfectionExoDeath(self)
                    return
                end

            end

            if self.infectionDamageTicksApplied >= 3 then
                self.infectionWasFullyInfected = false
                self.infectionHitCount = 0
                self.infectionDamageTicksApplied = 0
                self.infectionCreditedIsCommander = false
                self.infectionCreditedAttackerId = Entity.invalidId
            end

        end
    end

    -- ── Preserve the previous player's prototype upgrades across the exo ───────
    -- When a marine / jetpack marine becomes this exo, remember its prototype
    -- upgrade bits (e.g. the Jetpack's Boost) so they can be restored when the
    -- player ejects back out (see Marine/JetpackMarine:CopyPlayerDataFrom).
    -- Also remember whether the player had a Jetpack and/or Cannon so the HUD
    -- panels can remain visible while the player is piloting the exo.
    local baseExoCopyPlayerDataFrom = Exo.CopyPlayerDataFrom
    function Exo:CopyPlayerDataFrom(player)
        baseExoCopyPlayerDataFrom(self, player)
        if player then
            -- Skulk Parasite Infection: a Marine/JetpackMarine entering an Exo
            -- (buying one) must not have their Infection simply vanish - carry
            -- the tracking fields onto the Exo, plus a SEPARATE snapshot of
            -- their real health at the moment of entry (infectionPilotHealth).
            -- The Exo's own health/armor pool is completely untouched by this -
            -- Exo:OnProcessMove below decrements infectionPilotHealth only,
            -- never the Exo's real HP, and forces a proper death (see
            -- TriggerInfectionExoDeath) if it reaches 0, exactly mirroring
            -- what would have happened had the player stayed a Marine.
            if player.infectionHitCount ~= nil then
                self.infectionHitCount = player.infectionHitCount
                self.infectionWasFullyInfected = player.infectionWasFullyInfected
                self.infectionLastHitTime = player.infectionLastHitTime
                self.infectionDamageTicksApplied = player.infectionDamageTicksApplied
                self.infectionCreditedIsCommander = player.infectionCreditedIsCommander
                self.infectionCreditedAttackerId = player.infectionCreditedAttackerId
                self.infectionPilotHealth = player:GetHealth()
                -- Deep-copy the hit timestamps too (mirrors JetpackMarine's
                -- CopyPlayerDataFrom). The exo build-up phase in OnProcessMove
                -- reads these to realise a pending 3/3 that had not yet flipped
                -- infectionWasFullyInfected at the moment of entry, and to age out
                -- partials - without carrying them, that phase would see an empty
                -- list and never fire.
                self.infectionHitTimestamps = {}
                if player.infectionHitTimestamps then
                    for i, t in ipairs(player.infectionHitTimestamps) do
                        self.infectionHitTimestamps[i] = t
                    end
                end
            end
            if player:isa("Exo") then
                -- Carry the remembered bits forward on an exo→exo copy.
                self.prevPrototypeUpgradeBits = player.prevPrototypeUpgradeBits
                self.prevHadJetpack        = player.prevHadJetpack
                self.prevHadCannon         = player.prevHadCannon
                self.prevCannonUpgradeBits = player.prevCannonUpgradeBits
            else
                if player.prototypeUpgradeBits ~= nil then
                    self.prevPrototypeUpgradeBits = player.prototypeUpgradeBits
                end
                self.prevHadJetpack = player:isa("JetpackMarine")
                -- Search all weapons for a Cannon rather than relying on GetWeapon("cannon")
                -- which may return nil if the weapon list ordering varies.
                -- Match the same detection logic the HUD uses (GetTechId == kTechId.Cannon)
                -- with GetMapName == "cannon" as an additional fallback.
                local cannon = nil
                if player.GetHUDOrderedWeaponList then
                    for _, w in ipairs(player:GetHUDOrderedWeaponList()) do
                        if (w.GetTechId  and w:GetTechId()  == kTechId.Cannon)
                        or (w.GetMapName and w:GetMapName() == "cannon") then
                            cannon = w
                            break
                        end
                    end
                end
                if not cannon then
                    cannon = player.GetWeapon and player:GetWeapon("cannon")
                end
                self.prevHadCannon  = cannon ~= nil
                self.prevCannonUpgradeBits = (cannon and cannon.prototypeUpgradeBits) or 0
            end
        end
    end

    -- ── Persist prototype upgrades across eject → Exosuit → re-enter ───────────
    -- Vanilla Exo:PerformEject creates the dropped Exosuit but never carries the
    -- exo's prototype upgrades (Lifeform Scanner, Resupply, Boost, etc.) or the
    -- Resupply charge count.  Stash both into globals that Exosuit:SetLayout
    -- (called synchronously inside PerformEject right after the Exosuit is
    -- created) reads and stores on the Exosuit.  Exosuit:OnUseDeferred then
    -- restores them onto the new exo, so the remaining ammopack count stays
    -- constant across the eject/re-enter cycle instead of resetting to 10.
    local baseExoPerformEject = Exo.PerformEject
    function Exo:PerformEject()
        _G.gEjectingExoPrototypeBits    = self.prototypeUpgradeBits or 0
        _G.gEjectingExoResupplyCharges  = self.resupplyChargesRemaining or kResupplyMaxCharges
        baseExoPerformEject(self)
        _G.gEjectingExoPrototypeBits    = nil
        _G.gEjectingExoResupplyCharges  = nil
    end

end

function Exo:GetExoVariantOverride(variant)
    local entry   = kPrototypeExoLayouts[self.layout]
    local hasClaw = entry and (entry.l[1] == "claw" or entry.r[1] == "claw")

    if GetHasTech(self, kTechId.MilitaryProtocol) then
        -- Claw weapon models have no Chroma-variant material; force normal skin
        -- to prevent GetPrecachedCosmeticMaterial assertion failure.
        return hasClaw and kExoVariants.normal or kExoVariants.chroma
    end

    -- BUG FIX: the claw guard above only fired when Military Protocol was the
    -- one FORCING Chroma. A player who manually selected the Chroma skin
    -- (independent of Military Protocol) previously fell straight through to
    -- "return variant" below with no claw check at all - piloting a claw
    -- layout with a manually-picked Chroma skin would still hit the same
    -- missing-cosmetic-material failure this function exists to prevent.
    -- Apply the same guard here regardless of WHY Chroma was requested.
    if hasClaw and variant == kExoVariants.chroma then
        return kExoVariants.normal
    end

    return variant
end


function Exo:GetArmorAmount(armorLevels)

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

    -- Task 20: Armour Plating — +100 AP when prototype upgrade is active.
    -- Applied to both the MP branch and the normal branch (mirrors JetpackMarine +25 pattern).
    local armourPlatingBonus = self:GetHasPrototypeUpgrade(kTechId.PrototypeExoArmour) and 100 or 0

    local hasMP = GetHasTech(self,kTechId.MilitaryProtocol)
    return hasMP and (kExosuitMPArmor + armorLevels * kExosuitMPArmorPerUpgradeLevel + armourPlatingBonus)
                 or (kExosuitArmor + armorLevels * kExosuitArmorPerUpgradeLevel + armourPlatingBonus)

end

-- Task 20: Extra Fuel — override GetFuel to give +30% thruster duration.
-- Reproduces vanilla math (NS2-Copy/ns2/lua/Exo.lua ~1370-1386) exactly,
-- except when PrototypeExoExtraFuel is active the depletion slope is divided by 1.3
-- (the fuel lasts 30% longer).  The replenish slope is unchanged.
-- Non-upgraded result is bit-for-bit identical to vanilla.
function Exo:GetFuel()

    local slope
    local changeCooldownPeriod
    if self.thrustersActive then
        local divisor = self:GetHasPrototypeUpgrade(kTechId.PrototypeExoExtraFuel) and 1.3 or 1.0
        slope = -1.0 / (kThrusterDuration * divisor)
        changeCooldownPeriod = 0
    else
        slope = 1.0 / kThrustersCooldownTime
        changeCooldownPeriod = kThrusterRefuelCooldownTime
    end

    local deltaT = math.max(0, Shared.GetTime() - self.timeFuelChanged - changeCooldownPeriod)

    return (Clamp(slope * deltaT + self.fuelAtChange, 0, 1))

end


function Exo:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint) -- dud
    local reduction = kExoDamageReduction[doer:GetClassName()]
    if reduction then
        damageTable.damage = damageTable.damage * reduction
        return
    end
end

-- Reconstructed networkVars for Exo (verbatim from vanilla Exo.lua lines 44-60)
-- plus all AddMixinNetworkVars lines (vanilla lines 135-153)
-- plus PrototypeUpgradesMixin netvar. Re-linked with true (4th arg).
local networkVars =
{
    flashlightOn = "boolean",
    flashlightLastFrame = "private boolean",
    idleSound2DId = "private entityid",
    thrustersActive = "compensated boolean",
    timeThrustersEnded = "private compensated time",
    timeThrustersStarted = "private compensated time",
    weaponUpgradeLevel = "integer (0 to 3)",
    inventoryWeight = "float",
    thrusterMode = "enum kExoThrusterMode",
    hasDualGuns = "private boolean",
    creationTime = "private time",
    ejecting = "compensated boolean",
    timeFuelChanged = "private time",
    fuelAtChange = "private float (0 to 1 by 0.01)",

    -- Skulk Parasite Infection carried over from the Marine/JetpackMarine that
    -- entered this Exo (see CopyPlayerDataFrom) - same fields/types as
    -- Marine.lua/JetpackMarine.lua so GUIExoHUD.lua can reuse the identical
    -- client-side animation math GUIMarineHUD.lua already uses.
    infectionHitCount = "private integer (0 to 3)",
    infectionWasFullyInfected = "private boolean",
    infectionLastHitTime = "private time",
}

AddMixinNetworkVars(BaseMoveMixin, networkVars)
AddMixinNetworkVars(GroundMoveMixin, networkVars)
AddMixinNetworkVars(CameraHolderMixin, networkVars)
AddMixinNetworkVars(LOSMixin, networkVars)
AddMixinNetworkVars(CombatMixin, networkVars)
AddMixinNetworkVars(SelectableMixin, networkVars)
AddMixinNetworkVars(OrdersMixin, networkVars)
AddMixinNetworkVars(CorrodeMixin, networkVars)
AddMixinNetworkVars(TunnelUserMixin, networkVars)
AddMixinNetworkVars(NanoShieldMixin, networkVars)
AddMixinNetworkVars(CatPackMixin, networkVars)
AddMixinNetworkVars(ParasiteMixin, networkVars)
AddMixinNetworkVars(ScoringMixin, networkVars)
AddMixinNetworkVars(WebableMixin, networkVars)
AddMixinNetworkVars(MarineVariantMixin, networkVars)
AddMixinNetworkVars(ExoVariantMixin, networkVars)
AddMixinNetworkVars(AutoWeldMixin, networkVars)
AddMixinNetworkVars(GUINotificationMixin, networkVars)
AddMixinNetworkVars(PlayerStatusMixin, networkVars)

-- ── Jetpack/Cannon panel persistence — 3 private netvars ─────────────────────
-- Sent only to the owning client so GUIMarineHUD can show the panels while
-- the player is piloting the exo (the items are stored and returned on eject).
networkVars.prevHadJetpack           = "private boolean"
networkVars.prevHadCannon            = "private boolean"
networkVars.prevCannonUpgradeBits    = "private integer"
networkVars.prevPrototypeUpgradeBits = "private integer"
networkVars.exoHasScanned         = "private boolean"

-- ── Task 21: Lifeform Scanner — 7 private scan-count netvars ─────────────────
-- "private" = sent only to the owning client; the HUD reads these on the client.
-- Counts are clamped to 0-63 (6 bits); in practice a 7.5u radius holds far fewer.
local kScanNetVarFields =
{
    exoScanSkulk   = "private integer (0 to 63)",
    exoScanGorge   = "private integer (0 to 63)",
    exoScanProwler = "private integer (0 to 63)",
    exoScanLerk    = "private integer (0 to 63)",
    exoScanFade    = "private integer (0 to 63)",
    exoScanVokex   = "private integer (0 to 63)",
    exoScanOnos    = "private integer (0 to 63)",
}
for k, v in pairs(kScanNetVarFields) do
    networkVars[k] = v
end

-- Resupply cooldown: public `time` so nearby marine clients can read it.
-- "time" type is sent to ALL clients; nearby marines need it to show the HUD prompt.
networkVars.timeNextResupply = "time"
-- Resupply is a limited-use consumable: 10 charges (like 10 ammopacks) per exo
-- lifetime.  Public so nearby marine clients can show "X/10" on the HUD prompt.
kResupplyMaxCharges = 10
networkVars.resupplyChargesRemaining = "integer (0 to 10)"

AddMixinNetworkVars(PrototypeUpgradesMixin, networkVars)

Shared.LinkClassToMap("Exo", Exo.kMapName, networkVars, true)

local baseExoOnCreate = Exo.OnCreate
function Exo:OnCreate()
    baseExoOnCreate(self)
    InitMixin(self, PrototypeUpgradesMixin)
    -- The Grenade exo-arm mode fires a predicted Grenade projectile via
    -- player:CreatePredictedProjectile (ExoSpecialWeapon.lua FireGrenade).  That
    -- method comes from PredictedProjectileShooterMixin, which the Marine has but
    -- the Exo does NOT — so add it here.  The mixin has no networkVars (verified),
    -- so InitMixin alone is sufficient; no re-link required.  Marine and Gorge use
    -- the same pattern alongside their own OnProcessMove, so there is no conflict.
    InitMixin(self, PredictedProjectileShooterMixin)
    -- Init panel-persistence netvars (required before first network sync).
    self.prevHadJetpack           = false
    self.prevHadCannon            = false
    self.prevCannonUpgradeBits    = 0
    self.prevPrototypeUpgradeBits = 0
    self.exoHasScanned         = false
    -- Init scan netvars to 0 (required before first network sync).
    self.exoScanSkulk   = 0
    self.exoScanGorge   = 0
    self.exoScanProwler = 0
    self.exoScanLerk    = 0
    self.exoScanFade    = 0
    self.exoScanVokex    = 0
    self.exoScanOnos     = 0
    self.timeNextResupply = 0
    -- Fresh exo: full 10 Resupply charges.  Overwritten in OnUseDeferred/OnCreate
    -- callers below if this exo was re-entered from a dropped Exosuit that still
    -- had charges remaining (see Exosuit.lua storedResupplyCharges).
    self.resupplyChargesRemaining = kResupplyMaxCharges
end

-- Override GetUseText so the vanilla HUD can show resupply status when a Marine
-- aims at this Exo. (The picture + interaction key are drawn by GUIMarineHUD.)
function Exo:GetUseText(player)
    if not self:GetHasPrototypeUpgrade(kTechId.PrototypeResupply) then
        return nil
    end
    local charges = self.resupplyChargesRemaining or 0
    if charges <= 0 then
        return string.format("RESUPPLY  —  Empty (0/%d)", kResupplyMaxCharges)
    end
    local remaining = (self.timeNextResupply or 0) - Shared.GetTime()
    if remaining <= 0 then
        return string.format("RESUPPLY  —  Ready (%d/%d)", charges, kResupplyMaxCharges)
    else
        return string.format("RESUPPLY  —  Cooldown: %.0fs (%d/%d)", math.ceil(remaining), charges, kResupplyMaxCharges)
    end
end
