ScoringMixin.networkVars.bountyCurrentLife = "integer"

local kBountyCooldownTick = 2
local baseInitMixin = ScoringMixin.__initmixin
function ScoringMixin:__initmixin()
    baseInitMixin(self)
    self.bountyCurrentLife = 0
    -- Must be initialised here: the decay accumulator is no longer seeded by AddBounty (the 60s
    -- countdown runs continuously and is never reset by kills/assists/claims), so without this it
    -- would be nil the first time CheckBountyCooldown does arithmetic on it.
    self.bountyCooldown = 0
    if Server then
        self:AddTimedCallback( self.CheckBountyCooldown, kBountyCooldownTick )
    end
end

if Server then
    
    function ScoringMixin:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint)
        
        if self.isHallucination
            or self:GetIsVirtual()
            or (attacker.GetIsVirtual and attacker:GetIsVirtual())
        then return end
    
        if(damageTable.damage <= 0) then return end
    
        local damageScalar = 1
        
        -- local bountyScore = self:GetBountyCurrentLife()

        -- --Self Bounty Damage Taken Increase
        -- if bountyScore > 0 then   
        --     local scalar = bountyScore  * (0.1 / self.kBountyThreshold)
        --     scalar = scalar * (math.floor(bountyScore / self.kBountyThreshold)+ 1)
        --     damageScalar = damageScalar + scalar      --Receive Additional Damage And Die Please
        -- end

        local bountyScore = self:GetBountyCurrentLife()

        --Self Bounty Damage Taken Increase
        if bountyScore > 0 then
            local scalar = 1.5 * (bountyScore / 50)
            damageScalar = damageScalar + scalar -- Requires 1.5 extra via scalar at 50 bounty
        end

        damageScalar = Clamp(damageScalar,0.2,2.5) -- Was 5 maximum
        damageTable.damage = damageTable.damage * damageScalar
    end

    local baseResetScores = ScoringMixin.ResetScores
    function ScoringMixin:ResetScores()
        baseResetScores(self)
        self.bountyCurrentLife = 0
        self.bountyCooldown = 0
    end

    local baseCopyPlayerDataFrom = ScoringMixin.CopyPlayerDataFrom
    function ScoringMixin:CopyPlayerDataFrom(player)
        baseCopyPlayerDataFrom(self,player)
        self.bountyCurrentLife = player.bountyCurrentLife
        -- CARRY the decay accumulator across entity replacement (respawn, lifeform change). Zeroing
        -- it here would restart the 60s countdown every time a player died or evolved.
        self.bountyCooldown = player.bountyCooldown or 0
    end

    local function AddBounty(self,value)
        --if GetWarmupActive() then return end
        -- Going from ZERO bounty to some bounty starts a FRESH full 60s countdown, so a player who
        -- earns their first point never gets an instantly-short first tick from a leftover part
        -- cycle. While they ALREADY have bounty the countdown keeps running untouched - a kill or
        -- assist must never postpone the next -1 tick.
        local wasZero = ( self.bountyCurrentLife or 0 ) <= 0

        self.bountyCurrentLife = Clamp(self.bountyCurrentLife + value, 0, kMaxBountyScore)

        if wasZero and self.bountyCurrentLife > 0 then
            self.bountyCooldown = 0
        end
    end
    
    local baseAddKill = ScoringMixin.AddKill
    function ScoringMixin:AddKill()
        baseAddKill(self)
        if not NS2Gamerules.kBalanceConfig.bountyActive then
            return
        end
        AddBounty(self,kBountyScoreEachKill)
    end

    local baseAddAssistKill = ScoringMixin.AddAssistKill
    function ScoringMixin:AddAssistKill()
        baseAddAssistKill(self)
        if not NS2Gamerules.kBalanceConfig.bountyActive then
            return
        end
        AddBounty(self,kBountyScoreEachAssist)
    end

    function ScoringMixin:ClaimBounty()
        if self.bountyCurrentLife <= 0 then return 0 end

        local claim = math.min(self.bountyCurrentLife, math.floor(self.kBountyThreshold * kBountyClaimMultiplier))
        self.bountyCurrentLife = self.bountyCurrentLife - claim
        -- Decay countdown is NOT reset: dying (having your bounty claimed) must not postpone the
        -- next -1 tick either.
    end

    function ScoringMixin:CheckBountyCooldown()
        if self.bountyCurrentLife <= 0 then
            return true
        end

        -- FLAT decay: the bounty drops by exactly one point every kBountyCooldown seconds (60),
        -- whether or not the player is in combat. The old in-combat slowdown has been removed.
        -- NOTE: the test is >= , not > . With the 2s tick, a strict > meant the accumulator had to
        -- reach 62 before the first drop (62s, then 60s thereafter); >= makes every interval an
        -- exact 60s.
        self.bountyCooldown = self.bountyCooldown + kBountyCooldownTick
        if self.bountyCooldown >= kBountyCooldown then
            self.bountyCooldown = self.bountyCooldown - kBountyCooldown
            self.bountyCurrentLife = math.max(self.bountyCurrentLife - 1,0)
        end

        return true
    end

end

function ScoringMixin:GetBountyCurrentLife()
    assert(self.kBountyThreshold)
    return math.max(self.bountyCurrentLife - self.kBountyThreshold, 0)
end

function ScoringMixin:GetKDRatioUnforeseen()
    return math.max(
            - kKDRatioProtectionStep,0)
end

function ScoringMixin:AddContinuousScore(name, addAmount, amountNeededToScore, pointsGivenOnScore, resGivenOnScore )

    if Server then

        self.continuousScores[name] = self.continuousScores[name] or { amount = 0 }
        self.continuousScores[name].amount = self.continuousScores[name].amount + addAmount
        while self.continuousScores[name].amount >= amountNeededToScore do
            resGivenOnScore = resGivenOnScore or 0
            self:AddScore(pointsGivenOnScore, resGivenOnScore)
            self:AddResources(resGivenOnScore)
            self.continuousScores[name].amount = self.continuousScores[name].amount - amountNeededToScore

        end

    end

end