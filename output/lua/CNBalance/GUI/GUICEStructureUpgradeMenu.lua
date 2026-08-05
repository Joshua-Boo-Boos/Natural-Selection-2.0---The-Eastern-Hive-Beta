-- CNBalance/GUI/GUICEStructureUpgradeMenu.lua
-- Combat Engineers: the Combat Builder's right-click structure upgrade window.
--
-- Opened by aiming at a friendly structure in range with a Combat Builder equipped. Shows that
-- structure's own upgrade buttons in a grid, laid out and coloured like the commander's grid so a
-- marine does not have to learn a second visual language:
--   grey = prerequisites unmet, red = team cannot afford it, blue = ready to click.
--
-- Upgrades cost TEAM resources. Personal resources buy structures; team resources upgrade them.
--
-- The button list comes from the structure's own GetTechButtons() via
-- GetCEStructureUpgradeTechIds, so it can never drift from what the commander would see.

Script.Load("lua/GUIAnimatedScript.lua")

class 'GUICEStructureUpgradeMenu' (GUIAnimatedScript)

GUICEStructureUpgradeMenu.kMockupSize = Vector(2880, 1620, 0)

local kBackgroundTexture = PrecacheAsset("ui/buymenu_marine/prototypelab_background.dds")
local kIconTexture       = "ui/buildmenu.dds"

-- Panel. Width/height are DYNAMIC (see BuildLayout) - these are margins, not a fixed size.
local kPanelMarginX      = 90
local kPanelMarginBottom = 60
local kTitleY    = 40
local kSubTitleY = 120

-- Grid. kCellH has to fit icon + label + cost text stacked vertically: the label sits right below
-- the icon, and the cost sits below THAT - the previous 190 packed those two text rows only 28px
-- apart, which is not enough room for one 26pt bold line (let alone a longer tech name like
-- "EMERGENCY EJECTION" overflowing sideways into the next column) - the label and cost clipped into
-- each other. 250 gives each row real breathing space.
local kColumns    = 4
local kIconSize   = 120
local kCellW      = 230
local kCellH      = 250
local kGridTopY   = 210
local kLabelOffsetY = 128  -- below the icon's top-left cell origin
local kCostOffsetY  = 176  -- below the icon, WELL clear of the label above it

-- Colours, matching the Prototype Lab window's language.
local kColorLocked          = Color(0.30, 0.30, 0.32, 0.85)
local kColorUnaffordable    = Color(0.85, 0.30, 0.30, 1)
local kColorAvailable       = Color(0.45, 0.75, 1.00, 1)
local kColorHover           = Color(1,    1,    1,    1)
local kColorHeader          = Color(0.72, 0.88, 0.95, 1)
local kColorLabel           = Color(0.92, 0.97, 1.00, 1)

local kFontSizeTitle    = 46
local kFontSizeSubTitle = 38
local kFontSizeLabel    = 26
local kFontSizePopup    = 30

-- Hover description popup
local kPopupLineH        = 40
local kPopupPadY         = 18
local kPopupPadX         = 26
local kPopupCursorOffset = 22
local kPopupMaxLines     = 12

local function WrapText(text, maxChars)

    local lines = {}

    for paragraph in (text .. "\n"):gmatch("(.-)\n") do

        local line = ""

        for word in paragraph:gmatch("%S+") do
            if #line == 0 then
                line = word
            elseif #line + #word + 1 <= maxChars then
                line = line .. " " .. word
            else
                table.insert(lines, line)
                line = word
            end
        end

        table.insert(lines, line)
    end

    return lines
end

function GUICEStructureUpgradeMenu:Initialize()

    GUIAnimatedScript.Initialize(self)

    self.customScale       = Client.GetScreenHeight() / GUICEStructureUpgradeMenu.kMockupSize.y
    self.customScaleVector = Vector(1, 1, 1) * self.customScale

    self.buttons  = {}
    self.structure = nil

    MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
end

function GUICEStructureUpgradeMenu:SetStructure(structure)

    self.structure = structure
    self:BuildLayout()
end

function GUICEStructureUpgradeMenu:GetStructure()
    return self.structure
end

function GUICEStructureUpgradeMenu:BuildLayout()

    local s = self

    -- Size the panel to how many upgrades this structure actually has, rather than always paying
    -- for a fixed 1000x720 window - a one-button structure (Extractor) gets a small window, a
    -- five-button one (Armory) gets a wider one, instead of both using the same oversized panel.
    local techIds = GetCEStructureUpgradeTechIds(self.structure)
    local count   = math.max(#techIds, 1)
    local columns = math.min(count, kColumns)
    local rows    = math.max(1, math.ceil(count / kColumns))

    local bgWidth  = math.max(560, columns * kCellW + kPanelMarginX * 2)
    local bgHeight = kGridTopY + rows * kCellH + kPanelMarginBottom

    self.root = self:CreateAnimatedGraphicItem()
    self.root:SetIsScaling(false)
    self.root:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.root:SetHotSpot(Vector(0.5, 0.5, 0))
    self.root:SetTexture(kBackgroundTexture)
    self.root:SetSize(Vector(bgWidth, bgHeight, 0))
    self.root:SetColor(Color(0.55, 0.60, 0.65, 1.0))
    self.root:SetScale(self.customScaleVector)
    self.root:SetOptionFlag(GUIItem.CorrectScaling)
    self.root:SetLayer(kGUILayerMarineBuyMenu)

    local function MakeCenteredText(text, fontSize, centreX, y, color)
        local item = s:CreateAnimatedTextItem()
        item:SetIsScaling(false)
        item:AddAsChildTo(s.root)
        item:SetPosition(Vector(centreX, y, 0))
        item:SetAnchor(GUIItem.Left, GUIItem.Top)
        item:SetTextAlignmentX(GUIItem.Align_Center)
        item:SetTextAlignmentY(GUIItem.Align_Min)
        item:SetText(text)
        item:SetColor(color or kColorLabel)
        item:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(item, "kAgencyFBBold", fontSize)
        return item
    end

    local midX = bgWidth * 0.5

    MakeCenteredText("Brazier Industries Combat Engineer", kFontSizeTitle, midX, kTitleY, kColorHeader)
    MakeCenteredText("Structure Upgrade System v3.5",      kFontSizeTitle, midX, kTitleY + 52, kColorHeader)

    local structureName = self.structure
        and Locale.ResolveString(LookupTechData(self.structure:GetTechId(), kTechDataDisplayName, "")) or ""

    MakeCenteredText(string.upper(structureName), kFontSizeSubTitle, midX, kSubTitleY + 30, kColorHeader)

    -- ---- Upgrade grid ----
    local gridW  = columns * kCellW
    local gridX0 = (bgWidth - gridW) * 0.5

    for i, techId in ipairs(techIds) do

        local column = (i - 1) % kColumns
        local row    = math.floor((i - 1) / kColumns)

        local cellX = gridX0 + column * kCellW
        local cellY = kGridTopY + row * kCellH

        local icon = self:CreateAnimatedGraphicItem()
        icon:SetIsScaling(false)
        icon:AddAsChildTo(self.root)
        icon:SetAnchor(GUIItem.Left, GUIItem.Top)
        icon:SetPosition(Vector(cellX + (kCellW - kIconSize) * 0.5, cellY, 0))
        icon:SetSize(Vector(kIconSize, kIconSize, 0))
        icon:SetTexture(kIconTexture)
        icon:SetTexturePixelCoordinates(GUIUnpackCoords(GetTextureCoordinatesForIcon(techId)))
        icon:SetOptionFlag(GUIItem.CorrectScaling)

        -- Tech name under each icon, as specified.
        local label = self:CreateAnimatedTextItem()
        label:SetIsScaling(false)
        label:AddAsChildTo(self.root)
        label:SetAnchor(GUIItem.Left, GUIItem.Top)
        label:SetPosition(Vector(cellX + kCellW * 0.5, cellY + kLabelOffsetY, 0))
        label:SetTextAlignmentX(GUIItem.Align_Center)
        label:SetTextAlignmentY(GUIItem.Align_Min)
        label:SetText(Locale.ResolveString(LookupTechData(techId, kTechDataDisplayName, "")))
        label:SetColor(kColorLabel)
        label:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(label, "kAgencyFBBold", kFontSizeLabel)

        -- Cost, so the red state is explicable rather than mysterious.
        local costText = self:CreateAnimatedTextItem()
        costText:SetIsScaling(false)
        costText:AddAsChildTo(self.root)
        costText:SetAnchor(GUIItem.Left, GUIItem.Top)
        costText:SetPosition(Vector(cellX + kCellW * 0.5, cellY + kCostOffsetY, 0))
        costText:SetTextAlignmentX(GUIItem.Align_Center)
        costText:SetTextAlignmentY(GUIItem.Align_Min)
        costText:SetColor(kColorLabel)
        costText:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(costText, "kAgencyFBBold", kFontSizeLabel)

        table.insert(self.buttons, { TechId = techId, Item = icon, Label = label, CostText = costText })
    end

    if #techIds == 0 then
        MakeCenteredText("NO UPGRADES AVAILABLE", kFontSizeSubTitle, midX, kGridTopY + 40, kColorLocked)
    end

    -- ---- Hover popup ----
    self.popup = self:CreateAnimatedGraphicItem()
    self.popup:SetIsScaling(false)
    self.popup:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.popup:SetHotSpot(Vector(0, 0, 0))
    self.popup:SetSize(Vector(400, 200, 0))
    self.popup:SetScale(self.customScaleVector)
    self.popup:SetTexture(kBackgroundTexture)
    self.popup:SetColor(Color(0.45, 0.52, 0.58, 0.98))
    self.popup:SetOptionFlag(GUIItem.CorrectScaling)
    self.popup:SetLayer(kGUILayerMarineBuyMenu + 1)
    self.popup:SetIsVisible(false)

    self.popupLines = {}
    for i = 1, kPopupMaxLines do
        local lineItem = self:CreateAnimatedTextItem()
        lineItem:SetIsScaling(false)
        lineItem:AddAsChildTo(self.popup)
        lineItem:SetAnchor(GUIItem.Middle, GUIItem.Top)
        lineItem:SetTextAlignmentX(GUIItem.Align_Center)
        lineItem:SetTextAlignmentY(GUIItem.Align_Min)
        lineItem:SetPosition(Vector(0, kPopupPadY, 0))
        lineItem:SetColor(kColorLabel)
        lineItem:SetText("")
        lineItem:SetOptionFlag(GUIItem.CorrectScaling)
        lineItem:SetIsVisible(false)
        GUIMakeFontScale(lineItem, "kAgencyFB", kFontSizePopup)
        self.popupLines[i] = lineItem
    end
end

function GUICEStructureUpgradeMenu:GetIsVisible()
    return self.root ~= nil and self.root:GetIsVisible()
end

function GUICEStructureUpgradeMenu:SetIsVisible(visible)
    if self.root then self.root:SetIsVisible(visible) end
    if self.popup and not visible then self.popup:SetIsVisible(false) end
end

function GUICEStructureUpgradeMenu:Update(deltaTime)

    if not self.root then return end

    local player = Client.GetLocalPlayer()

    -- Close if the structure died, the marine walked away, or they put the builder away.
    if not player or not self.structure or not self.structure:GetIsAlive()
       or not player:GetWeapon(CombatBuilder.kMapName)
       or (self.structure:GetOrigin() - player:GetOrigin()):GetLength() > kCombatEngineersUpgradeRange * 1.5 then
        CEStructureUpgrade_Close()
        return
    end

    local mouseX, mouseY = Client.GetCursorPosScreen()
    local hoveredTechId  = nil

    for _, button in ipairs(self.buttons) do

        local over = GUIItemContainsPoint(button.Item, mouseX, mouseY, true)
        if over then hoveredTechId = button.TechId end

        local available, affordable, cost = GetCEStructureUpgradeState(self.structure, button.TechId, player)

        local color
        if not available then
            color = kColorLocked
        elseif not affordable then
            color = kColorUnaffordable
        elseif over then
            color = kColorHover
        else
            color = kColorAvailable
        end

        button.Item:SetColor(color)
        button.Label:SetColor(color)
        button.CostText:SetColor(color)
        button.CostText:SetText(string.format("%d", cost))
    end

    self:UpdatePopup(hoveredTechId)
end

function GUICEStructureUpgradeMenu:UpdatePopup(hoveredTechId)

    if not self.popup then return end

    if not hoveredTechId then
        self.popup:SetIsVisible(false)
        return
    end

    local raw = LookupTechData(hoveredTechId, kTechDataTooltipInfo, nil)
    local desc = raw and Locale.ResolveString(raw) or nil

    -- Some vanilla tech entries (Mines' research node is one) were never given a
    -- kTechDataTooltipInfo, since the commander HUD they were authored for never shows one for that
    -- button. This window always has room for one, so fall back to a generic line built from the
    -- name and cost rather than showing nothing.
    if not desc or desc == "" then
        local name = Locale.ResolveString(LookupTechData(hoveredTechId, kTechDataDisplayName, "?"))
        local cost = GetCostForTech and GetCostForTech(hoveredTechId) or LookupTechData(hoveredTechId, kTechDataCostKey, 0)
        desc = string.format("%s\n\n+Unlock this technology.\nCost: %d team resources.", string.upper(name), cost or 0)
    end

    local lines = WrapText(desc, 36)
    local maxW  = 0

    for i = 1, kPopupMaxLines do
        local item = self.popupLines[i]
        if lines[i] then
            item:SetText(lines[i])
            item:SetPosition(Vector(0, kPopupPadY + (i - 1) * kPopupLineH, 0))
            item:SetIsVisible(true)
            maxW = math.max(maxW, item:GetTextWidth(lines[i]) * item:GetScale().x)
        else
            item:SetIsVisible(false)
        end
    end

    local shown    = math.min(#lines, kPopupMaxLines)
    local designH  = shown * kPopupLineH + kPopupPadY * 2
    local designW  = maxW + kPopupPadX * 2
    self.popup:SetSize(Vector(designW, designH, 0))

    local cs = self.customScale
    local pw, ph = designW * cs, designH * cs
    local mx, my = Client.GetCursorPosScreen()
    local px = mx + kPopupCursorOffset * cs
    local py = my + kPopupCursorOffset * cs
    local sw, sh = Client.GetScreenWidth(), Client.GetScreenHeight()

    if px + pw > sw then px = mx - kPopupCursorOffset * cs - pw end
    if py + ph > sh then py = sh - ph end
    if px < 0 then px = 0 end
    if py < 0 then py = 0 end

    self.popup:SetPosition(Vector(px, py, 0))
    self.popup:SetIsVisible(true)
end

-- Reached from InputHandler BEFORE the player's own handler, so returning true stops a click in the
-- window from also firing the weapon behind it.
function GUICEStructureUpgradeMenu:SendKeyEvent(key, down)

    if not self:GetIsVisible() then
        return false
    end

    if key == InputKey.Escape then
        if not down then
            CEStructureUpgrade_Close()
        end
        return true
    end

    -- Right-click is SWALLOWED (so it never reaches the world) but must NOT close the window here.
    -- Closing on the release of the very click that opened it is exactly what forced the player to
    -- hold the button down to keep the window up. The open/close toggle belongs to
    -- CombatBuilder:OnSecondaryAttack, which is press-edge guarded - so a full press-and-release
    -- opens it, and the NEXT press closes it.
    if key == InputKey.MouseButton1 then
        return true
    end

    if key ~= InputKey.MouseButton0 then
        return false
    end

    if down then

        local mouseX, mouseY = Client.GetCursorPosScreen()
        local player = Client.GetLocalPlayer()

        for _, button in ipairs(self.buttons) do

            if GUIItemContainsPoint(button.Item, mouseX, mouseY, true) then

                local available, affordable = GetCEStructureUpgradeState(self.structure, button.TechId, player)

                if available and affordable then
                    Client.SendNetworkMessage("CEStructureUpgrade",
                        { entityId = self.structure:GetId(), techId = button.TechId }, true)
                    CEStructureUpgrade_Close()
                end

                return true
            end
        end
    end

    -- Swallow every other click while the window is up.
    return true
end

function GUICEStructureUpgradeMenu:Uninitialize()

    GUIAnimatedScript.Uninitialize(self)

    self.root       = nil
    self.popup      = nil
    self.popupLines = {}
    self.buttons    = {}
    self.structure  = nil

    MouseTracker_SetIsVisible(false)
end
