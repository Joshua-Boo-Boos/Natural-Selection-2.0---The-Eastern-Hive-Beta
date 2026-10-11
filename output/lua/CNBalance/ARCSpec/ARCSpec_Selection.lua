-- ARCUS: double-click / Ctrl-click selects only the clicked ARC's type.
-- Loaded post Commander_MouseActions.lua (client only). Its ClickSelect asks for
-- all on-screen entities of the clicked class; all four ARC types share "ARC".
-- Keep the original screen/team filtering and narrow that list by tech ID.

local baseGetSelectablesOnScreen = GetSelectablesOnScreen
function GetSelectablesOnScreen(commander, className, minPos, maxPos)

    local selectables = baseGetSelectablesOnScreen(commander, className, minPos, maxPos)

    -- Marquee selection passes no class and must continue to allow mixed ARCs.
    if className ~= "ARC" then
        return selectables
    end

    local mousePos = MouseTracker_GetCursorPos()
    local pickVec = CreatePickRay(commander, mousePos.x, mousePos.y)
    local clickedARC = commander:GetUnitUnderCursor(pickVec)
    if not clickedARC or not clickedARC:isa("ARC") then
        return selectables
    end

    local techId = clickedARC:GetTechId()
    local matchingARCs = {}
    for _, arc in ipairs(selectables) do
        if arc:GetTechId() == techId then
            matchingARCs[#matchingARCs + 1] = arc
        end
    end
    return matchingARCs

end
