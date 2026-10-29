-- Bot Biomass Fetch: a normal entry in the vote menu ("Bot Biomass Fetch").
--
-- (2026-10-28) ENABLED BY DEFAULT: every map starts with bot Gorges allowed to use Biomass Fetch whenever their plan
-- calls for it (OriginGorgeBuilder.lua).
--   * The vote DISABLES it, and can only be started BEFORE the round starts (pre-game / warm-up). Once passed, bot
--     Gorges may not use Biomass Fetch for the rest of the map - every round - until the map changes (a map change
--     reloads the server's Lua, so it is enabled again).
--   * Starting it once a round has started, or after it has already passed, does not start a vote; the player is told
--     why in chat.
-- (Before 2026-10-28 it was the other way round: disabled by default, a vote enabled it for one round.)
-- The helpers below (GetOriginGorgeState, OriginGorgeHasHumanAliens, OriginGorgeTeamMessage) are used by
-- OriginGorgeBuilder.lua and OriginGorgeFetchGate.lua.

if gOriginGorgeVoteLoaded then return end
gOriginGorgeVoteLoaded = true

local kVoteName = "VoteBotBiomassFetch"
local kExecuteVoteDelay = 2

RegisterVoteType(kVoteName, { })

if Client then

    if kPollWrapVoteTypes then kPollWrapVoteTypes[kVoteName] = true end

    AddVoteSetupCallback(function(voteMenu)
        voteMenu:AddMainMenuOption("Bot Biomass Fetch", nil, function()
            AttemptToStartVote(kVoteName, { })
        end)
        AddVoteStartListener(kVoteName, function()
            return "Disable bot Gorges' Biomass Fetch for the rest of this map?"
        end)
    end)

end

if not Server then return end

function OriginGorgeHasHumanAliens(team)
    for _, player in ipairs(GetEntitiesForTeam("Player", team:GetTeamNumber())) do
        local client = Server.GetOwner(player)
        if client and not client:GetIsVirtual() then return true end
    end
    return false
end

-- CETeamAnnounce carries at most 220 characters. A longer line is cut at the last whole word with "...".
local kTeamMessageMax = 220
local function FitTeamMessage(message)
    if #message <= kTeamMessageMax then return message end
    local cut = string.sub(message, 1, kTeamMessageMax - 3)
    local lastSpace = cut:match(".*()%s")
    if lastSpace and lastSpace > kTeamMessageMax / 2 then
        cut = string.sub(cut, 1, lastSpace - 1)
    end
    return cut .. "..."
end

function OriginGorgeTeamMessage(team, message)
    message = FitTeamMessage(message)
    for _, player in ipairs(GetEntitiesForTeam("Player", team:GetTeamNumber())) do
        if not player:GetIsVirtual() then
            Server.SendNetworkMessage(player, "CETeamAnnounce", {message = message}, true)
        end
    end
end

-- True once the vote has passed this map: bot Biomass Fetch is off until the map changes (the server's Lua reloads).
local disabledForMap = false

local function GetRoundStarted()
    local rules = GetGamerules()
    return rules ~= nil and rules:GetGameStarted()
end

-- Used by OriginGorgeBuilder.lua's first-Hive rule too: allowed unless the vote has disabled it for this map.
function OriginGorgeBotFetchAllowed()
    return not disabledForMap
end

local function ApplyToState(state, team)
    state.voteFinished = true   -- nothing to wait for any more: the vote is optional
    state.disallowed = disabledForMap
end

-- Team-owned state shared by all Gorge brains, invalidated every round.
function GetOriginGorgeState(team)
    local rules = GetGamerules()
    if not rules or not rules:GetGameStarted() then return nil end
    local epoch = rules:GetGameStartTime()
    if not team.originGorgeState or team.originGorgeState.epoch ~= epoch then
        team.originGorgeState = {epoch = epoch, reservations = {}}
    end
    -- Bot brains call this constantly; refresh at most once a second (OriginGorgeHasHumanAliens allocates).
    local state = team.originGorgeState
    local now = Shared.GetTime()
    if not state.nextApply or now >= state.nextApply then
        state.nextApply = now + 1
        ApplyToState(state, team)
    end
    return state
end

local function Chat(target, text)
    local message = BuildChatMessage(false, "Vote", -1, kTeamReadyRoom, kNeutralTeamType, text)
    if target then
        Server.SendNetworkMessage(target, "Chat", message, true)
    else
        Server.SendNetworkMessage("Chat", message, true)
    end
end

-- Already disabled, or the round has started: do not start a vote, just say why in chat.
Server.HookNetworkMessage(kVoteName, function(client, message)
    if disabledForMap then
        Chat(client, "Bot Biomass Fetch is already disabled for this map.")
        return
    end
    if GetRoundStarted() then
        Chat(client, "Bot Biomass Fetch can only be voted off before the round starts.")
        return
    end
    StartVote(kVoteName, client, message)
end)

SetVoteSuccessfulCallback(kVoteName, kExecuteVoteDelay, function()
    if GetRoundStarted() then
        Chat(nil, "Vote passed, but the round had already started: bot Biomass Fetch stays enabled.")
        return
    end
    disabledForMap = true
    Chat(nil, "Vote passed: bot Gorges can't use Biomass Fetch for the rest of this map.")
    local rules = GetGamerules()
    local team = rules and rules:GetTeam(kTeam2Index)
    local state = team and team.originGorgeState
    if state then
        ApplyToState(state, team)
        -- Bot Gorges re-plan straight away (OriginGorgeBuilder.lua watches voteFinishedTime).
        state.voteFinishedTime = Shared.GetTime()
    end
end)
