--[[
    BOT CRASH GUARDS - three vanilla bot script errors seen in server logs, each one repeating every
    frame for as long as the bot stayed in the state that caused it.

    Loaded as a POST hook on each of the three bot files involved (see CNBalance/FileHooks.lua). Every
    section checks that the thing it wraps exists and only installs once, so running this file after
    each of the three hooks is harmless: whichever section's target has loaded by then installs, and
    the others wait for their own hook.

    Nothing here changes how bots play. Each guard only takes over at the exact point the original
    would have thrown, and substitutes the value the original meant to produce.
]]

-- ---------------------------------------------------------------------------------------------
-- 1. BotMotion.lua:223 - "attempt to perform arithmetic on local 'aimTurnRate' (a nil value)"
--
-- BotAim sets aimTurnRate from BotAim.kBotTurnSpeeds[ className ] whenever the bot is in combat, and
-- that table only lists the classes someone remembered to add. Any class missing from it - a mod
-- lifeform, a class another mod introduced, or vanilla's own table on a server whose bots include
-- Onos/Prowler/Vokex - reads nil, and GetRotateSpeed then multiplies nil every frame.
--
-- Fixed at the source: a missing class now falls back to the table's own "Default" entry (1.0 if
-- even that is absent), so aimTurnRate can never be nil in the first place. The accessor is guarded
-- as well, for an aimTurnRate that was nil before this file ran.
-- ---------------------------------------------------------------------------------------------
if BotAim and BotAim.kBotTurnSpeeds and not BotAim.tehTurnSpeedGuard then

    BotAim.tehTurnSpeedGuard = true

    setmetatable( BotAim.kBotTurnSpeeds, {
        __index = function( Table, Key )
            return rawget( Table, "Default" ) or 1.0
        end
    } )

    local OldGetAimTurnRateModifier = BotAim.GetAimTurnRateModifier

    if OldGetAimTurnRateModifier then
        function BotAim:GetAimTurnRateModifier( ... )
            return OldGetAimTurnRateModifier( self, ... ) or 1.0
        end
    end

end

-- ---------------------------------------------------------------------------------------------
-- 2. BotUtils.lua:154 - "attempt to index local 'gatewayDistTable' (a nil value)"
--
-- GetBotWalkDistance asks the location graph for the gateway route between the bot's location and
-- the target's. When the bot stands somewhere the graph has no node for - the log's case was a
-- marine bot in "Ready Room" - there is no route, the graph returns nil, and the next line indexes
-- it. The original only falls back to straight-line distance when a location NAME is missing, not
-- when a named location simply is not in the graph.
--
-- Guarded by calling the original under pcall and, only if it throws, returning the same
-- straight-line distance the original already uses for its own "can't route" cases.
-- ---------------------------------------------------------------------------------------------
if GetBotWalkDistance and not TehBotWalkDistanceGuard then

    TehBotWalkDistanceGuard = true

    local OldGetBotWalkDistance = GetBotWalkDistance

    local function GetPos( EntOrPos )
        if not EntOrPos then return nil end
        if EntOrPos.isa and EntOrPos:isa( "Vector" ) then return EntOrPos end
        if EntOrPos.GetOrigin then return EntOrPos:GetOrigin() end
        return nil
    end

    function GetBotWalkDistance( BotPlayerOrPos, TargetEntOrPos, TargetLocationHint )

        local Ok, Result = pcall( OldGetBotWalkDistance, BotPlayerOrPos, TargetEntOrPos, TargetLocationHint )
        if Ok then return Result end

        local From = GetPos( BotPlayerOrPos )
        local To = GetPos( TargetEntOrPos )

        if From and To then
            return From:GetDistance( To )
        end

        -- Nothing sensible to measure: "very far" makes every caller treat the target as out of reach
        -- rather than as right next to them.
        return 99999

    end

end

-- ---------------------------------------------------------------------------------------------
-- 3. SkulkBrain_Data.lua (PressureEnemyNaturals) - "bad argument #1 to '__sub' (Vector or number
--    expected, got nil)" from skulk:GetOrigin():GetDistance( threatPos )
--
-- The objective stores threatGatewayPos from GetThreatGatewayForLocation, which returns nil when
-- there is no gateway from that natural back towards the enemy tech point. Skulks and Prowlers
-- (ProwlerBrain runs the Skulk objectives) then call GetDistance(nil) every frame.
--
-- Fixed where the objective is CREATED: if no threat gateway was found, the natural's own position -
-- which the objective always has, it is where the bot is walking to - stands in for it, so the bot
-- still goes to the natural and looks around it.
-- ---------------------------------------------------------------------------------------------
if kSkulkBrainObjectives and not TehSkulkObjectiveGuard then

    TehSkulkObjectiveGuard = true

    for Index, Objective in ipairs( kSkulkBrainObjectives ) do

        if type( Objective ) == "function" then

            kSkulkBrainObjectives[ Index ] = function( ... )

                local Action = Objective( ... )

                if type( Action ) == "table" and Action.name == "PressureEnemyNaturals"
                   and Action.threatGatewayPos == nil then
                    Action.threatGatewayPos = Action.position
                end

                return Action

            end

        end

    end

end

-- ---------------------------------------------------------------------------------------------
-- 5. BotUtils.lua:422 - "attempt to call method 'GetTeamBrain' (a nil value)"
--
-- PlayerBrain:Update does "self.teamBrain = GetTeamBrain( player:GetTeamNumber() )", and GetTeamBrain
-- asks that team for its brain. Only the two PLAYING teams have one: the Ready Room team and the
-- spectator team do not, and the call throws on them.
--
-- A bot lands there whenever its body outlives its team membership for a moment - it is moved to the
-- Ready Room, the round resets around it, or it is being placed on a team - and its brain keeps being
-- updated all the while, so the error repeats every frame for as long as that lasts. The log line that
-- prompted this had a live Skulk carrying teamNumber 0.
--
-- Guarded at GetTeamBrain rather than in the brain: a team with no brain now answers nil instead of
-- throwing, which is the truthful answer and the one PlayerBrain's own code already copes with (it
-- re-reads teamBrain every update, and the bot resumes the moment it is on a playing team again).
-- ---------------------------------------------------------------------------------------------
if GetTeamBrain and not gTehTeamBrainGuard then

    gTehTeamBrainGuard = true

    local OldGetTeamBrain = GetTeamBrain

    function GetTeamBrain( teamNum, ... )

        local Gamerules = GetGamerules and GetGamerules()
        local Team = Gamerules and Gamerules.GetTeam and Gamerules:GetTeam( teamNum )

        -- No team, or a team that has no brain to give (Ready Room, spectators).
        if not Team or not Team.GetTeamBrain then
            return nil
        end

        return OldGetTeamBrain( teamNum, ... )

    end

end

--[[
    ...and the line straight after it. With no team brain to be had, vanilla's very next statement is
    "self.teamBrain:UnassignPlayer( player )" (PlayerBrain.lua:140, and again at 151 and 199), so simply
    answering nil above would move the error one line down rather than end it.

    So a bot whose team HAS no brain - Ready Room, spectators, or the moment between teams - does not run
    its brain update at all this frame. That is what the update was about to conclude anyway: its own next
    lines exist to stop a bot that is not on a playing team, and they drop the brain exactly as this does.
    The bot picks up again on its own the moment it is on a playing team, because the brain is rebuilt then.
]]
if PlayerBrain and PlayerBrain.Update and not PlayerBrain.tehNoTeamBrainGuard then

    PlayerBrain.tehNoTeamBrainGuard = true

    local OldPlayerBrainUpdate = PlayerBrain.Update

    function PlayerBrain:Update( bot, move, player, ... )

        local ThinkingFor = player or ( bot and bot.GetPlayer and bot:GetPlayer() )

        if ThinkingFor and ThinkingFor.GetTeamNumber and GetTeamBrain then

            if GetTeamBrain( ThinkingFor:GetTeamNumber() ) == nil then

                -- The same two fields vanilla clears when it decides a bot is not on a playing team.
                if bot then bot.brain = nil end
                ThinkingFor.botBrain = nil

                return false

            end

        end

        return OldPlayerBrainUpdate( self, bot, move, player, ... )

    end

end
