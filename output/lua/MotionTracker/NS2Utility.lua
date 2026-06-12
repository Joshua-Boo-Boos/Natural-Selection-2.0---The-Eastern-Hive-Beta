
-- Minimap blip sprite for a dropped MotionTracker entity (BuildClassToGrid feeds
-- GUIMinimap/GameViz only — a different atlas from the inventory icons).
local oldBuildClassToGrid = BuildClassToGrid
function BuildClassToGrid()

    local ClassToGrid = oldBuildClassToGrid()

    ClassToGrid["MotionTracker"] = { 3, 2 }

    return ClassToGrid

end

-- Inventory / death-message atlas position (gTechIdPosition), registered exactly
-- like the BI9 pistol_mod. gTechIdPosition is built LAZILY on the first
-- GetTexCoordsForTechId call, so we set our entry from inside a wrapper that runs
-- after the table exists ("after everything else has loaded"). The standalone
-- custom texture is still drawn on top by GUIInventory.lua / GUIDeathMessages.lua.
local loadOnce = true
local oldGetTexCoordsForTechId = GetTexCoordsForTechId
function GetTexCoordsForTechId(techId)
    if loadOnce and gTechIdPosition then
        gTechIdPosition[kTechId.MotionTracker] = kDeathMessageIcon.MotionTracker
        loadOnce = false
    end
    return oldGetTexCoordsForTechId(techId)
end
