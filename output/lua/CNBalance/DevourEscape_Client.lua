-- DEVOUR ESCAPE - client handler. Loaded post lua/NetworkMessages_Client.lua.
--
-- Marine:DevourEscape (CNBalance/Marine.lua) sends "DevourEscape" from the server to a marine the moment they
-- leave an Onos, but nothing hooked it on the client: the console warned "No Client handler specified for
-- message DevourEscape" and the escape screen effect never played. The client half of Marine:DevourEscape
-- plays it. The local player may still be the DevouredPlayer (a Marine) when the message lands, which has the
-- same method, so either works.

Client.HookNetworkMessage("DevourEscape", function()
    local player = Client.GetLocalPlayer()
    if player and player.DevourEscape and player:isa("Marine") then
        player:DevourEscape()
    end
end)
