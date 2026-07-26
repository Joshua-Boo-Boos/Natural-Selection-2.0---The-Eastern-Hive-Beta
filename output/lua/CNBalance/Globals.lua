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
-- Respawn scaling (see GetRespawnTimeExtend). BOTH teams grow with GAME LENGTH + researched TECH
-- toward a +11 cap (=> 20s marines / 21s aliens); PLAYER COUNT is NEVER a factor. Game length is
-- shaped per team: MARINES use a CONVEX ramp (slower early, faster late); ALIENS use a LINEAR ramp.
-- Tech adds on top for both, so a normally-teched team reaches the cap in the late game. Structures
-- then shave the total (0.5s per built IP for marines, 2s per built Hive for aliens); the [0,11]
-- clamp means neither can push below the 9s/10s base - so structures have NO effect at the minimum.
local kMarineRampPower = 3   -- marines: higher power => flatter early / steeper late. Raised 2->3
                             -- to exaggerate the convex shape (slower early game, sharper late-game
                             -- climb) while still reaching the 20s cap by the ramp end.

function GetRespawnTimeExtend(player, teamIndex, _gameLength)
    local x = _gameLength or 0   -- seconds since round start; never nil (guards the x/ramp divide)

    -- No extension before the round starts -> base respawn only during pre-game.
    local gr = GetGamerules and GetGamerules()
    if gr and gr.GetGameStarted and not gr:GetGameStarted() then
        return 0
    end

    -- TECH (both teams): researched respawn-lengthening tech (kTechRespawnTimeExtension - marine
    -- Weapons/Armor 2-3 & Exo/Jetpack labs, alien higher Biomass). Team-based tech tree so it is
    -- correct server-side; the computed extension is networked to every HUD via TeamInfo.
    local tech = 0
    local techTree = GetTechTree and GetTechTree(teamIndex)
    if techTree and techTree.GetHasTech then
        for k, v in pairs(kTechRespawnTimeExtension) do
            if techTree:GetHasTech(k, true) then tech = tech + v end
        end
    end

    -- GAME LENGTH fraction over the ramp: 0 at round start -> 1 by the deadlock time.
    local t = Clamp(x / GetRespawnRampSeconds(), 0, 1)

    if teamIndex == kMarineTeamType then
        -- MARINES: CONVEX game-length growth (slower early, faster late) + tech.
        -- IMPORTANT: the growth is clamped to [0,11] FIRST, THEN the structure deduction is
        -- subtracted. If the deduction were inside the same clamp as the growth, a high tech
        -- total (convexTime + tech can be ~25) would keep the pre-clamp value far above 11, so
        -- the deduction would be swallowed by the +11 cap and never show up at the 20s maximum.
        -- Deducting AFTER the cap means the built-IP reduction ALWAYS lands, even at full respawn.
        -- 0.5s per BUILT Infantry Portal (numInfantryPortals = GetNumActiveInfantryPortals, so
        -- built/active only). The final [0,11] clamp keeps total respawn in [9s base, 20s cap]
        -- and gives the reduction NO effect at the 9s minimum (grown is already 0 there).
        local grown = Clamp( (t ^ kMarineRampPower) * 11 + tech, 0, 11 )
        local ip   = 0
        local info = GetTeamInfoEntity(teamIndex)
        if info and info.numInfantryPortals then ip = info.numInfantryPortals end
        return Clamp( grown - ip / 3, 0, 11 )   -- 1/3 s reduction per built IP
    else
        -- ALIENS: LINEAR game-length growth + tech, same two-stage clamp as marines so the Hive
        -- deduction always lands even at the 21s maximum (see the marine note above). Minus 2s per
        -- BUILT Hive (GetActiveHiveCount = alive AND built; falls back to the networked hive count
        -- when the team object is not available). Final [0,11] clamp keeps total respawn in [10s
        -- base, 21s cap]; the reduction has NO effect at the 10s minimum.
        local grown = Clamp( 11 * t + tech, 0, 11 )
        local hives = 0
        local team  = gr and gr.GetTeam and gr:GetTeam(teamIndex)
        if team and team.GetActiveHiveCount then
            hives = team:GetActiveHiveCount()
        else
            local info = GetTeamInfoEntity(teamIndex)
            hives = (info and info.GetNumHives and info:GetNumHives()) or 0
        end
        return Clamp( grown - hives * 2, 0, 11 )
    end
end

-- ── Prowler reel kill credit ──────────────────────────────────────────────────────────────────
-- Lava and void pits kill via a DeathTrigger entity, which is passed as BOTH the attacker and the
-- doer (DeathTrigger:DoDamageOverTime / :KillEntity) - never an alien weapon. So "attacker is a
-- DeathTrigger" is exactly the case where the game world, not an alien, landed the killing blow.
-- If the victim was reeled by a Prowler within kProwlerReelKillWindow seconds, that Prowler earned
-- the kill. If an alien actually landed the killing blow the attacker is that alien, this returns
-- nil, and the alien correctly keeps the kill.
--
-- SHARED so every path agrees. Two completely separate systems need this:
--   * NS2Gamerules:OnEntityKilled -> the KILLFEED entry
--   * PointGiverMixin:PreOnKill   -> the SCOREBOARD kill (AddKill), the bounty and ALL p-res
-- Previously only the gamerules path reattributed, which is why the killfeed showed the Prowler
-- but the scoreboard never awarded it.
kProwlerReelKillWindow = 5

function GetProwlerReelKillCredit(targetEntity, attacker)

    if not targetEntity or not attacker then return nil end

    -- isa("Marine") covers Marine AND JetpackMarine, and excludes Exos (which cannot be reeled).
    if not targetEntity.isa or not targetEntity:isa("Marine") then return nil end
    if not attacker.isa or not attacker:isa("DeathTrigger") then return nil end

    local reelTime = targetEntity._prowlerReelTime
    if not reelTime or (Shared.GetTime() - reelTime) > kProwlerReelKillWindow then return nil end

    -- If the Prowler has since died or changed form its entity is gone / no longer a Prowler, so
    -- this safely returns nil (no credit) rather than erroring.
    local prowler = targetEntity._prowlerReelPullerId
                    and Shared.GetEntity(targetEntity._prowlerReelPullerId)
    if prowler and prowler.isa and prowler:isa("Prowler") then
        return prowler
    end

    return nil
end