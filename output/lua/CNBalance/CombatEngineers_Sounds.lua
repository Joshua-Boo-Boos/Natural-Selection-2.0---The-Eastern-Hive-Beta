-- CNBalance/CombatEngineers_Sounds.lua
-- Combat Engineers sound-event constants (sound/combat_engineers.fev), precached once here and
-- shared by every trigger point (CombatBuilder.lua, CombatEngineers_Team.lua, CombatEngineers_Build.lua,
-- CombatEngineers_Upgrade.lua). Loaded early (post lua/TechData.lua, same as CombatEngineers_Shared.lua)
-- so these globals exist before anything that references them.

kCombatEngineersResearchedSound      = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_researched")
kCombatEngineersExplanationSound     = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_explanation")
kCombatEngineersBuyStructuresSound   = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_buy_structures_open")
kCombatEngineersStructurePlacedSound = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_structure_placed")
kCombatEngineersTechPurchasedSound   = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_tech_purchased")

-- Indexed by ladder level (1..6), same order as kCombatEngineersArmsLabLadder in
-- CombatEngineers_Shared.lua: Armor1, Weapons1, Armor2, Weapons2, Armor3, Weapons3.
kCombatEngineersArmsLabLadderSounds =
{
    PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_a1"),
    PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_w1"),
    PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_a2"),
    PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_w2"),
    PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_a3"),
    PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_w3"),
}
