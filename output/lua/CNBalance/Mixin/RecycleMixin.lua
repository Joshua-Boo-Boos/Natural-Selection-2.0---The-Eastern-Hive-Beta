

function RecycleMixin:OnRecycled()
    if self.PreOnKill then
        self:PreOnKill(nil,nil,nil,nil) --The nil army!
    end
end

function RecycleMixin:OnResearchComplete(researchId)

    if researchId == kTechId.Recycle then

        -- Do not display new killfeed messages during concede sequence
        if GetConcedeSequenceActive() then
            return
        end

        self:TriggerEffects("recycle_end")

        -- Amount to get back, accounting for upgraded structures too
        local upgradeLevel = 0
        if self.GetUpgradeLevel then
            upgradeLevel = self:GetUpgradeLevel()
        end

        local amount = GetRecycleAmount(self:GetTechId(), upgradeLevel) or 0
        -- returns a scalar from 0-1 depending on health the structure has (at the present moment)
        local scalar = self:GetRecycleScalar() * kRecyclePaybackScalar

        -- We round it up to the nearest value thus not having weird
        -- fracts of costs being returned which is not suppose to be
        -- the case.
        local finalRecycleAmount = math.round(amount * scalar)

        -- COMBAT ENGINEERS structures were paid for entirely out of marines' PERSONAL resources,
        -- tracked exactly on the structure as ceResSpent, and never cost the team a single team
        -- resource. The vanilla figure above is therefore meaningless for them: it is derived from a
        -- team-resource tech cost nobody paid. Refund a flat fraction of what was genuinely spent
        -- instead, so 100 p-res of construction returns 20 t-res to the commander.
        --
        -- `amount` is re-pointed at the p-res total as well, because it is only used from here on to
        -- report the SHORTFALL (amount - finalRecycleAmount) in the Recycle network message; leaving
        -- it as the old team cost would make that message describe a completely unrelated number.
        --
        -- No health scalar is applied: this pays back a share of resources actually contributed, and
        -- a half-built structure has already banked proportionally less in ceResSpent. Applying the
        -- health scalar on top would penalise the same incompleteness twice.
        if self.ceIsCombatEngineersStructure then

            amount = self.ceResSpent or 0
            finalRecycleAmount = math.round(amount * (kCombatEngineersRecycleRefundFraction or 0.20))

        end

        self:GetTeam():AddTeamResources(finalRecycleAmount)

        self:GetTeam():PrintWorldTextForTeamInRange(kWorldTextMessageType.Resources, finalRecycleAmount, self:GetOrigin() + kWorldMessageResourceOffset, kResourceMessageRange)

        Server.SendNetworkMessage( "Recycle", BuildRecycleMessage(amount - finalRecycleAmount, self:GetTechId(), finalRecycleAmount), true )

        local team = self:GetTeam()
        local deathMessageTable = team:GetDeathMessage(team:GetCommander(), kDeathMessageIcon.Recycled, self)
        local func = Closure [=[
            self deathMessageTable
            args player
            Server.SendNetworkMessage(player:GetClient(), "DeathMessage", deathMessageTable, true)
        ]=]{deathMessageTable}
        team:ForEachPlayer(func)

        self.recycled = true
        self.timeRecycled = Shared.GetTime()

        self:OnRecycled()

    end

end