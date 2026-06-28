
function ParseMarineBuildMessage(t)
    return t.origin, t.direction, t.structureIndex, t.lastClickedPosition
end

function OnCommandMarineBuildStructure(client, message)

    local player = client:GetControllingPlayer()
    local origin, direction, structureIndex, lastClickedPosition = ParseMarineBuildMessage(message)
    
    local dropStructureAbility = player:GetActiveWeapon()
    -- The player may not have an active weapon if the message is sent
    -- after the player has gone back to the ready room for example.
    if dropStructureAbility and dropStructureAbility.OnDropStructure then
        dropStructureAbility:OnDropStructure(origin, direction, structureIndex, lastClickedPosition)
    end
    
end
Server.HookNetworkMessage("MarineBuildStructure", OnCommandMarineBuildStructure)


function OnCommandGorgeBuildStructure(client, message)

    local player = client:GetControllingPlayer()
    local origin, direction, structureTechId, lastClickedPosition, lastClickedPositionNormal = ParseGorgeBuildMessage(message)

    local activeAbility = player:GetActiveWeapon()
    if not activeAbility then
        return 
    end
    
    if activeAbility.OnDropStructure then
        activeAbility:OnDropStructure(origin, direction, structureTechId, lastClickedPosition, lastClickedPositionNormal)
    end
end
Server.HookNetworkMessage("GorgeBuildStructure", OnCommandGorgeBuildStructure)


-- ============================================================================
-- NS2.0-TEH: route marine medpack / ammo requests instead of blanket-dropping
-- them. Identified by AlertTechId so the Marine, MAC and Mil-MAC request
-- variants are all caught (covers human key-press requests and bot calls).
--
-- The medpack / ammo request voiceover ALWAYS plays for the requester (human or
-- bot, any Military Protocol or cooldown state). What differs is who, if anyone,
-- is notified afterwards:
--
--   selfservice (Military Protocol off, not on cooldown):
--       grant the pack locally for personal resources; commander NOT alerted.
--   commander (HUMAN on cooldown, or Military Protocol active):
--       fall through to the base call so the Marine commander gets the alert +
--       sounds in addition to the request voiceover.
--   bot that cannot self-service (on cooldown, or Military Protocol active):
--       play the request voiceover only; never alert the commander.
--
-- Entities that fully ignore requests (e.g. devoured players) are dropped with
-- no sound at all. The decision lives in CNBalance/Mixin/RequestHandleMixin.lua
-- so the TriggerAlert path (CNBalance/PlayingTeam.lua) stays in sync.
-- ============================================================================
local TEH_baseCreateVoiceMessage = CreateVoiceMessage
function CreateVoiceMessage(player, voiceId)
    local soundData = GetVoiceSoundData(voiceId)
    local alertTechId = soundData and soundData.AlertTechId
    if alertTechId == kTechId.MarineAlertNeedMedpack or alertTechId == kTechId.MarineAlertNeedAmmo then
        if player and player.GetPackRequestDecision then

            -- entities that fully ignore requests get no sound and no notification.
            if player.kIgnoreRequest then return end

            local isMed = (alertTechId == kTechId.MarineAlertNeedMedpack)
            local decision = player:GetPackRequestDecision(isMed)
            local isHuman = not (player.GetIsVirtual and player:GetIsVirtual())

            if decision == "selfservice" then
                -- play the request voiceover, then grant the pack for personal
                -- resources; the commander is not alerted.
                if soundData.Sound then
                    StartSoundEffectOnEntity(soundData.Sound, player)
                end
                if isMed then
                    player:MedSelf()
                else
                    player:AmmoSelf()
                end
                return
            end

            if not isHuman then
                -- bot that cannot self-service: play the request voiceover only,
                -- never notify the commander.
                if soundData.Sound then
                    StartSoundEffectOnEntity(soundData.Sound, player)
                end
                return
            end

            -- human "commander" route: fall through so the base call plays the
            -- request voiceover AND notifies the Marine commander (alert + sounds).
        end
    end
    return TEH_baseCreateVoiceMessage(player, voiceId)
end