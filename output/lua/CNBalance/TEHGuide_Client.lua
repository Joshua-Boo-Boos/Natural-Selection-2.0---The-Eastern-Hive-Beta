-- CNBalance/TEHGuide_Client.lua
-- Wires up the guide window (CNBalance/GUI/GUITEHGuide.lua):
--   * creates it once the client is running (it then lives for the whole map),
--   * the Guide key (Options -> Mods -> NS2.0-TEH, default 0) is handled by the window itself,
--   * "!guide" typed in chat opens it,
--   * "guide" in the console opens it,
--   * it opens by itself when you join a server, unless "Show Guide Upon Join" is switched off (see below).
--
-- !guide is caught on the client by wrapping BuildChatClientMessage, which BOTH the vanilla chat box and Shine's chat
-- box call at send time. The message is emptied, and the server drops empty chat (NetworkMessages_Server.lua
-- OnChatReceived), so "!guide" is never shown to anyone. Nothing is sent to the server for any of this: no network
-- messages, no network variables.
--
-- Post-hooked onto lua/Chat.lua (client only).

if not Client then return end

local kGuideScript = "CNBalance/GUI/GUITEHGuide"

local function GetGuide()

    if gTEHGuide then
        return gTEHGuide
    end

    local manager = GetGUIManager and GetGUIManager()
    if not manager or not (Client.GetLocalPlayer and Client.GetLocalPlayer()) then
        return nil
    end

    gTEHGuide = manager:CreateGUIScript(kGuideScript)
    return gTEHGuide

end

function TEHGuide_Open()
    local guide = GetGuide()
    if guide then
        guide:SetOpen(true)
    end
end

local function IsGuideCommand(message)
    if type(message) ~= "string" then return false end
    local text = string.lower(StringTrim(message))
    return text == "!guide" or text == "/guide"
end

local wrappedChat = false
local function WrapChat()

    if wrappedChat or not BuildChatClientMessage then return end
    wrappedChat = true

    local baseBuildChatClientMessage = BuildChatClientMessage
    function BuildChatClientMessage(teamOnly, chatMessage)
        if IsGuideCommand(chatMessage) then
            TEHGuide_Open()
            chatMessage = ""
        end
        return baseBuildChatClientMessage(teamOnly, chatMessage)
    end

end

-- "Show Guide Upon Join" (Options -> Mods, default ON): the guide opens by itself a few seconds after you join.
--
-- The client VM is rebuilt on every map change, so "first update after loading" would also fire on each map change
-- while you stay connected. To tell a real join from a map change, the server address and the time are saved every
-- few seconds while you are in game: if you load into the SAME server within kMapChangeWindow seconds of the last
-- save, it is a map change and the guide is not opened. Option paths are literals and must match
-- CNBalance/TEHGuide_ModsMenuData.lua.
local kShowOnJoinOption = "TEHGuide/ShowOnJoin"
local kLastServerOption = "TEHGuide/LastServer"
local kLastSeenOption = "TEHGuide/LastSeen"
local kMapChangeWindow = 120     -- seconds
local kHeartbeatInterval = 10    -- seconds
local kShowDelay = 3             -- seconds after the local player first exists

local joinChecked = false
local showAt
local nextHeartbeat = 0

local function GetServerAddress()
    return Client.GetConnectedServerAddress and Client.GetConnectedServerAddress() or ""
end

local function CheckJoin()

    joinChecked = true

    local now = Shared.GetSystemTime()
    local address = GetServerAddress()
    local lastServer = Client.GetOptionString(kLastServerOption, "")
    local lastSeen = Client.GetOptionInteger(kLastSeenOption, 0)
    local isMapChange = address ~= "" and address == lastServer and now - lastSeen <= kMapChangeWindow

    if not isMapChange and Client.GetOptionBoolean(kShowOnJoinOption, true) then
        showAt = Shared.GetTime() + kShowDelay
    end

end

local function Heartbeat()
    local now = Shared.GetTime()
    if now < nextHeartbeat then return end
    nextHeartbeat = now + kHeartbeatInterval
    Client.SetOptionString(kLastServerOption, GetServerAddress())
    Client.SetOptionInteger(kLastSeenOption, Shared.GetSystemTime())
end

Event.Hook("UpdateClient", function()
    if not wrappedChat then
        WrapChat()
    end
    -- Only in a game with a local player, never in the main menu.
    if not (Client.GetLocalPlayer and Client.GetLocalPlayer()) then
        return
    end
    if not gTEHGuide then
        GetGuide()
    end
    if not joinChecked then
        CheckJoin()
    end
    if showAt and Shared.GetTime() >= showAt then
        showAt = nil
        if not (MainMenu_GetIsOpened and MainMenu_GetIsOpened()) then
            TEHGuide_Open()
        end
    end
    Heartbeat()
end)

Event.Hook("Console_guide", function()
    TEHGuide_Open()
end)
