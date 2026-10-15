--[[
    BOTS OBEY A HUMAN COMMANDER'S ORDERS (2026-10-14)

    When a HUMAN is commanding a bot's team and has given that bot an order with the order buttons (Move, Attack - e.g.
    Attack -> Hive -, Defend, Build, Weld...), the bot does that order and is not pulled away from it by anything except
    defending itself:
      - it still fights back (shoot / bite / reload / grenades / spores / umbra / retreat) when an enemy is close
        (seen within kSelfDefenceRange in the last kSelfDefenceMemory seconds) - and then goes straight back to the order,
        which it never forgets: the order is the bot's own (OrdersMixin), only ever cleared by completing it or by the
        Commander;
      - every other action - chasing distant targets, picking up weapons, building, welding, the bot Gorge structure
        builder, evolving, exploring... - waits until the order is done.
    Automatic orders (AutoConstruct / AutoWeld / AutoHeal) and orders from a BOT Commander are not "human orders": the
    bot plays as before. With no order, every bot decides for itself, as before.

    Applied by wrapping each bot brain's action table (TEHWrapBotActionsForHumanOrders, called at the end of each
    *Brain_Data.lua). Server only, no networking.
]]

if not Server then return end

local kSelfDefenceRange = 15
local kSelfDefenceMemory = 3
local kHumanOrderWeight = 100000      -- above every bot action weight in the game
local kSelfDefenceBonus = 200000      -- self-defence beats even the order

local kAutoOrders = {}
for _, name in ipairs({ "AutoConstruct", "AutoWeld", "AutoHeal" }) do
    local id = rawget(kTechId, name)
    if id then kAutoOrders[id] = true end
end

-- Is the bot's team commanded by a human, and has that human given this bot an order?
function TEHBotHasHumanOrder(bot)
    local player = bot and bot.GetPlayer and bot:GetPlayer()
    if not player or not player.GetCurrentOrder then return false end
    local order = player:GetCurrentOrder()
    if not order or kAutoOrders[order:GetType()] then return false end
    local team = player:GetTeam()
    local commander = team and team.GetCommander and team:GetCommander()
    local client = commander and Server.GetOwner(commander)
    return client ~= nil and not client:GetIsVirtual()
end

--[[
    (2026-10-14) ARC SIEGE CHECK for Alien bots placing a Hive (Commander bot and bot Gorges). A Hive dropped inside an
    ARC's reach dies before it finishes, so a spot is refused while the team has SEEN (its memories - never hidden
    information) a living ARC within kARCDangerRange of it in the last kARCMemoryTime seconds.
]]
local kARCDangerRange = 32          -- ARC fire range (26 m) plus room for it to roll a little closer
local kARCMemoryTime = 90
function TEHGetARCThreatNear(teamNumber, origin)
    if not origin or not GetTeamMemories then return false end
    local ok, memories = pcall(GetTeamMemories, teamNumber)
    if not ok or type(memories) ~= "table" then return false end
    local now = Shared.GetTime()
    for _, memory in ipairs(memories) do
        local ent = memory.entId and Shared.GetEntity(memory.entId)
        if ent and ent:isa("ARC") and ent:GetIsAlive() and ent:GetTeamNumber() ~= teamNumber
           and memory.lastSeenPos and (not memory.lastSeenTime or now - memory.lastSeenTime <= kARCMemoryTime)
           and (memory.lastSeenPos - origin):GetLength() <= kARCDangerRange then
            return true
        end
    end
    return false
end

-- An enemy seen close to the bot just now: it must defend itself.
local function GetMustDefend(bot, brain)
    local player = bot:GetPlayer()
    local teamBrain = brain and brain.teamBrain
    if not player or not teamBrain or not teamBrain.GetMemories then return false end
    local now = Shared.GetTime()
    local origin = player:GetOrigin()
    local enemyTeam = GetEnemyTeamNumber(player:GetTeamNumber())
    for _, memory in ipairs(teamBrain:GetMemories()) do
        if memory.team == enemyTeam and memory.lastSeenPos and memory.lastSeenTime
           and now - memory.lastSeenTime <= kSelfDefenceMemory
           and (memory.lastSeenPos - origin):GetLength() <= kSelfDefenceRange then
            return true
        end
    end
    return false
end

local kCombatWords = { "attack", "retreat", "umbra", "spore", "reload", "grenade", "babbler" }
local function IsCombatAction(name)
    if type(name) ~= "string" then return false end
    local lower = string.lower(name)
    if lower:find("structure") then return false end      -- shooting structures is not self-defence
    for _, word in ipairs(kCombatWords) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

-- Marine objective layer: FollowOrders is already the top goal, so only the IMMEDIATE actions need holding back.
local kMarineAllowed = { AttackLifeforms = true, AttackBabblers = true, ThrowHandGrenades = true,
                         ReloadPrimaryWeapon = true, ReloadPistol = true }

--[[
    kind = "marine": a Marine immediate-actions table (the order is the objective layer).
    kind = "alien":  a single-layer table with an "order" action (TEH_AlienOrderAction / Gorge's own).
]]
function TEHWrapActionList(actions, kind)
    if type(actions) ~= "table" or actions.tehHumanOrderWrapped then return end
    actions.tehHumanOrderWrapped = true

    for i, evaluate in ipairs(actions) do
        actions[i] = function(bot, brain, player, ...)
            local action = evaluate(bot, brain, player, ...)
            if type(action) ~= "table" or type(action.weight) ~= "number" then return action end
            local ok, hasOrder = pcall(TEHBotHasHumanOrder, bot)
            if not ok or not hasOrder then return action end

            local name = action.name
            if kind == "marine" then
                if kMarineAllowed[name] and action.weight > 0 then
                    if not GetMustDefend(bot, brain) then action.weight = 0 end
                elseif name == "AttackStructures" then
                    -- Allowed only for the structure the Commander ordered it to attack (that action already aims at it).
                    local order = player and player.GetCurrentOrder and player:GetCurrentOrder()
                    if not (order and order:GetType() == kTechId.Attack) then action.weight = 0 end
                elseif name == "FindMedpack" then
                    if not (player and player.GetHealthFraction and player:GetHealthFraction() < 0.35) then action.weight = 0 end
                else
                    action.weight = 0
                end
            else
                if name == "order" then
                    action.weight = kHumanOrderWeight
                elseif IsCombatAction(name) and action.weight > 0 and GetMustDefend(bot, brain) then
                    action.weight = kSelfDefenceBonus + action.weight
                else
                    -- Everything else stays below the order.
                    action.weight = math.min(action.weight, kHumanOrderWeight - 1)
                end
            end
            return action
        end
    end
end

--[[
    Every bot brain's action table is wrapped the first time that brain updates (PlayerBrain:Update), so no brain file
    needs editing. Marine brains use the "marine" rules (their order is the objective layer); every brain with an
    "order" action (all Alien lifeforms) uses the "alien" rules. Commander and Exo brains are left alone.
]]
--[[
    (2026-10-14) MARINE BOTS SPEND THEIR P-RES. The Marine brain's weapon purchase decides once per life, at random,
    whether the bot is saving for an Exo (40%) or a Jetpack (30%) and from then on keeps that much p-res back - even
    when the team has no Prototype Lab that could ever sell one. Those bots sat on 70 - 90 p-res with an Advanced Armory
    available and never bought a weapon. Now the decision is still made once, but it only HOLDS money back while the team
    can actually get that item (its Prototype Lab speciality researched); otherwise the bot buys weapons with everything
    it has. Applied every think, before the brain runs, through the brain's own bot.wantsExo / bot.wantsJetpack flags.
]]
local function TeamHasAny(teamNumber, names)
    local tree = GetTechTree and GetTechTree(teamNumber)
    if not tree then return false end
    for _, name in ipairs(names) do
        local id = rawget(kTechId, name)
        if id and tree:GetHasTech(id) then return true end
    end
    return false
end

local function UpdateMarineSavings(bot)
    local player = bot and bot.GetPlayer and bot:GetPlayer()
    if not player or not player:isa("Marine") then return end
    if bot.tehSavingRolled == nil then
        bot.tehSavingRolled = true
        bot.tehWantsExo = math.random() < 0.4
        bot.tehWantsJetpack = not bot.tehWantsExo and math.random() < 0.3
    end
    local n = player:GetTeamNumber()
    bot.decidedIfSavingForExo = true
    bot.decidedIfSavingForJetpack = true
    bot.wantsExo = bot.tehWantsExo and TeamHasAny(n, { "ExosuitPrototypeLab", "ExosuitTech" })
    bot.wantsJetpack = bot.tehWantsJetpack and TeamHasAny(n, { "JetpackPrototypeLab", "JetpackTech" })
end

-- NS2 copies inherited methods into each class when it is declared, so each brain class's own Update is hooked.
for className, kind in pairs({ MarineBrain = "marine", SkulkBrain = "alien", GorgeBrain = "alien", LerkBrain = "alien",
                               FadeBrain = "alien", OnosBrain = "alien", VokexBrain = "alien", ProwlerBrain = "alien" }) do
    local cls = rawget(_G, className)
    if cls and cls.Update and not cls.tehHumanOrdersHooked then
        cls.tehHumanOrdersHooked = true
        local baseUpdate = cls.Update
        cls.Update = function(self, bot, move)
            if kind == "marine" then pcall(UpdateMarineSavings, bot) end
            if not self.tehHumanOrdersChecked then
                self.tehHumanOrdersChecked = true
                pcall(function()
                    if self.GetActions then TEHWrapActionList(self:GetActions(), kind) end
                end)
            end
            return baseUpdate(self, bot, move)
        end
    end
end
