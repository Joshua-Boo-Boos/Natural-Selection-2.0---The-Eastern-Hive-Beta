-- ARMORY WEAPON STORAGE - shared definitions. Loaded post lua/NetworkMessages.lua so these exist in
-- every VM before the server and client halves load.

-- Anything not listed here is ignored by the whole system -- which is how undroppable items and the
-- Machine Gun (a one-time purchase, handled separately) stay out of every storage path at once.
kArmoryStorableTechIds =
{
    kTechId.Shotgun,
    kTechId.HeavyMachineGun,
    kTechId.GrenadeLauncher,
    kTechId.Flamethrower,
    kTechId.Welder,
    kTechId.LayMines,

    -- Both are Weapon subclasses carrying PickupableWeaponMixin and both have a kTechDataMapName, so
    -- they absorb and dispense through exactly the same path as the rest. MotionTracker is additionally
    -- listed as advanced-only below; CombatBuilder is not, since it is sold at a basic Armory.
    kTechId.MotionTracker,
    kTechId.CombatBuilder,
}

-- Per-armory, per-weapon ceiling. An armory holding its tenth welder will not take an eleventh: the
-- weapon is left lying on the floor rather than destroyed, so nothing is ever silently lost.
kArmoryMaxStoredPerWeapon = 10

-- Storable only by the Advanced Armory. The tech tree already gates these, so letting a basic Armory
-- hold one would launder an advanced weapon through a structure that cannot dispense it.
kArmoryAdvancedOnlyTechIds =
{
    [kTechId.HeavyMachineGun] = true,
    [kTechId.GrenadeLauncher] = true,
    [kTechId.Flamethrower]    = true,
    [kTechId.MotionTracker]   = true,
}

-- Map name -> techId. Built LAZILY: this file loads before TechData.lua, so building it now would
-- silently yield an empty table, reading as "no weapon is ever storable".
kArmoryStorableMapNames = setmetatable({}, {

    __index = function(self, mapName)

        for _, techId in ipairs(kArmoryStorableTechIds) do

            local techMapName = LookupTechData(techId, kTechDataMapName)
            if techMapName then
                rawset(self, techMapName, techId)
            end

        end

        setmetatable(self, nil)

        return rawget(self, mapName)

    end,

})

-- Free weapons are discarded rather than banked.
function GetIsArmoryStorableTechId(techId)

    if not techId or not kArmoryStorableMapNames then
        return false
    end

    for _, storable in ipairs(kArmoryStorableTechIds) do
        if storable == techId then
            return (GetCostForTech(techId) or 0) > 0
        end
    end

    return false

end

function GetArmoryCanStoreTechId(armory, techId)

    if not armory or not techId then
        return false
    end

    if kArmoryAdvancedOnlyTechIds[techId] and armory:GetTechId() ~= kTechId.AdvancedArmory then
        return false
    end

    return true

end

-- Sent per (armory, techId) so a single change costs one small message.
kArmoryStockMessage =
{
    armoryId = string.format("entityid"),
    techId   = string.format("enum kTechId"),
    count    = string.format("integer (0 to 255)"),
}

Shared.RegisterNetworkMessage("ArmoryStock", kArmoryStockMessage)

-- Server -> owning client only: "you have already bought the Machine Gun, it is free from now on". Purely
-- cosmetic -- the server decides the actual price regardless -- but without it the button would show
-- the full 30 while charging nothing, which reads as a bug.
Shared.RegisterNetworkMessage("ArmoryLmgOwned", { owned = "boolean" })
