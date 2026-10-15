--[[
    ALIENS COMMANDER BOT BUILD ORDERS (2026-10-14)

    At the start of a round (or as soon as an Aliens Commander bot takes the Hive mid-round) the bot picks one of five
    build orders, with the order of the Hive types chosen at random, and a random 2nd Hive location out of the two
    tech points nearest its main Hive. It tells the Aliens team the plan in team chat (kAlienComPlanAnnounce; off in
    Siege2.0-TEH, where the bot simply gets everything) and follows it. Once the plan is complete it goes on to finish
    the tech tree: every Hive type, 3 chambers of each, every Tunnel upgrade, Biomass to the maximum and as many Hives
    as it can.

    The plan lives on the Aliens team (team.alienComPlan) so bot Gorges (OriginGorgeBuilder.lua) can help with it:
    they cyst towards the planned Hive location and put Harvesters in that room first.

    No networking, no new entities: this is server-side bot logic only. The Commander brain calls every entry point
    through pcall (AlienCommanderBrain_Data.lua, ComPlanCall), and every function tolerates a missing plan.
]]

if not Server then return end

AlienComPlan = AlienComPlan or {}
local P = AlienComPlan

-- Siege2.0-TEH sets this to false (no plan messages; the bot goes straight for everything).
if kAlienComPlanAnnounce == nil then kAlienComPlanAnnounce = true end

local kTypes = {
    Crag  = { hive = "CragHive",  upgrade = "UpgradeToCragHive",  chamber = "Shell", chamberName = "Shells", tunnel = "CragTunnel" },
    Shift = { hive = "ShiftHive", upgrade = "UpgradeToShiftHive", chamber = "Spur",  chamberName = "Spurs",  tunnel = "ShiftTunnel" },
    Shade = { hive = "ShadeHive", upgrade = "UpgradeToShadeHive", chamber = "Veil",  chamberName = "Veils",  tunnel = "ShadeTunnel" },
}
P.kTypes = kTypes

local kBiomassRushTarget = 7
local kPlanTimeLimit = 20 * 60   -- seconds of game time before an unfinished plan gives way to "everything"

local function TechId(name) return rawget(kTechId, name) end

local function Shuffled(list)
    local result = {}
    for i, v in ipairs(list) do result[i] = v end
    for i = #result, 2, -1 do
        local j = math.random(i)
        result[i], result[j] = result[j], result[i]
    end
    return result
end

local function Alive(className, teamNumber)
    local count = 0
    for _, ent in ipairs(GetEntitiesForTeam(className, teamNumber)) do
        if ent:GetIsAlive() then count = count + 1 end
    end
    return count
end

local function HiveCount(teamNumber) return Alive("Hive", teamNumber) end

-- Does the team have (or is it upgrading to) this Hive type?
function P.HasType(teamNumber, typeName)
    local info = kTypes[typeName]
    for _, hive in ipairs(GetEntitiesForTeam("Hive", teamNumber)) do
        if hive:GetIsAlive() then
            if hive:GetTechId() == TechId(info.hive) then return true end
            if hive.GetResearchingId and hive:GetResearchingId() == TechId(info.upgrade) then return true end
        end
    end
    return false
end

local function Researched(teamNumber, techName)
    local techId = TechId(techName)
    local techTree = techId and GetTechTree(teamNumber)
    local node = techTree and techTree:GetTechNode(techId)
    return node ~= nil and (node:GetResearched() or node:GetResearching())
end

local function Biomass(team)
    return team and team.GetBioMassLevel and team:GetBioMassLevel() or 0
end

local function LocationName(entity)
    local name = entity and entity.GetLocationName and entity:GetLocationName() or ""
    return (name ~= "" and name) or "the next tech point"
end

-- The game round this plan belongs to.
local function Epoch()
    local rules = GetGamerules and GetGamerules()
    return rules and rules.GetGameStartTime and rules:GetGameStartTime() or 0
end

--[[
    The 2nd Hive: one of the two free tech points nearest the main Hive (by path length where there is a path), chosen
    at random. Re-chosen if it is taken.
]]
local function PathLength(from, to)
    local path = PointArray()
    if Pathing.GetPathPoints(from, to, path) and #path > 0 then
        local length, previous = 0, from
        for i = 1, #path do
            length = length + (path[i] - previous):GetLength()
            previous = path[i]
        end
        return length
    end
    return (from - to):GetLength() * 1.5
end

local function PickSecondHive(team)
    local main = team.GetInitialTechPoint and team:GetInitialTechPoint()
    local hives = GetEntitiesForTeam("Hive", team:GetTeamNumber())
    local origin = (hives[1] and hives[1]:GetOrigin()) or (main and main:GetOrigin())
    if not origin then return nil end
    local candidates = {}
    for _, tp in ientitylist(Shared.GetEntitiesWithClassname("TechPoint")) do
        if not tp:GetAttached() and (tp:GetOrigin() - origin):GetLength() > 5 then
            candidates[#candidates + 1] = { tp = tp, length = PathLength(origin, tp:GetOrigin()) }
        end
    end
    table.sort(candidates, function(a, b) return a.length < b.length end)
    local pick = candidates[math.random(math.min(2, #candidates))]
    return pick and pick.tp
end

function P.GetSecondHiveTP(plan, team)
    if not plan then return nil end
    local tp = plan.secondHiveTPId and Shared.GetEntity(plan.secondHiveTPId)
    if tp and tp:isa("TechPoint") then
        local attached = tp:GetAttached()
        if not attached then return tp end
        -- Ours: the 2nd Hive is in. Theirs: choose again.
        if attached:GetTeamNumber() == team:GetTeamNumber() then return nil end
    end
    if HiveCount(team:GetTeamNumber()) >= 2 then return nil end
    local oldName = tp and LocationName(tp)
    local newTP = PickSecondHive(team)
    plan.secondHiveTPId = newTP and newTP:GetId() or nil
    -- (2026-10-14) The planned spot was taken: tell the team where the 2nd Hive goes now (once per change).
    if oldName and plan.announcedLines then
        P.Notice(team, string.format("[Aliens Commander Bot]: 2nd Hive in %s not possible (Marines took it) - next: %s",
            oldName, newTP and ("2nd Hive in " .. LocationName(newTP)) or "rest of the plan until a Hive spot is free"))
    end
    return newTP
end

-- (2026-10-14) A plan change notice, never repeated within 30 s (the brain asks about the plan many times a second).
local kNoticeRepeat = 30
function P.Notice(team, text)
    if not kAlienComPlanAnnounce or not OriginGorgeTeamMessage then return end
    local now = Shared.GetTime()
    P.lastNotices = P.lastNotices or {}
    if P.lastNotices[text] and now - P.lastNotices[text] < kNoticeRepeat then return end
    P.lastNotices[text] = now
    OriginGorgeTeamMessage(team, string.sub(text, 1, 220))
end

local kStrategies = { "FastHive", "ChamberFocus", "TunnelNetwork", "TwoHivesFirst", "BiomassRush" }

local function NewPlan(team, allTech)
    local plan = { epoch = Epoch(), allTech = allTech, done = allTech }
    plan.name = kStrategies[math.random(#kStrategies)]
    local order = Shuffled({ "Crag", "Shift", "Shade" })
    if plan.name == "TunnelNetwork" then
        -- Tunnel upgrades first: the Shift Tunnel (the cheapest-travel upgrade) needs a Shift Hive.
        for i, name in ipairs(order) do
            if name == "Shift" then table.remove(order, i) break end
        end
        table.insert(order, 1, "Shift")
    end
    plan.order = order
    local tp = PickSecondHive(team)
    plan.secondHiveTPId = tp and tp:GetId() or nil
    return plan
end

-- The current team plan (creating it for this round if needed).
function P.Get(team)
    if not team or not team.GetTeamNumber then return nil end
    local plan = team.alienComPlan
    if not plan or plan.epoch ~= Epoch() then
        plan = NewPlan(team, not kAlienComPlanAnnounce)
        team.alienComPlan = plan
    end
    return plan
end

-- Read-only access for bot Gorges: the plan only while an Aliens Commander bot runs it.
function P.GetActive(team)
    local plan = team and team.alienComPlan
    if not plan or plan.epoch ~= Epoch() or not team.GetCommander then return nil end
    local commander = team:GetCommander()
    local client = commander and Server.GetOwner(commander)
    -- Only a bot Commander's plan: a human Commander makes their own calls.
    if not client or not client:GetIsVirtual() then return nil end
    return plan
end

local function Lines(plan, team)
    local t1, t2, t3 = kTypes[plan.order[1]], kTypes[plan.order[2]], kTypes[plan.order[3]]
    local mainHive = GetEntitiesForTeam("Hive", team:GetTeamNumber())[1]
    local main = LocationName(mainHive)
    local tp = P.GetSecondHiveTP(plan, team)
    local second = LocationName(tp)
    local name1, name2 = plan.order[1], plan.order[2]
    if plan.name == "FastHive" then
        return "Fast Hive", {
            string.format("2nd Hive ASAP in %s - Gorges, cyst there and take its Harvesters", second),
            string.format("%s Hive first, then 3 %s in %s", name1, t1.chamberName, main),
            string.format("Biomass up, then %s Hive + 3 %s at the 2nd Hive", name2, t2.chamberName),
            "Commander Tunnels between the Hives later on",
            string.format("Then %s Hive, all Tunnel upgrades, max Biomass and more Hives", plan.order[3]),
        }
    elseif plan.name == "ChamberFocus" then
        return "Chamber focus", {
            string.format("%s Hive first and 3 %s in %s as soon as possible", name1, t1.chamberName, main),
            string.format("2nd Hive at a normal pace in %s - Gorges, cyst there", second),
            string.format("%s Hive + 3 %s once the 2nd Hive is up", name2, t2.chamberName),
            string.format("Biomass and abilities next, %s Tunnel upgrade after", name1),
            string.format("Then %s Hive, all upgrades, max Biomass and more Hives", plan.order[3]),
        }
    elseif plan.name == "TunnelNetwork" then
        return "Tunnel network", {
            "Shift Hive first and the Shift Tunnel upgrade early",
            string.format("Commander Tunnels from %s towards %s", main, second),
            string.format("2nd Hive at a normal pace in %s - Gorges, cyst there", second),
            string.format("3 Spurs, then %s Hive + 3 %s", name2, t2.chamberName),
            string.format("Then %s Hive, all Tunnel upgrades, max Biomass and more Hives", plan.order[3]),
        }
    elseif plan.name == "TwoHivesFirst" then
        return "Two Hives first", {
            string.format("2nd Hive in %s before any chambers - Gorges, cyst there", second),
            string.format("%s Hive + 3 %s in %s", name1, t1.chamberName, main),
            string.format("%s Hive + 3 %s at the 2nd Hive", name2, t2.chamberName),
            "Biomass and abilities after the chambers",
            string.format("Then %s Hive, all Tunnel upgrades, max Biomass and more Hives", plan.order[3]),
        }
    end
    return "Biomass rush", {
        string.format("No chambers yet - straight Biomass towards %d", kBiomassRushTarget),
        string.format("2nd Hive at a normal pace in %s - Gorges, cyst there", second),
        string.format("%s Hive early, its 3 %s only after Biomass %d", name1, t1.chamberName, kBiomassRushTarget),
        string.format("Then %s Hive + 3 %s and Commander Tunnels", name2, t2.chamberName),
        string.format("Then %s Hive, all Tunnel upgrades and more Hives", plan.order[3]),
    }
end

local function Say(team, text)
    if OriginGorgeTeamMessage then
        OriginGorgeTeamMessage(team, string.sub(text, 1, 220))
    end
end

function P.Announce(plan, team)
    if not kAlienComPlanAnnounce then return end
    local title, lines = Lines(plan, team)
    plan.announcedLines = true
    Say(team, string.format("[Aliens Commander Bot build order]: %s", title))
    for i, line in ipairs(lines) do
        Say(team, string.format("%d. %s", i, line))
    end
end

-- Is the plan complete? (Then everything else is unlocked.)
local function CheckDone(plan, team)
    local n = team:GetTeamNumber()
    local hives = HiveCount(n)
    local t1, t2 = plan.order[1], plan.order[2]
    local function Chambers(typeName) return Alive(kTypes[typeName].chamber, n) end
    -- A Hive type is "done" only once its Hive exists (or is upgrading) AND it has its 3 chambers.
    local function TypeDone(typeName) return P.HasType(n, typeName) and Chambers(typeName) >= 3 end
    local tunnels = Alive("TunnelEntrance", n) >= 2

    --[[
        (2026-10-14) EVERY line of the announced plan (Lines above, 1-4; line 5 is what comes after) must be true before
        "plan complete" is said. Before, Fast Hive / Chamber focus only checked the 2nd Hive and the FIRST Hive type, so
        a Shift Hive + 3 Spurs ended a plan that still promised a Crag Hive + 3 Shells and Commander Tunnels.
    ]]
    if plan.name == "FastHive" then
        -- 1 2nd Hive, 2 first type + 3 chambers, 3 second type + 3 chambers, 4 Commander Tunnels
        return hives >= 2 and TypeDone(t1) and TypeDone(t2) and tunnels
    elseif plan.name == "ChamberFocus" then
        -- 1 first type + 3 chambers, 2 2nd Hive, 3 second type + 3 chambers, 4 the first type's Tunnel upgrade
        return hives >= 2 and TypeDone(t1) and TypeDone(t2) and Researched(n, kTypes[t1].tunnel)
    elseif plan.name == "TunnelNetwork" then
        -- 1 Shift Hive + Shift Tunnel, 2 Commander Tunnels, 3 2nd Hive, 4 3 Spurs, then second type + 3 chambers
        return hives >= 2 and TypeDone("Shift") and Researched(n, "ShiftTunnel") and tunnels and TypeDone(t2)
    elseif plan.name == "TwoHivesFirst" then
        -- 1 2nd Hive, 2 first type + 3 chambers, 3 second type + 3 chambers (4 Biomass comes after)
        return hives >= 2 and TypeDone(t1) and TypeDone(t2)
    end
    -- Biomass rush: 1 Biomass target, 2 2nd Hive, 3 first type + 3 chambers, 4 second type + 3 chambers and Tunnels
    return hives >= 2 and Biomass(team) >= kBiomassRushTarget and TypeDone(t1) and TypeDone(t2) and tunnels
end

--[[
    Called from the Commander brain's planning action every think: makes sure there is a plan for this round,
    announces it once per Commander bot, and marks it done once complete.
]]
function P.Update(brain, com)
    local team = com:GetTeam()
    local rules = GetGamerules and GetGamerules()
    if not team or not rules or not rules:GetGameStarted() then return end
    local plan = P.Get(team)
    if brain.alienComPlanAnnounced ~= plan.epoch then
        brain.alienComPlanAnnounced = plan.epoch
        if not plan.done then P.Announce(plan, team) end
    end
    if not plan.done and CheckDone(plan, team) then
        plan.done = true
        if kAlienComPlanAnnounce then
            Say(team, "[Aliens Commander Bot build order]: plan complete - now the rest of the tech and more Hives")
        end
    elseif not plan.done and Shared.GetTime() - plan.epoch >= kPlanTimeLimit then
        -- A plan that cannot be finished (Hives keep dying, a type keeps being lost) must not hold the tech tree back
        -- for the whole round: after kPlanTimeLimit the bot moves on to everything, and says so honestly.
        plan.done = true
        if kAlienComPlanAnnounce then
            Say(team, "[Aliens Commander Bot build order]: out of time for the plan - now the rest of the tech and more Hives")
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Questions the Commander brain asks. Each returns the vanilla behaviour when there is no plan.
-- ---------------------------------------------------------------------------------------------------------------

-- Which Hive type to upgrade to next, or nil to wait.
function P.NextHiveUpgrade(plan, team)
    local n = team:GetTeamNumber()
    if plan and not plan.done then
        if plan.name == "TwoHivesFirst" and HiveCount(n) < 2 then return nil end
        -- Fast Hive / Biomass rush: the second type only once the 2nd Hive is in.
        local limit = (HiveCount(n) >= 2) and 3 or 1
        if plan.name == "ChamberFocus" or plan.name == "TunnelNetwork" then limit = (HiveCount(n) >= 2) and 2 or 1 end
        for i = 1, limit do
            local typeName = plan.order[i]
            if not P.HasType(n, typeName) then return TechId(kTypes[typeName].upgrade) end
        end
        return nil
    end
    local order = plan and plan.order or { "Crag", "Shift", "Shade" }
    for _, typeName in ipairs(order) do
        if not P.HasType(n, typeName) then return TechId(kTypes[typeName].upgrade) end
    end
    return nil
end

-- How many chambers of this type the bot may have right now (0 = none yet).
function P.ChamberCap(plan, team, chamberTechId)
    if not plan or plan.done then return 3 end
    local n = team:GetTeamNumber()
    local typeName
    for name, info in pairs(kTypes) do
        if TechId(info.chamber) == chamberTechId then typeName = name end
    end
    if not typeName then return 0 end
    local hives = HiveCount(n)
    local first, second = plan.order[1], plan.order[2]
    if plan.name == "FastHive" then
        if hives < 2 then return 0 end   -- every t-res goes to the 2nd Hive first
        return (typeName == first or typeName == second) and 3 or 0
    elseif plan.name == "ChamberFocus" then
        if typeName == first then return 3 end
        return (typeName == second and hives >= 2) and 3 or 0
    elseif plan.name == "TunnelNetwork" then
        if typeName == "Shift" then return 3 end
        return (typeName == second and hives >= 2) and 3 or 0
    elseif plan.name == "TwoHivesFirst" then
        if hives < 2 then return 0 end
        return (typeName == first or typeName == second) and 3 or 0
    end
    -- Biomass rush
    if Biomass(team) < kBiomassRushTarget then return 0 end
    return (typeName == first or typeName == second) and 3 or 0
end

-- Chamber drop order: the plan's Hive types first.
function P.ChamberOrder(plan)
    local order = plan and plan.order or { "Crag", "Shift", "Shade" }
    local result = {}
    for _, typeName in ipairs(order) do
        result[#result + 1] = { TechId(kTypes[typeName].chamber), typeName }
    end
    return result
end

-- The Hive of a type (to drop its chambers next to).
function P.HiveOfType(team, typeName)
    local hiveTechId = TechId(kTypes[typeName].hive)
    for _, hive in ipairs(GetEntitiesForTeam("Hive", team:GetTeamNumber())) do
        if hive:GetIsAlive() and hive:GetIsBuilt() and hive:GetTechId() == hiveTechId then return hive end
    end
end

-- Should the commander save every t-res for the 2nd Hive right now?
function P.SavingForHive(plan, team)
    if not plan or plan.done then return false end
    return (plan.name == "FastHive") and HiveCount(team:GetTeamNumber()) < 2
end

-- Should the 2nd Hive go down now (ahead of the tech-path pace)?
function P.WantsHiveNow(plan, team, harvesterCount)
    if not plan then return false end
    local hives = HiveCount(team:GetTeamNumber())
    if plan.done then return hives < 3 end
    if hives >= 2 then return false end
    if plan.name == "FastHive" then return harvesterCount >= 2 end
    if plan.name == "TwoHivesFirst" then return harvesterCount >= 3 end
    return false
end

-- A research the plan wants now (beyond the tech path): Tunnel upgrades, Biomass rush, or anything left once done.
function P.Research(plan, team, doables, senses)
    if not plan then return nil end
    local n = team:GetTeamNumber()
    local function Doable(techName)
        local techId = TechId(techName)
        local units = techId and doables[techId]
        if type(units) ~= "table" then return nil end
        for _, unit in ipairs(units) do
            if not (unit.GetIsResearching and unit:GetIsResearching()) then return techId, unit end
        end
    end
    -- Tunnel network: the Shift Tunnel straight away. Chamber focus: its first type's Tunnel upgrade (plan line 4).
    if plan.name == "TunnelNetwork" or plan.name == "ChamberFocus" or plan.done then
        for i, typeName in ipairs(plan.order) do
            if plan.done or (plan.name == "TunnelNetwork" and typeName == "Shift")
               or (plan.name == "ChamberFocus" and i == 1) then
                local techId, unit = Doable(kTypes[typeName].tunnel)
                if techId then return techId, unit end
            end
        end
    end
    -- Biomass rush / plan done: the cheapest Biomass while the Hives allow more.
    if (plan.name == "BiomassRush" and not plan.done) or plan.done then
        local builtHives = 0
        for _, hive in ipairs(GetEntitiesForTeam("Hive", n)) do
            if hive:GetIsAlive() and hive:GetIsBuilt() then builtHives = builtHives + 1 end
        end
        local inProgress = team.GetInProgressBiomassLevel and team:GetInProgressBiomassLevel() or Biomass(team)
        local target = plan.done and math.min(12, builtHives * 4) or math.min(kBiomassRushTarget, builtHives * 4)
        -- Once done, keep 60 t-res back first so more Hives can still go down.
        if inProgress < target and (not plan.done or team:GetTeamResources() >= 60) then
            local cheapest = senses and senses:Get("cheapestBiomassUnit")
            if cheapest and cheapest.isValid then return cheapest.techId, cheapest.hiveEnt end
        end
    end
    return nil
end

-- Should Commander Tunnels be placed yet?
function P.TunnelsAllowed(plan, team, gameMinutes)
    if not plan or plan.done or plan.name == "TunnelNetwork" then return true end
    return HiveCount(team:GetTeamNumber()) >= 2 and gameMinutes >= 6
end
