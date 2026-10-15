-- Loaded after CNBalance's commander-button hooks so their atlas reset runs first.
-- Reuse the J-menu acronym crops; upgrade names render in front of the existing art.
local kNamePixels =
{
    hammer = { 6, 15, 95, 29 },
    vanguard = { 6, 9, 93, 35 },
    inferno = { 4, 11, 97, 32 },
}
local kTextures = {}
for key in pairs(kNamePixels) do
    kTextures[key] = PrecacheAsset("ui/arcus/" .. key .. "_level0.dds")
end

local function UpdateARCSpecButton(self, index)
    local button = self.buttons and self.buttons[index]
    if not button then return end

    -- Buttons are reused when selection/menu changes. Hide both overlays first.
    if button.arcSpecName then button.arcSpecName:SetIsVisible(false) end
    if button.arcSpecUpgrade then button.arcSpecUpgrade:SetIsVisible(false) end

    local player = Client.GetLocalPlayer()
    local techId = player and player.menuTechButtons and player.menuTechButtons[index]
    -- Slot 4 is the selected-entity portrait, not a research button.
    if index == 4 or not techId or not ARCSpec then return end

    local size = button:GetSize()
    local conversion = ARCSpec.kSpecByUpgrade[techId]
    if conversion then
        local icon = button.arcSpecName
        if not icon then
            icon = GUIManager:CreateGraphicItem()
            icon:SetAnchor(GUIItem.Middle, GUIItem.Center)
            icon:SetInheritsParentAlpha(true)
            button:AddChild(icon)
            button.arcSpecName = icon
        end
        local pixels = kNamePixels[conversion.key]
        local ratio = (pixels[3] - pixels[1]) / (pixels[4] - pixels[2])
        local height = math.min(size.y * 0.2, size.x * 0.9 / ratio)
        local iconSize = Vector(height * ratio, height, 0)
        button:SetTexture("ui/transparent.dds")
        button:SetTexturePixelCoordinates(0, 0, 1, 1)
        icon:SetTexture(kTextures[conversion.key])
        icon:SetTexturePixelCoordinates(unpack(pixels))
        icon:SetSize(iconSize)
        icon:SetPosition(-iconSize * 0.5)
        icon:SetColor(button:GetColor())
        icon:SetIsVisible(true)
        return
    end

    local upgradeName
    for _, spec in ipairs(ARCSpec.kSpecOrder) do
        for level, id in ipairs(spec.upgrades) do
            if techId == id then
                upgradeName = ARCSpec.kNames[spec.key].upgrades[level][1]
                break
            end
        end
        if upgradeName then break end
    end
    if not upgradeName then return end

    local label = button.arcSpecUpgrade
    if not label then
        label = GUIManager:CreateTextItem()
        label:SetFontName(Fonts.kAgencyFB_Small)
        label:SetAnchor(GUIItem.Middle, GUIItem.Center)
        label:SetTextAlignmentX(GUIItem.Align_Center)
        label:SetTextAlignmentY(GUIItem.Align_Min)
        label:SetInheritsParentAlpha(true)
        label:SetDropShadowEnabled(true)
        label:SetLayer(kGUILayerCommanderHUD + 1)
        button:AddChild(label)
        button.arcSpecUpgrade = label
    end
    -- One word per line keeps even "Fragmentation" inside a small commander button.
    local words, width = {}, 1
    for word in upgradeName:gmatch("%S+") do
        words[#words + 1] = word
        width = math.max(width, label:GetTextWidth(word))
    end
    local text = table.concat(words, "\n")
    label:SetText(text)
    -- Centre the whole block explicitly: vertical centre alignment can centre
    -- only the first line, leaving three-line labels hanging below the button.
    local lineHeight = math.max(1, label:GetTextHeight("Ag"))
    local blockHeight = lineHeight * #words
    local scale = math.min(size.x * 0.84 / width, size.y * 0.66 / blockHeight,
        size.y * 0.23 / lineHeight)
    label:SetScale(Vector(scale, scale, 1))
    label:SetPosition(Vector(0, -size.y * 0.04 - blockHeight * scale * 0.5, 0))
    -- Lift dim labels while retaining grey/blue/red availability cues.
    local color = button:GetColor()
    label:SetColor(Color(math.min(1, color.r * 1.15 + 0.12),
        math.min(1, color.g * 1.15 + 0.12), math.min(1, color.b * 1.15 + 0.12), color.a))
    label:SetIsVisible(true)
end

local oldUpdateButtonStatus = GUICommanderButtons.UpdateButtonStatus
function GUICommanderButtons:UpdateButtonStatus(index)
    oldUpdateButtonStatus(self, index)
    UpdateARCSpecButton(self, index)
end

-- Also follow hotkey/targeting colour changes applied after the status refresh.
local oldUpdate = GUICommanderButtons.Update
function GUICommanderButtons:Update(deltaTime)
    oldUpdate(self, deltaTime)
    for index = 1, #(self.buttons or {}) do
        UpdateARCSpecButton(self, index)
    end
end
