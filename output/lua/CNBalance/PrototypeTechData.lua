-- CNBalance/PrototypeTechData.lua
-- Prototype Lab conversion — grouping tables and authoritative cost lookups.
-- Loaded post lua/TechData.lua so kTechId and all tech data are already defined.
-- All globals (no local) so other mod files can read them directly.

kPrototypeSpecialityForTrack = {
    jetpack = kTechId.JetpackPrototypeLab,
    exo     = kTechId.ExosuitPrototypeLab,
    cannon  = kTechId.CannonPrototypeLab,
}

-- Research that unlocks the EXPERIMENTAL upgrades (the "extras") for each track.
-- The base items are gated by the speciality above; the bottom-half upgrades
-- additionally require the corresponding Experimental Technologies research.
kPrototypeExperimentalForTrack = {
    jetpack = kTechId.JetpackExperimentalTech,
    exo     = kTechId.ExosuitExperimentalTech,
    cannon  = kTechId.CannonExperimentalTech,
}

kPrototypeUpgradesForTrack = {
    jetpack = { kTechId.PrototypeBoost, kTechId.PrototypeJetpackExtraFuel, kTechId.PrototypeJetpackArmour },
    exo     = { kTechId.PrototypeExoArmour, kTechId.PrototypeExoExtraFuel, kTechId.PrototypeLifeformScanner,
                kTechId.PrototypeEmergencyEjection, kTechId.PrototypeSelfDestruct, kTechId.PrototypeResupply },
    cannon  = { kTechId.PrototypeExtendedMagazine, kTechId.PrototypeChargeShot,
                kTechId.PrototypeTungstenPenetrator, kTechId.PrototypeShotgun },
}

kPrototypeExoCombos = {
    [kTechId.DualMinigunExosuit]          = "DualMinigun",
    [kTechId.DualRailgunExosuit]          = "DualRailgun",
    [kTechId.DualFlamethrowerExosuit]     = "DualFlamethrower",
    [kTechId.DualGrenadeLauncherExosuit]  = "DualGL",
    [kTechId.DualWelderExosuit]           = "DualWelder",
    [kTechId.MinigunClawExosuit]          = "MinigunClaw",
    [kTechId.RailgunClawExosuit]          = "RailgunClaw",
    [kTechId.FlamethrowerClawExosuit]     = "FlamethrowerClaw",
    [kTechId.GrenadeLauncherClawExosuit]  = "GLClaw",
    [kTechId.WelderClawExosuit]           = "WelderClaw",
}

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

-- Verbatim cost lookups (authoritative for the buy window).
-- Base items: Jetpack, Cannon, and all exo combos.
kPrototypeBaseCost = {
    [kTechId.Jetpack]                    = 20,
    [kTechId.Cannon]                     = 25,
    [kTechId.DualMinigunExosuit]         = 55,
    [kTechId.DualRailgunExosuit]         = 55,
    [kTechId.DualFlamethrowerExosuit]    = 75,
    [kTechId.DualGrenadeLauncherExosuit] = 65,
    [kTechId.DualWelderExosuit]          = 55,
    [kTechId.MinigunClawExosuit]         = 40,
    [kTechId.RailgunClawExosuit]         = 40,
    [kTechId.FlamethrowerClawExosuit]    = 50,
    [kTechId.GrenadeLauncherClawExosuit] = 45,
    [kTechId.WelderClawExosuit]          = 40,
}

-- Upgrade items: all Prototype* ids.
kPrototypeUpgradeCost = {
    [kTechId.PrototypeBoost]               = 15,
    [kTechId.PrototypeJetpackExtraFuel]    = 15,
    [kTechId.PrototypeJetpackArmour]       = 15,
    [kTechId.PrototypeExoArmour]           = 20,
    [kTechId.PrototypeExoExtraFuel]        = 20,
    [kTechId.PrototypeLifeformScanner]     = 20,
    [kTechId.PrototypeEmergencyEjection]   = 20,
    [kTechId.PrototypeSelfDestruct]        = 20,
    [kTechId.PrototypeResupply]            = 20,
    [kTechId.PrototypeExtendedMagazine]    = 10,
    [kTechId.PrototypeChargeShot]          = 10,
    [kTechId.PrototypeTungstenPenetrator]  = 10,
    [kTechId.PrototypeShotgun]             = 10,
}

-- Unified cost accessor for the buy window.
function GetPrototypeCost(techId)
    return kPrototypeBaseCost[techId]
        or kPrototypeUpgradeCost[techId]
        or LookupTechData(techId, kTechDataCostKey, 0)
end
