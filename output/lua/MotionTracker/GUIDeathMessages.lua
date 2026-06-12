
local kKillHighlight = PrecacheAsset("ui/killfeed_highlight.dds")
local kKillLeftBorderCoords = { 0, 0, 15, 64 }
local kKillMiddleBorderCoords = { 16, 0, 112, 64 }
local kKillRightBorderCoords = { 113, 0, 128, 64 }
local kFontName = Fonts.kAgencyFB_Small
local kBackgroundHeight = GUIScale(32)
local kScreenOffset = GUIScale(40)
local kScreenOffsetX = GUIScale(38)

local kMotionTrackerTexture = PrecacheAsset("ui/motion_tracker/inventory_icon_motion_tracker.dds")

local kSustainTime = 4
local kFadeOutTime = 1

local oldAddMessage = GUIDeathMessages.AddMessage
function GUIDeathMessages:AddMessage(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
	-- Motion Tracker deals no damage, so it never produces a death message and is
	-- no longer registered in kDeathMessageIcon (the value is nil). Guard against a
	-- nil match so a nil iconIndex can never accidentally pick this branch.
	if kDeathMessageIcon.MotionTracker ~= nil and iconIndex == kDeathMessageIcon.MotionTracker then
        self:AddMessageCustom(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer, kMotionTrackerTexture)
    else
		oldAddMessage(self, killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
	end
end

function GUIDeathMessages:AddMessageCustom(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer, iconTexture)

    local xOffset = DeathMsgUI_GetTechOffsetX(iconIndex)
    local yOffset = DeathMsgUI_GetTechOffsetY(iconIndex)
    local iconWidth = DeathMsgUI_GetTechWidth(iconIndex)
    local iconHeight = DeathMsgUI_GetTechHeight(iconIndex)
    
    local insertMessage = { Background = nil, Killer = nil, Weapon = nil, Target = nil, Time = 0 }
    
    -- Check if we can reuse an existing message.
    if table.icount(self.reuseMessages) > 0 then
    
        insertMessage = self.reuseMessages[1]
        insertMessage["Time"] = 0
        insertMessage["Background"]:SetIsVisible(self.visible)
        table.remove(self.reuseMessages, 1)
        
    end
    
    if insertMessage["Killer"] == nil then
        insertMessage["Killer"] = GUIManager:CreateTextItem()
    end
    
    insertMessage["Killer"]:SetFontName(kFontName)
    insertMessage["Killer"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    insertMessage["Killer"]:SetTextAlignmentX(GUIItem.Align_Max)
    insertMessage["Killer"]:SetTextAlignmentY(GUIItem.Align_Center)
    insertMessage["Killer"]:SetColor(ColorIntToColor(killerColor))
    insertMessage["Killer"]:SetText(killerName .. " ")
    insertMessage["Killer"]:SetScale(GetScaledVector()*self.scale)
    GUIMakeFontScale(insertMessage["Killer"])
    
    if insertMessage["Weapon"] == nil then
        insertMessage["Weapon"] = GUIManager:CreateGraphicItem()
    end
    
    local scaledIconHeight = kBackgroundHeight - GUIScale(4)
    -- Preserve aspect ratio
    local scaledIconWidth = GUIScale(iconWidth)/(GUIScale(iconHeight)/scaledIconHeight)
    
    insertMessage["Weapon"]:SetSize(Vector(scaledIconWidth, scaledIconHeight, 0))
    insertMessage["Weapon"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    insertMessage["Weapon"]:SetTexture(iconTexture)
    insertMessage["Weapon"]:SetTexturePixelCoordinates(xOffset, yOffset, xOffset + iconWidth, yOffset + iconHeight)
    insertMessage["Weapon"]:SetColor(Color(1, 1, 1, 1))
    
    if insertMessage["Target"] == nil then
        insertMessage["Target"] = GUIManager:CreateTextItem()
    end
    
    insertMessage["Target"]:SetFontName(kFontName)
    insertMessage["Target"]:SetAnchor(GUIItem.Right, GUIItem.Center)
    insertMessage["Target"]:SetTextAlignmentX(GUIItem.Align_Min)
    insertMessage["Target"]:SetTextAlignmentY(GUIItem.Align_Center)
    insertMessage["Target"]:SetColor(ColorIntToColor(targetColor))
    insertMessage["Target"]:SetText(" " .. targetName)
    insertMessage["Target"]:SetScale(GetScaledVector()*self.scale)
    GUIMakeFontScale(insertMessage["Target"])
    
    local killerTextWidth = insertMessage["Killer"]:GetTextWidth(killerName .. " ") * insertMessage["Killer"]:GetScale().x
    local targetTextWidth = insertMessage["Target"]:GetTextWidth(targetName .. " ") * insertMessage["Target"]:GetScale().x
    local textWidth = killerTextWidth + targetTextWidth
    
    insertMessage["Weapon"]:SetPosition(Vector(killerTextWidth, -scaledIconHeight / 2, 0))
    
    if insertMessage["Background"] == nil then
    
        insertMessage["Background"] = GUIManager:CreateGraphicItem()
        insertMessage["Background"]:SetLayer(kGUILayerPlayerHUD)
        insertMessage["Background"].left = GUIManager:CreateGraphicItem()
        insertMessage["Background"].left:SetAnchor(GUIItem.Left, GUIItem.Top)
        insertMessage["Background"].right = GUIManager:CreateGraphicItem()
        insertMessage["Background"].right:SetAnchor(GUIItem.Right, GUIItem.Top)
        insertMessage["Background"]:AddChild(insertMessage["Background"].right)
        insertMessage["Background"]:AddChild(insertMessage["Background"].left)
        insertMessage["Weapon"]:AddChild(insertMessage["Killer"])
        insertMessage["Background"]:AddChild(insertMessage["Weapon"])
        insertMessage["Weapon"]:AddChild(insertMessage["Target"])
        self.anchor:AddChild(insertMessage["Background"])
        
    end

    local player = Client.GetLocalPlayer()
    local backgroundColor = ConditionalValue(GUIDeathMessages.kKillfeedCustomColorEnabled, GUIDeathMessages.kKillfeedCustomColor, ColorIntToColor(killerColor))
    backgroundColor.a = ConditionalValue(player and GUIDeathMessages.kKillfeedHighlightEnabled and Client.GetIsControllingPlayer() and player:GetName() == killerName and targetIsPlayer and killerColor ~= targetColor, 1, 0)
    
    insertMessage["BackgroundWidth"] = textWidth + scaledIconWidth
    insertMessage["Background"]:SetSize(Vector(insertMessage["BackgroundWidth"], kBackgroundHeight, 0))
    insertMessage["Background"]:SetAnchor(GUIItem.Right, GUIItem.Top)
    insertMessage["BackgroundXOffset"] = -textWidth - scaledIconWidth - kScreenOffset - kScreenOffsetX
    insertMessage["Background"]:SetPosition(Vector(insertMessage["BackgroundXOffset"], 0, 0))
    insertMessage["Background"]:SetColor(backgroundColor)
    insertMessage["Background"]:SetTexture(kKillHighlight)
    insertMessage["Background"]:SetTexturePixelCoordinates(GUIUnpackCoords(kKillMiddleBorderCoords))

    insertMessage["Background"].left:SetColor(backgroundColor)
    insertMessage["Background"].left:SetTexture(kKillHighlight)
    insertMessage["Background"].left:SetTexturePixelCoordinates(GUIUnpackCoords(kKillLeftBorderCoords))
    insertMessage["Background"].left:SetSize(Vector(GUIScale(8), kBackgroundHeight, 0))
    insertMessage["Background"].left:SetInheritsParentAlpha(true)
    insertMessage["Background"].left:SetPosition(Vector(-GUIScale(8), 0, 0))

    insertMessage["Background"].right:SetColor(backgroundColor)
    insertMessage["Background"].right:SetTexture(kKillHighlight)
    insertMessage["Background"].right:SetTexturePixelCoordinates(GUIUnpackCoords(kKillRightBorderCoords))
    insertMessage["Background"].right:SetSize(Vector(GUIScale(8), kBackgroundHeight, 0))
    insertMessage["Background"].right:SetInheritsParentAlpha(true)
    insertMessage.sustainTime = kSustainTime
    
    table.insert(self.messages, insertMessage)
    
end