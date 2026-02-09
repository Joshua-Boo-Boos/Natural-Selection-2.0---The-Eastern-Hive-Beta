if Client then

    local baseOnInitialized = SoundEffect.OnInitialized
    function SoundEffect:OnInitialized()
        baseOnInitialized(self)

        local assetName = Shared.GetSoundName(self.assetIndex)
        local isNs2Plus = assetName and string.find(assetName, "ns2plus.fev") ~= nil
        local isComm = assetName and string.find(assetName, "/comm/") ~= nil

        -- ONLY balance actual commander/comm sounds
        self.balanceVoice = isNs2Plus and isComm
    end

    local function CustomBalanceVoice(self)
        if not self.balanceVoice then return end
        if not (self.playing and self.soundEffectInstance) then return end

        local volume = OptionsDialogUI_GetSoundVolume() / 100
        volume = volume * (gMuteCustomVoices and 0 or 1)

        if self.volume ~= volume then
            self.volume = volume
            -- Defensive: instance may die between frames
            pcall(function()
                self.soundEffectInstance:SetVolume(volume)
            end)
        end
    end

    local baseOnUpdate = SoundEffect.OnUpdate
    function SoundEffect:OnUpdate(deltaTime)
        baseOnUpdate(self)
        CustomBalanceVoice(self)
    end

    local baseOnProcessMove = SoundEffect.OnProcessMove
    function SoundEffect:OnProcessMove()
        baseOnProcessMove(self)
        CustomBalanceVoice(self)
    end

    local baseOnProcessSpectate = SoundEffect.OnProcessSpectate
    function SoundEffect:OnProcessSpectate()
        baseOnProcessSpectate(self)
        CustomBalanceVoice(self)
    end

    -- Apply volume scaling ONLY to comm sounds (not weapons/abilities)
    local function GetVolume(soundEffectName, volume)
        if soundEffectName
           and string.find(soundEffectName, "ns2plus.fev") ~= nil
           and string.find(soundEffectName, "/comm/") ~= nil
        then
            volume = (volume or 1) * OptionsDialogUI_GetSoundVolume() / 100
        end
        return volume
    end

    -- Sound hooks
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
