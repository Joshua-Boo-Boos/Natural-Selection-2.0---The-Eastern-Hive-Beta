-- TEHBotManager.lua
-- Loaded after CommonAlienActions.lua (via Script.Load in PlayerBot_Server.lua).
-- Provides two features:
--
--   1. Lifeform Assignment: 20 seconds after a round starts, all alien bots are
--      given an assigned lifeform (bot.teh_assignedLifeform) from the six evolution
--      targets (Gorge/Prowler/Lerk/Fade/Vokex/Onos — Skulk excluded so no bot
--      wastes its slot staying as the starting form). Each bot also gets a staggered
--      reassessment timer (bot.teh_nextReassignTime) so they re-evaluate every ~30 s.
--      When the timer fires, TEH_GetMostNeededLifeform counts the current distribution
--      across ALL alien players (human + bot) and returns the least-represented form.
--      Lua's single-threaded execution means each reassignment is visible to the next
--      bot before it queries, preventing mass-simultaneous picks.
--      Respawn detection (teh_wasEvolved): when a bot transitions evolved→Skulk its
--      old timer is already expired; without correction every bot in the same fight
--      reassesses on the same tick and all pile onto whichever form is momentarily
--      at count 0. The respawn stagger re-scatters those timers over 12 s.
--
--   2. Safe Evolution: Assigned bots navigate to a built Hive before evolving, and
--      only trigger evolution when no Marine-team player has line of sight.

local kTEHAssignDelay     = 20.0  -- seconds after game start before first assignment
local kTEHReassessBase    = 30.0  -- seconds between individual bot reassessments
local kTEHReassessJitter  = 5.0   -- ± random jitter on each reassessment interval
local kTEHInitialSpread   = 30.0  -- spread (0..this) for staggering the first reassessment
local kTEHRespawnStagger  = 12.0  -- spread (0..this) used to re-stagger a bot whose timer
                                  -- expired while it was evolved (i.e. it just respawned)
local kTEHHiveEvolveDist  = 10.0  -- distance from Hive origin at which bot may evolve
local kTEHEvolveSafeRange = 25.0  -- max range at which a Marine blocks evolution
local kTEHNavTimeout      = 12.0  -- max seconds a bot will try to path to its hive before
                                  -- giving up and playing normally (avoids walk-into-wall freezes)
local kTEHEvolveRetryDelay = 8.0  -- after giving up, seconds to play normally before retrying
local kTEHEvolveSpotRadius = 6.0  -- search radius (around the hive) for a valid evolve spot
                                  -- with room for the target lifeform's body

-- The six evolution targets (Skulk excluded: it is the starting form, not an upgrade).
-- Bots are always assigned one of these so no slot is wasted on "stay Skulk".
local kTEHLifeforms = {
    kTechId.Gorge,
    kTechId.Prowler,
    kTechId.Lerk,
    kTechId.Fade,
    kTechId.Vokex,
    kTechId.Onos,
}
local kTEHLifeformCount = #kTEHLifeforms  -- 6

-- Class names for marine-team players (human and bot)
local kMarinePlayerClasses = { "Marine", "JetpackMarine", "ExoSuit" }

-- Lazy-initialised mapping: lifeform tech-id → class name string
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

-- The gameStartTime for which we last ran initial assignment (-1 = never)
local gTEHAssignedGameStartTime = -1

-- ---------------------------------------------------------------------------
-- IsSafeToEvolve(alienPlayer)
-- Returns true if no Marine-team player has line-of-sight within
-- kTEHEvolveSafeRange units.
-- ---------------------------------------------------------------------------
local function IsSafeToEvolve(alienPlayer)
    local alienPos = alienPlayer:GetOrigin() + Vector(0, 1, 0)

    for _, className in ipairs(kMarinePlayerClasses) do
        local entityList = Shared.GetEntitiesWithClassname(className)
        for i = 0, entityList:GetSize() - 1 do
            local marine = entityList:Get(i)
            if IsValid(marine) and marine:GetTeamNumber() == kMarineTeamType and marine:GetIsAlive() then
                local marinePos = marine:GetOrigin() + Vector(0, 1.5, 0)
                if (marinePos - alienPos):GetLength() <= kTEHEvolveSafeRange then
                    local trace = Shared.TraceRay(
                        marinePos, alienPos,
                        CollisionRep.LOS,
                        PhysicsMask.AllButPCsAndRagdolls,
                        EntityFilterTwo(alienPlayer, marine)
                    )
                    if trace.fraction >= 1.0 then
                        return false
                    end
                end
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- TEH_TrySpawnMist(player, origin)
-- Bots have no commander to mist their gestation, so spawn one nutrient mist
-- (once per bot — the caller gates this with bot.teh_requestedMist) at the
-- evolve spot to catalyse it. Conditions:
--   * Origin Form must NOT be researched (that tech reworks the alien economy).
--   * The team can AFFORD the mist's cost, OR an alien commander is present.
-- When affordable, the team-resource cost is deducted so the mist isn't free;
-- if only the presence of a commander permitted it, resources are left alone.
-- A standalone NutrientMist is safe to create: its OnInitialized SetOwner(nil)
-- is harmless and Perform() only reads origin/team/id, never the owner.
-- ---------------------------------------------------------------------------
local kNutrientMistMapName = "nutrientmist"

local function TEH_TrySpawnMist(player, origin)
    if not Server then return end

    local team = player.GetTeam and player:GetTeam()
    if not team then return end

    -- No auto-mist while Origin Form is active.
    if team.IsOriginForm and team:IsOriginForm() then
        return
    end

    local mistCost     = kNutrientMistCost or 2
    local teamRes      = (team.GetTeamResources and team:GetTeamResources()) or 0
    local canAfford    = teamRes >= mistCost
    local hasCommander = team.GetHasCommander and team:GetHasCommander()

    if not (canAfford or hasCommander) then
        return
    end

    local mist = CreateEntity(kNutrientMistMapName, origin, player:GetTeamNumber())
    if mist and canAfford and team.AddTeamResources then
        team:AddTeamResources(-mistCost)
    end
end

-- ---------------------------------------------------------------------------
-- TEH_GetMostNeededLifeform(excludeBot)
-- Counts the current lifeform distribution across all alien-team bots
-- (excluding excludeBot so we count its REPLACEMENT need, not its own slot).
-- For each bot: counts its actual class if already evolved past Skulk,
-- otherwise counts its assigned lifeform (or Skulk if unassigned).
-- Returns the lifeform (from kTEHLifeforms) with the lowest count.
-- Ties are broken randomly. Single-threaded Lua means each bot that
-- reassigns in a given tick updates the distribution before the next one sees it.
-- ---------------------------------------------------------------------------
local function TEH_GetMostNeededLifeform(excludeBot)
    local counts = {}
    for _, lf in ipairs(kTEHLifeforms) do
        counts[lf] = 0
    end

    local lifeformToClass = GetLifeformToClass()

    -- ---- Bot contribution ----
    -- Evolved bots count by actual class; Skulk bots count by their pending assignment.
    for _, bot in ipairs(gServerBots) do
        if bot ~= excludeBot then
            local player = bot:GetPlayer()
            if IsValid(player) and player:GetTeamNumber() == kAlienTeamType then
                local counted = false
                for lf, className in pairs(lifeformToClass) do
                    if not counted and lf ~= kTechId.Skulk and player:isa(className) then
                        if counts[lf] ~= nil then
                            counts[lf] = counts[lf] + 1
                        end
                        counted = true
                    end
                end
                -- Still a Skulk: reserve their assigned lifeform slot.
                if not counted then
                    local assignment = bot.teh_assignedLifeform
                    if assignment and counts[assignment] ~= nil then
                        counts[assignment] = counts[assignment] + 1
                    end
                    -- No assignment yet → bot doesn't affect the distribution.
                end
            end
        end
    end

    -- ---- Human alien player contribution ----
    -- Count actual evolved lifeforms played by human (non-bot) alien players so that
    -- the assignment spreads around whatever humans are already playing.
    for lf, className in pairs(lifeformToClass) do
        if lf ~= kTechId.Skulk and counts[lf] ~= nil then
            local entityList = Shared.GetEntitiesWithClassname(className)
            for i = 0, entityList:GetSize() - 1 do
                local player = entityList:Get(i)
                if IsValid(player) and player:GetTeamNumber() == kAlienTeamType then
                    -- Skip bot players (already counted above).
                    local isBot = false
                    for _, bot in ipairs(gServerBots) do
                        local bp = bot:GetPlayer()
                        if IsValid(bp) and bp == player then
                            isBot = true
                            break
                        end
                    end
                    if not isBot then
                        counts[lf] = counts[lf] + 1
                    end
                end
            end
        end
    end

    -- ---- Pick the least-represented lifeform, breaking ties randomly ----
    local minCount = math.huge
    local minLifeforms = {}
    for _, lf in ipairs(kTEHLifeforms) do
        local c = counts[lf] or 0
        if c < minCount then
            minCount = c
            minLifeforms = { lf }
        elseif c == minCount then
            minLifeforms[#minLifeforms + 1] = lf
        end
    end

    return minLifeforms[math.random(#minLifeforms)]
end

-- ---------------------------------------------------------------------------
-- TEH_AssignLifeforms()
-- Initial balanced assignment at the 20-second mark.
-- Sets bot.teh_assignedLifeform and bot.teh_nextReassignTime (staggered).
-- ---------------------------------------------------------------------------
local function TEH_AssignLifeforms()
    for _, bot in ipairs(gServerBots) do
        bot.teh_assignedLifeform = nil
        bot.teh_requestedMist    = nil
        bot.teh_nextReassignTime = nil
        bot.teh_wasEvolved       = nil
        bot.teh_navStart         = nil
        bot.teh_evolveRetryAfter = nil
        bot.teh_evolveSpot       = nil
    end

    local alienBots = {}
    for _, bot in ipairs(gServerBots) do
        local player = bot:GetPlayer()
        if IsValid(player) and player:GetTeamNumber() == kAlienTeamType then
            table.insert(alienBots, bot)
        end
    end

    local n = #alienBots
    if n == 0 then return end

    -- Shuffle so assignment order is random each round.
    for i = n, 2, -1 do
        local j = math.random(i)
        alienBots[i], alienBots[j] = alienBots[j], alienBots[i]
    end

    -- Build assignment list: basePerLifeform of each, then remainder cycling.
    local assignments = {}
    local basePerLifeform = math.floor(n / kTEHLifeformCount)
    local remainder       = n - basePerLifeform * kTEHLifeformCount

    for _, lifeformId in ipairs(kTEHLifeforms) do
        for _ = 1, basePerLifeform do
            table.insert(assignments, lifeformId)
        end
    end
    if remainder > 0 then
        local startIdx = math.random(kTEHLifeformCount)
        for r = 0, remainder - 1 do
            local idx = ((startIdx - 1 + r) % kTEHLifeformCount) + 1
            table.insert(assignments, kTEHLifeforms[idx])
        end
    end

    local now = Shared.GetTime()
    for i, bot in ipairs(alienBots) do
        bot.teh_assignedLifeform = assignments[i]
        -- Stagger each bot's first reassessment randomly across kTEHInitialSpread seconds
        -- so they never all fire at the same time.
        bot.teh_nextReassignTime = now + math.random() * kTEHInitialSpread
    end

    Log("[TEHBotManager] Assigned lifeforms to %d alien bots (base/lifeform=%d, remainder=%d)",
        n, basePerLifeform, remainder)
end

-- ---------------------------------------------------------------------------
-- Helper: trigger initial assignment once per round.
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

    return function(bot, brain, player)
        PROFILE("TEHBotManager - Evolve")

        TEH_CheckAndAssign()

        -- ----------------------------------------------------------------
        -- Determine assigned lifeform; give late-joiners a random pick.
        -- ----------------------------------------------------------------
        local assignedLifeform = bot.teh_assignedLifeform

        if assignedLifeform == nil then
            local gamerules = GetGamerules()
            if gamerules and gamerules:GetGameStarted() and
                    gTEHAssignedGameStartTime == gamerules:GetGameStartTime() then
                assignedLifeform = TEH_GetMostNeededLifeform(bot)
                bot.teh_assignedLifeform  = assignedLifeform
                bot.teh_nextReassignTime  = Shared.GetTime() + math.random() * kTEHInitialSpread
            end
        end

        if assignedLifeform == nil then
            return kNilAction  -- pre-assignment window: stay Skulk
        end

        -- ----------------------------------------------------------------
        -- Respawn detection.
        -- When a bot was evolved (non-Skulk) and is now a Skulk again it just
        -- died and respawned.  Its teh_nextReassignTime was last written while
        -- it was still a Skulk before evolving, so it is already in the past.
        -- Without a correction, every bot from the same fight reassesses on the
        -- same tick: bot-1 sees Gorge=0 → picks Gorge; bot-2 now sees Gorge=1
        -- (still the minimum) → picks Gorge again, and so on.  Re-scattering
        -- the timer over kTEHRespawnStagger seconds breaks the pile-up.
        -- ----------------------------------------------------------------
        local isNowSkulk = player:isa("Skulk")
        if isNowSkulk and bot.teh_wasEvolved then
            -- Transition: evolved → Skulk (respawn).
            bot.teh_wasEvolved = false
            if not bot.teh_nextReassignTime or
                    Shared.GetTime() >= bot.teh_nextReassignTime then
                bot.teh_nextReassignTime = Shared.GetTime()
                    + math.random() * kTEHRespawnStagger
            end
        elseif not isNowSkulk then
            bot.teh_wasEvolved = true
        end

        -- ----------------------------------------------------------------
        -- Per-bot dynamic reassessment (only while still a Skulk).
        -- Because Lua is single-threaded, updating bot.teh_assignedLifeform
        -- here is immediately visible to the next bot's GetMostNeeded call
        -- in the same tick, preventing simultaneous mass-switches.
        -- ----------------------------------------------------------------
        if isNowSkulk and bot.teh_nextReassignTime and
                Shared.GetTime() >= bot.teh_nextReassignTime then

            local needed = TEH_GetMostNeededLifeform(bot)
            if needed ~= bot.teh_assignedLifeform then
                bot.teh_assignedLifeform = needed
                assignedLifeform = needed
            end
            -- Schedule next reassessment with jitter to prevent lock-step clustering.
            bot.teh_nextReassignTime = Shared.GetTime() + kTEHReassessBase
                + (math.random() * 2 - 1) * kTEHReassessJitter
        end

        -- ----------------------------------------------------------------
        -- Standard evolution checks.
        -- ----------------------------------------------------------------
        if player.isHallucination then
            return kNilAction
        end

        -- Skulk is no longer in the assignment pool; guard against stale data.
        if assignedLifeform == kTechId.Skulk then
            bot.teh_assignedLifeform = TEH_GetMostNeededLifeform(bot)
            assignedLifeform = bot.teh_assignedLifeform
            if not assignedLifeform or assignedLifeform == kTechId.Skulk then
                return kNilAction
            end
        end

        local lifeformToClass = GetLifeformToClass()
        local assignedClass   = lifeformToClass[assignedLifeform]
        if assignedClass and player:isa(assignedClass) then
            return kNilAction  -- already the right lifeform
        end

        if not player:isa("Skulk") then
            return kNilAction
        end

        if not player:GetIsAllowedToBuy() then
            return kNilAction
        end

        local techNode = player:GetTechTree():GetTechNode(assignedLifeform)
        local isAvailable = techNode and techNode:GetAvailable(player, assignedLifeform, false)
        if not isAvailable then
            return kNilAction
        end

        local cost = GetCostForTech(assignedLifeform)
        if player:GetPersonalResources() < cost then
            return kNilAction
        end

        bot.lifeformEvolution = assignedLifeform

        local evolveName, evolveWeight = actionWeights:Get(actionType)

        -- ----------------------------------------------------------------
        -- All non-Skulk lifeforms navigate to a Hive first, then evolve
        -- only when no Marine has line of sight.
        -- ----------------------------------------------------------------
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

        if not nearestHive then
            bot.teh_navStart = nil
            return kNilAction  -- no built hive yet
        end

        local now = Shared.GetTime()

        -- Honour a retry cooldown set after a timed-out evolve attempt so the bot
        -- plays normally for a while instead of immediately re-pinning to the hive.
        if bot.teh_evolveRetryAfter and now < bot.teh_evolveRetryAfter then
            bot.teh_navStart = nil
            return kNilAction
        end

        local hivePos = nearestHive:GetEngagementPoint()

        if nearestDist > kTEHHiveEvolveDist then
            -- Navigating to the hive. Bound the attempt: if the bot cannot reach the
            -- hive within kTEHNavTimeout (bad path, camped, stuck on geometry) it
            -- gives up and plays normally for a while rather than freezing en route.
            bot.teh_navStart = bot.teh_navStart or now
            if now - bot.teh_navStart > kTEHNavTimeout then
                bot.teh_navStart         = nil
                bot.teh_evolveRetryAfter = now + kTEHEvolveRetryDelay
                return kNilAction
            end
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
        end

        -- Reached the hive: clear the navigation timer.
        bot.teh_navStart = nil

        -- Not safe to evolve (a Marine has LOS within range): do NOT freeze at the
        -- hive. Returning kNilAction lets the bot keep playing — it will engage the
        -- threatening Marine and defend the hive, then evolve once the area is clear
        -- (this action re-runs every frame, so it re-checks safety continuously).
        if not IsSafeToEvolve(player) then
            return kNilAction
        end

        -- ----------------------------------------------------------------
        -- Evolve AT the hive, on a spot with room for the target body.
        -- If the bot is standing somewhere too cramped for the lifeform (an
        -- Onos in a tight corner, etc.) it finds a valid spot close to the
        -- hive and walks there first, so it never evolves out in the open or
        -- in a space too small to fit. Bounded by the same nav timeout so the
        -- freeze fix still holds; if no reachable spot is found in time it
        -- evolves in place and lets the Embryo relocate during gestation.
        -- ----------------------------------------------------------------
        local extents = LookupTechData(assignedLifeform, kTechDataMaxExtents, Vector(0.4, 0.4, 0.4))
        local origin  = player:GetOrigin()

        local function HasRoomAt(pos)
            return GetHasRoomForCapsule(
                extents + Vector(0.1, 0.1, 0.1),
                pos + Vector(0, extents.y + 0.2, 0),
                CollisionRep.Default,
                PhysicsMask.AllButPCsAndRagdolls,
                nil,
                EntityFilterOne(player))
        end

        if HasRoomAt(origin) then
            -- Current spot is fine; drop any cached target.
            bot.teh_evolveSpot = nil
        else
            -- Reuse a previously chosen spot while it stays valid and near the
            -- hive; otherwise pick a new one. Caching keeps the move target
            -- stable across frames (GetRandomSpawnForCapsule returns a random
            -- point each call, which would otherwise make the bot jitter).
            local hiveOrigin = nearestHive:GetModelOrigin()
            local spot = bot.teh_evolveSpot
            if spot and (not HasRoomAt(spot) or
                    spot:GetDistance(hiveOrigin) > kTEHEvolveSpotRadius + 1) then
                spot = nil
            end
            if not spot then
                spot = GetRandomSpawnForCapsule(
                    extents.y, math.max(extents.x, extents.z),
                    hiveOrigin, 0.5, kTEHEvolveSpotRadius,
                    EntityFilterOne(player))
                bot.teh_evolveSpot = spot
            end

            if spot and origin:GetDistance(spot) > 1.2 then
                -- Walk to the valid spot near the hive (same nav-timeout safeguard).
                bot.teh_navStart = bot.teh_navStart or now
                if now - bot.teh_navStart > kTEHNavTimeout then
                    bot.teh_navStart         = nil
                    bot.teh_evolveSpot       = nil
                    bot.teh_evolveRetryAfter = now + kTEHEvolveRetryDelay
                    return kNilAction
                end
                return {
                    name       = evolveName or "teh_evolve_findspot",
                    weight     = (evolveWeight or 10),
                    spot       = spot,
                    fastUpdate = true,
                    perform    = function(move, b, br, p, action)
                        b:GetMotion():SetDesiredMoveTarget(action.spot)
                    end,
                }
            end
            -- Either no valid spot was found (evolve in place; the Embryo relocates
            -- during gestation) or we have arrived at the chosen spot — evolve now.
        end

        bot.teh_navStart   = nil
        bot.teh_evolveSpot = nil

        return {
            name            = evolveName or "teh_evolve",
            weight          = (evolveWeight or 10),
            desiredUpgrades = { assignedLifeform },
            perform         = function(move, b, br, p, action)
                -- Capture origin and request the mist BEFORE ProcessBuyAction,
                -- while p is still the live player entity (it becomes an Embryo
                -- after evolving, so team/origin lookups must happen first).
                local evolveOrigin = p:GetOrigin()
                if not b.teh_requestedMist then
                    b.teh_requestedMist = true
                    CreateVoiceMessage(p, kVoiceId.AlienRequestMist)
                    TEH_TrySpawnMist(p, evolveOrigin)
                end
                p:ProcessBuyAction(action.desiredUpgrades)
                return kPlayerObjectiveComplete
            end,
        }
    end
end
