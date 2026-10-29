-- CNBalance/TEHGuide_Server.lua
-- Registers "!guide" as a Shine chat command (console: sh_guide) so it appears, with its help text, in the Shine chat
-- box's command auto-complete list. That list is built on the server from Shine's registered commands.
--
-- The command itself does nothing on the server: the client opens the guide window and empties the chat message
-- before it is sent (CNBalance/TEHGuide_Client.lua), so this only runs for a client without that file. Available to
-- everyone (NoPerm) and silent. Does nothing on a server without Shine.
--
-- Post-hooked onto lua/NetworkMessages_Server.lua (server only).

if not Server then return end

local kHelpText = "Opens the guide to this server's game mode (also the Guide key, 0 by default)."

local registered = false
Event.Hook("UpdateServer", function()

    if registered then return end
    if not (Shine and Shine.RegisterCommand and Shine.Commands) then return end
    registered = true

    if Shine.Commands["sh_guide"] then return end

    local command = Shine:RegisterCommand("sh_guide", "guide", function() end, true, true)
    if command and command.Help then
        command:Help(kHelpText)
    end

end)
