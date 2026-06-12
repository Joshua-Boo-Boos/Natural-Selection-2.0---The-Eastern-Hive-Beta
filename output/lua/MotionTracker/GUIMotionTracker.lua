-- ======================================================================
-- Motion Tracker in-weapon screen — top-down radar matching the in-game map.
--
-- World->screen mapping mirrors NS2's GUIMinimap:PlotToMap so the radar is
-- oriented exactly like the minimap (world Z -> screen X, world X -> screen
-- -Y). This makes the green heading line track the player's yaw the same way
-- the minimap chevron does.
--
-- While active (primary held AND charge > 0) it overlays:
--   [Distance: Xm]     horizontal label, small gap ABOVE the box
--   [white box]        radar region (250x250)
--     UP/EQUAL/DOWN      stacked chars on the LEFT  — nearest alien elevation
--     green dot+line     player position + world-facing heading
--     two white lines    detection wedge edges (+/- half-angle)
--     red dots           detected aliens (already wedge-filtered)
--     LIFEFORM           stacked chars on the RIGHT — nearest alien class
--   [Charge: X%]       horizontal label, small gap BELOW the box
--
-- Side labels are vertically centred inside the box via dynamic Y placement:
-- Align_Center for Y positions the first character at the given Y, and each
-- subsequent newline-separated character extends downward by kSideLabelLineH.
-- GetSideLabelY() compensates by moving the anchor up by half the total block
-- height so the centre of the stacked text aligns with kCenter.
--
-- When inactive, only the honeycomb background shows.
-- ======================================================================

Script.Load("lua/GUIScript.lua")
Script.Load("lua/Utility.lua")

local kScreen  = 400
local kCenter  = kScreen / 2    -- 200
local kHalfBox = 125             -- radar box 250x250 (side/top/bottom gaps = 75px each)
local kBorder  = 3
local kBoxMin  = kCenter - kHalfBox   -- 75
local kBoxMax  = kCenter + kHalfBox   -- 325

-- Horizontal labels: pushed away from the box so there is clear breathing room.
local kLabelGap     = 28
local kDistLabelY   = kBoxMin - kLabelGap   -- 47  (above box with gap)
local kChargeLabelY = kBoxMax + kLabelGap   -- 353 (below box with gap)

-- Vertical side labels: X offset from the box edges.
local kLeftLabelX  = kBoxMin - 30    -- 45  (30 px left of box)
local kRightLabelX = kBoxMax + 30    -- 355 (30 px right of box)

-- Per-line pixel height for the stacked-character side labels.
-- Fonts.kAgencyFB_Small at size 10, scale 1.5 renders each line ~32 px tall.
local kSideLabelLineH = 32

-- How many pixels to shift the side labels upward from the box centre.
local kSideLabelYShift = 20

local kHeadingLength = 68
local kHeadingSegs   = 10
local kWedgeSegs     = 16
local kWedgeLength   = math.floor(kHalfBox * 0.85)
local kMaxBlips      = 32

local kColBox   = Color(1, 1, 1, 1)
local kColText  = Color(0.62, 0.92, 1, 1)
local kColAlert = Color(1, 0.25, 0.25, 1)
local kColGreen = Color(0.25, 1, 0.35, 1)
local kColRed   = Color(1, 0.18, 0.18, 1)
local kColWedge = Color(1, 1, 1, 0.85)

local kDistanceAlert = 5    -- m  — distance label turns red below this
local kChargeAlert   = 10   -- %  — charge label turns red below this

local kLabelScale     = Vector(1, 1, 1) * 1.5   -- horizontal distance/charge labels
local kSideLabelScale = Vector(1, 1, 1) * 1.5   -- vertical stacked side labels

-- Globals pushed by the weapon.
trackerActive       = "false"
trackerCharge       = 0
trackerScale        = 15.5
trackerHalfAngle    = math.rad(24)
trackerNearest      = 0
trackerFaceX        = 0
trackerFaceZ        = 1
trackerBlips        = ""
trackerVertDir      = ""
trackerNearestClass = ""

bulletDisplay = nil

class 'GUIMotionTrackerDisplay'

local function ParseBlips(str)
    local blips = {}
    if str and str ~= "" then
        for pair in string.gmatch(str, "([^;]+)") do
            local rx, rz = string.match(pair, "([^,]+),([^,]+)")
            if rx and rz then
                blips[#blips + 1] = { tonumber(rx) or 0, tonumber(rz) or 0 }
                if #blips >= kMaxBlips then break end
            end
        end
    end
    return blips
end

-- World (relX, relZ) -> screen pixel, matching PlotToMap:
-- screen X follows world +Z, screen Y follows world -X.
local function WorldToScreen(relX, relZ, scale)
    local nx = Clamp(relZ / scale, -1, 1)
    local ny = Clamp(relX / scale, -1, 1)
    return kCenter + nx * kHalfBox, kCenter - ny * kHalfBox
end

local function FaceToScreenDir(faceX, faceZ)
    return faceZ, -faceX
end

local function RotateScreen(x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c
end

-- Returns a string with a newline between every character so it renders as a
-- vertical stack (e.g. "UP" -> "U\nP", "LERK" -> "L\nE\nR\nK").
local function MakeVertical(str)
    if not str or str == "" then return "" end
    local t = {}
    for i = 1, #str do t[i] = str:sub(i, i) end
    return table.concat(t, "\n")
end

-- Returns the Y anchor that visually centres a stacked-character label at
-- kCenter. Align_Center for Y positions the FIRST character at the given Y;
-- each subsequent line extends downward by kSideLabelLineH, so the visual
-- centre of a numLines-tall block is at Y + (numLines-1)*kSideLabelLineH/2.
-- Solving for visual centre == kCenter:
--   Y = kCenter - (numLines - 1) * kSideLabelLineH / 2
local function GetSideLabelY(rawStr)
    local numLines = #rawStr  -- one char per line after MakeVertical
    return kCenter - (numLines - 1) * kSideLabelLineH / 2 - kSideLabelYShift
end

function GUIMotionTrackerDisplay:Initialize()

    self.active       = false
    self.charge       = 0
    self.scale        = 15.5
    self.halfAngle    = math.rad(24)
    self.nearest      = 0
    self.faceX        = 0
    self.faceZ        = 1
    self.blips        = {}
    self.vertDir      = ""
    self.nearestClass = ""

    -- Honeycomb background (always visible).
    self.background = GUIManager:CreateGraphicItem()
    self.background:SetSize( Vector(kScreen, kScreen, 0) )
    self.background:SetPosition( Vector(0, 0, 0) )
    self.background:SetTexture("models/marine/motion_tracker/tracker_display.dds")

    -- White box frame (four thin bars).
    self.frame = {}
    self.frame[1] = self:CreateBar(kBoxMin, kBoxMin, 2 * kHalfBox, kBorder)
    self.frame[2] = self:CreateBar(kBoxMin, kBoxMax - kBorder, 2 * kHalfBox, kBorder)
    self.frame[3] = self:CreateBar(kBoxMin, kBoxMin, kBorder, 2 * kHalfBox)
    self.frame[4] = self:CreateBar(kBoxMax - kBorder, kBoxMin, kBorder, 2 * kHalfBox)

    -- Horizontal labels: distance just above box, charge just below.
    self.distLabel   = self:CreateLabel(kCenter, kDistLabelY,   kLabelScale)
    self.chargeLabel = self:CreateLabel(kCenter, kChargeLabelY, kLabelScale)

    -- Vertical stacked side labels. Y is set dynamically in Update().
    self.vertDirLabel = self:CreateLabel(kLeftLabelX,  kCenter, kSideLabelScale)
    self.classLabel   = self:CreateLabel(kRightLabelX, kCenter, kSideLabelScale)

    -- Detection wedge edges (two segmented white lines).
    self.wedgeA = {}
    self.wedgeB = {}
    for i = 1, kWedgeSegs do
        self.wedgeA[i] = self:CreateDot(3, kColWedge)
        self.wedgeB[i] = self:CreateDot(3, kColWedge)
    end

    -- Green heading line segments.
    self.headSegs = {}
    for i = 1, kHeadingSegs do
        self.headSegs[i] = self:CreateDot(4, kColGreen)
    end

    -- Green player dot at centre.
    self.playerDot = self:CreateDot(10, kColGreen)
    self.playerDot:SetPosition( Vector(kCenter - 5, kCenter - 5, 0) )

    -- Red alien blip pool.
    self.redDots = {}
    for i = 1, kMaxBlips do
        self.redDots[i] = self:CreateDot(10, kColRed)
    end

    self:Update(0)

end

function GUIMotionTrackerDisplay:CreateBar(x, y, w, h)
    local item = GUIManager:CreateGraphicItem()
    item:SetSize( Vector(w, h, 0) )
    item:SetPosition( Vector(x, y, 0) )
    item:SetColor( kColBox )
    self.background:AddChild(item)
    return item
end

function GUIMotionTrackerDisplay:CreateDot(size, color)
    local item = GUIManager:CreateGraphicItem()
    item:SetSize( Vector(size, size, 0) )
    item:SetColor( color )
    item.dotSize = size
    self.background:AddChild(item)
    return item
end

function GUIMotionTrackerDisplay:CreateLabel(cx, cy, scale)
    local text = GUIManager:CreateTextItem()
    text:SetFontName(Fonts.kAgencyFB_Small)
    text:SetFontSize(10)
    text:SetScale(scale or kLabelScale)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Center)
    text:SetColor(kColText)
    text:SetPosition( Vector(cx, cy, 0) )
    self.background:AddChild(text)
    return text
end

local function PlaceLine(segs, dirX, dirY, length)
    local n = #segs
    for i = 1, n do
        local seg = segs[i]
        local t   = (i / n) * length
        local sz  = seg.dotSize
        seg:SetPosition( Vector(kCenter + dirX * t - sz / 2, kCenter + dirY * t - sz / 2, 0) )
        seg:SetIsVisible(true)
    end
end

function GUIMotionTrackerDisplay:SetVisibleOverlay(visible)
    for i = 1, #self.frame    do self.frame[i]:SetIsVisible(visible) end
    for i = 1, #self.headSegs do self.headSegs[i]:SetIsVisible(visible) end
    for i = 1, #self.wedgeA   do self.wedgeA[i]:SetIsVisible(visible) end
    for i = 1, #self.wedgeB   do self.wedgeB[i]:SetIsVisible(visible) end
    self.playerDot:SetIsVisible(visible)
    self.distLabel:SetIsVisible(visible)
    self.chargeLabel:SetIsVisible(visible)
    self.vertDirLabel:SetIsVisible(false)
    self.classLabel:SetIsVisible(false)
    if not visible then
        for i = 1, #self.redDots do self.redDots[i]:SetIsVisible(false) end
    end
end

function GUIMotionTrackerDisplay:Update(deltaTime)

    PROFILE("GUIMotionTrackerDisplay:Update")

    if not self.active then
        self:SetVisibleOverlay(false)
        return
    end

    self:SetVisibleOverlay(true)

    local hasTarget = #self.blips > 0

    -- Distance label: "Distance: Xm" or "--" when no target.
    if hasTarget then
        local d = math.floor(self.nearest + 0.5)
        self.distLabel:SetText(string.format("Distance: %dm", d))
        self.distLabel:SetColor(self.nearest < kDistanceAlert and kColAlert or kColText)
    else
        self.distLabel:SetText("--")
        self.distLabel:SetColor(kColText)
    end

    -- Charge label: "Charge: X%".
    local chargePct = math.floor(self.charge)
    self.chargeLabel:SetText(string.format("Charge: %d%%", chargePct))
    self.chargeLabel:SetColor(chargePct < kChargeAlert and kColAlert or kColText)

    -- Vertical side labels: shown only when a target is detected.
    -- Y is set dynamically so the entire stacked block is visually centred.
    if hasTarget and self.vertDir ~= "" then
        self.vertDirLabel:SetText(MakeVertical(self.vertDir))
        self.vertDirLabel:SetPosition(Vector(kLeftLabelX,  GetSideLabelY(self.vertDir),      0))
        self.vertDirLabel:SetColor(kColText)
        self.vertDirLabel:SetIsVisible(true)
    end
    if hasTarget and self.nearestClass ~= "" then
        self.classLabel:SetText(MakeVertical(self.nearestClass))
        self.classLabel:SetPosition(Vector(kRightLabelX, GetSideLabelY(self.nearestClass), 0))
        self.classLabel:SetColor(kColText)
        self.classLabel:SetIsVisible(true)
    end

    -- Heading line and wedge (screen space).
    local hx, hy = FaceToScreenDir(self.faceX, self.faceZ)
    PlaceLine(self.headSegs, hx, hy, kHeadingLength)

    local ax, ay = RotateScreen(hx, hy,  self.halfAngle)
    local bx, by = RotateScreen(hx, hy, -self.halfAngle)
    PlaceLine(self.wedgeA, ax, ay, kWedgeLength)
    PlaceLine(self.wedgeB, bx, by, kWedgeLength)

    -- Red alien blips (already wedge-filtered by the weapon).
    local scale = self.scale > 0 and self.scale or 1
    for i = 1, kMaxBlips do
        local dot  = self.redDots[i]
        local blip = self.blips[i]
        if blip then
            local sx, sy = WorldToScreen(blip[1], blip[2], scale)
            local sz = dot.dotSize
            dot:SetPosition( Vector(sx - sz / 2, sy - sz / 2, 0) )
            dot:SetIsVisible(true)
        else
            dot:SetIsVisible(false)
        end
    end

end

function GUIMotionTrackerDisplay:SetState(active, charge, scale, halfAngle, nearest, faceX, faceZ, blipStr, vertDir, nearestClass)
    self.active       = (active == "true")
    self.charge       = charge       or 0
    self.scale        = scale        or 15.5
    self.halfAngle    = halfAngle    or math.rad(24)
    self.nearest      = nearest      or 0
    self.faceX        = faceX        or 0
    self.faceZ        = faceZ        or 1
    self.blips        = ParseBlips(blipStr)
    self.vertDir      = vertDir      or ""
    self.nearestClass = nearestClass or ""
end

function Update(deltaTime)
    bulletDisplay:SetState(
        trackerActive, trackerCharge, trackerScale, trackerHalfAngle,
        trackerNearest, trackerFaceX, trackerFaceZ, trackerBlips,
        trackerVertDir, trackerNearestClass)
    bulletDisplay:Update(deltaTime)
end

function Initialize()
    GUI.SetSize( kScreen, kScreen )
    bulletDisplay = GUIMotionTrackerDisplay()
    bulletDisplay:Initialize()
end

Initialize()
