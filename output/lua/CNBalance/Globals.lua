kSuicideDelay = 10

kNS2PlusPlayTestItemId = 9002

debug.appendtoenum(kPlayerStatus, "Devoured")
debug.appendtoenum(kPlayerStatus, "Axe")
debug.appendtoenum(kPlayerStatus, "Knife")
debug.appendtoenum(kPlayerStatus, "Welder")

debug.appendtoenum(kPlayerStatus, "Pistol")
debug.appendtoenum(kPlayerStatus, "Revolver")
debug.appendtoenum(kPlayerStatus, "SubMachineGun")
debug.appendtoenum(kPlayerStatus, "LightMachineGun")

debug.appendtoenum(kPlayerStatus, "Cannon")

debug.appendtoenum(kPlayerStatus, "Prowler")
debug.appendtoenum(kPlayerStatus, "ProwlerEgg")

debug.appendtoenum(kPlayerStatus, "Vokex")
debug.appendtoenum(kPlayerStatus, "VokexEgg")

debug.appendtoenum(kDeathMessageIcon, "Devour")
debug.appendtoenum(kDeathMessageIcon, "Volley")
debug.appendtoenum(kDeathMessageIcon, "Rappel")
debug.appendtoenum(kDeathMessageIcon, "AcidSpray")
debug.appendtoenum(kDeathMessageIcon, "Revolver")
debug.appendtoenum(kDeathMessageIcon, "SubMachineGun")
debug.appendtoenum(kDeathMessageIcon, "Cannon")
debug.appendtoenum(kDeathMessageIcon, "LightMachineGun")
debug.appendtoenum(kDeathMessageIcon, "Knife")
debug.appendtoenum(kDeathMessageIcon, "CombatBuilder")
debug.appendtoenum(kDeathMessageIcon, "SporeMine")
debug.appendtoenum(kDeathMessageIcon, "TeamBuildAbility")
debug.appendtoenum(kDeathMessageIcon, "AcidRocket")
debug.appendtoenum(kDeathMessageIcon, "ShadowStep")
-- Prototype Lab overhaul: exo special-weapon + upgrade death icons (referenced by
-- CNBalance/Weapons/ExoWeaponHolderModels.lua, Exo.lua, Combat/ExoSpecialWeapon.lua).
debug.appendtoenum(kDeathMessageIcon, "ExoFlamethrower")
debug.appendtoenum(kDeathMessageIcon, "ExoFlamethrowerBurn")
debug.appendtoenum(kDeathMessageIcon, "ExoWelder")
debug.appendtoenum(kDeathMessageIcon, "ExoGrenadeLauncher")
debug.appendtoenum(kDeathMessageIcon, "ExoSelfDestruct")
-- [POWER SMASH REMOVED] ExoPowerStomp icon is no longer produced (Power Smash is
-- inaccessible); safe to drop as it was the LAST entry in this enum group, so removing
-- it shifts no other kDeathMessageIcon index. Re-add here (at the end) to re-enable.
-- debug.appendtoenum(kDeathMessageIcon, "ExoPowerStomp")

debug.appendtoenum(kMinimapBlipType, "HeavyMarine")
debug.appendtoenum(kMinimapBlipType, "DevouredPlayer")
debug.appendtoenum(kMinimapBlipType, "BioformSuppressor")

debug.appendtoenum(kMinimapBlipType, "Prowler")
debug.appendtoenum(kMinimapBlipType, "Vokex")
debug.appendtoenum(kMinimapBlipType, "WeaponCache")
debug.appendtoenum(kMinimapBlipType, "MarineSentry")
debug.appendtoenum(kMinimapBlipType, "BabblerEgg")
debug.appendtoenum(kMinimapBlipType, "SporeMine")
debug.appendtoenum(kMinimapBlipType, "Pheromone_Defend")
debug.appendtoenum(kMinimapBlipType, "Pheromone_Threat")
debug.appendtoenum(kMinimapBlipType, "Pheromone_Expand")

function GetPlayersAboveLimit(team)
    local info = GetTeamInfoEntity(team)
    if not info then return 0 end
    return math.max(0,(info.playerCount or 0) - kMatchMinPlayers)
end

-- Ramp endpoint for the respawn "blue curve" = the DEADLOCK START TIME (as an offset
-- in seconds from round start). Sourced LIVE from the deadlock config rather than
-- hardcoded, so if the deadlock start time is reconfigured the respawn ramp follows
-- it automatically:
--   * Server: NS2Gamerules.kBalanceConfig.deadlockInitialTime (from NS2.0Config.json;
--     this is the exact value PlayingTeam:OnGameStateChanged uses to schedule deadlock).
--   * Client: derived from the networked GameInfo entity (deadlock absolute time minus
--     round-start time), which the server publishes every tick from round start on.
--   * Fallback: kRespawnRampFallbackSeconds, only if neither source is available yet.
-- NOTE: if the round's deadlock start is later EXTENDED mid-game, the server keeps using
-- the original configured offset (a fixed curve) while the client's GameInfo-derived
-- value tracks the current projected deadlock - a display-only divergence on the HUD
-- respawn readout, never a gameplay difference (the server value is authoritative).
local kRespawnRampFallbackSeconds = 1500  -- 25 min; used if no deadlock time is available yet
-- HARD CAP on the ramp length. The deadlock config DEFAULTS to 2400s (40 min); with a 40-min
-- ramp the convex factor (gameTime/ramp)^power stays ~0 for almost the whole game, so respawn
-- never visibly climbs off the base - which is the "Marines stuck at 8s all game" bug. Capping
-- the ramp at 25 min means the respawn curve reaches its max by ~25 min no matter how late the
-- deadlock is set, while still tracking a SHORTER deadlock if one is configured.
local kRespawnRampMaxSeconds = 1500  -- 25 min

local function GetRespawnRampSeconds()
    local ramp = kRespawnRampFallbackSeconds
    if Server and NS2Gamerules and NS2Gamerules.kBalanceConfig
       and NS2Gamerules.kBalanceConfig.deadlockInitialTime then
        ramp = NS2Gamerules.kBalanceConfig.deadlockInitialTime
    else
        local info = GetGameInfoEntity and GetGameInfoEntity()
        if info and info.GetMarineDeadlockTime and info.GetStartTime then
            local offset = info:GetMarineDeadlockTime() - info:GetStartTime()
            if offset and offset > 0 then ramp = offset end
        end
    end
    -- Guard against a 0/negative/nil ramp (e.g. a misconfigured deadlockInitialTime): a 0 here
    -- would make x/ramp a divide-by-zero (inf/nan) and poison the whole curve. Floor at the
    -- fallback so the ramp length is always a sane positive number.
    if not ramp or ramp <= 0 then ramp = kRespawnRampFallbackSeconds end
    return math.min(ramp, kRespawnRampMaxSeconds)
end
-- Respawn "blue curve" tuning (see GetRespawnTimeExtend).
--
-- Design goal: BOTH teams start the round at their base respawn (marines 9s,
-- aliens 10s) and the respawn-time INCREASE stays small through early+mid game,
-- then accelerates toward late-game (convex ramp). Crucially the crowd-size and
-- tech lengthening are ALSO scaled by that same time curve - otherwise the flat
-- crowd term (+1s per player over kMatchMinPlayers, i.e. up to +10s at 20v20)
-- pins respawn near the cap from minute one and there is no "start at 9/10".
--
-- Marines are the statistically weaker early/mid team, so they get a HIGHER ramp
-- power (flatter early, steeper late): their respawn hugs the 9s base longer and
-- only lengthens sharply in the late game once their tech/Exo power spike lands.
-- Aliens use a lower power so their respawn increase kicks in a little sooner.
-- All values are tuning knobs - adjust after watching win-rate-vs-time.
--
-- The player-count (+1s per player over kMatchMinPlayers), tech (kTechRespawnTimeExtension
-- seconds) and Infantry-Portal reduction factors keep their CURRENT values and meaning -
-- they are summed exactly as before. The only new behaviour is an OVERALL time envelope
-- (the convex factor below) multiplying that whole sum: ~0 at round start (respawn == base
-- 9s/10s, fast), rising to full value by the deadlock start time (slow), still capped at
-- +11 so the maximum respawn stays 20s marines / 21s aliens. At a full 25v25 server the
-- player-count term alone (+15) already exceeds the +11 cap, so late-game respawn always
-- reaches the 20/21 max; tech/IP then mainly shape HOW SOON the cap is approached.
-- Ramp powers. Higher = flatter early / steeper late. These were 4/2, which (together with
-- the long deadlock ramp) kept respawn glued to the base for ~30 min. Lowered to 2/1.5 so the
-- increase is actually visible through the early/mid game while marines still climb a touch
-- more gently than aliens (marines are the weaker early team).
local kMarineRespawnRampPower  = 2      -- marines: still a little flatter early than aliens
local kAlienRespawnRampPower   = 1.5    -- aliens: ramp up a bit sooner
-- Seconds of respawn extension added per player OVER kMatchMinPlayers (10). The old
-- value was 1.0s/player, which on a full 25v25 server meant +15s from crowd alone -
-- that single-handedly blew past the +11 cap and made tech/round-length irrelevant.
-- 0.25s/player (=> ~+3.75s at a full 25-player team) keeps the crowd term a real but
-- modest contributor, so the respawn accrues NATURALLY from tech + round length +
-- player count + IPs and, under the convex envelope below, reaches the 20s/21s max only
-- around the deadlock start time rather than well before it. Appropriate for 25v25.
local kRespawnSecondsPerPlayer = 0.25
-- Small GUARANTEED baseline the respawn ramps toward, so it still climbs on a low-tech game
-- and never sits flat. Kept LOW (headroom option, for 25v25) so the crowd + tech + IP factors
-- actually drive how high it goes: at 25v25 the crowd term is only +3.75, so with this small
-- baseline the +11 cap is NOT auto-saturated - a fully-teched team reaches the 20s/21s max,
-- a low-tech team maxes lower, and extra Infantry Portals shave it down. Raise this toward
-- ~8 if you'd rather it always reach the cap by deadlock regardless of tech.
local kRespawnTimeRampMax = 2

function GetRespawnTimeExtend(player,teamIndex, _gameLength)
    --_gameLength = _gameLength * 60
    local x = _gameLength or 0   -- guard: never nil (would break the x/ramp division)

    -- No extension before the round starts. GetGameStartTime() returns 0 in pre-game, which
    -- would make _gameLength (= now - 0) huge and force the ramp to full - so guard it here so
    -- both the actual respawn (Team.lua) and the networked HUD value read 0 during pre-game.
    local gr = GetGamerules and GetGamerules()
    if gr and gr.GetGameStarted and not gr:GetGameStarted() then
        return 0
    end

    -- ── ALIENS: original NON-scaled respawn (no exponential time ramp - that is MARINES only).
    -- The base is the 10s kAlienSpawnTime MINIMUM. Crowd size over the match minimum + researched
    -- tech (kTechRespawnTimeExtension, e.g. higher Biomass) can LENGTHEN it. Each BUILT Hive then
    -- trims 1s back off - but ONLY as far as cancelling that lengthening (the math.min below), so
    -- the respawn NEVER drops below the 10s base: with no lengthening, Hives do nothing and the
    -- respawn stays at 10s; if it has been pushed up, each Hive claws 1s back toward the 10s min.
    -- Returns an extension of 0..11, i.e. total alien respawn 10s..21s.
    if teamIndex == kAlienTeamType then
        -- Lengthening factors (flat, NOT time-scaled) - the ORIGINAL alien increase: +1s per
        -- player over the match minimum (the original rate, NOT the marines' reduced 0.25s/player)
        -- plus researched tech from kTechRespawnTimeExtension.
        local increase = math.max( GetPlayersAboveLimit(teamIndex) , 0 ) * 1
        local teamTechTree = GetTechTree and GetTechTree(teamIndex)
        if teamTechTree and teamTechTree.GetHasTech then
            for k, v in pairs(kTechRespawnTimeExtension) do
                if teamTechTree:GetHasTech(k, true) then increase = increase + v end
            end
        end
        increase = Clamp(increase, 0, 11)   -- cap so the alien maximum respawn stays 21s

        -- Count only BUILT hives (alive AND fully constructed). GetActiveHiveCount checks
        -- GetIsAlive()+GetIsBuilt(); the networked GetNumHives is captured tech points (would
        -- count a half-built hive), so prefer the real built count. GetRespawnTimeExtend runs
        -- server-side (Team.lua queue + TeamInfo networking) and the result is networked to
        -- clients, so the server-only team method is safe; fall back to the netvar otherwise.
        local hives = 0
        local gr    = GetGamerules and GetGamerules()
        local team  = gr and gr.GetTeam and gr:GetTeam(teamIndex)
        if team and team.GetActiveHiveCount then
            hives = team:GetActiveHiveCount()
        else
            local info = GetTeamInfoEntity(teamIndex)
            hives = (info and info.GetNumHives and info:GetNumHives()) or 0
        end

        -- math.min mitigation: the 1s-per-Hive reduction can only offset the lengthening, so the
        -- total can never fall under the 10s base minimum. (0 increase -> Hives change nothing.)
        return increase - math.min(1 * hives, increase)
    end

    -- ── MARINES ONLY from here down (scaled ramp + 0.25s per BUILT Infantry Portal). ──
    -- Factors that LENGTHEN respawn: crowd size over the match minimum + researched tech.
    local lengthen = math.max( GetPlayersAboveLimit(teamIndex) , 0 ) * kRespawnSecondsPerPlayer
    -- TEAM-based tech check (the team's tech tree, by team number) so it evaluates the same
    -- on the server and reflects the TEAM's research - not GetHasTech(localPlayer), which on
    -- a client only knows the local viewer's tree (the spectator-vs-player mismatch). The
    -- per-team result is networked (TeamInfo) for the HUD.
    local teamTechTree = GetTechTree and GetTechTree(teamIndex)
    if teamTechTree and teamTechTree.GetHasTech then
        for k,v in pairs(kTechRespawnTimeExtension) do
            if teamTechTree:GetHasTech(k, true) then
                lengthen = lengthen + v
            end
        end
    end

    -- Growth target the ramp climbs toward = the guaranteed time-ramp max PLUS the factors
    -- that lengthen (crowd + tech). Capped at +11 so the SCALED part alone reaches at most
    -- base+11 = 20s/21s. The flat structure reduction below is subtracted on TOP of this.
    local growthTarget = Clamp(kRespawnTimeRampMax + lengthen, 0, 11)

    -- Convex time envelope: 0 at game start -> 1 at the ramp end (see GetRespawnRampSeconds).
    -- power > 1 keeps the OVERALL respawn increase shallow early (fast respawns) and steep
    -- late; marines use the higher power so their curve is flatter through the early/mid game.
    -- The convex envelope applies ONLY to the growth, so the rate-of-growth (2nd derivative)
    -- rises over the round as originally requested.
    local power  = kMarineRespawnRampPower   -- marine-only path (aliens returned early above)
    local t      = Clamp(x / GetRespawnRampSeconds(), 0, 1)
    local convex = t ^ power
    local convexGrowth = convex * growthTarget

    -- FLAT Infantry-Portal reduction - deliberately NOT scaled by the convex envelope: 0.25s
    -- per BUILT IP, capped at the map-wide limit kMaxInfantryPortalsGlobal (=12) -> max 3s.
    -- info.numInfantryPortals comes from GetNumActiveInfantryPortals (GetIsUnitActive), so ONLY
    -- constructed/active IPs count - an unbuilt/ghost IP grants NO reduction until it finishes.
    -- Recomputed each tick from the CURRENT built count, so IPs gained/lost change it live.
    local flatReduce = 0
    local info = GetTeamInfoEntity(teamIndex)
    if info and info.numInfantryPortals then
        local ipCap = kMaxInfantryPortalsGlobal or 12
        flatReduce = math.min(info.numInfantryPortals, ipCap) * 0.25
    end

    -- Final MARINE extension = scaled growth minus the flat IP reduction, clamped to [0, 11].
    -- The 0 floor guarantees the marine MINIMUM stays the 9s base no matter how many IPs; the
    -- +11 cap keeps the marine MAXIMUM at 20s.
    return Clamp(convexGrowth - flatReduce, 0, 11)
end