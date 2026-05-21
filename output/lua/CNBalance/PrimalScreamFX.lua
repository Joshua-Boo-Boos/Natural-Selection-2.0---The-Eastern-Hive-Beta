-- PrimalScreamFX
--
-- Networks the per-entity primal-scream WINDOW to clients. Sounds are no
-- longer sent here -- they are played server-side in PrimalScreamMixin via
-- StartSoundEffectOnEntity (a networked SoundEffect heard by all nearby
-- clients, volume-balanced per-listener by SoundEffect.lua).
--
-- The window is still needed on the client because the attack-speed override
-- (Alien.lua / Vokex.lua) must know that an enzymed alien's enzyme came from
-- PrimalScream (so it predicts the half-strength buff instead of full enzyme).
-- The mixin's enzymeIsFromPrimalScream field is server-only (never merged into
-- the Alien network spec), so we sync the window explicitly here.

local kPrimalScreamFXMessage =
{
    entityId = "entityid",
    duration = "float (0 to 60 by 0.05)",
}

Shared.RegisterNetworkMessage("PrimalScreamFX", kPrimalScreamFXMessage)

if Server then

    -- duration > 0 opens the window; duration 0 clears it (real enzyme took over).
    function SendPrimalScreamFX(entity, duration)

        if not entity then return end

        Server.SendNetworkMessage("PrimalScreamFX",
        {
            entityId = entity:GetId(),
            duration = duration or 0,
        }, true)

    end

end

if Client then

    -- entityId -> primal-scream end time (in Shared.GetTime() units).
    gPrimalScreamClientEndTimes = gPrimalScreamClientEndTimes or {}

    function GetClientPrimalScreamEndTime(entityId)
        return gPrimalScreamClientEndTimes[entityId] or 0
    end

    function GetIsClientPrimalScreamed(entityId)
        return (gPrimalScreamClientEndTimes[entityId] or 0) > Shared.GetTime()
    end

    local function OnPrimalScreamFX(message)

        local entityId = message.entityId
        if not entityId then return end

        if message.duration and message.duration > 0 then
            gPrimalScreamClientEndTimes[entityId] = Shared.GetTime() + message.duration
        else
            gPrimalScreamClientEndTimes[entityId] = 0
        end

    end

    Client.HookNetworkMessage("PrimalScreamFX", OnPrimalScreamFX)

end
