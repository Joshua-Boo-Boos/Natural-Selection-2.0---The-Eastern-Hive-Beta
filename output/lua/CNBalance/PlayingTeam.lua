
local baseInitialized = PlayingTeam.Initialize
function PlayingTeam:Initialize(teamName, teamNumber)
    self.maxSupply = kStartSupply
    baseInitialized(self,teamName,teamNumber)
end

local baseOnInitialized = PlayingTeam.OnInitialized
function PlayingTeam:OnInitialized()
    self.maxSupply = kStartSupply
    self.floatingResourceIncome = 0
    baseOnInitialized(self)
end

function PlayingTeam:GetSupplyUsed()
    return Clamp(self.supplyUsed, 0, self:GetMaxSupply())
end

function PlayingTeam:GetMaxSupply()
    return self.maxSupply
end

function PlayingTeam:AddMaxSupply(supplyIncrease)
    self.maxSupply = self.maxSupply + supplyIncrease
end

function PlayingTeam:RemoveMaxSupply(supplyDecrease)
    self.maxSupply = self.maxSupply - supplyDecrease
end

function PlayingTeam:AddSupplyUsed(supplyUsed)
    self.supplyUsed = self.supplyUsed + supplyUsed
end

function PlayingTeam:RemoveSupplyUsed(supplyUsed)
    self.supplyUsed = self.supplyUsed - supplyUsed
end

local function UpdatePlayerChanges(self)
    local teamPlayers = math.max(0,self:GetNumPlayers() - kMatchMinPlayers)
    local ents = GetEntitiesWithMixinForTeam("BiomassHealth",self:GetTeamType())
    for i = 1, #ents do
        local ent = ents[i]
        if (ent.GetExtraHealth)  then
            ent:UpdateHealthAmount(teamPlayers,0)
        end
    end
end

local baseResetTeam = PlayingTeam.ResetTeam
function PlayingTeam:ResetTeam()
    local _ = baseResetTeam(self)
    UpdatePlayerChanges(self)
    return _
end

function PlayingTeam:AddPlayer(player)
    local available = Team.AddPlayer(self,player)
    UpdatePlayerChanges(self)
    return available
end

function PlayingTeam:RemovePlayer(player)
    Team.RemovePlayer(self,player)
    UpdatePlayerChanges(self)
end

function PlayingTeam:Update()

    PROFILE("PlayingTeam:Update")

    self:UpdateTechTree()

    self:UpdateVotes()
    

    local gameStarted = GetGamerules():GetGameStarted()
    local warmupActive = GetWarmupActive()
    if gameStarted or warmupActive then

        if gameStarted then
            self:UpdateResTick()
        else
            self:RespawnAllDeadPlayer()
        end

    end

    if gameStarted then
        self:UpdateDeadlock()
        self:UpdateBotEconomy()
    end
end

function PlayingTeam:OnTeamKill(techID, _fraction)
    self:OnDeadlockExtend(techID)
    local tResReward = kTechDataTeamResOnKill[techID]
    if tResReward then
        self:AddTeamResources(tResReward * _fraction,true)      --Treat this as income
    end
    return 0
end

function PlayingTeam:AddTeamResources(amount, isIncome)
    local teamResourceDelta = amount
    if amount > 0 then
        teamResourceDelta = teamResourceDelta + self.floatingResourceIncome
        self.floatingResourceIncome = teamResourceDelta % 1
        teamResourceDelta = teamResourceDelta - self.floatingResourceIncome
    end
        
    if teamResourceDelta > 0 and isIncome then
        self.totalTeamResourcesCollected = self.totalTeamResourcesCollected + teamResourceDelta
    end
    self:SetTeamResources(self.teamResources + teamResourceDelta)
end

local baseTriggerAlert = PlayingTeam.TriggerAlert
function PlayingTeam:TriggerAlert(techId, entity, force)

    if not GetGamerules():GetGameStarted() then return false end

    if self:ShouldHandleManualAlert() then 
        if entity.HandleManualAlert and entity:HandleManualAlert(techId) then
            return
        end
    end

    return baseTriggerAlert(self,techId,entity,force)
end

function PlayingTeam:ShouldHandleManualAlert()
    return true
end

function PlayingTeam:UpdateResTick()

    local time = Shared.GetTime()
    if not self.lastTimeCollectResources then
        self.lastTimeCollectResources = time
    end
    
    if self.lastTimeCollectResources + kResourceTowerResourceInterval < Shared.GetTime() then
        self.lastTimeCollectResources = time

        local rtActiveCount = 0
        local rts = GetEntitiesForTeam("ResourceTower", self:GetTeamNumber())
        for _, rt in ipairs(rts) do
            if rt:GetIsAlive() and rt:GetIsCollecting() then
                rtActiveCount = rtActiveCount + 1
            end
        end

        local finalResParam = rtActiveCount

        if NS2Gamerules.kBalanceConfig.resourceEfficiency then
            local rtAboveThreshold = math.max( rtActiveCount - kMaxEfficiencyTowers,0)
            local rtInsideThreshold = math.min(rtActiveCount,kMaxEfficiencyTowers)
            finalResParam = rtInsideThreshold * 1 + rtAboveThreshold * .5
        end

        if finalResParam <= 0 then
            finalResParam = kTeamResourceWithoutTower
        end

        local pResEachRT = kPlayerResEachTower - GetPlayersAboveLimit(self:GetTeamNumber()) * kPlayerResDeductionAboveLimit

        local pRes = finalResParam * pResEachRT
        local tRes = finalResParam * kTeamResourceEachTower
        self:CollectTeamResources(tRes, pRes,rtActiveCount)
    end
end

function PlayingTeam:CollectTeamResources(teamRes,playerRes)
    if teamRes > 0 then
        self:AddTeamResources(teamRes,true)
    end
    if playerRes > 0 then
        for _, player in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do
            if not player:isa("Commander") then
                player:AddResources(playerRes)
            end
        end
    end
end

local oldGetIsResearchRelevant = debug.getupvaluex(PlayingTeam.OnResearchComplete, "GetIsResearchRelevant")
local relevantResearchIds
local function extGetIsResearchRelevant(techId)

    if not relevantResearchIds then
        relevantResearchIds = {}

        --relevantResearchIds[kTechId.MilitaryProtocol] = 1
        --
        --relevantResearchIds[kTechId.StandardSupply] = 1
        --relevantResearchIds[kTechId.LightMachineGunUpgrade] = 1
        --relevantResearchIds[kTechId.DragonBreath] = 1
        --relevantResearchIds[kTechId.CannonTech] = 1

        --relevantResearchIds[kTechId.GrenadeLauncherUpgrade] = 2
        --relevantResearchIds[kTechId.ExplosiveSupply] = 1
        --relevantResearchIds[kTechId.GrenadeLauncherDetectionShot] = 2
        --relevantResearchIds[kTechId.GrenadeLauncherAllyBlast] = 2

        --relevantResearchIds[kTechId.ElectronicSupply] = 1
        --relevantResearchIds[kTechId.ElectronicStation] = 1
        --relevantResearchIds[kTechId.MACEMPBlast] = 1
        --relevantResearchIds[kTechId.PoweredExtractorTech] = 1
        --
        --relevantResearchIds[kTechId.ArmorSupply] = 1
        --relevantResearchIds[kTechId.MinesUpgrade] = 1
        --relevantResearchIds[kTechId.LifeSustain] = 1
        --relevantResearchIds[kTechId.ArmorRegen] = 1
        --relevantResearchIds[kTechId.CombatBuilderTech] = 1

        relevantResearchIds[kTechId.Devour] = 1
        relevantResearchIds[kTechId.XenocideFuel] = 1
        relevantResearchIds[kTechId.AcidSpray] = 1
        
        relevantResearchIds[kTechId.ShiftTunnel] = 1
        relevantResearchIds[kTechId.ShadeTunnel] = 1
        relevantResearchIds[kTechId.CragTunnel] = 1
    end

    local relevant = relevantResearchIds[techId]
    if relevant ~= nil then
        return relevant
    end

    return oldGetIsResearchRelevant(techId)
end

local kDeadlockDecayInterval = 15   -- seconds per decay tick
local kDeadlockPeriodMinutes = 5    -- minutes per escalating band
local kDeadlockMinScale = 0.50      -- floor: a structure never drops below 50% of its base max EHP
-- Per-15s-tick reduction for each consecutive 5-minute band. Constant +0.25% step,
-- so cumulative reduction reaches exactly 50% at T+20 (20 ticks/band):
--   20*(0.25 + 0.50 + 0.75 + 1.00)% = 50%.
local kDeadlockPeriodRates = { 0.0025, 0.005, 0.0075, 0.010 }

-- Absolute deadlock scale as a function of seconds elapsed since the deadlock
-- start time T. Returns the fraction of base max EHP a structure should have RIGHT
-- NOW. Being a pure function of elapsed time, it gives brand-new structures the
-- correct catch-up value: one placed at T+12 is scaled to exactly what it would be
-- had it existed since T.
local function ComputeDeadlockScale(elapsedSeconds)
    local ticks = math.floor(math.max(0, elapsedSeconds) / kDeadlockDecayInterval)
    local ticksPerBand = (kDeadlockPeriodMinutes * 60) / kDeadlockDecayInterval -- 20
    local reduction = 0
    for band = 1, #kDeadlockPeriodRates do
        local bandTicks = math.min(ticks - (band - 1) * ticksPerBand, ticksPerBand)
        if bandTicks <= 0 then break end
        reduction = reduction + bandTicks * kDeadlockPeriodRates[band]
    end
    return math.max(kDeadlockMinScale, 1 - reduction)
end

-- Force a single structure's max health/armor to (base * scale). The pre-deadlock
-- base maxima are captured ONCE (first time we touch the structure) so the scale is
-- always applied against the true originals instead of compounding each pass.
local function ApplyDeadlockScaleToStructure(target, scale)

    if not target.SetMaxHealth or not target.GetMaxHealth then return end
    if target.CanTakeDamage and not target:CanTakeDamage() then return end

    if not target.deadlockBaseMaxHealth then
        target.deadlockBaseMaxHealth = target:GetMaxHealth()
        target.deadlockBaseMaxArmor = (target.GetMaxArmor and target:GetMaxArmor()) or 0
    end

    local newMaxHealth = math.max(1, math.floor(target.deadlockBaseMaxHealth * scale + 0.5))
    if target:GetMaxHealth() ~= newMaxHealth then
        target:SetMaxHealth(newMaxHealth)
        if target.GetHealth and target:GetHealth() > newMaxHealth then
            if target.SetHealth then target:SetHealth(newMaxHealth) else target.health = newMaxHealth end
        end
    end

    if target.SetMaxArmor and target.GetMaxArmor then
        local newMaxArmor = math.max(0, math.floor(target.deadlockBaseMaxArmor * scale + 0.5))
        if target:GetMaxArmor() ~= newMaxArmor then
            target:SetMaxArmor(newMaxArmor)
            if target.GetArmor and target:GetArmor() > newMaxArmor then
                if target.SetArmor then target:SetArmor(newMaxArmor) else target.armor = newMaxArmor end
            end
        end
    end

end

function PlayingTeam:OnGameStateChanged(_state)
    if _state == kGameState.Started then
        self.deadlockGameStartTime = Shared.GetTime()
        self.deadlockTime = Shared.GetTime() + (NS2Gamerules.kBalanceConfig.deadlockInitialTime or 99999)
        self.deadlockDamageInterval = self.deadlockTime + kDeadlockDecayInterval
        self.deadlockBroadcastInterval = 0
    end
end

function PlayingTeam:OnDeadlockExtend(techID)
    -- Deadlock extensions disabled in Beta: do nothing.
    return
end

function PlayingTeam:UpdateDeadlock()
    -- Master on/off switch (NS2.0Config.json -> deadlockEnabled)
    if NS2Gamerules and NS2Gamerules.kBalanceConfig
       and NS2Gamerules.kBalanceConfig.deadlockEnabled == false then
        return
    end

    local now = Shared.GetTime()
    if now > self.deadlockTime then
        -- Count human players on both teams (ignore bots, spectators, ready room)
        local humanPlayerCount = 0
        local gamerules = GetGamerules()
        if gamerules then
            local team1 = gamerules:GetTeam(kTeam1Index)
            local team2 = gamerules:GetTeam(kTeam2Index)
            
            if team1 then
                for _, player in ipairs(team1:GetPlayers()) do
                    if player and not player:GetIsVirtual() then
                        humanPlayerCount = humanPlayerCount + 1
                    end
                end
            end
            
            if team2 then
                for _, player in ipairs(team2:GetPlayers()) do
                    if player and not player:GetIsVirtual() then
                        humanPlayerCount = humanPlayerCount + 1
                    end
                end
            end
        end
        
        -- Optionally require a minimum number of human players for deadlock damage
        local requireMinPlayers = true
        local minPlayers = 10
        if NS2Gamerules and NS2Gamerules.kBalanceConfig then
            if NS2Gamerules.kBalanceConfig.deadlockRequireMinPlayers ~= nil then
                requireMinPlayers = NS2Gamerules.kBalanceConfig.deadlockRequireMinPlayers
            end
            if NS2Gamerules.kBalanceConfig.deadlockMinPlayers ~= nil then
                minPlayers = NS2Gamerules.kBalanceConfig.deadlockMinPlayers
            end
        end
        if requireMinPlayers and humanPlayerCount < minPlayers then
            return
        end
        
        -- Escalating decay measured from the configured deadlock start time T
        -- (T = round start + deadlockInitialTime, NS2.0Config.json). The per-15s
        -- reduction steps up by a constant 0.25% every 5 minutes, reaching the 50%
        -- floor exactly at T+20 (see ComputeDeadlockScale / kDeadlockPeriodRates):
        --   [T,T+5) 0.25%   [T+5,T+10) 0.50%   [T+10,T+15) 0.75%   [T+15,T+20) 1.00%
        --
        -- We apply an ABSOLUTE scale (base max EHP * scale) to EVERY structure --
        -- both teams AND neutral ones (e.g. unsocketed power nodes) -- with no
        -- opt-outs, so chairs, RTs, power nodes and hives are all affected. Because
        -- the scale is a pure function of elapsed time, a structure placed mid-
        -- deadlock (say at T+12) is immediately set to the same max-EHP % it would
        -- have had if it had existed since T (catch-up).
        --
        -- ===================== OLD DEADLOCK STRUCTURE PASS (commented for reference / toggle) =====================
        -- The previous version iterated structures PER TEAM and skipped any with
        -- kIgnoreDeadlock (so chairs, RTs, power nodes and hives were NOT affected),
        -- and it reduced max EHP incrementally each 15s tick instead of to an
        -- absolute time-based target (so newly-placed structures started at full
        -- health with no catch-up). To restore it, comment out the new block below
        -- and uncomment this one.
        --
        -- local kMinScale = 0.50
        -- local kDeadlockPeriodRatesOld = { 0.0025, 0.005, 0.0075, 0.010 }
        -- local damageFraction = 0
        -- if now > self.deadlockDamageInterval then
        --     self.deadlockDamageInterval = now + kDeadlockDecayInterval
        --     local lastDeadlockTickTime = gamerules and gamerules._lastDeadlockTickTime or nil
        --     local shouldApplyDamage = not lastDeadlockTickTime or now >= lastDeadlockTickTime + kDeadlockDecayInterval
        --     if shouldApplyDamage then
        --         if gamerules then gamerules._lastDeadlockTickTime = now end
        --         local minutesSinceDeadlockStart = math.max(0, (now - self.deadlockTime) / 60)
        --         local deadlockPeriod = math.max(1, math.floor(minutesSinceDeadlockStart / kDeadlockPeriodMinutes) + 1)
        --         damageFraction = kDeadlockPeriodRatesOld[math.min(deadlockPeriod, #kDeadlockPeriodRatesOld)]
        --     end
        -- end
        -- if damageFraction > 0 then
        --     for teamNum = kTeam1Index, kTeam2Index do
        --         for _, target in ipairs(GetEntitiesWithMixinForTeam("Construct", teamNum)) do
        --             if not target.kIgnoreDeadlock and target.SetMaxHealth then
        --                 if not target.CanTakeDamage or target:CanTakeDamage() then
        --                     if not target.originalMaxHealth then
        --                         target.originalMaxHealth = target:GetMaxHealth()
        --                         target.originalMaxArmor = target:GetMaxArmor()
        --                         target.originalEHP = target.originalMaxHealth + target.originalMaxArmor * kHealthPointsPerArmor
        --                     end
        --                     local origEHP = target.originalEHP or (target:GetMaxHealth() + target:GetMaxArmor() * kHealthPointsPerArmor)
        --                     local currentMaxEHP = target:GetMaxHealth() + target:GetMaxArmor() * kHealthPointsPerArmor
        --                     local newMaxEHP = math.max(currentMaxEHP - origEHP * damageFraction, origEHP * kMinScale)
        --                     local scale = newMaxEHP / origEHP
        --                     local newMaxHealth = math.max(1, math.floor((target.originalMaxHealth or target:GetMaxHealth()) * scale + 0.5))
        --                     local newMaxArmor = math.max(0, math.floor((target.originalMaxArmor or target:GetMaxArmor()) * scale + 0.5))
        --                     target:SetMaxHealth(newMaxHealth)
        --                     target:SetMaxArmor(newMaxArmor)
        --                     if target.GetHealth and target:GetHealth() > newMaxHealth then
        --                         if target.SetHealth then target:SetHealth(newMaxHealth) else target.health = newMaxHealth end
        --                     end
        --                     if target.GetArmor and target:GetArmor() > newMaxArmor then
        --                         if target.SetArmor then target:SetArmor(newMaxArmor) else target.armor = newMaxArmor end
        --                     end
        --                 end
        --             end
        --         end
        --     end
        -- end
        -- =========================================================================================================

        -- Both teams call UpdateDeadlock; throttle the structure pass so it runs a
        -- couple of times a second globally (cheap, and catches new structures fast).
        local runStructurePass = (not gamerules) or (not gamerules._nextDeadlockScale) or (now >= gamerules._nextDeadlockScale)
        if runStructurePass then
            if gamerules then
                gamerules._nextDeadlockScale = now + 0.5
            end

            local scale = ComputeDeadlockScale(now - self.deadlockTime)
            for _, target in ipairs(GetEntitiesWithMixin("Construct")) do
                ApplyDeadlockScaleToStructure(target, scale)
            end
        end

        if now > self.deadlockBroadcastInterval then
            self.deadlockBroadcastInterval = now + 60
            SendTeamMessage(self, kTeamMessageTypes.DeadlockActivated)
            self:PlayPrivateTeamSound(self.kDeadlockAlert)
        end
    end
end

-- =====================================================================
-- Bot economy: force bots to actually SPEND their personal resources.
--
-- Problem: bots hoarded p-res toward the 100 cap instead of evolving
-- (aliens) or buying gear (marines), because the stock bot brains only
-- evolve/buy under very strict conditions (e.g. within 8m of a hive with
-- no threat within 25m) that are rarely met. This supplemental server-side
-- pass runs alongside the brains and makes bots spend spare res through the
-- SAME validated path players use (ProcessBuyAction), so any attempt that
-- isn't currently legal (wrong location, tech not researched, can't afford)
-- simply no-ops -- it can never create an invalid purchase.
-- =====================================================================

local kBotEconomyInterval = 4   -- seconds between economy passes (per team)
local kBotEvolveDangerRange = 18 -- don't evolve (become a vulnerable egg) with an enemy this close
local kBotResHoardCap = 75      -- if a bot reaches this much res it MUST spend, even if its role target is locked

-- Role-weighted alien lifeform targets (weights need not sum to anything).
-- Includes the custom Prowler & Vokex lifeforms so bots actually become them.
local kAlienLifeformWeights =
{
    { techId = kTechId.Gorge,   weight = 12 },
    { techId = kTechId.Prowler, weight = 16 },
    { techId = kTechId.Lerk,    weight = 20 },
    { techId = kTechId.Fade,    weight = 22 },
    { techId = kTechId.Vokex,   weight = 16 },
    { techId = kTechId.Onos,    weight = 14 },
}

-- Marine primary goals, a roughly-even split across the high-value purchases.
-- Welders are layered on top (see TryBuyMarineBot) so some welders are always
-- bought without starving the weapon/JP/exo purchases.
local kMarinePrimaryGoals =
{
    kTechId.Shotgun,
    kTechId.HeavyMachineGun,
    kTechId.GrenadeLauncher,
    kTechId.Jetpack,
    kTechId.DualMinigunExosuit,
}

local function GetIsLifeformEvolveAvailable(player, techId)
    local techTree = player.GetTechTree and player:GetTechTree()
    if not techTree then return false end
    local node = techTree:GetTechNode(techId)
    -- Same eligibility check the stock bot evolve action uses.
    return node ~= nil and node:GetAvailable(player, techId, false)
end

-- True only when it's reasonably safe to spend several seconds as an egg.
local function GetIsBotSafeToEvolve(player)
    if player.GetIsInCombat and player:GetIsInCombat() then return false end
    local enemyTeam = GetEnemyTeamNumber(player:GetTeamNumber())
    for _, enemy in ipairs(GetEntitiesForTeamWithinRange("Player", enemyTeam, player:GetOrigin(), kBotEvolveDangerRange)) do
        if enemy.GetIsAlive and enemy:GetIsAlive() then
            return false
        end
    end
    return true
end

-- Assign each bot a fixed role target once (weighted random), so the team gets
-- a varied composition rather than everyone funnelling into one lifeform.
local function GetBotLifeformTarget(player)
    if not player.botEcoLifeformTarget then
        local total = 0
        for i = 1, #kAlienLifeformWeights do
            total = total + kAlienLifeformWeights[i].weight
        end
        local roll = math.random() * total
        local acc = 0
        for i = 1, #kAlienLifeformWeights do
            acc = acc + kAlienLifeformWeights[i].weight
            if roll <= acc then
                player.botEcoLifeformTarget = kAlienLifeformWeights[i].techId
                break
            end
        end
        player.botEcoLifeformTarget = player.botEcoLifeformTarget or kTechId.Lerk
    end
    return player.botEcoLifeformTarget
end

-- Highest-cost lifeform the bot can currently afford AND evolve to (anti-hoard fallback).
local function GetBestAffordableLifeform(player, res)
    local bestId, bestCost = nil, -1
    for i = 1, #kAlienLifeformWeights do
        local id = kAlienLifeformWeights[i].techId
        local cost = GetCostForTech(id) or math.huge
        if cost <= res and cost > bestCost and GetIsLifeformEvolveAvailable(player, id) then
            bestId, bestCost = id, cost
        end
    end
    return bestId
end

local function TryEvolveAlienBot(player)
    -- Only base lifeforms get auto-evolved; already-evolved bots have spent.
    if not player.isa or not player:isa("Skulk") then return end
    if not player:GetIsAlive() then return end
    if player.GetIsAllowedToBuy and not player:GetIsAllowedToBuy() then return end
    if not GetIsBotSafeToEvolve(player) then return end

    local res = player.GetPersonalResources and player:GetPersonalResources()
    if not res or res <= 0 then return end

    local target = GetBotLifeformTarget(player)
    local targetCost = GetCostForTech(target) or math.huge

    -- 1) Role target is reachable & affordable -> evolve straight into it.
    if res >= targetCost and GetIsLifeformEvolveAvailable(player, target) then
        player:ProcessBuyAction({ target })
        return
    end

    -- 2) Anti-hoard: we have enough for the target but it's still locked (e.g. not
    --    enough biomass yet), or we're near the cap -> spend on the best lifeform
    --    available now instead of sitting on resources.
    if res >= targetCost or res >= kBotResHoardCap then
        local bestId = GetBestAffordableLifeform(player, res)
        if bestId then
            player:ProcessBuyAction({ bestId })
        end
    end
end

local function GetMarineAlreadyHasGoal(player, goal)
    if goal == kTechId.Jetpack then
        return player.isa and player:isa("JetpackMarine")
    end
    if goal == kTechId.DualMinigunExosuit or goal == kTechId.DualRailgunExosuit then
        return player.isa and player:isa("Exo")
    end
    -- Weapon goals: don't rebuy the primary weapon we already hold.
    local wep = player.GetWeaponInHUDSlot and player:GetWeaponInHUDSlot(1)
    return wep ~= nil and wep.GetTechId and wep:GetTechId() == goal
end

local function TryBuyMarineBot(player)
    if not player:GetIsAlive() then return end
    if player.isa and player:isa("Exo") then return end -- exos can't buy anything
    if player.GetIsAllowedToBuy and not player:GetIsAllowedToBuy() then return end

    local res = player.GetResources and player:GetResources()
    if not res or res <= 0 then return end

    -- Assign a varied purchase plan once.
    if not player.botEcoMarineGoal then
        player.botEcoMarineGoal = kMarinePrimaryGoals[math.random(1, #kMarinePrimaryGoals)]
        player.botEcoWantsWelder = math.random() < 0.5   -- ~half of bots also carry a welder
    end

    -- Welder first (cheap utility) when wanted and not already held. ProcessBuyAction
    -- only succeeds near an armory, so this naturally happens when regrouping.
    if player.botEcoWantsWelder and player.GetWeapon and not player:GetWeapon(Welder.kMapName) then
        local welderCost = GetCostForTech(kTechId.Welder) or 0
        if res >= welderCost and player:ProcessBuyAction({ kTechId.Welder }) then
            return
        end
    end

    local goal = player.botEcoMarineGoal
    if GetMarineAlreadyHasGoal(player, goal) then return end

    local cost = GetCostForTech(goal) or math.huge
    if res >= cost then
        player:ProcessBuyAction({ goal })
    end
end

function PlayingTeam:UpdateBotEconomy()

    local now = Shared.GetTime()
    if self._nextBotEconomyTime and now < self._nextBotEconomyTime then return end
    self._nextBotEconomyTime = now + kBotEconomyInterval

    local teamType = self:GetTeamType()
    if teamType ~= kAlienTeamType and teamType ~= kMarineTeamType then return end

    for _, player in ipairs(self:GetPlayers()) do
        if player and player.GetIsVirtual and player:GetIsVirtual() then
            if teamType == kAlienTeamType then
                TryEvolveAlienBot(player)
            else
                TryBuyMarineBot(player)
            end
        end
    end

end

debug.setupvaluex(PlayingTeam.OnResearchComplete, "GetIsResearchRelevant", extGetIsResearchRelevant)
