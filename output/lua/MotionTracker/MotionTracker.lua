-- ======================================================================
-- Motion Tracker — alien detection device (Weapons-Level gated).
--
-- Fires no projectile and deals no damage. While the primary attack is
-- HELD it scans a forward cone from the player's eye and reports alien
-- entities on the in-weapon screen. Capability scales with Marine
-- Weapons Level (0-3). Uses a "charge" in place of ammo: drains while
-- held, no spare ammo, refilled only at an armory.
-- ======================================================================

Script.Load("lua/Weapons/Marine/ClipWeapon.lua")
Script.Load("lua/PickupableWeaponMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")
Script.Load("lua/PointGiverMixin.lua")

class 'MotionTracker' (ClipWeapon)

MotionTracker.kMapName = "MotionTracker"
MotionTracker.kModelName = PrecacheAsset("models/marine/motion_tracker/motion_tracker_world.model")
local kViewModelName = PrecacheAsset("models/marine/motion_tracker/motion_tracker_view.model")
local kAnimationGraph = PrecacheAsset("models/marine/motion_tracker/motion_tracker_view.animation_graph")

-- === Sounds (sound/motion_tracker.fev) ===
-- All three play through the normal SFX path (StartSoundEffect* / SoundEffect),
-- so each client's in-game sound-volume slider already scales them; the volume
-- values below are an additional fixed multiplier on top of the slider.
local kActivateSound = PrecacheAsset("sound/motion_tracker.fev/motion_tracker/activate") -- one-shot on equip
local kScanSound     = PrecacheAsset("sound/motion_tracker.fev/motion_tracker/scan")     -- LOOPING while primary held (author the FMOD event as a loop)
local kDetectSound   = PrecacheAsset("sound/motion_tracker.fev/motion_tracker/detect")   -- one-shot beep, repeated on a distance-based interval

local kActivateVolume = 0.675   -- 56% of original 1.2  (0.9 × 0.75)
local kScanVolume     = 0.304   -- 56% of original 0.54 (0.405 × 0.75)
local kDetectVolume   = 0.304   -- 56% of original 0.54 (0.405 × 0.75)

-- Detect-beep cadence: the beep gets FASTER (shorter interval) the CLOSER the
-- nearest target is (classic proximity beeper).
local kBeepIntervalNear = 0.15   -- seconds between beeps at point-blank (0 m) -> fast
local kBeepIntervalFar  = 0.8    -- seconds between beeps at max range -> slow

-- === Tunable detection parameters (indexed by Weapons Level 0-3) ===
-- Maximum detection range in metres (3D). Kept <= kMaxRelevancyDistance (40) so
-- behind-wall and cloaked enemies are guaranteed present on the client.
-- WL0 = 5 m start, WL3 = 15.5 m max (still <= kMaxRelevancyDistance 40).
local kMaxRange       = { [0] = 5.0,          [1] = 6.75,          [2] = 10.125,        [3] = 15.5 }
-- Detection FOV HALF-angle. Detection is yaw-only: pitch is ignored, matching
-- the 2D wedge and green line on the scanner screen. Any valid alien inside the
-- horizontal wedge and max range can be detected regardless of aim pitch.
local kHalfAngle      = { [0] = math.rad(18), [1] = math.rad(20), [2] = math.rad(22),  [3] = math.rad(24) }
-- Wall vision: false = clear line-of-sight required; true = sees through walls.
local kWallVision     = { [0] = false,        [1] = true,          [2] = true,          [3] = true }
-- Cloak: detect a candidate while its cloakFraction is STRICTLY BELOW this.
--   WL0/1 only see fully uncloaked (fraction 0); WL2 pierces partial cloak
--   (< 0.5); WL3 ignores cloak entirely (math.huge).
local kCloakThreshold = { [0] = 0.0001,       [1] = 0.0001,        [2] = 0.5,           [3] = math.huge }

-- Only these alien lifeforms are detected — never structures, tunnels, eggs, etc.
local kDetectableClasses =
{
    Skulk   = true,
    Gorge   = true,
    Prowler = true,
    Lerk    = true,
    Fade    = true,
    Vokex   = true,
    Onos    = true,
}

-- Max blips encoded for the screen.
local kMaxBlips = 32

-- === Charge model (tunable) ===
local kMaxCharge        = 100   -- full charge (mirrors kMotionTrackerClipSize)
local kDrainRate        = 2.0   -- charge consumed per second while tracking
local kArmoryRefillStep = 10    -- charge added per armory resupply tick

local networkVars =
{
    canPrimaryAttack  = "boolean",
    tracking          = "boolean",
    charge            = "float",
    toggleTracking    = "boolean",
}

AddMixinNetworkVars(LiveMixin, networkVars)

-- ----------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------

function MotionTracker:OnCreate()

    ClipWeapon.OnCreate(self)

    InitMixin(self, PickupableWeaponMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, PointGiverMixin)
    if Client then
        InitMixin(self, ClientWeaponEffectsMixin)
        -- Looping "scan" sound as a client-controllable instance (Railgun pattern).
        -- Client.CreateSoundEffect gives a real handle we can Start/Stop/SetVolume on,
        -- so it stops immediately on release and its volume follows the sound slider.
        self.scanSoundInstance = Client.CreateSoundEffect(Shared.GetSoundIndex(kScanSound))
        self.scanSoundInstance:SetParent(self:GetId())
    end

    self.canPrimaryAttack = true
    self.deployed = false
    self.tracking = false
    self.charge = kMaxCharge
    self.toggleTracking = false

end

function MotionTracker:OnDestroy()

    if self.scanSoundInstance then
        Client.DestroySoundEffect(self.scanSoundInstance)
        self.scanSoundInstance = nil
    end

    ClipWeapon.OnDestroy(self)

end

function MotionTracker:OnInitialized()

    ClipWeapon.OnInitialized(self)

    self.charge = kMaxCharge
    self.tracking = false
    self.toggleTracking = false

    -- Mirror charge onto the HUD bullet display; never show spare ammo.
    self.clip = math.ceil(self.charge)
    self.ammo = 0

end

function MotionTracker:OnDraw(player, previousWeaponMapName)

    ClipWeapon.OnDraw(self, player, previousWeaponMapName)

    self.deployed = false
    if Client and player and player:GetIsLocalPlayer() then
        local vol = Client.GetOptionInteger("soundVolume", 90) / 100
        StartSoundEffectOnEntity(kActivateSound, self, kActivateVolume * vol)
    end

end

function MotionTracker:OnHolster(player)
    self.tracking = false
    self.toggleTracking = false
    if self.scanSoundInstance and self.scanSoundInstance:GetIsPlaying() then
        self.scanSoundInstance:Stop()
    end
    ClipWeapon.OnHolster(self, player)
end

-- ----------------------------------------------------------------------
-- Attack / charge model — no projectile, no damage.
-- ----------------------------------------------------------------------

-- Continuous hold: OnPrimaryAttack is invoked each move tick while held.
function MotionTracker:GetPrimaryAttackRequiresPress()
    return false
end

function MotionTracker:OnPrimaryAttack(player)
    -- When toggle mode is on, primary does nothing (scan is already forced on).
    if not self.toggleTracking then
        self.tracking = self.charge > 0
    end
end

function MotionTracker:OnPrimaryAttackEnd(player)
    if not self.toggleTracking then
        self.tracking = false
    end
end

function MotionTracker:GetHasSecondary(player)
    return true
end

-- Secondary fires once per press via the GetSecondaryAttackLastFrame guard.
function MotionTracker:OnSecondaryAttack(player)
    if self.GetParent then
        local parent = self:GetParent()
        if parent then
            if not parent:GetSecondaryAttackLastFrame() then
                self.toggleTracking = not self.toggleTracking
                if not self.toggleTracking then
                    self.tracking = false
                end
            end
        end
    end
end

function MotionTracker:OnSecondaryAttackEnd(player)
    -- Toggle persists; no action needed on release.
end

-- Server-authoritative charge drain (and HUD mirror) once per move tick.
function MotionTracker:ProcessMoveOnWeapon(player, input)

    ClipWeapon.ProcessMoveOnWeapon(self, player, input)

    if Server then

        -- Toggle mode forces tracking on while charge remains.
        -- If charge runs out while toggled, cancel the toggle so the MT does
        -- not auto-resume when charge is restored by an armory or ammo pack.
        if self.toggleTracking then
            if self.charge <= 0 then
                self.toggleTracking = false
                self.tracking = false
            else
                self.tracking = true
            end
        end

        if self.tracking and self.charge > 0 then
            self.charge = math.max(0, self.charge - input.time * kDrainRate)
        end

        -- Keep the marine HUD bullet display in sync with charge.
        self.clip = math.ceil(self.charge)
        self.ammo = 0

    end

end

-- No bullet effects: the weapon never fires.
function MotionTracker:ApplyBulletGameplayEffects(player, target, endPoint, direction, damage, surface, showTracer)
end

-- ----------------------------------------------------------------------
-- Clip economy — charge replaces ammo. No spare ammo, no reload.
-- ----------------------------------------------------------------------

function MotionTracker:GetClipSize()
    return kMotionTrackerClipSize
end

function MotionTracker:GetMaxClips()
    return 0
end

function MotionTracker:CanReload()
    return false
end

function MotionTracker:OnReload(player)
    -- Reload disabled; refill happens at an armory.
end

-- Armory resupply hooks (Armory_Server.lua): a weapon is refilled only
-- while GetNeedsAmmo(false) is true, by calling GiveAmmo(1, false).
function MotionTracker:GetNeedsAmmo(includeClip)
    return self.charge < kMaxCharge
end

function MotionTracker:GiveAmmo(numClips, includeClip)

    if self.charge >= kMaxCharge then
        return false
    end

    self.charge = math.min(kMaxCharge, self.charge + kArmoryRefillStep)
    return true

end

-- ----------------------------------------------------------------------
-- Animation
-- ----------------------------------------------------------------------

function MotionTracker:OnTag(tagName)

    PROFILE("MotionTracker:OnTag")

    if tagName == "deploy_start" then
        self.canPrimaryAttack = false
        self.deployed = false
    elseif tagName == "deploy_end" then
        self.canPrimaryAttack = true
        self.deployed = true
    elseif tagName == "sprint_start" then
        self.canPrimaryAttack = false
    elseif tagName == "sprint_end" then
        self.canPrimaryAttack = true
    elseif tagName == "jump_start" then
        self.canPrimaryAttack = false
    elseif tagName == "jump_end" then
        self.canPrimaryAttack = true
    elseif tagName == "can_shoot" then
        self.canPrimaryAttack = true
    end

end

function MotionTracker:OnUpdateAnimationInput(modelMixin)

    PROFILE("MotionTracker:OnUpdateAnimationInput")

    local move = "idle"
    local player = self:GetParent()
    if player then
        if HasMixin(player, "Stun") and player:GetIsStunned() then
            -- Onos stomp (or any stun) freezes the marine: play the stun pose.
            move = "stun"
        elseif player:GetIsIdle() then
            move = "idle"
        elseif player:GetIsSprinting() then
            move = "sprint"
        elseif player:GetIsJumping() then
            move = "jump"
        else
            move = "run"
        end
    end
    modelMixin:SetAnimationInput("move", move)

    local activity = "none"
    if not self.deployed then
        activity = "draw"
    elseif self.tracking and self.charge > 0 then
        activity = "primary"
    end
    modelMixin:SetAnimationInput("activity", activity)

end

function MotionTracker:GetAnimationGraphName()
    return kAnimationGraph
end

function MotionTracker:GetViewModelName()
    return kViewModelName
end

-- ----------------------------------------------------------------------
-- 3D-cone detection (client-side cosmetic — drives the local screen).
-- ----------------------------------------------------------------------

local function GetPlayerWeaponLevel(player)
    -- Use the networked weapon-upgrade level (client-safe); GetWeaponLevel()
    -- reads the tech tree and is server-only.
    if player and player.GetWeaponUpgradeLevel then
        return Clamp(player:GetWeaponUpgradeLevel(), 0, 3)
    end
    return 0
end

-- Scan within a 2D YAW-ONLY wedge (half-angle kHalfAngle[level]) around the
-- player's horizontal facing: pitch is ignored, so any alien whose bearing falls
-- inside the wedge and within maxRange is detected no matter how far up/down the
-- marine aims. This matches the wedge/green line drawn on the scanner screen.
-- Detection still respects range, cloak threshold and (WL0) line-of-sight.
-- Returns:
--   count       number of detected aliens (inside the wedge)
--   nearest     3D distance to the closest detected alien (0 if none)
--   blipString  "rx,rz;rx,rz;..." relative WORLD offsets in metres (2D, height
--               ignored for plotting), one per detected alien, capped at kMaxBlips
local function ScanForAliens(player, level)

    local origin   = player:GetOrigin()
    local eyePos   = player:GetEyePos()
    local enemyTeam = GetEnemyTeamNumber(player:GetTeamNumber())

    local maxRange       = kMaxRange[level]
    local halfAngle      = kHalfAngle[level]
    local wallVision     = kWallVision[level]
    local cloakThreshold = kCloakThreshold[level]

    -- View direction. Only its horizontal (X,Z) part is used for the wedge test:
    -- detection is YAW-ONLY and ignores pitch, matching the 2D wedge drawn on the
    -- scanner screen. The vertical (Y) component is intentionally discarded.
    local viewDir = player:GetViewCoords().zAxis

    local count        = 0
    local nearest      = 0
    local nearestClass = ""
    local nearestDY    = 0
    local parts        = {}

    local candidates = GetEntitiesWithMixinWithinRange("Live", origin, maxRange)
    for _, ent in ipairs(candidates) do

        -- Only the whitelisted alien lifeforms (excludes structures, tunnels, the
        -- player). Enemy-team check kept as a guard.
        if ent ~= player and kDetectableClasses[ent:GetClassName()]
           and ent.GetTeamNumber and ent:GetTeamNumber() == enemyTeam then

            -- Only living entities register (skip ragdolls).
            local alive = (ent.GetIsAlive == nil) or ent:GetIsAlive()
            if alive then

                local entOrigin = ent:GetOrigin()
                local rel = entOrigin - origin
                local dist3D = rel:GetLength()
                if dist3D <= maxRange then

                    -- 2D YAW-ONLY wedge gate from the EYE: project both the view
                    -- direction and the eye->entity vector onto the horizontal
                    -- (X,Z) plane and compare yaw only. Pitch is ignored entirely,
                    -- so an alien inside the wedge is detected no matter how far
                    -- up or down the marine is aiming (within range).
                    local toEnt = entOrigin - eyePos
                    local viewLen2D = math.sqrt(viewDir.x * viewDir.x + viewDir.z * viewDir.z)
                    local entLen2D  = math.sqrt(toEnt.x * toEnt.x + toEnt.z * toEnt.z)
                    local inCone = true
                    if viewLen2D > 0 and entLen2D > 0 then
                        local cosA = (viewDir.x * toEnt.x + viewDir.z * toEnt.z) / (viewLen2D * entLen2D)
                        inCone = math.acos(Clamp(cosA, -1, 1)) <= halfAngle
                    end
                    -- (degenerate: marine aiming straight up/down, or entity
                    --  directly above/below the eye -> treat as inside.)

                    if inCone then

                        -- Cloak filter: GetCloakFraction() already folds in
                        -- Camouflage and Shade/Ink, so one check covers all sources.
                        local cloakFraction = (HasMixin(ent, "Cloakable") and ent:GetCloakFraction()) or 0
                        if cloakFraction < cloakThreshold then

                            -- Line-of-sight filter (WL0 only): reject if world geometry
                            -- blocks the view (eye -> entity).
                            local visible = true
                            if not wallVision then
                                visible = not GetWallBetween(eyePos, entOrigin, ent)
                            end

                            if visible then
                                count = count + 1
                                if nearest == 0 or dist3D < nearest then
                                    nearest      = dist3D
                                    nearestClass = string.upper(ent:GetClassName())
                                    nearestDY    = entOrigin.y - origin.y
                                end
                                if #parts < kMaxBlips then
                                    -- 2D world offset; height (Y) deliberately ignored.
                                    parts[#parts + 1] = string.format("%.1f,%.1f", rel.x, rel.z)
                                end
                            end

                        end

                    end

                end

            end

        end

    end

    local vertDir = ""
    if nearestClass ~= "" then
        if nearestDY > 0.5 then
            vertDir = "UP"
        elseif nearestDY < -0.5 then
            vertDir = "DOWN"
        else
            vertDir = "EQUAL"
        end
    end

    return count, nearest, table.concat(parts, ";"), nearestClass, vertDir

end

-- ----------------------------------------------------------------------
-- Client
-- ----------------------------------------------------------------------

if Client then

    function MotionTracker:GetBarrelPoint()

        local player = self:GetParent()
        if player then
            local origin = player:GetEyePos()
            local viewCoords = player:GetViewCoords()
            return origin + viewCoords.zAxis * 0.825 + viewCoords.xAxis * -0.29 + viewCoords.yAxis * -0.24
        end

        return self:GetOrigin()

    end

    function MotionTracker:GetUIDisplaySettings()
        return { xSize = 400, ySize = 400, script = "lua/MotionTracker/GUIMotionTracker.lua" }
    end

    -- No muzzle / fire effects on this weapon.
    function MotionTracker:GetTriggerPrimaryEffects()
        return false
    end

    function MotionTracker:OnUpdateRender()

        -- Base pushes weaponClip/weaponAmmo/globalTime and sets self.ammoDisplayUI.
        ClipWeapon.OnUpdateRender(self)

        local player = self:GetParent()
        local ammoDisplayUI = self.ammoDisplayUI
        if not (player and player:GetIsLocalPlayer() and ammoDisplayUI) then
            return
        end

        local active = self.tracking and self.charge > 0
        local vol    = Client.GetOptionInteger("soundVolume", 90) / 100
        local detected, nearest, blips, nearestClass, vertDir = 0, 0, "", "", ""
        if active then
            detected, nearest, blips, nearestClass, vertDir = ScanForAliens(player, 3)
        end

        -- Player horizontal world facing (unit vector) for the green heading line.
        local viewDir = player:GetViewCoords().zAxis
        local faceX, faceZ = viewDir.x, viewDir.z
        local faceLen = math.sqrt(faceX * faceX + faceZ * faceZ)
        if faceLen > 0 then
            faceX, faceZ = faceX / faceLen, faceZ / faceLen
        else
            faceX, faceZ = 0, 1
        end

        ammoDisplayUI:SetGlobal("trackerActive",       active and "true" or "false")
        ammoDisplayUI:SetGlobal("trackerCharge",        self.charge)
        ammoDisplayUI:SetGlobal("trackerScale",         kMaxRange[3])
        ammoDisplayUI:SetGlobal("trackerHalfAngle",     kHalfAngle[3])
        ammoDisplayUI:SetGlobal("trackerNearest",       nearest)
        ammoDisplayUI:SetGlobal("trackerFaceX",         faceX)
        ammoDisplayUI:SetGlobal("trackerFaceZ",         faceZ)
        ammoDisplayUI:SetGlobal("trackerBlips",         blips)
        ammoDisplayUI:SetGlobal("trackerVertDir",       vertDir)
        ammoDisplayUI:SetGlobal("trackerNearestClass",  nearestClass)

        -- Scan sound: looping client instance Started/Stopped off the tracking
        -- state (Railgun pattern). Volume is set every frame so it follows the
        -- sound slider, matching the activate/detect sounds.
        if self.scanSoundInstance then
            local playing = self.scanSoundInstance:GetIsPlaying()
            if active and not playing then
                self.scanSoundInstance:Start()
            elseif playing and not active then
                self.scanSoundInstance:Stop()
            end
            if active then
                self.scanSoundInstance:SetVolume(kScanVolume * vol)
            end
        end

        -- Detect beep: re-played on an interval that gets SHORTER as the nearest
        -- target gets FARTHER. Reset when nothing is detected so the next contact
        -- beeps immediately. Volume scales with the sound slider.
        if active and detected > 0 and nearest > 0 then
            local now = Shared.GetTime()
            if now >= (self.nextDetectBeep or 0) then
                local frac = Clamp(nearest / kMaxRange[3], 0, 1)
                local interval = kBeepIntervalNear + (kBeepIntervalFar - kBeepIntervalNear) * frac
                StartSoundEffectOnEntity(kDetectSound, player, kDetectVolume * vol)
                self.nextDetectBeep = now + interval
            end
        else
            self.nextDetectBeep = 0
        end

    end

end

-- ----------------------------------------------------------------------
-- Misc weapon plumbing
-- ----------------------------------------------------------------------

-- Mirrors the BI9 pistol_mod: return the weapon's own death-message icon.
function MotionTracker:GetDeathIconIndex()
    return kDeathMessageIcon.MotionTracker
end

function MotionTracker:GetTechId()
    return kTechId.MotionTracker
end

function MotionTracker:GetHUDSlot()
    return 2
end

function MotionTracker:GetWeight()
    return kMotionTrackerWeight
end

function MotionTracker:GetPrimaryCanInterruptReload()
    return false
end

function MotionTracker:GetSecondaryCanInterruptReload()
    return false
end

function MotionTracker:OverrideWeaponName()
    return "pistol"
end

-- The dropped weapon entity should shrug off most damage (kept from the
-- original so the device can't be trivially destroyed on the ground).
function MotionTracker:ModifyDamageTaken(damageTable, attacker, doer, damageType)
    if damageType ~= kDamageType.Corrode then
        damageTable.damage = 0
    end
end

function MotionTracker:GetCanTakeDamageOverride()
    return self:GetParent() == nil
end

if Server then

    function MotionTracker:OnKill()
        DestroyEntity(self)
    end

    function MotionTracker:GetSendDeathMessageOverride()
        return false
    end

end

Shared.LinkClassToMap("MotionTracker", MotionTracker.kMapName, networkVars)
