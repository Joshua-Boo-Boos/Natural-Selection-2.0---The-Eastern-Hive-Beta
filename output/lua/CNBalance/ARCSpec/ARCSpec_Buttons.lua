--[[
    ARC FACTORY SPECIALISATIONS - commander button icons (atlas cells reused from existing marine techs).

    Loaded post lua/TechTreeButtons.lua, after the mod's own hook. Every new id gets an entry: GetMaterialXYOffset warns about
    any tech id without one.
]]

local kTechIdToMaterialOffset = debug.getupvaluex(GetMaterialXYOffset, "kTechIdToMaterialOffset")

local kARC = 32
local kARCFactory = 6
local kUpgradeRoboticsFactory = 83
local kHeavyMachineGun = 171
local kFlamethrower = 86
local kWeapons1, kWeapons2, kWeapons3 = 80, 81, 82
local kArmor2 = 78
local kDualRailgunExosuit = 116
local kClusterGrenade = 161

-- Conversions
kTechIdToMaterialOffset[kTechId.ARCSpecHammerUpgrade] = kUpgradeRoboticsFactory
kTechIdToMaterialOffset[kTechId.ARCSpecVanguardUpgrade] = kHeavyMachineGun
kTechIdToMaterialOffset[kTechId.ARCSpecInfernoUpgrade] = kFlamethrower

-- Specialised factories and ARCs
kTechIdToMaterialOffset[kTechId.ARCSpecHammerFactory] = kARCFactory
kTechIdToMaterialOffset[kTechId.ARCSpecVanguardFactory] = kARCFactory
kTechIdToMaterialOffset[kTechId.ARCSpecInfernoFactory] = kARCFactory
kTechIdToMaterialOffset[kTechId.ARCSpecHammerARC] = kARC
kTechIdToMaterialOffset[kTechId.ARCSpecVanguardARC] = kARC
kTechIdToMaterialOffset[kTechId.ARCSpecInfernoARC] = kARC

-- Hammerworks: Deflector Plating, Fragmentation Casings, Thermobaric Payload, Hivebreaker Warheads
kTechIdToMaterialOffset[kTechId.ARCSpecHammer1] = kArmor2
kTechIdToMaterialOffset[kTechId.ARCSpecHammer2] = kClusterGrenade
kTechIdToMaterialOffset[kTechId.ARCSpecHammer3] = kWeapons3
kTechIdToMaterialOffset[kTechId.ARCSpecHammer4] = kWeapons1

-- Vanguard: Coaxial Machine Gun, Light Cannon Shells, Standard Cannon Shells, Railgun Sabots
kTechIdToMaterialOffset[kTechId.ARCSpecVanguard1] = kHeavyMachineGun
kTechIdToMaterialOffset[kTechId.ARCSpecVanguard2] = kWeapons1
kTechIdToMaterialOffset[kTechId.ARCSpecVanguard3] = kWeapons2
kTechIdToMaterialOffset[kTechId.ARCSpecVanguard4] = kDualRailgunExosuit

-- Inferno: Igniter Burst, Pressurised Flame Jet, Napalm Gel, Thermite Lance
kTechIdToMaterialOffset[kTechId.ARCSpecInferno1] = kFlamethrower
kTechIdToMaterialOffset[kTechId.ARCSpecInferno2] = kFlamethrower
kTechIdToMaterialOffset[kTechId.ARCSpecInferno3] = kClusterGrenade
kTechIdToMaterialOffset[kTechId.ARCSpecInferno4] = kFlamethrower
