Armory.kWeldAmount = 10
Armory.kHealAmount = 25

local oldArmoryGetItemList = Armory.GetItemList
function Armory:GetItemList(forPlayer)
    local itemList = oldArmoryGetItemList(self, forPlayer)
    table.insert(itemList, kTechId.Knife)
    table.insert(itemList, kTechId.Revolver)
    table.insert(itemList, kTechId.SubMachineGun)
    --table.insert(itemList, kTechId.LightMachineGun)
    table.insert(itemList, kTechId.LightMachineGunAcquire)
    table.insert(itemList, kTechId.Cannon)
    table.insert(itemList, kTechId.CombatBuilder)
	return itemList
end

local oldAdvancedArmoryGetItemList = AdvancedArmory.GetItemList
function AdvancedArmory:GetItemList(forPlayer)
    local itemList = oldAdvancedArmoryGetItemList(self, forPlayer)
	if self:GetTechId() == kTechId.AdvancedArmory then
        table.insert(itemList, kTechId.Knife)
        table.insert(itemList, kTechId.Revolver)
        table.insert(itemList, kTechId.SubMachineGun)
        --table.insert(itemList, kTechId.LightMachineGun)
        table.insert(itemList, kTechId.LightMachineGunAcquire)
        table.insert(itemList, kTechId.Cannon)
        table.insert(itemList, kTechId.CombatBuilder)
    end
	return itemList
end

function Armory:GetTechButtons(techId)

    local techButtons = 
    {
        kTechId.ShotgunTech , kTechId.None , kTechId.None , kTechId.None,
        kTechId.GrenadeTech , kTechId.MinesTech , kTechId.CombatBuilderTech , kTechId.None 
    }
    
    -- Show button to upgraded to advanced armory
    local advancedArmory = self:GetTechId() == kTechId.AdvancedArmory
    if not advancedArmory then
        techButtons[4] = kTechId.AdvancedArmoryUpgrade
    end
    
    return techButtons

end

function Armory:GetTechAllowed(techId, techNode, player)

    local allowed, canAfford = ScriptActor.GetTechAllowed(self, techId, techNode, player)

    if techId == kTechId.HeavyRifleTech then
        allowed = allowed and self:GetTechId() == kTechId.AdvancedArmory
    end

    return allowed, canAfford

end


--local baseGetCanBeUsed = Armory.GetCanBeUsed
--function Armory:GetCanBeUsed(player, useSuccessTable)
--
--    baseGetCanBeUsed(self,player,useSuccessTable)
--    if GetHasTech(self,kTechId.MilitaryProtocol) then
--        useSuccessTable.useSuccess = false
--    end
--    
--end

if Server then


    function Armory:GetShouldResupplyPlayer(player)

        if not player:GetIsAlive() then
            return false
        end

        local stunned = HasMixin(player, "Stun") and player:GetIsStunned()

        if stunned then
            return false
        end

        local inNeed = false

        -- Don't resupply when already full
        if (player:GetHealthScalar() < 1) then
            inNeed = true
        else

            -- Do any weapons need ammo?
            for i = 1, player:GetNumChildren() do
                local child = player:GetChildAtIndex(i - 1)
                if child:isa("ClipWeapon") and child:GetNeedsAmmo(false) then
                    inNeed = true
                    break
                end
            end

        end

        if inNeed then

            -- Check player facing so players can't fight while getting benefits of armory
            local viewVec = player:GetViewAngles():GetCoords().zAxis

            local toArmoryVec = self:GetOrigin() - player:GetOrigin()

            if(GetNormalizedVector(viewVec):DotProduct(GetNormalizedVector(toArmoryVec)) > .75) then

                if self:GetTimeToResupplyPlayer(player) then

                    return true

                end

            end

        end

        return false

    end

    -- CE marines get a free Combat Builder from an Armory/AdvancedArmory's resupply pulse - the
    -- normal facing-the-armory check the health/ammo resupply already uses, just without requiring
    -- the player to actually NEED health or ammo (a marine who dropped their builder but is otherwise
    -- topped up must still be able to walk up and get one back). NOT granted while Mines occupy slot
    -- 4 (same slot as the builder) - the user must use up or drop the Mines first. This is CE-only:
    -- standard/MP Marines still buy the Combat Builder from the Armory menu at its normal cost, even
    -- with CombatBuilderTech researched - that legacy path is untouched.
    local function GetArmoryShouldResupplyCombatBuilder(self, player)

        if not player:GetIsAlive() or not player:isa("Marine") or player:isa("MarineCommander") then
            return false
        end

        if not GetCombatEngineersActive(player) then
            return false
        end

        if player:GetWeapon(CombatBuilder.kMapName) then
            return false
        end

        local slotFourWeapon = player:GetWeaponInHUDSlot(4)
        if slotFourWeapon and not slotFourWeapon:isa("CombatBuilder") then
            return false
        end

        local viewVec = player:GetViewAngles():GetCoords().zAxis
        local toArmoryVec = self:GetOrigin() - player:GetOrigin()

        return GetNormalizedVector(viewVec):DotProduct(GetNormalizedVector(toArmoryVec)) > .75
    end

    local baseArmoryGetShouldResupplyPlayer = Armory.GetShouldResupplyPlayer
    function Armory:GetShouldResupplyPlayer(player)

        if baseArmoryGetShouldResupplyPlayer(self, player) then
            return true
        end

        return GetArmoryShouldResupplyCombatBuilder(self, player)
    end

    function Armory:ResupplyPlayer(player)

        local resuppliedPlayer = false

        -- Heal player first
        if (player:GetHealthScalar() < 1) then

            -- third param true = ignore armor
            if player:GetHealthFraction() < 1 then
                player:AddHealth(self.kHealAmount, false, true)
            else
                player:AddArmor(self.kWeldAmount, false, true)
            end
            self:TriggerEffects("armory_health", {effecthostcoords = Coords.GetTranslation(player:GetOrigin())})

            resuppliedPlayer = true
            --[[
            if HasMixin(player, "ParasiteAble") and player:GetIsParasited() then
            
                player:RemoveParasite()
                
            end
            --]]

            if player:isa("Marine") and player.poisoned then

                player.poisoned = false

            end

        end

        -- Give ammo to all their weapons, one clip at a time, starting from primary
        local weapons = player:GetHUDOrderedWeaponList()

        for _, weapon in ipairs(weapons) do

            if weapon:isa("ClipWeapon") then

                if weapon:GiveAmmo(1, false) then

                    self:TriggerEffects("armory_ammo", {effecthostcoords = Coords.GetTranslation(player:GetOrigin())})

                    resuppliedPlayer = true

                    break

                end

            end

        end

        -- CE marines missing a Combat Builder (dropped it, or otherwise never got one) get one free
        -- here - see GetArmoryShouldResupplyCombatBuilder above for the full eligibility check
        -- (CE active, no builder held, no Mines in slot 4). Clearing ceBuilderDropped lets
        -- Marine:GiveCombatEngineerBuilder resume auto-reissuing it from here on, exactly as if it
        -- had never been dropped.
        if GetArmoryShouldResupplyCombatBuilder(self, player) then

            player:GiveItem(CombatBuilder.kMapName)
            player.ceBuilderDropped = false
            resuppliedPlayer = true

        end

        if resuppliedPlayer then

            -- Insert/update entry in table
            self.resuppliedPlayers[player:GetId()] = Shared.GetTime()

            -- Play effect
            --self:PlayArmoryScan(player:GetId())

        end

    end
end