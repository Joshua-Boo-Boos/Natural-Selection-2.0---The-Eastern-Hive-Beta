-- ======= Copyright (c) 2003-2012, Unknown Worlds Entertainment, Inc. All rights reserved. =====
--
-- lua\Weapons\Alien\Blink.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
-- Blink - Attacking many times in a row will create a cool visual "chain" of attacks,
-- showing the more flavorful animations in sequence. Base class for swipe and vortex,
-- available at tier 2.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/Alien/Ability.lua")

class 'ShadowStep' (Ability)

ShadowStep.kMapName = "shadowstep"

-- Boost added when player blinks again in the same direction. The added benefit exact.
local kEtherealBoost = 0.833
local kEtherealVerticalForce = 2

local networkVars =
{
}

function ShadowStep:OnInitialized()

    Ability.OnInitialized(self)
    
    self.timeBlinkStarted = 0

    self.secondaryAttacking = false
end

--[[
    Combat Enhancer: SHADOW STEP IS HELD, like the Fade's Blink, on the secondary attack of EVERY Vokex weapon (they all
    derive from this class), so it works whichever weapon is out:
      * press secondary attack with more than half Blink's start cost (6 energy): the Vokex goes ethereal and steps - at
        a constant speed in the direction of the held movement keys (Vokex:ModifyVelocity);
      * held: it costs energy at Blink's full rate (32 a second), after Blink's 0.08 s grace;
      * a TAP works too: the Vokex is at full step speed for the tap, then keeps that momentum and slows in the air
        like a Fade after a Blink (Vokex:GetAirFriction), so tapping and bunny-hopping carry speed;
      * released, or out of energy: the step ends. Out of energy, it does not start again until the button is released
        and pressed again (Blink's own rule) - the latch is kept on the PLAYER, so switching weapon mid-step changes
        nothing;
      * jumping and crouching work as normal during a step.
    Energy taken for the step is marked (player.xmenuShadowStepCharge) while it is deducted, so Xmenu2's Sense of
    Ancients (Blink energy discount) can tell it apart from attacks.
]]
-- Half of Blink's START cost (user 2026-10-12: 6, so taps are cheap) but Blink's full HELD drain, 32 a second (user
-- 2026-10-13: half the drain was far too little while held, even with Adrenaline).
-- Siege: CE's exact values (6 / 32), not the formula - Siege's own Blink costs are lower (11 / 30, Balance.lua), and the
-- Shadow Step should feel the same as in Combat Enhancer.
local kStartShadowStepEnergyCost = 6
local kShadowStepEnergyPerSecond = 32
local kShadowStepEnergyGrace = 0.08

local function DeductShadowStepEnergy(player, amount)
    player.xmenuShadowStepCharge = true
    local ok, err = pcall(player.DeductAbilityEnergy, player, amount)
    player.xmenuShadowStepCharge = nil
    if not ok then error(err, 0) end
end

-- Holstering (a weapon switch, Metabolize) does NOT end a held step: the step belongs to the player, and the next weapon
-- (also a ShadowStep) carries it on.
function ShadowStep:OnHolster(player)

    Ability.OnHolster(self, player)

end

function ShadowStep:GetHasSecondary(player)
    return true
end

function ShadowStep:GetSecondaryAttackRequiresPress()
    return false
end

local function TriggerBlinkOutEffects(self, player)

    -- Play particle effect at vanishing position.
    if not Shared.GetIsRunningPrediction() then
    
        player:TriggerEffects("blink_out", {effecthostcoords = Coords.GetTranslation(player:GetOrigin())})
        
        if Client and player:GetIsLocalPlayer() and not player:GetIsThirdPerson() then
            player:TriggerEffects("blink_out_local", { effecthostcoords = Coords.GetTranslation(player:GetOrigin()) })
        end
        
    end
    
end

local function TriggerBlinkInEffects(self, player)

    if not Shared.GetIsRunningPrediction() then
        player:TriggerEffects("blink_in", { effecthostcoords = Coords.GetTranslation(player:GetOrigin()) })
    end
    
end

function ShadowStep:GetIsShadowStepping()

    local player = self:GetParent()
    
    if player then
        return player:GetIsShadowStepping()
    end
    
    return false
    
end

function ShadowStep:GetPrimaryAttackAllowed()
    return true
end

function ShadowStep:GetSecondaryEnergyCost()
    return kStartShadowStepEnergyCost
end

function ShadowStep:OnSecondaryAttack(player)

    --[[
        Start on a FRESH PRESS only: never restart while still held after running out.

        NS2.0-TEH / Siege: no new network variables (these mods are at the engine's networking limit). CE keeps its own
        networked latch; here the fresh press is read from the player's input state (secondary NOT held last frame -
        Player:GetSecondaryAttackLastFrame, rebuilt from the move input itself, so client prediction and the server agree),
        and the step's start time goes in the Vokex's existing networked etherealStartTime, unused since the old dash.
    ]]
    local freshPress = not (player.GetSecondaryAttackLastFrame and player:GetSecondaryAttackLastFrame())
    if freshPress and not player.ethereal then

        local allowed = not player.GetShadowStepAllowed or player:GetShadowStepAllowed()
        if allowed and player:GetEnergy() > kStartShadowStepEnergyCost then
            self:SetEthereal(player, true)
            player.etherealStartTime = Shared.GetTime()
        end

    end

    Ability.OnSecondaryAttack(self, player)
end

function ShadowStep:OnSecondaryAttackEnd(player)

    if player.ethereal then
        self:SetEthereal(player, false)
    end

    Ability.OnSecondaryAttackEnd(self, player)
end

function ShadowStep:ProcessMoveOnWeapon(player, input)

    if not player.ethereal then return end

    -- Held: Blink's energy drain, after its short grace so every step lasts at least a moment.
    if Shared.GetTime() > (player.etherealStartTime or 0) + kShadowStepEnergyGrace then
        DeductShadowStepEnergy(player, input.time * kShadowStepEnergyPerSecond)
    end

    -- Out of energy, or dead: the step ends (and stays ended until the button is pressed again).
    if player:GetEnergy() <= 0 or not player:GetIsAlive() then
        self:SetEthereal(player, false)
    end

end


function ShadowStep:SetEthereal(player, state)

    -- Enter or leave ethereal mode.
    if player.ethereal ~= state then
    
        if state then

            TriggerBlinkOutEffects(self, player)

            -- (Combat Enhancer: no forced lift-off. The Fade's Blink marks itself off the ground here; a Shadow Step runs
            -- along the ground, and forcing "in the air" on every tap dropped the Vokex for a frame and gave it the
            -- landing slowdown each time - the tap jank.)

        else
        
            TriggerBlinkInEffects(self, player)
            player.etherealEndTime = Shared.GetTime()
            
        end

        player.ethereal = state

        -- Give player initial velocity in direction we're pressing, or forward if not pressing anything.
        if player.ethereal then
        
            -- Deduct the step's start energy (Blink's start cost).
            DeductShadowStepEnergy(player, kStartShadowStepEnergyCost)
            player:TriggerShadowStep()
            
        -- A case where OnBlinkEnd() does not exist is when a Fade becomes Commanders and
        -- then a new ability becomes available through research which calls AddWeapon()
        -- which calls OnHolster() which calls this function. The Commander doesn't have
        -- a OnBlinkEnd() function but the new ability is still added to the Commander for
        -- when they log out and become a Fade again.
        elseif player.OnShadowStepEnd then
            player:OnShadowStepEnd()
        end
    end
end

function ShadowStep:OnUpdateAnimationInput(modelMixin)

    --local player = self:GetParent()
    --if self:GetIsShadowStepping() and (not self.GetHasMetabolizeAnimationDelay or not self:GetHasMetabolizeAnimationDelay()) then
    --    modelMixin:SetAnimationInput("move", "blink")
    --end
    
end

Shared.LinkClassToMap("ShadowStep", ShadowStep.kMapName, networkVars)
