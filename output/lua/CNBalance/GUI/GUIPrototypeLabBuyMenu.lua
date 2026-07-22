-- CNBalance/GUI/GUIPrototypeLabBuyMenu.lua
-- Prototype Lab buy window.
-- Two-stage, cost-accumulating menu: pick a base item (Jetpack / Exo combo / Cannon),
-- then optionally pick upgrades for that track, then click "FINAL COST" to purchase.
--
-- Visual rework (round 3):
--   * Per-column button widths — each column is only as wide as its longest label
--     (plus a small margin), so buttons are thinner where they can be.
--   * Columns distributed "space-evenly" (equal gaps before / between / after).
--   * Exosuit EXPERIMENTAL upgrades split into TWO columns (3 + 3).
--   * Reduced wasted vertical space (shorter panel, footer just below the content).
--   * Hover popup: smaller box, bigger text, sized to its content.
--   * Claw weapon-pair descriptions no longer mention welding (only the Dual Welder
--     and Welder + Claw can weld).
-- Interaction logic (selection / gating / cost / purchase / hit-testing) is UNCHANGED.

Script.Load("lua/GUIAnimatedScript.lua")

class 'GUIPrototypeLabBuyMenu' (GUIAnimatedScript)

GUIPrototypeLabBuyMenu.kMockupSize = Vector(2880, 1620, 0)

local kBackgroundTexture = PrecacheAsset("ui/buymenu_marine/prototypelab_background.dds")

-- "Big picture" gear atlas (same file the old Armory/PrototypeLab buy menu used for its
-- large item portraits). This mod's copy of the atlas has been extended to 4 stacked
-- cells (403x424 each): 0 = Dual Minigun Exosuit, 1 = Dual Railgun Exosuit, 2 = Jetpack,
-- 3 = Cannon (see GUIMarineBuyMenu.lua's kTechIdInfo BigPictureIndex for the same
-- mapping). Cell 0 (a dual-minigun Exo render) is used as the generic/default EXO
-- image next to the exo experimental buttons; cell 2 for Jetpack; cell 3 for Cannon.
local kBigPicturesTexture = PrecacheAsset("ui/buymenu_marine/prototypelab_bigicons.dds")
local kBigPicCellW = 403
local kBigPicCellH = 424
local kBigPicIndexExo     = 0   -- Dual Minigun Exosuit render (default/generic EXO image)
local kBigPicIndexJetpack = 2
local kBigPicIndexCannon  = 3

-- Button fill colours per state
GUIPrototypeLabBuyMenu.kBtnColorNormal     = Color(0.10, 0.16, 0.20, 0.88)
GUIPrototypeLabBuyMenu.kBtnColorHover      = Color(0.16, 0.50, 0.62, 0.97)
GUIPrototypeLabBuyMenu.kBtnColorSelected   = Color(0.01, 0.56, 1.00, 0.92)
GUIPrototypeLabBuyMenu.kBtnColorLocked     = Color(0.07, 0.07, 0.08, 0.82)
-- Unaffordable: RED at LOW opacity; a slightly different (brighter) red on hover.
GUIPrototypeLabBuyMenu.kBtnColorExpensive      = Color(0.50, 0.10, 0.10, 0.42)
GUIPrototypeLabBuyMenu.kBtnColorExpensiveHover = Color(0.72, 0.16, 0.16, 0.50)
GUIPrototypeLabBuyMenu.kBtnColorUpgradeOn  = Color(0.05, 0.42, 0.16, 0.92)
-- Already OWNED (gold), + a brighter gold on hover.
GUIPrototypeLabBuyMenu.kBtnColorOwned      = Color(0.80, 0.62, 0.12, 0.85)
GUIPrototypeLabBuyMenu.kBtnColorOwnedHover = Color(0.93, 0.75, 0.20, 0.90)
GUIPrototypeLabBuyMenu.kColorOwned         = Color(0.14, 0.11, 0.02, 1)   -- dark text on gold
-- Affordable-but-not-yet-selected buttons are BLUE; selected buttons go GREEN
-- (kBtnColorUpgradeOn); unaffordable buttons are RED (kBtnColorExpensive).
-- Affordable: muted MARINE BLUE at moderate opacity; a slightly brighter blue on hover.
GUIPrototypeLabBuyMenu.kBtnColorAffordable      = Color(0.13, 0.40, 0.72, 0.80)
GUIPrototypeLabBuyMenu.kBtnColorAffordableHover = Color(0.22, 0.56, 0.92, 0.88)
GUIPrototypeLabBuyMenu.kBtnColorFooterReady = Color(0.02, 0.45, 0.72, 0.94)
GUIPrototypeLabBuyMenu.kBtnColorFooterHover = Color(0.06, 0.66, 0.98, 0.98)
GUIPrototypeLabBuyMenu.kBtnColorFooterDim   = Color(0.08, 0.08, 0.09, 0.82)

-- Text colours
GUIPrototypeLabBuyMenu.kColorNormal       = Color(1,      1,      1,      1)
GUIPrototypeLabBuyMenu.kColorSelected     = Color(0.55,   0.90,   1,      1)
GUIPrototypeLabBuyMenu.kColorDim          = Color(0.45,   0.45,   0.45,   1)
GUIPrototypeLabBuyMenu.kColorHeader       = Color(0.72,   0.88,   0.95,   1)
GUIPrototypeLabBuyMenu.kColorUpgradeOn    = Color(0.4,    1,      0.55,   1)
GUIPrototypeLabBuyMenu.kColorAffordable   = Color(1,      1,      1,      1)
GUIPrototypeLabBuyMenu.kColorTooExpensive = Color(0.85,   0.30,   0.30,   1)

-- Font sizes (design pixels)
local kFontSizeTitle    = 70
local kFontSizeSubTitle = 50
local kFontSizeHeader   = 36
local kFontSizeButton   = 30
local kFontSizeFooter   = 42
local kFontSizePopup    = 36

-- Layout constants (design pixels on the 2880x1620 reference canvas)
local kBgWidth   = 1600   -- narrower: content is centred, no wasted horizontal space
local kBgHeight  = 1010
local kMarginX   = 95
local kContentW  = kBgWidth - kMarginX * 2

local kTitleY    = 36

local kColHeaderY = 175
local kBaseRowY   = 235   -- ~60px margin below the EXOSUIT header

local kBtnH      = 66
local kRowGapY   = 16
local kRowPitch  = kBtnH + kRowGapY

-- Per-column width estimation (each column is sized to its longest label).
local kBtnFontCharW = 16     -- px per character estimate at AgencyFBBold @ kFontSizeButton; trimmed from 19 (which was over-generous) so buttons are narrower. Raise slightly if any label's text clips at the button edges.
local kBtnPadX      = 9      -- horizontal padding each side of the label (tighter buttons)
local kBtnMinW      = 90

-- The 5 experimental exo buttons had noticeably more spare width than the base
-- buttons (their labels are shorter relative to the padding used). Tighten them
-- with smaller padding + a smaller inter-column gap so the experimental block is
-- more compact and matches the base buttons' look.
local kExpBtnPadX = 4        -- tighter horizontal padding for experimental buttons
local kExpBtnFontCharW = 14  -- narrower per-char estimate for experimental buttons (they are thinner than the base buttons). Raise if a label clips.
local kExpSubGap  = 26       -- tighter gap between the two experimental sub-columns

-- Divider (below the 5 base rows)
local kDividerY   = kBaseRowY + 3 * kRowPitch + 30   -- just below the 3 weapon rows (no empty rows)
local kDividerH   = 3

-- Experimental section
local kExpHeaderY  = kDividerY + kDividerH + 30
local kExpSubHeadY = kExpHeaderY + 48
local kExpRowY     = kExpSubHeadY + 60   -- ~60px margin below the experimental EXOSUIT header
local kExpBtnH     = kBtnH

-- Footer purchase button
local kFooterBtnW  = 440   -- BUY / FINAL COST button: a bit smaller (font size unchanged, kFontSizeFooter)
local kFooterBtnH  = 60
local kFooterY     = kBgHeight - 92

-- Hover description popup (design pixels; drawn in screen space, scaled by customScale)
local kPopupW          = 500   -- fallback only; the popup is sized to its content
local kPopupLineH      = 46
local kPopupPadY       = 22    -- slightly reduced vertical padding
local kPopupPadX       = 30    -- horizontal margin each side of the text (reduced)
local kPopupCursorOffset = 24
local kPopupMaxLines   = 16    -- pool size for the per-line centred description text

-- ============================================================
-- Helpers
-- ============================================================
local function GetDisplayName(techId)
    local raw = LookupTechData(techId, kTechDataDisplayName, "?")
    return Locale.ResolveString(raw)
end

-- Per-button label overrides for the buy window (does not touch global display names).
local kButtonLabelOverride =
{
    [kTechId.DualMinigunExosuit] = "DUAL MINIGUNS",
    [kTechId.DualRailgunExosuit] = "DUAL RAILGUNS",
    [kTechId.Cannon]             = "CANNON",
}


local function BtnLabelText(tid)
    local name = kButtonLabelOverride[tid] or string.upper(GetDisplayName(tid))
    return string.format("%s  %d", name, GetPrototypeCost(tid))
end

-- Width a button needs to fit a label string.
local function LabelWidth(label)
    return math.max(kBtnMinW, #label * kBtnFontCharW + kBtnPadX * 2)
end

-- Width a column needs to fit the longest of its techId labels.
local function ColumnWidth(techIds)
    local w = kBtnMinW
    for _, tid in ipairs(techIds) do
        w = math.max(w, LabelWidth(BtnLabelText(tid)))
    end
    return w
end

-- Same as LabelWidth/ColumnWidth but with a caller-supplied padding AND per-character
-- width (used to make the experimental buttons narrower than the base buttons without
-- touching the base buttons' sizing). charW defaults to kBtnFontCharW.
local function LabelWidthPad(label, padX, charW)
    return math.max(kBtnMinW, #label * (charW or kBtnFontCharW) + padX * 2)
end

local function ColumnWidthPad(techIds, padX, charW)
    local w = kBtnMinW
    for _, tid in ipairs(techIds) do
        w = math.max(w, LabelWidthPad(BtnLabelText(tid), padX, charW))
    end
    return w
end

-- Space-evenly distribution of N items of given widths across [x0, x0+containerW]:
-- equal gaps before, between and after.  Returns the left-edge x of each item.
local function SpaceEvenlyVar(containerW, x0, widths)
    local sum = 0
    for _, w in ipairs(widths) do sum = sum + w end
    local gap = (containerW - sum) / (#widths + 1)
    local xs  = {}
    local x   = x0 + gap
    for i, w in ipairs(widths) do
        xs[i] = x
        x = x + w + gap
    end
    return xs
end

local function CountLines(text)
    return select(2, text:gsub("\n", "")) + 1
end

-- Widest rendered line width (in the popup's design-pixel space) of a multi-line
-- string, measured with the popup's own text item.  textItem:GetTextWidth returns
-- the unscaled font width, so multiply by the item's scale to get design pixels.
local function MaxLineWidth(textItem, text)
    local scale = textItem:GetScale().x
    local maxW  = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local w = textItem:GetTextWidth(line) * scale
        if w > maxW then maxW = w end
    end
    return maxW
end

-- ============================================================
-- Hover descriptions (authored with explicit line breaks so the text is
-- GUARANTEED to fit inside the popup window).  Keyed by techId.
-- NOTE: only the Dual Welder and Welder + Claw can weld; the other claw pairs
-- mention melee only.
-- ============================================================
local function BuildDescriptions()
    local d = {}

    d[kTechId.Jetpack] = "JETPACK\n\nFlight pack with limited\nrecharging fuel. Hold jump\nto fly; fuel refills while\non the ground."
    d[kTechId.Cannon]  = "GAUSS CANNON\n\nSlow, heavy rounds with\na small area blast."

    d[kTechId.DualMinigunExosuit]         = "DUAL MINIGUNS\n\nTwo rapid-fire miniguns\nfor sustained damage."
    d[kTechId.DualRailgunExosuit]         = "DUAL RAILGUNS\n\nTwo charge railguns.\nHold to charge, release\nto fire a powerful shot.\n\nRequires the Gauss (Cannon)\ntech researched\n(Prototype Lab -> Gauss)."
    d[kTechId.DualFlamethrowerExosuit]    = "DUAL FLAMETHROWERS\n\nTwin flame projectors.\n5 seconds of fire before\noverheat; 5 sec cooldown."
    d[kTechId.MinigunClawExosuit]         = "MINIGUN + CLAW\n\nRight: rapid-fire minigun.\nLeft: claw (melee strike)."
    d[kTechId.RailgunClawExosuit]         = "RAILGUN + CLAW\n\nRight: charge railgun.\nLeft: claw (melee strike).\n\nRequires the Gauss (Cannon)\ntech researched\n(Prototype Lab -> Gauss)."
    d[kTechId.FlamethrowerClawExosuit]    = "FLAMETHROWER + CLAW\n\nRight: flame projector\n(5 sec before overheat).\nLeft: claw (melee strike)."


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
function GUIPrototypeLabBuyMenu:Initialize()

    GUIAnimatedScript.Initialize(self)

    self.customScale       = Client.GetScreenHeight() / GUIPrototypeLabBuyMenu.kMockupSize.y
    self.customScaleVector = Vector(1, 1, 1) * self.customScale

    -- Multi-select: at most one base per track, plus that track's upgrades.
    self.selectedBases    = {}    -- track -> baseTechId
    self.selectedUpgrades = {}    -- upgradeTechId -> true (spans all selected tracks)

    self.buttons     = {}
    self.footerItem  = nil
    self.footerLabel = nil

    self.mouseOverStates = {}
    self.descriptions    = BuildDescriptions()
    self.hoveredTechId   = nil

    MarineBuy_OnOpen()
    MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
end

-- ============================================================
-- SetHostStructure — builds the full layout
-- ============================================================
function GUIPrototypeLabBuyMenu:SetHostStructure(structure)

    self.hostStructure = structure
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

    -- ---- helpers ----
    local function MakeCenteredText(text, fontSize, centreX, y, color)
        local item = s:CreateAnimatedTextItem()
        item:SetIsScaling(false)
        item:AddAsChildTo(s.root)
        item:SetPosition(Vector(centreX, y, 0))
        item:SetAnchor(GUIItem.Left, GUIItem.Top)
        item:SetTextAlignmentX(GUIItem.Align_Center)
        item:SetTextAlignmentY(GUIItem.Align_Min)
        item:SetText(text)
        item:SetColor(color or GUIPrototypeLabBuyMenu.kColorNormal)
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
        rect:SetColor(fillColor or GUIPrototypeLabBuyMenu.kBtnColorNormal)
        rect:SetOptionFlag(GUIItem.CorrectScaling)

        local label = s:CreateAnimatedTextItem()
        label:SetIsScaling(false)
        label:AddAsChildTo(rect)
        label:SetPosition(Vector(w * 0.5, h * 0.5, 0))
        label:SetAnchor(GUIItem.Left, GUIItem.Top)
        label:SetTextAlignmentX(GUIItem.Align_Center)
        label:SetTextAlignmentY(GUIItem.Align_Center)
        label:SetText(text)
        label:SetColor(textColor or GUIPrototypeLabBuyMenu.kColorNormal)
        label:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(label, "kAgencyFBBold", fontSize or kFontSizeButton)
        return rect, label
    end

    local function AddButton(techId, track, kind, rect, label)
        table.insert(s.buttons, { TechId = techId, Track = track, Kind = kind, Item = rect, Label = label })
    end

    -- ============================================================
    -- BASE section column data
    -- ============================================================
    local kExoDual = {
        kTechId.DualMinigunExosuit, kTechId.DualRailgunExosuit, kTechId.DualFlamethrowerExosuit,
    }
    local kExoClaw = {
        kTechId.MinigunClawExosuit, kTechId.RailgunClawExosuit, kTechId.FlamethrowerClawExosuit,
    }

    -- The jetpack base column holds two stacked items: Jetpack, then Jumppack
    -- (the old Boost upgrade, now a standalone base item) directly beneath it.
    local kJetBase = { kTechId.Jetpack }

    -- ============================================================
    -- LAYOUT: Exosuit packed on the LEFT; Jetpack + Cannon stacked to its RIGHT.
    -- The whole block is centred so nothing hugs the panel edges.
    -- ============================================================
    local midX = kBgWidth * 0.5

    local wExoDual = ColumnWidth(kExoDual)
    local wExoClaw = ColumnWidth(kExoClaw)
    local wJet     = ColumnWidth(kJetBase)
    local wCan     = ColumnWidth({ kTechId.Cannon })

    local exoUps = kPrototypeUpgradesForTrack["exo"]
    local exoUpsL, exoUpsR = {}, {}
    for i, tid in ipairs(exoUps) do
        if i <= math.ceil(#exoUps / 2) then table.insert(exoUpsL, tid) else table.insert(exoUpsR, tid) end
    end
    local wExpExo = ColumnWidthPad(exoUps, kExpBtnPadX, kExpBtnFontCharW)

    local kSubGap = 40    -- between the exo dual + claw sub-columns
    local kColGap = 240   -- between the exo block and the jetpack/cannon column (wide: pushes the exosuit and jetpack/cannon groups further apart)

    -- Exo zone is wide enough for its weapons AND its 2 experimental columns.
    local exoWeaponsW = wExoDual + kSubGap + wExoClaw
    local exoExpW     = wExpExo + kExpSubGap + wExpExo
    local exoZoneW    = math.max(exoWeaponsW, exoExpW)

    local rightColW = math.max(wJet, wCan)
    local totalW    = exoZoneW + kColGap + rightColW

    local exoZoneX0 = math.max(kMarginX, (kBgWidth - totalW) * 0.5)
    local rightColX = exoZoneX0 + exoZoneW + kColGap
    local exoMidX   = exoZoneX0 + exoZoneW * 0.5

    -- ---- TITLE ----
    MakeCenteredText("BRAZIER INDUSTRIES",   kFontSizeTitle,    midX, kTitleY,      GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("PROTOTYPE LABORATORY", kFontSizeSubTitle, midX, kTitleY + 78, GUIPrototypeLabBuyMenu.kColorHeader)

    -- ---- LEFT: EXOSUIT weapons (dual + claw, packed) ----
    local colExoDualX = exoZoneX0
    local colExoClawX = exoZoneX0 + wExoDual + kSubGap

    MakeCenteredText("EXOSUIT", kFontSizeHeader, exoMidX, kColHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)

    for i, tid in ipairs(kExoDual) do
        local rowY = kBaseRowY + (i - 1) * kRowPitch
        local rect, lbl = MakeButton(BtnLabelText(tid), colExoDualX, rowY, wExoDual, kBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorNormal, GUIPrototypeLabBuyMenu.kColorNormal)
        AddButton(tid, "exo", "base", rect, lbl)
    end
    for i, tid in ipairs(kExoClaw) do
        local rowY = kBaseRowY + (i - 1) * kRowPitch
        local rect, lbl = MakeButton(BtnLabelText(tid), colExoClawX, rowY, wExoClaw, kBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorNormal, GUIPrototypeLabBuyMenu.kColorNormal)
        AddButton(tid, "exo", "base", rect, lbl)
    end

    -- ---- RIGHT: JETPACK (top) + CANNON (lower), stacked using the full height ----
    MakeCenteredText("JETPACK", kFontSizeHeader, rightColX + rightColW * 0.5, kColHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)
    do
        local rect, lbl = MakeButton(BtnLabelText(kTechId.Jetpack), rightColX, kBaseRowY, rightColW, kBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorNormal, GUIPrototypeLabBuyMenu.kColorNormal)
        AddButton(kTechId.Jetpack, "jetpack", "base", rect, lbl)
    end
    local canHeaderY = kExpSubHeadY   -- drop the Cannon down to align with the experimental section
    MakeCenteredText("CANNON", kFontSizeHeader, rightColX + rightColW * 0.5, canHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)
    do
        local rect, lbl = MakeButton(BtnLabelText(kTechId.Cannon), rightColX, canHeaderY + 70, rightColW, kBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorNormal, GUIPrototypeLabBuyMenu.kColorNormal)
        AddButton(kTechId.Cannon, "cannon", "base", rect, lbl)
    end

    -- ---- DIVIDER (spans only the exo zone) ----
    do
        local div = self:CreateAnimatedGraphicItem()
        div:SetIsScaling(false)
        div:AddAsChildTo(self.root)
        div:SetPosition(Vector(exoZoneX0, kDividerY, 0))
        div:SetAnchor(GUIItem.Left, GUIItem.Top)
        div:SetSize(Vector(exoZoneW, kDividerH, 0))
        div:SetColor(Color(0.18, 0.55, 0.78, 0.75))
        div:SetOptionFlag(GUIItem.CorrectScaling)
        self.divider = div
    end

    -- ---- LEFT: EXOSUIT experimental (2 cols) - packed at the LEFT of the exo zone ----
    -- Pack the two experimental columns tightly at the left (no space-evenly spreading),
    -- so they sit further left with the horizontal empty space removed. exoExpW is the
    -- packed block's total width (2 columns + the sub-gap); centre the headers over it.
    local expExoLX = exoZoneX0
    local expExoRX = exoZoneX0 + wExpExo + kExpSubGap
    local expBlockMidX = exoZoneX0 + exoExpW * 0.5

    MakeCenteredText("EXPERIMENTAL TECHNOLOGIES", kFontSizeSubTitle, expBlockMidX, kExpHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("EXOSUIT", kFontSizeHeader, expBlockMidX, kExpSubHeadY, GUIPrototypeLabBuyMenu.kColorHeader)

    local function AddUpgradeColumn(colX, colW, track, ups)
        for i, tid in ipairs(ups) do
            local rowY = kExpRowY + (i - 1) * kRowPitch
            local rect, lbl = MakeButton(BtnLabelText(tid), colX, rowY, colW, kExpBtnH,
                                         GUIPrototypeLabBuyMenu.kBtnColorLocked, GUIPrototypeLabBuyMenu.kColorDim)
            AddButton(tid, track, "upgrade", rect, lbl)
        end
    end
    AddUpgradeColumn(expExoLX, wExpExo, "exo", exoUpsL)
    AddUpgradeColumn(expExoRX, wExpExo, "exo", exoUpsR)

    -- ============================================================
    -- GEAR IMAGES (purely decorative; additive visual layout only)
    -- ============================================================
    local function MakeGearImage(centreX, centreY, w, bigPicIndex)
        local h = w * (kBigPicCellH / kBigPicCellW)
        local img = s:CreateAnimatedGraphicItem()
        img:SetIsScaling(false)
        img:AddAsChildTo(s.root)
        img:SetAnchor(GUIItem.Left, GUIItem.Top)
        img:SetPosition(Vector(centreX - w * 0.5, centreY - h * 0.5, 0))
        img:SetSize(Vector(w, h, 0))
        img:SetTexture(kBigPicturesTexture)
        local y1 = bigPicIndex * kBigPicCellH
        img:SetTexturePixelCoordinates(0, y1, kBigPicCellW, y1 + kBigPicCellH)
        img:SetColor(Color(1, 1, 1, 1))
        img:SetOptionFlag(GUIItem.CorrectScaling)
        return img
    end

    -- EXO default image: sits just to the RIGHT of the (left-packed) experimental block,
    -- so it stays close to the Experimental Technologies section rather than floating out
    -- at the exo zone's right edge. Vertically centred on the exo experimental rows.
    do
        local expRows   = math.max(#exoUpsL, #exoUpsR)
        local expTop    = kExpRowY
        local expBottom = kExpRowY + (expRows - 1) * kRowPitch + kExpBtnH
        local exoImgW    = 140
        local imgCentreX = exoZoneX0 + exoExpW + 30 + exoImgW * 0.5
        self.exoGearImage = MakeGearImage(imgCentreX, (expTop + expBottom) * 0.5, exoImgW, kBigPicIndexExo)
    end

    -- JETPACK image: right column, between the Jetpack button and the CANNON header.
    do
        local slotTop    = kBaseRowY + kBtnH
        local slotBottom = canHeaderY
        self.jetpackGearImage = MakeGearImage(rightColX + rightColW * 0.5, (slotTop + slotBottom) * 0.5, 140, kBigPicIndexJetpack)
    end

    -- CANNON image: right column, below the Cannon button down to the footer.
    do
        local slotTop    = canHeaderY + 70 + kBtnH
        local slotBottom = kFooterY - 16
        self.cannonGearImage = MakeGearImage(rightColX + rightColW * 0.5, (slotTop + slotBottom) * 0.5, 140, kBigPicIndexCannon)
    end

    -- ============================================================
    -- FOOTER
    -- ============================================================
    do
        local footerX = (kBgWidth - kFooterBtnW) * 0.5
        local rect, lbl = MakeButton("FINAL COST: 0", footerX, kFooterY, kFooterBtnW, kFooterBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorFooterDim, GUIPrototypeLabBuyMenu.kColorDim,
                                     kFontSizeFooter)
        self.footerItem  = rect
        self.footerLabel = lbl
        table.insert(self.buttons, { TechId = nil, Track = nil, Kind = "footer", Item = rect, Label = lbl })
    end

    -- ============================================================
    -- HOVER POPUP (screen space, sized to its content)
    -- ============================================================
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

        -- One text item PER LINE. NS2 centres a SINGLE line horizontally with
        -- Align_Center, but a multi-line "\n" string only centres as a BLOCK (the
        -- individual lines stay left-aligned within it). Rendering each line as its
        -- own Align_Center item gives true per-line horizontal centring.
        self.popupLines = {}
        for i = 1, kPopupMaxLines do
            local lineItem = self:CreateAnimatedTextItem()
            lineItem:SetIsScaling(false)
            lineItem:AddAsChildTo(self.popup)
            -- Middle/Top anchor: x=0 is the popup's horizontal centre; Align_Center
            -- then centres THIS line about that centre.
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
-- State helpers (UNCHANGED interaction logic)
-- ============================================================
function GUIPrototypeLabBuyMenu:GetTrackUnlocked(track)
    local specId = kPrototypeSpecialityForTrack[track]
    if not specId then return false end
    return GetHasTech(Client.GetLocalPlayer(), specId)
end

-- Whether a base's EXTRA research prerequisite (if any) is met. Bases without an entry in
-- kPrototypeBaseRequiresTech (shared, PrototypeTechData.lua) are always available; the Railgun
-- combos require the Gauss (Cannon) tech. Server enforces the same via Marine:AttemptToBuy.
function GUIPrototypeLabBuyMenu:GetBaseTechAvailable(techId)
    local reqTech = kPrototypeBaseRequiresTech and kPrototypeBaseRequiresTech[techId]
    if not reqTech then return true end
    return GetHasTech(Client.GetLocalPlayer(), reqTech) == true
end

-- The experimental UPGRADES for a track require the corresponding Experimental
-- Technologies research (in addition to the base speciality).
function GUIPrototypeLabBuyMenu:GetExperimentalUnlocked(track)
    local expId = kPrototypeExperimentalForTrack and kPrototypeExperimentalForTrack[track]
    if not expId then return false end
    -- Researched (any round): the team has Exosuit - Experimental Technologies.
    if GetHasTech(Client.GetLocalPlayer(), expId) then return true end
    -- Pre-game: upgrades are free for testing. On the CLIENT the game state must be
    -- read from the GameInfo entity (GetGamerules() has no reliable GetGameState here).
    local gameInfo = GetGameInfoEntity()
    if gameInfo and gameInfo.GetState and gameInfo:GetState() < kGameState.Started then
        return true
    end
    return false
end

function GUIPrototypeLabBuyMenu:GetTotalCost()
    local total = 0
    for _, baseTechId in pairs(self.selectedBases) do
        total = total + GetPrototypeCost(baseTechId)
    end
    for techId in pairs(self.selectedUpgrades) do
        total = total + GetPrototypeCost(techId)
    end
    return total
end

function GUIPrototypeLabBuyMenu:GetFinalPurchasable()
    -- Re-checked every Update() call already (see GetAlreadyOwnsBase's own
    -- callers), but this function itself never consulted it - so picking up
    -- an actual Cannon off the ground while the menu was still open (with
    -- Cannon selected) left the BUY button showing green/purchasable forever,
    -- even though the server-side AttemptToBuy guard would silently reject
    -- the click. Bug: the button lied about purchasability, not that the
    -- purchase itself was unsafe.
    local anySelected = false
    for track, baseTechId in pairs(self.selectedBases) do
        anySelected = true
        if self:GetAlreadyOwnsBase(baseTechId) then return false end
        if not self:GetTrackUnlocked(track) then return false end
        if not self:GetBaseTechAvailable(baseTechId) then return false end
    end
    if not anySelected then return false end
    return PlayerUI_GetPersonalResources() >= self:GetTotalCost()
end

function GUIPrototypeLabBuyMenu:GetAlreadyOwnsBase(techId)
    local player = Client.GetLocalPlayer()
    if not player then return false end
    if techId == kTechId.Jetpack then
        return player:isa("JetpackMarine")
    end
    if techId == kTechId.Cannon then
        local hasCannon = false
        if player and player.GetHUDOrderedWeaponList then
            for _, w in ipairs(player:GetHUDOrderedWeaponList()) do
                if w.GetTechId and w:GetTechId() == kTechId.Cannon then hasCannon = true break end
            end
        end
        return hasCannon
    end
    if kPrototypeExoCombos[techId] then
        return player:isa("Exo")
    end
    return false
end

-- Whether the player already OWNS this experimental-technology upgrade (so its button
-- should show gold). Only true if the player currently owns the carrier that carries the
-- upgrade bit (e.g. is piloting an Exo that has this exo upgrade, or is a JetpackMarine
-- that has a jetpack upgrade). A plain Marine at the buy window owns none, which is correct.
function GUIPrototypeLabBuyMenu:GetAlreadyOwnsUpgrade(techId)
    local player = Client.GetLocalPlayer()
    if not player or not player.GetHasPrototypeUpgrade then return false end
    return player:GetHasPrototypeUpgrade(techId) == true
end

-- ============================================================
-- SetIsVisible / GetIsVisible
-- ============================================================
function GUIPrototypeLabBuyMenu:SetIsVisible(visible)
    if self.root then self.root:SetIsVisible(visible) end
    if self.popup and not visible then self.popup:SetIsVisible(false) end
end

function GUIPrototypeLabBuyMenu:GetIsVisible()
    if self.root then return self.root:GetIsVisible() end
    return false
end

function GUIPrototypeLabBuyMenu:OnClose()
    if not self.closingMenu then MarineBuy_OnClose() end
end

function GUIPrototypeLabBuyMenu:OnResolutionChanged(oldX, oldY, newX, newY)
    self:Uninitialize()
    self:Initialize()
    MarineBuy_OnClose()
end

-- ============================================================
-- Update
-- ============================================================
local function GetIsMouseOver(self, rectItem)
    local mouseX, mouseY = Client.GetCursorPosScreen()
    local over = GUIItemContainsPoint(rectItem, mouseX, mouseY, true)
    if over and not self.mouseOverStates[rectItem] then
        MarineBuy_OnMouseOver()
    end
    self.mouseOverStates[rectItem] = over
    return over
end

function GUIPrototypeLabBuyMenu:Update(deltaTime)

    if not self.root then return end

    -- If the player picked up the actual item (e.g. a Cannon off the ground)
    -- while it was still selected in this menu, drop the now-invalid
    -- selection (and that track's upgrades) rather than leaving the UI
    -- sitting on a dead choice.
    for track, baseTechId in pairs(self.selectedBases) do
        if self:GetAlreadyOwnsBase(baseTechId) then
            self.selectedBases[track] = nil
            for _, u in ipairs(kPrototypeUpgradesForTrack[track] or {}) do
                self.selectedUpgrades[u] = nil
            end
        end
    end

    local totalCost     = self:GetTotalCost()
    local pres          = PlayerUI_GetPersonalResources()
    local canAfford     = pres >= totalCost
    local purchasable   = self:GetFinalPurchasable()
    local anyBaseSelected = next(self.selectedBases) ~= nil

    local hoveredTechId = nil

    for _, btn in ipairs(self.buttons) do
        local rect  = btn.Item
        local label = btn.Label
        local over  = GetIsMouseOver(self, rect)

        if over and btn.TechId then hoveredTechId = btn.TechId end

        if btn.Kind == "footer" then
            label:SetText(string.format("FINAL COST: %d", totalCost))
            if purchasable then
                if over then
                    rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorFooterHover)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorSelected)
                else
                    rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorFooterReady)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorAffordable)
                end
            elseif anyBaseSelected then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorExpensive)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorTooExpensive)
            else
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorFooterDim)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorDim)
            end

        elseif btn.Kind == "base" then
            local track      = btn.Track
            local tid        = btn.TechId
            -- "unlocked" folds in both the speciality tech AND any extra base prerequisite
            -- (Gauss for the Railgun combos), so a gated-but-unresearched base shows LOCKED.
            local unlocked   = self:GetTrackUnlocked(track) and self:GetBaseTechAvailable(tid)
            local owned      = self:GetAlreadyOwnsBase(tid)
            local isSelected = (self.selectedBases[track] == tid)

            if owned then
                -- Already owned -> GOLD (brighter gold on hover).
                rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorOwnedHover or GUIPrototypeLabBuyMenu.kBtnColorOwned)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorOwned)
            elseif not unlocked then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorLocked)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorDim)
            elseif isSelected then
                -- Clicked/selected -> GREEN.
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorUpgradeOn)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorUpgradeOn)
            else
                local cost = GetPrototypeCost(tid)
                if pres >= cost then
                    -- Affordable, not selected -> BLUE.
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorAffordableHover or GUIPrototypeLabBuyMenu.kBtnColorAffordable)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorAffordable)
                else
                    -- Unaffordable -> RED (a different red on hover).
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorExpensiveHover or GUIPrototypeLabBuyMenu.kBtnColorExpensive)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorTooExpensive)
                end
            end

        elseif btn.Kind == "upgrade" then
            local track        = btn.Track
            local tid          = btn.TechId
            -- An upgrade is selectable only when its track's base is selected AND
            -- the track's Experimental Technologies research has been completed.
            local trackActive  = (self.selectedBases[track] ~= nil) and self:GetExperimentalUnlocked(track)
            local isInSelected = self.selectedUpgrades[tid] == true
            local ownedUpg     = self:GetAlreadyOwnsUpgrade(tid)

            if ownedUpg then
                -- Already purchased -> GOLD (brighter gold on hover).
                rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorOwnedHover or GUIPrototypeLabBuyMenu.kBtnColorOwned)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorOwned)
            elseif not trackActive then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorLocked)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorDim)
            elseif isInSelected then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorUpgradeOn)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorUpgradeOn)
            else
                if canAfford then
                    -- Affordable, not selected -> BLUE.
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorAffordableHover or GUIPrototypeLabBuyMenu.kBtnColorAffordable)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorAffordable)
                else
                    -- Unaffordable -> RED (a different red on hover).
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorExpensiveHover or GUIPrototypeLabBuyMenu.kBtnColorExpensive)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorTooExpensive)
                end
            end
        end
    end

    -- Hover description popup (sized to its content).
    if self.popup then
        self.hoveredTechId = hoveredTechId
        local desc = hoveredTechId and self.descriptions[hoveredTechId] or nil
        if desc then
            local cs = self.customScale

            -- Lay each description line out as its own horizontally-centred item.
            local lineIndex = 0
            local maxW      = 0
            for line in (desc .. "\n"):gmatch("(.-)\n") do
                lineIndex = lineIndex + 1
                local item = self.popupLines[lineIndex]
                if item then
                    item:SetText(line)
                    item:SetPosition(Vector(0, kPopupPadY + (lineIndex - 1) * kPopupLineH, 0))
                    item:SetIsVisible(true)
                    local w = item:GetTextWidth(line) * item:GetScale().x
                    if w > maxW then maxW = w end
                end
            end
            -- Hide any leftover line items from a previous (longer) description.
            for i = lineIndex + 1, kPopupMaxLines do
                if self.popupLines[i] then self.popupLines[i]:SetIsVisible(false) end
            end

            local ph_d = lineIndex * kPopupLineH + kPopupPadY * 2
            local pw_d = maxW + kPopupPadX * 2
            self.popup:SetSize(Vector(pw_d, ph_d, 0))

            local pw, ph = pw_d * cs, ph_d * cs
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
        else
            self.popup:SetIsVisible(false)
        end
    end
end

-- ============================================================
-- SendKeyEvent (UNCHANGED interaction logic)
-- ============================================================
function GUIPrototypeLabBuyMenu:SendKeyEvent(key, down)

    if key == InputKey.Escape and not down then
        MarineBuy_OnClose()
        MarineBuy_Close()
        return true
    end

    local inputHandled = (key == InputKey.MouseButton0 or key == InputKey.MouseButton1)

    if key == InputKey.MouseButton0 and down then
        local mouseX, mouseY = Client.GetCursorPosScreen()

        for _, btn in ipairs(self.buttons) do
            local rect = btn.Item
            local over = GUIItemContainsPoint(rect, mouseX, mouseY, true)
            if not over then goto continue end

            if btn.Kind == "footer" then
                if self:GetFinalPurchasable() then
                    self:PurchaseBundle()
                    MarineBuy_OnClose()
                    MarineBuy_Close()
                end
                return true
            end

            if btn.Kind == "base" then
                local track = btn.Track
                local tid   = btn.TechId
                local owned = self:GetAlreadyOwnsBase(tid)
                if self:GetTrackUnlocked(track) and self:GetBaseTechAvailable(tid) and not owned then
                    local currentBase = self.selectedBases[track]
                    if currentBase == tid then
                        -- Clicking the currently-selected base of this track deselects it.
                        self.selectedBases[track] = nil
                        for _, u in ipairs(kPrototypeUpgradesForTrack[track] or {}) do
                            self.selectedUpgrades[u] = nil
                        end
                    else
                        -- Selecting a base in this track (fresh, or swapping) clears
                        -- that track's upgrades (upgrades are track-scoped).
                        self.selectedBases[track] = tid
                        for _, u in ipairs(kPrototypeUpgradesForTrack[track] or {}) do
                            self.selectedUpgrades[u] = nil
                        end
                    end
                    MarineBuy_OnMouseOver()
                end
                return true
            end

            if btn.Kind == "upgrade" then
                local track = btn.Track
                local tid   = btn.TechId
                if self.selectedBases[track] ~= nil
                   and self:GetExperimentalUnlocked(track) then
                    if self.selectedUpgrades[tid] then
                        self.selectedUpgrades[tid] = nil
                    else
                        self.selectedUpgrades[tid] = true
                    end
                    MarineBuy_OnMouseOver()
                end
                return true
            end

            ::continue::
        end
    end

    return inputHandled
end

-- ============================================================
-- PurchaseBundle
-- ============================================================
function GUIPrototypeLabBuyMenu:PurchaseBundle()
    if not self:GetFinalPurchasable() then return end

    -- Exo's Replace() destroys the marine entity, so Exo must be bought last:
    -- Cannon (GiveItem, marine survives) -> Jetpack (Replace->JetpackMarine,
    -- carries the cannon) -> Exo (Replace->Exo, carries everything else).
    local kTrackOrder = { "cannon", "jetpack", "exo" }

    for _, track in ipairs(kTrackOrder) do
        local baseTechId = self.selectedBases[track]
        if baseTechId and not self:GetAlreadyOwnsBase(baseTechId) then
            local list = { baseTechId }
            for techId in pairs(self.selectedUpgrades) do
                if kPrototypeTrackForTechId[techId] == track then
                    table.insert(list, techId)
                end
            end
            Client.SendNetworkMessage("Buy", BuildBuyMessage(list), true)
        end
    end

    MarineBuy_OnClose()
    MarineBuy_Close()
end

-- ============================================================
-- Uninitialize
-- ============================================================
function GUIPrototypeLabBuyMenu:Uninitialize()

    -- GUIAnimatedScript.Uninitialize destroys every item created via the
    -- Create* helpers (root, popup, buttons, etc.); just clear references after.
    GUIAnimatedScript.Uninitialize(self)

    self.root            = nil
    self.popup           = nil
    self.popupLines      = {}
    self.buttons         = {}
    self.footerItem      = nil
    self.footerLabel     = nil
    self.divider         = nil
    self.exoGearImage     = nil
    self.jetpackGearImage = nil
    self.cannonGearImage  = nil
    self.mouseOverStates = {}
    self.hoveredTechId   = nil

    MouseTracker_SetIsVisible(false)
end
