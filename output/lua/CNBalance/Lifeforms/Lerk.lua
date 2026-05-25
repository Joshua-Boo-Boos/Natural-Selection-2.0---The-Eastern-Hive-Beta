Lerk.kAdrenalineEnergyRecuperationRate = 18.0
Script.Load("lua/RailgunTargetMixin.lua")

if Server then

    -- Safety net for Primal Scream. The normal ability availability hook grants
    -- it now, but this keeps freshly gestated Lerks covered if update ordering
    -- delays that path for a moment.
    local function GivePrimalScreamIfReady(self)

        local mapName = (PrimalScream and PrimalScream.kMapName) or "primalscream"
        if self:GetWeapon(mapName) then
            return
        end

        if not GetIsTechUnlocked(self, kTechId.PrimalScream) then
            return
        end

        self:GiveItem(mapName, false)

    end

    local baseOnProcessMove = Lerk.OnProcessMove
    function Lerk:OnProcessMove(input)
        baseOnProcessMove(self, input)
        if not self:GetIsDestroyed() and self:GetIsAlive() then
            local now = Shared.GetTime()
            if not self._nextPrimalScreamCheck or now >= self._nextPrimalScreamCheck then
                self._nextPrimalScreamCheck = now + 0.5
                GivePrimalScreamIfReady(self)
            end
        end
    end

end

local baseOnInitialized = Lerk.OnInitialized
function Lerk:OnInitialized()
    baseOnInitialized(self)
    if Client then
        InitMixin(self, RailgunTargetMixin)
    end
    if Server then
        self._nextPrimalScreamCheck = 0
    end
end

function Lerk:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint) -- dud
        local reduction = kLerkDamageReduction[doer:GetClassName()]
        if reduction then
            damageTable.damage = damageTable.damage * reduction
        end
end

function Lerk:GetExtraHealth(techLevel,extraPlayers,recentWins)
    return techLevel * kLerkHealthPerBioMass 
            - recentWins * 3
end

if Server then
    function Lerk:GetTierTwoTechId()
        return kTechId.Spores
    end

    function Lerk:GetTierThreeTechId()
        return kTechId.Umbra
    end
end
