-- TEHBotManager.lua
-- Loaded after CommonAlienActions.lua (via Script.Load in PlayerBot_Server.lua).
-- Provides two features:
--
--   1. Lifeform Assignment: 20 seconds after a round starts, all alien bots are
--      collected and given an assigned lifeform stored in bot.teh_assignedLifeform.
--      The 7 lifeforms (Skulk, Gorge, Prowler, Lerk, Fade, Vokex, Onos) are
--      distributed as equally as possible. Remainder bots are split between Gorge
--      and Onos; any odd-one-out leftover gets a random lifeform.
--
--   2. Instant Evolution: Overrides CreateAlienEvolveAction so that assigned bots
--      evolve as soon as they have sufficient personal resources, with no hive
--      proximity or combat checks.

local kTEHAssignDelay    = 20.0   -- seconds after game start before assignment
local kTEHHiveRequiredCost = 15   -- Prowler+ (cost >= 15) must navigate to a Hive before evolving
local kTEHHiveEvolveDist   = 10.0 -- distance from Hive origin to trigger evolution

-- The seven lifeforms in assignment order
local kTEHLifeforms = {
    kTechId.Skulk,
    kTechId.Gorge,
    kTechId.Prowler,
    kTechId.Lerk,
    kTechId.Fade,
    kTechId.Vokex,
    kTechId.Onos,
}
local kTEHLifeformCount = #kTEHLifeforms  -- 7

-- Lazy-initialised mapping from lifeform tech-id → class name string
local gLifeformToClass = nil
local function GetLifeformToClass()
    if gLifeformToClass == nil then
        gLifeformToClass = {
            [kTechId.Skulk]   = "Skulk",
            [kTechId.Gorge]   = "Gorge",
            [kTechId.Prowler] = "Prowler",
            [kTechId.Lerk]    = "Lerk",
            [kTechId.Fade]    = "Fade",
            [kTechId.Vokex]   = "Vokex",
            [kTechId.Onos]    = "Onos",
        }
    end
    return gLifeformToClass
end

-- The gameStartTime value for which we last ran assignment (-1 = never)
local gTEHAssignedGameStartTime = -1

-- ---------------------------------------------------------------------------
-- TEH_AssignLifeforms()
-- Collects all alien bots, shuffles them, then assigns one of the 7 lifeforms
-- to each bot using even distribution.
-- ---------------------------------------------------------------------------
local function TEH_AssignLifeforms()
    -- Clear any stale assignments first
    for _, bot in ipairs(gServerBots) do
        bot.teh_assignedLifeform = nil
        bot.teh_requestedMist    = nil  -- clear per-life mist flag on reassignment
    end

    -- Collect bots on the alien team
    local alienBots = {}
    for _, bot in ipairs(gServerBots) do
        local player = bot:GetPlayer()
        if IsValid(player) and player:GetTeamNumber() == kAlienTeamType then
            table.insert(alienBots, bot)
        end
    end

    local n = #alienBots
    if n == 0 then return end

    -- Shuffle so assignment order is random each round
    for i = n, 2, -1 do
        local j = math.random(i)
        alienBots[i], alienBots[j] = alienBots[j], alienBots[i]
    end

    -- Build the flat assignment list
    local assignments = {}
    local basePerLifeform = math.floor(n / kTEHLifeformCount)
    local remainder       = n - basePerLifeform * kTEHLifeformCount  -- 0..6

    -- basePerLifeform of each lifeform
    for _, lifeformId in ipairs(kTEHLifeforms) do
        for _ = 1, basePerLifeform do
            table.insert(assignments, lifeformId)
        end
    end

    -- Remainder: split evenly between Gorge and Onos
    local gorgeExtra  = math.floor(remainder / 2)
    local onosExtra   = math.floor(remainder / 2)
    local randomExtra = remainder - gorgeExtra - onosExtra  -- 0 or 1 (only 1 when remainder is odd)

    for _ = 1, gorgeExtra  do table.insert(assignments, kTechId.Gorge) end
    for _ = 1, onosExtra   do table.insert(assignments, kTechId.Onos)  end
    for _ = 1, randomExtra do
        table.insert(assignments, kTEHLifeforms[math.random(kTEHLifeformCount)])
    end

    -- Assign to bots
    for i, bot in ipairs(alienBots) do
        bot.teh_assignedLifeform = assignments[i]
    end

    Log("[TEHBotManager] Assigned lifeforms to %d alien bots (base/lifeform=%d, remainder=%d)",
        n, basePerLifeform, remainder)
end

-- ---------------------------------------------------------------------------
-- Helper: check whether assignment needs to run and do it if so
-- Called from inside each bot's evolve evaluation function.
-- ---------------------------------------------------------------------------
local function TEH_CheckAndAssign()
    local gamerules = GetGamerules()
    if not gamerules or not gamerules:GetGameStarted() then return end

    local gameStartTime = gamerules:GetGameStartTime()

    if gameStartTime ~= gTEHAssignedGameStartTime and
            Shared.GetTime() - gameStartTime >= kTEHAssignDelay then
        gTEHAssignedGameStartTime = gameStartTime
        TEH_AssignLifeforms()
    end
end

-- ---------------------------------------------------------------------------
-- Override CreateAlienEvolveAction
-- ---------------------------------------------------------------------------
local gOriginalCreateAlienEvolveAction = CreateAlienEvolveAction

function CreateAlienEvolveAction(actionWeights, actionType, lifeformTechId)

    -- Build the vanilla action so we can fall through for unassigned bots
    local vanillaAction = gOriginalCreateAlienEvolveAction(actionWeights, actionType, lifeformTechId)

    -- Return the per-frame evaluation closure
    return function(bot, brain, player)
        PROFILE("TEHBotManager - Evolve")

        -- Run the periodic assignment check (no-ops if already done this round)
        TEH_CheckAndAssign()

        -- ----------------------------------------------------------------
        -- Determine if this bot has an assigned lifeform
        -- ----------------------------------------------------------------
        local assignedLifeform = bot.teh_assignedLifeform

        -- Late-joining bots (joined after the 20-second window):
        -- give them a random assignment if the game is already past the window
        if assignedLifeform == nil then
            local gamerules = GetGamerules()
            if gamerules and gamerules:GetGameStarted() and
                    gTEHAssignedGameStartTime == gamerules:GetGameStartTime() then
                -- Round has already been assigned; give this bot a random pick
                assignedLifeform = kTEHLifeforms[math.random(kTEHLifeformCount)]
                bot.teh_assignedLifeform = assignedLifeform
            end
        end

        -- If still no assignment (pre-assignment window), stay as Skulk.
        -- Using vanilla logic here caused many bots to evolve to Gorge before assignment
        -- ran, permanently over-populating that lifeform for the rest of the round.
        if assignedLifeform == nil then
            return kNilAction
        end

        -- ----------------------------------------------------------------
        -- Assignment-based evolution
        -- ----------------------------------------------------------------

        -- Hallucinations never evolve
        if player.isHallucination then
            return kNilAction
        end

        -- Skulk-assigned bots: stay as Skulk, nothing to buy
        if assignedLifeform == kTechId.Skulk then
            return kNilAction
        end

        -- Check if the bot is already the assigned lifeform
        local lifeformToClass = GetLifeformToClass()
        local assignedClass   = lifeformToClass[assignedLifeform]
        if assignedClass and player:isa(assignedClass) then
            -- Already evolved correctly
            return kNilAction
        end

        -- Only Skulks can evolve into other lifeforms
        if not player:isa("Skulk") then
            return kNilAction
        end

        -- Check basic purchase eligibility (handles embryo, dead, etc.)
        if not player:GetIsAllowedToBuy() then
            return kNilAction
        end

        -- Check tech availability in the current tech tree
        local techNode = player:GetTechTree():GetTechNode(assignedLifeform)
        local isAvailable = techNode and techNode:GetAvailable(player, assignedLifeform, false)
        if not isAvailable then
            return kNilAction
        end

        -- Check personal resources: evolve as soon as we can afford it
        local cost = GetCostForTech(assignedLifeform)
        if player:GetPersonalResources() < cost then
            return kNilAction
        end

        -- Record on bot so other systems (e.g. vanilla upgrade logic) know what we want
        bot.lifeformEvolution = assignedLifeform

        -- Return the evolve action (weight from the objective weight table)
        local evolveName, evolveWeight = actionWeights:Get(actionType)
        local lifeformCost = GetCostForTech(assignedLifeform)

        -- Gorge (cost 10) can evolve anywhere.
        -- Prowler+ (cost >= kTEHHiveRequiredCost = 15) must navigate to a Hive first.
        if lifeformCost >= kTEHHiveRequiredCost then
            -- Find the nearest alive, built Hive
            local hives = GetEntitiesForTeam("Hive", player:GetTeamNumber())
            local nearestHive = nil
            local nearestDist = math.huge
            for _, hive in ipairs(hives) do
                if hive:GetIsAlive() and hive:GetIsBuilt() then
                    local dist = player:GetOrigin():GetDistance(hive:GetOrigin())
                    if dist < nearestDist then
                        nearestDist = dist
                        nearestHive = hive
                    end
                end
            end

            if nearestHive and nearestDist > kTEHHiveEvolveDist then
                -- Not yet at the hive; navigate toward it (do NOT evolve yet)
                local hivePos = nearestHive:GetEngagementPoint()
                return {
                    name       = evolveName or "teh_evolve_to_hive",
                    weight     = (evolveWeight or 10),
                    hivePos    = hivePos,
                    fastUpdate = true,
                    perform    = function(move, b, br, p, action)
                        b:GetMotion():SetDesiredMoveTarget(action.hivePos)
                        move.commands = AddMoveCommand(move.commands, Move.MovementModifier)
                    end,
                }
            else
                -- At hive (or no hive found): evolve now and request Mist once
                return {
                    name            = evolveName or "teh_evolve",
                    weight          = (evolveWeight or 10),
                    desiredUpgrades = { assignedLifeform },
                    perform         = function(move, b, br, p, action)
                        p:ProcessBuyAction(action.desiredUpgrades)
                        if not b.teh_requestedMist then
                            b.teh_requestedMist = true
                            CreateVoiceMessage(p, kVoiceId.AlienRequestMist)
                        end
                        return kPlayerObjectiveComplete
                    end,
                }
            end
        else
            -- Gorge or lower-cost lifeform: evolve immediately without hive navigation
            return {
                name            = evolveName or "teh_evolve",
                weight          = (evolveWeight or 10),
                desiredUpgrades = { assignedLifeform },
                perform         = function(move, b, br, p, action)
                    p:ProcessBuyAction(action.desiredUpgrades)
                    if not b.teh_requestedMist then
                        b.teh_requestedMist = true
                        CreateVoiceMessage(p, kVoiceId.AlienRequestMist)
                    end
                    return kPlayerObjectiveComplete
                end,
            }
        end
    end
end
