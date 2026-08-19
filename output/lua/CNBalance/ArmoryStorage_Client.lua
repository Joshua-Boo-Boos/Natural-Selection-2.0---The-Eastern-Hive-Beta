-- ARMORY WEAPON STORAGE - client cache of the last count the server sent for each (armory, techId),
-- so the buy menu can render "Stored: N" without polling. Loaded post lua/NetworkMessages_Client.lua.

if not Client then return end

-- [armoryId][techId] = count
local ceArmoryStock = {}

Client.HookNetworkMessage("ArmoryStock", function(message)

    local perArmory = ceArmoryStock[message.armoryId]
    if not perArmory then
        perArmory = {}
        ceArmoryStock[message.armoryId] = perArmory
    end

    perArmory[message.techId] = message.count

end)

function GetArmoryStoredCount(armoryId, techId)

    -- Unknown reads as 0 so callers can format unconditionally; a zero stock just means full price,
    -- so guessing low is safe.
    local perArmory = armoryId and ceArmoryStock[armoryId]
    return (perArmory and perArmory[techId]) or 0

end

-- Red at empty, orange for a thin stock, green once well supplied.
--
-- Brightened from the original values. Alpha was already 1, so the washed-out look was not
-- transparency but the colours themselves being too dark against the button art -- raising the
-- non-dominant channels lifts them well clear of the background without changing the three bands.
function GetArmoryStoredCountColor(count)

    if count <= 0 then
        return Color(1, 0.42, 0.42, 1)
    elseif count <= 5 then
        return Color(1, 0.78, 0.28, 1)
    end

    return Color(0.55, 1, 0.55, 1)

end

-- No "find the nearby armory" helper here on purpose: the buy menu already knows which structure it
-- was opened against, so guessing from proximity risks disagreeing with the server.

-- Whether the local player already owns the Machine Gun, and so buys it for nothing.
local ceLmgOwned = false

Client.HookNetworkMessage("ArmoryLmgOwned", function(message)
    ceLmgOwned = message.owned
end)

function GetArmoryLmgIsFree()
    return ceLmgOwned
end

--[[
    The price the buy menu should actually gate on: 0 when this purchase would be free (stored stock
    at this host, or the Machine Gun already owned), the normal techCost otherwise.

    This is the piece that was missing. Server-side retrieval was made free, and the "Stored: N" label
    was made to show correctly, but nothing ever told the BUTTON ITSELF that the price had changed --
    it kept comparing the player's p-res against the full techCost regardless of stock, so a player
    below that price saw "INSUFFICIENT FUNDS" and the client never even sent the buy request. No
    server-side fix could ever reach that: the click was rejected before a network message existed.
]]
function GetArmoryEffectiveCost(hostStructure, techId, techCost)

    if not techId then
        return techCost
    end

    if techId == kTechId.LightMachineGunAcquire or techId == kTechId.LightMachineGun then
        if GetArmoryLmgIsFree and GetArmoryLmgIsFree() then
            return 0
        end
        return techCost
    end

    -- The armory can be destroyed while its buy menu is still open, leaving a stale reference here.
    -- Every accessor is therefore checked before use rather than assuming a live entity; a miss just
    -- falls back to the full price, which is the safe direction (the server decides the real cost).
    local valid = hostStructure ~= nil
              and hostStructure.isa ~= nil and hostStructure:isa("Armory")
              and hostStructure.GetId ~= nil
              and (hostStructure.GetIsDestroyed == nil or not hostStructure:GetIsDestroyed())

    if valid and GetArmoryStoredCount(hostStructure:GetId(), techId) > 0 then
        return 0
    end

    return techCost

end
