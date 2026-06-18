-- VokexBrain.lua
-- Brain class for Vokex bots. The Vokex is a Fade-like lifeform (Fade model and
-- control scheme), so this brain extends FadeBrain and reuses its senses and the
-- whole brain framework. Only the action tables differ (see VokexBrain_Data):
--   * melee with SwipeShadowStep (instead of Fade's SwipeBlink)
--   * ranged attacks with AcidRocket
--   * NEVER uses VortexShadowStep
--   * Vokex-safe movement (Metabolize + pathing; no Fade blink-jump sequence)
-- Senses are inherited from FadeBrain (CreateFadeBrainSenses) — they only read
-- generic stats (health/energy/location), which are valid for a Vokex.
-- GetExpectedPlayerClass returns "Vokex" so the bot keeps this brain after a
-- Skulk evolves into a Vokex.

Script.Load("lua/bots/FadeBrain.lua")
Script.Load("lua/bots/VokexBrain_Data.lua")

class 'VokexBrain' (FadeBrain)

function VokexBrain:GetExpectedPlayerClass()
    return "Vokex"
end

function VokexBrain:GetActions()
    return kVokexBrainActions
end

function VokexBrain:GetObjectiveActions()
    return kVokexBrainObjectives
end
