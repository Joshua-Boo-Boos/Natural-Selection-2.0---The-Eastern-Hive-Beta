--[[
    SIEGE2.0-TEH - A DROPPED WEAPON KEEPS ITS OWN RESERVE AMMO.

    POST hook on lua/Weapons/Marine/ClipWeapon.lua.

    Vanilla ClipWeapon:Dropped (server) does this when a clip weapon hits the floor:

        local ammopackMapName = self:GetAmmoPackMapName()
        if ammopackMapName and self.ammo ~= 0 then
            local ammoPack = CreateEntity(ammopackMapName, ...)
            ammoPack:SetAmmoPackSize(self.ammo)
            self.ammo = 0
            ...

    i.e. the reserve is moved OUT of the weapon into a separate "spare ammo bag" entity. Those bag
    classes are no longer registered at all (see CNBalance/AmmoPack_NoWeaponPacks.lua - they were
    network classes, and the server hit the engine's network class limit), so creating one would be
    an error. More to the point, the ammo should just stay with the gun.

    So for the duration of the original Dropped call only, GetAmmoPackMapName is shadowed on the
    weapon itself to return nil. Vanilla then skips the bag entirely and never zeroes self.ammo: a
    Shotgun dropped with 20 spare shells is a Shotgun on the floor with self.ammo = 20, and the next
    marine to pick it up gets all 20.

    The shadow is an instance field removed straight afterwards, so every weapon class's own
    GetAmmoPackMapName (which still names its now-unregistered bag class) is never actually called.
    Flamethrower:Dropped and anything else that calls ClipWeapon.Dropped reach this wrapper too, because
    they look the function up on the class at call time.

    Wrapped rather than copied: vanilla's Dropped calls CancelReload, a LOCAL of ClipWeapon.lua that a
    copied body here could not see.
]]

if not Server then return end
if not ClipWeapon or not ClipWeapon.Dropped or ClipWeapon.tehNoAmmoPackDrop then return end

ClipWeapon.tehNoAmmoPackDrop = true

local function NoAmmoPack()
    return nil
end

local OldDropped = ClipWeapon.Dropped

function ClipWeapon:Dropped( prevOwner, ... )

    self.GetAmmoPackMapName = NoAmmoPack

    local Ok, Result = pcall( OldDropped, self, prevOwner, ... )

    self.GetAmmoPackMapName = nil

    if not Ok then
        Print( "[NS2.0-TEH] error in ClipWeapon:Dropped: %s", tostring( Result ) )
        return nil
    end

    return Result

end
