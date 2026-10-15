--[[
    BMAC character: the per-round Marine choice (Biological / BMAC / Random, then a skin). Post-hook on
    NetworkMessages.lua. Client -> server only; a network MESSAGE, not a network variable or class.

    bodyType: kBMACChoiceRandom / kBMACChoiceBiological / kBMACChoiceBMAC. variant: the chosen skin's kMarineVariants
    id, or 0 for "Random" / not chosen yet. The server validates everything (ownership, type) when the round starts.
]]

kBMACChoiceRandom = 0
kBMACChoiceBiological = 1
kBMACChoiceBMAC = 2

Shared.RegisterNetworkMessage("BMACRoundChoice", { bodyType = "integer (0 to 2)", variant = "integer (0 to 1023)" })

--[[
    (2026-10-15) Which Marine skins this player owns, as a string of "0"/"1" indexed by kMarineVariants id (character i
    = variant i). The SERVER cannot check skin ownership: vanilla GetOwnsItem returns true on the server for every item
    (ItemUtils.lua), and every Marine skin is an item. Only the player's own client can ask Steam, so it reports here, and
    the server never hands out a skin outside this list (plus the free ones). Sent when the client connects and whenever
    the choice window opens.
]]
kBMACOwnedSkinsMax = 128
Shared.RegisterNetworkMessage("BMACOwnedSkins", { owned = string.format("string (%d)", kBMACOwnedSkinsMax) })

if Server then
    -- The handlers live with the round lock (BMAC_Shared.lua); looked up per message, so load order doesn't matter.
    Server.HookNetworkMessage("BMACRoundChoice", function(client, message)
        if BMAC_OnRoundChoiceMessage then
            BMAC_OnRoundChoiceMessage(client, message)
        end
    end)
    Server.HookNetworkMessage("BMACOwnedSkins", function(client, message)
        if BMAC_OnOwnedSkinsMessage then
            BMAC_OnOwnedSkinsMessage(client, message)
        end
    end)
end
