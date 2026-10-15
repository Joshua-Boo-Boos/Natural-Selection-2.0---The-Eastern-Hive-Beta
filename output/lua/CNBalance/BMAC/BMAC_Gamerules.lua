--[[
    BMAC character: round lock lifecycle. Post-hook on NS2Gamerules.lua, registered LAST on that target
    so it wraps the final SetGameState / ResetGame (CNBalance/NS2Gamerules.lua replaces both).

    Countdown (or Started without a countdown) begins the lock; Countdown -> Started keeps it. Any other
    state (team win, draw, NotStarted) and every ResetGame clear it. Vanilla StartCountdown calls
    ResetGame first and then SetGameState(Countdown), so the capture sees the reset players.
]]

if not Server then
    return
end

local function GetIsActiveRoundState(state)
    return state == kGameState.Countdown or state == kGameState.Started
end

--[[
    (2026-10-15) Per-round choices (BMAC_Shared.lua) are cleared only when a round ENDS (an active round going to any
    other state, or a reset during one). StartCountdown's own ResetGame comes BEFORE the round is active, so the choices
    made in the ready room survive it and are used by BMAC_BeginRoundLock.
]]
local function EndRound()
    if BMAC_GetIsRoundLockActive() then
        BMAC_ClearRoundChoices()
    end
    BMAC_ClearRoundLock()
end

local baseSetGameState = NS2Gamerules.SetGameState
function NS2Gamerules:SetGameState(state)
    baseSetGameState(self, state)

    if GetIsActiveRoundState(state) then
        BMAC_BeginRoundLock()   -- no-op when already active
    else
        EndRound()
    end
end

local baseResetGame = NS2Gamerules.ResetGame
function NS2Gamerules:ResetGame()
    EndRound()
    baseResetGame(self)
end
