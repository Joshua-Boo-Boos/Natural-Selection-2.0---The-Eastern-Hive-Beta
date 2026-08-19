--[[
    ARMORY WEAPON STORAGE - block pickup of a weapon reserved for storage.
    Loaded post lua/PickupableWeaponMixin.lua.

    A dropped weapon is claimed by the armory one frame later (destroying entities inside the engine's
    own drop call breaks the drop). In that gap a marine standing in front of the dropper would
    otherwise auto-pick it up and steal something bound for storage.

    GetIsValidRecipient is the single gate for every pickup route -- PickupableMixin's proximity
    auto-pickup, MarineActionFinderMixin's manual use, and the pickup highlight -- so blocking here
    covers all of them, and the prompt never appears in the first place.

    Hooked on this file rather than Weapon_Server.lua because the mixin is loaded by the individual
    weapon files (Rifle, Welder, Shotgun...), which load later; it does not exist at that point.
]]

if not Server then return end

if not PickupableWeaponMixin or PickupableWeaponMixin.ceStorageHooked then return end
PickupableWeaponMixin.ceStorageHooked = true

local basePickupableGetIsValidRecipient = PickupableWeaponMixin.GetIsValidRecipient

function PickupableWeaponMixin:GetIsValidRecipient(recipient)

    if self.ceReservedForStorage then

        -- Re-verify the reservation instead of trusting it. The weapon was reserved at DROP time, but
        -- the toss impulse can carry it back out of the armory's range before it is claimed, and the
        -- armory may have filled up, lost power or died in the meantime. A stale reservation would
        -- leave the weapon lying there permanently unpickupable by anyone.
        --
        -- Checking live means the weapon becomes pickup-able the moment it stops being claimable,
        -- rather than after some arbitrary timeout.
        if ArmoryStorage_GetWillBeClaimed and ArmoryStorage_GetWillBeClaimed(self) then
            return false
        end

        self.ceReservedForStorage = nil

    end

    return basePickupableGetIsValidRecipient(self, recipient)

end
