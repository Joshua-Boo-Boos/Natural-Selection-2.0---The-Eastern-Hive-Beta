-- ProwlerBrain.lua
-- Brain class for Prowler bots. Extends SkulkBrain so Prowler bots explore,
-- defend hives, retreat and respond to threats exactly like Skulks do; only the
-- attack actions differ (Prowler fires VolleyRappel instead of biting).
--   GetExpectedPlayerClass -> "Prowler" (keeps this brain after a Skulk evolves)
--   GetActions             -> kProwlerBrainActions

Script.Load("lua/bots/SkulkBrain.lua")
Script.Load("lua/bots/ProwlerBrain_Data.lua")

class 'ProwlerBrain' (SkulkBrain)

function ProwlerBrain:GetExpectedPlayerClass()
    return "Prowler"
end

function ProwlerBrain:GetActions()
    return kProwlerBrainActions
end
