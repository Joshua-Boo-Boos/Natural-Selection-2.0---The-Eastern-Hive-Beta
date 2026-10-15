-- Post AlienTeam: enforce the vote and notice even if another bot action tries to buy fetch.
if not Server then return end
local originalFetch = AlienTeam.OnOriginFormResourceFetch
function AlienTeam:OnOriginFormResourceFetch(player)
    if player:GetIsVirtual() then
        local state = GetOriginGorgeState and GetOriginGorgeState(self)
        -- (2026-10-14) The team's first Hive (no Hive alive) is fetched for whatever the vote said
        -- (OriginGorgeBuilder.lua B.FirstHiveFetch / B.Fund mark it with state.firstHiveFetchOwner).
        local firstHive = state and state.firstHiveFetchOwner == player:GetId()
        if not player:isa("Gorge") or not state
            or (not firstHive and ((OriginGorgeHasHumanAliens(self) and not state.voteFinished) or state.disallowed))
            or state.fetchOwner ~= player:GetId() or self:GetCommander() then return end
        state.fetchOwner = nil -- a single authorized withdrawal
    end
    return originalFetch(self, player)
end
