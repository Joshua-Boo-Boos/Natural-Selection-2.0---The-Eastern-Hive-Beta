--[[
    BMAC character: Marine behaviour. Post-hook on Marine.lua, AFTER CNBalance/Marine.lua (whose
    GetArmorAmount/GetAutoHealPerSecond these wrap). GetIsBMACMarine is in BMAC_Shared.lua.
    Everything delegates to the existing behaviour for anyone who is not a BMAC.
]]

-- +kBMACBonusArmor (the 100 HP as 50 AP) on top of the normal armour (armour levels, Nano Armour), once.
local baseGetArmorAmount = Marine.GetArmorAmount
function Marine:GetArmorAmount(armorLevels)
    local amount = baseGetArmorAmount(self, armorLevels)
    if GetIsBMACMarine(self) then
        amount = amount + kBMACBonusArmor
    end
    return amount
end

-- All damage comes off AP (Exo: kExosuitArmorUseFraction = 1).
local baseGetArmorUseFractionOverride = Marine.GetArmorUseFractionOverride
function Marine:GetArmorUseFractionOverride(damageType, armorFractionUsed, hitPoint)
    if GetIsBMACMarine(self) then
        return 1
    end
    if baseGetArmorUseFractionOverride then
        return baseGetArmorUseFractionOverride(self, damageType, armorFractionUsed, hitPoint)
    end
    return armorFractionUsed
end

-- LiveMixin reports 0 for an armour-only body, which made bot logic (retreat, find medpack, Commander
-- med drops) treat a full-AP BMAC as nearly dead. For a BMAC its AP is its health, so report that.
-- SERVER ONLY (bots run there): on the client the unit-status bar reads GetHealthFraction for its red
-- health section, and an armour-only body must show none there, exactly like an Exo (0).
-- (Defined on the class: the mixin merge returns the class function's result.)
if Server then
    function Marine:GetHealthFraction()
        if GetIsBMACMarine(self) then
            local maxArmor = self:GetMaxArmor()
            return maxArmor > 0 and Clamp(self:GetArmor() / maxArmor, 0, 1) or 0
        end
        return LiveMixin.GetHealthFraction(self)
    end
end

-- Spores (gas) and biological damage don't affect a BMAC, as for an Exo.
local baseGetReceivesVaporousDamage = Marine.GetReceivesVaporousDamage
function Marine:GetReceivesVaporousDamage(damageType)
    if GetIsBMACMarine(self) then
        return false
    end
    return baseGetReceivesVaporousDamage(self, damageType)
end

local baseGetReceivesBiologicalDamage = Marine.GetReceivesBiologicalDamage
function Marine:GetReceivesBiologicalDamage(damageType)
    if GetIsBMACMarine(self) then
        return false
    end
    return baseGetReceivesBiologicalDamage(self, damageType)
end

-- Can't be ignited (no burn over time). Flame hit damage is applied before ignition and still lands.
local baseOnOverrideCanSetFire = Marine.OnOverrideCanSetFire
function Marine:OnOverrideCanSetFire()
    if GetIsBMACMarine(self) then
        return false
    end
    if baseOnOverrideCanSetFire then
        return baseOnOverrideCanSetFire(self)
    end
    return true
end

-- Stun immune (StunMixin consults this; JetpackMarine's version calls Marine.GetIsStunAllowed).
local baseGetIsStunAllowed = Marine.GetIsStunAllowed
function Marine:GetIsStunAllowed()
    if GetIsBMACMarine(self) then
        return false
    end
    if baseGetIsStunAllowed then
        return baseGetIsStunAllowed(self)
    end
    return true
end

if Server then

    -- Baseline health regeneration and Life Sustain don't apply (AutoWeldMixin's health branch).
    -- Nano Armour is the separate armour branch (GetAutoWeldArmorPerSecond) and is untouched.
    local baseGetAutoHealPerSecond = Marine.GetAutoHealPerSecond
    function Marine:GetAutoHealPerSecond(lifeSustainResearched)
        if GetIsBMACMarine(self) then
            return 0
        end
        return baseGetAutoHealPerSecond(self, lifeSustainResearched)
    end

    -- Lerk bite poison doesn't affect a BMAC. Its damage is "health only", which LiveMixin turns into
    -- AP damage for an armour-only body, and its "never kill" check reads the (always full) ignored
    -- health - so on a BMAC it could drain AP to death. The bite itself still hits AP normally.
    local baseSetPoisoned = Marine.SetPoisoned
    if baseSetPoisoned then
        function Marine:SetPoisoned(attacker)
            if GetIsBMACMarine(self) then
                return
            end
            return baseSetPoisoned(self, attacker)
        end
    end

end
