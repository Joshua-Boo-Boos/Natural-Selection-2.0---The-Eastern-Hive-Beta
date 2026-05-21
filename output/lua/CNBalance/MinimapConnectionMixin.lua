-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\MinimapConnectionMixin.lua  (NS2.0-TEH Beta replacement)
--
--    Used for rendering connections on the minimap.
--    Propagates optional GetConnectionStartLabel / GetConnectionEndLabel
--    callbacks from the owner onto the MapConnector entity so the client
--    can render labels at the line endpoints.
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/MapConnector.lua")

MinimapConnectionMixin = CreateMixin( MinimapConnectionMixin )
MinimapConnectionMixin.type = "MinimapConnection"

MinimapConnectionMixin.expectedMixins =
{
    Team = "For team number."
}

MinimapConnectionMixin.expectedCallbacks =
{
    GetConnectionStartPoint = "For map connector.",
    GetConnectionEndPoint = "For map connector."
}

MinimapConnectionMixin.optionalCallbacks =
{
    GetConnectionStartLabel = "Returns the text label for the start of the connection.",
    GetConnectionEndLabel = "Returns the text label for the end of the connection.",
    GetConnectionColorSeed = "Returns an integer seed used to pick a deterministic random colour.",
}

function MinimapConnectionMixin:__initmixin()
end

if Server then

    local function UpdateConnectorMeta(self, connector)

        if connector.SetStartLabel and self.GetConnectionStartLabel then
            connector:SetStartLabel(self:GetConnectionStartLabel() or "")
        end
        if connector.SetEndLabel and self.GetConnectionEndLabel then
            connector:SetEndLabel(self:GetConnectionEndLabel() or "")
        end

        if connector.SetColorSeed then
            local seed
            if self.GetConnectionColorSeed then
                seed = self:GetConnectionColorSeed()
            end
            -- Default seed: a deterministic value derived from this entity's id.
            seed = seed or self:GetId()
            connector:SetColorSeed(seed)
        end

        if connector.SetOwnerStableClientIndex then
            local stableIndex
            if self.GetOwnerStableClientIndex then
                stableIndex = self:GetOwnerStableClientIndex()
            end
            connector:SetOwnerStableClientIndex(stableIndex or 0)
        end

        -- If this ownerable connection exposes exit entity ids (tunnel), capture
        -- the owner client index for each entrance so the client can decide
        -- which end is the player's entrance vs exit. This avoids label flips
        -- when the player's in-world entity id changes (evolution/replace).
        if connector.SetStartEntranceOwnerStableClientIndex then
            local startIndex = 0
            if self.exitAId and self.exitAId ~= Entity.invalidId then
                local exitA = Shared.GetEntity(self.exitAId)
                if exitA and exitA.ownerId and exitA.ownerId ~= Entity.invalidId then
                    local ownerEnt = Shared.GetEntity(exitA.ownerId)
                    if ownerEnt and ownerEnt.GetClientIndex then
                        startIndex = ownerEnt:GetClientIndex()
                    end
                end
            end
            connector:SetStartEntranceOwnerStableClientIndex(startIndex)
        end

        if connector.SetEndEntranceOwnerStableClientIndex then
            local endIndex = 0
            if self.exitBId and self.exitBId ~= Entity.invalidId then
                local exitB = Shared.GetEntity(self.exitBId)
                if exitB and exitB.ownerId and exitB.ownerId ~= Entity.invalidId then
                    local ownerEnt = Shared.GetEntity(exitB.ownerId)
                    if ownerEnt and ownerEnt.GetClientIndex then
                        endIndex = ownerEnt:GetClientIndex()
                    end
                end
            end
            connector:SetEndEntranceOwnerStableClientIndex(endIndex)
        end

    end

    function MinimapConnectionMixin:OnUpdate(deltaTime)

        local endPoint = self:GetConnectionEndPoint()
        local startPoint = self:GetConnectionStartPoint()

        if (not endPoint or not startPoint) and self.connectorId then

            local connector = Shared.GetEntity(self.connectorId)
            if connector then
                DestroyEntity(connector)
            end

            self.connectorId = nil

        elseif endPoint and startPoint and not self.connectorId then
            self.connectorId = CreateEntity(MapConnector.kMapName, startPoint, self:GetTeamNumber()):GetId()
        end

        if endPoint and startPoint and self.connectorId then

            local connector = Shared.GetEntity(self.connectorId)
            assert(connector)
            connector:SetOrigin(startPoint)
            connector:SetEndPoint(endPoint)

            UpdateConnectorMeta(self, connector)

        end

    end

    function MinimapConnectionMixin:OnDestroy()

        if self.connectorId then

            local connector = Shared.GetEntity(self.connectorId)
            if connector then
                DestroyEntity(connector)
            end

            self.connectorId = nil

        end

    end

end
