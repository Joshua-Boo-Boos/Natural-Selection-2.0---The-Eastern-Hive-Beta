-- ======= NS2.0-TEH-Beta: CNBalance/CommMapTools_Shared.lua =======
--
-- SHARED half of two features (loaded on BOTH client and server via a "post" hook on
-- lua/NetworkMessages.lua, so Shared.RegisterNetworkMessage is available):
--
--   1) All-player map PING (default N): any player pings the world spot they are aiming at,
--      once every 5s. Team-mates (only) see a beacon with the pinger's NAME under it in team
--      colour. World-anchored, visible through walls, auto-fades.
--
--   2) Commander map DRAWING: while the commander holds the fullscreen map open (C), LMB draws,
--      RMB erases, MMB clears. Only the drawer's OWN team sees it. Strokes are RED. The drawing
--      persists (server-stored) and is replayed to any team-mate who opens their map.
--
-- Everything is done with fire-and-forget NETWORK MESSAGES (not networked entity vars), so this
-- adds ZERO networked classes/vars - it cannot bump the engine's networked-class/var budget.
--
-- Client and server are separate Lua VMs; this file runs in each, so the config table below and
-- the message registrations exist identically on both sides.

-- Shared tuning / constants (same values in both VMs because this one file defines them in both).
kGCommMap = kGCommMap or {}
kGCommMap.PingCooldown   = 5.0    -- seconds between pings, per player (server-authoritative)
kGCommMap.PingDuration   = 4.0    -- seconds a ping beacon stays on screen
kGCommMap.PingRange      = 1000   -- max world-trace distance for locating the pinged spot
kGCommMap.EraseRadius    = 2.688  -- world units: eraser radius (2.24, then +20% -> 2.688)
kGCommMap.MinDrawStep    = 0.35   -- min world distance between stored draw points (sampling)
kGCommMap.MaxDrawPoints  = 3000   -- max drawn points per team. Each renders as ~1 GUIItem (a line
                                  -- segment), and NS2 hard-caps the WHOLE GUI at 5000 items, so this
                                  -- must stay well under that to leave room for the rest of the HUD.
kGCommMap.DrawColour     = Color(0.1, 1, 0.1, 1)   -- commander drawing is always GREEN, both teams

-- ---- Network messages -------------------------------------------------------------------------
-- Positions use the built-in "vector" field (full precision, mirrors the stock CommanderPing).

-- Client -> Server: "I want to ping the spot at <position>." Server enforces the cooldown.
Shared.RegisterNetworkMessage( "GC_Ping", { position = "vector" } )

-- Server -> Client (team only): "show a ping from <clientIndex> at <position>."
Shared.RegisterNetworkMessage( "GC_PingShow", {
    clientIndex = "integer",
    position    = "vector"
} )

-- Client -> Server: one draw sample from the commander. penUp = true marks the end of a stroke
-- (so separate strokes are not joined by a line); erase = true means remove nearby points.
-- Server -> Client (team only): apply the same sample to the local drawing. Same shape both ways.
local kDrawMsg = {
    position = "vector",
    erase    = "boolean",
    penUp    = "boolean"
}
Shared.RegisterNetworkMessage( "GC_Draw",     kDrawMsg )   -- C -> S
Shared.RegisterNetworkMessage( "GC_DrawShow", kDrawMsg )   -- S -> C (team)

-- Clear everything. C -> S (commander pressed MMB) and S -> C (tell the team to wipe local).
Shared.RegisterNetworkMessage( "GC_DrawClear", {} )

-- Client -> Server: "I just opened my map - send me the current team drawing." Server replays
-- the stored points to that one client (GC_DrawClear then a GC_DrawShow per stored point).
Shared.RegisterNetworkMessage( "GC_DrawRequest", {} )
