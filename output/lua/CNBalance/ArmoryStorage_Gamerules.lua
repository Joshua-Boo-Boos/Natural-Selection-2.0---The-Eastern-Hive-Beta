-- ARMORY WEAPON STORAGE - suspend absorption across a map reset. Loaded post lua/NS2Gamerules.lua.
--
-- ResetGame walks the entity list setting world state on weapons; absorbing (and so destroying) one
-- from inside that walk hangs the server. Nothing is lost by skipping: the reset destroys them all
-- anyway, and the sweep picks up anything left once play resumes.

if not Server then return end

gArmoryStorageSuspended = false

-- Guarded: if ResetGame is ever absent, wrapping it would make pcall fail and the error() below would
-- then abort every round reset -- turning a missing function into a fatal server bug.
local baseResetGame = NS2Gamerules.ResetGame

if baseResetGame then

    function NS2Gamerules:ResetGame()

        gArmoryStorageSuspended = true

        -- pcall so a failure inside the reset can never leave absorption permanently switched off.
        -- The error is re-raised afterwards so it still surfaces normally rather than being swallowed.
        local ok, err = pcall(baseResetGame, self)

        gArmoryStorageSuspended = false

        if not ok then
            error(err, 0)
        end

    end

end
