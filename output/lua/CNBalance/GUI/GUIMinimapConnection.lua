-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GUIMinimapConnection.lua  (NS2.0-TEH Beta replacement)
--
--    Used for rendering connections on the minimap.
--    Adds per-connection random colour and start/end text labels (creator name).
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

class 'GUIMinimapConnection'

GUIMinimapConnection.kLineMode = GetAdvancedOption("pglines")

local kLineTexture = PrecacheAsset("ui/mapconnector_line.dds")
local kDashedLineTexture = PrecacheAsset("ui/mapconnector_dashed.dds")
local kLineTextureCoord = {0, 0, 64, 16}

local kLabelFont = Fonts.kAgencyFB_Tiny
local kLabelFontMini = Fonts.kAgencyFB_Tiny

-- Layers: render tunnel art on top of all standard minimap content (player
-- names sit at layer 7 in GUIMinimap), so 8/9/10 keeps lines and labels
-- above everything else on both the in-HUD minimap and the full map view.
local kLineLayer        = 8
local kLabelShadowLayer = 9
local kLabelLayer       = 10

local kShadowOffset = Vector(2, 2, 0)
local kShadowColor  = Color(0, 0, 0, 1)

-- HSV -> RGB. h, s, v are in [0, 1].
local function HSVtoRGB(h, s, v)
    h = h * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

-- Deterministic vivid colour from a seed integer. Full saturation, near-full
-- value, always full alpha — produces high-contrast neon-style hues against
-- the grey/light minimap art.
local function ColorFromSeed(seed)
    seed = math.abs(tonumber(seed) or 0) + 1
    local a = (seed * 1103515245 + 12345) % 2147483648
    local hue = (a % 1000) / 1000
    local r, g, b = HSVtoRGB(hue, 1.0, 1.0)
    return Color(r, g, b, 1)
end

function GUIMinimapConnection:CheckLineTexture()

    self.lineTexture = ConditionalValue(GUIMinimapConnection.kLineMode == 2, kDashedLineTexture, kLineTexture)

    if self.line then
        self.line:SetTexture(self.lineTexture)
    end

end

function GUIMinimapConnection:SetConnector(connector)
    self.connector = connector
end

function GUIMinimapConnection:GetConnectorColor()
    if self.connector and self.connector.GetColorSeed then
        return ColorFromSeed(self.connector:GetColorSeed())
    end
    return Color(1, 1, 1, 1)
end

local function CreateLabelItem(self, layer, color)
    local item = GUI.CreateItem()
    item:SetOptionFlag(GUIItem.ManageRender)
    item:SetAnchor(GUIItem.Middle, GUIItem.Center)
    item:SetTextAlignmentX(GUIItem.Align_Center)
    item:SetTextAlignmentY(GUIItem.Align_Center)
    item:SetFontName(kLabelFont)
    item:SetFontIsBold(true)
    item:SetLayer(layer)
    item:SetColor(color)
    item:SetStencilFunc(self.stencilFunc)
    if self.parent then
        self.parent:AddChild(item)
    end
    return item
end

local function EnsureLabelItem(self, key)
    local item = self[key]
    if not item then
        item = CreateLabelItem(self, kLabelLayer, Color(1, 1, 1, 1))
        self[key] = item
    end
    return item
end

local function EnsureShadowItem(self, key)
    local item = self[key]
    if not item then
        item = CreateLabelItem(self, kLabelShadowLayer, kShadowColor)
        self[key] = item
    end
    return item
end

local function ReparentTo(item, parent)
    if not item then return end
    local currentParent = item:GetParent()
    if currentParent ~= parent then
        if currentParent then currentParent:RemoveChild(item) end
        if parent then parent:AddChild(item) end
    end
end

function GUIMinimapConnection:UpdateLabels(modeIsMini, color)

    local startLabel, endLabel = "", ""
    if self.connector then
        if self.connector.GetStartLabel then startLabel = self.connector:GetStartLabel() or "" end
        if self.connector.GetEndLabel then endLabel = self.connector:GetEndLabel() or "" end
    end

    -- If neither label exists, hide and exit.
    if startLabel == "" and endLabel == "" then
        if self.startText then self.startText:SetIsVisible(false) end
        if self.endText then self.endText:SetIsVisible(false) end
        if self.startTextShadow then self.startTextShadow:SetIsVisible(false) end
        if self.endTextShadow then self.endTextShadow:SetIsVisible(false) end
        return
    end

    -- Owner-specific visibility per entrance: the server now provides the
    -- stable client index of the owner for each entrance (start/end). For
    -- non-commander tunnel labels, only the owning player sees "My Entrance"
    -- / "My Exit" at the correct end. Commander labels are left unchanged.
    local startEntranceOwnerIndex = 0
    local endEntranceOwnerIndex = 0
    if self.connector then
        if self.connector.GetStartEntranceOwnerStableClientIndex then
            startEntranceOwnerIndex = self.connector:GetStartEntranceOwnerStableClientIndex() or 0
        end
        if self.connector.GetEndEntranceOwnerStableClientIndex then
            endEntranceOwnerIndex = self.connector:GetEndEntranceOwnerStableClientIndex() or 0
        end
    end

    local localClientIndex = self.clientIndex
    if not localClientIndex then
        local pl = Client.GetLocalPlayer()
        if pl and pl.GetClientIndex then localClientIndex = pl:GetClientIndex() end
    end

    local displayStartLabel = startLabel
    local displayEndLabel = endLabel

    local function IsCommanderLabel(text)
        return text and text:sub(1,5) == "Comm "
    end

    if not IsCommanderLabel(startLabel) then
        if startEntranceOwnerIndex > 0 then
            if startEntranceOwnerIndex == localClientIndex then
                displayStartLabel = "My Entrance"
            else
                displayStartLabel = ""
            end
        else
            displayStartLabel = ""
        end
    end

    if not IsCommanderLabel(endLabel) then
        if endEntranceOwnerIndex > 0 then
            if endEntranceOwnerIndex == localClientIndex then
                displayEndLabel = "My Exit"
            else
                displayEndLabel = ""
            end
        else
            displayEndLabel = ""
        end
    end

    local startShadow = EnsureShadowItem(self, "startTextShadow")
    local endShadow   = EnsureShadowItem(self, "endTextShadow")
    local startItem   = EnsureLabelItem(self, "startText")
    local endItem     = EnsureLabelItem(self, "endText")

    -- Force the label colour to a fully solid, vivid version of the per-
    -- connection colour (alpha clamped to 1 in case anything else dimmed it).
    local labelColor = Color(color.r, color.g, color.b, 1)

    local fontScale = ConditionalValue(modeIsMini, GUIScale(0.85), GUIScale(1.05))
    local offset = GUIScale(ConditionalValue(modeIsMini, 7, 11))

    -- Offset perpendicular to the line so the labels don't overlap the line.
    local dx = (self.endPoint and self.startPoint) and (self.endPoint.x - self.startPoint.x) or 0
    local dy = (self.endPoint and self.startPoint) and (self.endPoint.y - self.startPoint.y) or 0
    local len = math.sqrt(dx * dx + dy * dy)
    local nx, ny = 0, -1
    if len > 0.01 then
        nx = -dy / len
        ny = dx / len
    end

    local perpOffset = Vector(nx * offset, ny * offset, 0)

    local startBasePos = (self.startPoint or Vector(0, 0, 0)) + perpOffset
    local endBasePos   = (self.endPoint   or Vector(0, 0, 0)) + perpOffset

    local function ApplyText(item, text, textColor, pos, layer)
        item:SetText(text)
        item:SetColor(textColor)
        item:SetScale(Vector(fontScale, fontScale, 0))
        item:SetPosition(pos)
        item:SetLayer(layer)
        item:SetIsVisible(self.isVisible and text ~= "")
    end

    ApplyText(startShadow, displayStartLabel, kShadowColor, startBasePos + kShadowOffset, kLabelShadowLayer)
    ApplyText(endShadow,   displayEndLabel,   kShadowColor, endBasePos   + kShadowOffset, kLabelShadowLayer)
    ApplyText(startItem,   displayStartLabel, labelColor,   startBasePos,                 kLabelLayer)
    ApplyText(endItem,     displayEndLabel,   labelColor,   endBasePos,                   kLabelLayer)

    -- Make sure all label items are parented to the current parent.
    ReparentTo(startShadow, self.parent)
    ReparentTo(endShadow,   self.parent)
    ReparentTo(startItem,   self.parent)
    ReparentTo(endItem,     self.parent)

end

function GUIMinimapConnection:UpdateAnimation(teamNumber, modeIsMini)
    if not self.isVisible then return end

    local animatedArrows = not modeIsMini and teamNumber == kTeam1Index and #GetEntitiesForTeam("MapConnector", kTeam1Index) > 2
    local animation = ConditionalValue(animatedArrows and GUIMinimapConnection.kLineMode > 1, (Shared.GetTime() % 1) / 1, 0)

    local x1Coord = kLineTextureCoord[1] - animation * (kLineTextureCoord[3] - kLineTextureCoord[1])
    local x2Coord = x1Coord + (self.length or 0)

    -- Don't draw arrows for just 2 PGs, the direction is clear here
    -- Gorge tunnels also don't need this since it is limited to entrance/exit
    local textureIndex = ConditionalValue(animatedArrows and GUIMinimapConnection.kLineMode > 0, 16, 0)

    self.line:SetTexturePixelCoordinates(x1Coord, textureIndex, x2Coord, textureIndex + 16)

    local color = self:GetConnectorColor()
    -- Force solid alpha on the line itself.
    self.line:SetColor(Color(color.r, color.g, color.b, 1))
    self.line:SetLayer(kLineLayer)
    self.line:SetSize(Vector(self.length, GUIScale(ConditionalValue(modeIsMini, 6, 10)), 0))

    self:UpdateLabels(modeIsMini, color)
end


function GUIMinimapConnection:UpdateAnimation_Alien(modeIsMini, color)
    if not self.isVisible then return end

    local x1Coord = kLineTextureCoord[1] - 0
    local x2Coord = x1Coord + (self.length or 0)

    -- Don't draw arrows for just 2 PGs, the direction is clear here
    -- Gorge tunnels also don't need this since it is limited to entrance/exit
    local textureIndex = 0

    self.line:SetTexturePixelCoordinates(x1Coord, textureIndex, x2Coord, textureIndex + 16)

    -- Prefer the per-connection random colour if we have one; fall back to the
    -- legacy palette colour passed in from GUIMinimap.
    local lineColor = self:GetConnectorColor()
    if (not self.connector) and color then
        lineColor = color
    end

    -- Force solid alpha on the line itself.
    self.line:SetColor(Color(lineColor.r, lineColor.g, lineColor.b, 1))
    self.line:SetLayer(kLineLayer)
    self.line:SetSize(Vector(self.length, GUIScale(ConditionalValue(modeIsMini, 6, 10)), 0))

    self:UpdateLabels(modeIsMini, lineColor)
end

function GUIMinimapConnection:Setup(startPoint, endPoint, parent)

    assert(startPoint:isa("Vector"))
    assert(endPoint:isa("Vector"))
    assert(parent)

    self.lineTexture = ConditionalValue(GUIMinimapConnection.kLineMode == 2, kDashedLineTexture, kLineTexture)

    if startPoint ~= self.startPoint or endPoint ~= self.endPoint or self.parent ~= parent then

        -- Since we're using a texture we need to move the points up a bit so it gets aligned properly
        startPoint = startPoint - (Vector(0,4,0))
        endPoint = endPoint - (Vector(0,4,0))

        local direction = GetNormalizedVector(startPoint - endPoint)
        local rotation = math.atan2(direction.x, direction.y)
        if rotation < 0 then
            rotation = rotation + math.pi * 2
        end

        rotation = rotation + math.pi * 0.5

        self.startPoint = Vector(startPoint)
        self.endPoint = Vector(endPoint)
        self.parent = parent
        self.rotationVec = Vector(0, 0, rotation)

        local delta = self.endPoint - self.startPoint
        self.length = math.sqrt(delta.x ^ 2 + delta.y ^ 2)

        self:SetIsVisible(true)

        self:Render()

    end

end

function GUIMinimapConnection:SetStencilFunc(func)

    if self.line then
        self.line:SetStencilFunc(func)
    end
    if self.startText then self.startText:SetStencilFunc(func) end
    if self.endText then self.endText:SetStencilFunc(func) end
    if self.startTextShadow then self.startTextShadow:SetStencilFunc(func) end
    if self.endTextShadow then self.endTextShadow:SetStencilFunc(func) end

    self.stencilFunc = func

end

function GUIMinimapConnection:Uninitialize()

    if self.line then
        GUI.DestroyItem(self.line)
        self.line = nil
    end
    if self.startText then
        GUI.DestroyItem(self.startText)
        self.startText = nil
    end
    if self.endText then
        GUI.DestroyItem(self.endText)
        self.endText = nil
    end
    if self.startTextShadow then
        GUI.DestroyItem(self.startTextShadow)
        self.startTextShadow = nil
    end
    if self.endTextShadow then
        GUI.DestroyItem(self.endTextShadow)
        self.endTextShadow = nil
    end

end

function GUIMinimapConnection:Render()

    if not self.line then

        self.lineTexture = ConditionalValue(GUIMinimapConnection.kLineMode == 2, kDashedLineTexture, kLineTexture)

        self.line = GUI.CreateItem()
        self.line:SetTexture(self.lineTexture)
        self.line:SetAnchor(GUIItem.Middle, GUIItem.Center)
        self.line:SetStencilFunc(self.stencilFunc)
        self.line:SetLayer(kLineLayer)

        if self.parent then
            self.parent:AddChild(self.line)
        end

    end

    self.line:SetLayer(kLineLayer)
    self.line:SetSize(Vector(self.length, GUIScale(10), 0))
    self.line:SetPosition(self.startPoint)
    self.line:SetRotationOffset(Vector(-self.length, 0, 0))
    self.line:SetRotation(self.rotationVec)

    -- update line parent
    local currentParent = self.line:GetParent()
    if currentParent and currentParent ~= self.parent then

        currentParent:RemoveChild(self.line)

        if self.parent then
            self.parent:AddChild(self.line)
        end

    end

end

function GUIMinimapConnection:SetIsVisible(isVisible)
    if self.line then
        self.line:SetIsVisible(isVisible)
    end
    if self.startText then
        self.startText:SetIsVisible(isVisible and (self.startText:GetText() or "") ~= "")
    end
    if self.endText then
        self.endText:SetIsVisible(isVisible and (self.endText:GetText() or "") ~= "")
    end
    if self.startTextShadow then
        self.startTextShadow:SetIsVisible(isVisible and (self.startText and (self.startText:GetText() or "") ~= ""))
    end
    if self.endTextShadow then
        self.endTextShadow:SetIsVisible(isVisible and (self.endText and (self.endText:GetText() or "") ~= ""))
    end

    self.isVisible = isVisible
end
