-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIDeathMessagesLeap.lua =======
--
-- Post-hook on lua/GUIDeathMessages.lua.
--
-- Leap-impact kills (CNBalance/Lifeforms/Skulk.lua) use kDeathMessageIcon.Leap as
-- their killfeed icon. By default that icon is drawn from the standard vertical
-- icon-strip texture (ui/inventory_icons.dds, one icon per "row"). The user wants
-- the killfeed to instead show the SAME Leap icon used in the tech tree at
-- Biomass 4 (ui/buildmenu.dds, a 12-column grid of 80x80 cells, looked up via
-- kTechIdToMaterialOffset[kTechId.Leap] / GetMaterialXYOffset).
--
-- DeathMsgUI_GetTechOffsetX/Y/Width/Height (globals from lua/DeathMessage_Client.lua)
-- compute the icon's pixel rect for GUIDeathMessages:AddMessage / AddMessageCustom
-- (the MotionTracker plugin's custom-icon variant, CNBalance loads after
-- MotionTracker). Overriding them for the Leap case — and routing Leap kills
-- through AddMessageCustom with the buildmenu.dds texture — reuses all of the
-- existing killfeed layout code unchanged.

local kBuildMenuTexture  = PrecacheAsset("ui/buildmenu.dds")
local kBuildMenuCellSize = 80

local baseGetTechOffsetX = DeathMsgUI_GetTechOffsetX
function DeathMsgUI_GetTechOffsetX(iconIndex)
    if iconIndex == kDeathMessageIcon.Leap then
        local gridX = GetMaterialXYOffset(kTechId.Leap)
        if gridX then
            return gridX * kBuildMenuCellSize
        end
    end
    return baseGetTechOffsetX(iconIndex)
end

local baseGetTechOffsetY = DeathMsgUI_GetTechOffsetY
function DeathMsgUI_GetTechOffsetY(iconIndex)
    if iconIndex == kDeathMessageIcon.Leap then
        local _, gridY = GetMaterialXYOffset(kTechId.Leap)
        if gridY then
            return gridY * kBuildMenuCellSize
        end
    end
    return baseGetTechOffsetY(iconIndex)
end

local baseGetTechWidth = DeathMsgUI_GetTechWidth
function DeathMsgUI_GetTechWidth(iconIndex)
    if iconIndex == kDeathMessageIcon.Leap then
        return kBuildMenuCellSize
    end
    return baseGetTechWidth(iconIndex)
end

local baseGetTechHeight = DeathMsgUI_GetTechHeight
function DeathMsgUI_GetTechHeight(iconIndex)
    if iconIndex == kDeathMessageIcon.Leap then
        return kBuildMenuCellSize
    end
    return baseGetTechHeight(iconIndex)
end

local baseAddMessage = GUIDeathMessages.AddMessage
function GUIDeathMessages:AddMessage(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
    if iconIndex == kDeathMessageIcon.Leap and self.AddMessageCustom then
        self:AddMessageCustom(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer, kBuildMenuTexture)
        return
    end
    baseAddMessage(self, killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
end
