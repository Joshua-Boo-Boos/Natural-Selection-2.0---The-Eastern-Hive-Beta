-- ======= NS2.0-TEH-Beta: CNBalance/CommMapTools_Client.lua =======
--
-- CLIENT half (loaded via a "post" hook on lua/Client.lua). Handles:
--   * The N-key PING: trace the local player's aim, send GC_Ping (5s self-cooldown for feel).
--   * Rendering incoming pings as world-anchored beacons + the pinger's NAME in team colour,
--     through walls, auto-fading.
--   * Keeping the local copy of the commander ORDER ICONS (gGCLocalIcons) in sync from the network;
--     the actual on-map rendering + commander input live in CNBalance/GUIMinimapFrame.lua.

if not Client then return end

-- The local order icons, shared (same VM) with the GUIMinimapFrame hook that renders them.
-- Each entry: { pos = Vector, order = int (index into kGCommMap.Orders[team]) }.
gGCLocalIcons = gGCLocalIcons or {}
-- Bumped on every change so the renderer knows to rebuild.
gGCIconVersion = gGCIconVersion or 0

local function ClearLocalIcons()
    for i = #gGCLocalIcons, 1, -1 do
        gGCLocalIcons[i] = nil
    end
    gGCIconVersion = gGCIconVersion + 1
end

-- ---- Ping input --------------------------------------------------------------------------------
local gClientLastPing = 0
local gWasPingKeyDown = false

local function TryPing()
    local player = Client.GetLocalPlayer()
    if not player or not player.GetEyePos then return end
    if not HasMixin(player, "Team") then return end
    local teamNumber = player:GetTeamNumber()
    if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then return end

    local now = Shared.GetTime()
    if (now - gClientLastPing) < kGCommMap.PingCooldown then return end   -- self-limit for feel
    gClientLastPing = now

    local eye = player:GetEyePos()
    local dir = player:GetViewCoords().zAxis
    local trace = Shared.TraceRay(eye, eye + dir * kGCommMap.PingRange,
        CollisionRep.Select, PhysicsMask.AllButPCs, EntityFilterOne(player))
    local position = (trace.fraction ~= 1) and trace.endPoint or (eye + dir * kGCommMap.PingRange)

    Client.SendNetworkMessage("GC_Ping", { position = position }, true)
end

-- N is not consumed (players may have it bound elsewhere); we just also fire a ping on its press
-- edge, and never while typing in chat.
Event.Hook("SendKeyEvent", function(key, down)
    if InputKey and key == InputKey.N then
        if down and not gWasPingKeyDown then
            if not (ChatUI_EnteringChatMessage and ChatUI_EnteringChatMessage()) then
                TryPing()
            end
        end
        gWasPingKeyDown = down
    end
end)

-- ---- Ping rendering ----------------------------------------------------------------------------
-- Active beacons: { clientIndex, position, endTime, marker (GUIItem), text (GUIItem) }.
local gPings = {}

local function LocalTeamColour()
    return (Client.GetLocalClientTeamNumber() == kTeam2Index) and kAlienFontColor or kMarineFontColor
end

Client.HookNetworkMessage("GC_PingShow", function(message)
    local gui = GetGUIManager()

    local marker = gui:CreateGraphicItem()
    marker:SetAnchor(GUIItem.Left, GUIItem.Top)
    marker:SetSize(GUIScale(Vector(12, 12, 0)))
    marker:SetLayer(kGUILayerPlayerHUDForeground2)

    local text = gui:CreateTextItem()
    text:SetAnchor(GUIItem.Left, GUIItem.Top)
    text:SetFontName(Fonts.kAgencyFB_Small)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Min)
    text:SetScale(GUIScale(Vector(1, 1, 1)))
    text:SetText(Scoreboard_GetPlayerData(message.clientIndex, "Name") or "")
    text:SetLayer(kGUILayerPlayerHUDForeground2)

    gPings[#gPings + 1] = {
        clientIndex = message.clientIndex,
        position    = message.position,
        endTime     = Shared.GetTime() + kGCommMap.PingDuration,
        marker      = marker,
        text        = text,
    }
end)

local function DestroyPing(ping)
    if ping.marker then GUI.DestroyItem(ping.marker) end
    if ping.text then GUI.DestroyItem(ping.text) end
end

Event.Hook("UpdateClient", function()
    if #gPings == 0 then return end

    local now = Shared.GetTime()
    local player = Client.GetLocalPlayer()
    local eye = player and player.GetEyePos and player:GetEyePos()
    local fwd = player and player.GetViewCoords and player:GetViewCoords().zAxis
    local colour = LocalTeamColour()

    for i = #gPings, 1, -1 do
        local ping = gPings[i]
        if now >= ping.endTime then
            DestroyPing(ping)
            table.remove(gPings, i)
        else
            -- Hide when the pinged point is behind the camera (WorldToScreen would mirror it).
            local inFront = true
            if eye and fwd then
                local toPt = ping.position - eye
                inFront = (toPt.x * fwd.x + toPt.y * fwd.y + toPt.z * fwd.z) > 0
            end

            if inFront then
                local screen = Client.WorldToScreen(ping.position)
                -- Fade the last second.
                local remaining = ping.endTime - now
                local alpha = math.min(1, remaining)
                local c = Color(colour.r, colour.g, colour.b, alpha)

                local half = GUIScale(6)
                ping.marker:SetIsVisible(true)
                ping.marker:SetPosition(Vector(screen.x - half, screen.y - half, 0))
                ping.marker:SetColor(c)

                ping.text:SetIsVisible(true)
                ping.text:SetPosition(Vector(screen.x, screen.y + GUIScale(10), 0))
                ping.text:SetColor(c)
            else
                ping.marker:SetIsVisible(false)
                ping.text:SetIsVisible(false)
            end
        end
    end
end)

-- ---- Order icon sync (data only; rendering is in the GUIMinimapFrame hook) ---------------------
Client.HookNetworkMessage("GC_IconShow", function(message)
    gGCLocalIcons[#gGCLocalIcons + 1] = { pos = message.position, order = message.order, size = message.size }
    gGCIconVersion = gGCIconVersion + 1
end)

Client.HookNetworkMessage("GC_DrawClear", function(message)
    ClearLocalIcons()
end)
