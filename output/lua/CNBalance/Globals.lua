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

-- Prototype-Exo scoreboard combo statuses.  One per weapon combination, plus a
-- "…Plus" variant used when the Exo carries ANY Experimental Technology upgrade
-- (the trailing "+" on the scoreboard).  Exo:GetPlayerStatusDesc (Exo.lua) picks
-- which one to return from self.layout + GetHasPrototypeUpgrade.
debug.appendtoenum(kPlayerStatus, "ExoDualMinigun")
debug.appendtoenum(kPlayerStatus, "ExoDualRail")
debug.appendtoenum(kPlayerStatus, "ExoDualFT")
debug.appendtoenum(kPlayerStatus, "ExoClawMinigun")
debug.appendtoenum(kPlayerStatus, "ExoClawRail")
debug.appendtoenum(kPlayerStatus, "ExoClawFT")
debug.appendtoenum(kPlayerStatus, "ExoDualMinigunPlus")
debug.appendtoenum(kPlayerStatus, "ExoDualRailPlus")
debug.appendtoenum(kPlayerStatus, "ExoDualFTPlus")
debug.appendtoenum(kPlayerStatus, "ExoClawMinigunPlus")
debug.appendtoenum(kPlayerStatus, "ExoClawRailPlus")
debug.appendtoenum(kPlayerStatus, "ExoClawFTPlus")

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

function GetRespawnTimeExtend(player, teamIndex, _gameLength)
    -- player is not used in the code so ignore this variable

    -- Sanity checks
    if not teamIndex or not _gameLength then return 0 end

    -- Has the round started?
    local gr = GetGamerules and GetGamerules()
    if gr and gr.GetGameStarted and not gr:GetGameStarted() then
        return 0
    end

    local kEndGameBegin = 1500

    -- Now globals (Balance.lua) so the deadlock phase-two ramp below scales the same values these
    -- are, rather than a private copy that would drift if either is retuned.
    --
    -- Phase two lifts the MAXIMUM linearly to kDeadlockPhase2RespawnMultiplier over its duration; the
    -- minimum (kMarineRespawnTime / kAlienSpawnTime) is untouched, so a team spawning at its floor is
    -- unaffected and only the worst case stretches.
    local phase2 = GetDeadlockPhase2Fraction and GetDeadlockPhase2Fraction(_gameLength) or 0
    local respawnScale = 1 + phase2 * ((kDeadlockPhase2RespawnMultiplier or 2) - 1)

    local kDesiredMarinesMaximumRespawnTime = kDesiredMarinesMaximumRespawnTime * respawnScale
    local kDesiredAliensMaximumRespawnTime = kDesiredAliensMaximumRespawnTime * respawnScale

    local kDifferenceBetweenMarinesMaximumAndMinimumRespawnTime = kDesiredMarinesMaximumRespawnTime - kMarineRespawnTime
    local kDifferenceBetweenAliensMaximumAndMinimumRespawnTime = kDesiredAliensMaximumRespawnTime - kAlienSpawnTime

    -- Without Military Protocol Marines tech increases their respawn time less compared to Aliens tech for Aliens
    local kMarinesTechScaleFactor = 1/3
    local kAliensTechScaleFactor = 1/2

    -- Handle simple cases (and stop division by zero occuring)
    if _gameLength >= kEndGameBegin then
        if teamIndex == kMarineTeamType then
            return kDifferenceBetweenMarinesMaximumAndMinimumRespawnTime
        elseif teamIndex == kAlienTeamType then
            return kDifferenceBetweenAliensMaximumAndMinimumRespawnTime
        end
    end

    -- Handle tech
    local tech = 0
    local techTree = GetTechTree and GetTechTree(teamIndex)
    if techTree and techTree.GetHasTech then
        
        -- Check Marines for Military Protocol
        if techTree:GetHasTech(kTechId.MilitaryProtocol, true) then kMarinesTechScaleFactor = 1/2 end
        for k, v in pairs(kTechRespawnTimeExtension) do
            if techTree:GetHasTech(k, true) then
                if teamIndex == kTeam1Index then
                    tech = tech + kMarinesTechScaleFactor * v
                elseif teamIndex == kTeam2Index then
                    tech = tech + kAliensTechScaleFactor * v
                end
            end
        end
    end

    local timeToRemoveForMarines = 0
    local timeToRemoveForAliens = 0

    local timeToRemovePerBuiltIP = 1/3
    local timeToRemovePerBuiltHive = 1

    -- Time at any point has less of an impact on Marines respawn time compared to later on up to the maximum respawn time for Marines
    local exponentScaleFactorForRoundLengthAffectingMarinesRespawnTime = 2
    local exponentScaleFactorForRoundLengthAffectingAliensRespawnTime = 1

    -- Handle Marines considerations
    if teamIndex == kMarineTeamType then

        -- Built IPs
        local builtIPs = 0
        local ip = GetEntitiesForTeam("InfantryPortal", kTeam1Index)
        for _, ent in ipairs(ip) do
            if ent.GetIsBuilt and ent:GetIsBuilt() then builtIPs = builtIPs + 1 end
        end

        timeToRemoveForMarines = builtIPs * timeToRemovePerBuiltIP

        -- Clamp respawn time increase between 0 and the maximum difference between respawn times for Marines considering tech and built IPs
        local consideredMarinesTechAndBuiltIPs = Clamp(tech - timeToRemoveForMarines, 0, kDesiredMarinesMaximumRespawnTime - kMarineRespawnTime)
        local restOfMarinesRespawnTimeRequired = kDifferenceBetweenMarinesMaximumAndMinimumRespawnTime - consideredMarinesTechAndBuiltIPs

        -- Add a potentially non-linearly scaled amount of the rest of the respawn time increase needed to get to the desired maximum for Marines and return the result
        return consideredMarinesTechAndBuiltIPs + ((_gameLength / kEndGameBegin) ^ exponentScaleFactorForRoundLengthAffectingMarinesRespawnTime) * restOfMarinesRespawnTimeRequired

    -- Handle Aliens considerations
    elseif teamIndex == kAlienTeamType then

        -- Built Hives
        local builtHives = 0
        local hives = GetEntitiesForTeam("Hive", kTeam2Index)
        for _, ent in ipairs(hives) do
            if ent.GetIsBuilt and ent.GetIsAlive and ent:GetIsBuilt() and ent:GetIsAlive() then builtHives = builtHives + 1 end
        end

        timeToRemoveForAliens = builtHives * timeToRemovePerBuiltHive

        -- Clamp respawn time increase between 0 and the maximum difference between respawn times for Aliens considering tech and built Hives
        local consideredAliensTechAndBuiltHives = Clamp(tech - timeToRemoveForAliens, 0, kDesiredAliensMaximumRespawnTime - kAlienSpawnTime)
        local restOfAliensRespawnTimeRequired = kDifferenceBetweenAliensMaximumAndMinimumRespawnTime - consideredAliensTechAndBuiltHives

        -- Add a potentially non-linearly scaled amount of the rest of the respawn time increase needed to get to the desired maximum for Aliens and return the result
        return consideredAliensTechAndBuiltHives + ((_gameLength / kEndGameBegin) ^ exponentScaleFactorForRoundLengthAffectingAliensRespawnTime) * restOfAliensRespawnTimeRequired
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