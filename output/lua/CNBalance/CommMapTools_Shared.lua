-- ======= NS2.0-TEH-Beta: CNBalance/CommMapTools_Shared.lua =======
--
-- SHARED half of two features (loaded on BOTH client and server via a "post" hook on
-- lua/NetworkMessages.lua, so Shared.RegisterNetworkMessage is available):
--
--   1) All-player map PING (default N): any player pings the world spot they are aiming at,
--      once every 5s. Team-mates (only) see a beacon with the pinger's NAME under it in team
--      colour. World-anchored, visible through walls, auto-fades.
--
--   2) Commander map ORDER ICONS: while the commander has the fullscreen map open (C), MMB opens an
--      order wheel, LMB places the selected order icon, RMB clears all icons. Only the commander's
--      OWN team sees them. Each icon shows a small count (top-right) and the order name (below), in
--      green. Icons persist (server-stored) and are replayed to any team-mate who opens their map.
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
kGCommMap.MaxIcons       = 60     -- max order icons per team (each is ~3 GUIItems on every team-mate's map)
kGCommMap.DrawColour     = Color(0.1, 1, 0.1, 1)   -- order icon text + count are always GREEN, both teams

-- Icon sizes the commander scrolls between (index 3 = Normal is the default). scale multiplies the
-- on-map icon AND its text.
kGCommMap.IconSizes = {
    { name = "Minimum", scale = 0.6 },
    { name = "Small",   scale = 0.8 },
    { name = "Normal",  scale = 1.0 },
    { name = "Big",     scale = 1.3 },
    { name = "Largest", scale = 1.6 },
}
kGCommMap.DefaultIconSize = 3

-- Order wheel entries per team (index is what goes over the network). techId names are resolved
-- lazily on the client (for the button-atlas icon), so this file doesn't depend on kTechId load order.
kGCommMap.Orders = {
    [2] = {   -- Aliens (the orders the Alien Commander can give alien players)
        { name = "Move",   tech = "Move" },
        { name = "Attack", tech = "Attack" },
        { name = "Defend", tech = "Defend" },
        { name = "Build",  tech = "Construct" },
        { name = "Heal",   tech = "HealWave" },
    },
    [1] = {   -- Marines
        { name = "Move",   tech = "Move" },
        { name = "Attack", tech = "Attack" },
        { name = "Defend", tech = "Defend" },
        { name = "Build",  tech = "Construct" },
        { name = "Weld",   tech = "Weld" },
    },
}

-- ---- Network messages -------------------------------------------------------------------------
-- Positions use the built-in "vector" field (full precision, mirrors the stock CommanderPing).

-- Client -> Server: "I want to ping the spot at <position>." Server enforces the cooldown.
Shared.RegisterNetworkMessage( "GC_Ping", { position = "vector" } )

-- Server -> Client (team only): "show a ping from <clientIndex> at <position>."
Shared.RegisterNetworkMessage( "GC_PingShow", {
    clientIndex = "integer",
    position    = "vector"
} )

-- Client -> Server: "place order icon <order> at <position>" (commander only, server-validated).
-- Server -> Client (team only): "show order icon <order> at <position>". Same shape both ways.
local kIconMsg = {
    position = "vector",
    order    = "integer (1 to 15)",
    size     = "integer (1 to 5)"
}
Shared.RegisterNetworkMessage( "GC_Icon",     kIconMsg )   -- C -> S
Shared.RegisterNetworkMessage( "GC_IconShow", kIconMsg )   -- S -> C (team)

-- Clear every icon. C -> S (commander pressed RMB) and S -> C (tell the team to wipe local).
Shared.RegisterNetworkMessage( "GC_DrawClear", {} )

-- Client -> Server: "I just opened my map - send me the current team icons." Server replays
-- the stored icons to that one client (GC_DrawClear then a GC_IconShow per stored icon).
Shared.RegisterNetworkMessage( "GC_DrawRequest", {} )
