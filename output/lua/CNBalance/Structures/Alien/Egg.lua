
-- ===========================================================================
-- NS2.0-TEH: add commander-droppable Prowler (Biomass 4) and Vokex (Biomass 8)
-- lifeform eggs alongside the vanilla Gorge/Lerk/Fade/Onos eggs. The egg stays
-- an "Egg" entity; the chosen lifeform is driven entirely by the techId, so we
-- only need to (1) offer the buttons, (2) accept the research, and (3) map the
-- egg techId to the lifeform to gestate. These are post-hook overrides.
-- ===========================================================================

function Egg:GetTechButtons(techId)

    -- Default (already-upgraded eggs) keep the vanilla "nothing to do" layout.
    local techButtons = { kTechId.SpawnAlien, kTechId.None, kTechId.None, kTechId.None,
                          kTechId.None, kTechId.None, kTechId.None, kTechId.None }

    if self:GetTechId() == kTechId.Egg then
        -- 8 button slots: SpawnAlien + the 6 lifeform eggs. Prowler & Vokex take
        -- the previously-empty slots 2 and 3.
        techButtons = { kTechId.SpawnAlien, kTechId.ProwlerEgg, kTechId.VokexEgg, kTechId.None,
                        kTechId.GorgeEgg, kTechId.LerkEgg, kTechId.FadeEgg, kTechId.OnosEgg }
    end

    return techButtons

end

local kBaseEggOnResearchComplete = Egg.OnResearchComplete
function Egg:OnResearchComplete(techId)

    if techId == kTechId.ProwlerEgg or techId == kTechId.VokexEgg then
        self:UpgradeToTechId(techId)
        return false
    end

    return kBaseEggOnResearchComplete(self, techId)

end

local kBaseEggGetGestateTechId = Egg.GetGestateTechId
function Egg:GetGestateTechId()

    local techId = self:GetTechId()
    if self:GetIsResearching() then
        techId = self:GetResearchingId()
    end

    if techId == kTechId.ProwlerEgg then
        return kTechId.Prowler
    elseif techId == kTechId.VokexEgg then
        return kTechId.Vokex
    end

    return kBaseEggGetGestateTechId(self)

end

-- Grab player out of respawn queue unless player passed in (for test framework)
function Egg:SpawnPlayer(player)

    PROFILE("Egg:SpawnPlayer")

    local queuedPlayer = player
    
    if not queuedPlayer or self.queuedPlayerId ~= nil then
        queuedPlayer = Shared.GetEntity(self.queuedPlayerId)
    end
    
    if queuedPlayer ~= nil then
    
        local queuedPlayer = player
        if not queuedPlayer then
            queuedPlayer = Shared.GetEntity(self.queuedPlayerId)
        end
    
        
        -- Spawn player on top of egg
        local spawnOrigin = Vector(self:GetOrigin())
        -- Move down to the ground.
        --local _, normal = GetSurfaceAndNormalUnderEntity(self)
        
        local normal = self:GetCoords().yAxis
        --DebugLine(spawnOrigin,spawnOrigin + normal * 2,5,1,0,0,1)
        if normal.y == 1 then
            spawnOrigin = spawnOrigin - normal* (.664 / 4)
        else
            spawnOrigin = spawnOrigin + normal * 1
        end

        local gestationClass = self:GetClassToGestate()
        
        -- We must clear out queuedPlayerId BEFORE calling ReplaceRespawnPlayer
        -- as this will trigger OnEntityChange() which would requeue this player.
        self.queuedPlayerId = nil
        
        local team = queuedPlayer:GetTeam()
        local success, player = team:ReplaceRespawnPlayer(queuedPlayer, spawnOrigin, queuedPlayer:GetAngles(), gestationClass)                
        player:SetCameraDistance(0)
        player:SetHatched()
        -- It is important that the player was spawned at the spot we specified.
        assert(player:GetOrigin() == spawnOrigin)
        
        if success then
            SetPlayerStartingLocation(player)
            self:PickUpgrades(player)

            self:TriggerEffects("egg_death")
            DestroyEntity(self) 
            
            return true, player
            
        end
            
    end
    
    return false, nil

end
