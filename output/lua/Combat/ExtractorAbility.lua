class 'ExtractorAbility' (Entity)

ExtractorAbility.kDropRange = 6.5

function ExtractorAbility:GetDropRange()
    return ExtractorAbility.kDropRange
end

function ExtractorAbility:AllowBackfacing()
    return false
end

function ExtractorAbility:GetStoreBuildId()
    return false
end

function ExtractorAbility:GetEnergyCost(player)
    return kDropStructureEnergyCost
end

function ExtractorAbility:GetGhostModelName(ability)
    return Extractor.kModelName
end

function ExtractorAbility:GetDropStructureId()
    return kTechId.Extractor
end

function ExtractorAbility:GetSuffixName()
    return "Extractor"
end

function ExtractorAbility:GetDropClassName()
    return "Extractor"
end

function ExtractorAbility:GetDropMapName()
    return Extractor.kMapName
end

function ExtractorAbility:IsAllowed(player)
    return true
end

-- Extractor snaps to nozzles, so skip the attach-entity blocking check
function ExtractorAbility:GetAttachesToPoint()
    return true
end

function ExtractorAbility:GetMaxStructures(player)
    return 2
end

-- Extractor must snap to a ResourcePoint (nozzle)
function ExtractorAbility:GetIsPositionValid(position, player, surfaceNormal)
    local attachEntity = GetAttachEntity(kTechId.Extractor, position, kStructureSnapRadius)
    return attachEntity ~= nil
end

function ExtractorAbility:ModifyCoords(coords)
    local attachEntity = GetAttachEntity(kTechId.Extractor, coords.origin, kStructureSnapRadius)
    if attachEntity then
        local dstCoords = attachEntity:GetCoords()
        coords.origin = dstCoords.origin
        coords.zAxis = dstCoords.zAxis
        coords.yAxis = dstCoords.yAxis
        coords.xAxis = dstCoords.xAxis
    end
end

function ExtractorAbility:CreateStructure(coords, player)
    local newEnt = CreateEntity(Extractor.kMapName, coords.origin, player:GetTeamNumber())
    local attachEntity = GetAttachEntity(kTechId.Extractor, coords.origin, kStructureSnapRadius)
    if attachEntity and newEnt then
        newEnt:SetAttached(attachEntity)
    end
    return newEnt
end
