local kReadyRoomTeamBrain =
{
    UnassignPlayer = function() end,
    AddPlayer = function() end,
    AddBot = function() end,
    RemoveBot = function() end,
}

function GetTeamBrain(teamNum)

    local team = GetGamerules():GetTeam(teamNum)
    if not team or not team.GetTeamBrain then
        return kReadyRoomTeamBrain
    end

    return team:GetTeamBrain()

end
