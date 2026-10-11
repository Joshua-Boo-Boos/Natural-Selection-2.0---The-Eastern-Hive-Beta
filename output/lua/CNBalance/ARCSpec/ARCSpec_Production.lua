--[[
    ARCUS (ARC Upgrade System) - icons in the commander / spectator research tray (GUIProduction).

    Loaded post lua/GUIProduction.lua (after the mod's own hook there). The tray's normal entries come from TeamInfo's tech
    bitmask, which is already full, so the ARCUS state arrives in the ARCSpecTeamState message (ARCSpec_Shots.lua) and its
    icons are kept in the tray's "complete" list here, built the same way vanilla builds a researched-tech entry.

    One icon per specialisation the team has had, showing its acronym and level ("H.E.L.L." / "Level 3"):
      team colour (blue)  a factory of that specialisation stands
      red                 every factory of it has been destroyed (the researched levels return with a new one)
    Hovering it shows the factory's name and the current effects of its researched levels (ARCSpec.GetLevelTooltip).
]]

local kDeactivatedColor = Color(1, 0.2, 0.2, 1)
local kIconPixels = 100

local kIconTextures = {}
for _, key in ipairs({ "hammer", "vanguard", "inferno" }) do
    kIconTextures[key] = {}
    for level = 0, 4 do
        kIconTextures[key][level] = PrecacheAsset(string.format("ui/arcus/%s_level%d.dds", key, level))
    end
end

local function GetIconSize()
    return GUIScale(Vector(42, 42, 0))
end

-- Mirrors vanilla GUIProduction's file-local createTech for a finished tech (background, icon, and the hidden research bar
-- its resize code expects every entry to have).
local function CreateEntry(self, techId)

    local list = self.Complete
    local tech = list:Create(techId)
    local size = GetIconSize()

    tech.Background:SetTexture("ui/marine_buildmenu_buttonbg.dds")
    tech.Background:SetSize(size)

    local icon = GUIManager:CreateGraphicItem()
    icon:SetSize(size)
    tech.Background:AddChild(icon)
    tech.Icon = icon

    local researchBarBack = GUIManager:CreateGraphicItem()
    researchBarBack:SetIsVisible(false)
    researchBarBack:SetSize(Vector(size.x - 2, GUIScale(4), 0))
    researchBarBack:SetAnchor(GUIItem.Left, GUIItem.Bottom)
    tech.Background:AddChild(researchBarBack)
    tech.ResearchBarBack = researchBarBack

    local researchBar = GUIManager:CreateGraphicItem()
    researchBarBack:AddChild(researchBar)
    tech.ResearchBar = researchBar

    list:Add(tech)
    return tech

end

local function SyncARCUSEntries(self)

    if not self.Complete or self.TeamIndex ~= kTeam1Index then return end

    local teamState = ARCSpec.teamState and ARCSpec.teamState[self.TeamIndex]
    self.arcusShown = self.arcusShown or {}

    for _, spec in ipairs(ARCSpec.kSpecOrder) do

        local info = teamState and teamState[spec.key]
        local state = info and info.state or 0
        local level = info and Clamp(info.level or 0, 0, 4) or 0
        local techId = spec.factory
        local shownKey = state > 0 and (state .. ":" .. level) or nil

        if shownKey ~= self.arcusShown[techId] then

            if state == 0 then
                if self.Complete:Get(techId) then
                    self.Complete:Remove(techId)
                end
            else
                local tech = self.Complete:Get(techId) or CreateEntry(self, techId)
                tech.Icon:SetTexture(kIconTextures[spec.key][level])
                tech.Icon:SetTexturePixelCoordinates(0, 0, kIconPixels, kIconPixels)
                local color = state == 1 and kIconColors[self.TeamIndex] or kDeactivatedColor
                tech.Background:SetColor(color)
                tech.Icon:SetColor(color)
            end

            self.arcusShown[techId] = shownKey

        end

    end

end

local baseUpdateTech = GUIProduction.UpdateTech
function GUIProduction:UpdateTech(onChange)
    baseUpdateTech(self, onChange)
    SyncARCUSEntries(self)
end

--[[
    Hovering an ARCUS icon shows the factory's name and every effect its researched levels give (ARCSpec.GetLevelTooltip),
    instead of the plain name the tray shows for other entries. Applied after the tray's own Update, which has just set
    (and shown) the plain name for the hovered entry.
]]
local baseUpdate = GUIProduction.Update
function GUIProduction:Update(deltaTime)
    baseUpdate(self, deltaTime)

    if not GUIProduction.kShowProgressTooltip or not self.tooltip or not self.Complete or self.TeamIndex ~= kTeam1Index then
        return
    end

    local teamState = ARCSpec.teamState and ARCSpec.teamState[self.TeamIndex]
    local mouseX, mouseY = Client.GetCursorPosScreen()

    for _, spec in ipairs(ARCSpec.kSpecOrder) do
        local tech = self.Complete:Get(spec.factory)
        if tech and tech.Icon and GUIItemContainsPoint(tech.Icon, mouseX, mouseY) then
            local info = teamState and teamState[spec.key]
            local text = ARCSpec.GetLevelTooltip(spec.key, info and info.level or 0)
            if text then
                if info and info.state == 2 then
                    text = text .. "\n- Offline: no factory. Existing ARCs keep these levels"
                end
                self.tooltip:SetText(text)
                if not self.tooltip:GetShown() then
                    self.tooltip:Show()
                end
            end
            return
        end
    end
end

-- A team change rebuilds the tray from scratch, so forget what was shown.
local baseSetTeam = GUIProduction.SetTeam
function GUIProduction:SetTeam(teamIndex)
    self.arcusShown = nil
    if self.Complete then
        for _, spec in ipairs(ARCSpec.kSpecOrder) do
            if self.Complete:Get(spec.factory) then
                self.Complete:Remove(spec.factory)
            end
        end
    end
    return baseSetTeam(self, teamIndex)
end
