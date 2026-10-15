--[[
    BMAC character: Military Protocol mid-round. Post-hook on MarineTeam.lua, AFTER CNBalance/MarineTeam.lua and
    CombatEngineers_Team.lua (whose OnResearchComplete this wraps).

    The mod re-skins structures, MACs and ARCs the moment Military Protocol completes, but a Marine only took its
    Chroma skin on its next respawn. Now every Marine (and anyone waiting to respawn) is re-skinned at once: Biological
    Marines to the Chroma Biological skin, BMACs to the Chroma B.M.A.C. (or Chroma Military B.M.A.C.) - the lock keeps
    the body and Marine:GetVariantOverride applies the Chroma swap on top.
]]

if not Server then
    return
end

local baseOnResearchComplete = MarineTeam.OnResearchComplete
function MarineTeam:OnResearchComplete(structure, researchId)
    local result = baseOnResearchComplete(self, structure, researchId)
    if researchId == kTechId.MilitaryProtocol and BMAC_ReapplyRoundLock then
        BMAC_ReapplyRoundLock(self:GetTeamNumber())
    end
    return result
end
