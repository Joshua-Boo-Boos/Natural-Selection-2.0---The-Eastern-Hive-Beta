-- ARMORY WEAPON STORAGE - the weapon half. Loaded post lua/Weapons/Weapon_Server.lua.
--
-- Queues weapons for absorption as they enter the world. Dropped() covers player drops,
-- SetWeaponWorldState covers commander drops and drop-on-death.

if not Server then return end

-- The Machine Gun's instant despawn is handled in ArmoryStorage_TryAbsorb, which both hooks feed, so
-- it shares the same deferred destruction path.

-- The pickup block for reserved weapons lives in ArmoryStorage_Pickup.lua, hooked onto
-- PickupableWeaponMixin.lua -- that mixin is loaded by the individual weapon files, which load AFTER
-- Weapon_Server.lua, so it does not exist yet here.

local baseWeaponDropped = Weapon.Dropped
function Weapon:Dropped(prevOwner)

    self.ceDroppedTime = Shared.GetTime()

    local result = baseWeaponDropped(self, prevOwner)

    if ArmoryStorage_QueueAbsorb then
        ArmoryStorage_QueueAbsorb(self)
    end

    return result

end

local baseSetWeaponWorldState = Weapon.SetWeaponWorldState
function Weapon:SetWeaponWorldState(state, preventExpiration)

    local entering = state and not self:GetWeaponWorldState()

    if entering then
        self.ceDroppedTime = Shared.GetTime()
    end

    local result = baseSetWeaponWorldState(self, state, preventExpiration)

    if entering then

        -- Catch-all for both exits: death scatters weapons through a path that does not necessarily
        -- call Weapon:Dropped, but everything reaching the floor passes through here.
        if ArmoryStorage_QueueAbsorb then
            ArmoryStorage_QueueAbsorb(self)
        end

    end

    return result

end
