-- CNBalance/CombatEngineers_Shared.lua
-- Combat Engineers: the Marine counterpart to the alien Origin Form.
--
-- The commander stops being a builder and becomes a support/ARC controller; field marines place
-- and construct the base themselves using PERSONAL resources, and the Arms Lab ladder hands out
-- armour/weapon upgrades for free based purely on how many built, powered Arms Labs exist.
--
-- Loaded post lua/TechData.lua so kTechId and the tech data table already exist. Everything here is
-- shared (client + server) so the build menu, the ghost, and the authoritative server checks all
-- read one set of numbers and can never disagree.

-- Mutually exclusive with Military Protocol. Both tech ids stay in CommandStation:GetTechButtons()
-- for the whole round no matter which is chosen - they are made UNAVAILABLE rather than removed, so
-- the button list keeps a constant length and constant ids for any mod that whitelists buttons by
-- position or id.

-- ============================================================
-- Team resource income
-- ============================================================
-- CE cuts the marine team's t-res income from resource towers to a THIRD (was a half). p-res is
-- untouched by this: it now buys every structure, and the whole Arms Lab ladder (A1-W3, normally
-- 200 t-res) is free, so the team stream shrinks to match its much smaller remaining job (upgrades,
-- ARCs, Scan, Beacon).
--
-- NOTE this scalar deliberately does NOT affect the structure prices below. Structures are bought
-- with PERSONAL resources, and PlayingTeam:UpdateResTick pays p-res per marine independently of the
-- team stream, so tightening t-res here and raising p-res costs below are two separate levers.
kCombatEngineersTeamResScalar = 1 / 3

-- Free to research. Long enough to notice and cancel, short enough not to stall the opening.
kCombatEngineersResearchTime = 10

-- Recycling a CE structure pays the COMMANDER back in team resources, at this fraction of the
-- PERSONAL resources that were actually sunk into building it (structure.ceResSpent) - so a
-- structure that cost 100 p-res to build returns 20 t-res.
--
-- Deliberately NOT the vanilla formula, which pays back a fraction of the structure's TEAM-resource
-- tech cost scaled by current health. In a CE round nobody ever paid that team cost - the structure
-- was funded entirely out of marines' personal resources - so the vanilla number is unrelated to
-- what was actually spent, and on a part-built structure it would refund for resources that were
-- never contributed.
kCombatEngineersRecycleRefundFraction = 0.20

-- "Take Credits": the build menu entry that converts TEAM resources into PERSONAL resources for the
-- marine who clicks it. A flat 1:1 exchange of a fixed size - 20 team resources leave the pool and
-- 20 personal resources go to that marine - so the team can deliberately push its (largely idle in
-- this mode) team income back into the personal economy that actually pays for structures.
kCombatEngineersCreditsTeamCost   = 20
kCombatEngineersCreditsPlayerGain = 20

-- How much this marine can ACTUALLY exchange right now, which is not always the full chunk.
--
-- The exchange is 1:1, so it is capped by three things and takes the smallest:
--   * the standard chunk (20),
--   * the ROOM left under the personal resource cap - a marine on 95 of 100 takes 5, not 20, because
--     the other 15 would simply evaporate,
--   * what the team pool can actually cover.
--
-- Returns 0 when no exchange is possible at all (marine already at the cap, or an empty pool), which
-- is what the build-menu button greys out on - so a full marine sees a dead button rather than
-- burning team resources for nothing.
function GetCombatEngineersCreditsExchangeAmount(player)

    if not player then
        return 0
    end

    local chunk = kCombatEngineersCreditsTeamCost or 20

    local maxPres = kMaxPersonalResources or 100
    local room    = maxPres - (player:GetResources() or 0)

    local teamInfo = GetTeamInfoEntity(player:GetTeamNumber())
    local teamRes  = (teamInfo and teamInfo:GetTeamResources()) or 0

    local amount = math.min(chunk, room, teamRes)

    -- Whole resources only; a fractional trickle would be confusing in the announcement.
    amount = math.floor(amount)

    return math.max(0, amount)
end

-- ============================================================
-- Structure cost model
-- ============================================================
-- Derived from the income code in PlayingTeam:UpdateResTick rather than guessed. Per 6s tick:
--     param = min(RTs,3)*1 + max(RTs-3,0)*0.5
--     t-res to team                       = param * kTeamResourceEachTower  (1)
--     p-res to EVERY non-commander player = param * kPlayerResEachTower     (0.125)
-- p-res income PER MARINE is independent of team size, so team-wide p-res scales linearly with the
-- player count while t-res does not: team p-res income / t-res income = N / 8.
--
-- Cost = base * (N / divisor), so the share PER MARINE is a constant base/divisor at any team size.
-- That constant-per-head property is the whole point: it is what stops a 25-man team teching up
-- roughly six times faster than a 4-man one simply by having six times the income.
--
-- The scalar is BASE + PER-PLAYER, not a plain division by team size.
--
--     scalar = kCombatEngineersCostScalarBase + players * kCombatEngineersCostPerPlayer
--
-- The old model was scalar = players / divisor, which is linear THROUGH THE ORIGIN. That kept the
-- share per marine perfectly constant at any team size, but it also meant a small team paid almost
-- nothing per structure - at 4 players several structures sat on the hard floor and were
-- indistinguishable - while a 25-man team paid over six times as much for the same building.
--
-- Splitting it into a constant term plus a slope fixes both ends:
--   * The BASE term is the minimum. Even a tiny team pays a real price rather than a token one.
--   * The PER-PLAYER term still makes a big team pay meaningfully more, just less violently.
--
-- Tuned so 5 players -> 2.0 and 25 players -> 5.0, i.e. the largest team pays 2.5x the price a small
-- one does rather than 5x:
--     1.25 + 5  * 0.15 = 2.00
--     1.25 + 25 * 0.15 = 5.00
--
-- TRADE-OFF, stated plainly: because this is no longer proportional to the player count, the cost
-- PER MARINE now falls as the team grows - a 25-man team pays about half as much per head as a
-- 5-man one, so it will tech roughly twice as fast. That is the direct consequence of asking for a
-- gentler slope, and the two constants below are the dial: raising kCombatEngineersCostPerPlayer
-- towards 0.4 restores near-proportional scaling, lowering it flattens further.
kCombatEngineersCostScalarBase = 1.25
kCombatEngineersCostPerPlayer  = 0.15

-- Clamps. The minimum is now carried by the base term above, so these only guard the extremes: the
-- floor stops a scalar of zero if the player count ever reads as nothing, and the cap sits above
-- what 25 players produce (5.0) so it never binds in practice.
kCombatEngineersCostScalarMin = 1.0
kCombatEngineersCostScalarMax = 6.0
kCombatEngineersCostFloor = 5

-- Placing a CE blueprint costs NOTHING. Every personal resource a structure needs is charged while
-- it is physically being built (see ChargeForConstruction in CombatEngineers_Build.lua) - placement
-- only requires the structure to be a valid, currently-buildable one. (Formerly a small fraction was
-- required up front as an anti-spam gate; removed at the user's explicit direction that structures
-- must cost nothing to place.)

-- BASE cost per structure, in the same units as the commander's t-res price, before the team-size
-- scalar. Command Station is deliberately 2x its commander price (40, not kCommandStationCost 20):
-- it is the highest-value structure in the game - respawn anchor, commander seat, and in this mod
-- the host of all four supply upgrade branches - and in a CE round t-res is nearly idle, so parity
-- pricing would make it spammable relative to its worth.
kCombatEngineersStructureBaseCost =
{
    [kTechId.Extractor]        = kExtractorCost,          -- 10
    [kTechId.Armory]           = 10,
    [kTechId.Observatory]      = kObservatoryCost,        -- 10
    [kTechId.RoboticsFactory]  = kRoboticsFactoryCost,    -- 10
    [kTechId.InfantryPortal]   = kInfantryPortalCost,     -- 15
    [kTechId.PhaseGate]        = kPhaseGateCost,          -- 15
    [kTechId.SentryBattery]    = kSentryBatteryCost,      -- 20
    [kTechId.PrototypeLab]     = kPrototypeLabCost,       -- 25
    [kTechId.CommandStation]   = kCommandStationCost * 2, -- 40
}

--[[
    ARMS LAB PRICING: a rising PERSONAL-resource ladder, per track.

    The lab's research is now entirely FREE - it starts on its own the moment the lab finishes
    building and costs the team nothing from the resource pool. The personal price here is what pays
    for it. That is why these numbers are well above a plain kArmsLabCost (20): a CE Arms Lab is no
    longer a building that lets you buy an upgrade, it IS the upgrade, bought outright with p-res.

    The ladder is PER TRACK, so a team's first armour lab and its first weapons lab both cost the
    level-1 price. The two tracks are independent purchases and neither should be made dearer by
    progress on the other.

    These three numbers are the tuning knob for the whole exchange - raise them if free tech proves
    too cheap, lower them if the tracks stall. They are BASE costs: GetCombatEngineersCostScalar
    scales them by team size on top, the same as every other CE structure.
]]
kCombatEngineersArmsLabBaseCost =
{
    15,   -- 1st lab on the track -> Armor1 / Weapons1
    20,   -- 2nd lab on the track -> Armor2 / Weapons2
    25,   -- 3rd lab on the track -> Armor3 / Weapons3
}

-- Three labs per track, and nothing beyond that: a fourth would have no research left to do.
kCombatEngineersMaxArmsLabsPerTrack = #kCombatEngineersArmsLabBaseCost

-- The whole-team total, kept as its own constant rather than derived from the cost table. It is what
-- MarineTeamInfo clamps its counters to and what the old single global cap meant; it now simply
-- happens to be the two per-track caps added together.
kCombatEngineersMaxArmsLabs = kCombatEngineersMaxArmsLabsPerTrack * 2

-- Infantry Portals are capped for CE marines at the existing map-wide limit, shown as "N/12" in the
-- build menu. Uses the established global rather than a new number so the cap can never drift from
-- the limit the rest of the game already enforces.
kCombatEngineersMaxInfantryPortals = kMaxInfantryPortalsGlobal or 12

-- ============================================================
-- Arms Lab upgrade tracks
-- ============================================================
-- TWO INDEPENDENT TRACKS, not one fixed ladder. Each Arms Lab researches ONE tech, chosen by the
-- marine who places it, so the team's armour and weapon levels advance separately and in whatever
-- order the team wants. Index in each list IS that tech's level (1..3), and level N's prerequisite is
-- simply level N-1 of the same track - which is also the real tech-tree prerequisite (Armor2 requires
-- Armor1), so "next in track" and "prerequisite satisfied" are the same test.
--
-- This replaced a single six-step ladder (A1,W1,A2,W2,A3,W3) whose position doubled as the required
-- lab count. That made the order fixed and the choice automatic; it also made the loss rule fall out
-- for free, which is why the explicit rule in GetCombatEngineersTechToLose now exists.
--[[
    ARMS LAB TRACKS.

    Every CE Arms Lab is placed as either a WEAPONS lab or an ARMOUR lab (two separate entries in the
    Combat Builder menu) and researches that track automatically. The track is fixed at placement and
    networked, because the client needs it to label the lab and to grey its upgrade window.

    Networked as a small integer rather than a string: strings cost far more bandwidth per entity and
    this is replicated on up to six labs.
]]
kCombatEngineersTrackNone   = 0
kCombatEngineersTrackArmor  = 1
kCombatEngineersTrackWeapon = 2

-- Track index -> the "armor"/"weapon" names the rest of the CE code already speaks.
function GetCombatEngineersTrackName(trackIndex)
    if trackIndex == kCombatEngineersTrackArmor  then return "armor"  end
    if trackIndex == kCombatEngineersTrackWeapon then return "weapon" end
    return nil
end

function GetCombatEngineersTrackIndex(trackName)
    if trackName == "armor"  then return kCombatEngineersTrackArmor  end
    if trackName == "weapon" then return kCombatEngineersTrackWeapon end
    return kCombatEngineersTrackNone
end

-- The track this Arms Lab was placed as, or nil if it carries none (a lab from before the two-button
-- menu, or a non-CE lab).
function GetCombatEngineersLabTrack(structure)
    if not structure then return nil end
    return GetCombatEngineersTrackName(structure.ceTrackIndex or kCombatEngineersTrackNone)
end

kCombatEngineersArmorTrack   = { kTechId.Armor1,   kTechId.Armor2,   kTechId.Armor3 }
kCombatEngineersWeaponTrack  = { kTechId.Weapons1, kTechId.Weapons2, kTechId.Weapons3 }

kCombatEngineersMaxTrackLevel = 3

-- Kept as the flat list of every tech the Arms Lab system owns. Used for "is this a free/lab-granted
-- tech" tests (so these never appear as buyable upgrades elsewhere) and to index the ce_a1..ce_w3
-- sounds. NOT an ordering any more - nothing may infer sequence from it.
kCombatEngineersArmsLabLadder =
{
    kTechId.Armor1,
    kTechId.Weapons1,
    kTechId.Armor2,
    kTechId.Weapons2,
    kTechId.Armor3,
    kTechId.Weapons3,
}

-- Which track a tech belongs to, and at what level. Returns nil for anything else.
function GetCombatEngineersTrackForTech(techId)

    for level, id in ipairs(kCombatEngineersArmorTrack) do
        if id == techId then return "armor", level end
    end

    for level, id in ipairs(kCombatEngineersWeaponTrack) do
        if id == techId then return "weapon", level end
    end

    return nil, nil
end

-- The sound that announces a given ladder tech starting research.
function GetCombatEngineersTechSound(techId)

    if not kCombatEngineersArmsLabLadderSounds then return nil end

    for i, id in ipairs(kCombatEngineersArmsLabLadder) do
        if id == techId then
            return kCombatEngineersArmsLabLadderSounds[i]
        end
    end

    return nil
end

-- WHICH TECH IS LOST when the team has more granted levels than built+powered Arms Labs.
--
-- Highest level first; on a tie, weapons before armour. Worked through the cases:
--     A1 + W3 -> W3 (3 beats 1)
--     A2 + W2 -> W2 (tie at 2, weapons wins)
--     A3 + W2 -> A3 (3 beats 2)
--
-- Deliberately independent of WHICH lab died: labs are interchangeable once their research is done,
-- so only the two counts matter. Returns the track to decrement, or nil when there is nothing left.
function GetCombatEngineersTechToLose(armorLevel, weaponLevel)

    if (weaponLevel or 0) <= 0 and (armorLevel or 0) <= 0 then
        return nil
    end

    if weaponLevel > 0 and weaponLevel >= armorLevel then
        return "weapon"
    end

    return "armor"
end

-- ============================================================
-- Which Arms Lab tech may be chosen right now
-- ============================================================
-- Shared so the chooser's greying and the server's placement re-check are literally the same rule and
-- cannot disagree. Everything read here is available on BOTH sides: GetHasTech walks the networked
-- tech tree, and team resources come from the networked TeamInfo entity.

-- The team's current level in a track, derived from what is actually RESEARCHED rather than from a
-- stored counter, so it is correct on the client and cannot drift from the tech tree.
function GetCombatEngineersTrackLevel(player, track)

    local list = (track == "armor") and kCombatEngineersArmorTrack or kCombatEngineersWeaponTrack
    local level = 0

    for i, techId in ipairs(list) do
        if GetHasTech(player, techId) then
            level = i
        end
    end

    return level
end

-- The one tech a track could advance to next, or nil when that track is finished.
function GetCombatEngineersNextTechInTrack(player, track)

    local list = (track == "armor") and kCombatEngineersArmorTrack or kCombatEngineersWeaponTrack
    local level = GetCombatEngineersTrackLevel(player, track)

    if level >= kCombatEngineersMaxTrackLevel then
        return nil
    end

    return list[level + 1]
end

-- Is `techId` the next legal step in its own track for this team?
--
-- This is ONLY the track/prerequisite half of the answer. Lab capacity, whether another lab is
-- already researching it, and affordability are layered on by GetCEStructureUpgradeState, which is
-- what the Arms Lab's upgrade window actually calls.
function GetCombatEngineersArmsLabTechState(player, techId)

    local cost = GetCostForTech(techId) or 0

    if not player then
        return false, false, cost
    end

    local track = GetCombatEngineersTrackForTech(techId)
    if not track then
        return false, false, cost
    end

    -- Next-in-track IS the prerequisite test: Armor2 is only offered once Armor1 is researched.
    local available = GetCombatEngineersNextTechInTrack(player, track) == techId

    local teamInfo = GetTeamInfoEntity(player:GetTeamNumber())
    local teamRes  = (teamInfo and teamInfo:GetTeamResources()) or 0

    return available, teamRes >= cost, cost
end

-- Every tech the chooser displays, in page order: page 1 armour, page 2 weapons. All six are always
-- shown (greyed when not choosable) so the costs and the shape of both tracks stay visible.
function GetCombatEngineersArmsLabChoices()

    local choices = {}

    for _, techId in ipairs(kCombatEngineersArmorTrack) do
        table.insert(choices, techId)
    end

    for _, techId in ipairs(kCombatEngineersWeaponTrack) do
        table.insert(choices, techId)
    end

    return choices
end

-- Arms Labs are half as tough in a CE round - there are up to six of them and they are the team's
-- entire upgrade path, so they have to be a realistic target for the aliens.
kCombatEngineersArmsLabHealthScalar = 0.5

-- ============================================================
-- Cost helpers
-- ============================================================
-- Marine players who receive p-res income: everyone on the team except the commander, matching the
-- population PlayingTeam:CollectTeamResources pays.
--
-- READ FROM NETWORKED TEAM STATE, never by counting entities.
--
-- This used to walk GetEntitiesForTeam("Player", ...). That is correct on the server, which holds
-- every entity, but on the CLIENT that list only contains players currently RELEVANT to you -
-- teammates elsewhere on the map are simply not in it. So the displayed price drifted as players
-- moved in and out of relevance and as the menu was rebuilt, which is why a Command Station could
-- read one price, then a different one after flipping pages, with the roster completely unchanged.
-- It also meant the client and the server disagreed about the price outright.
--
-- TeamInfo.playerCount is a networked variable set from team:GetNumPlayers(), so it is identical on
-- both sides and unaffected by relevance. GetTeamHasCommander is likewise side-agnostic (the client
-- resolves it through the scoreboard, which lists every player). The price therefore only ever moves
-- when the roster actually changes.
function GetCombatEngineersPlayerCount(teamNumber)

    local teamInfo = GetTeamInfoEntity(teamNumber)
    local count = (teamInfo and teamInfo.GetPlayerCount and teamInfo:GetPlayerCount()) or 0

    if GetTeamHasCommander and GetTeamHasCommander(teamNumber) then
        count = count - 1
    end

    return math.max(0, count)
end

function GetCombatEngineersCostScalar(teamNumber)

    local players = GetCombatEngineersPlayerCount(teamNumber)
    local scalar  = kCombatEngineersCostScalarBase + players * kCombatEngineersCostPerPlayer

    return math.max(kCombatEngineersCostScalarMin, math.min(kCombatEngineersCostScalarMax, scalar))
end

-- Across-the-board discount on every NON-Arms-Lab structure, applied here rather than by editing
-- kCombatEngineersStructureBaseCost above so those entries stay readable as "the commander's price"
-- and can still be compared against the vanilla constants they are derived from.
--
-- 0.35: the earlier 30% cut (0.7) halved again. Applied on the BASE side deliberately rather than by
-- touching the team-size scalar, so that the two concerns stay separable: this constant sets WHAT A
-- STRUCTURE IS WORTH, and the scalar above sets how that scales with team size.
kCombatEngineersStructureCostScalar = 0.35

-- Base (unscaled) cost of a structure. For Arms Labs the price depends on how many the team already
-- has, so `armsLabIndex` is the position the NEXT lab would occupy.
function GetCombatEngineersBaseCost(techId, armsLabIndex)

    if techId == kTechId.ArmsLab then
        local index = math.max(1, math.min(kCombatEngineersMaxArmsLabsPerTrack, armsLabIndex or 1))
        return kCombatEngineersArmsLabBaseCost[index]
    end

    local base = kCombatEngineersStructureBaseCost[techId]
    if not base then
        -- nil is meaningful to every caller: it means "not a CE-priced structure at all", so it must
        -- be passed through untouched rather than turned into a number by the multiply below.
        return nil
    end

    return base * kCombatEngineersStructureCostScalar
end

-- Whether a structure's price is the DYNAMIC, team-size-scaled Combat Engineers cost (every CE
-- structure, ArmsLab included) as opposed to the flat legacy kTechDataPersonalCostKey values Sentry
-- and Supply Depot keep. This is the single source of truth for "is this structure CE-priced" -
-- every call site that used to test kCombatEngineersStructureBaseCost[techId] directly must go
-- through this instead, because that table alone OMITS ArmsLab (it is priced from the separate
-- kCombatEngineersArmsLabBaseCost ladder). Testing the narrower table directly was the exact bug
-- that let an Arms Lab charge its full cost at PLACEMENT (mis-classified as a non-CE, pay-up-front
-- structure) and then build for free (its ceTotalCost was never stamped).
function GetCombatEngineersStructureHasDynamicCost(techId)
    return GetCombatEngineersBaseCost(techId, 1) ~= nil
end

-- Final personal-resource cost. Callers that already know the scalar (a placed blueprint stores the
-- one it was stamped with) pass it in; everything else derives it from the live player count.
function GetCombatEngineersStructureCost(techId, teamNumber, armsLabIndex, scalarOverride)

    local base = GetCombatEngineersBaseCost(techId, armsLabIndex)
    if not base then
        -- Sentry and Supply Depot keep their own long-standing personal costs and are not scaled:
        -- already tuned, and too small to be worth it.
        return LookupTechData(techId, kTechDataPersonalCostKey, 0)
    end

    local scalar = scalarOverride or GetCombatEngineersCostScalar(teamNumber)

    return math.max(kCombatEngineersCostFloor, math.floor(base * scalar + 0.5))
end

-- ============================================================
-- Side-agnostic state lookups
-- ============================================================
-- The build menu, the ghost and the server's drop path all need the same answers, but Team methods
-- like IsCombatEngineers() and GetArmsLabCount() exist ONLY on the server. These read state that is
-- networked to both sides instead, so the client can never show something the server would refuse.
--
-- Requires kTechId.CombatEngineers in TeamInfo.kRelevantTechIdsMarine for GetHasTech to work.
--
-- WARMUP GUARD: during the pre-game TechNode:GetHasTech() AND TechNode:GetResearched() both return
-- TRUE for every tech in the game (TechNode.lua:275 and :105 short-circuit on GetWarmupActive).
-- Without this guard the pre-game would report BOTH Combat Engineers and Military Protocol as
-- chosen - marines would get the full CE build menu, the commander would be locked down, and team
-- resource income would be halved, all before the round had even started. Neither mode is meant to
-- exist in warmup, so every CE state check funnels through here.
function GetCombatEngineersWarmup()
    return GetWarmupActive ~= nil and GetWarmupActive() == true
end

function GetCombatEngineersActive(player)

    if GetCombatEngineersWarmup() then
        return false
    end

    return player ~= nil and GetHasTech(player, kTechId.CombatEngineers) == true
end

-- Structures with a TEAM-level cap, and where the current count is networked from.
-- Both counts include UNBUILT blueprints, so queuing them up cannot exceed the cap.
--
-- The Arms Lab entry resolves its counter FROM THE TRACK, because the cap is three per track rather
-- than six overall: the two build-menu buttons share kTechId.ArmsLab and differ only by track, so a
-- techId alone cannot say which of the two counters to read. Callers that know the track (the build
-- menu button, the placement check) pass it; a caller that does not falls back to the combined total
-- against the combined cap, which is the correct answer to the only question it can ask.
kCombatEngineersTeamCaps =
{
    [kTechId.ArmsLab] =
    {
        field = function(track)
            if track == "armor"  then return "numArmsLabsArmor",  kCombatEngineersMaxArmsLabsPerTrack end
            if track == "weapon" then return "numArmsLabsWeapon", kCombatEngineersMaxArmsLabsPerTrack end
            return nil, kCombatEngineersMaxArmsLabs
        end
    },
    [kTechId.InfantryPortal] = { field = "numInfantryPortalsTotal", max = function() return kCombatEngineersMaxInfantryPortals end },
}

-- Current count and cap for a capped structure, or nil when it has no cap.
function GetCombatEngineersStructureCount(techId, teamNumber, track)

    local cap = kCombatEngineersTeamCaps[techId]
    if not cap then return nil, nil end

    local teamInfo = GetTeamInfoEntity(teamNumber)

    if type(cap.field) == "function" then

        local field, max = cap.field(track)

        -- No track: report both tracks together against the combined cap.
        if not field then
            local total = ((teamInfo and teamInfo.numArmsLabsArmor)  or 0)
                        + ((teamInfo and teamInfo.numArmsLabsWeapon) or 0)
            return total, max
        end

        return (teamInfo and teamInfo[field]) or 0, max

    end

    return (teamInfo and teamInfo[cap.field]) or 0, cap.max()
end

function GetCombatEngineersCanBuild(techId, teamNumber, track)

    local count, max = GetCombatEngineersStructureCount(techId, teamNumber, track)
    if not count then return true end

    return count < max
end

-- ============================================================
-- Commander allow-list
-- ============================================================
-- In a CE round the commander may ONLY select units, give orders, Scan, Distress Beacon and operate
-- ARCs. Everything else - all structure placement, all equipment and Exo drops, medpacks,
-- ammopacks, cat packs, Nano Shield, Power Surge, and ALL research - is refused.
--
-- Menu ids stay allowed so the commander can still navigate the button grid; every leaf inside the
-- menus greys out on its own.
kCombatEngineersCommanderAllowed =
{
    [kTechId.None]            = true,
    [kTechId.RootMenu]        = true,
    [kTechId.BuildMenu]       = true,
    [kTechId.AdvancedMenu]    = true,
    [kTechId.AssistMenu]      = true,
    [kTechId.WeaponsMenu]     = true,
    [kTechId.ProtosMenu]      = true,

    [kTechId.Move]            = true,
    [kTechId.Attack]          = true,
    [kTechId.Stop]            = true,
    [kTechId.Defend]          = true,
    [kTechId.Construct]       = true,
    [kTechId.Weld]            = true,
    [kTechId.AutoWeld]        = true,
    [kTechId.FollowAndWeld]   = true,
    [kTechId.SetRally]        = true,
    [kTechId.SetTarget]       = true,

    [kTechId.Scan]            = true,
    [kTechId.SelectObservatory] = true,
    [kTechId.DistressBeacon]  = true,

    -- The commander's Sentry is the ONE structure they may still place in a CE round. It is bought
    -- and priced entirely normally - standard TEAM resources via the usual ProcessSuccessAction /
    -- GetCostForTech path, NOT the personal-resource CE cost model, because kTechId.Sentry has no
    -- entry in kCombatEngineersStructureBaseCost - and it still requires a Sentry Battery in range
    -- exactly as it always has, since none of that placement logic is touched by this mode.
    --
    -- Distinct from kTechId.MarineSentry, which is the Combat Builder's own personal-resource sentry
    -- placed by field marines; the two coexist without interfering.
    [kTechId.Sentry]          = true,

    [kTechId.ARCDeploy]       = true,
    [kTechId.ARCUndeploy]     = true,
    [kTechId.RoboticsFactoryARCUpgradesMenu] = true,

    -- Flipping a phase gate's direction costs nothing and places nothing; it is pure traffic
    -- management, which is exactly the role the CE commander is left with.
    [kTechId.ReversePhaseGate] = true,

    -- Cancel is DELIBERATELY not on this list: ResearchMixin:PerformAction routes kTechId.Cancel on
    -- a researching structure straight to AbortResearch(), which is exactly "cancel a tech that has
    -- already started" - explicitly disallowed once Combat Engineers is active, even for research
    -- the commander personally started before CE completed.
    [kTechId.Recycle]         = true,
}

-- The structures a Combat Engineer can place, and the order they appear in the build menu, live in
-- lua/Combat/CEStructureAbilities.lua (kCEStructures). They are defined there rather than here so
-- that file has no cross-hook load-order dependency on this one. Power Node is absent on purpose:
-- it is not commander-placeable, so it is not CE-buyable either.
