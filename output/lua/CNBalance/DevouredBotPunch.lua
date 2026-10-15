--[[
    MARINE BOTS ALWAYS PUNCH THE ONOS DEVOURING THEM (2026-10-14, as in Combat Enhancer)

    A devoured human holds the attack button and punches the inside of the Onos (Combat/DevouredViewModel.lua:
    OnPrimaryAttack sets primaryAttacking, the stomach animation plays its punches and each one lands on its animation
    tag). A bot did nothing, because no bot brain knows what a DevouredPlayer is, and just sat there until digested.

    While a bot's body is a DevouredPlayer, its move is simply "hold primary attack" - so it punches at exactly the rate
    a human holding the button does, with the same damage to the Onos and the same cost to itself. Its brain is not run
    meanwhile (there is nothing else it can do in there); it picks up again when the bot is free.

    Loaded at the END of lua/bots/PlayerBot_Server.lua (after PlayerBot:GenerateMove is defined). Installs once.
]]
if not Server or not PlayerBot or PlayerBot.tehDevouredPunch then return end
PlayerBot.tehDevouredPunch = true

local baseGenerateMove = PlayerBot.GenerateMove

function PlayerBot:GenerateMove(...)

    local player = self.GetPlayer and self:GetPlayer()
    if player and player:isa("DevouredPlayer") and player:GetIsAlive() then
        local move = Move()
        move.commands = AddMoveCommand(move.commands, Move.PrimaryAttack)
        return move
    end

    return baseGenerateMove(self, ...)

end
