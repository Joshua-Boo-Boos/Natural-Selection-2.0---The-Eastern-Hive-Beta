-- ======= Copyright (c) 2012, Unknown Worlds Entertainment, Inc. All rights reserved. =============
--
-- lua\AutoWeldMixin.lua
--
--    Created by:   Trevor Harris (trevor@naturalselection2.com)
--
--    Mixin for automatically welding armor when not in combat.
--
-- ========= For more information, visit us at http://www.unknownworlds.com ========================

AutoWeldMixin = CreateMixin(AutoWeldMixin)
AutoWeldMixin.type = "AutoWeld"

--AutoWeldMixin.kWeldArmorPerSecond = 8
AutoWeldMixin.kWeldInterval = 0.2 -- weld hits 5x per second.
AutoWeldMixin.kRegenInterval = 0.5
-- Delay (seconds) after last taking damage before over-time HP regen begins.
-- This is the PREVIOUS behaviour's delay (the combat timeout, kCombatTimeOut = 3s)
-- PLUS 2 seconds = 5s total. Regen also still requires being out of combat (see
-- SharedUpdate). Applies to Marine/JetpackMarine (the only classes with
-- GetAutoHealPerSecond). The DELAY only - tech may still change the heal AMOUNT/cap.
AutoWeldMixin.kHealthRegenDelay = 5

AutoWeldMixin.expectedMixins =
{
    Weldable = "Required to weld self.",
}

AutoWeldMixin.networkVars =
{
}

local function GetIsInCombat_WithoutCombatMixin(self, time)
    local timeLastDamage = self:GetTimeOfLastDamage() or 0
    return time < timeLastDamage + kCombatTimeOut
end

local function ResetTimer(self)
    local now = Shared.GetTime()
    self.timeNextWeld = now + AutoWeldMixin.kWeldInterval
    self.timeNextSustain =  now + AutoWeldMixin.kRegenInterval
end

function AutoWeldMixin:__initmixin()

    PROFILE("AutoWeldMixin:__initmixin")

    if Server then
        ResetTimer(self)
        self.armorRegenStack = 0

        -- Use combat mixin if we can find it, otherwise just use LiveMixin's GetTimeOfLastDamage()
        -- method.
        -- NOTE: The InitMixin() call for AutoWeldMixin should come AFTER the InitMixin() for
        -- CombatMixin, otherwise it won't be able to use it.
        if HasMixin(self, "Combat") then
            self.__GetIsInCombatForAutoRepair = CombatMixin.GetIsUnderFire
        else
            self.__GetIsInCombatForAutoRepair = GetIsInCombat_WithoutCombatMixin
        end

    end

end

if Server then

    local function SharedUpdate(self)

        local now = Shared.GetTime()

        -- Armor auto-weld: unchanged - suppressed for the full combat timeout.
        local inCombat = self:__GetIsInCombatForAutoRepair(now)

        if not inCombat and now > self.timeNextWeld then
            self.timeNextWeld = now + AutoWeldMixin.kWeldInterval

            local armorRegen = self:GetAutoWeldArmorPerSecond(GetHasTech(self, kTechId.ArmorRegen))

            if self.armorRegenStack > 0  then
                self.armorRegenStack = math.max(0, self.armorRegenStack - kMarineArmorDeductRegen * AutoWeldMixin.kWeldInterval)
                armorRegen = armorRegen + kMarineArmorDeductRegen
            end

            if armorRegen > 0 then
                self:OnWeld(self, AutoWeldMixin.kWeldInterval, self, armorRegen)
            end
        end

        -- Over-time HP regen (Marine/JetpackMarine): tops health back up to the regen
        -- cap (~80 HP). Requires being OUT of combat (unchanged condition) AND that
        -- kHealthRegenDelay seconds (previous combat timeout + 2s = 5s) have passed
        -- since the last damage TAKEN. Independent of tech (tech changes the heal
        -- AMOUNT/cap, not this delay).
        if self.GetAutoHealPerSecond then

            local healReady = not inCombat
                and now > (self:GetTimeOfLastDamage() or 0) + AutoWeldMixin.kHealthRegenDelay

            if healReady and now > self.timeNextSustain then
                self.timeNextSustain = now + AutoWeldMixin.kRegenInterval

                local lifeSustainResearched = GetHasTech(self, kTechId.ArmorStation)

                local healthCap = lifeSustainResearched and kLifeSustainMaxCap or kLifeRegenMaxCap

                local healthToRegen = self:GetMaxHealth() * healthCap - self:GetHealth()
                if healthToRegen > 0 then
                    local regenPerSecond = self:GetAutoHealPerSecond(lifeSustainResearched)
                    self:Heal(math.min(AutoWeldMixin.kRegenInterval * regenPerSecond,healthToRegen))
                end
            end
        end

    end

    function AutoWeldMixin:OnProcessMove(input)
        SharedUpdate(self)
    end

    function AutoWeldMixin:OnUpdate(deltaTime)
        SharedUpdate(self)
    end

    function AutoWeldMixin:GetCanSelfWeld()
        return true
    end

    function AutoWeldMixin:DeductArmorWithAutoWeld(amount)
        if self.armorRegenStack > 0 then return end     --Still Regenerating

        amount = math.min(self:GetArmor(),amount)

        ResetTimer(self)
        self.armorRegenStack = self.armorRegenStack + amount

        local engagePoint = HasMixin(self, "Target") and self:GetEngagementPoint() or self:GetOrigin()
        self:TakeDamage(amount, self, nil, engagePoint, nil, amount, 0, kDamageType.ArmorOnly, nil)

    end



end
