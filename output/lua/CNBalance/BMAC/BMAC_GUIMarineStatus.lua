--[[
    BMAC character: vanilla Marine status panel (bottom left). Post-hook on Hud/Marine/GUIMarineStatus.lua.

    A BMAC has only AP, so its HP/AP cluster (numbers, bars, borders, regen preview) is replaced by the
    Exo's own armour readout: the same panel art (Textures.kExosuit_View_Panel_Armor), font
    (MicrogrammaDMedExt) and colours as lua/GUIExoArmorDisplay.lua, built as an ordinary HUD item inside
    the status area so it keeps the panel's margin from the screen corner and its resolution scaling.

    When the viewed player stops being a BMAC, only what the HUD settings allow comes back - the base's
    own rules decide the rest:
      - HP/AP bars, borders and the status art only when the base hasn't hidden HP bars (hpBarHidden);
      - the regen preview is never forced on: its cache is reset so the base re-evaluates it;
      - minimal/hidden HUD hide other items or the whole panel and are never touched here.
]]

-- Exo panel art and text, as in lua/GUIExoArmorDisplay.lua (which loads GUIAssets the same way).
Script.Load("lua/GUIAssets.lua")
local kPanelTexture = Textures.kExosuit_View_Panel_Armor
local kPanelFont = Fonts.kMicrogrammaDMedExt_Small
-- The number uses the Marine HUD's own AP blue (as the normal AP number), not the Exo's paler tint.
local kNormalColor = GUIMarineStatus.kArmorBarColor
local kNearDeathColor = Color(0.8, 0.2, 0.2, 1)
local kNearDeathFraction = 0.3

-- Layout inside the 300x121 status background (unscaled units; items use the HUD's uniform scale).
-- The texture is square (256x256) and the Exo draws it unstretched, so it is drawn square here too;
-- stretching it flattened the shield/frame. Centred where the earlier (correctly placed) panel was.
local kPanelSide = 160
local kPanelSize = Vector(kPanelSide, kPanelSide, 0)
local kPanelPos = Vector(20 + (240 - kPanelSide) / 2, 6 + (108 - kPanelSide) / 2, 0)
-- Everything in the Exo view is in 256 px units at scale 1 (number 18,28 px right/down of centre);
-- scale the same way so the number keeps the Exo's size and place relative to the shield.
local kPanelRatio = kPanelSide / 256
local kTextOffset = Vector(18 * kPanelRatio, 28 * kPanelRatio, 0)
local kTextScale = kPanelRatio

local function GetViewedPlayerIsBMAC()
    local player = Client.GetLocalPlayer()
    return player ~= nil and player:isa("Marine") and player.GetIgnoreHealth ~= nil and player:GetIgnoreHealth() == true
end

local function LayoutBMACPanel(self)
    local scale = self.scale or 1
    self.bmacPanel:SetUniformScale(scale)
    self.bmacPanel:SetSize(kPanelSize)
    self.bmacPanel:SetPosition(kPanelPos)

    self.bmacText:SetUniformScale(scale)
    -- Same scaling as the panel (uniform HUD scale only), so text and art stay in proportion.
    self.bmacText:SetScale(Vector(kTextScale, kTextScale, 0))
    self.bmacText:SetPosition(kTextOffset)
    self.bmacText:SetFontName(kPanelFont)
    GUIMakeFontScale(self.bmacText)
end

local function CreateBMACPanel(self)
    local panel = self.script:CreateAnimatedGraphicItem()
    panel:SetAnchor(GUIItem.Left, GUIItem.Top)
    panel:SetTexture(kPanelTexture)
    panel:SetTexturePixelCoordinates(0, 0, 256, 256)
    panel:SetBlendTechnique(GUIItem.Add)
    panel:SetLayer(self.hudLayer + 1)
    panel:SetIsVisible(false)
    panel:AddAsChildTo(self.statusbackground)

    local text = self.script:CreateAnimatedTextItem()
    text:SetFontName(kPanelFont)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Center)
    text:SetAnchor(GUIItem.Middle, GUIItem.Center)
    text:SetLayer(self.hudLayer + 2)
    text:SetColor(kNormalColor)
    panel:AddChild(text)

    self.bmacPanel = panel
    self.bmacText = text
    LayoutBMACPanel(self)
end

local baseReset = GUIMarineStatus.Reset
function GUIMarineStatus:Reset(scale)
    baseReset(self, scale)
    if self.bmacPanel then
        LayoutBMACPanel(self)
    end
end

-- Items the BMAC panel replaces.
local function SetVanillaClusterVisible(self, visible)
    self.healthText:SetIsVisible(visible)
    self.armorText:SetIsVisible(visible)
    local bars = visible and not self.hpBarHidden
    self.healthBar:SetIsVisible(bars)
    self.healthBorder:SetIsVisible(bars)
    self.armorBar:SetIsVisible(bars)
    self.armorBorder:SetIsVisible(bars)
    if not visible then
        self.regenBar:SetIsVisible(false)
    end
end

local baseUpdate = GUIMarineStatus.Update
function GUIMarineStatus:Update(deltaTime, parameters)
    baseUpdate(self, deltaTime, parameters)

    local isBMAC = GetViewedPlayerIsBMAC()

    if isBMAC then

        if not self.bmacPanel then
            CreateBMACPanel(self)
        end

        if not self.bmacHidHealth then
            SetVanillaClusterVisible(self, false)
            self.statusbackground:SetTexture("ui/transparent.dds")
            self.bmacHidHealth = true
        end

        local armor = parameters and parameters[3] or 0
        local maxArmor = parameters and parameters[4] or 0
        local armorAmount = math.ceil(armor)
        if armorAmount ~= self.bmacLastArmor then
            self.bmacText:SetText(tostring(armorAmount))
            self.bmacLastArmor = armorAmount
        end
        local low = maxArmor > 0 and armor / maxArmor < kNearDeathFraction
        self.bmacText:SetColor(low and kNearDeathColor or kNormalColor)
        self.bmacPanel:SetIsVisible(true)

    elseif self.bmacHidHealth then

        self.bmacHidHealth = false
        if self.bmacPanel then
            self.bmacPanel:SetIsVisible(false)
        end
        SetVanillaClusterVisible(self, true)
        if not self.hpBarHidden then
            self.statusbackground:SetTexture(GUIMarineStatus.kStatusTexture)
        end
        -- Force the base to redraw health/armour and re-decide the regen preview next update.
        self.lastHealth = -1
        self.lastArmor = -1
        self.lastRegenHealth = -1
        self.bmacLastArmor = nil

    end
end
