
-- Resolve the player-name for a tunnel using whichever stable identifier
-- we have. We prefer the cached client index (set at tunnel creation /
-- connect time) because the player entity id changes whenever the owner
-- evolves into another lifeform — that's the bug where the label flips
-- to "Comm Entrance/Exit" after the round-start commander goes Origin
-- Form and then evolves.
local function ResolveOwnerName(tunnel)

    if not tunnel then return nil end

    local stableIndex = tunnel.ownerStableClientIndex
    if stableIndex and stableIndex ~= 0 and stableIndex ~= -1 then
        for _, playerInfo in ientitylist(Shared.GetEntitiesWithClassname("PlayerInfoEntity")) do
            if playerInfo.clientId == stableIndex then
                local name = playerInfo.playerName
                if name and name ~= "" then return name end
            end
        end
    end

    local ownerId = tunnel.ownerClientId
    if ownerId and ownerId ~= Entity.invalidId then
        for _, playerInfo in ientitylist(Shared.GetEntitiesWithClassname("PlayerInfoEntity")) do
            if playerInfo.playerId == ownerId then
                local name = playerInfo.playerName
                if name and name ~= "" then return name end
            end
        end
    end

    return nil

end

-- Returns the AlienTunnelManager for the tunnel's team (server only).
local function GetTunnelManagerForTunnel(tunnel)
    local teamInfo = GetTeamInfoEntity(tunnel:GetTeamNumber())
    if teamInfo and teamInfo.GetTunnelManager then
        return teamInfo:GetTunnelManager()
    end
end

-- Maps a commander tunnel entrance entity-id to a label like "Comm 1 Entrance"
-- / "Comm 3 Exit" using the AlienTunnelManager's button-index table.
-- buttonIndex 1..4 -> entries, 5..8 -> exits; pair number = ((idx - 1) % 4) + 1.
local function GetCommanderLabelForEntrance(tunnel, entranceEntityId)
    local manager = GetTunnelManagerForTunnel(tunnel)
    if not manager or not manager.tunnelEntIdToIndex then return nil end
    local buttonIndex = manager.tunnelEntIdToIndex[entranceEntityId]
    if not buttonIndex then return nil end
    local pairNum = ((buttonIndex - 1) % 4) + 1
    local isExit = buttonIndex > 4
    return string.format("Comm %d %s", pairNum, isExit and "Exit" or "Entrance")
end

function Tunnel:GetConnectionStartLabel()
    local name = ResolveOwnerName(self)
    if name then
        return string.format("%s Entrance", name)
    end
    if self.exitAId and self.exitAId ~= Entity.invalidId then
        local label = GetCommanderLabelForEntrance(self, self.exitAId)
        if label then return label end
    end
    return "Comm Tunnel"
end

function Tunnel:GetConnectionEndLabel()
    local name = ResolveOwnerName(self)
    if name then
        return string.format("%s Exit", name)
    end
    if self.exitBId and self.exitBId ~= Entity.invalidId then
        local label = GetCommanderLabelForEntrance(self, self.exitBId)
        if label then return label end
    end
    return "Comm Tunnel"
end

function Tunnel:GetConnectionColorSeed()
    -- Prefer a stable client index so the connection colour doesn't flip
    -- when the owner's entity id changes due to evolution/replace.
    local seed = self.ownerStableClientIndex
    if not seed or seed == 0 then
        seed = self.ownerClientId
    end
    if not seed or seed == Entity.invalidId or seed == 0 then
        seed = self:GetId()
    end
    return seed
end

if Server then

    function Tunnel:GetOwnerClientId()
        return self.ownerClientId
    end

    function Tunnel:SetOwnerClientId(clientId)
        self.ownerClientId = clientId

        -- Opportunistically capture a stable identifier (the client index
        -- never changes across Replace/lifeform evolution) so the
        -- label survives the owner switching forms.
        if clientId and clientId ~= Entity.invalidId then
            local entity = Shared.GetEntity(clientId)
            if entity and entity.GetClientIndex then
                local idx = entity:GetClientIndex()
                if idx and idx > 0 then
                    self.ownerStableClientIndex = idx
                end
            end
        end
    end

    function Tunnel:SetOwnerStableClientIndex(clientIndex)
        if clientIndex and clientIndex > 0 then
            self.ownerStableClientIndex = clientIndex
        end
    end

    function Tunnel:GetOwnerStableClientIndex()
        return self.ownerStableClientIndex
    end

    local function remap(x,t1,t2,s1,s2)
        local invLerp= ((x - t1) / (t2 - t1))
        return  invLerp * (s2 - s1) + s1
    end
    
    function Tunnel:UseExit(entity, exit, exitSide)
        
        
        local destinationOrigin = exit:GetOrigin() 

        local normal =exit:GetCoords().yAxis

        local extents = GetExtents(entity:GetTechId())
        local maxExtent = math.max(extents.x,extents.y,extents.z)
        local upValue = Math.DotProduct(normal,Vector(0,1,0))  -- -1 down 1 up
        local downParam = remap(upValue,1,-1,0,1)
        local sideParam = remap(math.abs(upValue),0,1,1,0)
        
        destinationOrigin =  destinationOrigin + normal * (0.3 + downParam * maxExtent * 2)
        destinationOrigin = destinationOrigin - Vector(0,sideParam * maxExtent ,0)
        
        if entity.OnUseGorgeTunnel then
            entity:OnUseGorgeTunnel(destinationOrigin)
        end

        self:TriggerEffects("tunnel_exit_3D", { effecthostcoords = entity:GetCoords() })

        --Required to call effects manager due to sound-parenting behaviors, otherwise sound doesn't play INSIDE tunnels
        self:TriggerEffects("tunnel_exit_3D", { effecthostcoords = entity:GetCoords() })

        entity:SetOrigin(destinationOrigin)

        if entity:isa("Player") then

            local newAngles = entity:GetViewAngles()
            newAngles.pitch = 0
            newAngles.roll = 0
            newAngles.yaw = newAngles.yaw + self:GetMinimapYawOffset()
            entity:SetOffsetAngles(newAngles)

            if HasMixin(entity, "TunnelUser") then
                entity.currentTunnelId = Entity.invalidId
            end

        end

        exit:OnEntityExited(entity)

        if exitSide == kTunnelExitSide.A then
            self.timeExitAUsed = Shared.GetTime()
        elseif exitSide == kTunnelExitSide.B then
            self.timeExitBUsed = Shared.GetTime()
        end
        
        if exit.hasCragUpgrade then
            if entity and HasMixin(entity, "Mucousable") then
                entity:SetMucousShield()
            end
        end
    end
    
    local baseMovePlayerToTunnel = Tunnel.MovePlayerToTunnel
    function Tunnel:MovePlayerToTunnel(player, entrance)
    
        assert(player)
        assert(entrance)
        
        local entranceId = entrance:GetId()
        if entrance.hasShiftUpgrade then
            if entranceId == self.exitAId then
                local exitB = self:GetExitB()
                if exitB then
                    self.timeExitAUsed = Shared.GetTime()
                    self:UseExit(player, exitB, kTunnelExitSide.B)
                    return
                end
            elseif entranceId == self.exitBId then
                local exitA = self:GetExitA()
                if exitA then
                    self.timeExitBUsed = Shared.GetTime()
                    self:UseExit(player, exitA, kTunnelExitSide.A)
                    return
                end 
            end
        end
        baseMovePlayerToTunnel(self,player,entrance)
    end
end
