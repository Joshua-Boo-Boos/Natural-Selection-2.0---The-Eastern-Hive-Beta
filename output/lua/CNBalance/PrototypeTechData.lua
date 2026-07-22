-- CNBalance/PrototypeTechData.lua
-- Prototype Lab buy-window: grouping tables + authoritative cost lookups.
-- Loaded post lua/TechData.lua so kTechId and tech data already exist.
-- All globals (no local) so other mod files read them directly.
--
-- SCOPE (limited port): Exo weapon combos + Exo experimental upgrades + the base
-- Jetpack and Cannon. Intentionally EXCLUDED: Jumppack, GL/Welder exo combos,
-- Power Smash, and the entire Jetpack + Cannon Experimental Technologies tracks.

-- Speciality lab that gates each track's BASE items.
kPrototypeSpecialityForTrack = {
    jetpack = kTechId.JetpackPrototypeLab,
    exo     = kTechId.ExosuitPrototypeLab,
    cannon  = kTechId.CannonPrototypeLab,
}

-- Research that unlocks each track's EXPERIMENTAL upgrades. Only the exo track
-- has upgrades in this port; jetpack/cannon have none (nil -> no upgrades shown).
kPrototypeExperimentalForTrack = {
    exo = kTechId.ExosuitExperimentalTech,
}

-- Upgrades per track. Jetpack + cannon are intentionally empty (their experimental
-- tracks are not ported). Power Smash is intentionally omitted from the exo list.
kPrototypeUpgradesForTrack = {
    jetpack = {},
    exo     = { kTechId.PrototypeExoArmour, kTechId.PrototypeExoExtraFuel,
                kTechId.PrototypeEmergencyEjection, kTechId.PrototypeSelfDestruct,
                kTechId.PrototypeResupply },
    cannon  = {},
}

-- Buyable exo combos -> exo layout key (see kPrototypeExoLayouts in Exo.lua).
-- GL/Welder combos intentionally omitted.
kPrototypeExoCombos = {
    [kTechId.DualMinigunExosuit]       = "DualMinigun",
    [kTechId.DualRailgunExosuit]       = "DualRailgun",
    [kTechId.DualFlamethrowerExosuit]  = "DualFlamethrower",
    [kTechId.MinigunClawExosuit]       = "MinigunClaw",
    [kTechId.RailgunClawExosuit]       = "RailgunClaw",
    [kTechId.FlamethrowerClawExosuit]  = "FlamethrowerClaw",
}

-- Base items: Jetpack, Cannon (NO Jumppack) + all exo combos.
kPrototypeBaseTechIds = {}
for _, t in ipairs({ kTechId.Jetpack, kTechId.Cannon }) do
    kPrototypeBaseTechIds[t] = true
end
for t in pairs(kPrototypeExoCombos) do
    kPrototypeBaseTechIds[t] = true
end

kPrototypeTrackForTechId = {
    [kTechId.Jetpack] = "jetpack",
    [kTechId.Cannon]  = "cannon",
}
for t in pairs(kPrototypeExoCombos) do
    kPrototypeTrackForTechId[t] = "exo"
end
for track, ups in pairs(kPrototypeUpgradesForTrack) do
    for _, u in ipairs(ups) do
        kPrototypeTrackForTechId[u] = track
    end
end

-- Authoritative costs for the buy window (t-res / p-res per the buy path).
-- Prices per the design image: dual combos 55, claw combos 35.
kPrototypeBaseCost = {
    [kTechId.Jetpack]                 = 20,
    [kTechId.Cannon]                  = 25,
    [kTechId.DualMinigunExosuit]      = 55,
    [kTechId.DualRailgunExosuit]      = 55,
    [kTechId.DualFlamethrowerExosuit] = 55,
    [kTechId.MinigunClawExosuit]      = 35,
    [kTechId.RailgunClawExosuit]      = 35,
    [kTechId.FlamethrowerClawExosuit] = 35,
}

-- Exo experimental upgrade costs per the design image.
kPrototypeUpgradeCost = {
    [kTechId.PrototypeExoArmour]         = 20,
    [kTechId.PrototypeExoExtraFuel]      = 5,
    [kTechId.PrototypeEmergencyEjection] = 5,
    [kTechId.PrototypeSelfDestruct]      = 5,
    [kTechId.PrototypeResupply]          = 5,
}

function GetPrototypeCost(techId)
    return kPrototypeBaseCost[techId]
        or kPrototypeUpgradeCost[techId]
        or LookupTechData(techId, kTechDataCostKey, 0)
end
