if Client then

    -- =========================================================================
    -- NS2.0-TEH SoundEffect — full client-side override
    --
    -- The vanilla SharedUpdate calls SetVolume / Start / Stop on FMOD handles
    -- that the C++ engine has silently recycled (voice-pool exhaustion).
    -- The C++ wrapper logs the error BEFORE raising it to Lua, so pcall alone
    -- cannot suppress the log spam.
    --
    -- Fix:
    --   1. Replace vanilla SharedUpdate entirely; wrap every FMOD call in
    --      pcall.  On first failure, nil the instance and enter a 1-second
    --      cooldown — zero FMOD calls during cooldown = zero log entries.
    --   2. Only run from OnUpdate (disable OnProcessMove / OnProcessSpectate
    --      on client) to cut call frequency by ~3×.
    --   3. Apply the volume slider to ALL ns2plus.fev sounds (not just comm).
    -- =========================================================================

    local kHandleCooldown  = 1.0   -- seconds before retrying after a dead handle
    local kBalanceInterval = 0.2   -- volume-balance check rate (~5 Hz)

    -- Safely destroy an FMOD instance (dead handles won't crash).
    local function SafeDestroy(self)
        local inst = self.soundEffectInstance
        if inst then
            pcall(function() Client.DestroySoundEffect(inst) end)
            self.soundEffectInstance = nil
        end
    end

    function SoundEffect:OnDestroy()
        SafeDestroy(self)
    end

    -- ── Complete replacement of the vanilla client SharedUpdate ──────
    local function SafeSharedUpdate(self)
        PROFILE("SoundEffect:SafeSharedUpdate")

        -- Predictor check (same as vanilla)
        if self.predictorId ~= Entity.invalidId then
            local predictor = Shared.GetEntity(self.predictorId)
            if predictor
               and Client.GetLocalPlayer() == predictor
               and Client.GetIsControllingPlayer()
               and self:GetParent() == predictor then
                return
            end
        end

        -- Skip ALL FMOD work while cooling down after a dead-handle detection
        local now = Shared.GetTime()
        if self._sndCooldown and now < self._sndCooldown then
            return
        end
        self._sndCooldown = nil

        -- ── Asset changed: destroy old instance, create new ──────────
        if self.clientAssetIndex ~= self.assetIndex then

            SafeDestroy(self)
            self.clientAssetIndex = self.assetIndex
            self.clientPlaying    = nil
            self.clientStartTime  = nil

            if self.assetIndex ~= 0 then

                local ok, inst = pcall(function()
                    return Client.CreateSoundEffect(self.assetIndex)
                end)

                if ok and inst then
                    self.soundEffectInstance = inst
                    local ok2 = pcall(function() inst:SetParent(self:GetId()) end)
                    if not ok2 then
                        SafeDestroy(self)
                        self._sndCooldown = now + kHandleCooldown
                        return
                    end
                elseif not ok then
                    self.soundEffectInstance = nil
                    self._sndCooldown = now + kHandleCooldown
                    return
                end
                -- ok but nil inst: asset missing; leave instance nil, no cooldown
            end
        end

        -- ── Play / stop state changes ────────────────────────────────
        if self.assetIndex ~= 0 and self.soundEffectInstance then
            if self.clientPlaying ~= self.playing
               or self.clientStartTime ~= self.startTime then

                self.clientPlaying   = self.playing
                self.clientStartTime = self.startTime

                if self.playing then
                    local ok = pcall(function()
                        self.soundEffectInstance:Start()
                        self.soundEffectInstance:SetVolume(self.volume)
                    end)

                    if not ok then
                        SafeDestroy(self)
                        self._sndCooldown    = now + kHandleCooldown
                        self.clientPlaying   = nil
                        self.clientStartTime = nil
                        return
                    end

                    -- Flush queued SetParameter calls
                    if self.clientSetParameters then
                        for c = 1, #self.clientSetParameters do
                            local p = self.clientSetParameters[c]
                            pcall(function()
                                self.soundEffectInstance:SetParameter(
                                    p.name, p.value, p.speed)
                            end)
                        end
                        self.clientSetParameters = nil
                    end
                else
                    local ok = pcall(function()
                        self.soundEffectInstance:Stop()
                    end)
                    if not ok then
                        SafeDestroy(self)
                        self._sndCooldown = now + kHandleCooldown
                        return
                    end
                end
            end
        end

        -- ── Positional update ────────────────────────────────────────
        if self.soundEffectInstance and self.clientPositional ~= self.positional then
            local ok = pcall(function()
                self.soundEffectInstance:SetPositional(self.positional)
            end)
            if ok then
                self.clientPositional = self.positional
            else
                SafeDestroy(self)
                self._sndCooldown = now + kHandleCooldown
            end
        end
    end

    -- ── OnInitialized: flag ns2plus.fev sounds for volume balancing ──
    local baseOnInitialized = SoundEffect.OnInitialized
    function SoundEffect:OnInitialized()
        baseOnInitialized(self)

        local assetName = Shared.GetSoundName(self.assetIndex)
        self.balanceVoice  = assetName and string.find(assetName, "ns2plus.fev") ~= nil
        self._balVol       = nil
        self._balNextCheck = 0
    end

    -- ── Volume-balance for NS2.0-TEH entity-based sounds ────────────
    local function CustomBalanceVoice(self)
        if not self.balanceVoice then return end
        if not self.playing then
            self._balVol = nil
            return
        end

        local inst = self.soundEffectInstance
        if not inst then
            self._balVol = nil
            return
        end

        local now = Shared.GetTime()
        if now < self._balNextCheck then return end
        self._balNextCheck = now + kBalanceInterval

        local volume = OptionsDialogUI_GetSoundVolume() / 100
        volume = volume * (gMuteCustomVoices and 0 or 1)

        if self._balVol == volume then return end
        self._balVol = volume

        local ok = pcall(function() inst:SetVolume(volume) end)
        if not ok then
            SafeDestroy(self)
            self._sndCooldown = Shared.GetTime() + kHandleCooldown
            self._balVol = nil
        end
    end

    -- ── Entry points ─────────────────────────────────────────────────

    -- OnUpdate: full sound management + volume balancing
    function SoundEffect:OnUpdate(deltaTime)
        SafeSharedUpdate(self)
        CustomBalanceVoice(self)
    end

    -- OnProcessMove / OnProcessSpectate: restore base processing so that
    -- action-driven sounds (e.g. Gorge taunt) still trigger, plus run
    -- custom volume balancing.  The heavy FMOD retry logic stays in OnUpdate.
    local baseOnProcessMove = SoundEffect.OnProcessMove
    function SoundEffect:OnProcessMove()
        if baseOnProcessMove then
            baseOnProcessMove(self)
        end
        CustomBalanceVoice(self)
    end

    local baseOnProcessSpectate = SoundEffect.OnProcessSpectate
    function SoundEffect:OnProcessSpectate()
        if baseOnProcessSpectate then
            baseOnProcessSpectate(self)
        end
        CustomBalanceVoice(self)
    end

    -- ── Volume scaling for one-shot NS2.0-TEH sounds ────────────────
    local function GetVolume(soundEffectName, volume)
        if soundEffectName
           and string.find(soundEffectName, "ns2plus.fev") ~= nil
        then
            volume = (volume or 0.8) * OptionsDialogUI_GetSoundVolume() / 100
        end
        return volume
    end

    local baseStartSoundEffectAtOrigin = StartSoundEffectAtOrigin
    function StartSoundEffectAtOrigin(name, origin, volume, predictor)
        baseStartSoundEffectAtOrigin(name, origin, GetVolume(name, volume), predictor)
    end

    local baseStartSoundEffectOnEntity = StartSoundEffectOnEntity
    function StartSoundEffectOnEntity(name, entity, volume, predictor)
        baseStartSoundEffectOnEntity(name, entity, GetVolume(name, volume), predictor)
    end

    local baseStartSoundEffect = StartSoundEffect
    function StartSoundEffect(name, volume, pitch)
        baseStartSoundEffect(name, GetVolume(name, volume), pitch)
    end

    local baseStartSoundEffectForPlayer = StartSoundEffectForPlayer
    function StartSoundEffectForPlayer(name, player, volume)
        baseStartSoundEffectForPlayer(name, player, GetVolume(name, volume))
    end

end
