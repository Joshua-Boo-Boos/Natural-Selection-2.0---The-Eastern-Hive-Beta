-- CNBalance/GUI/GUICommanderExoDropMenu.lua
-- Marine Commander Exosuit drop window.
--
-- The Prototype Lab buy window (CNBalance/GUI/GUIPrototypeLabBuyMenu.lua) with the jetpack and
-- cannon tracks removed: only the six Exo combos and the five Exosuit Experimental
-- Technologies upgrades, priced in TEAM resources instead of personal ones. Button states read
-- exactly as they do for a marine at a Prototype Lab - blue affordable, green selected, red
-- unaffordable, dark grey locked - so the commander does not have to learn a second language.
--
-- Everything gating-related is read from the SHARED helpers in PrototypeTechData.lua and
-- CNBalance/CommanderExoDrop.lua, which the server also uses to re-validate the purchase, so
-- this window can never offer something the server would then refuse.
--
-- Opened and closed by CNBalance/CommanderExoDrop.lua; BUY hands the configuration back to
-- MarineCommanderExoDrop_Confirm, which sends it and arms the placement ghost.
--
-- The commander's mouse cursor is already visible while commanding, so - unlike the marine
-- window - this script must NOT touch MouseTracker: hiding it on close would leave the
-- commander without a cursor.

Script.Load("lua/GUIAnimatedScript.lua")

class 'GUICommanderExoDropMenu' (GUIAnimatedScript)

GUICommanderExoDropMenu.kMockupSize = Vector(2880, 1620, 0)

local kBackgroundTexture = PrecacheAsset("ui/buymenu_marine/prototypelab_background.dds")

-- Same "big picture" gear atlas the Prototype Lab window uses; cell 0 is the generic Exo render.
local kBigPicturesTexture = PrecacheAsset("ui/buymenu_marine/prototypelab_bigicons.dds")
local kBigPicCellW    = 403
local kBigPicCellH    = 424
local kBigPicIndexExo = 0

-- Button fill colours per state (identical to the Prototype Lab window).
local kBtnColorLocked          = Color(0.07, 0.07, 0.08, 0.82)
local kBtnColorExpensive       = Color(0.50, 0.10, 0.10, 0.42)
local kBtnColorExpensiveHover  = Color(0.72, 0.16, 0.16, 0.50)
local kBtnColorSelected        = Color(0.05, 0.42, 0.16, 0.92)
local kBtnColorAffordable      = Color(0.13, 0.40, 0.72, 0.80)
local kBtnColorAffordableHover = Color(0.22, 0.56, 0.92, 0.88)
local kBtnColorFooterReady     = Color(0.02, 0.45, 0.72, 0.94)
local kBtnColorFooterHover     = Color(0.06, 0.66, 0.98, 0.98)
local kBtnColorFooterDim       = Color(0.08, 0.08, 0.09, 0.82)

-- Text colours
local kColorNormal       = Color(1,    1,    1,    1)
local kColorSelectedText = Color(0.55, 0.90, 1,    1)
local kColorDim          = Color(0.45, 0.45, 0.45, 1)
local kColorHeader       = Color(0.72, 0.88, 0.95, 1)
local kColorUpgradeOn    = Color(0.4,  1,    0.55, 1)
local kColorTooExpensive = Color(0.85, 0.30, 0.30, 1)

-- Font sizes (design pixels)
local kFontSizeTitle    = 70
local kFontSizeSubTitle = 50
local kFontSizeHeader   = 36
local kFontSizeButton   = 30
local kFontSizeFooter   = 42
local kFontSizePopup    = 36

-- Layout constants (design pixels on the 2880x1620 reference canvas). Narrower and shorter
-- than the Prototype Lab window because two of its three tracks are gone.
local kBgWidth  = 1180
local kBgHeight = 1010
local kMarginX  = 80

local kTitleY     = 36
local kColHeaderY = 175
local kBaseRowY   = 235

local kBtnH     = 66
local kRowGapY  = 16
local kRowPitch = kBtnH + kRowGapY

-- Per-column width estimation (each column is sized to its longest label).
local kBtnFontCharW = 16
local kBtnPadX      = 9
local kBtnMinW      = 90

local kExpBtnPadX      = 4
local kExpBtnFontCharW = 14
local kExpSubGap       = 26

local kDividerY = kBaseRowY + 3 * kRowPitch + 30
local kDividerH = 3

local kExpHeaderY  = kDividerY + kDividerH + 30
local kExpSubHeadY = kExpHeaderY + 48
local kExpRowY     = kExpSubHeadY + 60

local kFooterBtnW = 520
local kFooterBtnH = 60
local kFooterY    = kBgHeight - 92

-- Hover description popup
local kPopupW           = 500
local kPopupLineH       = 46
local kPopupPadY        = 22
local kPopupPadX        = 30
local kPopupCursorOffset = 24
local kPopupMaxLines    = 16

local kExoTrack = "exo"

-- ============================================================
-- Helpers
-- ============================================================
local function GetDisplayName(techId)
    return Locale.ResolveString(LookupTechData(techId, kTechDataDisplayName, "?"))
end

local kButtonLabelOverride =
{
    [kTechId.DualMinigunExosuit] = "DUAL MINIGUN",
    [kTechId.DualRailgunExosuit] = "DUAL RAILGUN",
}

-- Prices shown are TEAM resources, not the marine's personal price.
local function BtnLabelText(techId)
    local name = kButtonLabelOverride[techId] or string.upper(GetDisplayName(techId))
    return string.format("%s  %d", name, GetCommanderExoDropCost(techId))
end

local function LabelWidth(label, padX, charW)
    return math.max(kBtnMinW, #label * (charW or kBtnFontCharW) + (padX or kBtnPadX) * 2)
end

local function ColumnWidth(techIds, padX, charW)
    local w = kBtnMinW
    for _, techId in ipairs(techIds) do
        w = math.max(w, LabelWidth(BtnLabelText(techId), padX, charW))
    end
    return w
end

-- ============================================================
-- Hover descriptions. Same text as the Prototype Lab window, plus the t-res note on the
-- title line so the commander is never guessing which resource pool is being spent.
-- ============================================================
local function BuildDescriptions()

    local d = {}

    d[kTechId.DualMinigunExosuit]      = "DUAL MINIGUNS\n\nTwo rapid-fire miniguns\nfor sustained damage."
    d[kTechId.DualRailgunExosuit]      = "DUAL RAILGUNS\n\nTwo charge railguns.\nHold to charge, release\nto fire a powerful shot.\n\nRequires the Gauss (Cannon)\ntech researched\n(Prototype Lab -> Gauss)."
    d[kTechId.DualFlamethrowerExosuit] = "DUAL FLAMETHROWERS\n\nTwin flame projectors.\n5 seconds of fire before\noverheat; 5 sec cooldown."
    d[kTechId.MinigunClawExosuit]      = "MINIGUN + CLAW\n\nRight: rapid-fire minigun.\nLeft: claw (melee strike)."
    d[kTechId.RailgunClawExosuit]      = "RAILGUN + CLAW\n\nRight: charge railgun.\nLeft: claw (melee strike).\n\nRequires the Gauss (Cannon)\ntech researched\n(Prototype Lab -> Gauss)."
    d[kTechId.FlamethrowerClawExosuit] = "FLAMETHROWER + CLAW\n\nRight: flame projector\n(5 sec before overheat).\nLeft: claw (melee strike)."

    d[kTechId.PrototypeExoArmour]         = "ARMOUR PLATING\n\n+100 armour points\nto the exosuit."
    d[kTechId.PrototypeExoExtraFuel]      = "EXTRA FUEL\n\nExo thruster fuel\nlasts 30% longer."
    d[kTechId.PrototypeEmergencyEjection] = "EMERGENCY EJECTION\n\nSurvive a lethal hit by\nautomatically ejecting.\nThe exosuit is lost."
    d[kTechId.PrototypeSelfDestruct]      = "SELF-DESTRUCT\n\nOn death: damage to aliens\nwithin 5m.\nDamage: 100/0m -> 0/5m."
    d[kTechId.PrototypeResupply]          = "RESUPPLY\n\nTeammates press USE on\nyou to receive ammo.\n15 second cooldown.\n10 charges per exosuit\n(persists if you eject)."

    return d
end

-- ============================================================
-- Initialize
-- ============================================================
function GUICommanderExoDropMenu:Initialize()

    GUIAnimatedScript.Initialize(self)

    self.customScale       = Client.GetScreenHeight() / GUICommanderExoDropMenu.kMockupSize.y
    self.customScaleVector = Vector(1, 1, 1) * self.customScale

    self.selectedBase     = nil    -- exactly one combo, or nil
    self.selectedUpgrades = {}     -- upgradeTechId -> true

    self.buttons         = {}
    self.mouseOverStates = {}
    self.descriptions    = BuildDescriptions()

    self:BuildLayout()
end

-- ============================================================
-- BuildLayout
-- ============================================================
function GUICommanderExoDropMenu:BuildLayout()

    local s = self

    self.root = self:CreateAnimatedGraphicItem()
    self.root:SetIsScaling(false)
    self.root:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.root:SetHotSpot(Vector(0.5, 0.5, 0))
    self.root:SetTexture(kBackgroundTexture)
    self.root:SetSize(Vector(kBgWidth, kBgHeight, 0))
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
        item:SetColor(color or kColorNormal)
        item:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(item, "kAgencyFBBold", fontSize)
        return item
    end

    local function MakeButton(text, x, y, w, h, fillColor, textColor, fontSize)
        local rect = s:CreateAnimatedGraphicItem()
        rect:SetIsScaling(false)
        rect:AddAsChildTo(s.root)
        rect:SetPosition(Vector(x, y, 0))
        rect:SetAnchor(GUIItem.Left, GUIItem.Top)
        rect:SetSize(Vector(w, h, 0))
        rect:SetColor(fillColor or kBtnColorLocked)
        rect:SetOptionFlag(GUIItem.CorrectScaling)

        local label = s:CreateAnimatedTextItem()
        label:SetIsScaling(false)
        label:AddAsChildTo(rect)
        label:SetPosition(Vector(w * 0.5, h * 0.5, 0))
        label:SetAnchor(GUIItem.Left, GUIItem.Top)
        label:SetTextAlignmentX(GUIItem.Align_Center)
        label:SetTextAlignmentY(GUIItem.Align_Center)
        label:SetText(text)
        label:SetColor(textColor or kColorNormal)
        label:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(label, "kAgencyFBBold", fontSize or kFontSizeButton)
        return rect, label
    end

    local function AddButton(techId, kind, rect, label)
        table.insert(s.buttons, { TechId = techId, Kind = kind, Item = rect, Label = label })
    end

    local kExoDual = { kTechId.DualMinigunExosuit, kTechId.DualRailgunExosuit, kTechId.DualFlamethrowerExosuit }
    local kExoClaw = { kTechId.MinigunClawExosuit, kTechId.RailgunClawExosuit, kTechId.FlamethrowerClawExosuit }

    local midX     = kBgWidth * 0.5
    local wExoDual = ColumnWidth(kExoDual)
    local wExoClaw = ColumnWidth(kExoClaw)

    local exoUps = kPrototypeUpgradesForTrack[kExoTrack]
    local exoUpsL, exoUpsR = {}, {}
    for i, techId in ipairs(exoUps) do
        if i <= math.ceil(#exoUps / 2) then
            table.insert(exoUpsL, techId)
        else
            table.insert(exoUpsR, techId)
        end
    end
    local wExpExo = ColumnWidth(exoUps, kExpBtnPadX, kExpBtnFontCharW)

    local kSubGap     = 40
    local weaponsW    = wExoDual + kSubGap + wExoClaw
    local expW        = wExpExo + kExpSubGap + wExpExo
    local contentW    = math.max(weaponsW, expW)
    local contentX0   = math.max(kMarginX, (kBgWidth - contentW) * 0.5)
    local contentMidX = contentX0 + contentW * 0.5

    -- ---- TITLE ----
    MakeCenteredText("BRAZIER INDUSTRIES",   kFontSizeTitle,    midX, kTitleY,      kColorHeader)
    MakeCenteredText("EXOSUIT REQUISITION",  kFontSizeSubTitle, midX, kTitleY + 78, kColorHeader)

    -- ---- EXOSUIT weapons (dual + claw) ----
    local colDualX = contentX0
    local colClawX = contentX0 + wExoDual + kSubGap

    MakeCenteredText("EXOSUIT", kFontSizeHeader, contentMidX, kColHeaderY, kColorHeader)

    for i, techId in ipairs(kExoDual) do
        local rect, label = MakeButton(BtnLabelText(techId), colDualX, kBaseRowY + (i - 1) * kRowPitch,
                                       wExoDual, kBtnH, kBtnColorLocked, kColorNormal)
        AddButton(techId, "base", rect, label)
    end
    for i, techId in ipairs(kExoClaw) do
        local rect, label = MakeButton(BtnLabelText(techId), colClawX, kBaseRowY + (i - 1) * kRowPitch,
                                       wExoClaw, kBtnH, kBtnColorLocked, kColorNormal)
        AddButton(techId, "base", rect, label)
    end

    -- ---- DIVIDER ----
    do
        local div = self:CreateAnimatedGraphicItem()
        div:SetIsScaling(false)
        div:AddAsChildTo(self.root)
        div:SetPosition(Vector(contentX0, kDividerY, 0))
        div:SetAnchor(GUIItem.Left, GUIItem.Top)
        div:SetSize(Vector(contentW, kDividerH, 0))
        div:SetColor(Color(0.18, 0.55, 0.78, 0.75))
        div:SetOptionFlag(GUIItem.CorrectScaling)
    end

    -- ---- EXPERIMENTAL TECHNOLOGIES (2 columns) ----
    local expLX = contentX0
    local expRX = contentX0 + wExpExo + kExpSubGap

    MakeCenteredText("EXPERIMENTAL TECHNOLOGIES", kFontSizeSubTitle, contentX0 + expW * 0.5, kExpHeaderY,  kColorHeader)
    MakeCenteredText("EXOSUIT",                   kFontSizeHeader,   contentX0 + expW * 0.5, kExpSubHeadY, kColorHeader)

    local function AddUpgradeColumn(colX, colW, ups)
        for i, techId in ipairs(ups) do
            local rect, label = MakeButton(BtnLabelText(techId), colX, kExpRowY + (i - 1) * kRowPitch,
                                           colW, kBtnH, kBtnColorLocked, kColorDim)
            AddButton(techId, "upgrade", rect, label)
        end
    end
    AddUpgradeColumn(expLX, wExpExo, exoUpsL)
    AddUpgradeColumn(expRX, wExpExo, exoUpsR)

    -- ---- GEAR IMAGE (decorative), right of the experimental block ----
    do
        local expRows   = math.max(#exoUpsL, #exoUpsR)
        local expTop    = kExpRowY
        local expBottom = kExpRowY + (expRows - 1) * kRowPitch + kBtnH
        local imgW      = 140
        local imgH      = imgW * (kBigPicCellH / kBigPicCellW)
        local centreX   = contentX0 + expW + 30 + imgW * 0.5
        local centreY   = (expTop + expBottom) * 0.5

        local img = self:CreateAnimatedGraphicItem()
        img:SetIsScaling(false)
        img:AddAsChildTo(self.root)
        img:SetAnchor(GUIItem.Left, GUIItem.Top)
        img:SetPosition(Vector(centreX - imgW * 0.5, centreY - imgH * 0.5, 0))
        img:SetSize(Vector(imgW, imgH, 0))
        img:SetTexture(kBigPicturesTexture)
        img:SetTexturePixelCoordinates(0, kBigPicIndexExo * kBigPicCellH, kBigPicCellW, (kBigPicIndexExo + 1) * kBigPicCellH)
        img:SetColor(Color(1, 1, 1, 1))
        img:SetOptionFlag(GUIItem.CorrectScaling)
    end

    -- ---- FOOTER ----
    do
        local footerX = (kBgWidth - kFooterBtnW) * 0.5
        local rect, label = MakeButton("FINAL COST: 0", footerX, kFooterY, kFooterBtnW, kFooterBtnH,
                                       kBtnColorFooterDim, kColorDim, kFontSizeFooter)
        table.insert(self.buttons, { TechId = nil, Kind = "footer", Item = rect, Label = label })
    end

    -- ---- HOVER POPUP ----
    do
        self.popup = self:CreateAnimatedGraphicItem()
        self.popup:SetIsScaling(false)
        self.popup:SetAnchor(GUIItem.Left, GUIItem.Top)
        self.popup:SetHotSpot(Vector(0, 0, 0))
        self.popup:SetSize(Vector(kPopupW, kPopupLineH * 5 + kPopupPadY * 2, 0))
        self.popup:SetScale(self.customScaleVector)
        self.popup:SetTexture(kBackgroundTexture)
        self.popup:SetColor(Color(0.45, 0.52, 0.58, 0.98))
        self.popup:SetOptionFlag(GUIItem.CorrectScaling)
        self.popup:SetLayer(kGUILayerMarineBuyMenu + 1)
        self.popup:SetIsVisible(false)

        -- One text item PER LINE: Align_Center centres a single line, but a multi-line "\n"
        -- string only centres as a block, leaving the individual lines left-aligned inside it.
        self.popupLines = {}
        for i = 1, kPopupMaxLines do
            local lineItem = self:CreateAnimatedTextItem()
            lineItem:SetIsScaling(false)
            lineItem:AddAsChildTo(self.popup)
            lineItem:SetAnchor(GUIItem.Middle, GUIItem.Top)
            lineItem:SetTextAlignmentX(GUIItem.Align_Center)
            lineItem:SetTextAlignmentY(GUIItem.Align_Min)
            lineItem:SetPosition(Vector(0, kPopupPadY, 0))
            lineItem:SetColor(Color(0.92, 0.97, 1.0, 1))
            lineItem:SetText("")
            lineItem:SetOptionFlag(GUIItem.CorrectScaling)
            lineItem:SetIsVisible(false)
            GUIMakeFontScale(lineItem, "kAgencyFB", kFontSizePopup)
            self.popupLines[i] = lineItem
        end
    end
end

-- ============================================================
-- State helpers
-- ============================================================
function GUICommanderExoDropMenu:GetCommander()
    local player = Client.GetLocalPlayer()
    if player and player.isa and player:isa("MarineCommander") then
        return player
    end
    return nil
end

function GUICommanderExoDropMenu:GetBaseAllowed(techId)
    return GetCommanderExoDropComboAllowed(self:GetCommander(), techId)
end

function GUICommanderExoDropMenu:GetExperimentalUnlocked()
    return GetCommanderExoDropExperimentalUnlocked(self:GetCommander())
end

-- Running t-res total of the current configuration.
function GUICommanderExoDropMenu:GetTotalCost()
    local upgrades = {}
    for techId in pairs(self.selectedUpgrades) do
        table.insert(upgrades, techId)
    end
    return GetCommanderExoDropTotal(self.selectedBase, upgrades)
end

-- The BUY button is live only when a combo is chosen, still allowed, and the team can pay.
function GUICommanderExoDropMenu:GetPurchasable()
    if not self.selectedBase then return false end
    if not self:GetBaseAllowed(self.selectedBase) then return false end
    return PlayerUI_GetTeamResources() >= self:GetTotalCost()
end

function GUICommanderExoDropMenu:SetIsVisible(visible)
    if self.root then self.root:SetIsVisible(visible) end
    if self.popup and not visible then self.popup:SetIsVisible(false) end
end

function GUICommanderExoDropMenu:GetIsVisible()
    return self.root ~= nil and self.root:GetIsVisible()
end

function GUICommanderExoDropMenu:OnResolutionChanged()
    MarineCommanderExoDrop_Close()
end

-- ============================================================
-- Update
-- ============================================================
local function GetIsMouseOver(self, rectItem)
    local mouseX, mouseY = Client.GetCursorPosScreen()
    local over = GUIItemContainsPoint(rectItem, mouseX, mouseY, true)
    self.mouseOverStates[rectItem] = over
    return over
end

function GUICommanderExoDropMenu:Update(deltaTime)

    if not self.root then return end

    -- Stopped commanding (ejected, disconnected, round ended) while the window was open.
    if not self:GetCommander() then
        MarineCommanderExoDrop_Close()
        return
    end

    -- A research completing (or being lost with the lab) can invalidate the current pick.
    if self.selectedBase and not self:GetBaseAllowed(self.selectedBase) then
        self.selectedBase     = nil
        self.selectedUpgrades = {}
    end
    if not self:GetExperimentalUnlocked() then
        self.selectedUpgrades = {}
    end

    local totalCost     = self:GetTotalCost()
    local teamRes       = PlayerUI_GetTeamResources()
    local purchasable   = self:GetPurchasable()
    local experimental  = self:GetExperimentalUnlocked()
    local hoveredTechId = nil

    for _, btn in ipairs(self.buttons) do

        local rect  = btn.Item
        local label = btn.Label
        local over  = GetIsMouseOver(self, rect)

        if over and btn.TechId then
            hoveredTechId = btn.TechId
        end

        if btn.Kind == "footer" then

            label:SetText(string.format("FINAL COST: %d", totalCost))

            if purchasable then
                rect:SetColor(over and kBtnColorFooterHover or kBtnColorFooterReady)
                label:SetColor(over and kColorSelectedText or kColorNormal)
            elseif self.selectedBase then
                -- A combo is picked but the team cannot pay for it: red and unclickable. The
                -- commander deselects or closes the window; nothing is spent either way.
                rect:SetColor(kBtnColorExpensive)
                label:SetColor(kColorTooExpensive)
            else
                rect:SetColor(kBtnColorFooterDim)
                label:SetColor(kColorDim)
            end

        elseif btn.Kind == "base" then

            local techId = btn.TechId

            if not self:GetBaseAllowed(techId) then
                rect:SetColor(kBtnColorLocked)
                label:SetColor(kColorDim)
            elseif self.selectedBase == techId then
                rect:SetColor(kBtnColorSelected)
                label:SetColor(kColorUpgradeOn)
            elseif teamRes >= GetCommanderExoDropCost(techId) then
                rect:SetColor(over and kBtnColorAffordableHover or kBtnColorAffordable)
                label:SetColor(kColorNormal)
            else
                rect:SetColor(over and kBtnColorExpensiveHover or kBtnColorExpensive)
                label:SetColor(kColorTooExpensive)
            end

        elseif btn.Kind == "upgrade" then

            local techId = btn.TechId
            -- Selectable only once a combo is picked AND Experimental Technologies is
            -- researched - the same rule that locks these buttons for a marine in the field.
            local active = self.selectedBase ~= nil and experimental

            if not active then
                rect:SetColor(kBtnColorLocked)
                label:SetColor(kColorDim)
            elseif self.selectedUpgrades[techId] then
                rect:SetColor(kBtnColorSelected)
                label:SetColor(kColorUpgradeOn)
            elseif teamRes >= totalCost + GetCommanderExoDropCost(techId) then
                rect:SetColor(over and kBtnColorAffordableHover or kBtnColorAffordable)
                label:SetColor(kColorNormal)
            else
                rect:SetColor(over and kBtnColorExpensiveHover or kBtnColorExpensive)
                label:SetColor(kColorTooExpensive)
            end

        end
    end

    self:UpdatePopup(hoveredTechId)
end

function GUICommanderExoDropMenu:UpdatePopup(hoveredTechId)

    if not self.popup then return end

    local desc = hoveredTechId and self.descriptions[hoveredTechId] or nil
    if not desc then
        self.popup:SetIsVisible(false)
        return
    end

    local cs        = self.customScale
    local lineIndex = 0
    local maxW      = 0

    for line in (desc .. "\n"):gmatch("(.-)\n") do
        lineIndex = lineIndex + 1
        local item = self.popupLines[lineIndex]
        if item then
            item:SetText(line)
            item:SetPosition(Vector(0, kPopupPadY + (lineIndex - 1) * kPopupLineH, 0))
            item:SetIsVisible(true)
            maxW = math.max(maxW, item:GetTextWidth(line) * item:GetScale().x)
        end
    end
    for i = lineIndex + 1, kPopupMaxLines do
        if self.popupLines[i] then self.popupLines[i]:SetIsVisible(false) end
    end

    local designH = lineIndex * kPopupLineH + kPopupPadY * 2
    local designW = maxW + kPopupPadX * 2
    self.popup:SetSize(Vector(designW, designH, 0))

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

-- ============================================================
-- SendKeyEvent
-- ============================================================
-- Reached from InputHandler BEFORE the commander's own handler, so returning true here stops
-- a click inside the window from also issuing a world order behind it.
function GUICommanderExoDropMenu:SendKeyEvent(key, down)

    if not self.root or not self:GetIsVisible() then
        return false
    end

    -- Escape / right-click closes the window without spending anything. Both the press AND the
    -- release are swallowed: letting the press through would open the main menu behind us.
    if key == InputKey.Escape or key == InputKey.MouseButton1 then
        if not down then
            MarineCommanderExoDrop_Close()
        end
        return true
    end

    if key ~= InputKey.MouseButton0 and key ~= InputKey.MouseButton1 then
        return false
    end

    if key == InputKey.MouseButton0 and down then

        local mouseX, mouseY = Client.GetCursorPosScreen()

        for _, btn in ipairs(self.buttons) do

            if GUIItemContainsPoint(btn.Item, mouseX, mouseY, true) then

                if btn.Kind == "footer" then
                    if self:GetPurchasable() then
                        self:Purchase()
                    end
                    return true
                end

                if btn.Kind == "base" then
                    local techId = btn.TechId
                    if self:GetBaseAllowed(techId) then
                        if self.selectedBase == techId then
                            self.selectedBase = nil
                        else
                            self.selectedBase = techId
                        end
                        -- Upgrades are scoped to the chosen combo, so swapping or clearing the
                        -- combo clears them too.
                        self.selectedUpgrades = {}
                    end
                    return true
                end

                if btn.Kind == "upgrade" then
                    local techId = btn.TechId
                    if self.selectedBase and self:GetExperimentalUnlocked() then
                        self.selectedUpgrades[techId] = not self.selectedUpgrades[techId] or nil
                    end
                    return true
                end

            end
        end
    end

    -- Swallow every other click while the window is up so nothing leaks to the world below.
    return true
end

-- ============================================================
-- Purchase
-- ============================================================
function GUICommanderExoDropMenu:Purchase()

    if not self:GetPurchasable() then return end

    local upgrades = {}
    for techId in pairs(self.selectedUpgrades) do
        table.insert(upgrades, techId)
    end

    -- Hands off to CommanderExoDrop.lua, which sends the configuration, closes this window and
    -- arms the placement ghost. Nothing is charged until the Exo is actually placed.
    MarineCommanderExoDrop_Confirm(self.selectedBase, GetCommanderExoDropBits(upgrades))
end

-- ============================================================
-- Uninitialize
-- ============================================================
function GUICommanderExoDropMenu:Uninitialize()

    -- GUIAnimatedScript.Uninitialize destroys every item made with the Create* helpers.
    GUIAnimatedScript.Uninitialize(self)

    self.root            = nil
    self.popup           = nil
    self.popupLines      = {}
    self.buttons         = {}
    self.mouseOverStates = {}

    -- Deliberately does NOT call MouseTracker_SetIsVisible(false): the commander's cursor is
    -- owned by the commander HUD and must survive this window closing.
end
