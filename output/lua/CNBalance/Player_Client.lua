function Player:GetWeaponClipSize()
    local weapon = self:GetActiveWeapon()

    if weapon then
        if weapon:isa("ClipWeapon") then
            return weapon:GetClipSize()
        end
    end

    return 0
end


function PlayerUI_GetTeamRespawnInfo()
    local teamType = PlayerUI_GetTeamType()
    local respawnCount = 0

    local teamInfo = GetTeamInfoEntity(teamType)
    if teamInfo then
        if teamType == kTeam2Index then
            respawnCount = teamInfo:GetEggCount()
        elseif teamType == kTeam1Index then
            respawnCount = teamInfo.numInfantryPortals
        end
    end

    return teamType, respawnCount

end


function PlayerUI_GetDeadlockTimeLeft()

    local gameInfo = GetGameInfoEntity()
    if not gameInfo then return 99999 end
    local teamNumber = PlayerUI_GetTeamNumber()
    if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then return 99999 end

    local state = gameInfo:GetState()
    if state ~= kGameState.PreGame and state ~= kGameState.Countdown then
        if state ~= kGameState.Started then
            return 99999
        else
            local teamInfo = GetTeamInfoEntity(teamNumber )
            if teamInfo then
                return math.floor(teamInfo.deadlockTime - Shared.GetTime())
            end
        end
    end

    return 99999

end

local basePlayerUI_GetTooltipDataFromTechId = PlayerUI_GetTooltipDataFromTechId
function PlayerUI_GetTooltipDataFromTechId(techId, hotkeyIndex)

    local tooltipData = basePlayerUI_GetTooltipDataFromTechId(techId, hotkeyIndex)
    if tooltipData and tooltipData.resourceType == nil then
        tooltipData.resourceType = 0
    end

    return tooltipData

end

local basePlayerUI_GetInventoryTechIds = PlayerUI_GetInventoryTechIds
function PlayerUI_GetInventoryTechIds()
    local inventoryTechIds = basePlayerUI_GetInventoryTechIds()

    local player = Client.GetLocalPlayer()
    if inventoryTechIds and player and player.GetWeaponInHUDSlot then
        for i = 1, #inventoryTechIds do
            local inventoryItem = inventoryTechIds[i]
            local weapon = player:GetWeaponInHUDSlot(inventoryItem.HUDSlot)
            if weapon and weapon:isa("MotionTracker") then
                inventoryItem.TechId = kTechId.MotionTracker
            end
        end
    end

    return inventoryTechIds
end

local baseUpdateClientEffects = Player.UpdateClientEffects
function Player:UpdateClientEffects(deltaTime, isLocal)
    baseUpdateClientEffects(self, deltaTime, isLocal)

    if isLocal and not self:isa("Alien") and not self:isa("Spectator") then
        local useShader = Player.screenEffects.darkVision
        if useShader then
            useShader:SetActive(false)
        end
    end
end
