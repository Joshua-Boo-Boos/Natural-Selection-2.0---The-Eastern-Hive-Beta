-- CNBalance/CombatEngineers_Sounds.lua
-- Combat Engineers sound-event constants (sound/combat_engineers.fev), precached once here and
-- shared by every trigger point (CombatBuilder.lua, CombatEngineers_Team.lua, CombatEngineers_Build.lua,
-- CombatEngineers_Upgrade.lua). Loaded early (post lua/TechData.lua, same as CombatEngineers_Shared.lua)
-- so these globals exist before anything that references them.

-- Volume every CE sound plays at. NOT a percentage: FMOD volume is applied on a curve, so 0.5 is
-- audibly rather less than half as loud, which is the intent - these are voice/stinger cues layered
-- over normal combat audio and were overbearing at full volume.
--
-- Applied at every playback site so all eleven sounds stay in step: both Server.PlayPrivateSound and
-- Shared.PlaySound take volume as their third/fifth argument respectively.
kCombatEngineersSoundVolume = 0.5

kCombatEngineersResearchedSound      = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_researched")
kCombatEngineersExplanationSound     = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_explanation")
kCombatEngineersBuyStructuresSound   = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_buy_structures_open")
kCombatEngineersStructurePlacedSound = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_structure_placed")
kCombatEngineersTechPurchasedSound   = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_tech_purchased")
kCombatEngineersCreditsTakenSound    = PrecacheAsset("sound/combat_engineers.fev/combat_engineers/ce_tres_taken")

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
