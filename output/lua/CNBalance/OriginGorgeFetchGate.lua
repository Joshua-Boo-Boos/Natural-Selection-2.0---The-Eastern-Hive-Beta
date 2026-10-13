-- Post AlienTeam: enforce the vote and notice even if another bot action tries to buy fetch.
if not Server then return end
local originalFetch = AlienTeam.OnOriginFormResourceFetch
function AlienTeam:OnOriginFormResourceFetch(player)
    if player:GetIsVirtual() then
        local state = GetOriginGorgeState and GetOriginGorgeState(self)
        if not player:isa("Gorge") or not state
            or (OriginGorgeHasHumanAliens(self) and not state.voteFinished) or state.disallowed
            or state.fetchOwner ~= player:GetId() or self:GetCommander() then return end
        state.fetchOwner = nil -- a single authorized withdrawal
    end
    return originalFetch(self, player)
end
