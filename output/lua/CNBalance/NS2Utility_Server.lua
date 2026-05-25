local baseUpdateAbilityAvailability = UpdateAbilityAvailability

local kExtraBiomassAbilities =
{
    [kTechId.Lerk] =
    {
        kTechId.PrimalScream
    }
}

local function UnlockBiomassAbility(forAlien, techId)

    local mapName = LookupTechData(techId, kTechDataMapName)
    if mapName and forAlien:GetIsAlive() and not forAlien:GetWeapon(mapName) then

        local activeWeapon = forAlien:GetActiveWeapon()
        forAlien:GiveItem(mapName)

        if activeWeapon then
            forAlien:SetActiveWeapon(activeWeapon:GetMapName())
        end

    end

end

function UpdateAbilityAvailability(forAlien, tierOneTechId, tierTwoTechId, tierThreeTechId)

    baseUpdateAbilityAvailability(forAlien, tierOneTechId, tierTwoTechId, tierThreeTechId)

    local alienTechId = forAlien.GetTechId and forAlien:GetTechId() or kTechId.None
    local extraAbilities = kExtraBiomassAbilities[alienTechId]
    if not extraAbilities then
        return
    end

    for i = 1, #extraAbilities do

        local techId = extraAbilities[i]
        local unlockedField = "_unlockedBiomassAbility" .. tostring(techId)
        local hasTechNow = GetGamerules():GetAllTech() or GetIsTechUnlocked(forAlien, techId)

        -- Match vanilla biomass ability behavior: once a living lifeform earns
        -- the ability, it keeps it until death/evolve instead of losing it on
        -- later biomass drops.
        forAlien[unlockedField] = forAlien[unlockedField] or hasTechNow

        if forAlien[unlockedField] then
            UnlockBiomassAbility(forAlien, techId)
        end

    end

end
