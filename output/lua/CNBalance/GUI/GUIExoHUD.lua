-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIExoHUD.lua =======
--
-- Post-hook on lua/Hud/Marine/GUIExoHUD.lua. Adds ONE small on-screen panel that
-- lists, for the exo the local player is currently piloting:
--
--     Brazier Industries Exosuit      <- title: larger, Marine-blue, centred
--     <left weapon> / <right weapon>   <- centred
--     <each equipped prototype upgrade, one per line, centred>
--
-- All lines are HORIZONTALLY CENTRED (each is its own single-line Align_Center item,
-- because NS2 only centres a single line - a multi-line "\n" string centres as a block
-- with the lines left-aligned inside it).
--
-- The box is BOTTOM-anchored and grows UPWARD as more upgrades are added, so its bottom
-- edge stays fixed just above the Exo fuel HUD element and the box can never clip it no
-- matter how many experimental-technology upgrades the exo has. Tune kExoInfoBottomInset
-- (distance from the screen bottom to the box's bottom edge) to sit it exactly above the
-- fuel element.
--
-- Ported from the original Prototype Lab overhaul's Exo info panel, trimmed to ONLY this
-- panel (the old file's Lifeform Scanner, Parasite Infection meter and Power Smash / Welder
-- pieces are removed features and are intentionally not ported).

local kScanFontName   = Fonts.kAgencyFB_Small
local kBodyFontScale  = GUIScale(Vector(1, 1, 0))
local kTitleFontScale = GUIScale(Vector(1.2, 1.2, 0))   -- title is slightly larger than the body

-- Marine-blue title colour (team blue). Fallback literal if the global is unavailable.
local kExoTitleColor  = kMarineTeamColorFloat or Color(0.302, 0.859, 1.0, 1)
local kExoBodyColor   = Color(0.85, 0.9, 0.95, 0.95)

-- Panel geometry (design px, GUIScale'd at use).
local kExoInfoLeftInset   = 40
local kExoInfoBottomInset = 300   -- box BOTTOM edge sits this many px above the screen bottom (grows upward). Tune to sit just above the Exo fuel HUD element.
local kExoInfoPadX        = 12
local kExoInfoPadY        = 10
local kExoInfoLineH       = 20    -- body line height
local kExoInfoTitleH      = 26    -- title line height (taller, matches the larger title font)
local kExoInfoMaxLines    = 10    -- body-line pool size (upgrades + combo line)

-- Friendly name for a prototype exo upgrade tech id.
local function ExoUpgradeName(techId)
    if     techId == kTechId.PrototypeExoArmour         then return "Armour Plating"
    elseif techId == kTechId.PrototypeExoExtraFuel      then return "Extra Fuel"
    elseif techId == kTechId.PrototypeEmergencyEjection then return "Emergency Ejection"
    elseif techId == kTechId.PrototypeSelfDestruct      then return "Self-Destruct"
    elseif techId == kTechId.PrototypeResupply          then return "Resupply"
    end
    return "?"
end

-- Friendly name for one of the two equipped exo-arm weapons.
local function ExoSlotDisplayName(entity)
    if not entity then return "?" end
    if entity:isa("Minigun") then
        return "Minigun"
    elseif entity:isa("Railgun") then
        -- Railgun class also backs the Flamethrower special arm (weaponMode).
        local mode = entity.GetWeaponMode and entity:GetWeaponMode()
                     or (kExoSpecialMode and kExoSpecialMode.Railgun)
        if kExoSpecialMode and mode == kExoSpecialMode.Flamethrower then
            return "Flamethrower"
        end
        return "Railgun"
    elseif entity:isa("Claw") then
        return "Claw"
    end
    return tostring(entity:GetClassName())
end

-- Create one centred single-line text item as a child of the box.
local function MakeCentredLine(self, fontScale, color)
    local item = GUIManager:CreateTextItem()
    item:SetFontName(kScanFontName)
    item:SetScale(fontScale)
    item:SetColor(color)
    -- Middle/Top anchor: x=0 is the box's horizontal centre; Align_Center then centres
    -- this single line about that centre.
    item:SetAnchor(GUIItem.Middle, GUIItem.Top)
    item:SetTextAlignmentX(GUIItem.Align_Center)
    item:SetTextAlignmentY(GUIItem.Align_Min)
    item:SetText("")
    self.exoInfoBg:AddChild(item)
    return item
end

local baseGUIExoHUDInitialize = GUIExoHUD.Initialize
function GUIExoHUD:Initialize()
    baseGUIExoHUDInitialize(self)

    self.exoInfoBg = GUIManager:CreateGraphicItem()
    self.exoInfoBg:SetAnchor(GUIItem.Left, GUIItem.Top)   -- explicit screen coords; bottom-anchored via Update math
    self.exoInfoBg:SetColor(Color(0.05, 0.09, 0.12, 0.65))
    self.exoInfoBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.exoInfoBg:SetIsVisible(false)
    self.background:AddChild(self.exoInfoBg)

    -- Title (larger, Marine-blue) + a pool of centred body lines.
    self.exoInfoTitle = MakeCentredLine(self, kTitleFontScale, kExoTitleColor)
    self.exoInfoLines = {}
    for i = 1, kExoInfoMaxLines do
        self.exoInfoLines[i] = MakeCentredLine(self, kBodyFontScale, kExoBodyColor)
    end
end

local baseGUIExoHUDUninitialize = GUIExoHUD.Uninitialize
function GUIExoHUD:Uninitialize()
    -- Destroy our panel (its child text items go with it) before the base tears down.
    if self.exoInfoBg then
        GUI.DestroyItem(self.exoInfoBg)
        self.exoInfoBg    = nil
        self.exoInfoTitle = nil
        self.exoInfoLines = {}
    end
    baseGUIExoHUDUninitialize(self)
end

local baseGUIExoHUDUpdate = GUIExoHUD.Update
function GUIExoHUD:Update(deltaTime)
    baseGUIExoHUDUpdate(self, deltaTime)
    self:UpdateExoInfoPanel(Client.GetLocalPlayer())
end

function GUIExoHUD:UpdateExoInfoPanel(player)

    if not self.exoInfoBg then return end

    local isExo = player and player:isa("Exo")
    self.exoInfoBg:SetIsVisible(isExo or false)
    if not isExo then return end

    -- ── Build the body lines (combo + upgrades) ──────────────────────────────
    local body = {}

    local holder = player.GetActiveWeapon and player:GetActiveWeapon()
    if holder and holder.isa and holder:isa("ExoWeaponHolder") then
        local leftEnt  = Shared.GetEntity(holder.leftWeaponId)
        local rightEnt = Shared.GetEntity(holder.rightWeaponId)
        table.insert(body, ExoSlotDisplayName(leftEnt) .. " / " .. ExoSlotDisplayName(rightEnt))
    end

    if player.GetHasPrototypeUpgrade and kPrototypeUpgradesForTrack then
        for _, techId in ipairs(kPrototypeUpgradesForTrack["exo"] or {}) do
            if player:GetHasPrototypeUpgrade(techId) then
                table.insert(body, ExoUpgradeName(techId))
            end
        end
    end

    -- ── Title ────────────────────────────────────────────────────────────────
    local title = "Brazier Industries Exosuit"
    self.exoInfoTitle:SetText(title)
    local maxW = self.exoInfoTitle:GetTextWidth(title) * self.exoInfoTitle:GetScale().x

    -- ── Body lines (centred) ─────────────────────────────────────────────────
    local numBody = math.min(#body, kExoInfoMaxLines)
    for i = 1, kExoInfoMaxLines do
        local item = self.exoInfoLines[i]
        if i <= numBody then
            item:SetText(body[i])
            item:SetIsVisible(true)
            local w = item:GetTextWidth(body[i]) * item:GetScale().x
            if w > maxW then maxW = w end
        else
            item:SetIsVisible(false)
        end
    end

    -- ── Box size + vertical layout of the lines ──────────────────────────────
    local padX = GUIScale(kExoInfoPadX)
    local padY = GUIScale(kExoInfoPadY)
    local titleH = GUIScale(kExoInfoTitleH)
    local lineH  = GUIScale(kExoInfoLineH)

    local w = maxW + padX * 2
    local h = padY + titleH + numBody * lineH + padY

    -- Title centred at box top; each body line below it.
    self.exoInfoTitle:SetPosition(Vector(0, padY, 0))
    for i = 1, numBody do
        self.exoInfoLines[i]:SetPosition(Vector(0, padY + titleH + (i - 1) * lineH, 0))
    end

    -- ── Position: left inset, BOTTOM edge fixed at kExoInfoBottomInset above the
    -- screen bottom; the box grows UPWARD so it never reaches down into the fuel HUD.
    local sh = Client.GetScreenHeight()
    local boxTopY = sh - GUIScale(kExoInfoBottomInset) - h
    self.exoInfoBg:SetSize(Vector(w, h, 0))
    self.exoInfoBg:SetPosition(Vector(GUIScale(kExoInfoLeftInset), boxTopY, 0))

    -- Publish the box's top edge so any panel that stacks above it can follow.
    _G.gExoUpgradePanelTopAbsY = boxTopY
end
