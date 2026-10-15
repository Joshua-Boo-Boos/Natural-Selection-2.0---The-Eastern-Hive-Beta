--[[
    BMAC character: the per-round Marine choice window (client). Created by BMAC_RoundChoice_Client.lua.

    Window 1 - "Choose Your Marine": Biological / BMAC / Random, side by side, each with a picture (the game's own
               Thunderdome reward art) and a button underneath.
                 Biological or BMAC -> the choice is sent at once (so a body type with no skin still counts), then window 2.
                 Random             -> sent, window closes (the server picks the body and a skin at round start).
    Window 2 - "Choose Your <Biological / BMAC> Skin": a grid of the skins of that body the player owns (the default
               human skin and the base B.M.A.C. are always there) plus "Random", then Back / Confirm.

    Anything not finished before the round starts is random (server side, BMAC_Shared.lua ResolveRoundChoice). Escape
    closes the window (the same as not finishing it). Only a network message is sent; no network variable.
]]

Script.Load("lua/GUIScript.lua")
Script.Load("lua/GUIAssets.lua")

class 'GUIBMACRoundChoice' (GUIScript)

local kBiologicalImage = PrecacheAsset("ui/thunderdome_rewards_icons/marines_eliteassault.dds")
local kBMACImage = PrecacheAsset("ui/thunderdome_rewards_icons/bmac_chroma.dds")

local kTitleFont = Fonts.kAgencyFB_Huge
local kFont = Fonts.kAgencyFB_Large
local kSmallFont = Fonts.kAgencyFB_Medium

local kDimColor = Color(0, 0, 0, 0.55)
local kPanelColor = Color(0.03, 0.07, 0.12, 0.95)
local kTileColor = Color(0.09, 0.17, 0.27, 1)
local kTileHoverColor = Color(0.16, 0.30, 0.46, 1)
local kTileSelectedColor = Color(0.13, 0.52, 0.78, 1)
local kTextColor = Color(0.86, 0.94, 1, 1)
local kSubTextColor = Color(0.6, 0.72, 0.82, 1)

-- Unscaled layout (GUIScale applied when building).
local kPage1TileSize = Vector(300, 400, 0)
local kPage1ImageSize = Vector(280, 280, 0)
local kPage1Gap = 36
local kGridTileSize = Vector(230, 58, 0)
local kGridGap = 12
local kGridColumns = 4
local kBottomButtonSize = Vector(200, 58, 0)
local kMargin = 40
local kTitleHeight = 90

-- "Butler B.M.A.C. " -> "Butler B.M.A.C."; the first letter of every word upper case, the rest left as written.
local function TitleCase(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return (text:gsub("(%S)(%S*)", function(first, rest) return first:upper() .. rest end))
end

local function GetVariantName(variant)
    local data = kMarineVariantsData and kMarineVariantsData[variant]
    return TitleCase(data and data.displayName or tostring(variant))
end

local function SendChoice(bodyType, variant)
    Client.SendNetworkMessage("BMACRoundChoice", { bodyType = bodyType, variant = variant or 0 }, true)
end

local function CreateText(parent, text, font, color, position)
    local item = GUIManager:CreateTextItem()
    item:SetFontName(font)
    item:SetScale(GetScaledVector())
    GUIMakeFontScale(item)
    item:SetTextAlignmentX(GUIItem.Align_Center)
    item:SetTextAlignmentY(GUIItem.Align_Center)
    item:SetAnchor(GUIItem.Left, GUIItem.Top)
    item:SetPosition(position)
    item:SetColor(color)
    item:SetText(text)
    item:SetInheritsParentAlpha(false)
    parent:AddChild(item)
    return item
end

function GUIBMACRoundChoice:Initialize()
    GUIScript.Initialize(self)

    self.closed = false
    self.buttons = {}

    -- Full-screen dim behind the window.
    self.background = GUIManager:CreateGraphicItem()
    self.background:SetSize(Vector(Client.GetScreenWidth(), Client.GetScreenHeight(), 0))
    self.background:SetColor(kDimColor)
    self.background:SetLayer(kGUILayerMainMenu or 20)

    self:BuildChooseBody()

    MouseTracker_SetIsVisible(true, nil, true)
end

function GUIBMACRoundChoice:Uninitialize()
    if self.background then
        GUI.DestroyItem(self.background)
        self.background = nil
    end
    MouseTracker_SetIsVisible(false)
end

-- A centred panel of the given unscaled size; replaces the previous page.
function GUIBMACRoundChoice:NewPanel(size)
    if self.panel then
        GUI.DestroyItem(self.panel)
    end
    self.buttons = {}
    local scaled = GUIScale(size)
    self.panel = GUIManager:CreateGraphicItem()
    self.panel:SetSize(scaled)
    self.panel:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.panel:SetPosition(-scaled * 0.5)
    self.panel:SetColor(kPanelColor)
    self.background:AddChild(self.panel)
    return self.panel
end

-- A clickable tile at unscaled (x, y) inside the panel.
function GUIBMACRoundChoice:AddButton(x, y, size, onClick)
    local tile = GUIManager:CreateGraphicItem()
    tile:SetSize(GUIScale(size))
    tile:SetPosition(GUIScale(Vector(x, y, 0)))
    tile:SetColor(kTileColor)
    self.panel:AddChild(tile)
    local button = { item = tile, onClick = onClick }
    self.buttons[#self.buttons + 1] = button
    return tile, button
end

-- Window 1: Biological / BMAC / Random.
function GUIBMACRoundChoice:BuildChooseBody()
    local width = kMargin * 2 + kPage1TileSize.x * 3 + kPage1Gap * 2
    local height = kTitleHeight + kPage1TileSize.y + kMargin * 2
    local panel = self:NewPanel(Vector(width, height, 0))

    CreateText(panel, "Choose Your Marine", kTitleFont, kTextColor, GUIScale(Vector(width * 0.5, kTitleHeight * 0.5, 0)))
    CreateText(panel, "This Round Only - Random If Not Chosen Before The Round Starts", kSmallFont, kSubTextColor,
               GUIScale(Vector(width * 0.5, kTitleHeight - 10, 0)))

    local options =
    {
        { label = "Biological", image = kBiologicalImage, bodyType = kBMACChoiceBiological },
        { label = "BMAC", image = kBMACImage, bodyType = kBMACChoiceBMAC },
        { label = "Random", bodyType = kBMACChoiceRandom },
    }
    for index, option in ipairs(options) do
        local x = kMargin + (index - 1) * (kPage1TileSize.x + kPage1Gap)
        local y = kTitleHeight + kMargin * 0.5
        local tile = self:AddButton(x, y, kPage1TileSize, function()
            SendChoice(option.bodyType, 0)
            if option.bodyType == kBMACChoiceRandom then
                self.closed = true
            else
                self:BuildChooseSkin(option.bodyType)
            end
        end)
        local imageOffset = (kPage1TileSize.x - kPage1ImageSize.x) * 0.5
        if option.image then
            local image = GUIManager:CreateGraphicItem()
            image:SetTexture(option.image)
            image:SetSize(GUIScale(kPage1ImageSize))
            image:SetPosition(GUIScale(Vector(imageOffset, imageOffset, 0)))
            tile:AddChild(image)
        else
            CreateText(tile, "?", kTitleFont, kTextColor,
                       GUIScale(Vector(kPage1TileSize.x * 0.5, imageOffset + kPage1ImageSize.y * 0.5, 0)))
        end
        CreateText(tile, option.label, kFont, kTextColor,
                   GUIScale(Vector(kPage1TileSize.x * 0.5, kPage1TileSize.y - (kPage1TileSize.y - kPage1ImageSize.y - imageOffset) * 0.5, 0)))
    end
end

-- The panel is never narrower than this (unscaled), so the title and Back / Confirm always fit.
local kSkinPanelMinWidth = 640

-- Window 2: the owned skins of one body; Random only when there is more than one; Back / Confirm.
function GUIBMACRoundChoice:BuildChooseSkin(bodyType)
    local robotic = bodyType == kBMACChoiceBMAC
    local variants = BMAC_GetChoosableVariants(robotic, function(variant)
        return GetHasVariant(kMarineVariantsData, variant)
    end)

    -- (2026-10-15) "Random" only makes sense with more than one skin to pick from.
    local entries = {}
    if #variants > 1 then
        entries[1] = { label = "Random", variant = 0 }
    end
    for _, variant in ipairs(variants) do
        entries[#entries + 1] = { label = GetVariantName(variant), variant = variant }
    end

    -- Sized to the tiles actually shown: as many columns as needed (up to kGridColumns), as many rows as needed.
    local columns = math.max(1, math.min(kGridColumns, #entries))
    local rows = math.max(1, math.ceil(#entries / kGridColumns))
    local gridWidth = columns * kGridTileSize.x + (columns - 1) * kGridGap
    local width = math.max(kSkinPanelMinWidth, kMargin * 2 + gridWidth)
    local gridLeft = (width - gridWidth) * 0.5
    local height = kTitleHeight + rows * (kGridTileSize.y + kGridGap) + kMargin + kBottomButtonSize.y + kMargin
    local panel = self:NewPanel(Vector(width, height, 0))

    CreateText(panel, robotic and "Choose Your BMAC Skin" or "Choose Your Biological Skin", kTitleFont, kTextColor,
               GUIScale(Vector(width * 0.5, kTitleHeight * 0.5, 0)))
    CreateText(panel, #entries > 1 and "Only Skins You Have Are Shown - Random If Not Confirmed" or "Only Skins You Have Are Shown",
               kSmallFont, kSubTextColor, GUIScale(Vector(width * 0.5, kTitleHeight - 10, 0)))

    -- With a Random tile it starts selected; with a single skin, that skin is.
    self.selectedVariant = entries[1] and entries[1].variant or 0
    for index, entry in ipairs(entries) do
        local column = (index - 1) % kGridColumns
        local row = math.floor((index - 1) / kGridColumns)
        local x = gridLeft + column * (kGridTileSize.x + kGridGap)
        local y = kTitleHeight + row * (kGridTileSize.y + kGridGap)
        local tile, button = self:AddButton(x, y, kGridTileSize, function()
            self.selectedVariant = entry.variant
        end)
        button.variant = entry.variant     -- marks a skin tile (selection highlight)
        CreateText(tile, entry.label, kSmallFont, kTextColor, GUIScale(kGridTileSize * 0.5))
    end

    local buttonsY = height - kMargin - kBottomButtonSize.y
    local back = self:AddButton(kMargin, buttonsY, kBottomButtonSize, function()
        self:BuildChooseBody()
    end)
    CreateText(back, "Back", kFont, kTextColor, GUIScale(kBottomButtonSize * 0.5))

    local confirm = self:AddButton(width - kMargin - kBottomButtonSize.x, buttonsY, kBottomButtonSize, function()
        SendChoice(bodyType, self.selectedVariant)
        self.closed = true
    end)
    CreateText(confirm, "Confirm", kFont, kTextColor, GUIScale(kBottomButtonSize * 0.5))
end

function GUIBMACRoundChoice:Update(deltaTime)
    if self.closed or not self.panel then
        return
    end
    local mouseX, mouseY = Client.GetCursorPosScreen()
    for _, button in ipairs(self.buttons) do
        local item = button.item
        local color = kTileColor
        if button.variant ~= nil and button.variant == self.selectedVariant then
            color = kTileSelectedColor
        elseif GUIItemContainsPoint(item, mouseX, mouseY) then
            color = kTileHoverColor
        end
        item:SetColor(color)
    end
end

function GUIBMACRoundChoice:SendKeyEvent(key, down)
    if self.closed then
        return false
    end
    if key == InputKey.Escape and down then
        self.closed = true
        return true
    end
    if key == InputKey.MouseButton0 then
        if down then
            local mouseX, mouseY = Client.GetCursorPosScreen()
            for _, button in ipairs(self.buttons) do
                if GUIItemContainsPoint(button.item, mouseX, mouseY) then
                    button.onClick()
                    return true
                end
            end
        end
        return true     -- the window takes the mouse while it is open
    end
    return false
end
