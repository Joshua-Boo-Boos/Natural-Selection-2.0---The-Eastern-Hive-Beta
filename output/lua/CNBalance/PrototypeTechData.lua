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

-- EXTRA research gate for specific base combos, on TOP of the track speciality. The Railgun
-- exo weapon is locked behind the Gauss (Cannon) prototype-lab tech, so the Dual Railgun and
-- Railgun + Claw combos require kTechId.CannonPrototypeLab to be researched before they can be
-- bought. Enforced in BOTH the buy GUI (button lock) and the server AttemptToBuy (authoritative)
-- so it cannot be bypassed. Matches the tech tree, which lists CannonPrototypeLab as a
-- prerequisite of kTechId.DualRailgunExosuit (MarineTeam.lua).
kPrototypeBaseRequiresTech = {
    [kTechId.DualRailgunExosuit] = kTechId.CannonPrototypeLab,
    [kTechId.RailgunClawExosuit] = kTechId.CannonPrototypeLab,
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

-- Armour Plating's armour bonus. Shared so Exo:GetArmorAmount (CNBalance/Exo.lua) and the
-- commander Exo drop (CNBalance/CommanderExoDrop.lua), which has to size the armour of the
-- dropped Exosuit entity itself, can never disagree about how much armour the upgrade is worth.
kPrototypeExoArmourPlatingBonus = 100

-- ============================================================
-- Commander Exo drop
-- ============================================================
-- The Marine Commander can drop a fully-configured Exo for TEAM resources. The price is
-- 2/3 of what a marine pays in PERSONAL resources at a Prototype Lab, floored.
--
-- The floor is applied PER ITEM rather than once over the sum. Per-item flooring keeps the
-- window honest: every button shows its own true price and those prices add up EXACTLY to
-- the footer total. Flooring the sum instead would leave the displayed numbers disagreeing
-- with the total by 1-2 t-res on multi-upgrade configurations, which reads as a bug.
--
-- Resulting prices: dual combo 36, claw combo 23, Armour Plating 13, other upgrades 3 each.
kCommanderExoDropCostScalar = 2 / 3

function GetCommanderExoDropCost(techId)
    return math.floor(GetPrototypeCost(techId) * kCommanderExoDropCostScalar)
end

-- Total t-res for a base combo plus a list of experimental upgrade techIds.
function GetCommanderExoDropTotal(baseTechId, upgradeTechIds)
    local total = baseTechId and GetCommanderExoDropCost(baseTechId) or 0
    for _, techId in ipairs(upgradeTechIds or {}) do
        total = total + GetCommanderExoDropCost(techId)
    end
    return total
end

-- Cheapest drop the commander could possibly make (bare claw combo, no upgrades). The
-- commander's Exosuit button turns RED below this, because no configuration is affordable.
function GetCommanderExoDropCheapest()
    local cheapest
    for techId in pairs(kPrototypeExoCombos) do
        local cost = GetCommanderExoDropCost(techId)
        if not cheapest or cost < cheapest then
            cheapest = cost
        end
    end
    return cheapest or 0
end
