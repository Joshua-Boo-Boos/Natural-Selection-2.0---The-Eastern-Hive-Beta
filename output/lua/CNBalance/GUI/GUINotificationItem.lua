--
--local baseInitialize = GUINotificationItem.Initialize
--function GUINotificationItem:Initialize()       --Disable time display due to non-constant research time
--    baseInitialize(self)
--    self.bottomText:SetIsVisible(false)
--end

-- The marine HUD's research notification (left of the screen: the researching bar and the RESEARCH
-- COMPLETE banner) builds its icon from the shared atlas via GetTextureCoordinatesForIcon. Combat
-- Engineers has no atlas cell of its own - its kTechIdToMaterialOffset entry points at the Combat
-- Builder's cell purely as a fallback - so without this it shows the Combat Builder icon.
--
-- This is a SEPARATE widget from the commander's research tray (GUIProduction, patched in its own
-- hook): GUIProduction is only ever created by Commander_Client and GUISpectator, so that one is
-- what a COMMANDER sees, while this is what every marine sees.
local kCombatEngineersIconTexture = PrecacheAsset("ui/combat_engineers/combat_engineers_icon.dds")
local kCombatEngineersIconSize = 100

local baseNotificationInitialize = GUINotificationItem.Initialize

function GUINotificationItem:Initialize()

    baseNotificationInitialize(self)

    -- self.icon and self.techId are both set by the base call. ONLY the texture is swapped - the
    -- size/position offsets and the status colouring the base applies are left alone, so this
    -- notification still animates and tints exactly like every other one.
    if self.techId == kTechId.CombatEngineers and self.icon then
        self.icon:SetTexture(kCombatEngineersIconTexture)
        self.icon:SetTexturePixelCoordinates(0, 0, kCombatEngineersIconSize, kCombatEngineersIconSize)
    end

end
