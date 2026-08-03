-- ======= NS2.0-TEH-Beta: CNBalance/GUIMinimapFrame.lua =======
--
-- CLIENT post-hook on lua/GUIMinimapFrame.lua. Renders the commander's team drawing on the
-- fullscreen map, drives the commander's draw/erase/clear input, and shows the header + current
-- mode. The drawing DATA lives in gGCLocalDrawing (kept in sync by CommMapTools_Client.lua); this
-- file only turns it into on-screen red marks and lets the commander add to / edit it.
--
-- Input model (commander, while the fullscreen map is open):
--   * MIDDLE mouse cycles the MODE: Map Movement -> Drawing -> Erase -> Clear -> (repeat).
--   * LEFT mouse then does whatever the current mode is:
--       Map Movement -> the game's normal "pan the overhead view" (we don't touch it).
--       Drawing      -> freehand red drawing.
--       Erase        -> rubs out nearby marks.
--       Clear        -> a click wipes the whole drawing.
-- Left mouse is intercepted (so it doesn't also pan) ONLY in the drawing/erase/clear modes.
--
-- Draw marks are added as CHILDREN of the minimap item and positioned with the engine's own
-- world->minimap transform (self:PlotToMap), exactly like blips, so they line up at any zoom.
-- Cursor->world uses the engine's own MinimapToWorld (the same call the spawn-select map uses),
-- so the drawing lands exactly under the cursor.

if not Client then return end

local kHeaderLine1 = "Green - Commander's Order(s)"

-- Mode order that MMB cycles through.
local kModes = { "Map Movement", "Drawing", "Erase", "Clear" }

local function IsLocalCommander()
    local p = Client.GetLocalPlayer()
    return p ~= nil and p.isa and p:isa("Commander")
end

local function IsBigMapOpen(self)
    return self.comMode == GUIMinimapFrame.kModeBig
        and self.GetBackground and self:GetBackground() ~= nil
        and self:GetBackground():GetIsVisible()
end

local function CurrentMode(self)
    return kModes[self._gcModeIndex or 1]
end

-- Screen cursor -> world (x,z) by INVERTING GUIMinimap:PlotToMap - the SAME transform used to
-- render the marks. (The engine's MinimapToWorld uses a different, heightmap-based mapping, so
-- pairing it with PlotToMap put the drawing far from the cursor.) The marks are children of the
-- minimap item, so PlotToMap outputs item-local coordinates; the cursor's item-local position is
-- just (cursor - item's top-left screen position), because the zoom is baked into the plot factors
-- (the item's own GUIItem scale is 1). Inverting PlotToMap on that lands the point under the cursor.
local function CursorToWorld(self)
    local item = self.minimap
    if not item then return nil end

    local mx, my = Client.GetCursorPosScreen()
    local sp = GUIItemCalculateScreenPosition(item)
    local localX = mx - sp.x
    local localY = my - sp.y

    if Client.legacyMinimap then
        -- PlotToMap (legacy): localX = (posZ+constY)*linY ; localY = -(posX+constX)*linX
        if not (self.plotToMapLinX and self.plotToMapLinY)
           or self.plotToMapLinX == 0 or self.plotToMapLinY == 0 then return nil end
        local posZ =  localX / self.plotToMapLinY - self.plotToMapConstY
        local posX = -localY / self.plotToMapLinX - self.plotToMapConstX
        return Vector(posX, 0, posZ)
    else
        -- PlotToMap: localX = (posZ+plotZOffset)*plotZFactor ; localY = (posX+plotXOffset)*plotXFactor
        if not (self.plotXFactor and self.plotZFactor)
           or self.plotXFactor == 0 or self.plotZFactor == 0 then return nil end
        local posZ = localX / self.plotZFactor - self.plotZOffset
        local posX = localY / self.plotXFactor - self.plotXOffset
        return Vector(posX, 0, posZ)
    end
end

local function BreakStroke(self)
    if self._gcDrewLast then
        Client.SendNetworkMessage("GC_Draw",
            { position = Vector(0, 0, 0), erase = false, penUp = true }, true)
        self._gcDrewLast = false
    end
    self._gcLastSample = nil
end

function GUIMinimapFrame:GCCycleMode()
    self._gcModeIndex = ((self._gcModeIndex or 1) % #kModes) + 1
    self._gcLmb = false
    BreakStroke(self)   -- end any in-progress stroke when the mode changes
end

-- Intercept the mode/draw buttons on the OPEN map. LEFT mouse is only consumed in the modes that
-- act on it (so "Map Movement" keeps the game's normal LMB pan). MIDDLE mouse cycles the mode
-- (it is the commander ping when the map is closed, which we leave alone).
local baseSendKeyEvent = GUIMinimapFrame.SendKeyEvent
function GUIMinimapFrame:SendKeyEvent(key, down)

    if InputKey and IsLocalCommander() and IsBigMapOpen(self) then

        if key == InputKey.MouseButton2 then          -- MIDDLE: cycle mode
            if down then self:GCCycleMode() end
            self:UpdatePlayerMinimapVisible()
            return true

        elseif key == InputKey.MouseButton0 then       -- LEFT: act per current mode
            local mode = CurrentMode(self)
            if mode == "Drawing" or mode == "Erase" then
                self._gcLmb = down
                if not down then BreakStroke(self) end
                self:UpdatePlayerMinimapVisible()
                return true
            elseif mode == "Clear" then
                if down then Client.SendNetworkMessage("GC_DrawClear", {}, true) end
                self:UpdatePlayerMinimapVisible()
                return true
            end
            -- "Map Movement": fall through so the base pans the overhead view as normal.
        end
    end

    return baseSendKeyEvent(self, key, down)
end

-- ---- Header + mode text (created lazily, toggled with the big map). ----------------------------
-- Non-commanders get a single top-centre legend. The COMMANDER gets a stacked, multi-colour block
-- anchored bottom-right and sat ABOVE the button grid / armour+weapons icons, so nothing clips.
local function EnsureHeader(self)
    if self._gcTop then return end
    local gui = GetGUIManager()

    -- Top-centre legend for non-commander players.
    local top = gui:CreateTextItem()
    top:SetAnchor(GUIItem.Middle, GUIItem.Top)
    top:SetFontName(Fonts.kAgencyFB_Medium)
    top:SetTextAlignmentX(GUIItem.Align_Center)
    top:SetTextAlignmentY(GUIItem.Align_Min)
    top:SetScale(GUIScale(Vector(1, 1, 1)))
    top:SetPosition(Vector(0, GUIScale(90), 0))   -- midway between the old 60 (clipped) and 120 (too low)
    top:SetLayer(kGUILayerBigMap + 1)
    top:SetColor(kGCommMap.DrawColour)
    top:SetText(kHeaderLine1)
    top:SetIsVisible(false)
    self._gcTop = top

    -- Bottom-right stacked guidance for the commander. Distinct colour per line so the separate
    -- sentences read clearly. Row 0 is highest; the block sits ~280-360px above the bottom edge.
    local kBlue  = Color(0.45, 0.85, 1.0, 1)
    local kAmber = Color(1.0, 0.82, 0.30, 1)
    local kWhite = Color(1, 1, 1, 1)   -- LMB hint (green is now the drawing colour, so use white)

    local function makeRight(row, font, colour)
        local t = gui:CreateTextItem()
        t:SetAnchor(GUIItem.Right, GUIItem.Bottom)
        t:SetFontName(font)
        t:SetTextAlignmentX(GUIItem.Align_Max)     -- right-aligned to the screen edge
        t:SetTextAlignmentY(GUIItem.Align_Min)
        t:SetScale(GUIScale(Vector(1, 1, 1)))
        t:SetPosition(Vector(-GUIScale(24), -GUIScale(360) + GUIScale(26) * row, 0))
        t:SetLayer(kGUILayerBigMap + 1)
        t:SetColor(colour)
        t:SetIsVisible(false)
        return t
    end

    self._gcLegend  = makeRight(0, Fonts.kAgencyFB_Medium, kGCommMap.DrawColour)
    self._gcLegend:SetText(kHeaderLine1)
    self._gcModeText = makeRight(1, Fonts.kAgencyFB_Medium, kAmber)   -- "Mode: X" (dynamic)
    self._gcMmb     = makeRight(2, Fonts.kAgencyFB_Small, kBlue)
    self._gcMmb:SetText("MMB: Change Mode")
    self._gcLmbHint = makeRight(3, Fonts.kAgencyFB_Small, kWhite)
    self._gcLmbHint:SetText("LMB: Use Selected Mode")
end

-- Only players ON a playing team see that team's drawing (Marine sees Marine, Alien sees Alien);
-- ready-room and spectators see neither the marks nor the legend.
local function IsOnPlayingTeam()
    local n = Client.GetLocalClientTeamNumber()
    return n == kTeam1Index or n == kTeam2Index
end

-- ---- Draw-mark pool (children of the minimap item) ----------------------------------------------
-- A stroke is rendered as ONE line SEGMENT between each pair of consecutive points (plus one dot at
-- each stroke start, so single-point strokes still show). This is ~1 GUIItem per DRAWN point,
-- versus ~10 for the old interpolated-dot line - crucial because NS2 hard-caps the WHOLE GUI at
-- 5000 items. Curves stay smooth because the points are sampled finely (each segment is short).
-- Rendering is INCREMENTAL: normal drawing only appends items for the new points; a full rebuild
-- happens only on a structural change (clear / erase) or when the map (re)opens. Positions use the
-- engine's own PlotToMap and the segment orientation copies NS2's minimap connection-line maths.
local kDrawLayer = 25
local kMaxMarks  = 3000   -- well under the engine's 5000 total-GUIItem cap (leaves room for the HUD)

-- Default (top-left) self-anchor, so positions are relative to the minimap's top-left - matching
-- how CursorToWorld inverts the cursor. (A Middle/Center anchor is parent-CENTRE relative and put
-- the drawing ~half a map off from the cursor.) We centre each item on its point manually.
local function GCEnsure(self, n)
    local it = self._gcMarks[n]
    if not it then
        it = GetGUIManager():CreateGraphicItem()
        it:SetColor(kGCommMap.DrawColour)
        it:SetLayer(kDrawLayer)
        self:GetMinimapItem():AddChild(it)
        self._gcMarks[n] = it
    end
    return it
end

-- A dot centred at (x,y) (stroke starts / single points).
local function GCDot(self, x, y)
    if (self._gcMarkN or 0) >= kMaxMarks then return end
    self._gcMarkN = self._gcMarkN + 1
    local t = self._gcThickness
    local it = GCEnsure(self, self._gcMarkN)
    it:SetRotationOffset(Vector(0, 0, 0))
    it:SetRotation(Vector(0, 0, 0))
    it:SetSize(Vector(t, t, 0))
    it:SetPosition(Vector(x - t * 0.5, y - t * 0.5, 0))
    it:SetIsVisible(true)
end

-- A line segment from A(ax,ay) to B(bx,by): a rectangle centred on the segment midpoint and rotated
-- to the segment angle, pivoting about its own centre (all in the minimap's top-left space).
local function GCSeg(self, ax, ay, bx, by)
    if (self._gcMarkN or 0) >= kMaxMarks then return end
    local dx, dy = bx - ax, by - ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return end
    self._gcMarkN = self._gcMarkN + 1
    local it = GCEnsure(self, self._gcMarkN)

    local t = self._gcThickness
    local mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
    it:SetSize(Vector(length, t, 0))
    it:SetPosition(Vector(mx - length * 0.5, my - t * 0.5, 0))   -- top-left so the rect is centred on M
    it:SetRotationOffset(Vector(length * 0.5, t * 0.5, 0))        -- pivot = the rectangle's centre
    it:SetRotation(Vector(0, 0, math.atan2(dy, dx)))
    it:SetIsVisible(true)
end

local function GCComputeSizes(self)
    local pf = (math.abs(self.plotXFactor or 1) + math.abs(self.plotZFactor or 1)) * 0.5
    self._gcThickness = math.max(3, kGCommMap.MinDrawStep * 1.6 * pf)
end

-- Render entries [fromIdx .. end], appending marks and continuing the current stroke.
local function GCRenderRange(self, fromIdx)
    for i = fromIdx, #gGCLocalDrawing do
        local e = gGCLocalDrawing[i]
        if e.penUp or not e.pos then
            self._gcPrevX, self._gcPrevY = nil, nil
        else
            local mx, my = self:PlotToMap(e.pos.x, e.pos.z)
            if not self._gcPrevX then
                GCDot(self, mx, my)                       -- stroke start / single point
            else
                GCSeg(self, self._gcPrevX, self._gcPrevY, mx, my)
            end
            self._gcPrevX, self._gcPrevY = mx, my
        end
    end
    self._gcSrcRendered = #gGCLocalDrawing
end

local function GCFullRebuild(self)
    self._gcMarks = self._gcMarks or {}
    GCComputeSizes(self)
    self._gcMarkN = 0
    self._gcPrevX, self._gcPrevY = nil, nil
    GCRenderRange(self, 1)
    for i = (self._gcMarkN or 0) + 1, #self._gcMarks do   -- hide leftovers from a larger drawing
        self._gcMarks[i]:SetIsVisible(false)
    end
end

local function GCSyncMarks(self)
    self._gcMarks = self._gcMarks or {}
    if self._gcRenderStruct ~= gGCDrawStructVersion or self._gcRenderVer == nil then
        GCFullRebuild(self)
        self._gcRenderStruct = gGCDrawStructVersion
    elseif self._gcRenderVer ~= gGCDrawVersion then
        GCComputeSizes(self)
        GCRenderRange(self, (self._gcSrcRendered or 0) + 1)
    end
    self._gcRenderVer = gGCDrawVersion
end

local function GCHideMarks(self)
    if not self._gcMarks then return end
    for i = 1, #self._gcMarks do
        self._gcMarks[i]:SetIsVisible(false)
    end
end

-- ---- Main per-frame driver. --------------------------------------------------------------------
local function UpdateOverlay(self)

    -- "Showing" requires the big map open AND the local player on a playing team. Ready-room and
    -- spectators see no drawing and no legend.
    local onTeam = IsOnPlayingTeam()
    local show   = IsBigMapOpen(self) and onTeam

    -- On the open edge, ask the server to (re)send this team's persisted drawing and force a full
    -- rebuild once it arrives.
    if show and not self._gcWasShowing then
        Client.SendNetworkMessage("GC_DrawRequest", {}, true)
        self._gcRenderVer = nil
    end
    self._gcWasShowing = show

    EnsureHeader(self)
    local isComm = IsLocalCommander()   -- a commander is always on a playing team
    self._gcTop:SetIsVisible(show and not isComm)
    local showComm = show and isComm
    self._gcLegend:SetIsVisible(showComm)
    self._gcModeText:SetIsVisible(showComm)
    self._gcMmb:SetIsVisible(showComm)
    self._gcLmbHint:SetIsVisible(showComm)
    if showComm then
        self._gcModeText:SetText("Mode: " .. CurrentMode(self))
    end

    if not show then
        GCHideMarks(self)
        self._gcLmb = false
        BreakStroke(self)
        return
    end

    GCSyncMarks(self)

    -- Commander drawing / erasing while LMB is held in the matching mode (throttled by MinDrawStep).
    if isComm and self._gcLmb then
        local mode = CurrentMode(self)
        if mode == "Drawing" or mode == "Erase" then
            local world = CursorToWorld(self)
            if world then
                local stepSq = kGCommMap.MinDrawStep * kGCommMap.MinDrawStep
                local last = self._gcLastSample
                if not last or ((world.x - last.x) ^ 2 + (world.z - last.z) ^ 2) >= stepSq then
                    self._gcLastSample = world
                    -- Reliable so every point reaches the server (stored + replayed identically),
                    -- avoiding dropped points that would vanish on the next map re-open.
                    Client.SendNetworkMessage("GC_Draw",
                        { position = world, erase = (mode == "Erase"), penUp = false }, true)
                end
            end
            self._gcDrewLast = true
        end
    end
end

local baseUpdate = GUIMinimapFrame.Update
function GUIMinimapFrame:Update(deltaTime)
    baseUpdate(self, deltaTime)
    UpdateOverlay(self)
end
