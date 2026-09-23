-- One registration of lua/CNBalance/BotCrashGuards.lua, on lua/bots/SkulkBrain_Data.lua.
-- ModLoader runs any given file only ONCE, so a hook file registered on several targets would only run after
-- the first of them. Each registration has its own stub, which re-runs the shared file with reload = true.
Script.Load("lua/CNBalance/BotCrashGuards.lua", true)
