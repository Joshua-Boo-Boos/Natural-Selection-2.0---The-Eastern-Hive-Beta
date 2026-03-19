
-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Alien\SporeCloud.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
--                  Max McGuire (max@unknownworlds.com)
--
--    This class is used for the lerks spore dust cloud attack (trailing spores).
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/TeamMixin.lua")
Script.Load("lua/OwnerMixin.lua")
Script.Load("lua/DamageMixin.lua")
Script.Load("lua/EffectsMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/PointGiverMixin.lua")
Script.Load("lua/LOSMixin.lua")
Script.Load("lua/Mixins/ClientModelMixin.lua")

class 'Vortex' (Entity)

-- Spores didn't stack in NS1 so consider that
Vortex.kMapName = "vortex"
Vortex.kModelName = PrecacheAsset("models/alien/fade/vortex.model")
Vortex.kRadius = kVortexRadius
local kDamageInterval = 0.1
local kVortexSpeed = 0.45
local kScalarForVortexPower = 4

local networkVars =
{
    initialTime = "time",
    movementDirection = "vector",
    impacted = "boolean",
}

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(LOSMixin, networkVars)

function Vortex:OnCreate()

    Entity.OnCreate(self)

    InitMixin(self, TeamMixin)
    InitMixin(self, DamageMixin)
    InitMixin(self, EffectsMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LOSMixin)
    InitMixin(self, PointGiverMixin)
    InitMixin(self, BaseModelMixin)

    local creationTime = Shared.GetTime()
    if Server then
        InitMixin(self, OwnerMixin)
        self.destroyTime = creationTime + kVortexLifetime + kVortexInitTime
        self.damageInterval = kDamageInterval
        self.endurance = kVortexMaxDamageEndurance
    end
    self.initialTime = creationTime + kVortexInitTime

    self:SetUpdates(true, kRealTimeUpdateRate)
    self:SetRelevancyDistance(kMaxRelevancyDistance)
    self:SetModel(Vortex.kModelName)

    self.movementDirection = nil
    self.impactedWall = false
    self.impactedEntity = false
end

function Vortex:OnInitialized()
    Entity.OnInitialized(self)
    local origin = self:GetOrigin()
    self:TriggerEffects("blink_out", {effecthostcoords = Coords.GetTranslation(origin + Vector(0,-.6,0))})
    for _,v in pairs(GetEntitiesWithinRange("Vortex",origin,Vortex.kRadius)) do
        if v ~= self then
            DestroyEntity(v)
        end
    end
end


function Vortex:OnDestroy()
    Entity.OnDestroy(self)
    self:TriggerEffects("blink_in", {effecthostcoords = Coords.GetTranslation(self:GetOrigin() + Vector(0,-.6,0))})
end

function Vortex:GetModelOrigin()
    return self:GetOrigin()
end

function Vortex:GetEngagementPoint()
    return self:GetOrigin() + Vector(0, 0.5, 0)
end

function Vortex:GetDeathIconIndex()
    return kDeathMessageIcon.Vortex
end

function Vortex:GetTechId()
    return kTechId.Vortex
end

function Vortex:GetShowHitIndicator()
    return false
end

local kStartScale = 0.2
local kFinalScale = 1
function Vortex:OnAdjustModelCoords(modelCoords)
    local now = Shared.GetTime()
    local initScalarLeft = math.max(self.initialTime - now,0)
    local scaleFraction =  1 - initScalarLeft / kVortexInitTime
    scaleFraction = scaleFraction * scaleFraction
    
    local scale = kStartScale + scaleFraction * (kFinalScale - kStartScale)
    modelCoords.xAxis = modelCoords.xAxis * scale
    modelCoords.yAxis = modelCoords.yAxis * scale
    modelCoords.zAxis = modelCoords.zAxis * scale
    return modelCoords
end

function Vortex:UpdateMovement()
    local direction = self.movementDirection
    local startPoint = self:GetOrigin()
    local endPoint = startPoint + direction * kVortexSpeed
    local traceCapsule = Shared.TraceCapsule(startPoint, endPoint, 0.2, 0.2, CollisionRep.Move, PhysicsMask.All, EntityFilterOne(self))
    if traceCapsule.fraction == 1 then
        self:SetOrigin(endPoint)
    else
        self.impactedBlock = true
    end
end

function Vortex:OnUpdate(_deltaTime)
    local time = Shared.GetTime()
    if time < self.initialTime then
        return
    end
    
    if Server then
        if time > self.destroyTime 
                or self.endurance <= 0
        then
            DestroyEntity(self)
            return
        end

        self:DestroyProjectiles(_deltaTime)
        if not self.impactedBlock and not self.impactedEntity then
            self:UpdateMovement()
        end
        -- self:DamageEntities(_deltaTime)
    end
    
    self:SuckInEnemies(_deltaTime)
end

function Vortex:SuckInEnemies(_deltaTime)
    local attackPoint = self:GetOrigin()
    local enemies = GetEntitiesForTeamWithinRange("Player", kTeam1Index, attackPoint, Vortex.kRadius)
    for _, entity in pairs(enemies) do
        local mass = entity.GetMass and entity:GetMass() or Player.kMass
        local distanceToTarget = nil
        if mass < 200 then
            local playerTargetPoint = nil
            if entity.GetExtents then
                playerTargetPoint = entity:GetOrigin() + Vector(0, 0.5 * entity:GetExtents().y, 0)
                local rayTrace = Shared.TraceRay(attackPoint, playerTargetPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
                if rayTrace.fraction ~= 1 then
                    if rayTrace.entity then
                        if rayTrace.entity == entity then
                            local reelOffset = attackPoint - playerTargetPoint
                            distanceToTarget = reelOffset:GetLength()
                            entity:SetVelocity(entity:GetVelocity() + kScalarForVortexPower * reelOffset:GetUnit() * Vortex.kRadius * kVortexSuckinVelocityPerSecond * _deltaTime)
                            goto continue_to_next_entity
                        end
                    end
                end
            end
            if entity.GetEyePos then
                playerTargetPoint = entity:GetEyePos()
                local rayTrace = Shared.TraceRay(attackPoint, playerTargetPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
                if rayTrace.fraction ~= 1 then
                    if rayTrace.entity then
                        if rayTrace.entity == entity then
                            local reelOffset = attackPoint - playerTargetPoint
                            distanceToTarget = reelOffset:GetLength()
                            entity:SetVelocity(entity:GetVelocity() + kScalarForVortexPower * reelOffset:GetUnit() * Vortex.kRadius * kVortexSuckinVelocityPerSecond * _deltaTime)
                            goto continue_to_next_entity
                        end
                    end
                end
            end
            if entity.GetOrigin then
                playerTargetPoint = entity:GetOrigin()
                local rayTrace = Shared.TraceRay(attackPoint, playerTargetPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
                if rayTrace.fraction ~= 1 then
                    if rayTrace.entity then
                        if rayTrace.entity == entity then
                            local reelOffset = attackPoint - playerTargetPoint
                            distanceToTarget = reelOffset:GetLength()
                            entity:SetVelocity(entity:GetVelocity() + kScalarForVortexPower * reelOffset:GetUnit() * Vortex.kRadius * kVortexSuckinVelocityPerSecond * _deltaTime)
                            goto continue_to_next_entity
                        end
                    end
                end
            end
            ::continue_to_next_entity::
        end
        if distanceToTarget then
            if distanceToTarget < 1 then
                self.impactedEntity = true
            end
        end
    end
end

-- function Vortex:DamageEntities(_deltaTime)
--     --This code has been modified to require one of three ray-traces per entity to hit in order for the entity to be damaged. This stops the Vortex from damaging entities when there is a physical block between the Vortex and the entity
--     self.damageInterval = self.damageInterval + _deltaTime
--     if self.damageInterval < kDamageInterval then
--         return
--     end
--     self.damageInterval = 0
--     local attackPoint = self:GetOrigin()
--     local otherTeam = GetEnemyTeamNumber(self:GetTeamNumber())
--     local enemies = GetEntitiesWithMixinForTeamWithinRange("Live",otherTeam, attackPoint, Vortex.kRadius)
--     for index, entity in ipairs(enemies) do
--         local receiverPoint = nil
--         local rayTrace = nil
--         local damage = nil
--         if entity.GetEyePos then
--             receiverPoint = entity:GetEyePos()
--             rayTrace = Shared.TraceRay(attackPoint, receiverPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
--             if rayTrace.fraction ~= 1 then
--                 if rayTrace.entity then
--                     if rayTrace.entity == entity then
--                         damage = kVortexStructureDamagePerSecond
--                         if entity:isa("Player") then
--                             receiverPoint = entity:GetEyePos()
--                             damage = kVortexPlayerDamagePerSecond
--                             self.endurance = self.endurance - kVortexPerPlayerDamageEnduranceCostPerSecond * kDamageInterval
--                         end
--                         self:DoDamage(damage * kDamageInterval, entity, receiverPoint, (receiverPoint - attackPoint):GetUnit())
--                         goto end_of_the_code
--                     end
--                 end
--             end
--         end
--         if entity.GetOrigin and entity.GetExtents then
--             receiverPoint = entity:GetOrigin() + 0.5 * Vector(0, entity:GetExtents().y, 0)
--             rayTrace = Shared.TraceRay(attackPoint, receiverPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
--             if rayTrace.fraction ~= 1 then
--                 if rayTrace.entity then
--                     if rayTrace.entity == entity then
--                         damage = kVortexStructureDamagePerSecond
--                         if entity:isa("Player") then
--                             receiverPoint = entity:GetEyePos()
--                             damage = kVortexPlayerDamagePerSecond
--                             self.endurance = self.endurance - kVortexPerPlayerDamageEnduranceCostPerSecond * kDamageInterval
--                         end
--                         self:DoDamage(damage * kDamageInterval, entity, receiverPoint, (receiverPoint - attackPoint):GetUnit())
--                         goto end_of_the_code
--                     end
--                 end
--             end
--         end
--         if entity.GetOrigin then
--             receiverPoint = entity:GetOrigin()
--             rayTrace = Shared.TraceRay(attackPoint, receiverPoint, CollisionRep.Damage, PhysicsMask.Bullets, EntityFilterOne(self))
--             if rayTrace.fraction ~= 1 then
--                 if rayTrace.entity then
--                     if rayTrace.entity == entity then
--                         damage = kVortexStructureDamagePerSecond
--                         if entity:isa("Player") then
--                             receiverPoint = entity:GetEyePos()
--                             damage = kVortexPlayerDamagePerSecond
--                             self.endurance = self.endurance - kVortexPerPlayerDamageEnduranceCostPerSecond * kDamageInterval
--                         end
--                         self:DoDamage(damage * kDamageInterval, entity, receiverPoint, (receiverPoint - attackPoint):GetUnit())
--                         goto end_of_the_code
--                     end
--                 end
--             end
--         end
--         ::end_of_the_code::
--     end
-- end
-- This code has been commented out to stop the Vortex from being able to damage marine entities while being balanced by Alien players not getting stuck by the Vortex

if Server then
    function Vortex:DestroyProjectiles(_deltaTime)

        local checkAtPoint = self:GetOrigin()
        local projectiles = GetEntitiesWithinRange("PredictedProjectile", checkAtPoint, Vortex.kRadius)
        table.copy(GetEntitiesWithinRange("CragUmbra", checkAtPoint, CragUmbra.kRadius),projectiles,true)
        table.copy(GetEntitiesWithinRange("SporeCloud", checkAtPoint, kSporesDustCloudRadius), projectiles, true)

        for j = 1, #projectiles do
            local projectile = projectiles[j]
            DestroyEntity(projectile)
            self:TriggerEffects("blink_out", {effecthostcoords = Coords.GetTranslation(projectile:GetOrigin() + Vector(0,-.6,0))})
            --self.endurance = self.endurance - kVortexProjectileEnduranceCost
        end

    end

    function Vortex:OnKill()
        --self:TriggerEffects("burn_spore", { effecthostcoords = Coords.GetTranslation(self:GetOrigin()) } )
    end

    function Vortex:GetDestroyOnKill()
        return true
    end

    function Vortex:GetSendDeathMessageOverride()
        return false
    end
end

Shared.LinkClassToMap("Vortex", Vortex.kMapName, networkVars)
