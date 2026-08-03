

PrototypeLab.kUpgradeToTargetType =
{
    [kTechId.JetpackProtoUpgrade] = kTechId.JetpackPrototypeLab,
    [kTechId.ExosuitProtoUpgrade] = kTechId.ExosuitPrototypeLab,
    [kTechId.CannonProtoUpgrade] = kTechId.CannonPrototypeLab,
}

local function GetResearchAllowed(self, techId)
    local stationTypeTechId = PrototypeLab.kUpgradeToTargetType[techId]
    local available = not GetHasTech(self, stationTypeTechId) and not GetIsTechResearching(self, techId)
    return available and techId or kTechId.None
end

-- Each specialised lab offers its "Experimental Technologies" research.
-- (Only the Exosuit track is ported; jetpack/cannon experimental are intentionally out.)
PrototypeLab.kExperimentalTechForLab =
{
    [kTechId.ExosuitPrototypeLab] = kTechId.ExosuitExperimentalTech,
}

-- Show the experimental research button only while it is not researched / researching.
local function GetExperimentalResearchButton(self, techId)
    local available = not GetHasTech(self, techId) and not GetIsTechResearching(self, techId)
    return available and techId or kTechId.None
end

function PrototypeLab:GetTechButtons()

    local techId = self:GetTechId()
    local techButtons = { kTechId.None, kTechId.None, kTechId.None, kTechId.None,
                          kTechId.None, kTechId.None, kTechId.None, kTechId.None }
    if techId == kTechId.PrototypeLab then
        techButtons[1] = GetResearchAllowed(self,kTechId.JetpackProtoUpgrade)
        techButtons[2] = GetResearchAllowed(self,kTechId.ExosuitProtoUpgrade)
        techButtons[5] = GetResearchAllowed(self,kTechId.CannonProtoUpgrade)
    else
        -- A specialised lab offers its Experimental Technologies research.
        local expTech = PrototypeLab.kExperimentalTechForLab[techId]
        if expTech then
            techButtons[1] = GetExperimentalResearchButton(self, expTech)
        end
    end

    return techButtons
end

if Server then

    function PrototypeLab:UpdateResearch()

        local researchId = self:GetResearchingId()
        -- Structure-upgrade research drives the TARGET (variant) node; a normal
        -- research (Experimental Technologies) drives its OWN node.
        local nodeId = PrototypeLab.kUpgradeToTargetType[researchId] or researchId

        if nodeId then

            local techTree = self:GetTeam():GetTechTree()
            local researchNode = techTree:GetTechNode(nodeId)
            if researchNode then
                researchNode:SetResearchProgress(self.researchProgress)
                techTree:SetTechNodeChanged(researchNode, string.format("researchProgress = %.2f", self.researchProgress))
            end

        end
    end

    function PrototypeLab:OnResearchCancel(researchId)

        local nodeId = PrototypeLab.kUpgradeToTargetType[researchId] or researchId
        if nodeId then

            local team = self:GetTeam()
            if team then
                local techTree = team:GetTechTree()
                local researchNode = techTree:GetTechNode(nodeId)
                if researchNode then
                    researchNode:ClearResearching()
                    techTree:SetTechNodeChanged(researchNode, string.format("researchProgress = %.2f", 0))
                end
            end
        end
    end

    function PrototypeLab:OnResearchComplete(researchId)
        -- Structure-upgrade research morphs the lab into the specialised variant.
        local upgradeTech = PrototypeLab.kUpgradeToTargetType[researchId]
        if upgradeTech then
            self:UpgradeToTechId(upgradeTech)
        end
        -- Mark the correct node researched: the variant node for a structure upgrade,
        -- otherwise the research node itself (Experimental Technologies).
        local nodeId = upgradeTech or researchId
        local techTree = self:GetTeam():GetTechTree()
        local researchNode = techTree:GetTechNode(nodeId)

        if researchNode then
            researchNode:SetResearchProgress(1)
            techTree:SetTechNodeChanged(researchNode, string.format("researchProgress = %.2f", 1))
            researchNode:SetResearched(true)
        end
    end

end


function PrototypeLab:GetItemList(forPlayer)
    return { kTechId.Jetpack, kTechId.DualMinigunExosuit, kTechId.DualRailgunExosuit, kTechId.Cannon}
end

-- Show extra text on the lab's NAME once its Experimental Technologies research is complete, so
-- players and SPECTATORS can tell which specific Prototype Lab carries the research. GetUnitName
-- (UnitStatusMixin) calls this override for the whole name, so we rebuild the base display name
-- and append the suffix. Runs on both realms (the name is shown client-side), and is fully
-- guarded so a lab without an experimental tech (jetpack/cannon) is unaffected.
function PrototypeLab:GetUnitNameOverride(viewer)
    local unitName = GetDisplayName(self)

    if HasMixin(self, "Construct") and self.GetIsBuilt and not self:GetIsBuilt() then
        return string.format(Locale.ResolveString("UNBUILT_STRUCTURE"), unitName)
    end

    local expTech = PrototypeLab.kExperimentalTechForLab[self:GetTechId()]
    if expTech and GetHasTech(self, expTech) then
        unitName = unitName .. " - Experimental Tech"
    end

    return unitName
end


class 'ExosuitPrototypeLab' (PrototypeLab)
ExosuitPrototypeLab.kMapName = "exosuit_prototypelab"

class 'JetpackPrototypeLab' (PrototypeLab)
JetpackPrototypeLab.kMapName = "jetpack_prototypelab"

class 'CannonPrototypeLab' (PrototypeLab)
CannonPrototypeLab.kMapName = "cannon_prototypelab"

--local baseGetCanBeUsed = PrototypeLab.GetCanBeUsed
--function PrototypeLab:GetCanBeUsed(player, useSuccessTable)
--
--    baseGetCanBeUsed(self,player,useSuccessTable)
--    if GetHasTech(self,kTechId.MilitaryProtocol) then
--        useSuccessTable.useSuccess = false
--    end
--
--end