Shared.RegisterNetworkMessage("DevourEscape", {})

function OnCommandScores(scoreTable)

    local status = kPlayerStatus[scoreTable.status]
    if scoreTable.status == kPlayerStatus.Hidden then
        status = "-"
    elseif scoreTable.status == kPlayerStatus.Dead then
        status = Locale.ResolveString("STATUS_DEAD")
    elseif scoreTable.status == kPlayerStatus.Evolving then
        status = Locale.ResolveString("STATUS_EVOLVING")
    elseif scoreTable.status == kPlayerStatus.Embryo then
        status = Locale.ResolveString("STATUS_EMBRYO")
    elseif scoreTable.status == kPlayerStatus.Commander then
        status = Locale.ResolveString("STATUS_COMMANDER")
    elseif scoreTable.status == kPlayerStatus.Exo then
        status = Locale.ResolveString("STATUS_EXO")
    elseif scoreTable.status == kPlayerStatus.GrenadeLauncher then
        status = Locale.ResolveString("STATUS_GRENADE_LAUNCHER")
    elseif scoreTable.status == kPlayerStatus.Rifle then
        status = Locale.ResolveString("STATUS_RIFLE")
    elseif scoreTable.status == kPlayerStatus.HeavyMachineGun then
        status = Locale.ResolveString("STATUS_HMG")
    elseif scoreTable.status == kPlayerStatus.Shotgun then
        status = Locale.ResolveString("STATUS_SHOTGUN")
    elseif scoreTable.status == kPlayerStatus.Flamethrower then
        status = Locale.ResolveString("STATUS_FLAMETHROWER")
    elseif scoreTable.status == kPlayerStatus.Void then
        status = Locale.ResolveString("STATUS_VOID")
    elseif scoreTable.status == kPlayerStatus.Spectator then
        status = Locale.ResolveString("STATUS_SPECTATOR")
    elseif scoreTable.status == kPlayerStatus.Skulk then
        status = Locale.ResolveString("STATUS_SKULK")
    elseif scoreTable.status == kPlayerStatus.Gorge then
        status = Locale.ResolveString("STATUS_GORGE")
    elseif scoreTable.status == kPlayerStatus.Lerk then
        status = Locale.ResolveString("STATUS_LERK")
    elseif scoreTable.status == kPlayerStatus.Fade then
        status = Locale.ResolveString("STATUS_FADE")
    elseif scoreTable.status == kPlayerStatus.Onos then
        status = Locale.ResolveString("STATUS_ONOS")
    elseif scoreTable.status == kPlayerStatus.SkulkEgg then
        status = Locale.ResolveString("SKULK_EGG")
    elseif scoreTable.status == kPlayerStatus.GorgeEgg then
        status = Locale.ResolveString("GORGE_EGG")
    elseif scoreTable.status == kPlayerStatus.LerkEgg then
        status = Locale.ResolveString("LERK_EGG")
    elseif scoreTable.status == kPlayerStatus.FadeEgg then
        status = Locale.ResolveString("FADE_EGG")
    elseif scoreTable.status == kPlayerStatus.OnosEgg then
        status = Locale.ResolveString("ONOS_EGG")
    elseif scoreTable.status == kPlayerStatus.Devoured then
        status = Locale.ResolveString("STATUS_DEVOURED")
    end

    Scoreboard_SetPlayerData(scoreTable.clientId, scoreTable.entityId, scoreTable.playerName, scoreTable.teamNumber, scoreTable.score,
            scoreTable.kills, scoreTable.deaths, math.floor(scoreTable.resources), scoreTable.isCommander, scoreTable.isRookie,
            status, scoreTable.isSpectator, scoreTable.assists, scoreTable.clientIndex)

end


local kMarineBuildStructureMessage =
{
    origin = "vector",
    direction = "vector",
    -- Index into CombatBuilder.kSupportedStructures. Was 1..5 when the Combat Builder offered only a
    -- Sentry and a Supply Depot; Combat Engineers adds ten more, so the range must cover the whole
    -- list or the extra structures would be silently unsendable.
    structureIndex = "integer (1 to 16)",
    lastClickedPosition = "vector",
    -- The surface normal captured at the FIRST click of a two-click (place-then-rotate) placement.
    -- The server's own GetPositionForStructure call has no access to the client's local ghost
    -- state, so the locked normal has to travel over the wire alongside the locked position for the
    -- server to reconstruct the exact same orientation the client confirmed.
    lastClickedNormal = "vector"
}
Shared.RegisterNetworkMessage("MarineBuildStructure", kMarineBuildStructureMessage)

function BuildMarineDropStructureMessage(origin, direction, structureIndex, lastClickedPosition, lastClickedNormal)

    local t = {}

    t.origin = origin
    t.direction = direction
    t.structureIndex = structureIndex
    t.lastClickedPosition = lastClickedPosition or Vector(0,0,0)
    t.lastClickedNormal = lastClickedNormal or Vector(0,1,0)

    return t
end

local kScoreUpdate =
{
    points = "integer (0 to " .. kMaxScore .. ")",
    res = "float (0 to " .. kMaxPersonalResources ..  " by 0.1)",
    wasKill = "boolean"
}
Shared.RegisterNetworkMessage("ScoreUpdate", kScoreUpdate)

local kGorgeBuildStructureMessage =
{
    origin = "vector",
    direction = "vector",
    structureIndex = string.format("integer (1 to %d)",#kTechId),
    lastClickedPosition = "vector",
    lastClickedPositionNormal = "vector"
}

Shared.RegisterNetworkMessage("GorgeBuildStructure", kGorgeBuildStructureMessage)

-- Marine Commander Exo drop: the configuration chosen in the commander's Exosuit buy window
-- (CNBalance/GUI/GUICommanderExoDropMenu.lua), sent CLIENT -> SERVER when the commander clicks
-- BUY and before the placement ghost is armed. The server stashes it on the commander and
-- applies it to the Exosuit created by the subsequent DropDualMinigunExosuit placement.
-- Advisory only: the server re-validates the combo, the research gates and the t-res cost at
-- placement time, so a crafted message cannot drop a free or unresearched Exo.
-- upgradeBits uses PrototypeUpgradesMixin.kBit indices (5 exo upgrades -> bits 0..4).
local kCommanderExoConfigMessage =
{
    baseTechId  = string.format("integer (1 to %d)", #kTechId),
    upgradeBits = "integer (0 to 255)",
}

Shared.RegisterNetworkMessage("CommanderExoConfig", kCommanderExoConfigMessage)

-- Combat Engineers: a field marine starting a research/upgrade on a structure through the Combat
-- Builder's right-click upgrade window (CLIENT -> SERVER). Advisory only - the server re-validates
-- the structure, the tech node and the team's t-res before charging anything.
local kCEStructureUpgradeMessage =
{
    entityId = "entityid",
    techId   = string.format("integer (1 to %d)", #kTechId),
}

Shared.RegisterNetworkMessage("CEStructureUpgrade", kCEStructureUpgradeMessage)

if Server then

    function SendDamageMessage(attacker, targetEntityId, amount, point, overkill, weapon, type)

        if amount > 0 then

            local damageType = type or kDamageMessageType.Default
            local msg = BuildDamageMessage(targetEntityId, amount, point, damageType)

            Server.SendNetworkMessage(attacker, "Damage", msg, true)

            for _, spectator in ientitylist(Shared.GetEntitiesWithClassname("Spectator")) do
                local owner = Server.GetOwner(spectator)
                if owner and attacker == owner:GetSpectatingPlayer() then
                    Server.SendNetworkMessage(spectator, "Damage", msg, false)
                end
            end

        end

    end

end
