-- ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\PhaseGateUserMixin.lua
--
--    Created by:   Andreas Urwalek (andi@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

PhaseGateUserMixin = CreateMixin( PhaseGateUserMixin )
PhaseGateUserMixin.type = "PhaseGateUser"

local kPhaseDelay = 1

PhaseGateUserMixin.networkVars =
{
    timeOfLastPhase = "compensated private time"
}

local function SharedUpdate(self)
    PROFILE("PhaseGateUserMixin:OnUpdate")
    if self:GetCanPhase() then

        for _, phaseGate in ipairs(GetEntitiesForTeamWithinRange("PhaseGate", self:GetTeamNumber(), self:GetOrigin(), 0.5)) do
        
            if phaseGate:GetIsDeployed() and GetIsUnitActive(phaseGate) and phaseGate:Phase(self) then

                self.timeOfLastPhase = Shared.GetTime()
                
                if Client then               
                    self.timeOfLastPhaseClient = Shared.GetTime()
                    local viewAngles = self:GetViewAngles()
                    Client.SetYaw(viewAngles.yaw)
                    Client.SetPitch(viewAngles.pitch)     
                end
                --[[
                if HasMixin(self, "Controller") then
                    self:SetIgnorePlayerCollisions(1.5)
                end
                --]]
                break
                
            end
        
        end
    
    end

end

function PhaseGateUserMixin:__initmixin()
    
    PROFILE("PhaseGateUserMixin:__initmixin")
    
    self.timeOfLastPhase = 0
end

local kOnPhase =
{
    phaseGateId = "entityid",
    phasedEntityId = "entityid"
}
Shared.RegisterNetworkMessage("OnPhase", kOnPhase)

if Server then

    -- perf: cache PhaseGate entity count once per tick instead of per-entity
    local _pgCountCache = 0
    local _pgCountTime = -1
    local function GetPhaseGateCount()
        local now = Shared.GetTime()
        if now ~= _pgCountTime then
            _pgCountTime = now
            _pgCountCache = Shared.GetEntitiesWithClassname("PhaseGate"):GetSize()
        end
        return _pgCountCache
    end

    function PhaseGateUserMixin:OnProcessMove(input)
        PROFILE("PhaseGateUserMixin:OnProcessMove")

        -- perf: skip the expensive spatial query when no phase gates exist on the map
        if GetPhaseGateCount() == 0 then
            return
        end

        -- perf: skip the expensive spatial query when phase is on cooldown
        if not self:GetCanPhase() then
            return
        end

        for _, phaseGate in ipairs(GetEntitiesForTeamWithinRange("PhaseGate", self:GetTeamNumber(), self:GetOrigin(), 0.5)) do
            if phaseGate:GetIsDeployed() and GetIsUnitActive(phaseGate) and phaseGate:Phase(self) then
                -- If we can found a phasegate we can phase through, inform the server
                self.timeOfLastPhase = Shared.GetTime()
                local id = self:GetId()
                Server.SendNetworkMessage(self:GetClient(), "OnPhase", { phaseGateId = phaseGate:GetId(), phasedEntityId = id or Entity.invalidId }, true)
                return
            end
        end
    end

    function PhaseGateUserMixin:OnUpdate(deltaTime)
        -- perf: skip for players; OnProcessMove already handles phasing each tick.
        -- OnUpdate is still needed for non-player PhaseGateUser entities (e.g. Exos use OnUpdate).
        if not self:isa("Player") then
            -- perf: skip when no phase gates exist on the map
            if GetPhaseGateCount() == 0 then
                return
            end
            SharedUpdate(self)
        end
    end
    
end

if Client then

    local function OnMessagePhase(message)
        PROFILE("PhaseGateUserMixin:OnMessagePhase")

        -- TODO: Is there a better way to do this?
        local phaseGate = Shared.GetEntity(message.phaseGateId)
        local phasedEnt = Shared.GetEntity(message.phasedEntityId)
        if not phaseGate then return end

        -- Need to keep this var updated so that client side effects work correctly
        phasedEnt.timeOfLastPhaseClient = Shared.GetTime()

        phaseGate:Phase(phasedEnt)
        local viewAngles = phasedEnt:GetViewAngles()

        -- Update view angles
        Client.SetYaw(viewAngles.yaw)
        Client.SetPitch(viewAngles.pitch)
    end

    Client.HookNetworkMessage("OnPhase", OnMessagePhase)

end

function PhaseGateUserMixin:GetCanPhase()
    if Server then
        return self:GetIsAlive() and Shared.GetTime() > self.timeOfLastPhase + kPhaseDelay and not GetConcedeSequenceActive()
    else
        return self:GetIsAlive() and Shared.GetTime() > self.timeOfLastPhase + kPhaseDelay
    end
    
end


function PhaseGateUserMixin:OnPhaseGateEntry(destinationOrigin)
    if Server and HasMixin(self, "LOS") then
        self:MarkNearbyDirtyImmediately()
    end
end
