Script.Load("lua/Weapons/Alien/Ability.lua")
Script.Load("lua/Weapons/Alien/StompMixin.lua")

class 'Devour' (Ability)

Devour.kMapName = "devour"

local kAnimationGraph = PrecacheAsset("models/alien/onos/onos_view.animation_graph")

Devour.kAttackAnimationLength = 0.9 -- short cooldown

-- Why a long cooldown? One Onos versus two Marines results in
-- one marine being devoured for a while and the cooldown will elapse
-- before the marine is released but the check stops a second marine
-- from being devoured while the first marine is still being devoured?
Devour.kEatCoolDown = 1.0           -- cooldown after marine is released or dies
local kMinDevourHoldTime = 1.0      -- minimum time Onos must hold devour before manual release
Devour.kInitialDamage = 50 --40
Devour.damage = 5 --33 --40 per second
Devour.energyRate = 0 --kEnergyUpdateRate * 14

local kAttackRadius = 0.8
local kAttackOriginDistance = 1.7
local kAttackRange = 2 --1.7
local kDevourUpdateRate = 0.183 --0.15

local kDevourMarineManualReleaseSpeed = 4

local networkVars =
{
    attackButtonPressed = "boolean",
    eatingPlayerId = "entityid",
    devouringScalar = "float (0 to 1 by .01)",
    timeDevourEnd = "time",
}

AddMixinNetworkVars(StompMixin, networkVars)

local function UpdateDevour(self)

    local onos = self:GetParent()
    
    if onos and (not onos:isa("Onos") or not onos:GetIsAlive()) then
    
        self:ClearPlayer(true)
        return false
   
    else
        if self.eatingPlayerId ~= 0 then
            local player = Shared.GetEntity(self.eatingPlayerId)            
            if player then
                local timeNow = Shared.GetTime()
                local coords = onos:GetCoords()
                player:SetCoords(coords)                
		
				if player:GetIsAlive() and player:isa("Marine") then
                    self.lastDevourTime = self.lastDevourTime or timeNow
                    local deltaTime = timeNow - self.lastDevourTime
                    local damage = Devour.damage * deltaTime
                    onos:AddEnergy(Devour.energyRate * deltaTime)

                    player:DeductHealth(damage, onos, self , true)

                    -- devouringScalar drives the "goop eaten" visual on the devoured player.
                    self.devouringScalar = 1 - player:GetHealthFraction()
                    player.devouringScalar = self.devouringScalar  

                    self.lastDevourTime = timeNow
                else
                    self.devouringScalar = 0
                    self.eatingPlayerId = 0
                    self.lastDevourTime = nil
                    self.timeDevourEnd = Shared.GetTime() + Devour.kEatCoolDown
                end

            else
                self.devouringScalar = 0
                self.eatingPlayerId = 0
                self.lastDevourTime = nil
                self.timeDevourEnd = Shared.GetTime() + Devour.kEatCoolDown
            end
        end 
    end   

    return true
    
end

function Devour:OnCreate()

    Ability.OnCreate(self)
    
    self.devouringScalar = 0
    self.eatingPlayerId = 0
    self.timeDevourEnd = 0
    self.timeDevourStart = 0
    self.hasAttackedSinceLastPress = false
    
	InitMixin(self, StompMixin)

    --[[if Server then
        self:AddTimedCallback(UpdateDevour, kDevourUpdateRate)
    end--]]
    
end

function Devour:OnDestroy()
    self:ClearPlayer(true)
end

local function ClearPlayerNow(player)

	if player.Replace and player:GetIsAlive() then
		local oldHealth = player:GetHealth()
		local oldArmor = player:GetArmor()
        local playerHadWelder = player.hasWelder == true
        local onos = Shared.GetEntity(player:GetDevouringOnosId())
        local onosAlive = onos and onos:GetIsAlive() or false
        if onos and onosAlive then
            local onosViewDirection = onos:GetViewCoords().zAxis
            local endPoint = onos:GetEyePos() + onosViewDirection * 1.7
            -- The extents of the Marine are Vector(0.4, 1.7, 0.4)
            local isBlockingWallTraceCapsule = Shared.TraceCapsule(onos:GetEyePos(), endPoint, 0.2, 1.7, CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterAll())
            if isBlockingWallTraceCapsule.fraction == 1 then
                local isEnoughSpaceTraceCapsule = Shared.TraceCapsule(endPoint, endPoint, 0.2, 1.7, CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterAll())
                if isEnoughSpaceTraceCapsule.fraction == 1 then
                    player:SetOrigin(endPoint)
                    local newPlayer = player:Replace(player.previousMapName, player:GetTeamNumber(), false, endPoint)
                    newPlayer:DevourEscape()
                    newPlayer:SetHealth(oldHealth)
                    newPlayer:SetArmor(oldArmor)
                    newPlayer:DisableGroundMove(0.15)
                    newPlayer:SetVelocity(onos:GetVelocity() + onosViewDirection * kDevourMarineManualReleaseSpeed)

                    local oldWeapon1 = newPlayer:GetWeaponInHUDSlot(1)
                    if oldWeapon1 then
                        newPlayer:RemoveWeapon(oldWeapon1)
                        DestroyEntity(oldWeapon1)
                    end

                    local oldWeapon2 = newPlayer:GetWeaponInHUDSlot(2)
                    if oldWeapon2 then
                        newPlayer:SetActiveWeapon(oldWeapon2:GetMapName())
                    end

                    newPlayer:TriggerEffects("combat_devour_escape", {effecthostcoords = newPlayer:GetCoords()})
                    newPlayer:SetCorroded()

                    -- Clear Devour weapon state by looking it up through the Onos
                    local devourWeapon = onos:GetWeapon(Devour.kMapName)
                    if devourWeapon then
                        devourWeapon:TriggerEffects("combat_stop_effects")
                        devourWeapon.devouringScalar = 0
                        devourWeapon.eatingPlayerId = 0
                        devourWeapon.lastDevourTime = nil
                        devourWeapon.timeDevourEnd = Shared.GetTime() + Devour.kEatCoolDown
                    end
                end
            end
        elseif (onos and not onosAlive) or (not onos) then
            -- Onos died or evolved (entity gone) — release player at current position
            local newvelocity = player:GetVelocity()
            local playerExtents = player:GetExtents()
            local releaseOrigin = player:GetOrigin()
            if onos then
                local trace = Shared.TraceCapsule(player:GetOrigin(),
                    player:GetOrigin() + GetNormalizedVector(newvelocity),
                    math.max(playerExtents.x, playerExtents.z), playerExtents.y,
                    CollisionRep.Move, PhysicsMask.AllButPCs, EntityFilterAll())
                releaseOrigin = trace.endPoint
            end
            local newPlayer = player:Replace(player.previousMapName, player:GetTeamNumber(), false, releaseOrigin)
            newPlayer:DevourEscape()
            newPlayer:SetHealth(oldHealth)
            newPlayer:SetArmor(oldArmor)
            newPlayer:SetVelocity(newvelocity)
            newPlayer:DisableGroundMove(0.15)

            local oldWeapon1 = newPlayer:GetWeaponInHUDSlot(1)
            if oldWeapon1 then
                newPlayer:RemoveWeapon(oldWeapon1)
                DestroyEntity(oldWeapon1)
            end

            local oldWeapon2 = newPlayer:GetWeaponInHUDSlot(2)
            if oldWeapon2 then
                newPlayer:SetActiveWeapon(oldWeapon2:GetMapName())
            end

            newPlayer:TriggerEffects("combat_devour_escape", {effecthostcoords = newPlayer:GetCoords()})
            newPlayer:SetCorroded()
        end
	end
	return false

end

function Devour:ClearPlayer(isOnosDying)
    local onos = self:GetParent()
    local onosDied = isOnosDying or false
    if onos and self.eatingPlayerId ~= 0 then
        local devouredplayer = Shared.GetEntity(self.eatingPlayerId)
        if devouredplayer then
            if onosDied then
                local onosHorizontalFacing = GetNormalizedVectorXZ(onos:GetViewCoords().zAxis)
                devouredplayer:SetOrigin(onos:GetOrigin() + Vector(onosHorizontalFacing.x * 0.25, Onos.YExtents, onosHorizontalFacing.z * 0.25))
                local playerVelocity = Vector(0, 0, 0)
                if devouredplayer.SetIsOnosDying then
                    devouredplayer:SetIsOnosDying(true)
                end
                if devouredplayer.SetDevouringOnosId then
                    devouredplayer:SetDevouringOnosId(0)
                end
                devouredplayer:SetVelocity(playerVelocity)
                self:TriggerEffects("combat_stop_effects")
                self.devouringScalar = 0
                self.eatingPlayerId = 0
                self.lastDevourTime = nil
            else
                if devouredplayer.SetIsOnosDying then
                    devouredplayer:SetIsOnosDying(false)
                end
            end
            devouredplayer:AddTimedCallback(ClearPlayerNow, 0.01)
        end
    end
end

function Devour:GetDeathIconIndex()
    return kDeathMessageIcon.Devour
end

function Devour:GetAnimationGraphName()
    return kAnimationGraph
end

function Devour:GetEnergyCost()
	return self:GetCanDevour() and kDevourEnergyCost or 200
end

function Devour:GetHUDSlot()
    return 3
end

function Devour:OnHolster(player)

    Ability.OnHolster(self, player)    
    self:OnAttackEnd()
    
end

function Devour:GetMeleeBase()
    return 0.5,0.7
end

function Devour:GetDevourScalar()
    return self.devouringScalar
end


function Devour:Attack(player)

    local didHit = false
    local impactPoint = nil
    local target = nil
    
    if self.eatingPlayerId == 0 then     
        --Devour Attack
        didHit, target, impactPoint = AttackMeleeCapsule(self, player, Devour.kInitialDamage, kAttackRange, nil, false, EntityFilterOneAndIsa(player, "Babbler")) -- AttackMeleeCapsule(self, player, 0, kAttackRange)
        local energyCost = kDevourMissedEnergyCost
        
        self.timeDevourEnd = Shared.GetTime() + Devour.kAttackAnimationLength
        
        if target and HasMixin(target, "Live") and target:GetIsAlive() then            
            
            if target:isa("Player") and not target:isa("Exo") then
                if GetAreEnemies(self,target) then
                    self.eatingPlayerId = target:GetId()
                    self.timeDevourEnd = Shared.GetTime() + Devour.kEatCoolDown
                    energyCost = kDevourEnergyCost
                    
                    if Server then
                        self.timeDevourStart = Shared.GetTime()
                        self:DevourPlayer(target)                  
                        self:AddTimedCallback(UpdateDevour, kDevourUpdateRate)
                    end
                end
            end
        end
        player:DeductAbilityEnergy(energyCost)        
        
    end
    
end

function Devour:OnTag(tagName)

	PROFILE("Devour:OnTag") 						
    local player = self:GetParent()    
    
    if self.attackButtonPressed and player:GetEnergy() >= self:GetEnergyCost() then    

        self:TriggerEffects("gore_attack")  
        self:Attack(player)        

    else
        self:OnAttackEnd()
    end
    
end

function Devour:OnPrimaryAttack(player)

    if self:GetCanDevour() then
        if player:GetEnergy() >= self:GetEnergyCost() then
            self.attackButtonPressed = true
        else
            self:OnAttackEnd()
        end
    else
        -- Already devouring: allow manual release after minimum hold time
        if Server and self.eatingPlayerId ~= 0 and Shared.GetTime() - self.timeDevourStart >= kMinDevourHoldTime then
            self:ClearPlayer(false)
        else
            self:OnAttackEnd()
        end
    end
    
end

function Devour:GetCanDevour()
    return self.eatingPlayerId == 0 and ( Shared.GetTime() >= self.timeDevourEnd )
end

function Devour:OnPrimaryAttackEnd(player)
    
    Ability.OnPrimaryAttackEnd(self, player)
    self:OnAttackEnd()
    
end

function Devour:OnAttackEnd()
    self.attackButtonPressed = false    
end

function Devour:OnUpdateAnimationInput(modelMixin)

    local activityString = "none"
    local abilityString = "boneshield"
    
    if self.timeDevourEnd > Shared.GetTime() then
        activityString = "primary"
    elseif self.attackButtonPressed then
        activityString = "primary" --"taunt"        
        abilityString = "gore"
    end
    
    modelMixin:SetAnimationInput("ability", abilityString)
    modelMixin:SetAnimationInput("activity", activityString)
    
end

function Devour:DevourPlayer(targetPlayer)

	-- Look up and remember old values
    targetPlayer:DropAllWeapons()

    local devouredPlayer = targetPlayer:Replace(DevouredPlayer.kMapName , targetPlayer:GetTeamNumber(), false, Vector(targetPlayer:GetOrigin()))
    devouredPlayer:SetMaxHealth(targetPlayer:GetMaxHealth())
    devouredPlayer:SetHealth(targetPlayer:GetHealth())
    devouredPlayer:SetMaxArmor(targetPlayer:GetMaxArmor())
    devouredPlayer:SetArmor(targetPlayer:GetArmor())

    devouredPlayer.previousMapName = targetPlayer:GetMapName()
	local onos = self:GetParent()
	local onosId = onos:GetId()
	devouredPlayer:SetDevouringOnosId(onosId)
	
	self.eatingPlayerId = devouredPlayer:GetId()

    local devourCoords = targetPlayer:GetCoords()
    local vHeightOffset = Vector(0, Onos.YExtents, 0)
    devourCoords.origin = devourCoords.origin + vHeightOffset
	onos:TriggerEffects("combat_devour_eat", {effecthostcoords = devourCoords})
	
	-- Switch to the Gore weapon if successful.
	local owner = self:GetParent()
	if owner then
		owner:SwitchWeapon(1)
	end
   
end

Shared.LinkClassToMap("Devour", Devour.kMapName, networkVars)