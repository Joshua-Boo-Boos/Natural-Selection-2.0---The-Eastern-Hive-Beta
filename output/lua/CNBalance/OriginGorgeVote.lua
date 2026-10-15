-- Separate Alien electorate, using the existing yes/no vote HUD and keys.
-- Never register this as a public StartVote type: Marines cannot start or answer it.
if gOriginGorgeVoteLoaded then return end
gOriginGorgeVoteLoaded = true

Shared.RegisterNetworkMessage("OriginGorgeVote", {
    voteId = "integer", expireTime = "time", client_index = "integer"
})
Shared.RegisterNetworkMessage("OriginGorgeVoteChoice", { voteId = "integer", choice = "boolean" })
Shared.RegisterNetworkMessage("OriginGorgeVoteResults", {
    voteId = "integer", yesVotes = "integer (0 to 255)", noVotes = "integer (0 to 255)",
    requiredVotes = "integer (0 to 255)", state = "enum kVoteState"
})

if Client then
    local results
    if kPollWrapVoteTypes then kPollWrapVoteTypes.OriginGorgeVote = true end
    AddVoteStartListener("OriginGorgeVote", function()
        results = nil
        return "[Aliens - Origin Form]: Disallow bot Gorges to use Biomass Fetch?"
    end)
    Client.HookNetworkMessage("OriginGorgeVoteResults", function(message)
        if message.voteId == GetCurrentVoteId() then results = message end
    end)
    -- Vanilla predicts monotonically increasing tallies. This electorate can lose
    -- a vote when its player leaves Aliens, so display the authoritative count.
    local originalResults = GetVoteResults
    function GetVoteResults()
        if GetCurrentVoteId() >= 1000000000 then
            return results and results.yesVotes or 0, results and results.noVotes or 0, results and results.requiredVotes or 0
        end
        return originalResults()
    end
    local originalSend = SendVoteChoice
    function SendVoteChoice(choice)
        if GetCurrentVoteId() >= 1000000000 then
            Client.SendNetworkMessage("OriginGorgeVoteChoice", {voteId = GetCurrentVoteId(), choice = choice}, true)
        else
            originalSend(choice)
        end
    end
end

if not Server then return end

function OriginGorgeHasHumanAliens(team)
    for _, player in ipairs(GetEntitiesForTeam("Player", team:GetTeamNumber())) do
        local client = Server.GetOwner(player)
        if client and not client:GetIsVirtual() then return true end
    end
    return false
end

-- CETeamAnnounce carries at most 220 characters. (2026-10-14) A longer line is cut at the last whole word with
-- "..." rather than mid-word, so it never reads as if the text simply stopped.
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

local serial = 1000000000
local active
local originalAllowed = GetStartVoteAllowed
function GetStartVoteAllowed(voteName, client)
    if active then return kVoteCannotStartReason.VoteInProgress end
    return originalAllowed(voteName, client)
end

local function Humans(team)
    local result = {}
    for _, player in ipairs(GetEntitiesForTeam("Player", team:GetTeamNumber())) do
        local client = Server.GetOwner(player)
        if client and not client:GetIsVirtual() then result[client:GetUserId()] = player end
    end
    return result
end

local function SendElectorate(vote, name, data)
    -- Include former teammates for completion, so a team switch clears their HUD too.
    for _, player in ipairs(GetEntities("Player")) do
        local client = Server.GetOwner(player)
        if client and not client:GetIsVirtual() and vote.electorate[client:GetUserId()] then
            if player:GetTeamNumber() == vote.team:GetTeamNumber() or name == "VoteComplete" then
                Server.SendNetworkMessage(player, name, data, true)
            else
                Server.SendNetworkMessage(player, "VoteComplete", {voteId = vote.id}, true)
            end
        end
    end
end

local function Finish(vote, passed)
    vote.state.disallowed = passed
    vote.state.voteFinished = true
    -- (2026-10-14) Bot Gorges re-plan the moment the vote ends (OriginGorgeBuilder.lua), not on their next cycle.
    vote.state.voteFinishedTime = Shared.GetTime()
    SendElectorate(vote, "VoteComplete", {voteId = vote.id})
    OriginGorgeTeamMessage(vote.team, passed
        and "[Origin Form] Vote passed: bot Gorges cannot use Biomass Fetch this round."
        or "[Origin Form] Biomass Fetch remains enabled for bot Gorges this round.")
    active = nil
end

Server.HookNetworkMessage("OriginGorgeVoteChoice", function(client, message)
    local player = client:GetControllingPlayer()
    if active and Shared.GetTime() < active.expires and message.voteId == active.id
        and not client:GetIsVirtual() and player and player:GetTeamNumber() == active.team:GetTeamNumber()
        and active.electorate[client:GetUserId()] then
        active.votes[client:GetUserId()] = message.choice
    end
end)

-- Team-owned state is shared by all Gorge brains and invalidated on every round.
function GetOriginGorgeState(team)
    local rules = GetGamerules()
    if not rules or not rules:GetGameStarted() then return nil end
    local epoch = rules:GetGameStartTime()
    if not team.originGorgeState or team.originGorgeState.epoch ~= epoch then
        team.originGorgeState = {epoch = epoch, reservations = {}}
    end
    return team.originGorgeState
end

local nextUpdate = 0
Event.Hook("UpdateServer", function()
    local now = Shared.GetTime()
    if now < nextUpdate then return end
    nextUpdate = now + 0.5
    local rules = GetGamerules()
    local team = rules and rules:GetTeam(kTeam2Index)
    if not rules or not rules:GetGameStarted() or not team then
        if active then SendElectorate(active, "VoteComplete", {voteId = active.id}); active = nil end
        if team then team.originGorgeState = nil end
        return
    end
    local state = GetOriginGorgeState(team)
    if active and (active.state ~= state or not team:IsOriginForm()) then
        SendElectorate(active, "VoteComplete", {voteId = active.id})
        active = nil
    end
    if not team:IsOriginForm() then return end
    if not state.voteFinished and not active and not team:GetCommander() then
        local humans = Humans(team)
        local count = 0
        for _ in pairs(humans) do count = count + 1 end
        if count == 0 then
            state.voteFinished = true -- all-bot teams default to allowing fetch
        elseif originalAllowed("OriginGorgeVote", nil) == kVoteCannotStartReason.VoteAllowedToStart then
            serial = serial + 1
            active = {id = serial, team = team, state = state, electorate = humans,
                votes = {}, required = math.floor(count / 2) + 1, expires = now + 15}  -- (2026-10-14) 15-second vote
            SendElectorate(active, "OriginGorgeVote", {voteId = serial, expireTime = active.expires, client_index = 0})
        end
    end
    if active then
        local yes, no = 0, 0
        local humans = Humans(team)
        for id, choice in pairs(active.votes) do
            if humans[id] then
                if choice then yes = yes + 1 else no = no + 1 end
            end
        end
        local passed = yes >= active.required
        local done = passed or now >= active.expires
        SendElectorate(active, "OriginGorgeVoteResults", {voteId = active.id, yesVotes = yes, noVotes = no,
            requiredVotes = active.required, state = done and (passed and kVoteState.Passed or kVoteState.Failed) or kVoteState.InProgress})
        if done then Finish(active, passed) end
    end
end)
