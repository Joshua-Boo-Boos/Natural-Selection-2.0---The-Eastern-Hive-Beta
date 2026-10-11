--[[
    ARCUS (ARC Upgrade System) - shot effects for the V.A.T. and H.E.L.L.

    Loaded post lua/NetworkMessages.lua (every VM), so the message is registered identically on server and client.

    WHY A MESSAGE. A bullet tracer normally arrives in the damage hit message, but that message only goes to players near the
    ATTACKER - and an ARC's attacker is its owner, the commander, sitting in the Command Station. So players near the tank
    mostly never got a tracer. Server-made cinematics could not leave the barrel either: the server does not animate the
    ARC's bones. One small message per shot fixes both: every client draws the shot itself, from the ARC's real muzzle
    attach point (fxnode_arcmuzzle, the point vanilla's own ARC fire effects use) to the target.

    Not a network variable or class - just one message type. Shots are a few per second at most per tank.

      mg       rifle muzzle flash, pistol shot sound, normal bullet tracer
      shell    bullet tracer (the charge / fire cinematics and sounds are the ARC's own arc_charge / arc_firing effects)
      railgun  railgun tracer and residue
      flame    a flame stream of short bursts laid along the whole line at once, so it ALWAYS reaches the target instantly
]]

ARCSpec = ARCSpec or {}

ARCSpec.kShotKind = { mg = 0, shell = 1, railgun = 2, flame = 3 }

local kShotMessage =
{
    arcId = "entityid",
    endPoint = "vector",
    kind = "integer (0 to 3)",
}

Shared.RegisterNetworkMessage("ARCSpecShot", kShotMessage)

--[[
    ARCUS research tray state (commander and spectator HUD). TeamInfo's tech bitmask - what that tray normally reads - is
    already full, so each team's specialisation state travels in this message instead (sent by ARCSpec_MarineTeam.lua on
    change, and every few seconds for late joiners). Per specialisation: state 0 = never had one, 1 = active (a factory
    of it stands), 2 = lost (had one, all gone); level = upgrades researched (0-4).
]]
local kTeamStateMessage =
{
    teamNumber = "integer (0 to 3)",
    hammerState = "integer (0 to 2)", hammerLevel = "integer (0 to 4)",
    vanguardState = "integer (0 to 2)", vanguardLevel = "integer (0 to 4)",
    infernoState = "integer (0 to 2)", infernoLevel = "integer (0 to 4)",
}

Shared.RegisterNetworkMessage("ARCSpecTeamState", kTeamStateMessage)

-- Client copy: ARCSpec.teamState[teamNumber][specKey] = { state = n, level = n }.
ARCSpec.teamState = ARCSpec.teamState or {}

if Client then
    Client.HookNetworkMessage("ARCSpecTeamState", function(message)
        ARCSpec.teamState[message.teamNumber] =
        {
            hammer = { state = message.hammerState, level = message.hammerLevel },
            vanguard = { state = message.vanguardState, level = message.vanguardLevel },
            inferno = { state = message.infernoState, level = message.infernoLevel },
        }
    end)
end

local kMuzzleAttachPoint = "fxnode_arcmuzzle"
local kMGMuzzleCinematic = PrecacheAsset("cinematics/marine/rifle/muzzle_flash.cinematic")
local kFlameBurstCinematic = PrecacheAsset("cinematics/marine/flamethrower/flame_impact3.cinematic")
local kMGSound = PrecacheAsset("sound/NS2.fev/marine/pistol/fire")
local kFlameSound = PrecacheAsset("sound/NS2.fev/marine/flamethrower/attack_start")

local kFlameStepLength = 1
local kMaxFlameSteps = 20

if Server then

    function ARCSpec.SendShot(arc, kind, endPoint)
        if not arc or not endPoint then return end
        Server.SendNetworkMessage("ARCSpecShot", { arcId = arc:GetId(), endPoint = endPoint, kind = kind }, true)
    end

end

if Client then

    local function GetMuzzlePoint(arc)
        if arc.GetAttachPointIndex and arc.GetAttachPointCoords and arc:GetAttachPointIndex(kMuzzleAttachPoint) ~= -1 then
            local coords = arc:GetAttachPointCoords(kMuzzleAttachPoint)
            if coords then
                return coords.origin
            end
        end
        return arc:GetEyePos()
    end

    local function PlayCinematic(asset, origin, direction)
        local cinematic = Client.CreateCinematic(RenderScene.Zone_Default)
        cinematic:SetCinematic(asset)
        cinematic:SetCoords(Coords.GetLookIn(origin, direction))
    end

    local function OnShot(message)

        local arc = Shared.GetEntity(message.arcId)
        if not arc or not arc.GetEyePos then return end

        local startPoint = GetMuzzlePoint(arc)
        local endPoint = message.endPoint
        local distance = (endPoint - startPoint):GetLength()
        if distance < 0.1 then return end

        local direction = GetNormalizedVector(endPoint - startPoint)
        local velocity = direction * (kTracerSpeed or 115)
        local kind = message.kind

        if kind == ARCSpec.kShotKind.mg then

            PlayCinematic(kMGMuzzleCinematic, startPoint, direction)
            Shared.PlayWorldSound(nil, kMGSound, nil, startPoint, 1)
            CreateTracer(startPoint, endPoint, velocity, arc)

        elseif kind == ARCSpec.kShotKind.shell then

            CreateTracer(startPoint, endPoint, velocity, arc)

        elseif kind == ARCSpec.kShotKind.railgun then

            if kRailgunTracerEffectName then
                CreateTracer(startPoint, endPoint, velocity, arc, kRailgunTracerEffectName, kRailgunTracerResidueEffectName)
            else
                CreateTracer(startPoint, endPoint, velocity, arc)
            end

        elseif kind == ARCSpec.kShotKind.flame then

            Shared.PlayWorldSound(nil, kFlameSound, nil, startPoint, 1)
            local steps = math.min(kMaxFlameSteps, math.max(1, math.ceil(distance / kFlameStepLength)))
            for i = 0, steps do
                PlayCinematic(kFlameBurstCinematic, startPoint + direction * (distance * i / steps), direction)
            end

        end

    end

    Client.HookNetworkMessage("ARCSpecShot", OnShot)

end
