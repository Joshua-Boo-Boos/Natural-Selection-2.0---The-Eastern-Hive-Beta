 
Script.Load("lua/Weapons/Alien/Ability.lua")
Script.Load("lua/Prowler/RappelMixin.lua")


class 'VolleyRappel' (Ability)
VolleyRappel.kMapName = "volley"
VolleyRappel.kStartOffset = -0.5
VolleyRappel.AttackSpeedMod = 0.58 --0.515
VolleyRappel.kKeepCloakWhenSecondary = true
local kAnimationGraph = PrecacheAsset("models/alien/prowler/prowler_view.animation_graph") --PrecacheAsset("models/alien/skulk/skulk_view.animation_graph")
local kVolleyRappelTracer = PrecacheAsset("cinematics/prowler/1p_tracer_residue.cinematic")
local kAttackDuration = Shared.GetAnimationLength("models/alien/prowler/prowler_view.model", "bite_attack") -- 0.23333333432674 / 0.55555 = 0.42
local kAttackDuration2 = Shared.GetAnimationLength("models/alien/prowler/prowler_view.model", "bite_attack2") -- 0.38333332538605
local kAttackDuration3 = Shared.GetAnimationLength("models/alien/prowler/prowler_view.model", "bite_attack3") -- 1.8166667222977
local kAttackDuration4 = Shared.GetAnimationLength("models/alien/prowler/prowler_view.model", "bite_attack4") -- 0.36666667461395

-- Burst-fire parameters: kBurstShotCount shots per click with a short delay between each
local kBurstShotCount = 4
local kBurstShotDelay = 0.15  -- seconds between each burst shot

-- Damage falloff: full damage up close, linear falloff to minimum at range
local kMaxDamagePerShot = 60 / kBurstShotCount
local kMinDamagePerShot = 10 / kBurstShotCount
local kFalloffStartDistance = 4     -- full damage up to this distance
local kFalloffEndDistance = 9       -- minimum damage beyond this distance

local networkVars =
{
    lastAttackedAt = "time",
}

AddMixinNetworkVars(RappelMixin, networkVars)

function VolleyRappel:OnCreate()

    Ability.OnCreate(self)
    InitMixin(self, RappelMixin)
    InitMixin(self, BulletsMixin)
    
    self.primaryAttacking = false
    self.timeDrawCooldown = 0
    self.burstShotsRemaining = 0
    self.nextBurstTime = 0

    self.lastAttackedAt = 0
end

function VolleyRappel:ProcessMoveOnWeapon(player, input)
    self:UpdateBurstFire(player)
    RappelMixin.ProcessMoveOnWeapon(self, player, input)
end
function VolleyRappel:GetAnimationGraphName()
    return kAnimationGraph
end
function VolleyRappel:GetVampiricLeechScalar()
    return kVolleyRappelVampirismScalar
end

function VolleyRappel:GetIsAffectedByFocus()
    return self.primaryAttacking
end

function VolleyRappel:GetMaxFocusBonusDamage()
    return kVolleyFocusDamageBonusAtMax
end

function VolleyRappel:GetFocusAttackCooldown()
    return kVolleyFocusAttackSlowAtMax
end

function VolleyRappel:GetAttackAnimationDuration()
    return kAttackDuration
end
function VolleyRappel:GetTracerEffectName()
    return kVolleyRappelTracer
end
function VolleyRappel:GetTracerResidueEffectName()
    return kVolleyRappelTracer
end

function VolleyRappel:GetDamageForDistance(distance)
    if distance <= kFalloffStartDistance then
        return kMaxDamagePerShot
    elseif distance >= kFalloffEndDistance then
        return kMinDamagePerShot
    else
        local t = (distance - kFalloffStartDistance) / (kFalloffEndDistance - kFalloffStartDistance)
        return kMaxDamagePerShot - t * (kMaxDamagePerShot - kMinDamagePerShot)
    end
end

function VolleyRappel:GetEnergyCost(player)
    return kVolleyEnergyCost
end
function VolleyRappel:GetHUDSlot()
    return 1
end
function VolleyRappel:GetTechId()
    return kTechId.Volley
end
function VolleyRappel:GetRange()
    return 40
end
function VolleyRappel:GetBulletDamage()
    return kMaxDamagePerShot
end

function VolleyRappel:GetBarrelPoint()
    local player = self:GetParent()
    return player:GetEyePos() + Vector(0, -0.25, 0)
end

function VolleyRappel:GetDeathIconIndex()
    if self.primaryAttacking then
        return kDeathMessageIcon.Volley
    else
        return RappelMixin:GetDeathIconIndex()
    end
end

function VolleyRappel:GetDamageType()
    return kVolleyRappelDamageType
end

function VolleyRappel:OnPrimaryAttack(player)
    local hasEnergy = player:GetEnergy() >= self:GetEnergyCost()
    -- local cooledDown = (not self.nextAttackTime) or (Shared.GetTime() >= self.nextAttackTime)
    -- if hasEnergy and cooledDown then
    if hasEnergy and self.lastAttackedAt == 0 and not player:GetPrimaryAttackLastFrame() then
        self.lastAttackedAt = Shared.GetTime()
        self.primaryAttacking = true
    elseif hasEnergy and self.lastAttackedAt and Shared.GetTime() >= self.lastAttackedAt + kBurstShotCount * kBurstShotDelay + 0.05 and not player:GetPrimaryAttackLastFrame() then
        self.lastAttackedAt = Shared.GetTime()
        self.primaryAttacking = true
    else
        self.primaryAttacking = false
    end
    
end
function VolleyRappel:OnPrimaryAttackEnd()
    
    Ability.OnPrimaryAttackEnd(self)
    
    self.primaryAttacking = false
    
end


function VolleyRappel:OnDraw(player, previousWeaponMapName)
    Ability.OnDraw(self, player, previousWeaponMapName)
    self.burstShotsRemaining = 0
    if previousWeaponMapName == ProwlerStructureAbility.kMapName then
        self.timeDrawCooldown = Shared.GetTime() + 0.3
    end
end

function VolleyRappel:OnUpdateAnimationInput(modelMixin)

    PROFILE("VolleyRappel:OnUpdateAnimationInput")
    
    modelMixin:SetAnimationInput("ability", "bite")
    
    local activityString = (self.primaryAttacking and Shared.GetTime() > self.timeDrawCooldown) and "primary" or "none"
    modelMixin:SetAnimationInput("activity", activityString)    
end

-- Fire a single bullet in the player's aim direction with distance-based damage falloff
function VolleyRappel:FireSingleShot(player)

    local viewAngles = player:GetViewAngles()
    local shootCoords = viewAngles:GetCoords()
    local filter = EntityFilterTwo(player, self)
    local range = self:GetRange()
    local startPoint = player:GetEyePos()
    local endPoint = startPoint + shootCoords.zAxis * range

    local targets, trace, hitPoints = GetBulletTargets(startPoint, endPoint, shootCoords.zAxis, 0.1, filter)

    HandleHitregAnalysis(player, startPoint, endPoint, trace)

    local direction = (trace.endPoint - startPoint):GetUnit()
    local hitDistance = (trace.endPoint - startPoint):GetLength()
    local damage = self:GetDamageForDistance(hitDistance)
    local hitOffset = direction * kHitEffectOffset
    local impactPoint = trace.endPoint - hitOffset
    local showTracer = true
    local numTargets = #targets

    if numTargets == 0 then
        self:ApplyBulletGameplayEffects(player, nil, impactPoint, direction, 0, "rock", showTracer)
    end

    if Client and showTracer then
        TriggerFirstPersonTracer(self, impactPoint)
    end

    for i = 1, numTargets do

        local target = targets[i]
        local hitPoint = hitPoints[i]

        self:ApplyBulletGameplayEffects(player, target, hitPoint - hitOffset, direction, damage, "rock", showTracer and i == numTargets)

        if HasMixin(target, "Webable") then
            if target.GetIsOnGround and not target:GetIsOnGround() then
                target:SetWebbed(kVolleyWebTime, true)
            end
        end

        local client = Server and player:GetClient() or Client
        if not Shared.GetIsRunningPrediction() and client and client.hitRegEnabled then
            RegisterHitEvent(player, 1, startPoint, trace, damage)
        end

    end

    if Server then
        self:TriggerEffects("volley_attack")
    end

end

-- Called each frame via ProcessMoveOnWeapon to fire remaining burst shots
function VolleyRappel:UpdateBurstFire(player)
    if self.burstShotsRemaining > 0 and Shared.GetTime() >= self.nextBurstTime then
        if player and IsValid(player) then
            self:FireSingleShot(player)
        end
        self.burstShotsRemaining = self.burstShotsRemaining - 1
        if self.burstShotsRemaining > 0 then
            self.nextBurstTime = Shared.GetTime() + kBurstShotDelay
        end
    end
end

function VolleyRappel:OnTag(tagName)
    PROFILE("VolleyRappel:OnTag")

    if tagName == "hit" then
        local player = self:GetParent()

        if player then
            -- Fire first shot immediately, schedule remaining burst shots
            self:FireSingleShot(player)
            self.burstShotsRemaining = kBurstShotCount - 1
            self.nextBurstTime = Shared.GetTime() + kBurstShotDelay

            self:OnAttack(player)
        end
    end

end

function VolleyRappel:GetSecondaryTechId()
    return kTechId.Rappel
end

Shared.LinkClassToMap("VolleyRappel", VolleyRappel.kMapName, networkVars)