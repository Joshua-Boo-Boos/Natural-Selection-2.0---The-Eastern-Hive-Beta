
local kCommanderIcons = PrecacheAsset("ui/alien_hivestatus_commicons.dds")

local kLifeformEggButtonIcons =
{
    [kTechId.ProwlerEgg] =
    {
        UseBuildMenuIcon = true,
    },

    [kTechId.VokexEgg] =
    {
        -- Reuse the Fade egg's centered build-menu icon (VokexEgg's atlas offset is
        -- set to the Fade cell in TechTreeButtons), but flip it horizontally so the
        -- Vokex egg's Fade icon faces the other way.
        UseBuildMenuIcon = true,
        MirrorHorizontal = true,
    }
}

local kLifeformEggIconEnabledColor = Color(1, 0.62, 0.06, 1)
local kLifeformEggIconDisabledColor = Color(0.35, 0.35, 0.35, 1)
local kLifeformEggIconScale = 0.775

local function GetLifeformEggButtonColor(buttonItem)

    local color = buttonItem:GetColor()
    if color.a <= 0 then
        return color
    end

    if color.r < 0.5 and color.g < 0.5 and color.b < 0.5 then
        return kLifeformEggIconDisabledColor
    end

    if color.r > 0.8 and color.g < 0.2 and color.b < 0.2 then
        return kLifeformEggIconDisabledColor
    end

    return Color(kLifeformEggIconEnabledColor.r, kLifeformEggIconEnabledColor.g, kLifeformEggIconEnabledColor.b, color.a)

end

local function GetCommanderButtonTechId(buttonIndex)

    local player = Client.GetLocalPlayer()
    if not player or not player.menuTechButtons or buttonIndex > table.icount(player.menuTechButtons) then
        return kTechId.None
    end

    if buttonIndex == 4 then
        local selectedEnts = player:GetSelection()
        if selectedEnts and selectedEnts[1] then
            return selectedEnts[1]:GetTechId()
        end
    end

    return player.menuTechButtons[buttonIndex]

end

local function UpdateLifeformEggButtonIcon(self, buttonIndex)

    local buttonItem = self.buttons and self.buttons[buttonIndex]
    if not buttonItem then
        return
    end

    local techId = GetCommanderButtonTechId(buttonIndex)
    local iconInfo = kLifeformEggButtonIcons[techId]
    if not iconInfo then
        buttonItem:SetTexture("ui/buildmenu.dds")

        if buttonItem.lifeformEggIcon then
            buttonItem.lifeformEggIcon:SetIsVisible(false)
        end

        return
    end

    local icon = buttonItem.lifeformEggIcon
    if not icon then
        icon = GUIManager:CreateGraphicItem()
        icon:SetAnchor(GUIItem.Middle, GUIItem.Center)
        icon:SetInheritsParentAlpha(true)
        buttonItem:AddChild(icon)
        buttonItem.lifeformEggIcon = icon
    end

    local iconSize = buttonItem:GetSize() * (iconInfo.Scale or kLifeformEggIconScale)
    local iconColor = GetLifeformEggButtonColor(buttonItem)

    buttonItem:SetTexture("ui/transparent.dds")
    buttonItem:SetTexturePixelCoordinates(0, 0, 1, 1)
    buttonItem:SetColor(Color(iconColor.r, iconColor.g, iconColor.b, iconColor.a))

    if iconInfo.UseBuildMenuIcon then
        icon:SetTexture("ui/buildmenu.dds")
        local x1, y1, x2, y2 = GUIUnpackCoords(GetTextureCoordinatesForIcon(techId))
        if iconInfo.MirrorHorizontal then
            -- Swap left/right texture coords to flip the icon horizontally.
            x1, x2 = x2, x1
        end
        icon:SetTexturePixelCoordinates(x1, y1, x2, y2)
    elseif iconInfo.TextureCoords then
        icon:SetTexture(iconInfo.Texture)
        icon:SetTexturePixelCoordinates(GUIUnpackCoords(iconInfo.TextureCoords))
    else
        icon:SetTexture(iconInfo.Texture)
        icon:SetTexturePixelCoordinates(0, 0, iconInfo.SourceWidth, iconInfo.SourceHeight)
    end
    icon:SetSize(iconSize)
    icon:SetPosition(-iconSize * 0.5 + (iconInfo.Offset or Vector(0, 0, 0)))
    icon:SetColor(iconColor)
    icon:SetIsVisible(true)

end

local function SyncLifeformEggButtonIconColors(self)

    if not self.buttons then
        return
    end

    for i = 1, #self.buttons do
        local buttonItem = self.buttons[i]
        local techId = GetCommanderButtonTechId(i)
        local iconInfo = kLifeformEggButtonIcons[techId]
        if iconInfo then
            local iconColor = GetLifeformEggButtonColor(buttonItem)
            buttonItem:SetColor(iconColor)

            if buttonItem.lifeformEggIcon then
                buttonItem.lifeformEggIcon:SetColor(iconColor)
            end
        elseif buttonItem.lifeformEggIcon and buttonItem.lifeformEggIcon:GetIsVisible() then
            buttonItem.lifeformEggIcon:SetIsVisible(false)
        end
    end

end

local baseUpdateButtonStatus = GUICommanderButtons.UpdateButtonStatus
function GUICommanderButtons:UpdateButtonStatus(buttonIndex)

    baseUpdateButtonStatus(self, buttonIndex)
    UpdateLifeformEggButtonIcon(self, buttonIndex)

end

local function ResetTeamCountIcon(element)
    element.count = 0
    element:SetColor(GUIMarineHUD.kCountNoUsed)
    element.text:SetIsVisible(false)
end

local kTechIdToIndex = {
    [kTechId.Skulk] = 5,
    [kTechId.Gorge] = 4,
    [kTechId.Prowler] = 6,
    [kTechId.Lerk] = 3,
    [kTechId.Fade] = 2,
    [kTechId.Vokex] = 7,
    [kTechId.Onos] = 1,
}

local function CreateTeamCountElement(techID)
    local teamCountIcon = GetGUIManager():CreateGraphicItem()
    if PlayerUI_GetTeamType() == kMarineTeamType  then
        teamCountIcon:SetTexture(kInventoryIconsTexture)
        teamCountIcon:SetTexturePixelCoordinates(GetTexCoordsForTechId(techID))
        teamCountIcon:SetSize(GUIMarineHUD.kTeamIconSize)
    else
        local iconIndex = kTechIdToIndex[techID]
        teamCountIcon:SetTexture(kCommanderIcons)
        teamCountIcon:SetTexturePixelCoordinates(( iconIndex - 1)* 72 ,0 ,iconIndex * 72 ,68)
        teamCountIcon:SetSize(GUIScale( Vector( 35, 32, 0 ) ))
    end
    teamCountIcon:SetAnchor(GUIItem.Left, GUIItem.Top)
    teamCountIcon:SetColor(GUIMarineHUD.kBackgroundColor)

    local countText = GUIManager:CreateTextItem()
    countText:SetPosition(Vector( -9 , -12, 0 ) )
    countText:SetAnchor( GUIItem.Right, GUIItem.Bottom )
    countText:SetFontName( Fonts.kAgencyFB_Large_Bold )
    countText:SetColor( PlayerUI_GetTeamType() == kMarineTeamType and kMarineTeamColorFloat or kAlienTeamColorFloat)
    countText:SetScale(  GUIScale( Vector(1,1,0) * 0.4725 ))  --Scaled???
    countText:SetLayer( kGUILayerPlayerHUDForeground2 )
    teamCountIcon:AddChild(countText)

    teamCountIcon.text = countText
    teamCountIcon.techId = techID

    ResetTeamCountIcon(teamCountIcon)
    return teamCountIcon
end

GUICommanderButtons.kAlienTechIdToNetworkVar = {
    [kTechId.Skulk] = "teamSkulkCount",
    [kTechId.Gorge] = "teamGorgeCount",
    [kTechId.Prowler] = "teamProwlerCount",
    [kTechId.Vokex] = "teamVokexCount",
    [kTechId.Lerk] = "teamLerkCount",
    [kTechId.Fade] = "teamFadeCount",
    [kTechId.Onos] = "teamOnosCount",
}

local function UpdateTeamCount(self, _teamInfo, _element)
    local netVarName = nil
    if PlayerUI_GetTeamType() == kMarineTeamType then
        local techMapName = GUIMarineBuyMenu._GetMapNameForNetvar(nil, _element.techId)       --???
        assert(techMapName)
        netVarName = TeamInfo_GetUserTrackerNetvarName(techMapName)
    else
        netVarName = GUICommanderButtons.kAlienTechIdToNetworkVar[_element.techId]
    end

    assert(netVarName)
    local count = _teamInfo[netVarName]
    if _element.count ~= count then
        _element.count = count
        _element.text:SetText(string.format("x%i", _element.count))
        if PlayerUI_GetTeamType() == kMarineTeamType then
            _element:SetColor(numUsers ~= 0 and GUIMarineHUD.kCountHaveUser or GUIMarineHUD.kCountNoUsed)
        else
            _element:SetColor(numUsers ~= 0 and GUIHiveStatus.kTeamCountIconColor or GUIHiveStatus.kTeamCountZeroedIconColor)
        end
        _element.text:SetIsVisible(count > 1)
    end
end

local baseInitialize = GUICommanderButtons.Initialize
function GUICommanderButtons:Initialize()
    baseInitialize(self)
    self.teamCountElements = {}
    if PlayerUI_GetTeamType() == kMarineTeamType then
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Shotgun))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.HeavyMachineGun))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.GrenadeLauncher))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Flamethrower))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Cannon))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.DualRailgunExosuit))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.DualMinigunExosuit))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Jetpack))

    else
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Skulk))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Gorge))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Prowler))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Lerk))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Fade))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Vokex))
        table.insert(self.teamCountElements,CreateTeamCountElement(kTechId.Onos))
    end

    local text = GUIManager:CreateTextItem()
    text:SetAnchor( GUIItem.Top, GUIItem.Left )
    text:SetFontName( Fonts.kAgencyFB_Large_Bold )
    text:SetColor(  PlayerUI_GetTeamType() == kMarineTeamType and kMarineTeamColorFloat or kAlienTeamColorFloat)
    text:SetScale(  GUIScale( Vector(1,1,0) * 0.4725 ))  --Scaled???
    text:SetPosition( PlayerUI_GetTeamType() == kMarineTeamType and Vector( 25 , 60, 0 ) or Vector(25,210,0))
    self.text = text
    
    for index,element in ipairs(self.teamCountElements) do
        local offset = index - 1
        local gap = PlayerUI_GetTeamType() == kMarineTeamType and 48 or 35
        element:SetPosition(Vector(25 + offset * gap,30,0))
    end
end 

local baseUninitialize = GUICommanderButtons.Uninitialize
function GUICommanderButtons:Uninitialize()
    if self.teamCountElements then
        for k,v in pairs(self.teamCountElements) do
            GUI.DestroyItem(v)
        end
    end
    self.teamCountElements = nil

    if self.text then
        GUI.DestroyItem(self.text)
    end
    self.text = nil
    baseUninitialize(self)
    
end


local baseReset = GUICommanderButtons.Reset
function GUICommanderButtons:Reset()
    baseReset(self)
    for _,element in ipairs(self.teamCountElements) do
        ResetTeamCountIcon(element)
    end
end

local kErrorColor = Color(1, 0, 0, 1)
local baseUpdate = GUICommanderButtons.Update
function GUICommanderButtons:Update(deltaTime)
    baseUpdate(self,deltaTime)
    SyncLifeformEggButtonIconColors(self)

    local player = Client.GetLocalPlayer()
    local teamInfo = GetTeamInfoEntity(player:GetTeamNumber())
    if teamInfo then
        for _,element in ipairs(self.teamCountElements) do
            UpdateTeamCount(self,teamInfo,element)
        end
    end
    self.text:SetText(PlayerUI_GetGameTimeString())
    self.text:SetColor(PlayerUI_DeadlockActivated() and kErrorColor or (PlayerUI_GetTeamType() == kMarineTeamType and kMarineTeamColorFloat or kAlienTeamColorFloat))
end
