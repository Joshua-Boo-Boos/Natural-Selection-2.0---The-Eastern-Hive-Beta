Alien.kBountyThreshold = kBountyClaimMinAlien

function Alien:GetPlayerStatusDesc()

    local status = kPlayerStatus.Void
    
    if (self:GetIsAlive() == false) then
        status = kPlayerStatus.Dead
    else
        if (self:isa("Embryo")) then
            if self.gestationTypeTechId == kTechId.Skulk then
                status = kPlayerStatus.SkulkEgg
            elseif self.gestationTypeTechId == kTechId.Gorge then
                status = kPlayerStatus.GorgeEgg
            elseif self.gestationTypeTechId == kTechId.Lerk then
                status = kPlayerStatus.LerkEgg
            elseif self.gestationTypeTechId == kTechId.Fade then
                status = kPlayerStatus.FadeEgg
            elseif self.gestationTypeTechId == kTechId.Onos then
                status = kPlayerStatus.OnosEgg
            elseif self.gestationTypeTechId == kTechId.Prowler then
                status = kPlayerStatus.ProwlerEgg
            elseif self.gestationTypeTechId == kTechId.Vokex then
                status = kPlayerStatus.VokexEgg
            else
                status = kPlayerStatus.Embryo
            end
        else
            status = kPlayerStatus[self:GetClassName()]
        end
    end
    
    return status
end

Script.Load("lua/CNBalance/Mixin/PrimalScreamMixin.lua")

local baseAlienOnInitialized = Alien.OnInitialized
function Alien:OnInitialized()
    if baseAlienOnInitialized then
        baseAlienOnInitialized(self)
    end

    -- Ensure all Alien-derived entities can receive PrimalScream
    if not HasMixin(self, "PrimalScream") then
        InitMixin(self, PrimalScreamMixin)
    end

    -- Alien Commander orders. Vanilla only gives OrdersMixin to hallucinations; like theirs, the
    -- mixin's network field is NOT added, so no class is re-linked (orders are server-side).
    if not HasMixin(self, "Orders") then
        InitMixin(self, OrdersMixin, { kMoveOrderCompleteDistance = kPlayerMoveOrderCompleteDistance })
    end
end

-- Right-click orders from the Alien Commander, mirroring Marine:OnOverrideOrder: defend a friendly
-- target, attack a sighted enemy, otherwise move. Gorges also get Construct / Heal (Lifeforms/Gorge.lua).
function Alien:OnOverrideOrder(order)

    if order:GetType() ~= kTechId.Default then
        return
    end

    local orderTarget = Shared.GetEntity(order:GetParam())

    if GetOrderTargetIsDefendTarget(order, self:GetTeamNumber()) then
        order:SetType(kTechId.Defend)
    elseif orderTarget and GetAreEnemies(orderTarget, self) and HasMixin(orderTarget, "Live") and orderTarget:GetIsAlive()
            and (not HasMixin(orderTarget, "LOS") or orderTarget:GetIsSighted()) then
        order:SetType(kTechId.Attack)
    else
        order:SetType(kTechId.Move)
    end

end

-- Real enzyme always wins over PrimalScream. Hook the server-side
-- TriggerEnzyme entry point so any non-PrimalScream caller (EnzymeCloud,
-- console commands, etc.) clears the primal flag — the same call still
-- writes timeWhenEnzymeExpires, so the target gets full-strength enzyme.
if Server and Alien.TriggerEnzyme then
    local baseAlienTriggerEnzyme = Alien.TriggerEnzyme
    function Alien:TriggerEnzyme(duration)
        if self.ClearPrimalScreamFlag then
            self:ClearPrimalScreamFlag()
        end
        baseAlienTriggerEnzyme(self, duration)
    end
end

-- PrimalScream uses the same enzyme machinery as real enzyme, so the base
-- Alien:OnUpdateAnimationInput already writes the full enzyme attack speed
-- when the alien is enzymed. If that enzyme actually came from PrimalScream,
-- the buff should be ~50% as strong, so overwrite attack_speed with the
-- partial-boost value. Real enzyme always overrides PrimalScream via the
-- TriggerEnzyme hook above, so non-primal enzyme keeps the full bonus.
-- Returns true if this alien's *current* enzyme came from PrimalScream.
-- Server has the authoritative flag; the client reads the networked window
-- broadcast by PrimalScreamFX.lua (the mixin field never syncs).
local function GetEnzymeIsFromPrimalScream(self)
    if Server then
        return self.enzymeIsFromPrimalScream == true
    end
    if GetIsClientPrimalScreamed then
        return GetIsClientPrimalScreamed(self:GetId())
    end
    return false
end

local baseAlienOnUpdateAnimationInput = Alien.OnUpdateAnimationInput
function Alien:OnUpdateAnimationInput(modelMixin)

    baseAlienOnUpdateAnimationInput(self, modelMixin)

    if not (self.GetIsEnzymed and self:GetIsEnzymed()) then return end
    if not GetEnzymeIsFromPrimalScream(self) then return end

    -- PrimalScream is exactly 50% of the enzyme attack-speed boost.
    -- e.g. real enzyme boosts attack speed by (kEnzymeAttackSpeed - 1) = +25%;
    --      PrimalScream therefore boosts by 0.5 * (+25%) = +12.5%.
    -- kDefaultAttackSpeed is local to vanilla Alien.lua, so use 1 here.
    local kPrimalScreamFraction = 0.5
    local enzymeBoost = (kEnzymeAttackSpeed or 1.25) - 1
    local primalSpeed = 1 + enzymeBoost * kPrimalScreamFraction
    primalSpeed = primalSpeed * (self.electrified and (kElectrifiedAttackSpeed or 0.8) or 1)

    if self.ModifyAttackSpeed then
        local attackSpeedTable = { attackSpeed = primalSpeed }
        self:ModifyAttackSpeed(attackSpeedTable)
        primalSpeed = attackSpeedTable.attackSpeed
    end

    modelMixin:SetAnimationInput("attack_speed", primalSpeed)

end

-- if Server then
--     -- ThirdPerson Codes
--     local function ThirdPerson(self)
--         if HasMixin(self, "CameraHolder") then

--             local numericDistance = 3
--             if self:GetIsThirdPerson() then
--                 numericDistance = 0
--             end
            
--             self:SetIsThirdPerson(numericDistance)
--         end
--     end

--     local baseHandleButtons = Alien.HandleButtons

--     local tpPressed = false

--     function Alien:HandleButtons(input)

--         baseHandleButtons(self,input)

--             if bit.band(input.commands, Move.Reload) ~= 0 then
--                 if not tpPressed then
--                     tpPressed=true
--                     ThirdPerson(self)
--                 end
--             else
--                 tpPressed=false
--             end
        
--     end
-- end