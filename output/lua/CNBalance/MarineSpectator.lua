
-- perf: pre-allocate message tables to avoid garbage every callback
local kWaveSpawnMsg = { time = 0 }
local kRespawningMsg = { isRespawning = true }

local function UpdateWaveTime(self)

    if self:GetIsDestroyed() then
        return false
    end

    local team = self:GetTeam()
    assert(team:GetIsMarineTeam(), team.teamName)

    local entryTime = self:GetRespawnQueueEntryTime() or 0

    -- perf: only send network message when the value actually changes
    if self.timeWaveSpawnEnd ~= entryTime then
        self.timeWaveSpawnEnd = entryTime
        kWaveSpawnMsg.time = entryTime
        Server.SendNetworkMessage(Server.GetOwner(self), "SetTimeWaveSpawnEnds", kWaveSpawnMsg, true)
    end

    if not self.sentRespawnMessage then
        Server.SendNetworkMessage(Server.GetOwner(self), "SetIsRespawning", kRespawningMsg, true)
        self.sentRespawnMessage = true
    end

    return true
end

local baseOnInitialized = MarineSpectator.OnInitialized
function MarineSpectator:OnInitialized()
    baseOnInitialized(self)
    if Server then
        -- fix: send first update immediately so client sees wave timer right away,
        -- then poll at 1s interval (client counts down locally using Shared.GetTime())
        UpdateWaveTime(self)
        self:AddTimedCallback(UpdateWaveTime, 1.0)
    end
end

if Server then
    function MarineSpectator:GetDesiredSpawnPoint()
        return self.desiredSpawnPoint
    end
    
    local onCopyPlayerDataFrom = MarineSpectator.CopyPlayerDataFrom
    function MarineSpectator:CopyPlayerDataFrom( player )
        onCopyPlayerDataFrom(self,player)
        self.primaryRespawn = player.primaryRespawn
        self.secondaryRespawn = player.secondaryRespawn
        self.meleeRespawn = player.meleeRespawn
    end


    function MarineSpectator:Replace(mapName, newTeamNumber, preserveWeapons, atOrigin, extraValues, _)

        Server.SendNetworkMessage(Server.GetOwner(self), "SetIsRespawning", { isRespawning = false }, true)
        return TeamSpectator.Replace(self, mapName, newTeamNumber, preserveWeapons, atOrigin, extraValues, _)

    end
end
