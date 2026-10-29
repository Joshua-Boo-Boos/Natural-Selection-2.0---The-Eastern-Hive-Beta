Script.Load("lua/Weapons/Marine/ClipWeapon.lua")
Script.Load("lua/PickupableWeaponMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")
Script.Load("lua/PointGiverMixin.lua")

kBI9Loaded = true

class 'bi9' (ClipWeapon)

bi9.kMapName = "bi9"
bi9.kModelName = PrecacheAsset("models/marine/bi9/Pistol_World.model")
local kViewModelName = PrecacheAsset("models/marine/bi9/Pistol_View.model")
local kAnimationGraph = PrecacheAsset("models/marine/bi9/Pistol_View.animation_graph")

local kbi9BulletSize = 0.15
local kRange = 250
local kSpread = Math.Radians(3.4)      -- (2026-10-25) -20% (was 4.25)
local kMinSpread = Math.Radians(2.0)   -- (2026-10-25) -20% (was 2.5; unused)
local kAoeRadius = 4
local kButtRange = 1.1

local kFireSound = PrecacheAsset("sound/Pistol.fev/Pistol/Shoot")
local kDrawSound = PrecacheAsset("sound/Pistol.fev/Pistol/Equip")
local kReloadSound = PrecacheAsset("sound/Pistol.fev/Pistol/Reload")

local networkVars =
{
    canPrimaryAttack = "boolean",
    shooting = "boolean",
}

AddMixinNetworkVars(LiveMixin, networkVars)

local kMuzzleCinematics = 
{
    PrecacheAsset("cinematics/marine/rifle/muzzle_flash.cinematic"),
    PrecacheAsset("cinematics/marine/rifle/muzzle_flash.cinematic"),
    PrecacheAsset("cinematics/marine/rifle/muzzle_flash2.cinematic"),
    PrecacheAsset("cinematics/marine/rifle/muzzle_flash3.cinematic"),
}

--[[
    (2026-10-25) MUZZLE FLASH - one flash per bullet, same setup as the BIHC.
    Attach point "weapon_compensator": a bone in Pistol_View.fbx, and an armature (one bone) of that name at the muzzle
    of Pistol_World.fbx - both listed as attach_point in their .model_compile.
    Shooter: view-model copy created here (first person) or on the world model (third person).
    Everyone else: world-model copy via the effect system (bi9_muzzle in MarineWeaponEffects.lua).
    (Before: the attach point was "Compensator", which neither model has, so no flash ever showed.)
]]
local kMuzzleEffect = PrecacheAsset("cinematics/marine/pistol/muzzle_flash.cinematic")   -- vanilla NS2 pistol flash
local kMuzzleAttachPoint = "weapon_compensator"
local kMuzzleEffectVisibleTime = 0.5   -- seconds the shooter's copy stays before it is destroyed (vanilla pistol flash is shorter: it plays in full)

local function DestroyMuzzleEffect(self)
    if Client and self.muzzleCinematic then
        Client.DestroyCinematic(self.muzzleCinematic)
    end
    self.muzzleCinematic = nil
    self.muzzleCinematicEndTime = nil
    self.activeCinematicName = nil
end

local function PlayMuzzleEffect(self)
    if Server then
        self:TriggerEffects("bi9_muzzle")
    end
    -- Skipped during prediction re-runs so one shot creates it once.
    if Client and not Shared.GetIsRunningPrediction() then
        DestroyMuzzleEffect(self)
        self.muzzleCinematic = CreateMuzzleCinematic(self, kMuzzleEffect, kMuzzleEffect, kMuzzleAttachPoint)
        if self.muzzleCinematic then
            self.muzzleCinematicEndTime = Shared.GetTime() + kMuzzleEffectVisibleTime
        end
    end
end

--[[
    COSMETIC VIEW-MODEL SPIN: first play after 10 idle seconds, then every 10 seconds measured start-to-start.

    (2026-10-26) REWRITTEN - it played once and never again, not even after dying. The old version kept its state on
    the client only (never during prediction) and relied on the graph's "spin_start" / "spin_end" tags reaching that
    client code. NS2 animates the player's own view model in prediction, so the code animating it and the code holding
    the state were not reliably the same - one spin, then nothing. Now the state is worked out in OnProcessMove from
    the player's own movement, identically on the server, in prediction and on the client, and the spin's end is read
    from the view model's own animation (start time + length / play speed), the way the shot cycle is. No tags.

      1. Idle for kIdleSpinInterval seconds -> ask for a spin: activity "idle" + should_spin_gun.
      2. Once the view model is seen playing idle_spin (started since the ask), keep activity "idle" (should_spin_gun
         off) until that play ends. Then back to "none", and the next spin is due 10 s after this one started.
      3. If the graph has not started the spin within kIdleSpinStartWindow, the ask is dropped until the next interval.
    Anything that is not idle (moving, turning, firing, reloading, stunned, drawing...) resets the 10 s count.
]]
local kIdleSpinInterval = 10
local kIdleSpinStartWindow = 1   -- seconds the graph has to start a spin once asked
local kIdleSpinFailsafe = 9.5    -- longest a spin is allowed to hold "idle" (any spin speed fits in the 10 s gap)

local function ResetIdleSpin(self)
    self.idleSpinNextTime = nil
    self.idleSpinRequestedAt = nil
    self.idleSpinEnd = nil
end

-- Start time and end time of the view model's current play of `sequenceName`, or nil if it is not playing it.
local function GetViewModelAnimationTimes(player, sequenceName)
    local viewModel = player and player.GetViewModelEntity and player:GetViewModelEntity()
    local model = viewModel and viewModel.modelIndex and Shared.GetModel(viewModel.modelIndex)
    if not model or not viewModel.animationSequence then return nil end
    local index = model:GetSequenceIndex(sequenceName)
    if index < 0 or viewModel.animationSequence ~= index then return nil end
    local speed = viewModel.animationSpeed or 1
    if speed <= 0 then return nil end
    return viewModel.animationStart, viewModel.animationStart + model:GetSequenceLength(index) / speed
end

-- Called from OnProcessMove, every move, in every realm.
local function UpdateIdleSpin(self, player)

    local now = Shared.GetTime()
    local angles = player and player:GetViewAngles()
    local turned = angles and self.idleSpinYaw and
        (math.abs(angles.yaw - self.idleSpinYaw) > 0.0001 or
         math.abs(angles.pitch - self.idleSpinPitch) > 0.0001)
    if angles then
        self.idleSpinYaw = angles.yaw
        self.idleSpinPitch = angles.pitch
    end

    local idle = player and player:GetIsAlive() and player:GetActiveWeapon() == self
        and player:GetIsIdle() and not player:GetIsSprinting() and not player:GetIsJumping()
        and not (HasMixin(player, "Stun") and player:GetIsStunned())
        and self.deployed and not self.reloading and not self.shotCycle
        and not self.primaryAttacking and not player.primaryAttackLastFrame
        and not player.secondaryAttackLastFrame and not turned

    if not idle then
        ResetIdleSpin(self)
        return
    end

    -- Playing: hold until this play ends.
    if self.idleSpinEnd then
        if now >= self.idleSpinEnd then
            self.idleSpinEnd = nil
        end
        return
    end

    -- Asked: wait for the view model to start a play of idle_spin (one that started since the ask).
    if self.idleSpinRequestedAt then
        local startTime, endTime = GetViewModelAnimationTimes(player, "idle_spin")
        if startTime and startTime >= self.idleSpinRequestedAt - 0.1 then
            self.idleSpinEnd = math.min(endTime, self.idleSpinRequestedAt + kIdleSpinFailsafe)
            self.idleSpinRequestedAt = nil
        elseif now - self.idleSpinRequestedAt > kIdleSpinStartWindow then
            self.idleSpinRequestedAt = nil
        end
        return
    end

    self.idleSpinNextTime = self.idleSpinNextTime or (now + kIdleSpinInterval)
    if now >= self.idleSpinNextTime then
        self.idleSpinRequestedAt = now
        self.idleSpinNextTime = now + kIdleSpinInterval
    end

end


function bi9:OnDestroy()
    ClipWeapon.OnDestroy(self)
    DestroyMuzzleEffect(self)
end

function bi9:OnCreate()
    ClipWeapon.OnCreate(self)
    InitMixin(self, PickupableWeaponMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, PointGiverMixin)
    if Client then
        InitMixin(self, ClientWeaponEffectsMixin)
    end
    self.canPrimaryAttack = true
    self.primaryAttacking = false
    self.deployed = false
    self.reloading = false
    self.shooting = false
    self.firstPersonLoaded = false
    self.activeCinematicName = nil
    self.muzzleCinematic = nil
end

function bi9:OnInitialized()
    ClipWeapon.OnInitialized(self)
end

if Client then

    function bi9:OnFilteredCinematicOptionChanged()
        DestroyMuzzleEffect(self)
    end

    -- (2026-10-25) The muzzle flash is now one per bullet (PlayMuzzleEffect, from FireShot).
    function bi9:OnClientPrimaryAttackStart()
    end

    function bi9:OnClientPrimaryAttackEnd()
    end

    function bi9:OnParentChanged(oldParent, newParent)
        ClipWeapon.OnParentChanged(self, oldParent, newParent)
        DestroyMuzzleEffect(self)
    end

    function bi9:OnUpdateRender()
        if ClipWeapon.OnUpdateRender then
            ClipWeapon.OnUpdateRender(self)
        end
        -- Remove the shooter's muzzle flash once its visible time is up.
        if self.muzzleCinematicEndTime and Shared.GetTime() >= self.muzzleCinematicEndTime then
            DestroyMuzzleEffect(self)
        end
    end

    function bi9:GetPrimaryEffectRate()
        return 1
    end

    function bi9:GetTriggerPrimaryEffects()
        return not self:GetIsReloading() and self.shooting
    end

end

function bi9:OnHolster(player)
    ResetIdleSpin(self)
    -- Vanilla holster: cancels a reload in progress, clears "deployed", hides the weapon. It was never called, so a BI9
    -- holstered mid-reload stayed "reloading" (and its reload sound/state carried on) after switching weapon.
    ClipWeapon.OnHolster(self, player)
    self.reloadProgress = nil
    self.shotCycle = false
    self.shotFired = false
    DestroyMuzzleEffect(self)
    self.shooting = false
    if Client then
        self:OnClientPrimaryAttackEnd()
    end
end

function bi9:OnHolsterClient()
    ResetIdleSpin(self)
    DestroyMuzzleEffect(self)
    ClipWeapon.OnHolsterClient(self)
    self.shooting = false
    if Client then
        self:OnClientPrimaryAttackEnd()
    end
end

--[[
    (2026-10-25) FIRING - DRIVEN BY THE SHOOT ANIMATION, FULL AUTO.
    One "shot cycle" = one play of the view model's "shoot" animation (graph node: activity == primary):
      1. Trigger held and the gun can fire -> a cycle starts: ONE bullet fires, activity becomes "primary" and the
         shoot animation plays.
      2. When that animation has finished playing (read from the view model's own animation state: start time +
         length / play speed), the cycle ends and activity goes back to "none". If the trigger is still held, the next
         cycle starts on the next frame.
    So the fire rate is the shoot animation's play speed in Pistol_View.animation_graph - nothing else. No animation
    tag is used (an earlier version waited for can_shoot, which the graph sent at the wrong time).
]]
local kShotCycleFailsafe = 2   -- seconds: ends a cycle if the shoot animation is never seen playing (a graph problem)
local FireShot   -- defined below OnPrimaryAttack

-- The time the view model's current shoot animation finishes, or nil if it isn't playing the shoot animation.
local function GetShootAnimationEnd(player)
    local viewModel = player and player.GetViewModelEntity and player:GetViewModelEntity()
    local model = viewModel and viewModel.modelIndex and Shared.GetModel(viewModel.modelIndex)
    if not model or not viewModel.animationSequence then return nil end
    local index = model:GetSequenceIndex("shoot")
    if index < 0 or viewModel.animationSequence ~= index then return nil end
    local speed = viewModel.animationSpeed or 1
    if speed <= 0 then return nil end
    return viewModel.animationStart + model:GetSequenceLength(index) / speed
end

local function EndShotCycle(self)
    self.shotCycle = false
    self.shotFired = false
    self.shotAnimEnd = nil
    self.primaryAttacking = false
    self.shooting = false
    if Client then
        self:OnClientPrimaryAttackEnd()
    end
end

local function GetCanFire(self, player)
    return player and not self.reloading and self.deployed
        and not (player.GetIsSprinting and player:GetIsSprinting())
        and not (HasMixin(player, "Stun") and player:GetIsStunned())
end

-- Called every frame the trigger is held. Starts a shot cycle; never fires by itself.
function bi9:OnPrimaryAttack(player)
    ResetIdleSpin(self)

    player = player or self:GetParent()
    if not GetCanFire(self, player) then
        if self.shotCycle then EndShotCycle(self) end
        return
    end

    -- Empty: reload (once - Reload sets self.reloading, which stops this the next frame).
    if self.clip <= 0 then
        if self.shotCycle then EndShotCycle(self) end
        if self.ammo > 0 then
            player:Reload()   -- OnReload plays the reload sound (it used to play here too: twice)
        end
        return
    end

    if not self.shotCycle then
        self.shotCycle = true
        self.shotFired = false
        self.shotCycleStart = Shared.GetTime()
        self.shotAnimEnd = nil
        self.primaryAttacking = true   -- activity "primary": the graph plays the shoot animation
        FireShot(self)
    end

end

-- The trigger was released: the current shot still plays out (activity stays "primary" until its animation ends).
function bi9:OnPrimaryAttackEnd(player)
    ClipWeapon.OnPrimaryAttackEnd(self, player)
end

-- One bullet per cycle, fired as the shoot animation starts.
FireShot = function(self)
    local player = self:GetParent()
    if not (self.shotCycle and not self.shotFired and self.clip > 0 and GetCanFire(self, player)) then return end
    self.shotFired = true
    self.shooting = true
    if Client then
        self:OnClientPrimaryAttackStart()
    end
    if Server then
        StartSoundEffectOnEntity(kFireSound, player, 0.05)
    end
    self:FireBullets(player)
    PlayMuzzleEffect(self)
    self.clip = self.clip - 1
end

function bi9:FireBullets(player)
    PROFILE("bi9:FireBullets")
    local viewAngles = player:GetViewAngles()
    local shootCoords = viewAngles:GetCoords()
    local filter = EntityFilterTwo(player, self)
    local range = self:GetRange()
    local numberBullets = self:GetBulletsPerShot()
    local startPoint = player:GetEyePos()
    local bulletSize = self:GetBulletSize()
    for bullet = 1, numberBullets do
        local spreadDirection = self:CalculateSpreadDirection(shootCoords, player)
        local endPoint = startPoint + spreadDirection * range
        local targets, trace, hitPoints = GetBulletTargets(startPoint, endPoint, spreadDirection, bulletSize, filter)
        local damage = self:GetBulletDamage()
        HandleHitregAnalysis(player, startPoint, endPoint, trace)
        local direction = (trace.endPoint - startPoint):GetUnit()
        local hitOffset = direction * kHitEffectOffset
        local impactPoint = trace.endPoint - hitOffset
        local effectFrequency = 1
        local showTracer = true
        local numTargets = #targets
        if numTargets == 0 then
            self:ApplyBulletGameplayEffects(player, nil, impactPoint, direction, 0, trace.surface, true)
        end
        for i = 1, numTargets do
            local target = targets[i]
            local hitPoint = hitPoints[i]
            self:ApplyBulletGameplayEffects(player, target, hitPoint - hitOffset, direction, damage, "", true)
            local client = Server and player:GetClient() or Client
            if not Shared.GetIsRunningPrediction() and client.hitRegEnabled then
                RegisterHitEvent(player, bullet, startPoint, trace, damage)
            end
        end
    end
end

-- (2026-10-25) The older OnTag / OnUpdateAnimationInput pair that stood here was removed: they were defined again
-- further down, so these were never used. The versions below are the only ones.

function bi9:GetAnimationGraphName()
    return kAnimationGraph
end

function bi9:GetViewModelName()
    return kViewModelName
end

function bi9:GetDeathIconIndex()
    return kDeathMessageIcon.bi9
end

function bi9:GetHUDSlot()
    return kSecondaryWeaponSlot
end

function bi9:GetPrimaryMinFireDelay()
    -- No timer: the fire rate is the shoot animation's play speed (see the shot cycle in OnPrimaryAttack).
end

function bi9:OnDraw(player, previousWeaponMapName)
    ResetIdleSpin(self)

    ClipWeapon.OnDraw(self, player, previousWeaponMapName)

    self.deployed = false
    if Server then
        StartSoundEffectOnEntity(kDrawSound, self, 0.03)
    end
    
end

function bi9:GetMaxClips()
    return 4
end

-- (2026-10-25) Spare ammo = 4 full magazines (the chambered round isn't part of a magazine): 4 x 32.
-- (2026-10-26) The magazine is GetClipSize() - 1, not a fixed 32, so a bigger magazine from another mod (Combat
-- Enhancer's Advanced Ammopack wraps GetClipSize) also gives bigger magazines here and in the reload below.
local function GetMagazineRounds(self)
    return math.max(1, self:GetClipSize() - 1)
end
function bi9:GetMaxAmmo()
    return self:GetMaxClips() * GetMagazineRounds(self)
end

function bi9:GetClipSize()
    
    return kbi9ClipSize

end

function bi9:GetSpread()
    return kSpread
end

local function CannonRandom()
    return math.max(0.2 + NetworkRandom())
end

function bi9:CalculateSpreadDirection(shootCoords, player)
    return CalculateSpread(shootCoords, self:GetSpread() * self:GetInaccuracyScalar(player), CannonRandom)
end

function bi9:GetBulletDamage(target, endPoint)
    return kbi9Damage
end

function bi9:GetBulletSize()
    return kbi9BulletSize
end

function bi9:GetRange()
    return kRange
end

function bi9:GetWeight()
    return kbi9Weight
end

function bi9:GetPrimaryCanInterruptReload()
    return false
end

function bi9:GetSecondaryCanInterruptReload()
    return false
end

function bi9:GetHasSecondary(player)
    return false
end

--[[
    The reload animation's speed. Pistol_View.animation_graph's reload node plays at the "catalyst_speed" input, which
    Marine:OnUpdateAnimationInput sets every frame from this (x1.25 with a Catpack). 0.25 is the speed the
    reload node had before it was wired to the input, so a normal reload is exactly as fast as before; Combat's
    Fast Reload makes it x1.75 (vanilla Combat's bonus), and Combat Enhancer's Rapid Reload multiplies it
    further. Always returns a number (the old version could return nothing mid-reload).
]]
function bi9:GetCatalystSpeedBase()
    -- The reload node plays at "catalyst_speed", so while reloading this is the reload's own base speed (0.25,
    -- x1.75 with Combat Fast Reload). Outside a reload it is 1, like every other weapon, so nothing else wired to
    -- catalyst_speed is slowed down.
    if not self:GetIsReloading() then
        return 1
    end
    local speed = 0.25
    if kCombatVersion then
        local player = self:GetParent()
        if player and player.GotFastReload and player:GotFastReload() then
            speed = speed * 1.75
        end
    end
    return speed
end

function bi9:OnReload(player)
    ResetIdleSpin(self)
    if self:CanReload() then
        if Server then
            StartSoundEffectOnEntity(kReloadSound, player, 0.1)
        end
        self.reloading = true
    end
end


--[[
    Safety net: a reload finishes on the view model's "reload_end" tag. If that tag never arrives (a graph problem -
    e.g. its speed input not set), the reload is finished here instead.
    (2026-10-26) The net follows the reload's REAL SPEED, not a fixed 5 seconds: every move it advances by the time
    passed x the current catalyst_speed (GetCatalystSpeedBase - which Combat's Fast Reload and Combat Enhancer's Rapid
    Reload raise - x the Catalyst pack bonus, exactly what Marine:OnUpdateAnimationInput feeds the graph), and the
    reload ends once the reload animation (frames 200-223, 0.8 s at speed 1) would have played to the end, plus a
    little slack so the tag normally gets there first. With the old fixed 5 s, a reload that ended on the net ignored
    every reload speed bonus.
]]
local kReloadAnimationLength = 24 / 30   -- seconds at speed 1
local kReloadNetSlack = 1.1              -- the net fires at 110% of the animation, after the tag would have
function bi9:OnProcessMove(input)
    ClipWeapon.OnProcessMove(self, input)
    if self.reloading then
        local speed = self:GetCatalystSpeedBase()
        local player = self:GetParent()
        if player and player.GetHasCatPackBoost and player:GetHasCatPackBoost() then
            speed = speed * kCatPackWeaponSpeed
        end
        self.reloadProgress = (self.reloadProgress or 0) + (input.time or 0) * speed / kReloadAnimationLength
        if self.reloadProgress >= kReloadNetSlack then
            self.reloadProgress = nil
            self:OnTag("reload_end")
        end
    else
        self.reloadProgress = nil
    end
    UpdateIdleSpin(self, self:GetParent())
    -- End the shot cycle once this cycle's shoot animation has finished playing (only a play that started with this
    -- cycle counts - 0.1 s slack for the frame the graph switched on). Safety net if it is never seen playing.
    if self.shotCycle then
        local now = Shared.GetTime()
        local animEnd = GetShootAnimationEnd(self:GetParent())
        if not self.shotAnimEnd and animEnd and animEnd - (self.shotCycleStart or 0) > -0.1 then   -- first play only: a graph loop must not push the end back
            self.shotAnimEnd = animEnd
        end
        if (self.shotAnimEnd and now >= self.shotAnimEnd) or now - (self.shotCycleStart or 0) > kShotCycleFailsafe then
            EndShotCycle(self)
        end
    end
end

function bi9:GetAmmoPackMapName()
    -- return RifleAmmo.kMapName
end


function bi9:OverrideWeaponName()
    return "pistol"
end

function bi9:ApplyBulletGameplayEffects(player, target, endPoint, direction, damage, surface, showTracer)
end

function bi9:GetPrimaryAttackRequiresPress()
    return false   -- full auto: hold to keep firing, one shot per play of the shoot animation
end

function bi9:OnTag(tagName)

    PROFILE("bi9:OnTag")

    -- (2026-10-26) The idle spin no longer uses its "spin_start" / "spin_end" tags (see UpdateIdleSpin).

    local player = self:GetParent()

    -- (2026-10-25) Shots no longer use tags: the shot cycle ends when the shoot animation finishes (OnProcessMove).

    if tagName == "deploy_start" then

        self.canPrimaryAttack = false
        self.deployed = false

    end

    if tagName == "deploy_end" then

        self.canPrimaryAttack = true
        self.deployed = true

    end

    if tagName == "sprint_start" then

        self.canPrimaryAttack = false
    
    end

    if tagName == "reload_start" then

        self.primaryAttacking = false
        self.canPrimaryAttack = false
        self.shooting = false
        if Client then
            self:OnClientPrimaryAttackEnd()
        end

    end

    if tagName == "reload_end" then
        
        self.reloading = false
        self.canPrimaryAttack = true

        -- (2026-10-25) A round left in the gun stays chambered: reloading then gives 32 + 1 = 33. From empty: 32.
        local target = self.clip > 0 and self:GetClipSize() or GetMagazineRounds(self)
        local taken = math.max(0, math.min(target - self.clip, self.ammo))
        self.clip = self.clip + taken
        self.ammo = self.ammo - taken

    end

    if tagName == "jump_end" then

        self.canPrimaryAttack = true

    end

    if tagName == "can_shoot" then
        self.canPrimaryAttack = true
    end

    -- Onos Stomp: the marine is stunned and locked into the "stomped" view-model node. Block firing on entry,
    -- restore it when the node is left (as the Mac-10 does).
    if tagName == "stomped_now" then
        self.primaryAttacking = false
        self.canPrimaryAttack = false
        self.shooting = false
        if Client then
            self:OnClientPrimaryAttackEnd()
        end
    end

    if tagName == "stomped_end" then
        self.canPrimaryAttack = true
    end

end

function bi9:OnUpdateAnimationInput(modelMixin)

    PROFILE("bi9:OnUpdateAnimationInput")
    
    local move = "idle"
    local activity = "draw"

    local player = self:GetParent()
    if player then

        if HasMixin(player, "Stun") and player:GetIsStunned() then
            -- Onos Stomp stun takes priority over every other move state ("stomped" node).
            move = "stomped"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsIdle() then
            modelMixin:SetAnimationInput("move", move)
        elseif not player:GetIsIdle() and not player:GetIsSprinting() then
            move = "run"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsSprinting() then
            move = "sprint"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsJumping() then
            move = "jump"
            modelMixin:SetAnimationInput("move", move)
        end
    
    end

    if self.reloading then
        activity = "reload"
    elseif not self.deployed then
        activity = "draw"
    elseif self.shotCycle and not self.shotAnimEnd and self.deployed then
        -- (2026-10-25) "primary" only until the shoot node has started: its "Hold before exit" plays it to the end, and
        -- "none" by then stops the graph looping it a second time. The next shot sets "primary" again.
        activity = "primary"
    else
        activity = "none"
    end

    -- Idle spin (UpdateIdleSpin, run from OnProcessMove): asked for, or playing.
    if (self.idleSpinRequestedAt or self.idleSpinEnd) and activity == "none" then
        activity = "idle" -- the graph's spin-only activity; ordinary idle remains "none"
    end
    modelMixin:SetAnimationInput("should_spin_gun", self.idleSpinRequestedAt ~= nil)
    modelMixin:SetAnimationInput("activity", activity)

end

if Client then    
    
    
    function bi9:GetBarrelPoint()
    
        local player = self:GetParent()
        if player then
        
            local origin = player:GetEyePos()
            local viewCoords= player:GetViewCoords()
            
            return origin + viewCoords.zAxis * 0.825 + viewCoords.xAxis * -0.29 + viewCoords.yAxis * -0.24
            
        end
        
        return self:GetOrigin()
        
    end    
    
    function bi9:GetUIDisplaySettings()
        -- 320x320 (was 80x80, which made the ammo text blurry); must match GUIBI9Display.lua screenX / screenY.
        return { xSize = 320, ySize = 320, script = "lua/BI9/GUIBI9Display.lua"}
    end
    
end

function bi9:ModifyDamageTaken(damageTable, attacker, doer, damageType)

    if damageType ~= kDamageType.Corrode then
        damageTable.damage = 0
    end
    
end

function bi9:GetCanTakeDamageOverride()
    return self:GetParent() == nil
end

-- function bi9:GetTracerEffectName()
--     return kTracerCinematic
-- end

-- function bi9:GetTracerResidueEffectName()
--     return kTracerResidueCinematic
-- end

-- function bi9:GetTracerEffectFrequency()
--     return 1
-- end

if Server then

    function bi9:OnKill()
        DestroyEntity(self)
    end
    
    function bi9:GetSendDeathMessageOverride()
        return false
    end 
    
end


Shared.LinkClassToMap("bi9", bi9.kMapName, networkVars)