Script.Load("lua/Utility.lua")
-- Siege: Shadow Step rework ported from Combat Enhancer (lua/Xmenu2/Vokex/Vokex.lua, 2026-10-13); comments marked
-- "Combat Enhancer:" describe that rework and apply here unchanged.
Script.Load("lua/CNBalance/Weapons/Alien/SwipeShadowStep.lua")
Script.Load("lua/CNBalance/Weapons/Alien/ReadyRoomShadowStep.lua")
Script.Load("lua/CNBalance/Weapons/Alien/MetabolizeShadowStep.lua")
Script.Load("lua/CNBalance/Weapons/Alien/VortexShadowStep.lua")
Script.Load("lua/CNBalance/Weapons/Alien/AcidRocket.lua")
Script.Load("lua/Alien.lua")
Script.Load("lua/Mixins/BaseMoveMixin.lua")
Script.Load("lua/Mixins/GroundMoveMixin.lua")
Script.Load("lua/CelerityMixin.lua")
Script.Load("lua/Mixins/JumpMoveMixin.lua")
Script.Load("lua/Mixins/CrouchMoveMixin.lua")
Script.Load("lua/Mixins/CameraHolderMixin.lua")
Script.Load("lua/DissolveMixin.lua")
Script.Load("lua/TunnelUserMixin.lua")
Script.Load("lua/BabblerClingMixin.lua")
Script.Load("lua/Weapons/PredictedProjectile.lua")
Script.Load("lua/IdleMixin.lua")
Script.Load("lua/FilteredCinematicMixin.lua")
Script.Load("lua/RailgunTargetMixin.lua")

class 'Vokex' (Alien)

Vokex.kMapName = "vokex"

Vokex.kModelName = PrecacheAsset("models/alien/fade/vokex.model")
local kVokexAnimationGraph = PrecacheAsset("models/alien/fade/fade.animation_graph")
local kViewModelName = PrecacheAsset("models/alien/fade/fade_albino_view.model")
local kViewAnimationGraphName = PrecacheAsset("models/alien/vokex/vokex_view.model")
Vokex.kBountyThreshold = kBountyClaimMinFade

PrecacheAsset("models/alien/fade/fade.surface_shader")

local kViewOffsetHeight = 1.7
Vokex.XZExtents = 0.4
Vokex.YExtents = 1.05
Vokex.kHealth = kVokexHealth
Vokex.kArmor = kVokexArmor
Vokex.kAdrenalineEnergyRecuperationRate = 15.0

Vokex.kShadowStepFriction = 0
Vokex.kGroundFrictionBase = 9
Vokex.kGroundFrictionPostBlink = 3
Vokex.kGroundFrictionPostBlinkDelay = 0.25


local kMetabolizeAnimationDelay = 0.65
-- ~350 pounds.
local kMass = 158
local kJumpHeight = 1.4

local kVokexScanDuration = 4

-- Slow the Vokex down while Shadow Stepping by 10% (from 25 to 22.5) and increase the cooldown by 0.05 seconds (from 0.4 to 0.45).
-- Combat Enhancer: Shadow Step is HELD (secondary attack, any Vokex weapon) and moves the Vokex at a constant speed - the
-- Fade's Blink speed (vanilla Fade.lua kBlinkSpeed, 14) - in the direction of the held movement keys. Was a 22.5 dash.
-- 20% faster than Blink (user 2026-10-12: 14 * 1.2 = 16.8), then 80% of that (user 2026-10-13): 13.44.
local kShadowStepSpeed = 14 * 1.2 * 0.8
-- Vanilla NS2's Blink speed cap (Fade.lua kBlinkMaxSpeed): the step's top speed, and the jump-during-a-step launch speed.
local kShadowStepMaxSpeed = 25
-- Scale on the FINAL step speed (after Celerity and other bonuses, and after the cap). Was 0.8 briefly; back to full
-- speed, with and without Celerity (user 2026-10-13): 13.44 base, up to 14.94 with full Celerity, cap 25.
local kShadowStepSpeedScale = 1
-- Holding jump during a step: gravity is balanced out; the climb builds up by this much a second to a steady climbing
-- speed and holds it (user 2026-10-13: going up at a not too fast speed).
-- 80% of the earlier 14 / 7 (user 2026-10-13: the vertical speed was a bit too much) - same time to reach top speed.
local kShadowStepClimbAccel = 14 * 0.8
local kShadowStepClimbSpeed = 7 * 0.8
local kShadowStepSpeedBonusPerCelerity = 0.66
Vokex.kShadowStepDuration = 0.2
--[[
    The time before Shadow Step can be used again after a step ends is 0.15 s (user 2026-10-18; was 0.2 s - same as
    Combat Enhancer). A step's end sets timeShadowStep to (end time - kShadowStepDuration), and GetHasShadowStepCooldown
    waits until timeShadowStep + kShadowStepCooldown, so the gap after a step is kShadowStepCooldown - kShadowStepDuration.
]]
local kShadowStepReuseGap = 0.15
local kShadowStepCooldown = Vokex.kShadowStepDuration + kShadowStepReuseGap

local kMaxSpeed = 7.2

local kCelerityFrictionFactor = 0.04


-- Gravity: 80% of the original 1.5x (user 2026-10-13) - the Vokex falls more slowly. (NS2 fall speed comes from this
-- multiplier, not from the Vokex's mass.) The jump keeps its original HEIGHT: jump speed scales by
-- sqrt(1.5 * new gravity), so height = speed^2 / (2 * gravity) is unchanged (it just rises and falls more slowly).
local kVokexGravityMod = 1.5 * 0.8
local kVokexJumpMod = math.sqrt(1.5 * kVokexGravityMod)

if Server then
    Script.Load("lua/CNBalance/Lifeforms/Vokex_Server.lua")
elseif Client then
    Script.Load("lua/CNBalance/Lifeforms/Vokex_Client.lua")
end

local networkVars =
{
    isScanned = "boolean",
    shadowStepping = "boolean",
    timeShadowStep = "private compensated time",
    shadowStepDirection = "private vector",
    shadowStepSpeed = "private compensated interpolated float",
    
    etherealStartTime = "private time",
    etherealEndTime = "private time",
    
    hasDoubleJumped = "private compensated boolean",

    -- (NS2.0-TEH / Siege: NO new network variables for the held Shadow Step - CE's networked press latch and start time
    -- are replaced by the player's input state and etherealStartTime above; see ShadowStep:OnSecondaryAttack.)

    -- // True when we're moving quickly "through the ether"
    ethereal = "boolean",
    
    timeMetabolize = "private compensated time",
    
    timeOfLastPhase = "time",
    hasEtherealGate = "boolean"
    
}

AddMixinNetworkVars(BaseMoveMixin, networkVars)
AddMixinNetworkVars(GroundMoveMixin, networkVars)
AddMixinNetworkVars(JumpMoveMixin, networkVars)
AddMixinNetworkVars(CrouchMoveMixin, networkVars)
AddMixinNetworkVars(CelerityMixin, networkVars)
AddMixinNetworkVars(CameraHolderMixin, networkVars)
AddMixinNetworkVars(DissolveMixin, networkVars)
AddMixinNetworkVars(TunnelUserMixin, networkVars)
AddMixinNetworkVars(BabblerClingMixin, networkVars)
AddMixinNetworkVars(IdleMixin, networkVars)

function Vokex:OnCreate()

    InitMixin(self, BaseMoveMixin, { kGravity = Player.kGravity * kVokexGravityMod })
    InitMixin(self, GroundMoveMixin)
    InitMixin(self, JumpMoveMixin)
    InitMixin(self, CrouchMoveMixin)
    InitMixin(self, CelerityMixin)
    InitMixin(self, CameraHolderMixin, { kFov = kFadeFov })
    
    Alien.OnCreate(self)
    
    InitMixin(self, DissolveMixin)
    InitMixin(self, TunnelUserMixin)
    InitMixin(self, BabblerClingMixin)
    
    InitMixin(self, PredictedProjectileShooterMixin)
    
    if Client then
        InitMixin(self, FilteredCinematicMixin)
    end
    
    self.shadowStepDirection = Vector()
    
    if Server then
    
        self.timeLastScan = 0
        self.timeShadowStep = 0
        self.shadowStepping = false
        
    end
    
    self.etherealStartTime = 0
    self.etherealEndTime = 0
    self.ethereal = false

end

function Vokex:OnInitialized()

    Alien.OnInitialized(self)
    
    self:SetModel(Vokex.kModelName, kVokexAnimationGraph)
    
    if Client then
    
        self.blinkDissolve = 0
        
        self:AddHelpWidget("GUITunnelEntranceHelp", 1)

        InitMixin(self, RailgunTargetMixin)
    end
    
    InitMixin(self, IdleMixin)
    
end

function Vokex:GetShowElectrifyEffect()
    return self.hasEtherealGate or self.electrified
end

function Vokex:GetMapBlipType()
    return kMinimapBlipType.Vokex
end

function Vokex:ModifyJump(input, velocity, jumpVelocity)

    -- (Combat Enhancer: a jump during a Shadow Step is a normal Vokex jump; holding jump then climbs gently - see the
    -- climb in Vokex:ModifyVelocity.)
    if not self.hasDoubleJumped then
        jumpVelocity:Scale(kVokexJumpMod)
    end
end

function Vokex:OnKill()
    self:TriggerEffects("metabolize_stop") --Might not be ideal

    Player.OnKill(self)
end

function Vokex:OnDestroy()

    Alien.OnDestroy(self)
    
    if Client then
        self:DestroyTrailCinematic()
    end
    
end

function Vokex:GetControllerPhysicsGroup()

    if self.isHallucination then
        return PhysicsGroup.SmallStructuresGroup
    end

    return PhysicsGroup.BigPlayerControllersGroup  
  
end

function Vokex:GetInfestationBonus()
    return kFadeInfestationSpeedBonus
end

function Vokex:GetCarapaceSpeedReduction()
    return kFadeCarapaceSpeedReduction
end

function Vokex:MovementModifierChanged(newMovementModifierState, input)

    if newMovementModifierState and self:GetActiveWeapon() ~= nil then
        local weaponMapName = self:GetActiveWeapon():GetMapName()
        local metabweapon = self:GetWeapon(MetabolizeShadowStep.kMapName)
        if metabweapon and not metabweapon:GetHasAttackDelay() and self:GetEnergy() >= metabweapon:GetEnergyCost() then
            self:SetActiveWeapon(MetabolizeShadowStep.kMapName)
            self:PrimaryAttack()
            if weaponMapName ~= MetabolizeShadowStep.kMapName then
                self.previousweapon = weaponMapName
            end
        end
    end
end

function Vokex:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint)
    if not doer then return end
    local reduction = kVokexDamageReduction[doer:GetClassName()]
    if reduction then
        damageTable.damage = damageTable.damage * reduction
    end
end

function Vokex:OnProcessMove(input)

    Alien.OnProcessMove(self,input)
end

function Vokex:OverrideInput(input)

    Alien.OverrideInput(self, input)

    -- Combat Enhancer: the movement keys are NOT overridden while Shadow Stepping - their live direction steers the step
    -- (Vokex:ModifyVelocity).
    return input
end

function Vokex:ModifyCrouchAnimation(crouchAmount)    
    return Clamp(crouchAmount * (1 - ( (self:GetVelocityLength() - kMaxSpeed) / (kMaxSpeed * 0.5))), 0, 1)
end

function Vokex:GetHeadAttachpointName()
    return "fade_tongue2"
end

-- // Prevents reseting of celerity.
function Vokex:OnSecondaryAttack()
end

function Vokex:GetBaseArmor()
    return Vokex.kArmor
end

function Vokex:GetBaseHealth()
    return Vokex.kHealth
end

function Vokex:GetExtraHealth(techLevel,extraPlayers,recentWins)
    return kVokexHealthPerBioMass * techLevel
            - recentWins * 5
end

function Vokex:GetCarapaceBonusPerBiomass()
    return kVokexCarapaceArmorPerBiomass
end

function Vokex:GetMaxViewOffsetHeight()
    return kViewOffsetHeight
end

function Vokex:GetViewModelName()
    return kViewModelName
end

function Vokex:OnJump()

    if not self:GetIsOnGround() then
        self.hasDoubleJumped = true
        self:TriggerEffects("blink_out", {effecthostcoords = Coords.GetTranslation(self:GetOrigin())})
    end
end

function Vokex:GetHasDoubleJumped()
    return self.hasDoubleJumped
end

-- Combat Enhancer: a held Shadow Step runs along the ground, so it climbs stairs and small ledges like normal movement
-- (it was blocked during the old 0.2 s dash).
function Vokex:GetCanStep()
    return true
end

function Vokex:ModifyGravityForce(gravityTable)

    -- Combat Enhancer: normal gravity while Shadow Stepping (user 2026-10-13), except while jump is HELD during the step:
    -- then gravity is balanced out and the Vokex climbs at a steady speed (Vokex:ModifyVelocity sets xmenuShadowClimb
    -- earlier in the same move).
    if self:GetIsOnGround() or (self.xmenuShadowClimb and self:GetIsShadowStepping()) then
        gravityTable.gravity = 0
    end

end

--[[
    Combat Enhancer: while Shadow Stepping the step sets the horizontal velocity outright every move (Vokex:ModifyVelocity),
    so the direction snaps to the movement keys at once. The movement code's own acceleration, air steering (air
    control / forward control) and falling speed boost are switched off for the step - they ran AFTER the step's velocity
    and tugged it around every frame, which made the step feel janky and added speed.
]]
function Vokex:GetAcceleration()
    if self:GetIsShadowStepping() then
        return 0
    end
    return 11
end

function Vokex:GetHasFallAccel()
    return not self:GetIsShadowStepping()
end

-- Combat Enhancer: the Vokex stays on the ground while Shadow Stepping (it runs, it does not float), so it can jump and
-- crouch as normal.
function Vokex:OverrideUpdateOnGround(onGround)
    return onGround
end

function Vokex:GetGroundFriction()
    
    if self:GetIsShadowStepping() then
        return 0
    end

    local timeSinceLastEthereal = Shared.GetTime() - Vokex.kShadowStepDuration - self.timeShadowStep
    if timeSinceLastEthereal < Vokex.kGroundFrictionPostBlinkDelay then
        local frac = timeSinceLastEthereal / Vokex.kGroundFrictionPostBlinkDelay
        return Vokex.kGroundFrictionPostBlink + (Vokex.kGroundFrictionBase - Vokex.kGroundFrictionPostBlink) * frac
    end
    return Vokex.kGroundFrictionBase
end  

function Vokex:GetAirControl()
    if self:GetIsShadowStepping() then
        return 0
    end
    return 40
end   

function Vokex:GetAirFriction()


    if self:GetIsShadowStepping() then
        return 0
    end

    --[[
        Combat Enhancer: the Fade's air friction after a Blink (vanilla Fade:GetAirFriction), so a tapped or released
        Shadow Step keeps its momentum in the air and bleeds it off gradually, and bunny-hopping carries speed. It used
        to apply the GROUND friction ramp (3 rising to 9) in the air for 0.25 s after every step, which killed the speed
        the moment the button was let go.
    ]]
    local baseFriction = 0.17
    local fastFriction = 0.40
    local fastSpeed = GetHasCelerityUpgrade(self) and 20.5 or 19
    if self:GetVelocityLength() > fastSpeed then
        return fastFriction
    end

    return baseFriction
end

--[[
    Combat Enhancer: the held Shadow Step's speed. Blink's speed (14), passed through ModifyMaxSpeed exactly as vanilla
    Fade:ModifyVelocity passes Blink's - so whatever raises a Blink's speed raises a Shadow Step's the same way: Celerity,
    and Xmenu2's Hunger and Xmenu2+'s Pheromone Trail (both ModifyMaxSpeed wraps on every alien).
]]
function Vokex:GetShadowStepSpeed(input)
    local speedTable = { maxSpeed = kShadowStepSpeed }
    if self.ModifyMaxSpeed then
        self:ModifyMaxSpeed(speedTable, input)
    end
    -- Never above vanilla's Blink speed cap (Fade.lua kBlinkMaxSpeed, 25), whatever bonuses stack.
    local speed = math.min(kShadowStepMaxSpeed, math.max(kShadowStepSpeed, speedTable.maxSpeed or kShadowStepSpeed))
    return speed * kShadowStepSpeedScale
end

function Vokex:ModifyVelocity(input, velocity, deltaTime)

    --[[
        Combat Enhancer: the held Shadow Step. While stepping, the Vokex's HORIZONTAL velocity is set to a constant
        kShadowStepSpeed (the Fade's Blink speed) in the direction of the movement keys held right now. With no movement
        key held it keeps going the way it was already moving; standing still, it stays still. Vertical velocity is left
        alone, so jumping and falling work as normal.
    ]]
    if self:GetIsShadowStepping() then

        local viewCoords = self:GetViewCoords()
        local direction = viewCoords:TransformVector(input.move)
        direction.y = 0

        if direction:GetLengthSquared() < 0.0001 then
            direction = Vector(velocity.x, 0, velocity.z)
        end

        if direction:GetLengthSquared() > 0.0001 then
            local speed = self:GetShadowStepSpeed(input)
            direction:Normalize()
            velocity.x = direction.x * speed
            velocity.z = direction.z * speed
            self.shadowStepDirection = direction * speed
        end

        --[[
            Jump HELD during a step (user 2026-10-13): gravity is balanced out completely (Vokex:ModifyGravityForce reads
            xmenuShadowClimb) and the Vokex climbs at a steady, modest speed: below kShadowStepClimbSpeed it speeds up by
            kShadowStepClimbAccel a second until it reaches it, and from then on it HOLDS that vertical speed for as long as
            jump is held (a jump that started faster is brought down to it). Combined with the horizontal step, so it
            climbs diagonally in whatever direction it is moving. Let go of jump and gravity takes over again.
        ]]
        self.xmenuShadowClimb = bit.band(input.commands, Move.Jump) ~= 0
        if self.xmenuShadowClimb then
            -- No wait after re-pressing jump (user 2026-10-13): any fall built up while jump was released is cancelled
            -- at once, so the climb starts from level instead of first working off the falling speed.
            if velocity.y < 0 then
                velocity.y = 0
            end
            if velocity.y < kShadowStepClimbSpeed then
                velocity.y = math.min(kShadowStepClimbSpeed, velocity.y + kShadowStepClimbAccel * deltaTime)
            else
                velocity.y = kShadowStepClimbSpeed
            end
        end

    else
        self.xmenuShadowClimb = false
    end

end

-- Combat Enhancer: jumping works the same while Shadow Stepping (normal Vokex jump height and timing).
function Vokex:GetCanJump()
    return Alien.GetCanJump(self) or not self.hasDoubleJumped
end

function Vokex:GetIsShadowStepping()
    return self.shadowStepping
end

function Vokex:GetMaxSpeed(possible)

    if possible then
        return kMaxSpeed
    end

    -- Combat Enhancer: the movement code's speed cap allows the held Shadow Step's constant speed (Vokex:ModifyVelocity
    -- sets it; ModifyMaxSpeed's own bonuses are applied on top of this value by the movement code itself).
    if self:GetIsShadowStepping() then
        return kShadowStepSpeed * kShadowStepSpeedScale
    end

    -- // Take into account crouching.
    return kMaxSpeed
    
end

function Vokex:GetMass()
    return kMass
end

function Vokex:GetJumpHeight()
    return kJumpHeight
end

function Vokex:GetHasShadowStepCooldown()
    return self.timeShadowStep + kShadowStepCooldown > Shared.GetTime()
end

function Vokex:GetMovementSpecialTechId()
    --if self:GetCanMetabolizeHealth() then
    --    return kTechId.MetabolizeHealth
    --else
        return kTechId.MetabolizeEnergy
    --end
end

function Vokex:GetHasMovementSpecial()
    return self:GetHasOneHive()
end

function Vokex:GetMovementSpecialEnergyCost()
    return kVokexShadowStepEnergyCost
end

function Vokex:GetCollisionSlowdownFraction()
    return 0.05
end

function Vokex:TriggerShadowStep()

    self.ethereal = true
    
    
    local weapon = self:GetActiveWeapon()
    local canShadowStep = not weapon or not weapon.GetCanShadowStep or weapon:GetCanShadowStep()

    -- Combat Enhancer: the start of a HELD step - the weapon (ShadowStep.lua) already checked energy and the short
    -- re-press gap, so no cooldown is checked again here. It lasts until Vokex:OnShadowStepEnd.
    if canShadowStep then

        --local velocity = self:GetVelocity()
        self.hasDoubleJumped = false
        self.timeShadowStep = Shared.GetTime()
        self.shadowStepping = true
        
        -- shadowStepDirection is zero-vector until first ModifyVelocity call; Coords.GetLookIn
        -- on a zero vector produces NaN coords and crashes the particle system.
        local stepDir = (self.shadowStepDirection and self.shadowStepDirection:GetLengthSquared() > 0.001)
            and self.shadowStepDirection or self:GetViewCoords().zAxis
        self:TriggerEffects("shadow_step", {effecthostcoords = Coords.GetLookIn(self:GetOrigin(), stepDir)})

        -- /*
        -- if Client and Client.GetLocalPlayer() == self then
        --     self:TriggerFirstPersonMiniBlinkEffect(direction)
        -- end
        -- */
        
        self:TriggerCloak()
    
    end
    
end

function Vokex:OnShadowStepEnd()
    self.ethereal = false
    -- Combat Enhancer: the held step ends here (released, or out of energy). timeShadowStep is moved so the ground
    -- friction ramp after a step (GetGroundFriction / GetAirFriction) and the short re-press gap count from now.
    self.shadowStepping = false
    self.timeShadowStep = Shared.GetTime() - Vokex.kShadowStepDuration
end

function Vokex:GetHasMetabolizeAnimationDelay()
    return self.timeMetabolize + kMetabolizeAnimationDelay > Shared.GetTime()
end

--function Vokex:GetCanMetabolizeHealth()
--    return GetHasTech(self,kTechId.MetabolizeHealth)
--end

function Vokex:OnProcessMove(input)

    Alien.OnProcessMove(self, input)
    
    if Server then

        if self.isScanned and self.timeLastScan + kVokexScanDuration < Shared.GetTime() then
            self.isScanned = false
        end

        -- Bot AI: grant AcidRocket (the Vokex's ranged weapon) once it is unlocked by
        -- Biomass (kTechId.AcidRocket <- kTechId.BioMassFive). Human Vokex buy it via the
        -- Vokex menu; bots do not use menus, so give it directly when the tech is
        -- available. Checked periodically (not every tick) and never force-switched to.
        if self:GetIsVirtual() and AcidRocket and (not self.tehNextAcidCheck or Shared.GetTime() >= self.tehNextAcidCheck) then
            self.tehNextAcidCheck = Shared.GetTime() + 2
            if self:GetIsAlive() and not self:GetWeapon(AcidRocket.kMapName) and GetHasTech(self, kTechId.AcidRocket) then
                self:GiveItem(AcidRocket.kMapName, false)
            end
        end

    end

    if not self:GetHasMetabolizeAnimationDelay() and self.previousweapon ~= nil then

        if self:GetActiveWeapon():GetMapName() == MetabolizeShadowStep.kMapName then
            self:SetActiveWeapon(self.previousweapon)
        end

        self.previousweapon = nil
    end
end

function Vokex:GetShadowStepAllowed()
    return not self:GetHasShadowStepCooldown()
end

function Vokex:GetStepHeight()

    if self:GetIsShadowStepping() then
        return 2
    end
    
    return Player.GetStepHeight(self)
    
end

function Vokex:OnScan()

    if Server then
    
        self.timeLastScan = Shared.GetTime()
        self.isScanned = true
        
    end
    
end

function Vokex:SetDetected(state)

    if Server then
    
        if state then
        
            self.timeLastScan = Shared.GetTime()
            self.isScanned = true
            
        else
            self.isScanned = false
        end
        
    end
    
end

function Vokex:GetIsStabbing()
    local stabWeapon = self:GetWeapon(VortexShadowStep.kMapName)
    return stabWeapon and stabWeapon:GetIsStabbing()
end

function Vokex:OnUpdateAnimationInput(modelMixin)

    if not self:GetHasMetabolizeAnimationDelay() then
        Alien.OnUpdateAnimationInput(self, modelMixin)

        if self.timeOfLastPhase + 0.5 > Shared.GetTime() then
            modelMixin:SetAnimationInput("move", "teleport")
        end
    else
        local weapon = self:GetActiveWeapon()
        if weapon ~= nil and weapon.OnUpdateAnimationInput and weapon:GetMapName() == MetabolizeShadowStep.kMapName then
            weapon:OnUpdateAnimationInput(modelMixin)
        end
    end
    return
end

-- Combat Enhancer: Shadow Step is held, not a timed dash - shadowStepping is set by Vokex:TriggerShadowStep and cleared by
-- Vokex:OnShadowStepEnd (the weapon, ShadowStep.lua), no longer recomputed from a fixed duration here.
function Vokex:PreUpdateMove(input, runningPrediction)
end


function Vokex:GetEngagementPointOverride()
    return self:GetOrigin() + Vector(0, 0.8, 0)
end


function Vokex:OverrideVelocityGoal(velocityGoal)
    
    if not self:GetIsOnGround() and self:GetCrouching() then
        velocityGoal:Scale(0)
    end
    
end

function Vokex:OnGroundChanged(onGround, impactForce, normal, velocity)

    Alien.OnGroundChanged(self, onGround, impactForce, normal, velocity)

    if onGround then
        self.hasDoubleJumped = false

        -- Combat Enhancer: as Fade:OnGroundChanged - tell a bot's brain it has landed, so it queues its next jump in
        -- the Shadow Step -> Jump -> Jump sequence (lua/Xmenu2/Bot_Fixes/VokexBrain_Data.lua).
        local client = self.GetClient and self:GetClient()
        if Server and self:GetIsAlive() and client and client:GetIsVirtual() then
            local bot = client.bot
            local brain = bot and bot.brain
            if brain and brain.OnGroundLanded then
                brain:OnGroundLanded()
            end
        end
    end

end

function Vokex:GetMovementSpecialCooldown()
    local cooldown = 0
    local timeLeft = (Shared.GetTime() - self.timeMetabolize)
    
    local metabolizeWeapon = self:GetWeapon(MetabolizeShadowStep.kMapName)
    local metaDelay = metabolizeWeapon and metabolizeWeapon:GetAttackDelay() or 0
    if timeLeft < metaDelay then
        return Clamp(timeLeft / metaDelay, 0, 1)
    end
    
    return cooldown
end

function Vokex:GetAdrenalineEnergyRechargeRate()
    return Vokex.kAdrenalineEnergyRecuperationRate
end

function Vokex:GetBaseCarapaceArmorBuff()
    return kVokexBaseCarapaceUpgradeAmount
end

function Vokex:GetCarapaceBonusPerBiomass()
    return kVokexCarapaceArmorPerBiomass
end

local kDefaultAttackSpeed = 1
function Vokex:OnUpdateAnimationInput(modelMixin)

    Player.OnUpdateAnimationInput(self, modelMixin)

    -- Server has the authoritative primal flag; the client reads the
    -- networked window from PrimalScreamFX.lua (the mixin field never syncs).
    local isPrimal
    if Server then
        isPrimal = self.enzymeIsFromPrimalScream == true
    elseif GetIsClientPrimalScreamed then
        isPrimal = GetIsClientPrimalScreamed(self:GetId())
    else
        isPrimal = false
    end

    local attackSpeed = kDefaultAttackSpeed
    if self.GetIsEnzymed and self:GetIsEnzymed() then
        if isPrimal then
            -- PrimalScream is exactly 50% of the enzyme attack-speed boost.
            local kPrimalScreamFraction = 0.5
            local enzymeBoost = (kEnzymeAttackSpeed - kDefaultAttackSpeed)
            attackSpeed = kDefaultAttackSpeed + enzymeBoost * kPrimalScreamFraction
        else
            attackSpeed = kEnzymeAttackSpeed
        end
    end
    attackSpeed = attackSpeed * ( self.electrified and kElectrifiedAttackSpeed or 1 )
    if self.ModifyAttackSpeed then

        local attackSpeedTable = { attackSpeed = attackSpeed }
        self:ModifyAttackSpeed(attackSpeedTable)
        attackSpeed = attackSpeedTable.attackSpeed

    end

    modelMixin:SetAnimationInput("attack_speed", attackSpeed)

    local activeWeapon = self:GetActiveWeapon()
    if activeWeapon and activeWeapon.ModifyAttackSpeedView then
        local attackSpeedTable = { attackSpeed = attackSpeed }
        activeWeapon:ModifyAttackSpeedView(attackSpeedTable)
        attackSpeed = attackSpeedTable.attackSpeed
    end
    modelMixin:SetAnimationInput("attack_speed_view", attackSpeed)

end

Shared.LinkClassToMap("Vokex", Vokex.kMapName, networkVars, true)