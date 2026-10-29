-- The BI9 uses the Pistol's tech button icon.
local origGetMaterialXYOffset = GetMaterialXYOffset
function GetMaterialXYOffset(techId)
    if rawget(kTechId, "bi9") and techId == kTechId.bi9 then
        techId = kTechId.Pistol
    end
    return origGetMaterialXYOffset(techId)
end
