Exo.kBountyThreshold = kBountyClaimMinExo
Exo.kMaxProtectionDamageReduction = 0

if Server then

    local kDeploy2DSound = PrecacheAsset("sound/NS2.fev/marine/heavy/deploy_2D")
    local kBoostKnockbackCheckRadius = 2.2
    local kBoostKnockbackExtents = Vector(1.1, 1.0, 1.25)
    local kBoostKnockbackCooldown = 0.6
    local kBoostKnockbackSpeed = 8

    local function GetBoostKnockbackDirection(self)
        local velocity = self:GetVelocity()
        local direction = Vector(velocity.x, 0, velocity.z)

        if direction:GetLengthSquared() < 0.01 then
            local viewDirection = self:GetViewCoords().zAxis
            direction = Vector(viewDirection.x, 0, viewDirection.z)
        end

        direction:Normalize()
        return direction
    end

    local function CanBoostKnockbackTarget(target)
        if not target or not target:GetIsAlive() then
            return false
        end

        return target:isa("Marine") or target:isa("JetpackMarine")
    end

    local function BoostKnockbackNearbyMarines(self)
        if not self.thrustersActive or self.thrusterMode == kExoThrusterMode.Vertical then
            return
        end

        local direction = GetBoostKnockbackDirection(self)
        local hitOrigin = self:GetOrigin() + Vector(0, 0.8, 0) + direction * kBoostKnockbackExtents.z
        local hitboxCoords = Coords.GetLookIn(hitOrigin, direction, Vector(0, 1, 0))
        local invHitboxCoords = hitboxCoords:GetInverse()
        local marines = GetEntitiesForTeamWithinRange("Player", self:GetTeamNumber(), hitOrigin, kBoostKnockbackCheckRadius)
        local now = Shared.GetTime()

        for i = 1, #marines do
            local marine = marines[i]
            if marine ~= self and CanBoostKnockbackTarget(marine) and (not marine.nextExoBoostKnockback or now >= marine.nextExoBoostKnockback) then
                local localSpacePosition = invHitboxCoords:TransformPoint(marine:GetEngagementPoint())
                local extents = marine:GetExtents()

                if math.abs(localSpacePosition.x) <= kBoostKnockbackExtents.x + extents.x
                        and math.abs(localSpacePosition.y) <= kBoostKnockbackExtents.y + extents.y
                        and math.abs(localSpacePosition.z) <= kBoostKnockbackExtents.z + extents.z then
                    marine.nextExoBoostKnockback = now + kBoostKnockbackCooldown
                    ApplyPushback(marine, 0.2, direction * kBoostKnockbackSpeed + Vector(0, 2.5, 0))
                end
            end
        end
    end

    local baseModifyVelocity = Exo.ModifyVelocity
    function Exo:ModifyVelocity(input, velocity, deltaTime)
        baseModifyVelocity(self, input, velocity, deltaTime)
        BoostKnockbackNearbyMarines(self)
    end

    function Exo:GetCanVampirismBeUsedOn()
        return true
    end

    function Exo:InitWeapons()

        Player.InitWeapons(self)

        local weaponHolder = self:GetWeapon(ExoWeaponHolder.kMapName)

        if not weaponHolder then
            weaponHolder = self:GiveItem(ExoWeaponHolder.kMapName, false)
        end

        if self.layout == "MinigunMinigun" then
            weaponHolder:SetWeapons(Minigun.kMapName, Minigun.kMapName)
        elseif self.layout == "RailgunRailgun" then
            weaponHolder:SetWeapons(Railgun.kMapName, Railgun.kMapName)
        --elseif self.layout == "ClawRailgun" then
        --    weaponHolder:SetWeapons(Claw.kMapName, Railgun.kMapName)
        --elseif self.layout == "ClawMinigun" then
        --    weaponHolder:SetWeapons(Claw.kMapName, Minigun.kMapName)
        else
            Log("Warning: incorrect layout set for exosuit")
            weaponHolder:SetWeapons(Minigun.kMapName, Minigun.kMapName)
        end

        weaponHolder:TriggerEffects("exo_login")
        self.inventoryWeight = weaponHolder:GetInventoryWeight(self)
        self:SetActiveWeapon(ExoWeaponHolder.kMapName)
        StartSoundEffectForPlayer(kDeploy2DSound, self)

    end

    function Exo:GetAutoWeldArmorPerSecond(nanoArmorResearched)
        return nanoArmorResearched and kExoNanoArmorPerSecond or kExoArmorPerSecond
    end
end

function Exo:GetExoVariantOverride(variant)
    if GetHasTech(self,kTechId.MilitaryProtocol) then
        return kExoVariants.chroma
    end
    return variant
end


function Exo:GetArmorAmount(armorLevels)

    if not armorLevels then

        armorLevels = 0

        if GetHasTech(self, kTechId.Armor3, true) then
            armorLevels = 3
        elseif GetHasTech(self, kTechId.Armor2, true) then
            armorLevels = 2
        elseif GetHasTech(self, kTechId.Armor1, true) then
            armorLevels = 1
        end

    end

    local hasMP = GetHasTech(self,kTechId.MilitaryProtocol)
    return hasMP and (kExosuitMPArmor + armorLevels * kExosuitMPArmorPerUpgradeLevel  ) 
                 or (kExosuitArmor + armorLevels *kExosuitArmorPerUpgradeLevel)

end


function Exo:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint) -- dud
    local reduction = kExoDamageReduction[doer:GetClassName()]
    if reduction then
        damageTable.damage = damageTable.damage * reduction
        return
    end
end
