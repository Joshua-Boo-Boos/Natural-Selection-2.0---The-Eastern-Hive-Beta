-- ======= NS2.0-TEH-Beta: CNBalance/CommMapTools_Server.lua =======
--
-- SERVER half of the ping + commander order-icon features. Loaded via a "post" hook on
-- lua/NS2Gamerules.lua - which loads AFTER NetworkMessages.lua (so the shared file has already
-- registered the messages) and where NS2Gamerules:ResetGame is defined (so wrapping it is safe).
--
-- Responsibilities:
--   * Ping: enforce the 5s-per-player cooldown, then relay the ping to the pinger's TEAM only.
--   * Order icons: accept icon placements / clears from a team's COMMANDER only, keep the
--     authoritative per-team icon list (a plain Lua table - NOT networked vars), relay to the team,
--     and replay the stored icons to any team-mate who opens their map.

if not Server then return end

-- Per-player ping cooldown, keyed by Steam id (survives entity churn). time of last accepted ping.
local gLastPing = {}

-- Authoritative per-team order icons: gDraw[teamNumber] = { { pos = Vector, order = int }, ... }
local gDraw = {
    [kTeam1Index] = {},
    [kTeam2Index] = {},
}

local function IsPlayingTeam(teamNumber)
    return teamNumber == kTeam1Index or teamNumber == kTeam2Index
end

-- Send a message to every (human or bot) player on a team.
local function SendToTeam(teamNumber, messageName, message)
    for _, player in ipairs(GetEntitiesForTeam("Player", teamNumber)) do
        Server.SendNetworkMessage(player, messageName, message, true)
    end
end

-- ---- Ping ------------------------------------------------------------------------------------
Server.HookNetworkMessage("GC_Ping", function(client, message)

    if not client then return end
    local player = client.GetControllingPlayer and client:GetControllingPlayer()
    if not player then return end

    local teamNumber = player:GetTeamNumber()
    if not IsPlayingTeam(teamNumber) then return end   -- ready room / spectators can't ping

    -- 5s cooldown per player (server-authoritative; the client also self-limits for feedback).
    local now = Shared.GetTime()
    local id  = client.GetUserId and client:GetUserId() or client
    if gLastPing[id] and (now - gLastPing[id]) < kGCommMap.PingCooldown then
        return
    end
    gLastPing[id] = now

    SendToTeam(teamNumber, "GC_PingShow", {
        clientIndex = player:GetClientIndex(),
        position    = message.position,
    })
end)

-- ---- Draw ------------------------------------------------------------------------------------
-- Only a team's commander may draw. Returns the team number if allowed, else nil.
local function GetCommanderTeam(client)
    local player = client and client.GetControllingPlayer and client:GetControllingPlayer()
    if not player or not player.isa or not player:isa("Commander") then return nil end
    local teamNumber = player:GetTeamNumber()
    if not IsPlayingTeam(teamNumber) then return nil end
    return teamNumber
end

Server.HookNetworkMessage("GC_Icon", function(client, message)

    local teamNumber = GetCommanderTeam(client)
    if not teamNumber then return end

    local orders = kGCommMap.Orders[teamNumber]
    local order = message.order
    if not orders or not orders[order] then return end

    local list = gDraw[teamNumber]
    if #list >= kGCommMap.MaxIcons then return end   -- cap reached: don't relay what we can't store

    local size = kGCommMap.IconSizes[message.size] and message.size or kGCommMap.DefaultIconSize
    list[#list + 1] = { pos = message.position, order = order, size = size }
    SendToTeam(teamNumber, "GC_IconShow", { position = message.position, order = order, size = size })
end)

Server.HookNetworkMessage("GC_DrawClear", function(client, message)
    local teamNumber = GetCommanderTeam(client)
    if not teamNumber then return end
    gDraw[teamNumber] = {}
    SendToTeam(teamNumber, "GC_DrawClear", {})
end)

-- A team-mate opened their map: wipe their local copy, then replay the stored team icons to
-- just that client so it persists across map re-opens, respawns and late joins.
Server.HookNetworkMessage("GC_DrawRequest", function(client, message)
    if not client then return end
    local player = client.GetControllingPlayer and client:GetControllingPlayer()
    if not player then return end
    local teamNumber = player:GetTeamNumber()
    if not IsPlayingTeam(teamNumber) then return end

    Server.SendNetworkMessage(player, "GC_DrawClear", {}, true)

    local list = gDraw[teamNumber]
    for i = 1, #list do
        local entry = list[i]
        Server.SendNetworkMessage(player, "GC_IconShow", { position = entry.pos, order = entry.order, size = entry.size }, true)
    end
end)

local function WipeAllDrawings()
    gDraw = { [kTeam1Index] = {}, [kTeam2Index] = {} }
    SendToTeam(kTeam1Index, "GC_DrawClear", {})
    SendToTeam(kTeam2Index, "GC_DrawClear", {})
end

-- Wipe both teams' drawings when a round resets so orders don't carry across rounds.
local baseResetGame = NS2Gamerules.ResetGame
function NS2Gamerules:ResetGame()
    baseResetGame(self)
    WipeAllDrawings()
end

-- Wipe the instant the round ENDS too, so the orders don't linger on the ready-room map that
-- players open after a win/draw (ResetGame only fires later, at the next round's reset).
local baseSetGameState = NS2Gamerules.SetGameState
function NS2Gamerules:SetGameState(state)
    baseSetGameState(self, state)
    if kGameState and (state == kGameState.Team1Won or state == kGameState.Team2Won
       or state == kGameState.Draw) then
        WipeAllDrawings()
    end
end
