Script.Load("lua/Weapons/Marine/ClipWeapon.lua")
Script.Load("lua/PickupableWeaponMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/EntityChangeMixin.lua")
Script.Load("lua/Weapons/ClientWeaponEffectsMixin.lua")
Script.Load("lua/PointGiverMixin.lua")

class 'CombatInjector' (ClipWeapon)

CombatInjector.kMapName = "combatinjector"
CombatInjector.kModelName = PrecacheAsset("models/marine/CombatInjector/CombatInjector_World.model")
local kViewModelName = PrecacheAsset("models/marine/CombatInjector/CombatInjector_View.model")
local kAnimationGraph = PrecacheAsset("models/marine/CombatInjector/CombatInjector_View.animation_graph")

local kBI9BulletSize = 0.15
local kRange = 250
local kSpread = Math.Radians(4.25)
local kMinSpread = Math.Radians(2.5)
local kAoeRadius = 4
local kButtRange = 1.1

local kDrawSound = PrecacheAsset("sound/combat_injector.fev/combat_injector/Draw")
local kInjectSound = PrecacheAsset("sound/combat_injector.fev/combat_injector/Inject")
-- local kAntidoteSound = PrecacheAsset("sound/combat_injector.fev/combat_injector/antidote")
-- local kRegenerationSound = PrecacheAsset("sound/combat_injector.fev/combat_injector/regeneration")
-- local kDefensePlusSound = PrecacheAsset("sound/combat_injector.fev/combat_injector/defense_plus")
-- local kCatPackSound = PrecacheAsset("sound/combat_injector.fev/combat_injector/cat_pack")

local networkVars =
{
    canPrimaryAttack = "boolean",
    injectorType = "string (32)"
}

AddMixinNetworkVars(LiveMixin, networkVars)

-- local kMuzzleEffect = PrecacheAsset("cinematics/marine/rifle/muzzle_flash.cinematic")
-- local kMuzzleAttachPoint = "Muzzle"

-- local function DestroyMuzzleEffect(self)

--     if self.muzzleCinematic then
--         Client.DestroyCinematic(self.muzzleCinematic)            
--     end
    
--     self.muzzleCinematic = nil
--     self.activeCinematicName = nil

-- end

-- local function CreateMuzzleEffect(self)

--     local player = self:GetParent()

--     if player then

--         local cinematicName = kMuzzleEffect
--         self.activeCinematicName = cinematicName
--         self.muzzleCinematic = CreateMuzzleCinematic(self, cinematicName, cinematicName, kMuzzleAttachPoint, nil, Cinematic.Repeat_Endless)
--         self.firstPersonLoaded = player:GetIsLocalPlayer() and player:GetIsFirstPerson()
    
--     end

-- end

function CombatInjector:OnCreate()
    ClipWeapon.OnCreate(self)
    InitMixin(self, PickupableWeaponMixin)
    InitMixin(self, EntityChangeMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, PointGiverMixin)
    if Client then
        InitMixin(self, ClientWeaponEffectsMixin)
    end
    self.canPrimaryAttack = true
    self.primaryAttacking = false
    self.deployed = false
    self.injectorType = "REGEN"
    self.used = false
    self.readyToDestroy = false
end

function CombatInjector:OnInitialized()
    ClipWeapon.OnInitialized(self)
end

function CombatInjector:OnPrimaryAttack()
    local player = self:GetParent()
    if self.clip > 0 and self.canPrimaryAttack then
        self.primaryAttacking = true
        self.canPrimaryAttack = false
        if Server then
            StartSoundEffectOnEntity(kInjectSound, player, 0.4)
        end
    end
end

function CombatInjector:OnTag(tagName)
    PROFILE("CombatInjector:OnTag")
    local player = self:GetParent()
    if tagName == "inject" then
        -- animation completed, enter Remove Combat Injector node
    elseif tagName == "delete_combat_injector" then
        if Server then
            local player = self:GetParent()
            if player then
                -- apply effects now that the animation has fully completed
                if self.injectorType == "REGEN" then
                    for i = 1, 20 do
                        player:AddTimedCallback(function(self)
                            if self:GetHealth() < self:GetMaxHealth() then
                                self:TriggerEffects("medpack_pickup", { effecthostcoords = self:GetCoords() })
                                self:SetHealth(math.min(self:GetHealth() + 5, self:GetMaxHealth()))
                            end
                        end, i)
                    end
                elseif self.injectorType == "ANTIDOTE" then
                    player.isSporesImmuneCombatInjector = true
                elseif self.injectorType == "CAT-PACK" then
                    player:ApplyCatPack()
                    player:TriggerEffects("catpack_pickup", { effecthostcoords = self:GetCoords() })
                    for i = 1, 1 do
                        player:AddTimedCallback(function(self)
                            self:ApplyCatPack()
                            self:TriggerEffects("catpack_pickup", { effecthostcoords = self:GetCoords() })
                        end, 5.2 * i)
                    end
                elseif self.injectorType == "DEFENSE+" then
                    player:ActivateNanoShield()
                    for i = 1, 2 do
                        player:AddTimedCallback(function(self)
                            self:ActivateNanoShield()
                        end, 3.2 * i)
                    end
                end
            end
        end
        self.readyToDestroy = true
    elseif tagName == "deploy_start" then
        self.canPrimaryAttack = false
        self.deployed = false
    elseif tagName == "deploy_end" then
        self.canPrimaryAttack = true
        self.deployed = true
    elseif tagName == "sprint_start" then
        self.canPrimaryAttack = false
    elseif tagName == "sprint_end" then
        self.canPrimaryAttack = true
    elseif tagName == "jump_start" then
        self.canPrimaryAttack = false
    elseif tagName == "jump_end" then
        self.canPrimaryAttack = true
    elseif tagName == "can_inject" then
        self.primaryAttacking = false
        self.canPrimaryAttack = true
    end
end

function CombatInjector:OnUpdateAnimationInput(modelMixin)
    PROFILE("CombatInjector:OnUpdateAnimationInput")
    local move = "idle"
    local activity = "draw"
    local player = self:GetParent()
    if player then
        if player:GetIsIdle() then
            modelMixin:SetAnimationInput("move", move)
        elseif not player:GetIsIdle() and not player:GetIsSprinting() and not player:GetIsJumping() then
            move = "run"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsSprinting() and not player:GetIsJumping() then
            move = "sprint"
            modelMixin:SetAnimationInput("move", move)
        elseif not player:GetIsSprinting() and player:GetIsJumping() then
            move = "jump"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsSprinting() and player:GetIsJumping() then
            move = "jump"
            modelMixin:SetAnimationInput("move", move)
        end
    end
    if not self.deployed then
        activity = "draw"
    elseif self.primaryAttacking and self.deployed then
        activity = "primary"
    else
        activity = "none"
    end
    modelMixin:SetAnimationInput("activity", activity)
end

function CombatInjector:GetAnimationGraphName()
    return kAnimationGraph
end

function CombatInjector:GetViewModelName()
    return kViewModelName
end

function CombatInjector:GetDeathIconIndex()
    return kDeathMessageIcon.CombatInjector
end

function CombatInjector:GetIsDroppable()
    return false
end

function CombatInjector:GetHUDSlot()
    return 4
end

function CombatInjector:GetPrimaryMinFireDelay()
end

function CombatInjector:OnDraw(player, previousWeaponMapName)

    ClipWeapon.OnDraw(self, player, previousWeaponMapName)

    self.deployed = false
    if Server then
        StartSoundEffectOnEntity(kDrawSound, self, 0.075)
    end
    
end

function CombatInjector:GetMaxClips()
    return 0
end

function CombatInjector:GetClipSize()
    return kCombatInjectorClipSize
end

function CombatInjector:GetWeight()
    return kCombatInjectorWeight
end

function CombatInjector:OnUpdateRender()

    local parent = self:GetParent()
    local settings = self:GetUIDisplaySettings()
    if parent and parent:GetIsLocalPlayer() and settings then

        local isActive = self:GetIsActive()
        local mapName = settings.textureNameOverride or self:GetMapName()
        local ammoDisplayUI = GetWeaponDisplayManager():GetWeaponDisplayScript(settings, mapName)
        self.ammoDisplayUI = ammoDisplayUI

        ammoDisplayUI:SetGlobal("injectorType", self.injectorType)

        if settings.variant and isActive then
            --[[
                Only update variant if we are the active weapon, since some
                of these GUIViews are re-used. For example, the Builder and Welder GUIViews are one
                and the same, which could cause (randomly, depending on the order of execution) the builder
                to override the variant of the welder due to this method being called for both weapons, and the
                builder's UpdateRender function being called _after_ the welder's.
            --]]
            ammoDisplayUI:SetGlobal("weaponVariant", settings.variant)
        end
        self.ammoDisplayUI:SetGlobal("globalTime", Shared.GetTime())
        -- For some reason I couldn't pass a bool here so... this is for modding anyways!
        -- If you pass anything that's not "true" it will disable the low ammo warning
        self.ammoDisplayUI:SetGlobal("lowAmmoWarning", tostring(Weapon.kLowAmmoWarningEnabled))
        
        -- Render this frame, if the weapon is active.  This is called every frame, so we're just
        -- saying "render one frame" every frame it's equipped.  Easier than keeping track of
        -- when the weapon is holstered vs equipped, and this call is super cheap.
        if isActive then
            self.ammoDisplayUI:SetRenderCondition(GUIView.RenderOnce)
        end
        
    end
    
end

function CombatInjector:GetHasSecondary(player)
    return true
end

function CombatInjector:OnSecondaryAttack()
    local parent = self:GetParent()
    if parent then
        if not parent:GetSecondaryAttackLastFrame() then
            -- if parent.weaponUpgradeLevel then
            --     local wepLvl = parent.weaponUpgradeLevel
            --     if wepLvl == 1 then
            --         if self.cartridgeType == "standard" then
            --             self.cartridgeType = "incendiary"
            --         elseif self.cartridgeType == "incendiary" then
            --             self.cartridgeType = "standard"
            --         end
            --     elseif wepLvl >= 2 then
            --         if self.cartridgeType == "standard" then
            --             self.cartridgeType = "incendiary"
            --         elseif self.cartridgeType == "incendiary" then
            --             self.cartridgeType = "slug"
            --         elseif self.cartridgeType == "slug" then
            --             self.cartridgeType = "standard"
            --         end
            --     end
            -- end
            if parent.weaponUpgradeLevel then
                if self.injectorType == "REGEN" then
                    -- StartSoundEffectOnEntity(kAntidoteSound, player, 0.35)
                    self.injectorType = "ANTIDOTE"
                elseif self.injectorType == "ANTIDOTE" then
                    -- StartSoundEffectOnEntity(kCatPackSound, player, 0.35)
                    self.injectorType = "CAT-PACK"
                elseif self.injectorType == "CAT-PACK" then
                    -- StartSoundEffectOnEntity(kDefensePlusSound, player, 0.35)
                    self.injectorType = "DEFENSE+"
                elseif self.injectorType == "DEFENSE+" then
                    -- StartSoundEffectOnEntity(kRegenerationSound, player, 0.35)
                    self.injectorType = "REGEN"
                end
            end
        end
    end
end

function CombatInjector:GetCatalystSpeedBase()
    if self:GetIsReloading() and kCombatVersion then
        local player = self:GetParent()
        if player then
            return player:GotFastReload() and 2.5 or 1.5
        end
    else
        return 1.5
    end
end

function CombatInjector:OnReload(player)
end


if Server then
    function CombatInjector:OnProcessMove(input)
        ClipWeapon.OnProcessMove(self, input)
        local player = self:GetParent()
        if player then
            local activeWeapon = player:GetActiveWeapon()
            local allowDestruction = self.readyToDestroy
            if allowDestruction then
                if activeWeapon == self then
                    player:QuickSwitchWeapon()
                end
                player.combatInjectorRespawn = nil
                player:RemoveWeapon(self)
                DestroyEntity(self)
            end
        end
    end
end

function CombatInjector:OverrideWeaponName()
    return "axe"
end

function CombatInjector:ApplyBulletGameplayEffects(player, target, endPoint, direction, damage, surface, showTracer)
end

function CombatInjector:GetPrimaryAttackRequiresPress()
    return true
end

function CombatInjector:OnUpdateAnimationInput(modelMixin)

    PROFILE("CombatInjector:OnUpdateAnimationInput")
    
    local move = "idle"
    local activity = "draw"

    local player = self:GetParent()
    if player then

        if player:GetIsIdle() then
            modelMixin:SetAnimationInput("move", move)
        elseif not player:GetIsIdle() and not player:GetIsSprinting() then
            move = "run"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsSprinting() then
            move = "sprint"
            modelMixin:SetAnimationInput("move", move)
        elseif player:GetIsJumping() then
            move = "jump"
            modelMixin:SetAnimationInput("move", move)
        end
    
    end

    if self.reloading then
        activity = "reload"
    elseif not self.deployed then
        activity = "draw"
    elseif self.primaryAttacking and self.deployed and self.clip > 0 then
        activity = "primary"
    else
        activity = "none"
    end

    modelMixin:SetAnimationInput("activity", activity)

end

if Client then
    
    function CombatInjector:GetUIDisplaySettings()
        return { xSize = 512, ySize = 80, script = "lua/Combat/GUICombatInjectorDisplay.lua"}
    end
    
end

function CombatInjector:ModifyDamageTaken(damageTable, attacker, doer, damageType)

    if damageType ~= kDamageType.Corrode then
        damageTable.damage = 0
    end
    
end

function CombatInjector:GetCanTakeDamageOverride()
    return self:GetParent() == nil
end

if Server then

    function CombatInjector:OnKill()
        DestroyEntity(self)
    end
    
    function CombatInjector:GetSendDeathMessageOverride()
        return false
    end 
    
end


Shared.LinkClassToMap("CombatInjector", CombatInjector.kMapName, networkVars)