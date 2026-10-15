--[[
    BMAC character: JetpackMarine. Post-hook on JetpackMarine.lua, AFTER CNBalance/JetpackMarine.lua,
    which gives JetpackMarine its own GetArmorAmount and GetAutoHealPerSecond (so Marine's wraps in
    BMAC_Marine.lua don't reach it). A Jetpacker stays a BMAC.
]]

local baseGetArmorAmount = JetpackMarine.GetArmorAmount
function JetpackMarine:GetArmorAmount(armorLevels)
    local amount = baseGetArmorAmount(self, armorLevels)
    if GetIsBMACMarine(self) then
        amount = amount + kBMACBonusArmor
    end
    return amount
end

if Server then

    local baseGetAutoHealPerSecond = JetpackMarine.GetAutoHealPerSecond
    function JetpackMarine:GetAutoHealPerSecond(lifeSustainResearched)
        if GetIsBMACMarine(self) then
            return 0
        end
        return baseGetAutoHealPerSecond(self, lifeSustainResearched)
    end

end
