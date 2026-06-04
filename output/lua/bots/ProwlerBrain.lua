-- ProwlerBrain.lua
-- Brain class for Prowler bots. Extends SkulkBrain so Prowler bots can explore,
-- defend hives, retreat and respond to threats the same way Skulks do.
-- Key overrides:
--   GetExpectedPlayerClass → "Prowler"  (prevents brain-nil when Skulk evolves to Prowler)
--   GetActions             → kProwlerBrainActions (uses VolleyRappel attack, not BiteLeap)
-- Objectives are re-used from kSkulkBrainObjectives; the Evolve objective is
-- intercepted by TEHBotManager.lua so Prowler bots handle assigned lifeforms correctly.

Script.Load("lua/bots/SkulkBrain.lua")
Script.Load("lua/bots/ProwlerBrain_Data.lua")

class 'ProwlerBrain' (SkulkBrain)

function ProwlerBrain:GetExpectedPlayerClass()
    return "Prowler"
end

function ProwlerBrain:GetActions()
    return kProwlerBrainActions
end
