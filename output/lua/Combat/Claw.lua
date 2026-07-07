-- ======= NS2.0-TEH-Beta: Combat/Claw.lua =======
--
-- Vanilla Claw (NS2-Copy/ns2/lua/Weapons/Marine/Claw.lua) never defines
-- GetIsAffectedByWeaponUpgrades, unlike Minigun/Railgun (both explicitly
-- return true - Minigun.lua:248-250, Railgun.lua:217-219). Without it,
-- NS2Gamerules_GetUpgradedDamage's guard (CNBalance/DamageTypes.lua:120-121,
-- `if doer.GetIsAffectedByWeaponUpgrades and doer:GetIsAffectedByWeaponUpgrades() then ...`)
-- is never satisfied, so Claw damage never scales with the Weapons upgrade at
-- all. kTechId.Claw also has no entry in the scalar table, so this alone
-- makes it fall into the same "Default" 1.1/1.2/1.3 scaling Minigun/Railgun use.
-- =====================================================================

function Claw:GetIsAffectedByWeaponUpgrades()
    return true
end
