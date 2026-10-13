--[[
    ARCUS (ARC Upgrade System) - the specialisations on the Marines' J-menu tech map (GUITechMap), for the Commander and
    spectators.

    Three branches leave the ARC Factory / ARC: up-right to H.A.M.M.E.R., right to V.A.T., down-right to H.E.L.L.; each
    name then has its four upgrades in a horizontal row - Level 1, Level 2, Level 3, Level 4 - joined by short lines:

        ARC Factory - ARC  /  H.A.M.M.E.R. - Level 1 - Level 2 - Level 3 - Level 4
                           -  V.A.T.       - Level 1 - Level 2 - Level 3 - Level 4
                           \  H.E.L.L.     - Level 1 - Level 2 - Level 3 - Level 4

    Lighting, from the ARCUS team state the research tray already uses (ARCSpecTeamState, ARCSpec_Shots.lua - TeamInfo's
    tech bitmask is full, so the normal J-menu colouring cannot see these techs):
      * the branch line and the name light up once that specialisation exists (a factory has been converted);
      * each Level and the short line leading to it light up as that level is researched;
      * if every factory of a specialisation is destroyed, its researched parts turn red (as in the research tray) - they
        come back with a new factory of it;
      * anything not researched yet stays grey.
    Hovering a name or a level shows that tech's tooltip.

    The words are the research tray's own ARCUS icons (ui/arcus/<key>_level<n>.dds: the acronym on the top half, "Level n"
    on the bottom half): a name uses the top half of level 0's icon, Level n the bottom half of level n's icon. No new
    assets. The map's panel is widened by two cells (kExtraColumns) so the four levels fit inside it; the panel stays
    centred.

    Client only. Loaded at the end of lua/CNBalance/GUI/GUITechMap.lua (the post hook on lua/GUITechMap.lua).
]]

if not Client or not GUITechMap or GUITechMap.arcusTechMap then return end
GUITechMap.arcusTechMap = true

--[[
    Text crops: the exact pixel box of the text in each research-tray icon (measured from the .dds files). The tray fits
    each acronym to the icon's width, so V.A.T. and H.E.L.L. are drawn much taller there than H.A.M.M.E.R. (26 / 21 / 14
    px letters); cropping tight to the text and giving every crop the same on-screen letter height (kTextHeight) makes
    all three names and the Level labels the same size. Each crop's width follows from its own aspect ratio.
]]
local kNamePixels =
{
    hammer   = { 6, 15, 95, 29 },
    vanguard = { 6, 9, 93, 35 },
    inferno  = { 4, 11, 97, 32 },
}
local kLevelPixels = { 13, 56, 89, 76 }     -- "Level n", bottom half (the same box in every icon)
local kTextHeight = 0.18                    -- letter height, in cells

--[[
    Layout (2026-10-13, second pass), in tech-map cells (one cell = one icon) before the map's own vertical offset:
    names LEFT-ALIGNED just right of the ARC, then a fixed column for Level 1-4 so the levels line up row to row like a
    table. Every row gets a clear line from its name into Level 1 (longer for the shorter names) and kLevelGap-long lines
    between the levels. The panel is widened by kExtraColumns so the rows end kRightMargin inside it - the margin the map
    already has on its left.
]]
local kBranchOrigin = { 11.5, 0 }           -- the ARC's centre (it sits right of the ARC Factory, at 11, -0.5)
local kRows = { hammer = -1.0, vanguard = 0, inferno = 1.0 }
local kNameLeft = 12.12                     -- just clear of the ARC's right edge (12)
local kLevel1Left = 13.6                    -- 0.34 past the longest name (H.A.M.M.E.R.)
local kLevelGap = 0.3                       -- line length between two levels
local kLineGap = 0.04                       -- space left between a line's end and the text
local kRightMargin = 0.45
local kBaseColumns = 15                     -- vanilla GUITechMap's panel width, in cells

local function GetTextWidth(pixels)
    return kTextHeight * (pixels[3] - pixels[1]) / (pixels[4] - pixels[2])
end

local kLevelWidth = GetTextWidth(kLevelPixels)
local kRowRight = kLevel1Left + 4 * kLevelWidth + 3 * kLevelGap
local kExtraColumns = math.max(0, kRowRight + kRightMargin - kBaseColumns)

local kLitColor = Color(0.8, 1, 1, 1)
local kUnlitColor = Color(0.35, 0.35, 0.35, 1)
local kLostColor = Color(1, 0.2, 0.2, 1)
local kLineLitColor = Color(0, 0.8, 1, 0.9)
local kLineUnlitColor = Color(0.3, 0.3, 0.3, 0.5)
local kLineLostColor = Color(1, 0.2, 0.2, 0.7)

local kTextures = {}
for _, key in ipairs({ "hammer", "vanguard", "inferno" }) do
    kTextures[key] = {}
    for level = 0, 4 do
        kTextures[key][level] = PrecacheAsset(string.format("ui/arcus/%s_level%d.dds", key, level))
    end
end

local function GetCellSize()
    return GUIScale(Vector(56, 56, 0))     -- vanilla GUITechMap's icon (cell) size
end

local function ToPixels(cellSize, x, y)
    return Vector(x * cellSize.x, (y + kMarineTechMapYStart) * cellSize.y, 0)
end

-- A text crop, centred on (cx, cy) cells.
local function CreateWord(self, cellSize, texture, pixels, cx, cy, size)
    local item = GetGUIManager():CreateGraphicItem()
    local pixelSize = Vector(size[1] * cellSize.x, size[2] * cellSize.y, 0)
    item:SetSize(pixelSize)
    item:SetPosition(ToPixels(cellSize, cx, cy) - pixelSize * 0.5)
    item:SetTexture(texture)
    item:SetTexturePixelCoordinates(pixels[1], pixels[2], pixels[3], pixels[4])
    item:SetColor(kUnlitColor)
    item:SetLayer(1)
    self.background:AddChild(item)
    return item
end

-- A straight line between two points in cells (vanilla GUITechMap's own construction).
local function CreateLine(self, cellSize, x1, y1, x2, y2)
    local startPoint = ToPixels(cellSize, x1, y1)
    local endPoint = ToPixels(cellSize, x2, y2)
    local delta = startPoint - endPoint
    local length = math.sqrt(delta.x ^ 2 + delta.y ^ 2)
    local direction = GetNormalizedVector(delta)
    local rotation = math.atan2(direction.x, direction.y)
    if rotation < 0 then
        rotation = rotation + math.pi * 2
    end
    rotation = rotation + math.pi * 0.5

    local line = GetGUIManager():CreateGraphicItem()
    line:SetSize(Vector(length, 2, 0))
    line:SetPosition(startPoint)
    line:SetRotationOffset(Vector(-length, 0, 0))
    line:SetRotation(Vector(0, 0, rotation))
    line:SetColor(kLineUnlitColor)
    line:SetLayer(0)
    self.background:AddChild(line)
    return line
end

local function CreateARCUSNodes(self)

    local cellSize = GetCellSize()

    -- Widen the panel to the right by kExtraColumns cells and keep it centred (every node is a child of it, so the
    -- whole map moves with it).
    local size = self.background:GetSize()
    size.x = size.x + kExtraColumns * cellSize.x
    self.background:SetSize(size)
    self.background:SetPosition(-size * 0.5)

    self.arcusNodes = {}

    for _, spec in ipairs(ARCSpec.kSpecOrder) do

        local row = kRows[spec.key]
        local namePixels = kNamePixels[spec.key]
        local nameWidth = GetTextWidth(namePixels)
        local node =
        {
            spec = spec,
            branch = CreateLine(self, cellSize, kBranchOrigin[1], kBranchOrigin[2], kNameLeft - kLineGap, row),
            name = CreateWord(self, cellSize, kTextures[spec.key][0], namePixels, kNameLeft + nameWidth * 0.5, row,
                              { nameWidth, kTextHeight }),
            levels = {},
            links = {},
        }

        local previousRight = kNameLeft + nameWidth
        for level = 1, 4 do
            local left = kLevel1Left + (level - 1) * (kLevelWidth + kLevelGap)
            node.links[level] = CreateLine(self, cellSize, previousRight + kLineGap, row, left - kLineGap, row)
            node.levels[level] = CreateWord(self, cellSize, kTextures[spec.key][level], kLevelPixels,
                                            left + kLevelWidth * 0.5, row, { kLevelWidth, kTextHeight })
            previousRight = left + kLevelWidth
        end

        self.arcusNodes[#self.arcusNodes + 1] = node

    end

end

local function UpdateARCUSNodes(self)

    local teamState = ARCSpec.teamState and ARCSpec.teamState[kTeam1Index]
    local mouseX, mouseY = Client.GetCursorPosScreen()

    for _, node in ipairs(self.arcusNodes) do

        local info = teamState and teamState[node.spec.key]
        local state = info and info.state or 0
        local level = (info and Clamp(info.level or 0, 0, 4)) or 0

        local lit = state == 2 and kLostColor or kLitColor
        local lineLit = state == 2 and kLineLostColor or kLineLitColor

        node.name:SetColor(state > 0 and lit or kUnlitColor)
        node.branch:SetColor(state > 0 and lineLit or kLineUnlitColor)

        for i = 1, 4 do
            local researched = state > 0 and level >= i
            node.levels[i]:SetColor(researched and lit or kUnlitColor)
            node.links[i]:SetColor(researched and lineLit or kLineUnlitColor)
        end

        -- Tooltips: the conversion research on the name, each upgrade on its level.
        if not self.hoverTechId then
            if GUIItemContainsPoint(node.name, mouseX, mouseY) then
                self.hoverTechId = node.spec.upgrade
            else
                for i = 1, 4 do
                    if GUIItemContainsPoint(node.levels[i], mouseX, mouseY) then
                        self.hoverTechId = node.spec.upgrades[i]
                        break
                    end
                end
            end
        end

    end

end

local baseInitialize = GUITechMap.Initialize
function GUITechMap:Initialize(...)
    baseInitialize(self, ...)
    self.arcusNodes = nil
    if self.teamType == kMarineTeamType and self.background and ARCSpec and ARCSpec.kSpecOrder then
        local ok, err = pcall(CreateARCUSNodes, self)
        if not ok then
            self.arcusNodes = nil
            Print("[ARCUS] tech map: %s", tostring(err))
        end
    end
end

local baseUninitialize = GUITechMap.Uninitialize
function GUITechMap:Uninitialize(...)
    self.arcusNodes = nil      -- children of the background, destroyed with it
    return baseUninitialize(self, ...)
end

local baseUpdate = GUITechMap.Update
function GUITechMap:Update(deltaTime, ...)
    baseUpdate(self, deltaTime, ...)
    if self.arcusNodes and self.background and self.background:GetIsVisible() then
        local ok, err = pcall(UpdateARCUSNodes, self)
        if not ok and not self.arcusUpdateErrorShown then
            self.arcusUpdateErrorShown = true
            Print("[ARCUS] tech map: %s", tostring(err))
        end
    end
end
