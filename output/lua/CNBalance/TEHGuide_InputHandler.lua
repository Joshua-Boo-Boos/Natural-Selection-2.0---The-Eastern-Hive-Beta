-- Seed the runtime keybinding table with the Guide key's default (0) until the player's own settings are loaded.
local keyBinding = debug.getupvaluex(Input_SyncInputOptions, "_keyBinding")
keyBinding.TEHGuide = InputKey.Num0
