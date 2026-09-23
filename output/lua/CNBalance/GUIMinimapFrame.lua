-- ======= NS2.0-TEH-Beta: CNBalance/GUIMinimapFrame.lua =======
--
-- CLIENT post-hook on lua/GUIMinimapFrame.lua. Commander ORDER ICONS on the fullscreen map
-- (replaces the old freehand commander drawing). The icon DATA lives in gGCLocalIcons (kept in sync
-- by CommMapTools_Client.lua); this file draws the icons, the order wheel and the commander input.
--
-- Input (commander, while the fullscreen map is open):
--   * HOLD MIDDLE mouse over the map: the order wheel opens at the cursor, and that cursor spot is
--     remembered as where the order will be placed. While holding, move the cursor over an order and
--     either RELEASE middle mouse or click LEFT mouse: that order's icon is placed at the remembered
--     spot and the wheel closes. Releasing over nothing just closes the wheel.
--   * With the wheel closed, left mouse and the scroll wheel behave as normal (pan / zoom).
--   * RIGHT mouse: clear every order icon for the commander's team.
--
-- Everyone on the commander's team sees the icons on their fullscreen map. Each icon has the order
-- name underneath and a number (1, 2, 3... in placement order, across all orders) at its top-right, in the team colour
-- (Marines blue / Kharaa orange).
--
-- Map icons are CHILDREN of the minimap item and positioned with the engine's own world->minimap
-- transform (self:PlotToMap), exactly like blips, so they line up at any zoom.

if not Client then return end

local kIconTexture   = "ui/buildmenu.dds"
local kMapIconSize   = 50     -- on-map icon size (before GUIScale); was 40, +25%
local kMapLayer      = 25
local kWheelLayer    = kGUILayerBigMap + 3
local kWheelInner    = 75     -- order wheel inner circle radius (before GUIScale)
local kWheelOuter    = 175    -- order wheel outer circle radius
local kWheelIconSize = 56

-- The ring is drawn with TEXTURES (real circles, no rotated pieces): one texture per order slice
-- (tinted individually for hover) plus one texture with the inner/outer circles and the dividers.
-- The textures are 512x512 with the outer circle at radius 250 and the inner circle at
-- 250 * kWheelInner / kWheelOuter, so kWheelInner/kWheelOuter must keep that 75:175 ratio.
local kWheelSliceTextures = {
    "ui/teh_orderwheel_slice1.dds", "ui/teh_orderwheel_slice2.dds", "ui/teh_orderwheel_slice3.dds",
    "ui/teh_orderwheel_slice4.dds", "ui/teh_orderwheel_slice5.dds",
}
for i = 1, #kWheelSliceTextures do PrecacheAsset(kWheelSliceTextures[i]) end
local kWheelLinesTexture = PrecacheAsset("ui/teh_orderwheel_lines.dds")
local kTextureOuterRadiusFraction = 250 / 256   -- outer circle radius / half the texture size

-- Team colours. text = order names / counts / legend; slice = wheel background; hover = the slice
-- under the cursor; line = circles + dividers.
local kTeamColours = {
    [1] = {   -- Marines blue
        text  = Color(0.40, 0.90, 1.00, 1),      -- brighter, slightly turquoise blue
        slice = Color(0.03, 0.15, 0.24, 0.82),
        hover = Color(0.14, 0.60, 0.82, 0.92),
        line  = Color(0.50, 0.93, 1.00, 0.9),
    },
    [2] = {   -- Kharaa orange
        text  = Color(1.00, 0.52, 0.06, 1),      -- slightly more orange
        slice = Color(0.27, 0.10, 0.01, 0.82),
        hover = Color(0.88, 0.38, 0.02, 0.92),
        line  = Color(1.00, 0.58, 0.12, 0.9),
    },
}

local function GetTeamColours()
    return kTeamColours[Client.GetLocalClientTeamNumber()] or kTeamColours[2]
end

local function IsLocalCommander()
    local p = Client.GetLocalPlayer()
    return p ~= nil and p.isa and p:isa("Commander")
end

local function IsBigMapOpen(self)
    return self.comMode == GUIMinimapFrame.kModeBig
        and self.GetBackground and self:GetBackground() ~= nil
        and self:GetBackground():GetIsVisible()
end

local function IsOnPlayingTeam()
    local n = Client.GetLocalClientTeamNumber()
    return n == kTeam1Index or n == kTeam2Index
end

local function GetOrders()
    return kGCommMap.Orders[Client.GetLocalClientTeamNumber()] or kGCommMap.Orders[kTeam2Index]
end

-- Button-atlas pixel coords for an order entry (same atlas and maths as the commander buttons).
local function SetOrderIcon(item, entry)
    item:SetTexture(kIconTexture)
    local techId = entry and kTechId and kTechId[entry.tech]
    local coords = techId and GetTextureCoordinatesForIcon(techId)
    if coords then
        item:SetTexturePixelCoordinates(GUIUnpackCoords(coords))
    end
end

-- Screen cursor -> world (x,z) by INVERTING GUIMinimap:PlotToMap - the SAME transform used to render
-- the icons (MinimapToWorld uses a different, heightmap-based mapping that lands off the cursor).
local function CursorToWorld(self)
    local item = self.minimap
    if not item then return nil end

    local mx, my = Client.GetCursorPosScreen()
    local sp = GUIItemCalculateScreenPosition(item)
    local localX = mx - sp.x
    local localY = my - sp.y

    if Client.legacyMinimap then
        if not (self.plotToMapLinX and self.plotToMapLinY)
           or self.plotToMapLinX == 0 or self.plotToMapLinY == 0 then return nil end
        local posZ =  localX / self.plotToMapLinY - self.plotToMapConstY
        local posX = -localY / self.plotToMapLinX - self.plotToMapConstX
        return Vector(posX, 0, posZ)
    else
        if not (self.plotXFactor and self.plotZFactor)
           or self.plotXFactor == 0 or self.plotZFactor == 0 then return nil end
        local posZ = localX / self.plotZFactor - self.plotZOffset
        local posX = localY / self.plotXFactor - self.plotXOffset
        return Vector(posX, 0, posZ)
    end
end

-- ---- Order wheel ---------------------------------------------------------------------------------
local function NewScreenGraphic(layer, texture)
    local it = GetGUIManager():CreateGraphicItem()
    it:SetAnchor(GUIItem.Left, GUIItem.Top)
    it:SetLayer(layer)
    if texture then it:SetTexture(texture) end
    it:SetIsVisible(false)
    return it
end

local function EnsureWheel(self, count)
    if self._gcWheel then return end
    local wheel = { slices = {}, icons = {}, labels = {} }
    for i = 1, count do
        wheel.slices[i] = NewScreenGraphic(kWheelLayer, kWheelSliceTextures[i])
        wheel.icons[i]  = NewScreenGraphic(kWheelLayer + 2)

        local label = GetGUIManager():CreateTextItem()
        label:SetAnchor(GUIItem.Left, GUIItem.Top)
        label:SetFontName(Fonts.kAgencyFB_Small)
        label:SetTextAlignmentX(GUIItem.Align_Center)
        label:SetTextAlignmentY(GUIItem.Align_Min)
        label:SetLayer(kWheelLayer + 2)
        label:SetIsVisible(false)
        wheel.labels[i] = label
    end
    wheel.lines = NewScreenGraphic(kWheelLayer + 1, kWheelLinesTexture)
    self._gcWheel = wheel
end

-- Segment index (1..count) for a screen angle measured from the wheel centre. Segment 1 is centred
-- at the top and they go clockwise - the same layout the slice textures were generated with.
local function SegmentForAngle(angle, count)
    local step = 2 * math.pi / count
    local a = (angle + math.pi * 0.5 + step * 0.5) % (2 * math.pi)
    return math.floor(a / step) + 1
end

-- Which segment the cursor points at, or nil if the cursor is inside the inner circle. Anything
-- beyond the outer circle still counts: only the ANGLE decides the order once past the inner circle.
local function WheelSegmentAtCursor(self)
    local count = math.min(#GetOrders(), #kWheelSliceTextures)
    local cx, cy = self._gcWheelX, self._gcWheelY
    if not cx or count == 0 then return nil end
    local mx, my = Client.GetCursorPosScreen()
    local dx, dy = mx - cx, my - cy
    local r = math.sqrt(dx * dx + dy * dy)
    if r < GUIScale(kWheelInner) then return nil end
    return SegmentForAngle(math.atan2(dy, dx), count)
end

local function HideWheel(self)
    local wheel = self._gcWheel
    if not wheel then return end
    for i = 1, #wheel.slices do
        wheel.slices[i]:SetIsVisible(false)
        wheel.icons[i]:SetIsVisible(false)
        wheel.labels[i]:SetIsVisible(false)
    end
    wheel.lines:SetIsVisible(false)
end

local function CloseWheel(self)
    self._gcWheelOpen = false
    self._gcPlaceAt = nil
    HideWheel(self)
end

-- Opens the wheel at the cursor and remembers the world spot under the cursor as the placement point.
local function OpenWheel(self)
    local mx, my = Client.GetCursorPosScreen()
    if not GUIItemContainsPoint(self.minimap, mx, my) then return end
    local world = CursorToWorld(self)
    if not world then return end
    self._gcWheelX, self._gcWheelY = mx, my
    self._gcPlaceAt = world
    self._gcWheelOpen = true
end

-- If the cursor is on an order, place that order at the remembered spot. Always closes the wheel.
local function ChooseAndClose(self)
    local idx = WheelSegmentAtCursor(self)
    if idx and self._gcPlaceAt then
        Client.SendNetworkMessage("GC_Icon",
            { position = self._gcPlaceAt, order = idx, size = kGCommMap.DefaultIconSize }, true)
    end
    CloseWheel(self)
end

local function UpdateWheel(self)
    local orders = GetOrders()
    local count = math.min(#orders, #kWheelSliceTextures)
    if not self._gcWheelOpen or count == 0 then
        HideWheel(self)
        return
    end
    EnsureWheel(self, count)
    local wheel = self._gcWheel
    local colours = GetTeamColours()

    local cx, cy = self._gcWheelX, self._gcWheelY
    local inner, outer = GUIScale(kWheelInner), GUIScale(kWheelOuter)
    local midR = (inner + outer) * 0.5
    local hovered = WheelSegmentAtCursor(self)

    -- Every wheel texture is the same square, centred on the wheel centre.
    local texSize = (outer / kTextureOuterRadiusFraction) * 2
    local texPos = Vector(cx - texSize * 0.5, cy - texSize * 0.5, 0)
    local texVec = Vector(texSize, texSize, 0)

    wheel.lines:SetSize(texVec)
    wheel.lines:SetPosition(texPos)
    wheel.lines:SetColor(colours.line)
    wheel.lines:SetIsVisible(true)

    local step = 2 * math.pi / count
    local iconSize = GUIScale(kWheelIconSize)
    for i = 1, count do
        local slice = wheel.slices[i]
        slice:SetSize(texVec)
        slice:SetPosition(texPos)
        slice:SetColor((i == hovered) and colours.hover or colours.slice)
        slice:SetIsVisible(true)

        -- Icon + name in the band between the two circles, nudged up a little so the pair sits centred.
        local a = -math.pi * 0.5 + (i - 1) * step
        local px, py = cx + math.cos(a) * midR, cy + math.sin(a) * midR

        local icon = wheel.icons[i]
        SetOrderIcon(icon, orders[i])
        icon:SetColor(Color(1, 1, 1, 1))
        icon:SetSize(Vector(iconSize, iconSize, 0))
        icon:SetPosition(Vector(px - iconSize * 0.5, py - iconSize * 0.80, 0))
        icon:SetIsVisible(true)

        local label = wheel.labels[i]
        label:SetText(orders[i].name)
        label:SetColor(colours.text)
        label:SetScale(GUIScale(Vector(1.0, 1.0, 1)))
        label:SetPosition(Vector(px, py + iconSize * 0.12, 0))
        label:SetIsVisible(true)
    end
end

-- ---- Input ---------------------------------------------------------------------------------------
local baseSendKeyEvent = GUIMinimapFrame.SendKeyEvent
function GUIMinimapFrame:SendKeyEvent(key, down)

    if InputKey and IsLocalCommander() and IsBigMapOpen(self) then

        if key == InputKey.MouseButton2 then                  -- MIDDLE: hold = wheel, release = choose
            if down then
                if not self._gcWheelOpen then
                    OpenWheel(self)
                end
            elseif self._gcWheelOpen then
                ChooseAndClose(self)
            end
            return true

        elseif key == InputKey.MouseButton0 and self._gcWheelOpen then   -- LEFT while the wheel is open
            if down then
                ChooseAndClose(self)
            end
            return true                                        -- never pan/select through the wheel

        elseif key == InputKey.MouseButton1 then              -- RIGHT: clear all team icons
            if down then
                Client.SendNetworkMessage("GC_DrawClear", {}, true)
            end
            return true
        end
    end

    return baseSendKeyEvent(self, key, down)
end

-- ---- Header + hint text (created lazily, toggled with the big map) -------------------------------
local function EnsureHeader(self)
    if self._gcMmb then return end
    local gui = GetGUIManager()

    -- Bottom-right stacked guidance for the commander (no "Commander's Order(s)" heading).
    local kBlue  = Color(0.45, 0.85, 1.0, 1)
    local kWhite = Color(1, 1, 1, 1)

    local function makeRight(row, font, colour, text)
        local t = gui:CreateTextItem()
        t:SetAnchor(GUIItem.Right, GUIItem.Bottom)
        t:SetFontName(font)
        t:SetTextAlignmentX(GUIItem.Align_Max)
        t:SetTextAlignmentY(GUIItem.Align_Min)
        t:SetScale(GUIScale(Vector(1, 1, 1)))
        t:SetPosition(Vector(-GUIScale(24), -GUIScale(360) + GUIScale(26) * row, 0))
        t:SetLayer(kGUILayerBigMap + 1)
        if colour then t:SetColor(colour) end
        if text then t:SetText(text) end
        t:SetIsVisible(false)
        return t
    end

    self._gcMmb     = makeRight(1, Fonts.kAgencyFB_Small, kBlue,  "Hold MMB: Order Wheel")
    self._gcLmbHint = makeRight(2, Fonts.kAgencyFB_Small, kWhite, "Release MMB / LMB on an order: Place it")
    self._gcRmbHint = makeRight(3, Fonts.kAgencyFB_Small, kWhite, "RMB: Clear All Orders")
end

-- ---- On-map icon pool (children of the minimap item) ---------------------------------------------
local function EnsureMapIcon(self, n)
    self._gcIcons = self._gcIcons or {}
    local e = self._gcIcons[n]
    if e then return e end
    local gui = GetGUIManager()
    local parent = self:GetMinimapItem()

    local icon = gui:CreateGraphicItem()
    icon:SetLayer(kMapLayer)
    parent:AddChild(icon)

    local count = gui:CreateTextItem()
    count:SetFontName(Fonts.kAgencyFB_Small)
    count:SetTextAlignmentX(GUIItem.Align_Min)
    count:SetTextAlignmentY(GUIItem.Align_Max)
    count:SetLayer(kMapLayer + 1)
    parent:AddChild(count)

    local name = gui:CreateTextItem()
    name:SetFontName(Fonts.kAgencyFB_Small)
    name:SetTextAlignmentX(GUIItem.Align_Center)
    name:SetTextAlignmentY(GUIItem.Align_Min)
    name:SetLayer(kMapLayer + 1)
    parent:AddChild(name)

    e = { icon = icon, count = count, name = name }
    self._gcIcons[n] = e
    return e
end

local function HideMapIcons(self, fromIdx)
    if not self._gcIcons then return end
    for i = fromIdx or 1, #self._gcIcons do
        local e = self._gcIcons[i]
        e.icon:SetIsVisible(false)
        e.count:SetIsVisible(false)
        e.name:SetIsVisible(false)
    end
end

-- Positions are recomputed every frame the map is open, so icons follow zoom / pan changes.
local function RenderMapIcons(self)
    local orders = GetOrders()
    local colours = GetTeamColours()
    local size = GUIScale(kMapIconSize)
    local n = 0
    for i = 1, #gGCLocalIcons do
        local data = gGCLocalIcons[i]
        local entry = orders[data.order]
        if entry and data.pos then
            n = n + 1
            local e = EnsureMapIcon(self, n)
            local mx, my = self:PlotToMap(data.pos.x, data.pos.z)

            SetOrderIcon(e.icon, entry)
            e.icon:SetColor(colours.text)   -- tinted Marines blue / Kharaa orange for the viewer's team
            e.icon:SetSize(Vector(size, size, 0))
            e.icon:SetPosition(Vector(mx - size * 0.5, my - size * 0.5, 0))
            e.icon:SetIsVisible(true)

            e.count:SetText(tostring(n))   -- chronological: 1, 2, 3... across ALL orders until cleared
            e.count:SetColor(colours.text)
            e.count:SetScale(GUIScale(Vector(1.0625, 1.0625, 1)))   -- 1.25 - 15%
            e.count:SetPosition(Vector(mx + size * 0.40, my - size * 0.22, 0))
            e.count:SetIsVisible(true)

            e.name:SetText(string.upper(entry.name))
            e.name:SetColor(colours.text)
            e.name:SetScale(GUIScale(Vector(0.935, 0.935, 1)))       -- 1.1 - 15%
            e.name:SetPosition(Vector(mx, my + size * 0.40, 0))   -- a little closer to the icon
            e.name:SetIsVisible(true)
        end
    end
    HideMapIcons(self, n + 1)
end

-- ---- Main per-frame driver -----------------------------------------------------------------------
local function UpdateOverlay(self)

    -- Only players ON a playing team see that team's icons; ready room / spectators see nothing.
    local show = IsBigMapOpen(self) and IsOnPlayingTeam()

    -- On the open edge, ask the server to (re)send this team's stored icons.
    if show and not self._gcWasShowing then
        Client.SendNetworkMessage("GC_DrawRequest", {}, true)
    end
    self._gcWasShowing = show

    EnsureHeader(self)

    local isComm = IsLocalCommander()
    local showComm = show and isComm
    self._gcMmb:SetColor(GetTeamColours().text)   -- MMB hint in the team colour
    for _, t in ipairs({ self._gcMmb, self._gcLmbHint, self._gcRmbHint }) do
        t:SetIsVisible(showComm)
    end

    if not show or not isComm then
        CloseWheel(self)
    end
    if not show then
        HideMapIcons(self)
        return
    end

    RenderMapIcons(self)
    UpdateWheel(self)
end

local baseUpdate = GUIMinimapFrame.Update
function GUIMinimapFrame:Update(deltaTime)
    baseUpdate(self, deltaTime)
    UpdateOverlay(self)
end
