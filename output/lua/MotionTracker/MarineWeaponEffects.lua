-- local kCannonEffects =

-- {
-- 	draw =
--     {
--         marineWeaponDrawSounds =
--         {
--             {player_sound = "sound/NS2.fev/marine/rifle/draw", classname = "Cannon", done = true},
--         },

--     },
--    reload_speed0 = 
--     {
--         gunReloadEffects =
--         {
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/heavy_cannon/reload0", classname = "Cannon", done = true},
--             --{player_sound = "sound/Cannon.fev/combat_cannon/cannon_reload", classname = "Cannon", done = true},
		
--         },
--     },
	
-- 	reload_speed1 = 
--     {
--         gunReloadEffects =
--         {

--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/heavy_cannon/reload1", classname = "Cannon", done = true},
--             --{player_sound = "sound/Cannon.fev/combat_cannon/cannon_reload1", classname = "Cannon", done = true},

--         },
--     },
	
--     reload_cancel =
--     {
--         gunReloadCancelEffects =
--         {

--             {stop_sound = "sound/combat/combat.fev/combat/weapons/marine/heavy_cannon/reload0", classname = "Cannon"},
--             {stop_sound = "sound/combat/combat.fev/combat/weapons/marine/heavy_cannon/reload1", classname = "Cannon", done = true},
-- 		    --{stop_sound = "sound/Cannon.fev/combat_cannon/cannon_reload", classname = "Cannon"},
-- 			--{stop_sound = "sound/Cannon.fev/combat_cannon/cannon_reload1", classname = "Cannon", done = true},

--         },
--     },
-- 	cannon_attack = 
--     {
--         cannonAttackEffects = 
--         {
--             {viewmodel_cinematic = "cinematics/marine/cannon_muzzle_flash.cinematic", attach_point = "fxnode_hcmuzzle", empty = false},            
--             --{weapon_cinematic = "cinematics/marine/pistol/muzzle_flash.cinematic", attach_point = "fxnode_hcmuzzle", empty = false},

--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/heavy_cannon/fire", done = true},
-- 			--{player_sound = "sound/Cannon.fev/combat_cannon/cannon_fire", done = true},
--         },
--     },
-- }
-- GetEffectManager():AddEffectData("kCannonEffects", kCannonEffects)

-- local kMarineWeaponEffects =
-- {
--     draw =
--     {
--         marineWeaponDrawSounds =
--         {
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/revolver/draw", classname = "Revolver", done = true},
--             --{player_sound = "sound/revolver.fev/Revolver/revolver_draw", classname = "Revolver", done = true},
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/lmg/draw", classname = "Submachinegun", done = true},
--             --{player_sound = "sound/Submachinegun.fev/submachinegun/lmg_draw", classname = "Submachinegun", done = true},
--         },

--     },

--     reload_speed0 =
--     {
--         gunReloadEffects =
--         {
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/revolver/reload0", classname = "Revolver", done = true},
--             --{player_sound = "sound/revolver.fev/Revolver/revolver_reload0", classname = "Revolver", done = true},
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/lmg/reload0", classname = "Submachinegun", done = true},
--             --{player_sound = "sound/Submachinegun.fev/submachinegun/lmg_reload", classname = "Submachinegun", done = true},
--         },
--     },

--     reload_speed1 =
--     {
--         gunReloadEffects =
--         {
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/revolver/reload1", classname = "Revolver", done = true},
--             --{player_sound = "sound/revolver.fev/Revolver/revolver_reload1", classname = "Revolver", done = true},
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/lmg/reload1", classname = "Submachinegun", done = true},
--             --{player_sound = "sound/Submachinegun.fev/submachinegun/lmg_reload1", classname = "Submachinegun", done = true},

--         },
--     },

--     reload_cancel =
--     {
--         gunReloadCancelEffects =
--         {
--             {stop_sound = "sound/combat/combat.fev/combat/weapons/marine/revolver/reload0", classname = "Revolver"},
--             {stop_sound = "sound/combat/combat.fev/combat/weapons/marine/revolver/reload1", classname = "Revolver", done = true},
--             --{stop_sound = "sound/revolver.fev/Revolver/revolver_reload0", classname = "Revolver"},
--             --{stop_sound = "sound/revolver.fev/Revolver/revolver_reload1", classname = "Revolver", done = true},
--             {stop_sound = "sound/combat/combat.fev/combat/weapons/marine/lmg/reload0", classname = "Submachinegun"},
--             {stop_sound = "sound/combat/combat.fev/combat/weapons/marine/lmg/reload1", classname = "Submachinegun", done = true},
--             --{stop_sound = "sound/Submachinegun.fev/submachinegun/lmg_reload", classname = "Submachinegun"},
--             --{stop_sound = "sound/Submachinegun.fev/submachinegun/lmg_reload1", classname = "Submachinegun", done = true},
--         },
--     },

--     revolver_attack =
--     {
--         revolverAttackEffects =
--         {
--             {viewmodel_cinematic = "cinematics/marine/Revolver_muzzle.cinematic", attach_point = "fxnode_revolvermuzzle"},
--             {weapon_cinematic = "cinematics/marine/Revolver_muzzle.cinematic", attach_point = "fxnode_revolvermuzzle"},
--             -- Sound effect
--             {player_sound = "sound/combat/combat.fev/combat/weapons/marine/revolver/fire"},
--             --{player_sound = "sound/revolver.fev/Revolver/revolver_fire"},
--         },
--     },

--     rifle_alt_attack =
--     {
--         rifleAltAttackEffects =
--         {
--             { player_sound = "sound/NS2.fev/marine/rifle/alt_swing_female", sex = "female", done = true },
--             { player_sound = "sound/NS2.fev/marine/rifle/alt_swing" },
--         },
--     },

-- }

-- GetEffectManager():AddEffectData("MarineWeaponEffects", kMarineWeaponEffects)