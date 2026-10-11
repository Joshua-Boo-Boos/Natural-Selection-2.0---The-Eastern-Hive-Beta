--[[
    ARC FACTORY SPECIALISATIONS - the conversions are INSTANCED researches.

    Loaded post lua/TechTree.lua, after the mod's own hook (which defines GetTechIdIsInstanced). Instanced means each ARC
    Factory researches its own conversion, exactly like UpgradeRoboticsFactory: several factories can convert at once, to
    the same or different specialisations, and the team node is never marked researched by one of them.
]]

local baseGetTechIdIsInstanced = GetTechIdIsInstanced
function GetTechIdIsInstanced(techId)
    if ARCSpec and ARCSpec.kSpecByUpgrade[techId] then
        return true
    end
    return baseGetTechIdIsInstanced(techId)
end
