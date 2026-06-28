if Client then

    -- Alien vision is an alien-only screen effect. Marine-team spectators must
    -- never see it - this includes respawning marines, who are MarineSpectators
    -- (a marine-team spectator) for the whole time they are being spawned by an
    -- Infantry Portal. Without this guard such a player could press the toggle
    -- (F) and turn Alien Vision on while spawning.
    local function GetSpectatorCanUseAlienVision(self)
        return not (self.GetTeamType and self:GetTeamType() == kMarineTeamType)
    end

    local function SetSpectatorAlienVision(self, state)
        state = state == true

        if self.spectatorAlienVisionOn ~= state then
            self.spectatorAlienVisionOn = state

            -- Purely a local screen effect. Only trigger feedback for the local spectator so we
            -- never touch another (possibly owner-less) spectator entity's effect pipeline.
            if self == Client.GetLocalPlayer() then
                if state then
                    self.spectatorAlienVisionTime = Shared.GetTime()
                    self:TriggerEffects("alien_vision_on")
                else
                    self.spectatorAlienVisionEndTime = Shared.GetTime()
                    self:TriggerEffects("alien_vision_off")
                end
            end
        end
    end

    local baseOnProcessMove = Spectator.OnProcessMove
    function Spectator:OnProcessMove(input)
        baseOnProcessMove(self, input)

        -- The alien-vision toggle is a client-only, local-only screen effect. Bail out for any
        -- non-local spectator so this never runs against an entity without a controlling client
        -- (an owner-less AlienSpectator), which is what previously produced a "no owner" error.
        if self ~= Client.GetLocalPlayer() then
            return
        end

        -- Marine-team spectators (e.g. respawning marines) cannot use alien vision.
        -- Force it off and ignore the toggle key for them.
        if not GetSpectatorCanUseAlienVision(self) then
            if self.spectatorAlienVisionOn then
                SetSpectatorAlienVision(self, false)
            end
            self.spectatorAlienVisionLastFrame = bit.band(input.commands, Move.ToggleFlashlight) ~= 0
            return
        end

        local darkVisionPressed = bit.band(input.commands, Move.ToggleFlashlight) ~= 0
        if not self.spectatorAlienVisionLastFrame and darkVisionPressed then
            SetSpectatorAlienVision(self, not self.spectatorAlienVisionOn)
        end

        self.spectatorAlienVisionLastFrame = darkVisionPressed
    end

    local baseUpdateClientEffects = Spectator.UpdateClientEffects
    function Spectator:UpdateClientEffects(deltaTime, isLocal)
        baseUpdateClientEffects(self, deltaTime, isLocal)

        if not isLocal then
            return
        end

        local useShader = Player.screenEffects.darkVision
        if not useShader then
            return
        end

        -- Marine-team spectators (e.g. respawning marines) never get alien vision.
        if not GetSpectatorCanUseAlienVision(self) then
            self.spectatorAlienVisionOn = false
            useShader:SetActive(false)
            return
        end

        if self.spectatorAlienVisionOn then
            self.spectatorAlienVisionTime = self.spectatorAlienVisionTime or Shared.GetTime()
            useShader:SetActive(true)
            useShader:SetParameter("startTime", self.spectatorAlienVisionTime)
            useShader:SetParameter("time", Shared.GetTime())
            useShader:SetParameter("amount", 1)
            if avType ~= nil then
                useShader:SetParameter("avType", avType)
            end
        else
            useShader:SetActive(false)
        end
    end

end
