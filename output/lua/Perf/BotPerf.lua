-- TeamBrains exist only to serve bot AI, but vanilla feeds them entity
-- memories on every LOS change even on a bot-less server. Skip all of it
-- while no bots are connected. When bots ARE present, behavior is vanilla.
if Server then

    local baseUpdateEntityForTeamBrains = UpdateEntityForTeamBrains

    function UpdateEntityForTeamBrains(entity, destroy)

        if not gServerBots or #gServerBots == 0 then
            return
        end

        return baseUpdateEntityForTeamBrains(entity, destroy)

    end

end
