-- lua\bots\TEH_AlienOrderAction.lua
--
-- NS2.0-TEH: Alien bots follow Alien Commander orders the same way Marine bots follow Marine
-- Commander orders (MarineBrain_Data kExecFollowOrder). The action is built per brain so each
-- lifeform moves and attacks with its own PerformMove / PerformAttackEntity.
--
-- Order types come from Alien:OnOverrideOrder (CNBalance/Alien.lua): Move, Attack and Defend for
-- every lifeform. Construct and Heal (the Alien version of the Marine build / weld orders) are only
-- ever given to Gorges - see Gorge:OnOverrideOrder - and GorgeBrain_Data handles them itself.
--
-- The weight passed in must sit BELOW the brain's own attack weight, so a bot on its way to an
-- ordered location still fights enemies it runs into, exactly like Marine bots do.

function CreateTEHAlienOrderAction(weight, PerformMove, AttackEntity)

    local kExecFollowOrder = function(move, bot, brain, player, action)

        local order = action.order
        if not order then
            return
        end

        brain.teamBrain:UnassignBot(bot)

        local orderType = order:GetType()
        local target = Shared.GetEntity(order:GetParam())

        if target and orderType == kTechId.Attack then

            brain.teamBrain:AssignBotToEntity(bot, target:GetId())
            AttackEntity(player, target, order:GetLocation(), bot, brain, move)

        elseif target and orderType == kTechId.Defend then

            brain.teamBrain:AssignBotToEntity(bot, target:GetId())
            PerformMove(player:GetOrigin(), target:GetOrigin(), bot, brain, move)

        else
            PerformMove(player:GetOrigin(), order:GetLocation(), bot, brain, move)
        end

    end

    return function(bot, brain, player)
        PROFILE("AlienBrain - FollowOrder")

        local order = bot:GetPlayerOrder()

        return
        {
            name = "order",
            weight = order and weight or 0.0,
            order = order,
            perform = kExecFollowOrder
        }
    end

end
