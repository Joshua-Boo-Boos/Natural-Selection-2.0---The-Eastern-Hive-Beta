-- Route Marine Commander MMB through the same tap/hold handler as the GUI.
-- Other commanders and other ping bindings retain the game's normal behaviour.
if not Client then return end
local basePing = CheckKeyEventForCommanderPing
function TEHMedMode_SendPing()
    SetCommanderPingEnabled(true)
    return basePing(InputKey.MouseButton0, true)
end
function CheckKeyEventForCommanderPing(key, down)
    if TEHMedMode_HandleMiddle and TEHMedMode_HandleMiddle(key, down) then return true end
    return basePing(key, down)
end
