local oldBuildClassToGrid = BuildClassToGrid
function BuildClassToGrid()

    local ClassToGrid = oldBuildClassToGrid()

    ClassToGrid["bi9"] = { 3, 2 }

    return ClassToGrid

end

local loadOnce = true
local oldGetTexCoordsForTechId = GetTexCoordsForTechId
function GetTexCoordsForTechId(techId)
    if loadOnce and gTechIdPosition then
        gTechIdPosition[kTechId.bi9] = kDeathMessageIcon.bi9
        loadOnce = false
    end
    return oldGetTexCoordsForTechId(techId)
end
