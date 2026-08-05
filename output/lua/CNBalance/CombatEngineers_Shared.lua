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
-- DIVISOR 3 (was 5, and 10 before that). Each change is solved from the same equation rather than
-- guessed. Worked example at 3.5 RTs (param 3.25 -> 0.125 * 3.25 * 10 = 4.06 p-res per marine per
-- minute), for the COMPLETE build-out - every structure below plus all six Arms Labs, 475 base -
-- where each marine's share is base/divisor and every marine starts holding kMarineInitialIndivRes
-- (15):
--
--     divisor 10 ->  47.5 = 15 + 4.06t  ->  t =  8.0 min   (far too fast)
--     divisor  5 ->  95.0 = 15 + 4.06t  ->  t = 19.7 min
--     divisor  3 -> 158.3 = 15 + 4.06t  ->  t = 35.3 min   <- current
--
-- (Earlier revisions of this comment quoted a 295 base and correspondingly shorter times; 295 was
-- simply the wrong total - the structures below sum to 285 and the Arms Lab ladder adds a further
-- 320, of which any one round buys at most 190 more. 475 is the real all-in figure.)
--
-- That full build-out is a whole-round project, not an opening: a practical early base at 10 players
-- (Command Station 133 + Infantry Portal 50 + Extractor 33 + Armory 33 = 249 team-wide, 24.9 each)
-- still lands about 2.5 minutes in.
--
-- The share PER MARINE is base/divisor at ANY team size, which is the whole point of dividing by N:
-- it stops a 25-man team teching up six times faster than a 4-man one purely by having six times the
-- aggregate income.
--
-- CAP 8.5, raised in step with the divisor. The cap must not bind anywhere inside the 1..25 player
-- range the server actually runs, or the largest teams - the exact case this model exists to guard
-- against - would pay LESS per head than mid-sized ones. N/3 reaches 8.33 at N=25, so 8.5 clears it
-- with a little room and never fires in practice. (The old 2.2 cap bound from 22 players up, which
-- had precisely that inverted effect; 5.0 was correct for divisor 5 but would bind from N=15 here.)
--
-- Starting resources matter as much as income and are easy to overlook: a 25-man team begins the
-- round with 375 p-res already pooled before any income arrives at all.
kCombatEngineersCostDivisor = 3
kCombatEngineersCostScalarMin = 0.6
kCombatEngineersCostScalarMax = 8.5
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

-- Arms Labs are priced by LADDER POSITION, not by a flat number: the Nth lab carries the research it
-- unlocks for free, so it costs the base lab price plus the t-res that research would have cost.
-- Index = the lab's position (1..6).
kCombatEngineersArmsLabBaseCost =
{
    kArmsLabCost + kArmor1ResearchCost,    -- 1 -> Armor 1   : 20 + 25 = 45
    kArmsLabCost + kWeapons1ResearchCost,  -- 2 -> Weapons 1 : 20 + 20 = 40
    kArmsLabCost + kArmor2ResearchCost,    -- 3 -> Armor 2   : 20 + 35 = 55
    kArmsLabCost + kWeapons2ResearchCost,  -- 4 -> Weapons 2 : 20 + 35 = 55
    kArmsLabCost + kArmor3ResearchCost,    -- 5 -> Armor 3   : 20 + 40 = 60
    kArmsLabCost + kWeapons3ResearchCost,  -- 6 -> Weapons 3 : 20 + 45 = 65
}

kCombatEngineersMaxArmsLabs = #kCombatEngineersArmsLabBaseCost

-- Infantry Portals are capped for CE marines at the existing map-wide limit, shown as "N/12" in the
-- build menu. Uses the established global rather than a new number so the cap can never drift from
-- the limit the rest of the game already enforces.
kCombatEngineersMaxInfantryPortals = kMaxInfantryPortalsGlobal or 12

-- The ladder itself: how many built AND POWERED Arms Labs grant which upgrade. Position in this
-- list IS the required lab count, which is what makes the "lose the LATEST tech, not the tech the
-- destroyed lab happened to research" rule fall out for free.
kCombatEngineersArmsLabLadder =
{
    kTechId.Armor1,
    kTechId.Weapons1,
    kTechId.Armor2,
    kTechId.Weapons2,
    kTechId.Armor3,
    kTechId.Weapons3,
}

-- Arms Labs are half as tough in a CE round - there are up to six of them and they are the team's
-- entire upgrade path, so they have to be a realistic target for the aliens.
kCombatEngineersArmsLabHealthScalar = 0.5

-- ============================================================
-- Cost helpers
-- ============================================================
-- Marine players who receive p-res income: the same population PlayingTeam:CollectTeamResources
-- pays, i.e. every player on the team except the commander.
function GetCombatEngineersPlayerCount(teamNumber)

    local count = 0

    for _, player in ipairs(GetEntitiesForTeam("Player", teamNumber)) do
        if not player:isa("Commander") then
            count = count + 1
        end
    end

    return count
end

function GetCombatEngineersCostScalar(teamNumber)

    local players = GetCombatEngineersPlayerCount(teamNumber)
    local scalar  = players / kCombatEngineersCostDivisor

    return math.max(kCombatEngineersCostScalarMin, math.min(kCombatEngineersCostScalarMax, scalar))
end

-- Base (unscaled) cost of a structure. For Arms Labs the price depends on how many the team already
-- has, so `armsLabIndex` is the position the NEXT lab would occupy.
function GetCombatEngineersBaseCost(techId, armsLabIndex)

    if techId == kTechId.ArmsLab then
        local index = math.max(1, math.min(kCombatEngineersMaxArmsLabs, armsLabIndex or 1))
        return kCombatEngineersArmsLabBaseCost[index]
    end

    return kCombatEngineersStructureBaseCost[techId]
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
kCombatEngineersTeamCaps =
{
    [kTechId.ArmsLab]        = { field = "numArmsLabs",             max = function() return kCombatEngineersMaxArmsLabs end },
    [kTechId.InfantryPortal] = { field = "numInfantryPortalsTotal", max = function() return kCombatEngineersMaxInfantryPortals end },
}

-- Current count and cap for a capped structure, or nil when it has no cap.
function GetCombatEngineersStructureCount(techId, teamNumber)

    local cap = kCombatEngineersTeamCaps[techId]
    if not cap then return nil, nil end

    local teamInfo = GetTeamInfoEntity(teamNumber)
    local count = (teamInfo and teamInfo[cap.field]) or 0

    return count, cap.max()
end

function GetCombatEngineersCanBuild(techId, teamNumber)

    local count, max = GetCombatEngineersStructureCount(techId, teamNumber)
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
