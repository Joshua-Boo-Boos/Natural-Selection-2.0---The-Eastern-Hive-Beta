-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\CNBalance\Weapons\Alien\PrimalScream.lua
--
--    Lerk-cast AoE buff. Applies a half-strength enzyme effect (drives the
--    same machinery as real enzyme — shader, HUD timer, attack-speed path —
--    but the attack-speed delta is halved) to every OTHER alien-team script
--    actor in range that can be enzymed. The caster is NOT affected (no
--    shader/icon/buff); the caster only plays the cast scream sound. Targets
--    already under real enzyme are skipped (real enzyme wins). Each affected
--    target plays the "received" sound (handled in PrimalScreamMixin).
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/Alien/Ability.lua")

class 'PrimalScream' (Ability)

PrimalScream.kMapName = "primalscream"

local kPrimalRadius     = 10
local kPrimalEnergyCost = 40
local kPrimalCooldown   = 2
local kPrimalDuration   = 4   -- 50% of the previous 8s duration

-- Lerk's Primal Scream ability sound and the receiving sound played by applicable recipients.
local kPrimalScreamCastSound = PrecacheAsset("sound/NS1_Sounds.fev/Lerk/PrimalScream")
local kReceiveSound = PrecacheAsset("sound/NS1_Sounds.fev/Aliens/PrimalScreamReceiving")

-- The volume levels of both Primal Scream sounds
local kPrimalScreamVolume = 0.16
local kPrimalScreamReceivedVolume = 0.16

-- Drive the bite animation on the lerk's first-person view each cast.
local kViewModelName  = PrecacheAsset("models/alien/lerk/lerk_view.model")
local kAnimationGraph = PrecacheAsset("models/alien/lerk/lerk_view.animation_graph")
local kBiteDuration   = Shared.GetAnimationLength(kViewModelName, "bite")
if not kBiteDuration or kBiteDuration <= 0 then
    kBiteDuration = 0.6
end

local networkVars =
{
    primaryAttacking      = "boolean",
    primaryAttackLatched  = "boolean",
    lastPrimalScreamTime  = "time",
}

function PrimalScream:OnCreate()

    Ability.OnCreate(self)

    self.primaryAttacking     = false
    self.primaryAttackLatched = false
    self.lastPrimalScreamTime = 0

end

function PrimalScream:OnInitialized()
    Ability.OnInitialized(self)
end

function PrimalScream:GetAnimationGraphName()
    return kAnimationGraph
end

function PrimalScream:GetEnergyCost()
    return kPrimalEnergyCost
end

function PrimalScream:GetPrimaryEnergyCost()
    return kPrimalEnergyCost
end

function PrimalScream:GetHUDSlot()
    return 4
end

function PrimalScream:GetDeathIconIndex()
    return kDeathMessageIcon.Umbra
end

function PrimalScream:GetPrimaryAttackRequiresPress()
    return true
end

local function GetCanFire(self, player)

    if not player then return false end

    if player:GetEnergy() < kPrimalEnergyCost then
        return false
    end

    if Shared.GetTime() < self.lastPrimalScreamTime + kPrimalCooldown then
        return false
    end

    return true

end

function PrimalScream:OnPrimaryAttack(player)

    if not player then return end

    -- LATCH: once we've fired on this press, refuse to fire again until the
    -- player physically releases the attack key (OnPrimaryAttackEnd). Without
    -- this, fast input ticks (especially the first press, before the network
    -- has rolled forward) can run OnPrimaryAttack multiple times before
    -- lastPrimalScreamTime gates them out.
    if self.primaryAttackLatched then
        return
    end

    -- Held from last frame? Wait for release.
    if player:GetPrimaryAttackLastFrame() then
        return
    end

    if not GetCanFire(self, player) then
        return
    end

    -- Latch and stamp the cooldown BEFORE doing any other work so that any
    -- re-entrant call inside this frame falls through the early-outs above.
    self.primaryAttackLatched   = true
    self.primaryAttacking       = true
    self.lastPrimalScreamTime   = Shared.GetTime()
    self.lastPrimaryAttackTime  = self.lastPrimalScreamTime

    player:DeductAbilityEnergy(kPrimalEnergyCost)

    if Server then

        -- The caster only screams -- it is NOT affected by the buff (no
        -- enzyme shader/icon/attack-speed). Play the cast sound on the lerk.
        StartSoundEffectOnEntity(kPrimalScreamCastSound, player, kPrimalScreamVolume)

        -- Apply the effect to every OTHER valid alien-team script actor in
        -- range: anything that exposes the enzyme state machine (self.enzymed)
        -- and can receive a PrimalScream via the mixin. The caster is skipped.
        -- Targets already under real enzyme are skipped (real enzyme wins).
        for _, entity in ipairs(GetEntitiesForTeamWithinRange("ScriptActor", player:GetTeamNumber(), player:GetOrigin(), kPrimalRadius)) do

            if entity ~= player then

                local canBeEnzymed       = entity.enzymed ~= nil
                local canReceivePrimal   = entity.ApplyPrimalScream ~= nil
                local alreadyRealEnzymed =
                    entity.GetIsEnzymed and entity:GetIsEnzymed()
                    and not entity.enzymeIsFromPrimalScream

                if canBeEnzymed and canReceivePrimal and not alreadyRealEnzymed then
                    entity:ApplyPrimalScream(kPrimalDuration)
                    StartSoundEffectOnEntity(kReceiveSound, entity, kPrimalScreamReceivedVolume)
                end

            end

        end

    end

end

function PrimalScream:OnPrimaryAttackEnd(player)

    Ability.OnPrimaryAttackEnd(self, player)
    self.primaryAttacking     = false
    self.primaryAttackLatched = false

end

function PrimalScream:OnHolster(player)

    Ability.OnHolster(self, player)
    self.primaryAttacking     = false
    self.primaryAttackLatched = false

end

function PrimalScream:OnUpdateAnimationInput(modelMixin)

    PROFILE("PrimalScream:OnUpdateAnimationInput")

    modelMixin:SetAnimationInput("ability", "bite")

    local activityString = "none"
    if self.lastPrimalScreamTime > 0
       and Shared.GetTime() - self.lastPrimalScreamTime < kBiteDuration then
        activityString = "primary"
    end

    modelMixin:SetAnimationInput("activity", activityString)

end

Shared.LinkClassToMap("PrimalScream", PrimalScream.kMapName, networkVars)
