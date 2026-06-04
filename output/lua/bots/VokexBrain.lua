-- VokexBrain.lua
-- Brain class for Vokex bots. Extends FadeBrain since Vokex is the alien equivalent
-- of Fade and shares similar mobility (ShadowStep instead of Blink) and combat style.
-- Key overrides:
--   GetExpectedPlayerClass → "Vokex"  (prevents brain-nil when Fade evolves to Vokex)
--   GetActions             → returns kVokexBrainActions (fixes SwipeShadowStep weapon check)
-- Objectives (retreat to hive, explore, etc.) are reused from kFadeBrainObjectives.

Script.Load("lua/bots/FadeBrain.lua")
Script.Load("lua/bots/VokexBrain_Data.lua")

class 'VokexBrain' (FadeBrain)

function VokexBrain:GetExpectedPlayerClass()
    return "Vokex"
end

function VokexBrain:GetActions()
    return kVokexBrainActions
end
