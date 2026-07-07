Script.Load("lua/CNBalance/GUI/GUIUtility.lua")

GUIMarineHUD.kTeamCountIconStart = Vector(25, 30, 0)
GUIMarineHUD.kMinimapPowerPos = Vector(25, 30 + 32, 0)
GUIMarineHUD.kLocationTextOffset = Vector(75, 30 + 32, 0)
GUIMarineHUD.kMinimapPos = Vector(30, 64 + 32, 0)

GUIMarineHUD.kUpgradeSize = Vector(80, 80, 0)

GUIMarineHUD.kTeamIconSize =  GUIScale( Vector( 48, 24, 0 ) )
GUIMarineHUD.kCountNoUsed = Color(0.3 , 0.3 , 0.3 , 1)
GUIMarineHUD.kCountHaveUser = Color(0x01 / 0xFF, 0x8F / 0xFF, 0xFF / 0xFF, 1)

local function ResetTeamCountIcon(element)
    element.count = 0
    element:SetColor(GUIMarineHUD.kCountNoUsed)
    element.text:SetIsVisible(false)
end

local function CreateTeamCountElement(techID)
    local teamCountIcon = GetGUIManager():CreateGraphicItem()
    teamCountIcon:SetSize(GUIMarineHUD.kTeamIconSize)
    teamCountIcon:SetTexture(kInventoryIconsTexture)
    teamCountIcon:SetTexturePixelCoordinates(GetTexCoordsForTechId(techID))
    teamCountIcon:SetAnchor(GUIItem.Left, GUIItem.Top)
    teamCountIcon:SetColor(GUIMarineHUD.kBackgroundColor)

    local countText = GUIManager:CreateTextItem()
    countText:SetPosition(Vector( -9 , -12, 0 ) )
    countText:SetAnchor( GUIItem.Right, GUIItem.Bottom )
    countText:SetFontName( Fonts.kAgencyFB_Large_Bold )
    countText:SetColor( GUIMarineHUD.kBackgroundColor )
    countText:SetScale(  GUIScale( Vector(1,1,0) * 0.4725 ))  --Scaled???
    countText:SetLayer( kGUILayerPlayerHUDForeground2 )
    teamCountIcon:AddChild(countText)

    teamCountIcon.text = countText
    teamCountIcon.techId = techID
    
    ResetTeamCountIcon(teamCountIcon)
    return teamCountIcon
end


local function UpdateTeamCount(self,teamInfo,element)
    local techMapName = GUIMarineBuyMenu._GetMapNameForNetvar(nil,element.techId)       --???
    assert(techMapName)
    if  techMapName then
        local netVarName = TeamInfo_GetUserTrackerNetvarName(techMapName)
        local numUsers = teamInfo[netVarName]
        if element.count ~= numUsers then
            element.count = numUsers
            element.text:SetText(string.format("x%i",element.count))
            
            element:SetColor(numUsers ~= 0 and self.kCountHaveUser or self.kCountNoUsed)
            element.text:SetIsVisible(numUsers > 1)
        end
    end
end

local function CreateTechIcon( techId)
    local techIcon = GetGUIManager():CreateGraphicItem()
    techIcon:SetTexture(GUIMarineHUD.kUpgradesTexture)
    techIcon:SetAnchor(GUIItem.Right, GUIItem.Center)
    techIcon:SetIsVisible(false)
    techIcon:SetTexturePixelCoordinates(GUIUnpackCoords(GetTextureCoordinatesForIcon(techId)))
    techIcon:SetColor(kIconColors[kMarineTeamType])
    return techIcon
end

-- ── Prototype upgrade panels ──────────────────────────────────────────────────
-- Two separate panels; both grow upward from the screen bottom.
--
-- JETPACK panel   → bottom-LEFT (above the weapon inventory left side)
-- CANNON panel    → bottom-RIGHT (inset from the ammo readout), 2-column layout
--
-- Exo upgrades live in GUIExoUpgradeHud (also repositioned to bottom-left).

-- Shared styling
local kProtoPanelBgColor  = Color(0.05, 0.09, 0.12, 0.55)
local kProtoTextColor     = Color(0.85, 0.9,  0.95, 0.95)
local kProtoHeaderColor   = Color(0.4,  0.85, 1.0,  1.0)
local kProtoFontName      = Fonts.kAgencyFB_Small
local kProtoFontScale     = GUIScale(Vector(1, 1, 0))
local kProtoPanelPadX     = 12
local kProtoPanelPadY     = 10
local kProtoLineH         = 20   -- px per text line

-- Human-readable names for prototype upgrade tech IDs.
-- GetDisplayNameForTechId returns nil for custom mod tech IDs (no localization entry).
local kProtoUpgradeName = {
    [kTechId.PrototypeBoost]               = "Boost",
    [kTechId.PrototypeJetpackExtraFuel]    = "Extra Fuel",
    [kTechId.PrototypeJetpackArmour]       = "Armour Plating",
    [kTechId.PrototypeExoArmour]           = "Armour Plating",
    [kTechId.PrototypeExoExtraFuel]        = "Extra Fuel",
    [kTechId.PrototypeLifeformScanner]     = "Lifeform Scanner",
    [kTechId.PrototypeEmergencyEjection]   = "Emergency Ejection",
    [kTechId.PrototypeSelfDestruct]        = "Self-Destruct",
    [kTechId.PrototypeResupply]            = "Resupply",
    [kTechId.PrototypeExtendedMagazine]    = "Extended Magazine",
    [kTechId.PrototypeChargeShot]          = "Charge Shot",
    [kTechId.PrototypeTungstenPenetrator]  = "Tungsten Penetrator",
    [kTechId.PrototypeShotgun]             = "Shotgun",
}

-- Jetpack panel (BOTTOM-LEFT)
-- Positioned relative to screen centre using Middle/Center anchor.
-- "Left inset" = distance from screen left edge to panel left edge.
-- "Bottom inset" = distance from screen bottom to panel bottom edge.
local kJPPanelW           = 230
local kJPPanelLeftInset   = 350   -- px from left
local kJPPanelBottomInset = 48    -- px from bottom

-- Cannon panel (BOTTOM-RIGHT, 2-column)
local kCannonPanelW           = 310
local kCannonPanelRightInset  = 255   -- px from right
local kCannonPanelBottomInset = 40    -- px from bottom
local kCannonColW             = 145   -- width of each upgrade column

-- Infection meter (stacked directly above the Jetpack panel). Top half =
-- "Infection"/"Infected!" label, bottom half = X/3 hit-count readout - equal
-- row heights so each sits centered in its own half of the box.
local kInfBarW_d   = 160   -- design px
local kInfRowH_d   = 18    -- design px, EACH row's height (label row + percentage row)
local kInfGap_d    = 10    -- design px, gap above the Jetpack panel
local kInfTextShiftLeft_d = 3  -- design px, nudges the (already-centered) text left slightly

-- Must match Marine.lua's OnProcessMove constants exactly, since this file
-- independently re-derives the same decay animation from networked state
-- rather than reading a per-frame networked fraction.
local kInfectionDoTSeconds = 5

-- Rendered width (screen px) of a single line of text in one of the proto text
-- items.  GetTextWidth returns the unscaled font width, so multiply by the item's
-- own scale (which is GUIScale-based, giving screen pixels to match panel sizes).
local function ProtoTextWidth(item, str)
    return item:GetTextWidth(str) * item:GetScale().x
end

local baseInitialize = GUIMarineHUD.Initialize
function GUIMarineHUD:Initialize()
    self.militaryProtocol = CreateTechIcon(kTechId.MilitaryProtocol)
    self.lastMilitaryProtocol = nil

    self.autoMedPack = GUIUtility_CreateRequestIcon(kTechId.MedPack, Vector(-52 - 32, -36, 0),kMarineTeamType)
    self.autoAmmoPack = GUIUtility_CreateRequestIcon(kTechId.AmmoPack, Vector(52 - 32, -36, 0),kMarineTeamType)
    self.teamCountElements = {}
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Shotgun))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.HeavyMachineGun))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.GrenadeLauncher))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Flamethrower))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Cannon))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.DualRailgunExosuit))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.DualMinigunExosuit))
    table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Jetpack))
    baseInitialize(self)

    self.resourceDisplay.background:AddChild(self.autoMedPack)
    self.resourceDisplay.background:AddChild(self.autoAmmoPack)
    self.background:AddChild(self.militaryProtocol)
    --........ or i should totally rewrite initialize
    for index,element in ipairs(self.teamCountElements) do
        --Vector(25, 46, 0)
        local offset = index - 1
        element:SetPosition(GUIMarineHUD.kTeamCountIconStart + Vector(offset * 48, offset * 2,0))
        self.background:AddChild(element)
    end

    -- ── Jetpack upgrade panel (BOTTOM-LEFT) ──────────────────────────────────
    -- Middle/Center anchor matches the Cannon panel pattern exactly so the
    -- sw/sh positioning math is identical and guaranteed to work.
    self.jetpackPanelBg = GetGUIManager():CreateGraphicItem()
    self.jetpackPanelBg:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.jetpackPanelBg:SetColor(kProtoPanelBgColor)
    self.jetpackPanelBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.jetpackPanelBg:SetIsVisible(false)

    -- "JETPACK" header — Middle/Top child: auto-sizes to fit text, centres on panel.
    self.jetpackHeaderText = GetGUIManager():CreateTextItem()
    self.jetpackHeaderText:SetFontName(kProtoFontName)
    self.jetpackHeaderText:SetScale(kProtoFontScale)
    self.jetpackHeaderText:SetColor(kProtoHeaderColor)
    self.jetpackHeaderText:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.jetpackHeaderText:SetTextAlignmentX(GUIItem.Align_Center)
    self.jetpackHeaderText:SetTextAlignmentY(GUIItem.Align_Min)
    self.jetpackHeaderText:SetPosition(GUIScale(Vector(0, kProtoPanelPadY, 0)))
    self.jetpackHeaderText:SetText("JETPACK")
    self.jetpackPanelBg:AddChild(self.jetpackHeaderText)

    -- Upgrade list — Middle/Top child, will receive explicit width in Update.
    self.jetpackPanelText = GetGUIManager():CreateTextItem()
    self.jetpackPanelText:SetFontName(kProtoFontName)
    self.jetpackPanelText:SetScale(kProtoFontScale)
    self.jetpackPanelText:SetColor(kProtoTextColor)
    self.jetpackPanelText:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.jetpackPanelText:SetTextAlignmentX(GUIItem.Align_Center)
    self.jetpackPanelText:SetTextAlignmentY(GUIItem.Align_Min)
    self.jetpackPanelText:SetPosition(GUIScale(Vector(0, kProtoPanelPadY + kProtoLineH, 0)))
    self.jetpackPanelText:SetText("")
    self.jetpackPanelBg:AddChild(self.jetpackPanelText)

    -- ── Cannon upgrade panel (BOTTOM-RIGHT, 2-column) ────────────────────────
    self.cannonPanelBg = GetGUIManager():CreateGraphicItem()
    self.cannonPanelBg:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.cannonPanelBg:SetColor(kProtoPanelBgColor)
    self.cannonPanelBg:SetSize(GUIScale(Vector(kCannonPanelW, 0, 0)))
    self.cannonPanelBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.cannonPanelBg:SetIsVisible(false)

    -- "CANNON" header — centered horizontally in the panel.
    self.cannonHeaderText = GetGUIManager():CreateTextItem()
    self.cannonHeaderText:SetFontName(kProtoFontName)
    self.cannonHeaderText:SetScale(kProtoFontScale)
    self.cannonHeaderText:SetColor(kProtoHeaderColor)
    self.cannonHeaderText:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.cannonHeaderText:SetTextAlignmentX(GUIItem.Align_Center)
    self.cannonHeaderText:SetTextAlignmentY(GUIItem.Align_Min)
    self.cannonHeaderText:SetPosition(GUIScale(Vector(0, kProtoPanelPadY, 0)))
    self.cannonHeaderText:SetText("CANNON")
    self.cannonPanelBg:AddChild(self.cannonHeaderText)

    -- Left upgrade column (items 1, 3, 5 …).
    self.cannonColLeft = GetGUIManager():CreateTextItem()
    self.cannonColLeft:SetFontName(kProtoFontName)
    self.cannonColLeft:SetScale(kProtoFontScale)
    self.cannonColLeft:SetColor(kProtoTextColor)
    self.cannonColLeft:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.cannonColLeft:SetTextAlignmentX(GUIItem.Align_Center)
    self.cannonColLeft:SetTextAlignmentY(GUIItem.Align_Min)
    self.cannonColLeft:SetPosition(GUIScale(Vector(kCannonColW * 0.5, kProtoPanelPadY + kProtoLineH, 0)))
    self.cannonColLeft:SetText("")
    self.cannonPanelBg:AddChild(self.cannonColLeft)

    -- Right upgrade column (items 2, 4, 6 …).
    self.cannonColRight = GetGUIManager():CreateTextItem()
    self.cannonColRight:SetFontName(kProtoFontName)
    self.cannonColRight:SetScale(kProtoFontScale)
    self.cannonColRight:SetColor(kProtoTextColor)
    self.cannonColRight:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.cannonColRight:SetTextAlignmentX(GUIItem.Align_Center)
    self.cannonColRight:SetTextAlignmentY(GUIItem.Align_Min)
    self.cannonColRight:SetPosition(GUIScale(Vector(kCannonColW * 1.5, kProtoPanelPadY + kProtoLineH, 0)))
    self.cannonColRight:SetText("")
    self.cannonPanelBg:AddChild(self.cannonColRight)

    -- NOTE: The Lifeform Scanner HUD is handled entirely by GUILifeformScanner
    -- (bottom-left panel with "BRAZIER INDUSTRIES" header).  No duplicate panel here.

    -- Cannon Charge Shot — vertical bar on the right edge of the screen.
    -- Position is set each frame in Update using actual sw/sh so it stays
    -- flush to the edge at any resolution.
    self.cannonChargeBg = GetGUIManager():CreateGraphicItem()
    self.cannonChargeBg:SetAnchor(GUIItem.Middle, GUIItem.Center)
    -- Marine team blue, 85% opacity.
    self.cannonChargeBg:SetColor(Color(0.02, 0.06, 0.18, 0.85))
    self.cannonChargeBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.cannonChargeBg:SetIsVisible(false)

    -- Fill bar: child of the background, repositioned each frame to grow bottom-to-top.
    self.cannonChargeFill = GetGUIManager():CreateGraphicItem()
    self.cannonChargeFill:SetAnchor(GUIItem.Left, GUIItem.Top)
    -- Marine blue fill, 50% of original opacity (0.80 → 0.40)
    self.cannonChargeFill:SetColor(Color(0.20, 0.50, 1.0, 0.40))
    self.cannonChargeBg:AddChild(self.cannonChargeFill)

    -- "CHARGE" as one character per line — renders vertically without rotation.
    -- Anchor Middle/Top (same pattern as the other correctly-centered HUD labels,
    -- e.g. cannonHeaderText) rather than Left/Top: a Left-anchored box + SetSize
    -- was NOT centering the glyph column reliably, leaving a visible gap on one
    -- Anchor Middle/Center: the origin is the bar's exact centre, and
    -- Align_Center on both axes centres the "CHARGE" block on that origin, so
    -- position (0,0) centres it in the bar regardless of the bar's size. (The
    -- previous Middle/Top anchor + position.x = barW*0.5 double-offset it,
    -- pushing the text half a bar-width to the right.)
    -- Left/Top anchor + Align_Min on Y: (0,0) is the bar's TOP-LEFT corner and
    -- the text grows DOWNWARD from the y position, instead of Left/Center +
    -- Align_Center (which centred the "CHARGE" block on the bar's vertical
    -- MIDDLE, spilling out above and below it - the reported bug).
    self.cannonChargeText = GUIManager:CreateTextItem()
    self.cannonChargeText:SetFontName(Fonts.kAgencyFB_Small)
    self.cannonChargeText:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.cannonChargeText:SetTextAlignmentX(GUIItem.Align_Center)
    self.cannonChargeText:SetTextAlignmentY(GUIItem.Align_Min)
    self.cannonChargeText:SetScale(GUIScale(Vector(0.5, 0.5, 0)))
    -- Marine blue text, 100% opacity.
    self.cannonChargeText:SetColor(Color(0.35, 0.62, 1.0, 1.0))
    self.cannonChargeText:SetText("C\nH\nA\nR\nG\nE")
    self.cannonChargeBg:AddChild(self.cannonChargeText)

    -- Skulk Parasite Infection meter — horizontal bar, positioned above the
    -- Jetpack panel each frame in Update (see below). Label row on top,
    -- fill bar + percentage readout underneath.
    self.infectionBg = GetGUIManager():CreateGraphicItem()
    self.infectionBg:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.infectionBg:SetColor(Color(0.02, 0.06, 0.18, 0.85))
    self.infectionBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.infectionBg:SetIsVisible(false)

    -- Fill sits behind both text rows, spanning the whole box - it is NOT a
    -- child of either text row, so it can visually cross the label/count
    -- boundary as it animates rather than being clipped to one half.
    self.infectionFill = GetGUIManager():CreateGraphicItem()
    self.infectionFill:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.infectionFill:SetColor(Color(0.20, 0.50, 1.0, 0.40))
    self.infectionBg:AddChild(self.infectionFill)

    -- Top half: "Infection"/"Infected!" label. Left/Top anchor with an
    -- explicit position.x computed each frame from the text's own rendered
    -- width (via ProtoTextWidth, the same technique already proven correct
    -- for the Jetpack/Cannon panel headers elsewhere in this file) - a
    -- Middle-anchor/midpoint-position attempt here did NOT actually center
    -- reliably in testing, so this file no longer relies on that trick for
    -- the Infection meter specifically.
    self.infectionLabelText = GUIManager:CreateTextItem()
    self.infectionLabelText:SetFontName(Fonts.kAgencyFB_Small)
    self.infectionLabelText:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.infectionLabelText:SetTextAlignmentX(GUIItem.Align_Min)
    self.infectionLabelText:SetTextAlignmentY(GUIItem.Align_Center)
    self.infectionLabelText:SetScale(GUIScale(Vector(0.7, 0.7, 0)))
    self.infectionLabelText:SetColor(Color(0.35, 0.62, 1.0, 1.0))
    self.infectionLabelText:SetText("Infection")
    self.infectionBg:AddChild(self.infectionLabelText)

    -- Bottom half: percentage readout, same explicit-centering pattern.
    self.infectionPercentText = GUIManager:CreateTextItem()
    self.infectionPercentText:SetFontName(Fonts.kAgencyFB_Small)
    self.infectionPercentText:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.infectionPercentText:SetTextAlignmentX(GUIItem.Align_Min)
    self.infectionPercentText:SetTextAlignmentY(GUIItem.Align_Center)
    self.infectionPercentText:SetScale(GUIScale(Vector(0.7, 0.7, 0)))
    self.infectionPercentText:SetColor(Color(0.35, 0.62, 1.0, 1.0))
    self.infectionPercentText:SetText("0.0%")
    self.infectionBg:AddChild(self.infectionPercentText)

    -- ── Resupply Exo prompt panel (SCREEN-CENTRE BOTTOM) ────────────────────
    -- Visible when a Marine is in use-range of a friendly Exo with Resupply.
    -- Layout (horizontally centred):  [ammopack icon]  "RESUPPLY  E"  "Cooldown: Xs"
    local kResupplyPanelH = 72   -- design px
    self.resupplyPanel = GetGUIManager():CreateGraphicItem()
    self.resupplyPanel:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.resupplyPanel:SetColor(Color(0.02, 0.06, 0.18, 0.60))
    self.resupplyPanel:SetLayer(kGUILayerPlayerHUDForeground2)
    self.resupplyPanel:SetIsVisible(false)

    -- Ammopack icon: the same flat build-menu icon the Marine Commander uses for
    -- the AmmoPack ability (ui/buildmenu.dds, a 12-column grid of 80x80 cells),
    -- not the 3D world-model texture (which looked wrong as a flat HUD icon).
    self.resupplyIcon = GetGUIManager():CreateGraphicItem()
    self.resupplyIcon:SetTexture("ui/buildmenu.dds")
    do
        local kIconCellSize = 80
        local iconX, iconY = GetMaterialXYOffset(kTechId.AmmoPack)
        if iconX then
            self.resupplyIcon:SetTexturePixelCoordinates(
                iconX * kIconCellSize, iconY * kIconCellSize,
                iconX * kIconCellSize + kIconCellSize, iconY * kIconCellSize + kIconCellSize)
        end
    end
    self.resupplyIcon:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.resupplyIcon:SetColor(Color(1, 1, 1, 0.85))
    self.resupplyPanel:AddChild(self.resupplyIcon)

    -- Header: "RESUPPLY" + key hint.
    self.resupplyHeader = GetGUIManager():CreateTextItem()
    self.resupplyHeader:SetFontName(kProtoFontName)
    self.resupplyHeader:SetScale(kProtoFontScale)
    self.resupplyHeader:SetColor(kProtoHeaderColor)
    self.resupplyHeader:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.resupplyHeader:SetTextAlignmentX(GUIItem.Align_Min)
    self.resupplyHeader:SetTextAlignmentY(GUIItem.Align_Min)
    self.resupplyHeader:SetText("RESUPPLY")
    self.resupplyPanel:AddChild(self.resupplyHeader)

    -- Status line: "Ready" or "Cooldown: Xs".
    self.resupplyStatus = GetGUIManager():CreateTextItem()
    self.resupplyStatus:SetFontName(kProtoFontName)
    self.resupplyStatus:SetScale(kProtoFontScale)
    self.resupplyStatus:SetColor(kProtoTextColor)
    self.resupplyStatus:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.resupplyStatus:SetTextAlignmentX(GUIItem.Align_Min)
    self.resupplyStatus:SetTextAlignmentY(GUIItem.Align_Min)
    self.resupplyStatus:SetText("")
    self.resupplyPanel:AddChild(self.resupplyStatus)

    -- "E" key hint badge.
    self.resupplyKey = GetGUIManager():CreateTextItem()
    self.resupplyKey:SetFontName(kProtoFontName)
    self.resupplyKey:SetScale(kProtoFontScale)
    self.resupplyKey:SetColor(Color(1.0, 0.85, 0.2, 1.0))   -- yellow
    self.resupplyKey:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.resupplyKey:SetTextAlignmentX(GUIItem.Align_Min)
    self.resupplyKey:SetTextAlignmentY(GUIItem.Align_Min)
    self.resupplyKey:SetText("[E]")
    self.resupplyPanel:AddChild(self.resupplyKey)
end

local baseUninitialize = GUIMarineHUD.Uninitialize
function GUIMarineHUD:Uninitialize()
    self.teamCountElements = nil

    -- Destroy the jetpack upgrade panel (header + text children destroyed with it).
    if self.jetpackPanelBg then
        GUI.DestroyItem(self.jetpackPanelBg)
        self.jetpackPanelBg    = nil
        self.jetpackHeaderText = nil
        self.jetpackPanelText  = nil
    end
    -- Destroy the cannon upgrade panel (column children destroyed with it).
    if self.cannonPanelBg then
        GUI.DestroyItem(self.cannonPanelBg)
        self.cannonPanelBg   = nil
        self.cannonHeaderText = nil
        self.cannonColLeft    = nil
        self.cannonColRight   = nil
    end

    -- Destroy the cannon charge readout (fill + text are children, destroyed with it).
    if self.cannonChargeBg then
        GUI.DestroyItem(self.cannonChargeBg)
        self.cannonChargeBg   = nil
        self.cannonChargeFill = nil
        self.cannonChargeText = nil
    end

    -- Destroy the Infection meter (label/fill/percentage children destroyed with it).
    if self.infectionBg then
        GUI.DestroyItem(self.infectionBg)
        self.infectionBg          = nil
        self.infectionLabelText   = nil
        self.infectionFill        = nil
        self.infectionPercentText = nil
    end

    -- Destroy the resupply prompt panel (children destroyed with it).
    if self.resupplyPanel then
        GUI.DestroyItem(self.resupplyPanel)
        self.resupplyPanel  = nil
        self.resupplyIcon   = nil
        self.resupplyHeader = nil
        self.resupplyStatus = nil
        self.resupplyKey    = nil
    end

    baseUninitialize(self)
end

local baseReset = GUIMarineHUD.Reset
function GUIMarineHUD:Reset()
    baseReset(self)
    self.militaryProtocol:SetPosition(Vector(GUIMarineHUD.kUpgradePos.x, GUIMarineHUD.kUpgradePos.y - GUIMarineHUD.kUpgradeSize.y - 8, 0) * self.scale)
    self.militaryProtocol:SetSize(GUIMarineHUD.kUpgradeSize * self.scale)
    self.militaryProtocol:SetIsVisible(false)

    local marineHudBars = GetAdvancedOption("hudbars_m")
    if marineHudBars > 0 then
        if marineHudBars == 2 then
            local pos = self.militaryProtocol:GetPosition()
            self.militaryProtocol:SetPosition(Vector(pos.x, pos.y-100, 0))
        end
    end

    for _,element in ipairs(self.teamCountElements) do
        ResetTeamCountIcon(element)
    end

    -- Clear upgrade panel text on reset.
    if self.jetpackPanelText  then self.jetpackPanelText:SetText("")  end
    if self.cannonColLeft     then self.cannonColLeft:SetText("")     end
    if self.cannonColRight    then self.cannonColRight:SetText("")    end
end

local kErrorColor = Color(1, 0, 0, 1)

local baseUpdate = GUIMarineHUD.Update
function GUIMarineHUD:Update(deltaTime)
    baseUpdate(self,deltaTime)
    local player = Client.GetLocalPlayer()
    local hasMilitaryProtocol = GetHasTech(player,kTechId.MilitaryProtocol)
    if hasMilitaryProtocol ~= self.lastMilitaryProtocol then
        self.lastMilitaryProtocol = hasMilitaryProtocol
        self.militaryProtocol:SetIsVisible(self.lastMilitaryProtocol)
    end

    local requestHandle = player.timeLastPrimaryRequestHandle and not hasMilitaryProtocol or false
    if requestHandle then
        local time = Shared.GetTime()
        local color = kIconColors[kMarineTeamType]
        local percentage = Clamp(1 - (player.timeLastPrimaryRequestHandle - time)/kAutoMedCooldown,0,1)
        local medColor = color * (percentage * percentage)
        medColor.a = percentage >= 1 and 1 or 0.5
        self.autoMedPack:SetColor(medColor)

        percentage = Clamp(1 - (player.timeLastAutoAmmoPack - time)/kAutoAmmoCooldown,0,1)
        local ammoColor = color * (percentage * percentage)
        ammoColor.a = percentage >= 1 and 1 or 0.5
        percentage = percentage * percentage
        self.autoAmmoPack:SetColor(ammoColor)
    end

    self.autoAmmoPack:SetIsVisible(requestHandle)
    self.autoMedPack:SetIsVisible(requestHandle)
    
    local teamInfo = GetTeamInfoEntity(player:GetTeamNumber())
    if teamInfo then
        for _,element in ipairs(self.teamCountElements) do
            UpdateTeamCount(self,teamInfo,element)
        end
    end


    if self.gameTime:GetIsVisible() then
        self.gameTime:SetColor(PlayerUI_DeadlockActivated() and kErrorColor or kBrightColor)
    end

    -- Both panels use Middle/Center anchor, so positions are relative to the
    -- screen centre.  Formula for bottom-left placement:
    --   X = -screenW/2 + leftInset
    --   Y =  screenH/2 - bottomInset - panelHeight
    -- and for bottom-right:
    --   X =  screenW/2 - rightInset - panelWidth
    --   Y =  screenH/2 - bottomInset - panelHeight
    local sw = Client.GetScreenWidth()
    local sh = Client.GetScreenHeight()

    -- Helper: decode a prototypeUpgradeBits integer into a list of techIds.
    -- Mirrors PrototypeUpgradesMixin:GetPrototypeUpgradeList() without needing self.
    local function DecodeUpgradeBits(bits)
        local list = {}
        if not PrototypeUpgradesMixin or not PrototypeUpgradesMixin.kBit then return list end
        bits = bits or 0
        for techId, bitIdx in pairs(PrototypeUpgradesMixin.kBit) do
            if math.floor(bits / (2 ^ bitIdx)) % 2 == 1 then
                table.insert(list, techId)
            end
        end
        return list
    end

    -- ── Jetpack upgrade panel (BOTTOM-LEFT) ──────────────────────────────────
    local inExo = player:isa("Exo")
    if self.jetpackPanelBg and player then
        local jpLines = {}
        local isJP   = player:isa("JetpackMarine")
        local showJP = isJP or (inExo and player.prevHadJetpack)
        if isJP then
            if player.GetPrototypeUpgradeList then
                for _, techId in ipairs(player:GetPrototypeUpgradeList()) do
                    if techId ~= kTechId.PrototypeBoost then
                        table.insert(jpLines, kProtoUpgradeName[techId] or "?")
                    end
                end
            end
            -- Boost: always label it; append countdown only when on cooldown.
            if player.GetHasPrototypeUpgrade and player:GetHasPrototypeUpgrade(kTechId.PrototypeBoost) then
                local remain = (player.timePrototypeBoostNext or 0) - Shared.GetTime()
                if remain > 0 then
                    table.insert(jpLines, string.format("Boost  %.1fs", remain))
                else
                    table.insert(jpLines, "Boost")
                end
            end
        elseif inExo and player.prevHadJetpack then
            -- Mirror the JetpackMarine path's display order: non-Boost upgrades first,
            -- Boost appended last (with no cooldown countdown since we're not that player).
            local bits = player.prevPrototypeUpgradeBits or 0
            local kBit = PrototypeUpgradesMixin and PrototypeUpgradesMixin.kBit
            local prevHadBoost = false
            for _, techId in ipairs((kPrototypeUpgradesForTrack or {})["jetpack"] or {}) do
                local idx = kBit and kBit[techId]
                if idx ~= nil and math.floor(bits / (2^idx)) % 2 == 1 then
                    if techId == kTechId.PrototypeBoost then
                        prevHadBoost = true   -- append after the others
                    else
                        table.insert(jpLines, kProtoUpgradeName[techId] or "?")
                    end
                end
            end
            if prevHadBoost then
                table.insert(jpLines, kProtoUpgradeName[kTechId.PrototypeBoost] or "Boost")
            end
        end
        self.jetpackPanelBg:SetIsVisible(showJP)
        if showJP then
            self.jetpackPanelText:SetText(table.concat(jpLines, "\n"))
            local lh   = GUIScale(kProtoLineH)
            local rows = math.max(#jpLines, 0)
            local h    = (1 + rows) * lh + GUIScale(kProtoPanelPadY) * 2
            -- Width = widest text content + left/right padding.
            local maxW = ProtoTextWidth(self.jetpackHeaderText, "JETPACK")
            for _, line in ipairs(jpLines) do
                maxW = math.max(maxW, ProtoTextWidth(self.jetpackPanelText, line))
            end
            local w = maxW + GUIScale(kProtoPanelPadX) * 2
            self.jetpackPanelBg:SetSize(Vector(w, h, 0))
            -- Middle/Center anchor: position relative to screen centre.
            -- Panel bottom-left target = (kJPPanelLeftInset from left, kJPPanelBottomInset from bottom).
            self.jetpackPanelBg:SetPosition(Vector(
                -sw * 0.5 + GUIScale(kJPPanelLeftInset),
                 sh * 0.5 - GUIScale(kJPPanelBottomInset) - h,
                0))
            -- Set width on text children so Align_Center centres within the panel.
            self.jetpackHeaderText:SetSize(Vector(w, 0, 0))
            self.jetpackPanelText:SetSize(Vector(w, 0, 0))
            -- Expose the absolute screen Y of the jetpack panel's top edge so
            -- GUIExoHUD can position the Lifeform Scanner panel directly above it.
            -- Middle/Center anchor: absolute Y = sh/2 + position.y = sh - bottomInset - h.
            _G.gJetpackPanelTopAbsY = sh - GUIScale(kJPPanelBottomInset) - h
        else
            -- Panel not showing: expose the bottom inset position as the reference.
            _G.gJetpackPanelTopAbsY = sh - GUIScale(kJPPanelBottomInset)
        end
    end

    -- ── Skulk Parasite Infection meter ───────────────────────────────────────
    -- Marine/JetpackMarine only. Stacked directly above the Jetpack panel
    -- (or its resting spot when the panel isn't showing) using the absolute Y
    -- this same Update just published above. Top row = "Infection"/"Infected!"
    -- label (no fill behind it); bottom row = percentage readout with the
    -- fill bar confined to just that row, filling left-to-right underneath it.
    if self.infectionBg then
        local showInfection = player and (player:isa("Marine") or player:isa("JetpackMarine"))
                               and (player.infectionHitCount or 0) > 0
        self.infectionBg:SetIsVisible(showInfection or false)
        if showInfection then

            local barW   = GUIScale(kInfBarW_d)
            local rowH   = GUIScale(kInfRowH_d)
            local gap    = GUIScale(kInfGap_d)
            local totalH = rowH * 2

            local infectionTopAbsY = (_G.gJetpackPanelTopAbsY or sh) - gap - totalH

            -- Centre the (fixed-width) Infection box over the Jetpack panel's
            -- own ACTUAL width, which varies with its content - left-aligning
            -- both boxes at the same X only lines up their left edges, not
            -- their centres, whenever the two widths differ (they usually do).
            local jpLeftX = -sw * 0.5 + GUIScale(kJPPanelLeftInset)
            local jpWidth = barW
            if self.jetpackPanelBg and self.jetpackPanelBg:GetIsVisible() then
                jpWidth = self.jetpackPanelBg:GetSize().x
            end
            local infectionX = jpLeftX + (jpWidth - barW) * 0.5

            self.infectionBg:SetSize(Vector(barW, totalH, 0))
            self.infectionBg:SetPosition(Vector(
                infectionX,
                infectionTopAbsY - sh * 0.5,
                0))

            -- Displayed fill fraction animates continuously (not in discrete
            -- 1/3 steps) across the full kInfectionDoTSeconds unwind, even
            -- though the actual damage ticks - and the true networked
            -- infectionHitCount used for the "X/3" text below - only change
            -- at 3 fixed points within that span. The fill is purely a
            -- cosmetic smoothing; the text always shows true game state.
            local displayedCount = player.infectionHitCount or 0
            if player.infectionWasFullyInfected then
                local elapsed = Shared.GetTime() - (player.infectionLastHitTime or 0)
                displayedCount = math.max(0, 3 - math.min(elapsed, kInfectionDoTSeconds) / kInfectionDoTSeconds * 3)
            end

            local infected   = player.infectionWasFullyInfected
            local themeColor = infected and Color(1.0, 0.45, 0.1, 1.0) or Color(0.35, 0.62, 1.0, 1.0)

            -- Fill occupies ONLY the bottom row (behind the percentage text),
            -- never the top label row.
            local frac  = Clamp(displayedCount / 3, 0, 1)
            local fillW = math.max(1, frac * barW)
            self.infectionFill:SetSize(Vector(fillW, rowH, 0))
            self.infectionFill:SetPosition(Vector(0, rowH, 0))
            self.infectionFill:SetColor(infected
                and Color(1.0, 0.45, 0.1, 0.40)
                or  Color(0.20, 0.50, 1.0, 0.40))

            -- Percentage is DISPLAY ONLY - derived from the same hit-based
            -- state (displayedCount above), capped at 100% (Clamp already
            -- caps frac at 1 regardless of any transient overshoot).
            local displayPercent = frac * 100

            local labelStr   = infected and "Infected!" or "Infection"
            local percentStr = string.format("%.1f%%", displayPercent)

            local textShiftLeft = GUIScale(kInfTextShiftLeft_d)

            -- Align_Center on the Y axis centres the text vertically AROUND
            -- the given position.y (not within a [0,rowH] box below it) - so
            -- position.y must be each row's own MIDPOINT (rowH*0.5 / rowH*1.5),
            -- not its top edge (0 / rowH), or the text renders shifted upward
            -- out of its row (this was the "text too high" bug).
            self.infectionLabelText:SetText(labelStr)
            self.infectionLabelText:SetColor(themeColor)
            self.infectionLabelText:SetSize(Vector(0, rowH, 0))
            self.infectionLabelText:SetPosition(Vector(
                (barW - ProtoTextWidth(self.infectionLabelText, labelStr)) * 0.5 - textShiftLeft,
                rowH * 0.5, 0))

            self.infectionPercentText:SetText(percentStr)
            self.infectionPercentText:SetColor(themeColor)
            self.infectionPercentText:SetSize(Vector(0, rowH, 0))
            self.infectionPercentText:SetPosition(Vector(
                (barW - ProtoTextWidth(self.infectionPercentText, percentStr)) * 0.5 - textShiftLeft,
                rowH * 1.5, 0))

            -- Green poison-style screen pulse, triggered independently of the
            -- vanilla `poisoned` field so it stacks cleanly with real Lerk
            -- poison instead of interfering with it.
            if infected then
                local feedbackUI = ClientUI.GetScript("GUIPoisonedFeedback")
                if feedbackUI and player:GetIsAlive() and not feedbackUI:GetIsAnimating() then
                    feedbackUI:TriggerPoisonEffect()
                end
            end
        end
    end

    -- ── Cannon upgrade panel (BOTTOM-RIGHT, 2-column) ────────────────────────
    if self.cannonPanelBg and player then
        local cannonUpgrades = {}
        local hasCannon = false
        if inExo and player.prevHadCannon then
            hasCannon = true
            local bits = player.prevCannonUpgradeBits or 0
            local kBit = PrototypeUpgradesMixin and PrototypeUpgradesMixin.kBit
            for _, techId in ipairs((kPrototypeUpgradesForTrack or {})["cannon"] or {}) do
                local idx = kBit and kBit[techId]
                if idx ~= nil and math.floor(bits / (2^idx)) % 2 == 1 then
                    table.insert(cannonUpgrades, kProtoUpgradeName[techId] or "?")
                end
            end
        elseif player.GetHUDOrderedWeaponList then
            for _, w in ipairs(player:GetHUDOrderedWeaponList()) do
                if w.GetTechId and w:GetTechId() == kTechId.Cannon then
                    hasCannon = true
                    if w.GetPrototypeUpgradeList then
                        for _, techId in ipairs(w:GetPrototypeUpgradeList()) do
                            table.insert(cannonUpgrades, kProtoUpgradeName[techId] or "?")
                        end
                    end
                    break
                end
            end
        end
        self.cannonPanelBg:SetIsVisible(hasCannon)
        if hasCannon then
            -- Split upgrades: odd indices → left column, even → right column.
            local col1, col2 = {}, {}
            for i, s in ipairs(cannonUpgrades) do
                if i % 2 == 1 then table.insert(col1, s)
                else              table.insert(col2, s) end
            end
            self.cannonColLeft:SetText(table.concat(col1, "\n"))
            self.cannonColRight:SetText(table.concat(col2, "\n"))

            local rows = math.max(#col1, #col2, 0)
            local lh   = GUIScale(kProtoLineH)
            -- +1 for the CANNON header row
            local h    = (1 + rows) * lh + GUIScale(kProtoPanelPadY) * 2

            -- Dynamic width: each column is sized to ITS OWN widest label (not the
            -- widest label across both columns).  Sizing the left column to the
            -- right column's long labels was padding it out and pushing the short
            -- left-column text far from the panel's left edge (big left margin).
            local pad = GUIScale(kProtoPanelPadX)
            local function ColTextW(items)
                local wmax = 0
                for _, s in ipairs(items) do
                    wmax = math.max(wmax, ProtoTextWidth(self.cannonColLeft, s))
                end
                return wmax
            end
            local colWLeft  = ColTextW(col1) + pad
            local colWRight = ColTextW(col2) + pad
            local colGap    = pad
            local numCols   = (#col2 > 0) and 2 or 1
            local groupW    = colWLeft + (numCols == 2 and (colGap + colWRight) or 0)
            local headerW   = ProtoTextWidth(self.cannonHeaderText, "CANNON")
            local w         = math.max(groupW, headerW + pad) + pad
            self.cannonPanelBg:SetSize(Vector(w, h, 0))

            -- Position the column(s): Left-anchored, centre-aligned text, so each
            -- SetPosition is the column's horizontal centre.  Centre the group.
            local colY    = GUIScale(kProtoPanelPadY + kProtoLineH)
            local startX  = (w - groupW) * 0.5
            self.cannonColLeft:SetPosition(Vector(startX + colWLeft * 0.5, colY, 0))
            if numCols == 2 then
                self.cannonColRight:SetIsVisible(true)
                self.cannonColRight:SetPosition(Vector(startX + colWLeft + colGap + colWRight * 0.5, colY, 0))
            else
                self.cannonColRight:SetIsVisible(false)
            end

            self.cannonPanelBg:SetPosition(Vector(
                 sw * 0.5 - GUIScale(kCannonPanelRightInset) - w,
                 sh * 0.5 - GUIScale(kCannonPanelBottomInset) - h,
                0))
        end
    end

    -- Cannon Charge Shot: vertical bar on the right edge, fills bottom-to-top.
    if self.cannonChargeBg then
        local charging = false
        local frac     = 0
        if player and player.GetActiveWeapon then
            local w = player:GetActiveWeapon()
            if w and w:isa("Cannon") and w.GetCannonChargeFraction and w.cannonCharging then
                charging = true
                frac     = Clamp(w:GetCannonChargeFraction(), 0, 1)
            end
        end
        self.cannonChargeBg:SetIsVisible(charging)
        if charging then
            -- Middle/Center anchor: origin = screen centre.
            -- Bar sits just to the right of the crosshair's right ammo arc (~108 px).
            local kBarW_d       = 16    -- bar width (design px) — thin single-char column
            local kBarXOffset_d = 82    -- left edge X from screen centre (design px)
            local barW = GUIScale(kBarW_d)
            -- Bar height is now driven by the actual "CHARGE" text height (measured,
            -- not a fixed design constant) plus a small top/bottom margin equal to
            -- kTextTopPad - the same padding already used below to position the text
            -- from the top - so the bar hugs the text with a symmetric margin instead
            -- of leaving a large empty gap below it (as the old fixed 100px did).
            local kTextTopPad = GUIScale(4)
            local textH = self.cannonChargeText:GetTextHeight("C\nH\nA\nR\nG\nE") * self.cannonChargeText:GetScale().x
            local barH = textH + kTextTopPad * 2
            self.cannonChargeBg:SetSize(Vector(barW, barH, 0))
            self.cannonChargeBg:SetPosition(Vector(
                GUIScale(kBarXOffset_d),
                -barH * 0.5,
                0))
            -- Fill from bottom to top.
            local fillH = math.max(1, frac * barH)
            self.cannonChargeFill:SetSize(Vector(barW, fillH, 0))
            self.cannonChargeFill:SetPosition(Vector(0, barH - fillH, 0))
            -- Marine blue, brightening with charge; 75% opacity (max alpha 0.60).
            self.cannonChargeFill:SetColor(Color(
                0.15 + 0.25 * frac, 0.40 + 0.30 * frac, 1.0, 0.60))
            self.cannonChargeText:SetColor(Color(
                0.30 + 0.20 * frac, 0.55 + 0.20 * frac, 1.0, 1.0))
            -- Left/Top anchor: X measured from the bar's LEFT edge (barW*0.5 +
            -- Align_Center horizontally-centres each glyph on the bar), Y
            -- measured DOWN from the bar's TOP edge (a small pad, then
            -- Align_Min so the text starts there and grows downward - this is
            -- what makes "CHARGE" begin at the top of the bar instead of
            -- spilling out from the vertical middle).
            self.cannonChargeText:SetPosition(Vector(barW * 0.5, kTextTopPad, 0))
        end
    end

    -- ── Resupply Exo prompt ───────────────────────────────────────────────────
    -- Shown when this marine player is within use-range of a friendly Exo that
    -- has the Resupply upgrade.  Trace forward to find the targeted Exo.
    if self.resupplyPanel and player and not player:isa("Exo") then
        local showResupply = false
        local resupplyExo  = nil

        local eyePos  = player:GetEyePos()
        local lookDir = player:GetViewCoords().zAxis
        local trace   = Shared.TraceRay(eyePos, eyePos + lookDir * 3.0,
                            CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls,
                            EntityFilterOne(player))
        if trace.entity and trace.entity:isa("Exo")
           and trace.entity:GetTeamNumber() == player:GetTeamNumber()
           and trace.entity.GetHasPrototypeUpgrade
           and trace.entity:GetHasPrototypeUpgrade(kTechId.PrototypeResupply) then
            showResupply = true
            resupplyExo  = trace.entity
        end

        self.resupplyPanel:SetIsVisible(showResupply)
        if showResupply then
            local kIconSz   = GUIScale(48)
            local kPadX     = GUIScale(10)
            local kPadY     = GUIScale(10)
            local kLineH    = GUIScale(kProtoLineH)
            local kPanelH   = kIconSz + kPadY * 2
            local kTextX    = kIconSz + kPadX * 2

            -- Status text: cooldown/ready state plus the remaining charge count
            -- (out of 10), so marines can see how many resupplies are left.
            local charges  = resupplyExo.resupplyChargesRemaining or 0
            local chargesStr = string.format(" (%d/%d)", charges, kResupplyMaxCharges)
            local remaining = (resupplyExo.timeNextResupply or 0) - Shared.GetTime()
            local statusStr
            if charges <= 0 then
                statusStr = "EMPTY" .. chargesStr
                self.resupplyStatus:SetColor(Color(1.0, 0.3, 0.3, 1.0))
            elseif remaining <= 0 then
                statusStr = "READY" .. chargesStr
                self.resupplyStatus:SetColor(Color(0.3, 1.0, 0.3, 1.0))
            else
                statusStr = string.format("Cooldown: %.0fs", math.ceil(remaining)) .. chargesStr
                self.resupplyStatus:SetColor(Color(1.0, 0.5, 0.2, 1.0))
            end
            self.resupplyStatus:SetText(statusStr)

            -- Measure text widths for dynamic panel width
            local headerW = ProtoTextWidth(self.resupplyHeader, "RESUPPLY")
            local statusW = ProtoTextWidth(self.resupplyStatus, statusStr)
            local keyW    = ProtoTextWidth(self.resupplyKey, "[E]")
            local textBlockW = math.max(headerW, statusW) + kPadX + keyW
            local panelW  = kTextX + textBlockW + kPadX

            self.resupplyPanel:SetSize(Vector(panelW, kPanelH, 0))
            -- Position panel just above the crosshair centre.
            self.resupplyPanel:SetPosition(Vector(
                -panelW * 0.5,
                 sh * 0.5 - GUIScale(120) - kPanelH,
                0))

            -- Icon position (left side of panel)
            self.resupplyIcon:SetSize(Vector(kIconSz, kIconSz, 0))
            self.resupplyIcon:SetPosition(Vector(kPadX, kPadY, 0))

            -- Header text
            self.resupplyHeader:SetPosition(Vector(kTextX, kPadY, 0))

            -- Status text below header
            self.resupplyStatus:SetPosition(Vector(kTextX, kPadY + kLineH, 0))

            -- "[E]" key hint to the right of the header
            self.resupplyKey:SetPosition(Vector(kTextX + headerW + kPadX, kPadY, 0))
        end
    end

    -- Lifeform Scanner is handled by GUILifeformScanner (bottom-left panel).
end
