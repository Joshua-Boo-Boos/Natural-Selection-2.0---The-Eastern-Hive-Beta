-- CNBalance/GUI/GUILifeformScanner.lua
-- Exo Lifeform Scanner HUD panel (lower-left).
-- Shows all 7 lifeform types always; green if count > 0, red if count == 0.
-- "AWAITING SCAN" shown if no scan has been performed yet (exoHasScanned=false).

class 'GUILifeformScanner' (GUIScript)

local kPanelOffsetX = 24          -- px from left edge (pre-scale)
local kPanelOffsetY = 220         -- px from bottom edge (pre-scale)
local kLineH        = 20          -- px per content line (pre-scale)
local kPadX         = 12
local kPadY         = 10
local kColW         = 110         -- width of each column (pre-scale)
local kPanelW       = kColW * 2 + kPadX * 2   -- 244

local kFontName     = Fonts.kAgencyFB_Small
local kFontScale    = GUIScale(Vector(1, 1, 0))
local kColorHeader  = Color(0.4, 0.85, 1.0, 1.0)    -- cyan "BRAZIER INDUSTRIES"
local kColorHigh    = Color(0.3, 1.0, 0.3, 1.0)     -- green: count > 0
local kColorLow     = Color(1.0, 0.22, 0.22, 1.0)   -- red:   count == 0
local kColorAwait   = Color(0.9, 0.85, 0.4, 1.0)    -- yellow: awaiting scan
local kBgColor      = Color(0.05, 0.09, 0.12, 0.55)

-- 7 lifeforms arranged in two columns (left, right) for 4 display rows.
-- kLifeformGrid[i] = { name, field, col (0 or 1), row }
local kLifeformGrid = {
    { name = "SKULK",   field = "exoScanSkulk",   col = 0, row = 0 },
    { name = "GORGE",   field = "exoScanGorge",   col = 1, row = 0 },
    { name = "PROWLER", field = "exoScanProwler", col = 0, row = 1 },
    { name = "LERK",    field = "exoScanLerk",    col = 1, row = 1 },
    { name = "FADE",    field = "exoScanFade",    col = 0, row = 2 },
    { name = "VOKEX",   field = "exoScanVokex",   col = 1, row = 2 },
    { name = "ONOS",    field = "exoScanOnos",    col = 0, row = 3 },
}
local kNumDataRows  = 4   -- rows used for the 7 entries

function GUILifeformScanner:Initialize()

    self.background = GetGUIManager():CreateGraphicItem()
    self.background:SetAnchor(GUIItem.Left, GUIItem.Bottom)
    self.background:SetColor(kBgColor)
    self.background:SetLayer(kGUILayerPlayerHUDForeground2)
    self.background:SetIsVisible(false)

    -- ── Header text ──────────────────────────────────────────────────────────
    self.txtHeader = GetGUIManager():CreateTextItem()
    self.txtHeader:SetFontName(kFontName)
    self.txtHeader:SetScale(kFontScale)
    self.txtHeader:SetColor(kColorHeader)
    self.txtHeader:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.txtHeader:SetTextAlignmentX(GUIItem.Align_Min)
    self.txtHeader:SetTextAlignmentY(GUIItem.Align_Min)
    self.txtHeader:SetPosition(GUIScale(Vector(kPadX, kPadY, 0)))
    self.txtHeader:SetText("BRAZIER INDUSTRIES\nLIFEFORM SCANNER V2.5")
    self.background:AddChild(self.txtHeader)

    -- ── One text item per lifeform entry (for per-entry colour control) ──────
    self.lfItems = {}
    for i, lf in ipairs(kLifeformGrid) do
        local item = GetGUIManager():CreateTextItem()
        item:SetFontName(kFontName)
        item:SetScale(kFontScale)
        item:SetColor(kColorHigh)
        item:SetAnchor(GUIItem.Left, GUIItem.Top)
        item:SetTextAlignmentX(GUIItem.Align_Min)
        item:SetTextAlignmentY(GUIItem.Align_Min)
        local xOff = kPadX + lf.col * kColW
        local yOff = kPadY + kLineH * 2 + lf.row * kLineH   -- 2 header lines
        item:SetPosition(GUIScale(Vector(xOff, yOff, 0)))
        item:SetText("")
        self.background:AddChild(item)
        self.lfItems[i] = item
    end

    -- ── "AWAITING SCAN" fallback text (centred, shown before first scan) ────
    self.txtAwait = GetGUIManager():CreateTextItem()
    self.txtAwait:SetFontName(kFontName)
    self.txtAwait:SetScale(kFontScale)
    self.txtAwait:SetColor(kColorAwait)
    self.txtAwait:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.txtAwait:SetTextAlignmentX(GUIItem.Align_Center)
    self.txtAwait:SetTextAlignmentY(GUIItem.Align_Min)
    self.txtAwait:SetSize(GUIScale(Vector(kPanelW, 0, 0)))
    self.txtAwait:SetPosition(GUIScale(Vector(0, kPadY + kLineH * 2.5, 0)))
    self.txtAwait:SetText("AWAITING SCAN")
    self.background:AddChild(self.txtAwait)

    self.isVisible = false
end

function GUILifeformScanner:Uninitialize()
    if self.background then
        GUI.DestroyItem(self.background)
        self.background  = nil
        self.txtHeader   = nil
        self.txtAwait    = nil
        self.lfItems     = nil
    end
end

function GUILifeformScanner:GetIsVisible()
    return self.isVisible
end

function GUILifeformScanner:SetIsVisible(isVisible)
    self.isVisible = isVisible
    if self.background then
        self.background:SetIsVisible(isVisible)
    end
end

function GUILifeformScanner:Update(_deltaTime)

    local player = Client.GetLocalPlayer()
    local shouldShow = player
        and player:isa("Exo")
        and player.GetHasPrototypeUpgrade
        and player:GetHasPrototypeUpgrade(kTechId.PrototypeLifeformScanner)

    if not shouldShow then
        if self.isVisible then
            self.isVisible = false
            self.background:SetIsVisible(false)
        end
        return
    end

    local hasScanned = player.exoHasScanned == true

    -- Show/hide the correct sub-elements.
    self.txtAwait:SetIsVisible(not hasScanned)
    for i = 1, #self.lfItems do
        self.lfItems[i]:SetIsVisible(hasScanned)
    end

    if hasScanned then
        for i, lf in ipairs(kLifeformGrid) do
            local count = player[lf.field] or 0
            self.lfItems[i]:SetText(string.format("%s: %d", lf.name, count))
            self.lfItems[i]:SetColor(count > 0 and kColorHigh or kColorLow)
        end
    end

    -- Panel height: 2 header lines + data rows (or 1 line for await).
    local dataRows  = hasScanned and kNumDataRows or 1
    local h = (2 + dataRows) * GUIScale(kLineH) + GUIScale(kPadY) * 2
    self.background:SetSize(Vector(GUIScale(kPanelW), h, 0))
    self.background:SetPosition(GUIScale(Vector(kPanelOffsetX, -kPanelOffsetY, 0)))

    if not self.isVisible then
        self.isVisible = true
        self.background:SetIsVisible(true)
    end

end
