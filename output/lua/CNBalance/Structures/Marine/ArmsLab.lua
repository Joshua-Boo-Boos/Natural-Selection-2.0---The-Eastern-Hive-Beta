Script.Load("lua/BiomassHealthMixin.lua")

local baseOnCreate = ArmsLab.OnCreate
function ArmsLab:OnCreate()
    baseOnCreate(self)
    InitMixin(self, BiomassHealthMixin)
end

function ArmsLab:GetExtraHealth(techLevel,extraPlayers,recentWins)
    return kArmsLabHealthPerPlayerAdd * extraPlayers
end

-- ============================================================
-- Combat Engineers
-- ============================================================
-- In a CE round Arms Labs are the team's ENTIRE upgrade path and there are up to six of them, so
-- they are halved in toughness to stay a realistic alien target. Applied here rather than in
-- BalanceHealth.lua so non-CE rounds are completely untouched.
local function GetIsCombatEngineersLab(self)
    local team = self:GetTeam()
    return team ~= nil and team.IsCombatEngineers and team:IsCombatEngineers()
end

if Server then

    -- Max health/armour live as LiveMixin FIELDS seeded from tech data, not as an overridable
    -- getter, so the halving is applied by adjusting those fields. AdjustMaxHealth/AdjustMaxArmor
    -- preserve the current fraction, so a damaged lab stays proportionally damaged.
    --
    -- Guarded by a flag because this runs both when the lab initialises and when Combat Engineers
    -- completes (labs the commander built beforehand are halved too, so the ladder - which counts
    -- every Arms Lab regardless of who paid - never mixes tough and fragile labs).
    function ArmsLab:ApplyCombatEngineersHealth()

        if self.ceHealthApplied or not GetIsCombatEngineersLab(self) then
            return
        end

        self.ceHealthApplied = true

        self:AdjustMaxHealth(math.max(1, math.floor(self:GetMaxHealth() * kCombatEngineersArmsLabHealthScalar)))
        self:AdjustMaxArmor(math.max(0, math.floor(self:GetMaxArmor() * kCombatEngineersArmsLabHealthScalar)))
    end

    local baseOnInitialized = ArmsLab.OnInitialized
    function ArmsLab:OnInitialized()
        if baseOnInitialized then
            baseOnInitialized(self)
        end
        self:ApplyCombatEngineersHealth()
    end

    -- Every event that can change the count of BUILT, POWERED Arms Labs funnels into one recount on
    -- the team. The team recomputes from scratch, so no ordering of these can desync the ladder.
    local function UpdateLadder(self)
        local team = self:GetTeam()
        if team and team.UpdateCombatEngineerTechLevel then
            team:UpdateCombatEngineerTechLevel()
        end
    end

    local baseOnConstructionComplete = ArmsLab.OnConstructionComplete
    function ArmsLab:OnConstructionComplete()
        if baseOnConstructionComplete then
            baseOnConstructionComplete(self)
        end
        UpdateLadder(self)
    end

    local baseOnKill = ArmsLab.OnKill
    function ArmsLab:OnKill(attacker, doer, point, direction)
        if baseOnKill then
            baseOnKill(self, attacker, doer, point, direction)
        end
        -- Deferred by a tick: this entity is still in the team's entity list right now, so an
        -- immediate recount would still see it and the ladder would not drop.
        self:AddTimedCallback(function() UpdateLadder(self) return false end, 0)
    end

    local baseOnDestroy = ArmsLab.OnDestroy
    function ArmsLab:OnDestroy()
        local team = self:GetTeam()
        if baseOnDestroy then
            baseOnDestroy(self)
        end
        if team and team.UpdateCombatEngineerTechLevel then
            team:UpdateCombatEngineerTechLevel()
        end
    end

    local baseOnPowerOn = ArmsLab.OnPowerOn
    function ArmsLab:OnPowerOn()
        if baseOnPowerOn then
            baseOnPowerOn(self)
        end
        UpdateLadder(self)
    end

    local baseOnPowerOff = ArmsLab.OnPowerOff
    function ArmsLab:OnPowerOff()
        if baseOnPowerOff then
            baseOnPowerOff(self)
        end
        UpdateLadder(self)
    end

    -- The ladder's researches are free and driven entirely by the lab count, so an Arms Lab in a CE
    -- round must never show or accept the normal paid Armor/Weapons buttons.
    local baseGetTechButtons = ArmsLab.GetTechButtons
    function ArmsLab:GetTechButtons(techId)

        if GetIsCombatEngineersLab(self) then
            return { kTechId.None, kTechId.None, kTechId.None, kTechId.None,
                     kTechId.None, kTechId.None, kTechId.None, kTechId.None }
        end

        return baseGetTechButtons and baseGetTechButtons(self, techId) or nil
    end

end
