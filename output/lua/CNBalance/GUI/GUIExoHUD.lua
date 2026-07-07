-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIExoHUD.lua =======
--
-- Post-hook on lua/Hud/Marine/GUIExoHUD.lua.
-- Adds the Lifeform Scanner panel to the Exo HUD, positioned directly above
-- the Jetpack upgrade panel (whose top edge is published each frame by
-- GUIMarineHUD into _G.gJetpackPanelTopAbsY in absolute screen coords).
--
-- Panel only shows when the local player is an Exo with the
-- PrototypeLifeformScanner upgrade.  Scan data (7 lifeform counts) is
-- supplied by Exo.lua's server-side UpdateLifeformScan, which writes to
-- private networked vars synced to the owning client.
-- ============================================================

-- Styling constants.
local kScanBgColor     = Color(0.05, 0.09, 0.12, 0.55)
local kScanHeaderColor = Color(0.4,  0.85, 1.0,  1.0)
local kScanHighColor   = Color(0.9,  0.2,  0.2,  1.0)   -- red         (count >= 1)
local kScanLowColor    = Color(0.35, 0.62, 1.0,  1.0)   -- marine blue (count == 0)
local kScanFontName    = Fonts.kAgencyFB_Small
local kScanFontScale   = GUIScale(Vector(1, 1, 0))

-- Layout (unscaled px).
local kScanPadX        = 12
local kScanPadY        = 10
local kScanLineH       = 20
local kScanColW        = 110   -- width of each of the two lifeform columns
local kScanPanelW      = kScanColW * 2 + kScanPadX * 2   -- 244
local kScanHeaderRows  = 2     -- "Brazier Industries" line + "Lifeform Scanner v2.5" line
local kScanDataRows    = 4
local kScanPanelH      = kScanPadY * 2 + kScanLineH * (kScanHeaderRows + kScanDataRows)
local kScanLeftInset   = 300   -- px from screen left
local kScanGapBelowPanel = 8   -- px gap between scanner bottom and jetpack panel top

-- Lifeform grid: col 0 = left column, col 1 = right column.
local kScanLifeforms = {
    { key = "exoScanSkulk",   name = "SKULK",   col = 0, row = 0 },
    { key = "exoScanGorge",   name = "GORGE",   col = 1, row = 0 },
    { key = "exoScanProwler", name = "PROWLER", col = 0, row = 1 },
    { key = "exoScanLerk",    name = "LERK",    col = 1, row = 1 },
    { key = "exoScanFade",    name = "FADE",    col = 0, row = 2 },
    { key = "exoScanVokex",   name = "VOKEX",   col = 1, row = 2 },
    { key = "exoScanOnos",    name = "ONOS",    col = 0, row = 3 },
}

-- Skulk Parasite Infection meter, carried onto the Exo when the pilot entered
-- while infected (Exo.lua's CopyPlayerDataFrom/OnProcessMove). Same visual
-- layout/constants as GUIMarineHUD.lua's Infection box; positioned the same
-- way the Lifeform Scanner panel above already stacks off the Jetpack panel's
-- published top-Y, since this file uses absolute (not Middle/Center-relative)
-- positioning throughout.
local kInfBarW_d           = 160
local kInfRowH_d           = 18
local kInfLeftInset        = 300   -- matches kScanLeftInset, same column as the Scanner panel
local kInfGap_d            = 10
local kInfTextShiftLeft_d  = 3     -- design px, nudges the (already-centered) text left slightly
local kInfectionDoTSeconds = 5

-- ── Initialize ───────────────────────────────────────────────────────────────

local baseGUIExoHUDInitialize = GUIExoHUD.Initialize
function GUIExoHUD:Initialize()
    baseGUIExoHUDInitialize(self)

    -- Background panel (absolute child of self.background).
    self.scanBg = GUIManager:CreateGraphicItem()
    self.scanBg:SetColor(kScanBgColor)
    self.scanBg:SetSize(GUIScale(Vector(kScanPanelW, kScanPanelH, 0)))
    self.scanBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.scanBg:SetIsVisible(false)
    self.background:AddChild(self.scanBg)

    -- Two-line header centred at the top of the panel.
    -- Line 1: "Brazier Industries"  Line 2: "Lifeform Scanner v2.5"
    self.scanHeader = GUIManager:CreateTextItem()
    self.scanHeader:SetFontName(kScanFontName)
    self.scanHeader:SetScale(kScanFontScale)
    self.scanHeader:SetColor(kScanHeaderColor)
    self.scanHeader:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.scanHeader:SetTextAlignmentX(GUIItem.Align_Center)
    self.scanHeader:SetTextAlignmentY(GUIItem.Align_Min)
    self.scanHeader:SetSize(GUIScale(Vector(kScanPanelW, 0, 0)))
    self.scanHeader:SetPosition(GUIScale(Vector(0, kScanPadY, 0)))
    self.scanHeader:SetText("Brazier Industries\nLifeform Scanner v2.5")
    self.scanBg:AddChild(self.scanHeader)

    -- "AWAITING SCAN" placeholder (below the 2-line header).
    self.scanAwaiting = GUIManager:CreateTextItem()
    self.scanAwaiting:SetFontName(kScanFontName)
    self.scanAwaiting:SetScale(kScanFontScale)
    self.scanAwaiting:SetColor(kScanHeaderColor)
    self.scanAwaiting:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.scanAwaiting:SetTextAlignmentX(GUIItem.Align_Center)
    self.scanAwaiting:SetTextAlignmentY(GUIItem.Align_Min)
    self.scanAwaiting:SetSize(GUIScale(Vector(kScanPanelW, 0, 0)))
    self.scanAwaiting:SetPosition(GUIScale(Vector(0, kScanPadY + kScanLineH * kScanHeaderRows, 0)))
    self.scanAwaiting:SetText("AWAITING SCAN")
    self.scanBg:AddChild(self.scanAwaiting)

    -- Two text items per lifeform (name + value), not one combined string -
    -- a single "NAME: count" string centred as one unit means different-length
    -- names ("SKULK" vs "PROWLER") never line up between rows. Splitting into
    -- a left-aligned name (fixed at the column's left edge) and a
    -- right-aligned value (fixed at the column's right edge) gives real
    -- table-column alignment, matching how a properly-aligned data grid reads.
    self.scanItems = {}
    for i, lf in ipairs(kScanLifeforms) do
        local colX = kScanPadX + lf.col * kScanColW
        local rowY = kScanPadY + kScanLineH * (kScanHeaderRows + lf.row)

        local nameItem = GUIManager:CreateTextItem()
        nameItem:SetFontName(kScanFontName)
        nameItem:SetScale(kScanFontScale)
        nameItem:SetColor(kScanHighColor)
        nameItem:SetAnchor(GUIItem.Left, GUIItem.Top)
        nameItem:SetTextAlignmentX(GUIItem.Align_Min)
        nameItem:SetTextAlignmentY(GUIItem.Align_Min)
        nameItem:SetSize(GUIScale(Vector(kScanColW, 0, 0)))
        nameItem:SetPosition(GUIScale(Vector(colX, rowY, 0)))
        nameItem:SetText(lf.name .. ":")
        nameItem:SetIsVisible(false)
        self.scanBg:AddChild(nameItem)

        local valueItem = GUIManager:CreateTextItem()
        valueItem:SetFontName(kScanFontName)
        valueItem:SetScale(kScanFontScale)
        valueItem:SetColor(kScanHighColor)
        valueItem:SetAnchor(GUIItem.Left, GUIItem.Top)
        valueItem:SetTextAlignmentX(GUIItem.Align_Max)
        valueItem:SetTextAlignmentY(GUIItem.Align_Min)
        valueItem:SetSize(GUIScale(Vector(kScanColW, 0, 0)))
        -- Align_Max right-aligns the count to its position.x, so position it at
        -- the column's RIGHT edge (minus a small pad), not its left edge - at
        -- the left edge the count rendered just before the name ("0SKULK:").
        valueItem:SetPosition(GUIScale(Vector(colX + kScanColW - 14, rowY, 0)))
        valueItem:SetText("")
        valueItem:SetIsVisible(false)
        self.scanBg:AddChild(valueItem)

        self.scanItems[i] = { nameItem = nameItem, valueItem = valueItem, key = lf.key, name = lf.name }
    end

    -- Skulk Parasite Infection meter (see constants above). Absolute-child of
    -- self.background, same as scanBg - Left/Top positioning throughout.
    self.infectionBg = GUIManager:CreateGraphicItem()
    self.infectionBg:SetColor(Color(0.02, 0.06, 0.18, 0.85))
    self.infectionBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.infectionBg:SetIsVisible(false)
    self.background:AddChild(self.infectionBg)

    self.infectionFill = GUIManager:CreateGraphicItem()
    self.infectionFill:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.infectionFill:SetColor(Color(0.20, 0.50, 1.0, 0.40))
    self.infectionBg:AddChild(self.infectionFill)

    -- Left/Top anchor with an explicit position.x computed each frame from
    -- the text's own rendered width (see UpdateInfectionMeter below) - a
    -- Middle-anchor/midpoint-position attempt did not actually center
    -- reliably in testing (matches the same fix applied in GUIMarineHUD.lua).
    self.infectionLabelText = GUIManager:CreateTextItem()
    self.infectionLabelText:SetFontName(kScanFontName)
    self.infectionLabelText:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.infectionLabelText:SetTextAlignmentX(GUIItem.Align_Min)
    self.infectionLabelText:SetTextAlignmentY(GUIItem.Align_Center)
    self.infectionLabelText:SetScale(GUIScale(Vector(0.7, 0.7, 0)))
    self.infectionLabelText:SetColor(Color(0.35, 0.62, 1.0, 1.0))
    self.infectionLabelText:SetText("Infection")
    self.infectionBg:AddChild(self.infectionLabelText)

    self.infectionPercentText = GUIManager:CreateTextItem()
    self.infectionPercentText:SetFontName(kScanFontName)
    self.infectionPercentText:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.infectionPercentText:SetTextAlignmentX(GUIItem.Align_Min)
    self.infectionPercentText:SetTextAlignmentY(GUIItem.Align_Center)
    self.infectionPercentText:SetScale(GUIScale(Vector(0.7, 0.7, 0)))
    self.infectionPercentText:SetColor(Color(0.35, 0.62, 1.0, 1.0))
    self.infectionPercentText:SetText("0.0%")
    self.infectionBg:AddChild(self.infectionPercentText)
end

-- ── Uninitialize ─────────────────────────────────────────────────────────────

local baseGUIExoHUDUninitialize = GUIExoHUD.Uninitialize
function GUIExoHUD:Uninitialize()
    -- scanBg/infectionBg are children of self.background, destroyed by the base Uninitialize.
    self.scanBg       = nil
    self.scanHeader   = nil
    self.scanAwaiting = nil
    self.scanItems    = nil
    self.infectionBg          = nil
    self.infectionFill        = nil
    self.infectionLabelText   = nil
    self.infectionPercentText = nil
    baseGUIExoHUDUninitialize(self)
end

-- ── Update ───────────────────────────────────────────────────────────────────

local baseGUIExoHUDUpdate = GUIExoHUD.Update
function GUIExoHUD:Update(deltaTime)
    baseGUIExoHUDUpdate(self, deltaTime)

    if not self.scanBg then return end

    local player      = Client.GetLocalPlayer()
    local showScanner = player
        and player:isa("Exo")
        and player.GetHasPrototypeUpgrade
        and player:GetHasPrototypeUpgrade(kTechId.PrototypeLifeformScanner)

    self.scanBg:SetIsVisible(showScanner == true)

    if not showScanner then return end

    -- Position the panel directly above the jetpack upgrade panel.
    local sh      = Client.GetScreenHeight()
    local panelH  = GUIScale(kScanPanelH)
    local panelW  = GUIScale(kScanPanelW)
    local jetTopY = _G.gJetpackPanelTopAbsY or (sh - GUIScale(48 + 120))
    local posY    = jetTopY - GUIScale(kScanGapBelowPanel) - panelH
    local posX    = GUIScale(kScanLeftInset)

    self.scanBg:SetSize(Vector(panelW, panelH, 0))
    self.scanBg:SetPosition(Vector(posX, posY, 0))
    self.scanHeader:SetSize(Vector(panelW, 0, 0))

    local hasScanned = player.exoHasScanned == true
    self.scanAwaiting:SetIsVisible(not hasScanned)

    for _, entry in ipairs(self.scanItems) do
        local count = hasScanned and (player[entry.key] or 0) or 0
        local color = count > 0 and kScanHighColor or kScanLowColor
        entry.nameItem:SetIsVisible(hasScanned)
        entry.nameItem:SetColor(color)
        entry.valueItem:SetIsVisible(hasScanned)
        entry.valueItem:SetText(tostring(count))
        entry.valueItem:SetColor(color)
    end

    self:UpdateInfectionMeter(player, showScanner, posY)
end

-- ── Skulk Parasite Infection meter ──────────────────────────────────────────
-- Only relevant if the pilot entered the Exo already carrying Infection state
-- (Exo.lua's CopyPlayerDataFrom/OnProcessMove) - an Exo can never gain NEW
-- Parasite hits itself. Stacks above the Scanner panel if it's showing (to
-- avoid overlapping it), otherwise directly above the Jetpack reference Y,
-- same pattern the Scanner panel itself uses relative to the Jetpack panel.
function GUIExoHUD:UpdateInfectionMeter(player, scannerShowing, scannerTopY)

    if not self.infectionBg then return end

    local showInfection = player and player:isa("Exo") and (player.infectionHitCount or 0) > 0
    self.infectionBg:SetIsVisible(showInfection or false)
    if not showInfection then return end

    local sh = Client.GetScreenHeight()

    local barW   = GUIScale(kInfBarW_d)
    local rowH   = GUIScale(kInfRowH_d)
    local gap    = GUIScale(kInfGap_d)
    local totalH = rowH * 2

    local jetTopY  = _G.gJetpackPanelTopAbsY or (sh - GUIScale(48 + 120))
    local aboveY   = (scannerShowing and scannerTopY or jetTopY) - gap
    local posY     = aboveY - totalH
    local posX     = GUIScale(kInfLeftInset)

    self.infectionBg:SetSize(Vector(barW, totalH, 0))
    self.infectionBg:SetPosition(Vector(posX, posY, 0))

    -- Same continuous-decay animation math as GUIMarineHUD.lua's Infection
    -- meter - must stay in sync with Exo.lua's kInfectionDoTSeconds.
    local displayedCount = player.infectionHitCount or 0
    if player.infectionWasFullyInfected then
        local elapsed = Shared.GetTime() - (player.infectionLastHitTime or 0)
        displayedCount = math.max(0, 3 - math.min(elapsed, kInfectionDoTSeconds) / kInfectionDoTSeconds * 3)
    end

    local infected   = player.infectionWasFullyInfected
    local themeColor = infected and Color(1.0, 0.45, 0.1, 1.0) or Color(0.35, 0.62, 1.0, 1.0)

    -- Fill occupies ONLY the bottom row (behind the percentage text), never
    -- the top label row.
    local frac  = Clamp(displayedCount / 3, 0, 1)
    local fillW = math.max(1, frac * barW)
    self.infectionFill:SetSize(Vector(fillW, rowH, 0))
    self.infectionFill:SetPosition(Vector(0, rowH, 0))
    self.infectionFill:SetColor(infected
        and Color(1.0, 0.45, 0.1, 0.40)
        or  Color(0.20, 0.50, 1.0, 0.40))

    local labelStr   = infected and "Infected!" or "Infection"
    local percentStr = string.format("%.1f%%", frac * 100)

    local textShiftLeft = GUIScale(kInfTextShiftLeft_d)

    -- Align_Center on the Y axis centres text vertically AROUND position.y
    -- (not within a [0,rowH] box below it) - position.y must be each row's
    -- own midpoint (rowH*0.5 / rowH*1.5), not its top edge, matching the fix
    -- applied in GUIMarineHUD.lua.
    self.infectionLabelText:SetText(labelStr)
    self.infectionLabelText:SetColor(themeColor)
    self.infectionLabelText:SetSize(Vector(0, rowH, 0))
    self.infectionLabelText:SetPosition(Vector(
        (barW - self.infectionLabelText:GetTextWidth(labelStr) * self.infectionLabelText:GetScale().x) * 0.5 - textShiftLeft,
        rowH * 0.5, 0))

    self.infectionPercentText:SetText(percentStr)
    self.infectionPercentText:SetColor(themeColor)
    self.infectionPercentText:SetSize(Vector(0, rowH, 0))
    self.infectionPercentText:SetPosition(Vector(
        (barW - self.infectionPercentText:GetTextWidth(percentStr) * self.infectionPercentText:GetScale().x) * 0.5 - textShiftLeft,
        rowH * 1.5, 0))

    -- Same Lerk-poison screen pulse reuse as GUIMarineHUD.lua, independent of
    -- the vanilla poisoned field.
    if infected then
        local feedbackUI = ClientUI.GetScript("GUIPoisonedFeedback")
        if feedbackUI and player:GetIsAlive() and not feedbackUI:GetIsAnimating() then
            feedbackUI:TriggerPoisonEffect()
        end
    end
end
