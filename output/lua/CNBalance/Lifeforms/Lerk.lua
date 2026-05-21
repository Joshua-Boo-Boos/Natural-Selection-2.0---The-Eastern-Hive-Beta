Lerk.kAdrenalineEnergyRecuperationRate = 18.0
Script.Load("lua/RailgunTargetMixin.lua")
local baseOnInitialized = Lerk.OnInitialized
function Lerk:OnInitialized()
    baseOnInitialized(self)
    if Client then
        InitMixin(self, RailgunTargetMixin)
    end
    if Server then
        local mapName = (PrimalScream and PrimalScream.kMapName) or "primalscream"
        if GetHasTech(self, kTechId.PrimalScream) and not self:GetWeapon(mapName) then
            -- Extra safety: ensure the team's biomass level is actually high
            -- enough. This prevents the client HUD from lighting the ability
            -- when the player spawns before the team's biomass/state is fully
            -- propagated or if TechTree reports the tech prematurely.
            local team = self:GetTeam()
            local biomassLevel = 0
            if team and team.GetBioMassLevel then
                biomassLevel = team:GetBioMassLevel()
            end
            if biomassLevel >= 8 then
                self:GiveItem(mapName, false)
            end
        end
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
