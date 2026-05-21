-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\MapConnector.lua  (NS2.0-TEH Beta replacement)
--
--    Used for displaying connections on the minimap. origin is startpoint.
--    Adds networked startLabel/endLabel strings and a colorSeed used by the
--    minimap renderer to pick a deterministic random colour per connection.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Entity.lua")
Script.Load("lua/TeamMixin.lua")

class 'MapConnector' (Entity)

MapConnector.kMapName = "mapconnector"

local networkVars =
{
    endPoint = "vector",
    startLabel = "string (32)",
    endLabel = "string (32)",
    colorSeed = "integer",
    ownerStableClientIndex = "integer",
    startEntranceOwnerStableClientIndex = "integer",
    endEntranceOwnerStableClientIndex = "integer",
}

AddMixinNetworkVars(TeamMixin, networkVars)

function MapConnector:OnCreate()

    Entity.OnCreate(self)

    InitMixin(self, TeamMixin)

    self:SetUpdates(false)

    self.startLabel = ""
    self.endLabel = ""
    self.colorSeed = 0
    self.ownerStableClientIndex = 0
    self.startEntranceOwnerStableClientIndex = 0
    self.endEntranceOwnerStableClientIndex = 0

end

function MapConnector:SetEndPoint(endPoint)
    self.endPoint = endPoint
end

function MapConnector:GetEndPoint()
    return self.endPoint
end

function MapConnector:SetStartLabel(label)
    label = label or ""
    if #label > 31 then label = label:sub(1, 31) end
    self.startLabel = label
end

function MapConnector:SetEndLabel(label)
    label = label or ""
    if #label > 31 then label = label:sub(1, 31) end
    self.endLabel = label
end

function MapConnector:GetStartLabel()
    return self.startLabel or ""
end

function MapConnector:GetEndLabel()
    return self.endLabel or ""
end

function MapConnector:SetColorSeed(seed)
    self.colorSeed = seed or 0
end

function MapConnector:SetOwnerStableClientIndex(index)
    -- store stable client index (0 for none)
    self.ownerStableClientIndex = index or 0
end

function MapConnector:GetOwnerStableClientIndex()
    return self.ownerStableClientIndex or 0
end

function MapConnector:GetColorSeed()
    return self.colorSeed or 0
end

function MapConnector:SetStartEntranceOwnerStableClientIndex(index)
    self.startEntranceOwnerStableClientIndex = index or 0
end

function MapConnector:GetStartEntranceOwnerStableClientIndex()
    return self.startEntranceOwnerStableClientIndex or 0
end

function MapConnector:SetEndEntranceOwnerStableClientIndex(index)
    self.endEntranceOwnerStableClientIndex = index or 0
end

function MapConnector:GetEndEntranceOwnerStableClientIndex()
    return self.endEntranceOwnerStableClientIndex or 0
end

function MapConnector:OnTeamChange()
    self:UpdateRelevancy()
end

function MapConnector:UpdateRelevancy()

    self:SetRelevancyDistance(Math.infinity)

    local mask = 0

    if self:GetTeamNumber() == kTeam1Index then
        mask = kRelevantToTeam1
    elseif self:GetTeamNumber() == kTeam2Index then
        mask = kRelevantToTeam2
    end

    self:SetExcludeRelevancyMask(mask)

end

Shared.LinkClassToMap("MapConnector", MapConnector.kMapName, networkVars)
