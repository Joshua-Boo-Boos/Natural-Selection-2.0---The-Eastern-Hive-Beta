-- ======= NS2.0-TEH-Beta: CNBalance/CommMapTools_Server.lua =======
--
-- SERVER half of the ping + commander-drawing features. Loaded via a "post" hook on
-- lua/NS2Gamerules.lua - which loads AFTER NetworkMessages.lua (so the shared file has already
-- registered the messages) and where NS2Gamerules:ResetGame is defined (so wrapping it is safe).
--
-- Responsibilities:
--   * Ping: enforce the 5s-per-player cooldown, then relay the ping to the pinger's TEAM only.
--   * Draw: accept draw / erase samples from a team's COMMANDER only, keep the authoritative
--     per-team stroke list (a plain Lua table - NOT networked vars), relay to the team, and
--     replay the stored drawing to any team-mate who opens their map.

if not Server then return end

-- Per-player ping cooldown, keyed by Steam id (survives entity churn). time of last accepted ping.
local gLastPing = {}

-- Authoritative per-team drawing: gDraw[teamNumber] = { { pos = Vector, penUp = bool }, ... }
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

-- Count only ACTUAL drawn points (not the penUp break markers that erasing leaves behind), so the
-- cap frees up as you erase - each rendered point is one such entry.
local function CountDrawPoints(list)
    local n = 0
    for i = 1, #list do
        if list[i].pos then n = n + 1 end
    end
    return n
end

local function EraseNear(list, position)
    local rSq = kGCommMap.EraseRadius * kGCommMap.EraseRadius
    for i = 1, #list do
        local p = list[i].pos
        if p then
            local dx, dz = p.x - position.x, p.z - position.z
            if (dx * dx + dz * dz) <= rSq then
                -- Turn the erased point into a stroke BREAK, don't delete it. Deleting would make
                -- its neighbours adjacent and the renderer would draw a line bridging the gap (the
                -- "pulled away" artefact). A break removes the dot and severs the line both sides.
                list[i] = { penUp = true }
            end
        end
    end
end

Server.HookNetworkMessage("GC_Draw", function(client, message)

    local teamNumber = GetCommanderTeam(client)
    if not teamNumber then return end

    local list = gDraw[teamNumber]

    local relay = true
    if message.erase then
        EraseNear(list, message.position)
    elseif message.penUp then
        -- Stroke break marker: only store one if the last point wasn't already a break.
        local last = list[#list]
        if last and not last.penUp then
            list[#list + 1] = { penUp = true }
        end
    else
        -- Cap on the number of actual POINTS (not #list): erasing turns points into penUp breaks
        -- that stay in the list, so gating on #list would keep rejecting new points after erasing
        -- until a full Clear. Counting real points means erasing frees the cap again.
        if CountDrawPoints(list) < kGCommMap.MaxDrawPoints then
            list[#list + 1] = { pos = message.position, penUp = false }
        else
            -- Cap reached: do NOT relay a point we can't store, else it would show while drawing
            -- but vanish on the next map re-open (the replay only has the stored points).
            relay = false
        end
    end

    -- Relay the exact same sample to the whole team so their local drawing stays in sync.
    if relay then
        SendToTeam(teamNumber, "GC_DrawShow", {
            position = message.position,
            erase    = message.erase == true,
            penUp    = message.penUp == true,
        })
    end
end)

Server.HookNetworkMessage("GC_DrawClear", function(client, message)
    local teamNumber = GetCommanderTeam(client)
    if not teamNumber then return end
    gDraw[teamNumber] = {}
    SendToTeam(teamNumber, "GC_DrawClear", {})
end)

-- A team-mate opened their map: wipe their local copy, then replay the stored team drawing to
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
        Server.SendNetworkMessage(player, "GC_DrawShow", {
            position = entry.pos or Vector(0, 0, 0),
            erase    = false,
            penUp    = entry.penUp == true,
        }, true)
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
