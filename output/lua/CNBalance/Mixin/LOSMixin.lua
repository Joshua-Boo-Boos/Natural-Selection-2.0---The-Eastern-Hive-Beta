if Server then
    
    
    function LOSMixin:GetLastViewer()

        if self.lastViewerId and self.lastViewerId ~= Entity.invalidId then

            local viewer = Shared.GetEntity(self.lastViewerId)

            if viewer and not HasMixin(viewer, "LOS") then

                Shared.Message(string.format("%s: %s added as a viewer without having LOS mixin", ToString(self), ToString(viewer)))
                self.lastViewerId = Entity.invalidId
                return nil
            end

            return viewer

        end

    end

end

if Server then

    -- Perf: vanilla drives SharedUpdate from every entity update AND every
    -- player move tick; its internal dirty/scan gates sit at 0.2s. This
    -- outer gate caps the driver itself: players 0.25s, non-players 0.4s.
    -- Immediate paths (beacon, phase gate, tunnel, teleport, kill) call
    -- UnsightImmediately/MarkNearbyDirty directly and are NOT affected.
    local kPlayerLOSGateInterval = 0.25
    local kOtherLOSGateInterval = 0.4

    local baseLOSOnUpdate = LOSMixin.OnUpdate
    local baseLOSOnProcessMove = LOSMixin.OnProcessMove

    local function LOSGateExpired(self)

        local now = Shared.GetTime()
        local interval = self:isa("Player") and kPlayerLOSGateInterval or kOtherLOSGateInterval

        if (self.timeLastLOSGate or 0) + interval > now then
            return false
        end

        self.timeLastLOSGate = now
        return true

    end

    function LOSMixin:OnUpdate(deltaTime)
        if LOSGateExpired(self) then
            baseLOSOnUpdate(self, deltaTime)
        end
    end

    function LOSMixin:OnProcessMove(input)
        if LOSGateExpired(self) then
            baseLOSOnProcessMove(self, input)
        end
    end

end
