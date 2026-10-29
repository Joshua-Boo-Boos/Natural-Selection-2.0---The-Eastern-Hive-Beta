--[[
    SIEGE2.0-TEH - lua/AmmoPack.lua REPLACEMENT: the per-weapon dropped ammo bags are gone.

    Vanilla's AmmoPack.lua defines the commander's AmmoPack drop AND six classes for the "spare ammo
    that falls out when a weapon is dropped" mechanic: WeaponAmmoPack plus RifleAmmo, ShotgunAmmo,
    FlamethrowerAmmo, GrenadeLauncherAmmo and HeavyMachineGunAmmo. CNBalance/AmmoPack.lua then added four
    more (RevolverAmmo, SubMachineGunAmmo, LightMachineGunAmmo, CannonAmmo). Every one of those is a
    Shared.LinkClassToMap - a registered NETWORK CLASS - and the server has crashed on hitting the
    engine's network class limit.

    So this file is vanilla's AmmoPack.lua VERBATIM down to and including the commander AmmoPack class
    (which commander drops, Exo resupply and everything else still need), and everything after that is
    commented out below rather than deleted, so it can be restored by removing the comment markers.

    The ammo those bags used to carry now simply stays IN THE WEAPON: see
    CNBalance/NoWeaponAmmoPacks.lua, which stops ClipWeapon:Dropped from creating a bag, so a Shotgun
    dropped with 20 reserve shells lands on the floor still holding self.ammo = 20 and whoever picks it
    up gets them with it.
]]

-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\AmmoPack.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/DropPack.lua")

class 'AmmoPack' (DropPack)

AmmoPack.kMapName = "ammopack"

AmmoPack.kModelNameWinter = PrecacheAsset("seasonal/holiday2012/models/gift_ammopack_01.model")
AmmoPack.kModelName = PrecacheAsset("models/marine/ammopack/ammopack.model")
local function GetModelName()
    return GetSeason() == Seasons.kWinter and AmmoPack.kModelNameWinter or AmmoPack.kModelName
end

AmmoPack.kNumClips = 5


function AmmoPack:OnInitialized()

    DropPack.OnInitialized(self)
    
    self:SetModel(GetModelName())
	
end

function AmmoPack:OnTouch(recipient)

    local consumedPack = false
    local oldAmmo = 0
    
    for i = 0, recipient:GetNumChildren() - 1 do
    
        local child = recipient:GetChildAtIndex(i)
        if child:isa("ClipWeapon") then

            oldAmmo = oldAmmo + child:GetAmmo()

            if child:GiveAmmo(AmmoPack.kNumClips, false) then
                consumedPack = true
            end
            
        end
        
    end
    
    if consumedPack then

        local newAmmo = 0
        for i = 0, recipient:GetNumChildren() - 1 do

            local child = recipient:GetChildAtIndex(i)
            if child:isa("ClipWeapon") then
                newAmmo = newAmmo + child:GetAmmo()
            end
        end

        self:TriggerEffects("ammopack_pickup", { effecthostcoords = recipient:GetCoords()})

        -- Handle Stats
        if Server then

            local commanderStat = StatsUI_GetStatForCommander(StatsUI_GetMarineCommmaderSteamID())

            if self:GetMapName() ~= "ammopack" or not commanderStat then
                return
            end

            commanderStat["ammopack"].misses   = commanderStat["ammopack"].misses - 1
            commanderStat["ammopack"].picks    = commanderStat["ammopack"].picks + 1
            commanderStat["ammopack"].refilled = commanderStat["ammopack"].refilled + newAmmo - oldAmmo
        end
    end
    
end

function AmmoPack:GetIsValidRecipient(recipient)

	if not recipient:isa("Marine") then
		return false
	end
	
    local needsAmmo = false
    
    for i = 0, recipient:GetNumChildren() - 1 do
    
        local child = recipient:GetChildAtIndex(i)
        if child:isa("ClipWeapon") and child:GetNeedsAmmo(false) then
        
            needsAmmo = true
            break
            
        end
        
    end 

    -- Ammo packs give ammo to clip as well (so pass true to GetNeedsAmmo())
    return needsAmmo
    
end

Shared.LinkClassToMap("AmmoPack", AmmoPack.kMapName)

-- =====================================================================================================
-- SIEGE2.0-TEH: per-weapon dropped ammo bags DISABLED (network class limit). Original code preserved:
-- =====================================================================================================
--[==[
class 'WeaponAmmoPack' (AmmoPack)
WeaponAmmoPack.kMapName = "weapoanammopack"

function WeaponAmmoPack:SetAmmoPackSize(size)
    self.ammoPackSize = size
end

function WeaponAmmoPack:OnTouch(recipient)

    local weapon = recipient:GetActiveWeapon()
    weapon:GiveReserveAmmo(self.ammoPackSize)
    self:TriggerEffects("ammopack_pickup", { effecthostcoords = recipient:GetCoords()})
    
end

function WeaponAmmoPack:GetIsValidRecipient(recipient)
    local valid = AmmoPack.GetIsValidRecipient(self, recipient)
    if not valid then return false end

    local weapon = recipient:GetActiveWeapon()
    local correctWeaponType = weapon and weapon:isa(self:GetWeaponClassName())
    return self.ammoPackSize ~= nil and correctWeaponType
end

Shared.LinkClassToMap("WeaponAmmoPack", WeaponAmmoPack.kMapName)

-- -------------

class 'RifleAmmo' (WeaponAmmoPack)
RifleAmmo.kMapName = "rifleammo"
RifleAmmo.kModelName = PrecacheAsset("models/marine/rifle/rifleammo.model")

function RifleAmmo:OnInitialized()

    WeaponAmmoPack.OnInitialized(self)
    self:SetModel(RifleAmmo.kModelName)

end

function RifleAmmo:GetWeaponClassName()
    return "Rifle"
end

Shared.LinkClassToMap("RifleAmmo", RifleAmmo.kMapName)

-- -------------

class 'ShotgunAmmo' (WeaponAmmoPack)
ShotgunAmmo.kMapName = "shotgunammo"
ShotgunAmmo.kModelName = PrecacheAsset("models/marine/shotgun/shotgunammo.model")

function ShotgunAmmo:OnInitialized()

    WeaponAmmoPack.OnInitialized(self)    
    self:SetModel(ShotgunAmmo.kModelName)

end

function ShotgunAmmo:GetWeaponClassName()
    return "Shotgun"
end    

Shared.LinkClassToMap("ShotgunAmmo", ShotgunAmmo.kMapName)

-- -------------

class 'FlamethrowerAmmo' (WeaponAmmoPack)
FlamethrowerAmmo.kMapName = "flamethrowerammo"
FlamethrowerAmmo.kModelName = PrecacheAsset("models/marine/flamethrower/flamethrowerammo.model")

function FlamethrowerAmmo:OnInitialized()

    WeaponAmmoPack.OnInitialized(self)    
    self:SetModel(FlamethrowerAmmo.kModelName)

end

function FlamethrowerAmmo:GetWeaponClassName()
    return "Flamethrower"
end

Shared.LinkClassToMap("FlamethrowerAmmo", FlamethrowerAmmo.kMapName)

-- -------------

class 'GrenadeLauncherAmmo' (WeaponAmmoPack)
GrenadeLauncherAmmo.kMapName = "grenadelauncherammo"
GrenadeLauncherAmmo.kModelName = PrecacheAsset("models/marine/grenadelauncher/grenadelauncherammo.model")

function GrenadeLauncherAmmo:OnInitialized()

    WeaponAmmoPack.OnInitialized(self)    
    self:SetModel(GrenadeLauncherAmmo.kModelName)

end

function GrenadeLauncherAmmo:GetWeaponClassName()
    return "GrenadeLauncher"
end

Shared.LinkClassToMap("GrenadeLauncherAmmo", GrenadeLauncherAmmo.kMapName)

-- -------------

class 'HeavyMachineGunAmmo' (WeaponAmmoPack)
HeavyMachineGunAmmo.kMapName = "heavymachinegunammo"
HeavyMachineGunAmmo.kModelName = PrecacheAsset("models/marine/hmg/hmgammo.model")

function HeavyMachineGunAmmo:OnInitialized()

    WeaponAmmoPack.OnInitialized(self)
    self:SetModel(HeavyMachineGunAmmo.kModelName)

end

function HeavyMachineGunAmmo:GetWeaponClassName()
    return "HeavyMachineGun"
end

Shared.LinkClassToMap("HeavyMachineGunAmmo", HeavyMachineGunAmmo.kMapName)
]==]
