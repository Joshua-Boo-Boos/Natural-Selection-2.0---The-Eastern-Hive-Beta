-- Brazier Industries 9 (BI9), ported from the standalone BI9 mod (lua/mod_files/pistol_mod, workshop 3678033597)
-- following lua/BIHK/ and lua/BIHC/. Differences from the standalone mod:
--   * a FREE, PERMANENT secondary weapon like the Revolver: the buy/respawn handling lives in CNBalance/Marine.lua
--     (secondaryRespawn), the buy node in CNBalance/MarineTeam.lua, and the Pistol / Revolver / BI9 buy buttons in
--     CNBalance/GUI/GUIMarineBuyMenu.lua + lua/BI9/GUIMarineBuyMenu.lua,
--   * no commander drop and no research tech (no Dropbi9 / bi9Tech tech ids),
--   * tech id added with the same never-colliding appender lua/BIHC/ uses (not EnumUtils),
--   * no MarineTeamInfo tracker and no kPlayerStatus entry (no extra network fields - the engine's limit is tight),
--   * no AmmoPack.lua (per-weapon ammo bags were removed), no Combat data (not a Combat mod),
--   * GUIDeathMessages reuses BIHC's AddMessageCustom; BIHC's WeaponOwnerMixin fix already covers the BI9.
-- The weapon file (BI9.lua) and its on-gun ammo display (GUIBI9Display.lua) are the standalone mod's, unchanged
-- except for the display's script path.

ModLoader.SetupFileHook( "lua/Balance.lua", "lua/BI9/Balance.lua", "post" )
ModLoader.SetupFileHook( "lua/Globals.lua", "lua/BI9/Globals.lua", "post" )
ModLoader.SetupFileHook( "lua/TechTreeConstants.lua", "lua/BI9/TechTreeConstants.lua", "post" )
ModLoader.SetupFileHook( "lua/TechData.lua", "lua/BI9/TechData.lua", "post" )
ModLoader.SetupFileHook( "lua/TechTreeButtons.lua", "lua/BI9/TechTreeButtons.lua", "post" )
ModLoader.SetupFileHook( "lua/NS2Utility.lua", "lua/BI9/NS2Utility.lua", "post" )
ModLoader.SetupFileHook( "lua/Armory.lua", "lua/BI9/Armory.lua", "post" )
ModLoader.SetupFileHook( "lua/Weapons/Marine/ClipWeapon.lua", "lua/BI9/ClipWeapon.lua", "post" )
ModLoader.SetupFileHook( "lua/Weapons/WeaponDisplayManager.lua", "lua/BI9/WeaponDisplayManager.lua", "post" )
ModLoader.SetupFileHook( "lua/MarineWeaponEffects.lua", "lua/BI9/MarineWeaponEffects.lua", "post" )
ModLoader.SetupFileHook( "lua/HitSounds.lua", "lua/BI9/HitSounds.lua", "post" )
ModLoader.SetupFileHook( "lua/UmbraMixin.lua", "lua/BI9/UmbraMixin.lua", "post" )
ModLoader.SetupFileHook( "lua/GUIActionIcon.lua", "lua/BI9/GUIActionIcon.lua", "post" )
ModLoader.SetupFileHook( "lua/GUIMarineBuyMenu.lua", "lua/BI9/GUIMarineBuyMenu.lua", "post" )
ModLoader.SetupFileHook( "lua/MarineVariantMixin.lua", "lua/BI9/MarineVariantMixin.lua", "post" )
ModLoader.SetupFileHook( "lua/Hud/GUIInventory.lua", "lua/BI9/GUIInventory.lua", "post" )
ModLoader.SetupFileHook( "lua/GUIDeathMessages.lua", "lua/BI9/GUIDeathMessages.lua", "post" )
