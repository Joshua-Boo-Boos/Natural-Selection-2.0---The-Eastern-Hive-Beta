
local kStatusTranslationStringMap = debug.getupvaluex(Scoreboard_ReloadPlayerData, "kStatusTranslationStringMap")
kStatusTranslationStringMap[kPlayerStatus.Devoured] = "STATUS_DEVOURED"

kStatusTranslationStringMap[kPlayerStatus.Prowler]="PROWLER"
kStatusTranslationStringMap[kPlayerStatus.ProwlerEgg]="PROWLER_EGG"
kStatusTranslationStringMap[kPlayerStatus.Vokex]="VOKEX"
kStatusTranslationStringMap[kPlayerStatus.VokexEgg]="VOKEX_EGG"

kStatusTranslationStringMap[kPlayerStatus.Pistol]="STATUS_PISTOL"
kStatusTranslationStringMap[kPlayerStatus.Axe]="STATUS_AXE"
kStatusTranslationStringMap[kPlayerStatus.Welder]="STATUS_WELDER"
kStatusTranslationStringMap[kPlayerStatus.Knife]="STATUS_KNIFE"
kStatusTranslationStringMap[kPlayerStatus.Revolver]="STATUS_REVOLVER"
kStatusTranslationStringMap[kPlayerStatus.SubMachineGun]="STATUS_SUBMACHINEGUN"
kStatusTranslationStringMap[kPlayerStatus.LightMachineGun]="STATUS_LIGHTMACHINEGUN"
kStatusTranslationStringMap[kPlayerStatus.Cannon]="STATUS_CANNON"

-- Prototype-Exo combo names.  The "…Plus" variants resolve to the same name with
-- a trailing "+" (Exo carries an Experimental Technology upgrade).
kStatusTranslationStringMap[kPlayerStatus.ExoDualMinigun]="STATUS_EXO_DUAL_MINIGUN"
kStatusTranslationStringMap[kPlayerStatus.ExoDualRail]="STATUS_EXO_DUAL_RAIL"
kStatusTranslationStringMap[kPlayerStatus.ExoDualFT]="STATUS_EXO_DUAL_FT"
kStatusTranslationStringMap[kPlayerStatus.ExoClawMinigun]="STATUS_EXO_CLAW_MINIGUN"
kStatusTranslationStringMap[kPlayerStatus.ExoClawRail]="STATUS_EXO_CLAW_RAIL"
kStatusTranslationStringMap[kPlayerStatus.ExoClawFT]="STATUS_EXO_CLAW_FT"
kStatusTranslationStringMap[kPlayerStatus.ExoDualMinigunPlus]="STATUS_EXO_DUAL_MINIGUN_PLUS"
kStatusTranslationStringMap[kPlayerStatus.ExoDualRailPlus]="STATUS_EXO_DUAL_RAIL_PLUS"
kStatusTranslationStringMap[kPlayerStatus.ExoDualFTPlus]="STATUS_EXO_DUAL_FT_PLUS"
kStatusTranslationStringMap[kPlayerStatus.ExoClawMinigunPlus]="STATUS_EXO_CLAW_MINIGUN_PLUS"
kStatusTranslationStringMap[kPlayerStatus.ExoClawRailPlus]="STATUS_EXO_CLAW_RAIL_PLUS"
kStatusTranslationStringMap[kPlayerStatus.ExoClawFTPlus]="STATUS_EXO_CLAW_FT_PLUS"

debug.setupvaluex( Scoreboard_ReloadPlayerData, "kStatusTranslationStringMap", kStatusTranslationStringMap)