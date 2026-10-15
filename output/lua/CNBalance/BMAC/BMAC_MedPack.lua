--[[
    BMAC character: a medpack gives a BMAC 25 AP instead of a biological Marine's 50 HP (Beta: 40 HP at once
    + 10 HP regeneration). 25 AP = 50 HP at kHealthPointsPerArmor = 2. Post-hook on MedPack.lua, AFTER
    CNBalance/MedPack.lua.

    Everything else works as for a biological Marine: pickup (dropped packs), the Commander's target-assist,
    the "need medpack" request and self-medication, and the per-player pickup delay. Only the eligibility
    test (AP not full, instead of health not full) and the payout (AP, instead of health + regeneration)
    differ. The AP is given at once: regeneration only heals health, which a BMAC doesn't use.
]]

kBMACMedpackArmor = 25

-- Shared by dropped packs (below) and self-medication (CNBalance/Mixin/RequestHandleMixin.lua MedSelf).
function BMAC_GiveMedpackArmor(recipient)
    recipient:AddArmor(kBMACMedpackArmor, false, true)
    recipient.timeLastMedpack = Shared.GetTime()
end

-- MedPack.kPickupDelay, not self.kPickupDelay: self-medication calls GetIsValidRecipient with the Marine as
-- "self" (MedPack.GetIsValidRecipient(self, self)), which has no kPickupDelay.
local function GetMedpackDelayOver(recipient)
    return not recipient.timeLastMedpack or recipient.timeLastMedpack + MedPack.kPickupDelay <= Shared.GetTime()
end

local baseGetIsValidRecipient = MedPack.GetIsValidRecipient
function MedPack:GetIsValidRecipient(recipient)
    if GetIsBMACMarine(recipient) then
        return recipient:GetIsAlive() and recipient:GetArmor() < recipient:GetMaxArmor() and GetMedpackDelayOver(recipient)
    end
    return baseGetIsValidRecipient(self, recipient)
end

local baseOnTouch = MedPack.OnTouch
function MedPack:OnTouch(recipient)
    if GetIsBMACMarine(recipient) then
        if GetMedpackDelayOver(recipient) then
            BMAC_GiveMedpackArmor(recipient)
            self:TriggerEffects("medpack_pickup", { effecthostcoords = self:GetCoords() })
        end
        return
    end
    return baseOnTouch(self, recipient)
end
