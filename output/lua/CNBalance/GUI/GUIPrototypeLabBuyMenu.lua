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

-- Button fill colours per state
GUIPrototypeLabBuyMenu.kBtnColorNormal     = Color(0.10, 0.16, 0.20, 0.88)
GUIPrototypeLabBuyMenu.kBtnColorHover      = Color(0.16, 0.50, 0.62, 0.97)
GUIPrototypeLabBuyMenu.kBtnColorSelected   = Color(0.01, 0.56, 1.00, 0.92)
GUIPrototypeLabBuyMenu.kBtnColorLocked     = Color(0.07, 0.07, 0.08, 0.82)
GUIPrototypeLabBuyMenu.kBtnColorExpensive  = Color(0.30, 0.05, 0.05, 0.88)
GUIPrototypeLabBuyMenu.kBtnColorUpgradeOn  = Color(0.05, 0.42, 0.16, 0.92)
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
local kBgWidth   = 2300   -- wide enough to fit upgrade button labels without text collision
local kBgHeight  = 1330
local kMarginX   = 95
local kContentW  = kBgWidth - kMarginX * 2

local kTitleY    = 36

local kColHeaderY = 200
local kBaseRowY   = 270

local kBtnH      = 66
local kRowGapY   = 16
local kRowPitch  = kBtnH + kRowGapY

-- Per-column width estimation (each column is sized to its longest label).
local kBtnFontCharW = 20     -- approx px per character at the button font (AgencyFBBold at kFontSizeButton)
local kBtnPadX      = 26     -- horizontal padding each side of the label
local kBtnMinW      = 150

-- Divider (below the 5 base rows)
local kDividerY   = kBaseRowY + 5 * kRowPitch + 24
local kDividerH   = 3

-- Experimental section
local kExpHeaderY  = kDividerY + kDividerH + 30
local kExpSubHeadY = kExpHeaderY + 48
local kExpRowY     = kExpSubHeadY + 54
local kExpBtnH     = kBtnH

-- Footer purchase button
local kFooterBtnW  = 540
local kFooterBtnH  = 74
local kFooterY     = kBgHeight - 110

-- Hover description popup (design pixels; drawn in screen space, scaled by customScale)
local kPopupW          = 500   -- fallback only; the popup is sized to its content
local kPopupLineH      = 46
local kPopupPadY       = 22    -- slightly reduced vertical padding
local kPopupPadX       = 30    -- horizontal margin each side of the text (reduced)
local kPopupCursorOffset = 24

-- ============================================================
-- Helpers
-- ============================================================
local function GetDisplayName(techId)
    local raw = LookupTechData(techId, kTechDataDisplayName, "?")
    return Locale.ResolveString(raw)
end

local function BtnLabelText(tid)
    return string.format("%s  %d", string.upper(GetDisplayName(tid)), GetPrototypeCost(tid))
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

    d[kTechId.Jetpack] = "JETPACK\n\nFlight pack with\nlimited recharging fuel."
    d[kTechId.Cannon]  = "GAUSS CANNON\n\nSlow, heavy rounds with\na small area blast."

    d[kTechId.DualMinigunExosuit]         = "DUAL MINIGUNS\n\nTwo rapid-fire miniguns\nfor sustained damage."
    d[kTechId.DualRailgunExosuit]         = "DUAL RAILGUNS\n\nTwo charge railguns.\nHold to charge, release\nto fire a powerful shot."
    d[kTechId.DualFlamethrowerExosuit]    = "DUAL FLAMETHROWERS\n\nTwin flame projectors.\n5 seconds of fire before\noverheat; 5 sec cooldown."
    d[kTechId.DualGrenadeLauncherExosuit] = "DUAL GRENADE\nLAUNCHERS\n\nTwo grenade arms. Each\nfires automatically at\nfull charge."
    d[kTechId.DualWelderExosuit]          = "DUAL WELDERS\n\nTwo welder arms. Repairs\nallies and damages aliens\n(1.5x welder damage each)."
    d[kTechId.MinigunClawExosuit]         = "MINIGUN + CLAW\n\nRight: rapid-fire minigun.\nLeft: claw (melee strike)."
    d[kTechId.RailgunClawExosuit]         = "RAILGUN + CLAW\n\nRight: charge railgun.\nLeft: claw (melee strike)."
    d[kTechId.FlamethrowerClawExosuit]    = "FLAMETHROWER + CLAW\n\nRight: flame projector\n(5 sec before overheat).\nLeft: claw (melee strike)."
    d[kTechId.GrenadeLauncherClawExosuit] = "GRENADE LAUNCHER\n+ CLAW\n\nRight: grenade arm\n(fires at full charge).\nLeft: claw (melee strike)."
    d[kTechId.WelderClawExosuit]          = "WELDER + CLAW\n\nRight: welder arm (repairs\nallies, damages aliens).\nLeft: claw (melee strike)."

    d[kTechId.PrototypeBoost]            = "BOOST\n\nJump, then jump AGAIN in\nmid-air to burst forward\n(straight up if standing\nstill). 0.75s cooldown,\ncosts fuel per boost."
    d[kTechId.PrototypeJetpackExtraFuel] = "EXTRA FUEL\n\n+33% jetpack fuel\ncapacity.\n(6 Boost charges instead of 5)"
    d[kTechId.PrototypeJetpackArmour]    = "ARMOUR PLATING\n\n+20 armour points\nto the jetpack marine."

    d[kTechId.PrototypeExoArmour]         = "ARMOUR PLATING\n\n+100 armour points\nto the exosuit."
    d[kTechId.PrototypeExoExtraFuel]      = "EXTRA FUEL\n\nExo thruster fuel\nlasts 30% longer."
    d[kTechId.PrototypeLifeformScanner]   = "LIFEFORM SCANNER\n\nActivate to scan nearby\naliens. HUD panel shows\ncounts per lifeform type."
    d[kTechId.PrototypeEmergencyEjection] = "EMERGENCY EJECTION\n\nSurvive a lethal hit by\nautomatically ejecting.\nThe exosuit is lost."
    d[kTechId.PrototypeSelfDestruct]      = "SELF-DESTRUCT\n\nOn death: 200 damage to\nall aliens within 5m."
    d[kTechId.PrototypeResupply]          = "RESUPPLY\n\nTeammates press USE on\nyou to receive ammo.\n15 second cooldown.\n10 charges per exosuit\n(persists if you eject)."

    d[kTechId.PrototypeExtendedMagazine]   = "EXTENDED MAGAZINE\n\nClip 6 -> 9 and +50%\nreserve ammo."
    d[kTechId.PrototypeChargeShot]         = "CHARGE SHOT\n\nHold fire to charge up.\nFull charge: +35% damage."
    d[kTechId.PrototypeTungstenPenetrator] = "TUNGSTEN PENETRATOR\n\nShots pierce to hit a\n2nd target for full damage."
    d[kTechId.PrototypeShotgun]            = "SHOTGUN\n\nFires 6 pellets spread.\nEach pellet = 1/6 damage."

    return d
end

-- ============================================================
-- Initialize
-- ============================================================
function GUIPrototypeLabBuyMenu:Initialize()

    GUIAnimatedScript.Initialize(self)

    self.customScale       = Client.GetScreenHeight() / GUIPrototypeLabBuyMenu.kMockupSize.y
    self.customScaleVector = Vector(1, 1, 1) * self.customScale

    self.selectedBaseTechId = nil
    self.selectedUpgrades   = {}

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
        kTechId.DualGrenadeLauncherExosuit, kTechId.DualWelderExosuit,
    }
    local kExoClaw = {
        kTechId.MinigunClawExosuit, kTechId.RailgunClawExosuit, kTechId.FlamethrowerClawExosuit,
        kTechId.GrenadeLauncherClawExosuit, kTechId.WelderClawExosuit,
    }

    local wJet     = ColumnWidth({ kTechId.Jetpack })
    local wExoDual = ColumnWidth(kExoDual)
    local wExoClaw = ColumnWidth(kExoClaw)
    local wCan     = ColumnWidth({ kTechId.Cannon })

    local baseXs = SpaceEvenlyVar(kContentW, kMarginX, { wJet, wExoDual, wExoClaw, wCan })
    local colJetX, colExoDualX, colExoClawX, colCanX = baseXs[1], baseXs[2], baseXs[3], baseXs[4]

    -- ============================================================
    -- TITLE
    -- ============================================================
    local midX = kBgWidth * 0.5
    MakeCenteredText("BRAZIER INDUSTRIES",   kFontSizeTitle,    midX, kTitleY,      GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("PROTOTYPE LABORATORY", kFontSizeSubTitle, midX, kTitleY + 78, GUIPrototypeLabBuyMenu.kColorHeader)

    -- ============================================================
    -- BASE headers + buttons
    -- ============================================================
    MakeCenteredText("JETPACK", kFontSizeHeader, colJetX + wJet * 0.5, kColHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("EXOSUIT", kFontSizeHeader, (colExoDualX + colExoClawX + wExoClaw) * 0.5, kColHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("CANNON",  kFontSizeHeader, colCanX + wCan * 0.5, kColHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)

    do
        local tid = kTechId.Jetpack
        local rect, lbl = MakeButton(BtnLabelText(tid), colJetX, kBaseRowY, wJet, kBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorNormal, GUIPrototypeLabBuyMenu.kColorNormal)
        AddButton(tid, "jetpack", "base", rect, lbl)
    end
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
    do
        local tid = kTechId.Cannon
        local rect, lbl = MakeButton(BtnLabelText(tid), colCanX, kBaseRowY, wCan, kBtnH,
                                     GUIPrototypeLabBuyMenu.kBtnColorNormal, GUIPrototypeLabBuyMenu.kColorNormal)
        AddButton(tid, "cannon", "base", rect, lbl)
    end

    -- ============================================================
    -- DIVIDER
    -- ============================================================
    do
        local div = self:CreateAnimatedGraphicItem()
        div:SetIsScaling(false)
        div:AddAsChildTo(self.root)
        div:SetPosition(Vector(kMarginX, kDividerY, 0))
        div:SetAnchor(GUIItem.Left, GUIItem.Top)
        div:SetSize(Vector(kContentW, kDividerH, 0))
        div:SetColor(Color(0.18, 0.55, 0.78, 0.75))
        div:SetOptionFlag(GUIItem.CorrectScaling)
        self.divider = div
    end

    -- ============================================================
    -- EXPERIMENTAL section — Jetpack | Exo (2 cols) | Cannon
    -- ============================================================
    local jetUps  = kPrototypeUpgradesForTrack["jetpack"]
    local exoUps  = kPrototypeUpgradesForTrack["exo"]
    local canUps  = kPrototypeUpgradesForTrack["cannon"]

    -- Split the 6 exo upgrades into two columns of 3.
    local exoUpsL, exoUpsR = {}, {}
    for i, tid in ipairs(exoUps) do
        if i <= math.ceil(#exoUps / 2) then table.insert(exoUpsL, tid) else table.insert(exoUpsR, tid) end
    end

    local wExpJet = ColumnWidth(jetUps)
    local wExpExo = ColumnWidth(exoUps)   -- both exo sub-columns share this width
    local wExpCan = ColumnWidth(canUps)

    local expXs = SpaceEvenlyVar(kContentW, kMarginX, { wExpJet, wExpExo, wExpExo, wExpCan })
    local expJetX, expExoLX, expExoRX, expCanX = expXs[1], expXs[2], expXs[3], expXs[4]

    MakeCenteredText("EXPERIMENTAL TECHNOLOGIES", kFontSizeSubTitle, midX, kExpHeaderY, GUIPrototypeLabBuyMenu.kColorHeader)

    MakeCenteredText("JETPACK", kFontSizeHeader, expJetX + wExpJet * 0.5, kExpSubHeadY, GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("EXOSUIT", kFontSizeHeader, midX, kExpSubHeadY, GUIPrototypeLabBuyMenu.kColorHeader)
    MakeCenteredText("CANNON",  kFontSizeHeader, expCanX + wExpCan * 0.5, kExpSubHeadY, GUIPrototypeLabBuyMenu.kColorHeader)

    local function AddUpgradeColumn(colX, colW, track, ups)
        for i, tid in ipairs(ups) do
            local rowY = kExpRowY + (i - 1) * kRowPitch
            local rect, lbl = MakeButton(BtnLabelText(tid), colX, rowY, colW, kExpBtnH,
                                         GUIPrototypeLabBuyMenu.kBtnColorLocked, GUIPrototypeLabBuyMenu.kColorDim)
            AddButton(tid, track, "upgrade", rect, lbl)
        end
    end
    AddUpgradeColumn(expJetX,  wExpJet, "jetpack", jetUps)
    AddUpgradeColumn(expExoLX, wExpExo, "exo",     exoUpsL)
    AddUpgradeColumn(expExoRX, wExpExo, "exo",     exoUpsR)
    AddUpgradeColumn(expCanX,  wExpCan, "cannon",  canUps)

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

        self.popupText = self:CreateAnimatedTextItem()
        self.popupText:SetIsScaling(false)
        self.popupText:AddAsChildTo(self.popup)
        -- Middle/Top anchor: x=0 means the popup's horizontal centre, so
        -- Align_Center produces true centering without needing pw_d*0.5 updates.
        self.popupText:SetAnchor(GUIItem.Middle, GUIItem.Top)
        self.popupText:SetTextAlignmentX(GUIItem.Align_Center)
        self.popupText:SetTextAlignmentY(GUIItem.Align_Min)
        self.popupText:SetPosition(Vector(0, kPopupPadY, 0))
        self.popupText:SetColor(Color(0.92, 0.97, 1.0, 1))
        self.popupText:SetText("")
        self.popupText:SetOptionFlag(GUIItem.CorrectScaling)
        GUIMakeFontScale(self.popupText, "kAgencyFB", kFontSizePopup)
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

-- The experimental UPGRADES for a track require the corresponding Experimental
-- Technologies research (in addition to the base speciality).
function GUIPrototypeLabBuyMenu:GetExperimentalUnlocked(track)
    local expId = kPrototypeExperimentalForTrack and kPrototypeExperimentalForTrack[track]
    if not expId then return false end
    if GetHasTech(Client.GetLocalPlayer(), expId) then return true end
    -- During the pre-game, upgrades are freely available for testing.
    local gr = GetGamerules and GetGamerules()
    if gr and gr.GetGameState and gr:GetGameState() < kGameState.Started then
        return true
    end
    return false
end

function GUIPrototypeLabBuyMenu:GetTotalCost()
    local total = self.selectedBaseTechId and GetPrototypeCost(self.selectedBaseTechId) or 0
    for techId in pairs(self.selectedUpgrades) do
        total = total + GetPrototypeCost(techId)
    end
    return total
end

function GUIPrototypeLabBuyMenu:GetFinalPurchasable()
    if not self.selectedBaseTechId then return false end
    -- Re-checked every Update() call already (see GetAlreadyOwnsBase's own
    -- callers), but this function itself never consulted it - so picking up
    -- an actual Cannon off the ground while the menu was still open (with
    -- Cannon selected) left the BUY button showing green/purchasable forever,
    -- even though the server-side AttemptToBuy guard would silently reject
    -- the click. Bug: the button lied about purchasability, not that the
    -- purchase itself was unsafe.
    if self:GetAlreadyOwnsBase(self.selectedBaseTechId) then return false end
    local track = kPrototypeTrackForTechId[self.selectedBaseTechId]
    return self:GetTrackUnlocked(track) and PlayerUI_GetPersonalResources() >= self:GetTotalCost()
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
    -- selection rather than leaving the UI sitting on a dead choice.
    if self.selectedBaseTechId and self:GetAlreadyOwnsBase(self.selectedBaseTechId) then
        self.selectedBaseTechId = nil
        self.selectedUpgrades = {}
    end

    local selectedBase  = self.selectedBaseTechId
    local selectedTrack = selectedBase and kPrototypeTrackForTechId[selectedBase] or nil
    local totalCost     = self:GetTotalCost()
    local pres          = PlayerUI_GetPersonalResources()
    local canAfford     = pres >= totalCost
    local purchasable   = self:GetFinalPurchasable()

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
            elseif selectedBase then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorExpensive)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorTooExpensive)
            else
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorFooterDim)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorDim)
            end

        elseif btn.Kind == "base" then
            local track      = btn.Track
            local tid        = btn.TechId
            local unlocked   = self:GetTrackUnlocked(track)
            local owned      = self:GetAlreadyOwnsBase(tid)
            local isSelected = (selectedBase == tid)

            if not unlocked or owned then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorLocked)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorDim)
            elseif isSelected then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorSelected)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorSelected)
            else
                local cost = GetPrototypeCost(tid)
                if pres >= cost then
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorHover or GUIPrototypeLabBuyMenu.kBtnColorNormal)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorAffordable)
                else
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorHover or GUIPrototypeLabBuyMenu.kBtnColorExpensive)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorTooExpensive)
                end
            end

        elseif btn.Kind == "upgrade" then
            local track        = btn.Track
            local tid          = btn.TechId
            -- An upgrade is selectable only when its track's base is selected AND
            -- the track's Experimental Technologies research has been completed.
            local trackActive  = (selectedTrack == track) and self:GetExperimentalUnlocked(track)
            local isInSelected = self.selectedUpgrades[tid] == true

            if not trackActive then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorLocked)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorDim)
            elseif isInSelected then
                rect:SetColor(GUIPrototypeLabBuyMenu.kBtnColorUpgradeOn)
                label:SetColor(GUIPrototypeLabBuyMenu.kColorUpgradeOn)
            else
                if canAfford then
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorHover or GUIPrototypeLabBuyMenu.kBtnColorNormal)
                    label:SetColor(GUIPrototypeLabBuyMenu.kColorAffordable)
                else
                    rect:SetColor(over and GUIPrototypeLabBuyMenu.kBtnColorHover or GUIPrototypeLabBuyMenu.kBtnColorExpensive)
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
            self.popupText:SetText(desc)

            local cs   = self.customScale
            local ph_d = CountLines(desc) * kPopupLineH + kPopupPadY * 2
            -- Width = widest description line + a small margin each side.
            local pw_d = MaxLineWidth(self.popupText, desc) + kPopupPadX * 2
            self.popup:SetSize(Vector(pw_d, ph_d, 0))
            -- Give the text item an explicit width so Align_Center centres within the popup.
            self.popupText:SetSize(Vector(pw_d, 0, 0))

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
                if self:GetTrackUnlocked(track) and not owned then
                    local prevTrack = self.selectedBaseTechId and kPrototypeTrackForTechId[self.selectedBaseTechId] or nil
                    if prevTrack ~= track then
                        self.selectedUpgrades = {}
                    end
                    self.selectedBaseTechId = tid
                    MarineBuy_OnMouseOver()
                end
                return true
            end

            if btn.Kind == "upgrade" then
                local track = btn.Track
                local tid   = btn.TechId
                if self.selectedBaseTechId and kPrototypeTrackForTechId[self.selectedBaseTechId] == track
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
    local list = { self.selectedBaseTechId }
    for techId in pairs(self.selectedUpgrades) do
        table.insert(list, techId)
    end
    Client.SendNetworkMessage("Buy", BuildBuyMessage(list), true)
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
    self.popupText       = nil
    self.buttons         = {}
    self.footerItem      = nil
    self.footerLabel     = nil
    self.divider         = nil
    self.mouseOverStates = {}
    self.hoveredTechId   = nil

    MouseTracker_SetIsVisible(false)
end
