-- Motion Tracker inventory-slot icon (bottom HUD weapon bar).
--
-- Approach: resize item.Graphic directly to 80% of the slot and recentre it,
-- then set the texture/colour on the Graphic itself (BI9 pattern).  This is
-- simpler and more reliable than a child GUIItem:
--   • No child/parent alpha-inheritance quirks.
--   • Works correctly with AnimatedGraphicItem.
--   • Size is restored in the else-branch when the slot holds a different weapon.
--
-- MotionTracker_ApplyInventoryIcon is a global so GUIInventoryAfterCN.lua can
-- call it after CNBalance's per-frame alien-slot reset.

local kMotionTrackerTexture = PrecacheAsset("ui/motion_tracker/inventory_icon_motion_tracker.dds")
local kIconWidth  = 128
local kIconHeight = 64
local kIconScale  = 0.8   -- display at 80 % of the slot size

-- Marine blue tint (matches kIconColors[kMarineTeamType] = Color(0.8, 0.96, 1, 1))
local kMTActiveColor   = kIconColors[kMarineTeamType]
local kMTInactiveColor = Color(kMTActiveColor.r * 0.6,
                                kMTActiveColor.g * 0.6,
                                kMTActiveColor.b * 0.6, 0.6)

function MotionTracker_ApplyInventoryIcon(item, isActive, index)
    if not item or not item.Graphic then return end

    -- Texture
    item.Graphic:SetTexture(kMotionTrackerTexture)
    item.Graphic:SetTexturePixelCoordinates(0, 0, kIconWidth, kIconHeight)

    -- Colour: blue tint when active (equipped), grey-dim when inactive
    item.Graphic:SetColor(isActive and kMTActiveColor or kMTInactiveColor)

    -- Resize to 80 % and centre within the slot space.
    -- The base LocalAdjustSlot already set the Graphic's X to
    -- (kItemPadding + kItemSize.x) * (index-1); we add a small X offset to
    -- keep the smaller graphic centred, and shift Y down by the same amount.
    local fw  = GUIInventory.kItemSize.x   -- 96
    local fh  = GUIInventory.kItemSize.y   -- 48
    local w   = fw * kIconScale            -- 76.8
    local h   = fh * kIconScale            -- 38.4
    local offX = (fw - w) * 0.5           -- 9.6
    local offY = (fh - h) * 0.5           -- 4.8
    local baseX = (GUIInventory.kItemPadding + fw) * (index - 1)

    item.Graphic:SetSize(Vector(w, h, 0))
    item.Graphic:SetPosition(Vector(baseX + offX, offY, 0))

    item.teh_mtSized = true
end

local oldLocalAdjust = GUIInventory.LocalAdjustSlot
function GUIInventory:LocalAdjustSlot(index, hudSlot, techId, isActive, resetAnimations, alienStyle)

    oldLocalAdjust(self, index, hudSlot, techId, isActive, resetAnimations, alienStyle)

    local item = self.inventoryIcons[index]
    if not item then return end

    if techId == kTechId.MotionTracker then
        MotionTracker_ApplyInventoryIcon(item, isActive, index)
    elseif item.teh_mtSized then
        -- Restore full slot size; position was already reset by base LocalAdjustSlot.
        item.teh_mtSized = false
        item.Graphic:SetSize(GUIInventory.kItemSize)
    end

end
