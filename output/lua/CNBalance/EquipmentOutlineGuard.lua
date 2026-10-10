--[[
    EQUIPMENT OUTLINE GUARD (client)

    Vanilla's EquipmentOutline_UpdateModel (lua/EquipmentOutline.lua) reads Client.GetLocalPlayer() and calls
    player:GetTeamNumber() on it. For a moment while the local player's entity is being replaced, that can be whatever
    entity now holds the id - seen as a SoundEffect - which has no GetTeamNumber, so every pickupable weapon on the map
    raised "attempt to call method 'GetTeamNumber' (a nil value)" every frame.

    While the local "player" is not actually a player, the outline update is skipped (the outlines simply stay as they
    were for that moment). Everything else is handed straight to the original.

    POST hook on lua/EquipmentOutline.lua. Wraps one global function, once.
]]

if not Client or type(EquipmentOutline_UpdateModel) ~= "function" or gEquipmentOutlineGuardInstalled then return end
gEquipmentOutlineGuardInstalled = true

local oldEquipmentOutline_UpdateModel = EquipmentOutline_UpdateModel

function EquipmentOutline_UpdateModel(forEntity, ...)
    local player = Client.GetLocalPlayer()
    if player ~= nil and not (player.isa and player:isa("Player")) then
        return
    end
    return oldEquipmentOutline_UpdateModel(forEntity, ...)
end
