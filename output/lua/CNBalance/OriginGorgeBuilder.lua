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
function B.Threatened(brain, player, position)
    local now = Shared.GetTime()
    local enemyTeam = player:GetTeamNumber() == kTeam1Index and kTeam2Index or kTeam1Index
    for _, memory in ipairs(brain.teamBrain:GetMemories()) do
        if memory.team == enemyTeam
            and memory.lastSeenPos and now - memory.lastSeenTime < 20
            and Distance(memory.lastSeenPos, position) < 22 then
            return true
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

function B.Safe(brain, player, point, expansion)
    if player:GetIsInCombat() or player:GetHealthScalar() < 0.8
        or B.Threatened(brain, player, player:GetOrigin()) or B.Threatened(brain, player, point) then return false end
    if expansion then return FriendsNear(player, point) end
    local home = Home(player)
    return FriendsNear(player, point) or (home and Distance(point, home:GetOrigin()) < 12)
end

local function RouteSafe(brain, player, point)
    local path = PointArray()
    if not Pathing.GetPathPoints(player:GetOrigin(), point, path) then return false end
    local length, previous = 0, player:GetOrigin()
    for i = 1, #path do
        if B.Threatened(brain, player, path[i]) then return false end
        local delta = path[i] - previous
        local segmentLength = delta:GetLength()
        for offset = 5, segmentLength, 5 do
            if B.Threatened(brain, player, previous + delta * (offset / segmentLength)) then return false end
        end
        length = length + segmentLength
        if length >= 65 then return false end
        previous = path[i]
    end
    return length < 65 -- no long expeditions through the map
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
    if job.kind == "egg" then return Alive(target) and target:GetIsBuilt() and #Entities(player, "Egg") < job.limit end
    if job.kind == "defense" then
        return Alive(target) and target:GetIsBuilt() and NearCount(player, "Whip", target:GetOrigin(), 10) < job.limit
    end
    local hiveName = EnumToString(kTechId, target:GetTechId())
    return Alive(target) and target:GetIsBuilt()
        and (chambers[hiveName] == job.className or supports[hiveName] == job.className)
        and #Entities(player, job.className) < job.limit
end

local function Reserved(state, player, key)
    local reservation = state.reservations[key]
    return reservation and reservation.owner ~= player:GetId() and reservation.expires > Shared.GetTime()
end

function B.Plan(brain, player, ability, state)
    local function Make(kind, className, target, point, limit)
        if not point then return end
        local techId = kTechId[className]
        local key = (kind == "hive" or kind == "harvester" or kind == "cyst")
            and ("node:" .. target:GetId()) or (kind == "defense" and (className .. target:GetId()) or className)
        local expansion = kind == "hive" or kind == "harvester" or kind == "cyst"
        if Reserved(state, player, key) or not Allowed(player, ability, techId)
            or not B.Safe(brain, player, point, expansion) or not RouteSafe(brain, player, point) then return end
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
        for _, point in ipairs(points) do
            if Free(point) then
                local job = Make("hive", types[math.random(#types)], point, point:GetOrigin())
                if job then return job end
            end
        end
    end
    -- Opening Hive comes before spending on other structures; expansion Hives follow economy.
    if #hives == 0 then
        local job = HiveJob()
        if job then return job end
    end
    local nodes = GetEntities("ResourcePoint")
    table.sort(nodes, function(a, b) return Distance(a:GetOrigin(), player:GetOrigin()) < Distance(b:GetOrigin(), player:GetOrigin()) end)
    for _, node in ipairs(nodes) do
        if Free(node) and B.Safe(brain, player, node:GetOrigin(), true) then
            local job
            if GetIsPointOnInfestation(node:GetOrigin()) then
                job = Make("harvester", "Harvester", node, node:GetOrigin())
            else
                job = Make("cyst", "Cyst", node, B.CystPoint(player, node))
            end
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
            local support = supports[hiveName]
            local limit = kBiomassPerTower[#kBiomassPerTower]
            if support and #Entities(player, support) < limit then
                local job = Make("support", support, hive, Spot(player, hive:GetOrigin(), kTechId[support], hive:GetLocationName()), limit)
                if job then return job end
            end
        end
    end
    local expansion = HiveJob()
    if expansion then return expansion end
    -- Base-menu tasks are deliberately outside the Origin Form and fetch-vote gates.
    for _, hive in ipairs(hives) do
        if hive:GetIsBuilt() then
            if #Entities(player, "Egg") < 2 then
                local job = Make("egg", "Egg", hive, Spot(player, hive:GetOrigin(), kTechId.Egg, hive:GetLocationName()), 2)
                if job then return job end
            end
            if NearCount(player, "Whip", hive:GetOrigin(), 10) < 2 then
                local job = Make("defense", "Whip", hive, Spot(player, hive:GetOrigin(), kTechId.Whip, hive:GetLocationName()), 2)
                if job then return job end
            end
        end
    end
end

local function Cancel(state, player)
    if state.pending and state.pending.owner == player:GetId() then state.pending = nil end
end

-- Human Alien teammates get a 120s notice; an all-bot Alien team fetches immediately.
function B.Fund(brain, player, ability, state, job)
    local cost = kGorgeAbilitiesCost[job.techId] or 0
    if player:GetResources() >= cost then Cancel(state, player); return true end
    local team = player:GetTeam()
    local hasHumans = OriginGorgeHasHumanAliens(team)
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
        if team:GetTeamResources() >= kOriginFormTeamResourceFetchThreshold then
            state.fetchOwner = player:GetId()
            team:OnOriginFormResourceFetch(player)
            state.fetchOwner = nil
        end
        return player:GetResources() >= cost
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
        state.pending = {owner = player:GetId(), key = job.key, techId = job.techId,
            ready = now + 120, expires = now + 180}
        job.expires = math.max(job.expires or 0, now + 180)
        local structureName = job.className:gsub("(%l)(%u)", "%1 %2")
        OriginGorgeTeamMessage(team, string.format(
            "[Origin Form] Bot Gorge %s wants to use Biomass Fetch to take t-res to build %s in %s and will do so in 2 minutes",
            string.sub(player:GetName(), 1, 32), structureName, string.sub(job.room, 1, 40)))
    elseif now >= pending.ready and team:GetTeamResources() >= kOriginFormTeamResourceFetchThreshold then
        -- Use the same team method as the human buy action; no resources are fabricated.
        state.fetchOwner = player:GetId()
        team:OnOriginFormResourceFetch(player)
        state.fetchOwner = nil
        state.pending = nil
    end
    return player:GetResources() >= cost
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
                if healTarget then heal(player, healTarget, bot, brain, move); return end
                if not job or not funded then StayHome(); return end
                if Distance(player:GetOrigin(), job.point) > 4.5 then
                    if now >= (job.nextRouteCheck or 0) then
                        job.routeSafe = RouteSafe(brain, player, job.point)
                        job.nextRouteCheck = now + 0.75
                    end
                    if job.routeSafe then moveTo(player:GetOrigin(), job.point, bot, brain, move) else
                        Cancel(state, player); brain.originJob = nil; StayHome()
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
