--[[
    BMAC character: the unit-status bar above a player (and its "health/armour" text). Post-hook on
    Player_Client.lua, after CNBalance/Player_Client.lua. Client only.

    Vanilla PlayerUI_GetUnitStatusInfo writes the text as "health/armour" for everyone except an Exo, which
    gets just its armour. A BMAC is armour-only too, so it gets the Exo form - otherwise it showed its hidden
    (always full) health followed by its AP. Its health bar section is already empty: the client-side
    GetHealthFraction of an armour-only body is 0, as for an Exo.
]]

local baseGetUnitStatusInfo = PlayerUI_GetUnitStatusInfo
if not baseGetUnitStatusInfo then
    return
end

function PlayerUI_GetUnitStatusInfo()
    local unitStates = baseGetUnitStatusInfo()
    if not unitStates or not GetIsBMACMarine then
        return unitStates
    end
    for _, state in ipairs(unitStates) do
        local unit = state.UnitId and Shared.GetEntity(state.UnitId)
        if unit and GetIsBMACMarine(unit) then
            state.HealthFraction = 0
            if state.HealthAndArmorFraction then
                state.HealthAndArmorFraction = string.format("%d", math.max(1, math.ceil(unit:GetArmor())))
            end
        end
    end
    return unitStates
end
