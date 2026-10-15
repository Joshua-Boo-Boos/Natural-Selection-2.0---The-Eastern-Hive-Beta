-- Server-only Gorge decisions. All drops use the human Gorge ability and its checks.
if not Server then return end

OriginGorgeBuilder = {}
local B = OriginGorgeBuilder
local up = Vector(0, 1, 0)
local hiveTypes = {"CragHive", "ShadeHive", "ShiftHive"}
local chambers = {CragHive = "Shell", ShadeHive = "Veil", ShiftHive = "Spur"}
local supports = {CragHive = "Crag", ShadeHive = "Shade", ShiftHive = "Shift"}

local function Distance(a, b) return (a - b):GetLength() end
local function Alive(entity) return entity and entity:GetIsAlive() end
local function Entities(player, className)
    local result = {}
    for _, entity in ipairs(GetEntitiesForTeam(className, player:GetTeamNumber())) do
        if Alive(entity) then result[#result + 1] = entity end
    end
    return result
end

-- Do not resolve enemy entity IDs here: only the team's observed position and time
-- may affect decisions. No enumeration of hidden enemy players or structures.
--[[
    (2026-10-14) ROOM-AWARE. An enemy only threatens a point if it was seen IN THE SAME ROOM as that point (within 22 m),
    or right next to it (within kAdjacentThreatRange, whatever the room). Before, any enemy within 22 m in a straight
    line counted - through walls, from the next room - so Marines next door made the starting tech point look unsafe
    and the Gorge walked off to another one while the team had no Hive at all.
]]
local kAdjacentThreatRange = 10
function B.Threatened(brain, player, position)
    local now = Shared.GetTime()
    local enemyTeam = player:GetTeamNumber() == kTeam1Index and kTeam2Index or kTeam1Index
    local room
    for _, memory in ipairs(brain.teamBrain:GetMemories()) do
        if memory.team == enemyTeam and memory.lastSeenPos and now - memory.lastSeenTime < 20 then
            local distance = Distance(memory.lastSeenPos, position)
            if distance < kAdjacentThreatRange then return true end
            if distance < 22 then
                room = room or (GetLocationForPoint(position) and GetLocationForPoint(position):GetName() or "")
                local seenRoom = memory.lastSeenLoc
                if not seenRoom or seenRoom == "" then
                    local location = GetLocationForPoint(memory.lastSeenPos)
                    seenRoom = location and location:GetName() or ""
                end
                if room == "" or seenRoom == room then return true end
            end
        end
    end
    return false
end

local function FriendsNear(player, point)
    for _, friend in ipairs(Entities(player, "Player")) do
        if friend ~= player and not friend:isa("Commander") and not friend.isHallucination
            and Distance(friend:GetOrigin(), point) < 14 then return true end
    end
    return false
end

local function Home(player)
    local best, distance
    for _, hive in ipairs(Entities(player, "Hive")) do
        local d = Distance(hive:GetOrigin(), player:GetOrigin())
        if not distance or d < distance then best, distance = hive, d end
    end
    return best or player:GetTeam():GetInitialTechPoint()
end

--[[
    (2026-10-14) "Relatively safe": the Gorge is not badly hurt, and each place (where it stands, where it builds) either
    has no enemies seen near it recently or has friendly players with it. A scratch no longer counts: the Gorge stays
    committed to its build goal unless it is below half health, or hurt AND fighting.
]]
function B.Safe(brain, player, point, expansion)
    local health = player:GetHealthScalar()
    if health < 0.5 or (player:GetIsInCombat() and health < 0.7) then return false end
    if B.Threatened(brain, player, player:GetOrigin()) and not FriendsNear(player, player:GetOrigin()) then return false end
    if B.Threatened(brain, player, point) and not FriendsNear(player, point) then return false end
    return true
end

-- maxLength: how far the Gorge will walk for it (100 m by default; a Hive is worth crossing the map for).
local function RouteSafe(brain, player, point, maxLength)
    maxLength = maxLength or 100
    local path = PointArray()
    if not Pathing.GetPathPoints(player:GetOrigin(), point, path) then return false end
    local length, previous = 0, player:GetOrigin()
    -- A point on the way is fine if no enemy was seen near it, or friendlies are there.
    local function Unsafe(p) return B.Threatened(brain, player, p) and not FriendsNear(player, p) end
    for i = 1, #path do
        if Unsafe(path[i]) then return false end
        local delta = path[i] - previous
        local segmentLength = delta:GetLength()
        for offset = 5, segmentLength, 5 do
            if Unsafe(previous + delta * (offset / segmentLength)) then return false end
        end
        length = length + segmentLength
        if length >= maxLength then return false end
        previous = path[i]
    end
    return length < maxLength -- no long expeditions through the map (100 m reaches the next room's node / cyst link)
end

local function Room(point)
    local location = GetLocationForPoint(point)
    return location and location:GetName() or "unknown room"
end

local function Allowed(player, ability, techId)
    local structure = ability.kSupportedStructures[techId]
    if techId == kTechId.Whip and player:GetTeam():GetNumDroppedGorgeStructures(player, techId)
        >= ability:GetNumStructuresCanDrop(techId, 1) then return false end
    return structure and GetTeamStructureDropAllowed(ability, player, techId) and structure:IsAllowed(player)
end

local function Free(node) return node and node:GetAttached() == nil end
local function NearCount(player, className, point, radius)
    local count = 0
    for _, entity in ipairs(Entities(player, className)) do
        if Distance(point, entity:GetOrigin()) < radius then count = count + 1 end
    end
    return count
end

local function Ground(player, point)
    local trace = Shared.TraceRay(point + up * 3, point - up * 5,
        CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, EntityFilterOne(player))
    if trace.fraction < 1 and trace.normal.y > 0.9 and not trace.entity then return trace.endPoint end
end

local function Spot(player, center, techId, room)
    for i = 1, 16 do
        local angle = math.random() * math.pi * 2
        local radius = 2.5 + math.random() * 4
        local point = Ground(player, center + Vector(math.cos(angle) * radius, 0, math.sin(angle) * radius))
        if point and (not room or Room(point) == room) and not GetPointBlocksAttachEntities(point)
            and (not LookupTechData(techId, kTechDataRequiresInfestation) or GetIsPointOnInfestation(point)) then
            local structure = DropStructureAbility.kSupportedStructures[techId]
            if structure:GetIsPositionValid(point, player, up) then return point end
        end
    end
end

-- Outside Origin Form, extend the real connected network along a navigable path.
-- Never invent a connection or bypass the normal parent/path test.
function B.CystPoint(player, node)
    local destination = node:GetOrigin()
    if player:GetTeam():IsOriginForm() then
        if NearCount(player, "Cyst", destination, 7) > 0 then return nil end
        return Spot(player, destination, kTechId.Cyst, Room(destination))
    end
    local seeds = Entities(player, "Cyst")
    for _, hive in ipairs(Entities(player, "Hive")) do seeds[#seeds + 1] = hive end
    table.sort(seeds, function(a, b) return Distance(a:GetOrigin(), destination) < Distance(b:GetOrigin(), destination) end)
    for _, seed in ipairs(seeds) do
        if seed:GetIsBuilt() and (seed:isa("Hive") or seed:GetIsActuallyConnected()) then
            local path = PointArray()
            if Pathing.GetPathPoints(seed:GetOrigin(), destination, path) then
                -- Nav paths can contain one very long straight segment. Sample its
                -- interior as well as corners, otherwise no next link can be found.
                local samples, previous = {}, seed:GetOrigin()
                for i = 1, #path do
                    local delta = path[i] - previous
                    local length = delta:GetLength()
                    if length > 0 then
                        for offset = 3, length, 3 do
                            samples[#samples + 1] = previous + delta * (offset / length)
                        end
                    end
                    samples[#samples + 1] = path[i]
                    previous = path[i]
                end
                for i = #samples, 1, -1 do
                    local point = Ground(player, samples[i])
                    if point and Distance(point, seed:GetOrigin()) <= seed:GetCystParentRange()
                        and Distance(point, destination) < Distance(seed:GetOrigin(), destination) - 2
                        and Distance(point, seed:GetOrigin()) >= 3
                        and not GetPointBlocksAttachEntities(point) and NearCount(player, "Cyst", point, 3) == 0
                        and GetCystParentFromPoint(point, up, "GetIsActuallyConnected", nil, player:GetTeamNumber()) then
                        return point
                    end
                end
            end
        end
    end
end

function B.Valid(player, ability, job)
    if not job or not Allowed(player, ability, job.techId) then return false end
    local target = Shared.GetEntity(job.targetId)
    if not target then return false end
    if job.kind == "hive" then return Free(target) end
    if job.kind == "harvester" then return Free(target) and GetIsPointOnInfestation(target:GetOrigin()) end
    if job.kind == "cyst" then
        return Free(target) and not GetIsPointOnInfestation(target:GetOrigin())
            and NearCount(player, "Cyst", job.point, 2) == 0
            and (player:GetTeam():IsOriginForm()
                or GetCystParentFromPoint(job.point, up, "GetIsActuallyConnected", nil, player:GetTeamNumber()) ~= nil)
    end
    if job.kind == "egg" then return Alive(target) and target:GetIsBuilt() and B.NormalEggs(player) < job.limit end
    if job.kind == "defense" then
        return Alive(target) and target:GetIsBuilt() and NearCount(player, "Whip", target:GetOrigin(), 10) < job.limit
    end
    -- Any support (Crag / Shift / Shade) may go by any built Hive; a chamber needs its own Hive type.
    if job.kind == "support" then
        return Alive(target) and target:GetIsBuilt() and #Entities(player, job.className) < job.limit
    end
    local hiveName = EnumToString(kTechId, target:GetTechId())
    return Alive(target) and target:GetIsBuilt()
        and chambers[hiveName] == job.className
        and #Entities(player, job.className) < job.limit
end

--[[
    (2026-10-14) Can this Gorge pay for techId now, or through a Biomass Fetch it may use? A job it cannot pay for is
    never chosen, so a Gorge short of p-res for a Harvester still places the Cyst (or whatever it can afford) instead
    of holding the Harvester job and doing nothing.
]]
--[[
    (2026-10-14) THE TEAM'S FIRST HIVE. An Origin Form team with NO Hive loses the round, and a Gorge can only afford a
    Hive (40) with Biomass Fetch. So for a Hive while the team has none, Biomass Fetch is ALWAYS allowed: whatever the
    vote said, without waiting for the vote, and without the 15-second notice (B.Fund). The team is told why.
]]
local kHiveTechIds = {}
for _, name in ipairs({"CragHive", "ShadeHive", "ShiftHive"}) do
    local id = rawget(kTechId, name)
    if id then kHiveTechIds[id] = true end
end
function B.FirstHiveFetch(team, techId)
    if not kHiveTechIds[techId] or not team:IsOriginForm() or team:GetCommander() then return false end
    for _, hive in ipairs(GetEntitiesForTeam("Hive", team:GetTeamNumber())) do
        if hive:GetIsAlive() then return false end
    end
    return true
end

local function CanPay(player, state, techId)
    local cost = kGorgeAbilitiesCost[techId] or 0
    if player:GetResources() >= cost then return true end
    local team = player:GetTeam()
    local firstHive = B.FirstHiveFetch(team, techId)
    if not firstHive then
        if not team:IsOriginForm() or state.disallowed or team:GetCommander() then return false end
        if OriginGorgeHasHumanAliens and OriginGorgeHasHumanAliens(team) and not state.voteFinished then return false end
    end
    local pending = state.pending
    if pending and pending.owner ~= player:GetId() then return false end
    -- (2026-10-14) What one fetch would actually give (AlienTeam:OnOriginFormResourceFetch): the team's t-res, up to
    -- the initial / extra Gorge amount, and nothing below the threshold. The job is affordable only if p-res plus that
    -- covers it - so a Hive (40) is not chosen when the fetch could not pay for it.
    -- (2026-10-14) Several fetches in a row count (B.FetchUntil does them): the first gives up to the initial amount,
    -- each later one up to the extra amount, while the pool still has at least the threshold.
    local pool = math.floor(team:GetTeamResources())
    local fetches = team.timeGorgeGestated or 0
    local total = player:GetResources()
    for _ = 1, 20 do
        if total >= cost then return true end
        local desired = fetches == 0 and (kOriginFormInitialGorgePRes or 0) or (kOriginFormExtraGorgePRes or 0)
        local fetch = math.min(pool, desired)
        if fetch < kOriginFormTeamResourceFetchThreshold then break end
        total, pool, fetches = total + fetch, pool - fetch, fetches + 1
    end
    return total >= cost
end

-- (2026-10-14) Biomass Fetch as many times as needed (one at a time, each through the normal team method) until this
-- Gorge can pay for cost, or the pool runs below the threshold.
function B.FetchUntil(team, player, state, cost)
    for _ = 1, 20 do
        if player:GetResources() >= cost then break end
        if team:GetTeamResources() < kOriginFormTeamResourceFetchThreshold then break end
        local before = player:GetResources()
        state.fetchOwner = player:GetId()
        team:OnOriginFormResourceFetch(player)
        state.fetchOwner = nil
        if player:GetResources() <= before then break end
    end
    return player:GetResources() >= cost
end

--[[
    (2026-10-14) Tell the team what this bot Gorge has decided to build, e.g.
    "[Gorge] Bot Gorge Chops: placing a Cyst towards the resource node in Strand". Once per new objective, and at most
    one line per Gorge every 10 seconds.
]]
local kAnnounceInterval = 10
-- "a Harvester", "a Cyst towards the resource node", ... for a goal.
function B.Describe(job)
    local name = job.className:gsub("(%l)(%u)", "%1 %2")
    local what
    -- (2026-10-14) Kept short: team lines must stay well inside the 220-character CETeamAnnounce limit.
    if job.kind == "cyst" and job.forPlan then what = "Cyst to the planned Hive"
    elseif job.kind == "cyst" then what = "Cyst to the res node"
    elseif job.kind == "harvester" then what = "Harvester"
    elseif job.kind == "hive" then what = name
    elseif job.kind == "egg" then what = "Egg at the Hive"
    elseif job.kind == "defense" then
        -- A Whip guards either a Harvester or a Hive - say which.
        local target = Shared.GetEntity(job.targetId)
        what = (target and target:isa("Harvester")) and "Whip at the Harvester" or "Whip at the Hive"
    else what = name .. " at the Hive" end
    return what
end

--[[
    (2026-10-14) A goal that turned out NOT POSSIBLE is reported once, together with what the Gorge does instead:
    "[Gorge bot - ...] Chops: Cyst to the res node in Cargo not possible (Marines there) - next: Harvester in
    Junction". If nothing can be built next, one line says so (B.ReportIdle). Never more than one line per
    Gorge per kAnnounceInterval, and the "not possible" part only for the most recent dropped goal.
]]
function B.NoteImpossible(brain, job, reason)
    if not job then return end
    brain.originImpossible = {
        text = string.format("%s in %s not possible (%s)", B.Describe(job), string.sub(job.room or "?", 1, 40), reason),
        time = Shared.GetTime(),
    }
end

function B.ReportIdle(brain, player)
    local note = brain.originImpossible
    if not note or not OriginGorgeTeamMessage then return end
    local now = Shared.GetTime()
    if now - note.time < 4 or now < (brain.originNextAnnounce or 0) then return end   -- give a new goal a moment first
    brain.originImpossible = nil
    brain.originNextAnnounce = now + kAnnounceInterval
    OriginGorgeTeamMessage(player:GetTeam(), string.format("[Gorge bot] %s: %s - nothing else to build, helping the team",
        B.ShortName(player), note.text))
end

function B.Announce(brain, player, job)
    if not job or not OriginGorgeTeamMessage then return end
    local now = Shared.GetTime()
    if brain.originAnnouncedKey == job.key and brain.originAnnouncedRoom == job.room then return end
    if now < (brain.originNextAnnounce or 0) then return end
    brain.originAnnouncedKey, brain.originAnnouncedRoom = job.key, job.room
    brain.originNextAnnounce = now + kAnnounceInterval
    local what = B.Describe(job)
    local fetch = player:GetResources() < (kGorgeAbilitiesCost[job.techId] or 0)
    local note = brain.originImpossible
    brain.originImpossible = nil
    local text = string.format("%s %s: %s%s in %s%s",
        B.Prefix(player, job), B.ShortName(player),
        note and (note.text .. " - next: ") or "",
        what, string.sub(job.room or "?", 1, 40),
        fetch and " (Biomass Fetch)" or "")
    -- The same line again within a minute (the same objective re-planned after a retry) is not repeated.
    if brain.originLastText == text and now < (brain.originLastTextTime or 0) + 60 then return end
    brain.originLastText, brain.originLastTextTime = text, now
    OriginGorgeTeamMessage(player:GetTeam(), text)
end

-- (2026-10-14) The bot's name without the "[BOT] " tag - the prefix already says it is a Gorge bot.
function B.ShortName(player)
    local name = player:GetName() or "?"
    name = name:gsub("^%s*%[BOT%]%s*", "")
    return string.sub(name, 1, 32)
end

--[[
    (2026-10-14) "[Gorge bot - Origin Form]" when the objective needs Origin Form: a Hive, chamber or support
    structure, an unchained Cyst (Origin Form's free Cyst placement), or Biomass Fetch to pay for it.
    "[Gorge bot - non-Origin Form]" for everything a Gorge can do without it (chained Cysts, Harvesters, Eggs, Whips
    paid from its own p-res).
]]
local kOriginFormKinds = { hive = true, chamber = true, support = true }
function B.Prefix(player, job)
    local originForm = kOriginFormKinds[job.kind]
        or (job.kind == "cyst" and player:GetTeam():IsOriginForm())
        or player:GetResources() < (kGorgeAbilitiesCost[job.techId] or 0)
    return originForm and "[Gorge bot - Origin Form]" or "[Gorge bot - non-Origin Form]"
end

local function Reserved(state, player, key)
    local reservation = state.reservations[key]
    return reservation and reservation.owner ~= player:GetId() and reservation.expires > Shared.GetTime()
end

function B.Plan(brain, player, ability, state)
    local noHive = #Entities(player, "Hive") == 0
    local function Make(kind, className, target, point, limit)
        if not point then return end
        local techId = kTechId[className]
        local key = (kind == "hive" or kind == "harvester" or kind == "cyst")
            and ("node:" .. target:GetId()) or (kind == "defense" and (className .. target:GetId()) or className)
        local expansion = kind == "hive" or kind == "harvester" or kind == "cyst"
        -- (2026-10-14) A job whose drop kept failing is skipped for a while, instead of being planned again at once
        -- and retried forever (the Gorge looked stuck circling the same spot).
        local failedUntil = brain.originFailedKeys and brain.originFailedKeys[key]
        if failedUntil and Shared.GetTime() < failedUntil then return end
        if Reserved(state, player, key) or not Allowed(player, ability, techId) or not CanPay(player, state, techId)
            or not B.Safe(brain, player, point, expansion) then return end
        -- (2026-10-14) With no Hive at all, the Hive is the team's one goal: any distance, as long as the site is safe.
        -- Any Hive: up to 400 m of path (anywhere on the map); with no Hive at all, any distance.
        if not (kind == "hive" and noHive) and not RouteSafe(brain, player, point, kind == "hive" and 400 or nil) then return end
        return {kind = kind, className = className, techId = techId, targetId = target:GetId(),
            point = point, limit = limit, key = key, expansion = expansion, room = Room(point)}
    end
    local hives = Entities(player, "Hive")
    table.sort(hives, function(a, b) return Distance(a:GetOrigin(), player:GetOrigin()) < Distance(b:GetOrigin(), player:GetOrigin()) end)
    local function HiveJob()
        if not player:GetTeam():IsOriginForm() then return end
        local types = {}
        for _, name in ipairs(hiveTypes) do
            if Allowed(player, ability, kTechId[name]) then types[#types + 1] = name end
        end
        if #types == 0 then return end
        local points = GetEntities("TechPoint")
        table.sort(points, function(a, b) return Distance(a:GetOrigin(), player:GetOrigin()) < Distance(b:GetOrigin(), player:GetOrigin()) end)
        -- (2026-10-14) With no Hive, the team's own starting tech point is tried first (the team spawned there).
        local start = noHive and player:GetTeam().GetInitialTechPoint and player:GetTeam():GetInitialTechPoint()
        if start then
            for i, point in ipairs(points) do
                if point == start then table.remove(points, i) break end
            end
            table.insert(points, 1, start)
        end
        for _, point in ipairs(points) do
            -- (2026-10-14) Never under ARCs: a Hive placed in their reach just dies (TEHGetARCThreatNear).
            local underARCs = TEHGetARCThreatNear and TEHGetARCThreatNear(player:GetTeamNumber(), point:GetOrigin())
            if Free(point) and not underARCs then
                local job = Make("hive", types[math.random(#types)], point, point:GetOrigin())
                if job then return job end
            end
        end
    end
    --[[
        (2026-10-14) NO HIVE AT ALL: the Hive always comes first, whenever this Gorge's p-res plus what a Biomass Fetch
        would give covers it (CanPay, checked in Make). Until then its p-res goes on Harvesters first, then Cysts
        (chained or not, as the round allows) - and it re-checks the Hive at every plan, so the moment the team pool
        can pay for one it goes for it.
    ]]
    if #hives == 0 then
        local job = HiveJob()
        if job then return job end
    end
    --[[
        (2026-10-14) MORE HIVES FIRST. Whenever the team can pay for another Hive (this Gorge's p-res plus Biomass Fetch,
        checked by CanPay in Make) it is the top goal, before Harvesters, chambers and supports - a Hive is Biomass,
        a new spawn and a new hive type. Before, it came after every chamber and support, so t-res piled up unused.
    ]]
    if #hives > 0 then
        local job = HiveJob()
        if job then return job end
    end
    --[[
        (2026-10-14) THE ALIENS COMMANDER BOT'S BUILD ORDER (CNBalance/AlienComPlan.lua). While a Commander bot runs a
        plan, bot Gorges help it: Cysts towards the planned 2nd Hive location (chained, as without Origin Form), and
        that room's resource nodes come first for Harvesters and Cysts.
    ]]
    local comPlan, planTP
    if AlienComPlan and AlienComPlan.GetActive then
        local ok, plan = pcall(AlienComPlan.GetActive, player:GetTeam())
        comPlan = ok and plan or nil
        if comPlan then
            local okTP, tp = pcall(AlienComPlan.GetSecondHiveTP, comPlan, player:GetTeam())
            planTP = okTP and tp or nil
        end
    end
    if planTP and not GetIsPointOnInfestation(planTP:GetOrigin()) and B.Safe(brain, player, planTP:GetOrigin(), true) then
        local job = Make("cyst", "Cyst", planTP, B.CystPoint(player, planTP))
        if job then job.forPlan = true; return job end
    end
    local planRoom = planTP and Room(planTP:GetOrigin())

    local nodes = GetEntities("ResourcePoint")
    table.sort(nodes, function(a, b)
        -- The planned Hive's room first, then nearest.
        if planRoom then
            local aIn, bIn = Room(a:GetOrigin()) == planRoom, Room(b:GetOrigin()) == planRoom
            if aIn ~= bIn then return aIn end
        end
        return Distance(a:GetOrigin(), player:GetOrigin()) < Distance(b:GetOrigin(), player:GetOrigin())
    end)
    -- Harvesters on infested nodes before any Cyst towards a new one.
    for _, node in ipairs(nodes) do
        if Free(node) and GetIsPointOnInfestation(node:GetOrigin()) and B.Safe(brain, player, node:GetOrigin(), true) then
            local job = Make("harvester", "Harvester", node, node:GetOrigin())
            if job then return job end
        end
    end
    for _, node in ipairs(nodes) do
        if Free(node) and not GetIsPointOnInfestation(node:GetOrigin()) and B.Safe(brain, player, node:GetOrigin(), true) then
            local job = Make("cyst", "Cyst", node, B.CystPoint(player, node))
            if job then return job end
        end
    end
    for _, hive in ipairs(hives) do
        if hive:GetIsBuilt() then
            local hiveName = EnumToString(kTechId, hive:GetTechId())
            local chamber = chambers[hiveName]
            if chamber and #Entities(player, chamber) < 3 then
                local job = Make("chamber", chamber, hive, Spot(player, hive:GetOrigin(), kTechId[chamber], hive:GetLocationName()), 3)
                if job then return job end
            end
            --[[
                (2026-10-14) Crags, Shifts and Shades (Origin Form only - Allowed checks that), the Hive's own type first.
                Bot Gorges stop at kOriginGorgeBotMaxSupports of each type for the whole team when a mod sets it
                (Siege2.0-TEH: 6, while human Gorges may go up to the 12 cap); otherwise the biomass tower limit.
            ]]
            local limit = kOriginGorgeBotMaxSupports or kBiomassPerTower[#kBiomassPerTower]
            local own = supports[hiveName]
            local order = { own }
            for _, name in ipairs({"Crag", "Shift", "Shade"}) do
                if name ~= own then order[#order + 1] = name end
            end
            for _, support in ipairs(order) do
                if #Entities(player, support) < limit then
                    local job = Make("support", support, hive, Spot(player, hive:GetOrigin(), kTechId[support], hive:GetLocationName()), limit)
                    if job then return job end
                end
            end
        end
    end
    --[[
        (2026-10-14) Nothing for biomass, Hives or Harvesters: base-menu tasks, deliberately outside the Origin Form and
        fetch-vote gates.
          1. Normal Eggs while the team is short of them (B.WantedEggs per built Hive).
          2. Otherwise Whips, mainly guarding Harvesters on infestation (1 each), then Hives (2 each). The Gorge's own
             Whip limit still applies (Allowed).
    ]]
    local builtHives = {}
    for _, hive in ipairs(hives) do
        if hive:GetIsBuilt() then builtHives[#builtHives + 1] = hive end
    end
    local wantedEggs = B.WantedEggs(#builtHives)
    if B.NormalEggs(player) < wantedEggs then
        for _, hive in ipairs(builtHives) do
            local job = Make("egg", "Egg", hive, Spot(player, hive:GetOrigin(), kTechId.Egg, hive:GetLocationName()), wantedEggs)
            if job then return job end
        end
    end
    local harvesters = Entities(player, "Harvester")
    table.sort(harvesters, function(a, b) return Distance(a:GetOrigin(), player:GetOrigin()) < Distance(b:GetOrigin(), player:GetOrigin()) end)
    for _, harvester in ipairs(harvesters) do
        if harvester:GetIsBuilt() and GetIsPointOnInfestation(harvester:GetOrigin())
            and NearCount(player, "Whip", harvester:GetOrigin(), 10) < 1 then
            local job = Make("defense", "Whip", harvester, Spot(player, harvester:GetOrigin(), kTechId.Whip, Room(harvester:GetOrigin())), 1)
            if job then return job end
        end
    end
    for _, hive in ipairs(builtHives) do
        if NearCount(player, "Whip", hive:GetOrigin(), 10) < 2 then
            local job = Make("defense", "Whip", hive, Spot(player, hive:GetOrigin(), kTechId.Whip, hive:GetLocationName()), 2)
            if job then return job end
        end
    end
end

-- Normal Eggs only: lifeform eggs (Siege) are not the team's spawn eggs.
function B.NormalEggs(player)
    local count = 0
    for _, egg in ipairs(Entities(player, "Egg")) do
        if egg:GetTechId() == kTechId.Egg then count = count + 1 end
    end
    return count
end

-- "A lack of eggs": fewer than 3 per built Hive (at least 3).
function B.WantedEggs(builtHiveCount)
    return math.max(3, 3 * builtHiveCount)
end

local function Cancel(state, player)
    if state.pending and state.pending.owner == player:GetId() then state.pending = nil end
end

-- Human Alien teammates get a 15s notice; an all-bot Alien team fetches immediately.
function B.Fund(brain, player, ability, state, job)
    local cost = kGorgeAbilitiesCost[job.techId] or 0
    if player:GetResources() >= cost then Cancel(state, player); return true end
    local team = player:GetTeam()
    local hasHumans = OriginGorgeHasHumanAliens(team)
    -- The team's first Hive: fetch now, whatever the vote (B.FirstHiveFetch), and say why - once per round.
    if B.FirstHiveFetch(team, job.techId) and B.Valid(player, ability, job) then
        Cancel(state, player)
        if hasHumans and not state.firstHiveFetchAnnounced then
            state.firstHiveFetchAnnounced = true
            OriginGorgeTeamMessage(team, string.format(
                "[Gorge bot - Origin Form] %s: no Hive yet - Biomass Fetch for a Hive in %s (vote doesn't apply)",
                B.ShortName(player), string.sub(job.room or "?", 1, 40)))
        end
        state.firstHiveFetchOwner = player:GetId()
        local paid = B.FetchUntil(team, player, state, cost)
        state.firstHiveFetchOwner = nil
        return paid
    end
    if not team:IsOriginForm() or (hasHumans and not state.voteFinished) or state.disallowed or team:GetCommander() then
        Cancel(state, player)
        return false
    end
    if not B.Valid(player, ability, job) or not B.Safe(brain, player, job.point, job.expansion) then
        Cancel(state, player)
        return false
    end
    if not hasHumans then
        -- Recheck membership on each decision, including when the last human leaves
        -- during an announced wait. No notice or artificial delay is needed now.
        state.pending = nil
        return B.FetchUntil(team, player, state, cost)
    end
    local now = Shared.GetTime()
    local pending = state.pending
    if pending then
        local owner = Shared.GetEntity(pending.owner)
        if not Alive(owner) or not owner:isa("Gorge") or owner:GetTeamNumber() ~= team:GetTeamNumber()
            or now > pending.expires then state.pending = nil; pending = nil end
    end
    if pending and (pending.owner ~= player:GetId() or pending.key ~= job.key or pending.techId ~= job.techId) then return false end
    if not pending then
        if team:GetTeamResources() < kOriginFormTeamResourceFetchThreshold then return false end
        -- (2026-10-14) The team has just voted to allow fetching, so the FIRST fetch after the vote needs no notice.
        if not state.firstFetchDone then
            state.firstFetchDone = true
            return B.FetchUntil(team, player, state, cost)
        end
        state.pending = {owner = player:GetId(), key = job.key, techId = job.techId,
            ready = now + 15, expires = now + 75}   -- (2026-10-14) 15-second notice (was 120)
        job.expires = math.max(job.expires or 0, now + 75)
        local structureName = job.className:gsub("(%l)(%u)", "%1 %2")
        OriginGorgeTeamMessage(team, string.format(
            "[Gorge bot - Origin Form] %s: Biomass Fetch (t-res) for %s in %s in 15 seconds",
            B.ShortName(player), structureName, string.sub(job.room, 1, 40)))
    elseif now >= pending.ready and team:GetTeamResources() >= kOriginFormTeamResourceFetchThreshold then
        -- Use the same team method as the human buy action; no resources are fabricated. One notice covers every
        -- fetch this objective needs.
        B.FetchUntil(team, player, state, cost)
        state.pending = nil
    end
    return player:GetResources() >= cost
end

--[[
    HAS WORK (2026-10-13). The builder action replaces the Gorge's whole action list (GorgeBrain_Data.lua), so whenever
    it had nothing to do - no job, a job it cannot pay for yet, or a Biomass Fetch notice still counting down - it
    called StayHome and the Gorge stood still next to the Hive with every normal Gorge behaviour (healing teammates,
    following, attacking, retreating, tunnels...) switched off. The wrapper now asks this first and only hands the
    Gorge to the builder when there is something for it to do right now:
      * the Gorge is not safe at home (the builder's stay-home-and-heal behaviour);
      * a friendly structure within 14 m needs finishing or healing;
      * it has (or can plan) a valid job, and can pay for it: its own resources, or a Biomass Fetch it may start now
        (Origin Form, fetching not voted off, no Commander, vote finished when humans are on the team, team resources
        at the threshold) or whose 15-second notice has finished.
    Planning here uses the same B.Plan / job bookkeeping as the action, so a job planned here is the one it performs.
    No resources are fetched here - only B.Fund (in the action) does that.
]]
--[[
    (2026-10-14) A job given up (stuck on the way, or could not be placed): skip it for 30 s the first time, then
    60, 120, up to 5 minutes for each further failure of the same job, so a Gorge does not keep going back to a site it
    cannot reach. The builder also lets go of the Gorge for 10 s, so it plays normally and moves somewhere else first.
]]
function B.Fail(brain, key, now)
    brain.originFailedKeys = brain.originFailedKeys or {}
    brain.originFailCounts = brain.originFailCounts or {}
    local count = (brain.originFailCounts[key] or 0) + 1
    brain.originFailCounts[key] = count
    brain.originFailedKeys[key] = now + math.min(300, 30 * 2 ^ (count - 1))
    brain.originPauseUntil = now + 10
end

-- Goal priority, best first (the order B.Plan tries them). Used to decide whether a re-plan is worth switching to.
local kReplanInterval = 5
local kUnaffordableGrace = 5
local kCommitTime = 15
local kMaxSwitches, kSwitchWindow, kLockTime = 3, 60, 45

-- Record a change of goal: commit to the next one for a while, and lock it if the Gorge keeps changing its mind.
function B.NoteSwitch(brain, now)
    brain.originNextReplan = math.max(brain.originNextReplan or 0, now + kCommitTime)
    local recent = {}
    for _, t in ipairs(brain.originSwitchTimes or {}) do
        if now - t < kSwitchWindow then recent[#recent + 1] = t end
    end
    recent[#recent + 1] = now
    brain.originSwitchTimes = recent
    if #recent > kMaxSwitches then
        brain.originGoalLockedUntil = now + kLockTime
        brain.originSwitchTimes = {}
    end
end
local kJobRank = { hive = 1, harvester = 2, cyst = 3, chamber = 4, support = 5, egg = 6, defense = 7 }

-- Let go of a goal: its reservation, and this Gorge's Biomass Fetch notice for it (so nobody waits on it).
function B.DropJob(brain, state, player, job)
    if job and state.reservations[job.key] and state.reservations[job.key].owner == player:GetId() then
        state.reservations[job.key] = nil
    end
    if state.pending and state.pending.owner == player:GetId() then state.pending = nil end
    brain.originJob = nil
end

function B.HasWork(bot, brain, player)

    local state = GetOriginGorgeState and GetOriginGorgeState(player:GetTeam())
    if not state or player.isHallucination or not player:GetIsAlive() then return false end
    -- (2026-10-14) A human Commander's order always comes first (CNBalance/BotHumanOrders.lua). The build goal is kept
    -- (brain.originJob) and picked up again once the order is done.
    if TEHBotHasHumanOrder and TEHBotHasHumanOrder(bot) then return false end
    local ability = player:GetWeapon(DropTeamStructureAbility.kMapName)
    if not ability then return false end
    -- Just gave a job up (B.Fail): play normally for a few seconds first.
    if Shared.GetTime() < (brain.originPauseUntil or 0) then return false end

    if brain.originEpoch ~= state.epoch then
        brain.originEpoch = state.epoch
        brain.originJob = nil
        brain.originNextPlan = nil
        brain.originNextDrop = nil
    end
    -- (2026-10-14) The Biomass Fetch vote just ended: decide straight away instead of waiting for the next plan cycle.
    if state.voteFinishedTime and brain.originVoteSeen ~= state.voteFinishedTime then
        brain.originVoteSeen = state.voteFinishedTime
        brain.originJob = nil
        brain.originNextPlan = nil
    end

    -- (2026-10-14) Not safe: the Gorge plays normally (fights, retreats, heals) instead of being held at the Hive.
    if not B.Safe(brain, player, player:GetOrigin(), false) then return false end

    for _, entity in ipairs(GetEntitiesWithMixinForTeamWithinRange("Live", player:GetTeamNumber(), player:GetOrigin(), 14)) do
        local unfinished = entity.GetIsBuilt and not entity:GetIsBuilt() and entity.CanBeBuilt and entity:CanBeBuilt()
        local damaged = entity.GetCanBeHealed and entity:GetCanBeHealed() and entity:GetHealthScalar() < 0.95
        if entity ~= player and Alive(entity) and (unfinished or damaged)
            and B.Safe(brain, player, entity:GetOrigin(), false) then
            return true
        end
    end

    local now = Shared.GetTime()
    local job = brain.originJob
    -- A goal that is no longer possible - a human Gorge already built it, a human's Biomass Fetch left too little to pay
    -- for it, the site was taken - is dropped (with this Gorge's own fetch notice, if any) and a new one chosen at once.
    --[[
        (2026-10-14) NO GOAL FLIP-FLOPPING:
          * "Can't pay" must last kUnaffordableGrace seconds before the goal is dropped, so a pool hovering around the
            price (a fetch here, a spend there) does not bounce the Gorge between goals.
          * After ANY change of goal the Gorge commits to the new one for kCommitTime before a re-plan may switch it.
          * More than kMaxSwitches changes within kSwitchWindow without placing anything locks the current goal for
            kLockTime: only an impossible goal (built by someone else, site taken, unsafe) is dropped then.
        The stuck watchdog in the action still gives up a goal it cannot get closer to.
    ]]
    if job then
        if CanPay(player, state, job.techId) then
            job.unaffordableSince = nil
        else
            job.unaffordableSince = job.unaffordableSince or now
        end
    end
    local unaffordable = job and job.unaffordableSince and now - job.unaffordableSince >= kUnaffordableGrace
    if job and (not B.Valid(player, ability, job) or not B.Safe(brain, player, job.point, job.expansion)
        or Reserved(state, player, job.key) or now > job.expires or unaffordable) then
        local reason
        if not B.Valid(player, ability, job) and job.forPlan then reason = "Hive spot taken"
        elseif not B.Valid(player, ability, job) then reason = "already built or site taken"
        elseif unaffordable then reason = "not enough res"
        elseif Reserved(state, player, job.key) then reason = "another Gorge is on it"
        elseif now > job.expires then reason = "took too long"
        else reason = "Marines there" end
        -- Getting hurt is not the goal being impossible - only report real reasons.
        if B.Safe(brain, player, player:GetOrigin(), false) then B.NoteImpossible(brain, job, reason) end
        B.DropJob(brain, state, player, job)
        B.NoteSwitch(brain, now)
        job = nil
        brain.originNextPlan = now
    end
    if not job and now >= (brain.originNextPlan or 0) then
        job = B.Plan(brain, player, ability, state)
        brain.originNextPlan = now + 3
        brain.originJob = job
        if job then job.expires = now + 240 end
    end
    --[[
        (2026-10-14) RE-PLAN AS THE TEAM CHANGES. Every kReplanInterval the Gorge works out the best goal again from the
        current state (what human Gorges have built, t-res a human has fetched or left in the pool, Hives lost or
        gained). If that goal ranks higher than the one it is on - e.g. a Hive has become affordable, or the Harvester
        it was cysting towards was already placed by a human - it switches. A goal it is about to place (at the site
        and able to pay) is finished first.
    ]]
    if job and now >= (brain.originNextReplan or 0) and now >= (brain.originGoalLockedUntil or 0) then
        brain.originNextReplan = now + kReplanInterval
        local nearlyDone = Distance(player:GetOrigin(), job.point) <= 6
            and player:GetResources() >= (kGorgeAbilitiesCost[job.techId] or 0)
        if not nearlyDone then
            local better = B.Plan(brain, player, ability, state)
            if better and better.key ~= job.key and (kJobRank[better.kind] or 99) < (kJobRank[job.kind] or 99) then
                B.DropJob(brain, state, player, job)
                B.NoteSwitch(brain, now)
                job = better
                job.expires = now + 240
                brain.originJob = job
            end
        end
    end
    if not job then
        B.ReportIdle(brain, player)
        return false
    end
    B.Announce(brain, player, job)

    if player:GetResources() >= (kGorgeAbilitiesCost[job.techId] or 0) then return true end

    local team = player:GetTeam()
    -- The team's first Hive is always paid for (B.FirstHiveFetch): go and drop it now.
    if B.FirstHiveFetch(team, job.techId) then return true end
    if not team:IsOriginForm() or state.disallowed or team:GetCommander() then return false end
    local hasHumans = OriginGorgeHasHumanAliens and OriginGorgeHasHumanAliens(team)
    if hasHumans and not state.voteFinished then return false end

    local pending = state.pending
    if pending and pending.owner == player:GetId() then
        -- (2026-10-14) Notice still counting down: stay on the goal (walk to the site and wait there), not wander off.
        return true
    end
    if pending then return false end    -- another Gorge holds the fetch notice
    return team:GetTeamResources() >= kOriginFormTeamResourceFetchThreshold

end

function B.CreateAction(moveTo, heal)
    return function(bot, brain, player)
        return {name = "origin gorge builder", weight = 2000, fastUpdate = true,
            perform = function(move)
                local state = GetOriginGorgeState and GetOriginGorgeState(player:GetTeam())
                if not state or player.isHallucination or not player:GetIsAlive() then return end
                if brain.originEpoch ~= state.epoch then
                    brain.originEpoch = state.epoch
                    brain.originJob = nil
                    brain.originNextPlan = nil
                    brain.originNextDrop = nil
                end
                local ability = player:GetWeapon(DropTeamStructureAbility.kMapName)
                if not ability then return end
                local now = Shared.GetTime()
                local home = Home(player)
                player:SetActiveWeapon(SpitSpray.kMapName, true)
                local function StayHome()
                    if home and Distance(player:GetOrigin(), home:GetOrigin()) > 7 then
                        moveTo(player:GetOrigin(), home:GetOrigin(), bot, brain, move)
                    else
                        bot:GetMotion():SetDesiredMoveTarget(nil)
                        bot:GetMotion():SetDesiredMoveDirection(nil)
                    end
                end
                if not B.Safe(brain, player, player:GetOrigin(), false) then
                    Cancel(state, player)
                    brain.originJob = nil
                    StayHome()
                    -- In a threatened Hive room, keep spraying nearby visible friends
                    -- without following them out into the fight.
                    for _, friend in ipairs(GetEntitiesWithMixinForTeamWithinRange("Live", player:GetTeamNumber(), player:GetOrigin(), 4)) do
                        if friend ~= player and Alive(friend) and friend.GetCanBeHealed and friend:GetCanBeHealed()
                            and friend:GetHealthScalar() < 0.95 and bot:GetBotCanSeeTarget(friend) then
                            bot:GetMotion():SetDesiredViewTarget(friend:GetOrigin())
                            move.commands = AddMoveCommand(move.commands, Move.SecondaryAttack)
                            break
                        end
                    end
                    if player:GetHealthScalar() < 0.95 then move.commands = AddMoveCommand(move.commands, Move.SecondaryAttack) end
                    return
                end
                local job = brain.originJob
                if job and (not B.Valid(player, ability, job) or not B.Safe(brain, player, job.point, job.expansion)
                    or Reserved(state, player, job.key) or now > job.expires) then
                    Cancel(state, player)
                    if state.reservations[job.key] and state.reservations[job.key].owner == player:GetId() then state.reservations[job.key] = nil end
                    job = nil
                    brain.originJob = nil
                end
                if not job and now >= (brain.originNextPlan or 0) then
                    job = B.Plan(brain, player, ability, state)
                    brain.originNextPlan = now + 3
                    brain.originJob = job
                    if job then job.expires = now + 240 end
                end
                if job then B.Announce(brain, player, job) end
                local funded = false
                if job then
                    state.reservations[job.key] = {owner = player:GetId(), expires = now + 5}
                    funded = B.Fund(brain, player, ability, state, job)
                end
                -- Finish and repair friendly structures before placing another. This also
                -- lets a Gorge remain useful at home throughout a pending resource request.
                local healTarget, best = nil, math.huge
                for _, entity in ipairs(GetEntitiesWithMixinForTeamWithinRange("Live", player:GetTeamNumber(), player:GetOrigin(), 14)) do
                    local unfinished = entity.GetIsBuilt and not entity:GetIsBuilt() and entity.CanBeBuilt and entity:CanBeBuilt()
                    local damaged = entity.GetCanBeHealed and entity:GetCanBeHealed() and entity:GetHealthScalar() < 0.95
                    if entity ~= player and Alive(entity) and (unfinished or damaged)
                        and B.Safe(brain, player, entity:GetOrigin(), false) then
                        local priority = Distance(player:GetOrigin(), entity:GetOrigin()) - (unfinished and 20 or 0)
                        if priority < best then healTarget, best = entity, priority end
                    end
                end
                if healTarget then
                    -- Time spent healing is not "stuck" (watchdog below).
                    if job then job.lastProgress = now; job.atSiteSince = nil end
                    heal(player, healTarget, bot, brain, move)
                    return
                end
                if not job then StayHome(); return end
                if not funded then
                    -- (2026-10-14) Waiting for this Gorge's own Biomass Fetch notice: go to the site and wait there, so
                    -- it is ready to drop the moment the t-res arrives. Otherwise (no way to pay yet) hold at home.
                    local myNotice = state.pending and state.pending.owner == player:GetId()
                    if myNotice and now >= (job.nextRouteCheck or 0) then
                        job.routeSafe = RouteSafe(brain, player, job.point, job.kind == "hive" and 400 or nil)
                        job.nextRouteCheck = now + 0.75
                    end
                    if myNotice and Distance(player:GetOrigin(), job.point) > 4.5 and job.routeSafe then
                        job.lastProgress = now   -- waiting is not being stuck
                        moveTo(player:GetOrigin(), job.point, bot, brain, move)
                    elseif myNotice then
                        job.lastProgress = now
                        job.atSiteSince = nil
                        bot:GetMotion():SetDesiredMoveTarget(nil)
                        bot:GetMotion():SetDesiredViewTarget(job.point)
                    else
                        StayHome()
                    end
                    return
                end
                --[[
                    (2026-10-14) STUCK WATCHDOG. The Gorge gives a job up (and skips it for 30 s, B.Plan) when, while
                    walking to it, it has not got 1.5 m closer for 6 s, or when it has spent 20 s at the site without
                    managing to place it - so it never loiters around one spot.
                ]]
                local function GiveUp(reason)
                    B.NoteImpossible(brain, job, reason)
                    brain.originJob = nil
                    state.reservations[job.key] = nil
                    Cancel(state, player)
                    B.Fail(brain, job.key, now)
                    brain.originNextPlan = now
                end
                local distanceToSite = Distance(player:GetOrigin(), job.point)
                if not job.bestDistance or distanceToSite < job.bestDistance - 1.5 then
                    job.bestDistance = distanceToSite
                    job.lastProgress = now
                end
                if distanceToSite > 4.5 and now - (job.lastProgress or now) > 6 then GiveUp("can't get there"); return end
                if distanceToSite <= 4.5 then
                    job.atSiteSince = job.atSiteSince or now
                    if now - job.atSiteSince > 20 then GiveUp("no room there"); return end
                else
                    job.atSiteSince = nil
                end
                if Distance(player:GetOrigin(), job.point) > 4.5 then
                    if now >= (job.nextRouteCheck or 0) then
                        job.routeSafe = RouteSafe(brain, player, job.point, job.kind == "hive" and 400 or nil)
                        job.nextRouteCheck = now + 0.75
                    end
                    if job.routeSafe then moveTo(player:GetOrigin(), job.point, bot, brain, move) else
                        -- The way there is no longer safe (or too long): drop it rather than re-planning it at once.
                        B.NoteImpossible(brain, job, "path blocked by Marines")
                        state.reservations[job.key] = nil
                        Cancel(state, player); brain.originJob = nil
                        B.Fail(brain, job.key, now)
                    end
                    return
                end
                bot:GetMotion():SetDesiredMoveTarget(nil)
                bot:GetMotion():SetDesiredViewTarget(job.point)
                if now < (brain.originNextDrop or 0) or ability:GetHasDropCooldown() then return end
                brain.originNextDrop = now + 1
                local direction = (job.point - player:GetEyePos()):GetUnit()
                local structure = ability.kSupportedStructures[job.techId]
                local coords, valid = ability:GetPositionForStructure(player:GetEyePos(), direction, structure)
                -- The ray must hit the intended site, not an intervening wall or another node.
                local intendedOrigin = job.point + up * (LookupTechData(job.techId, kTechDataSpawnHeightOffset, 0) or 0)
                if valid and Distance(coords.origin, intendedOrigin) < 2
                    and (job.kind ~= "cyst" or player:GetTeam():IsOriginForm()
                        or GetCystParentFromPoint(coords.origin, up, "GetIsActuallyConnected", nil, player:GetTeamNumber())) then
                    local before = player:GetResources()
                    ability:OnDropStructure(player:GetEyePos(), direction, job.techId)
                    if player:GetResources() < before then
                        if brain.originFailCounts then brain.originFailCounts[job.key] = nil end
                        brain.originSwitchTimes = {}       -- it placed something: not flip-flopping
                        state.reservations[job.key] = nil
                        brain.originJob = nil
                        brain.originNextPlan = now + 2
                    end
                else
                    job.failed = (job.failed or 0) + 1
                    if job.failed >= 4 then
                        brain.originJob = nil
                        state.reservations[job.key] = nil
                        Cancel(state, player)
                        -- Skip this job for a while (B.Fail), so the Gorge moves on to something else.
                        B.NoteImpossible(brain, job, "no room there")
                        B.Fail(brain, job.key, now)
                    end
                    -- Change the approach rather than repeatedly firing into an obstruction.
                    local angle = math.random() * math.pi * 2
                    local approach = job.point + Vector(math.cos(angle) * 3, 0, math.sin(angle) * 3)
                    if B.Safe(brain, player, approach, job.expansion) and RouteSafe(brain, player, approach) then
                        moveTo(player:GetOrigin(), approach, bot, brain, move)
                    end
                end
            end}
    end
end
