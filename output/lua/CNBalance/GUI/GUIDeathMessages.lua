local kCombatInjectorTexture = PrecacheAsset("ui/inventory_icon_combat_injector.dds")

local oldAddMessage = GUIDeathMessages.AddMessage
function GUIDeathMessages:AddMessage(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
    -- Let the base game handle all layout/sizing, then swap the texture for CombatInjector
    oldAddMessage(self, killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)

    if iconIndex == kDeathMessageIcon.CombatInjector then
        local lastMessage = self.messages[#self.messages]
        if lastMessage and lastMessage["Weapon"] then
            lastMessage["Weapon"]:SetTexture(kCombatInjectorTexture)
            lastMessage["Weapon"]:SetTexturePixelCoordinates(0, 0, 128, 64)
        end
    end
end
