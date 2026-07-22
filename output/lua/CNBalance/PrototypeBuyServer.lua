-- CNBalance/PrototypeBuyServer.lua
-- Server-side bundle purchase handler for the Prototype Lab buy window.
-- Loaded post lua/Marine_Server.lua (vanilla Marine:AttemptToBuy / GiveJetpack /
-- resource accessors live there). Limited port: no Jumppack; exo combos whose
-- weapon files aren't present yet fall back to a valid exo via Exo:InitWeapons.

if Server then

-- Replace the Marine with an Exo carrying the requested combo layout key
-- (e.g. "DualFlamethrower"). Preserves the marine's weapons across the transition
-- so they return on eject. Returns the new Exo (for setting upgrade flags).
function Marine:GivePrototypeExo(layoutKey)

    local weapons = self:GetWeapons()
    for i = 1, #weapons do
        weapons[i]:SetParent(nil)
    end

    local exo = self:Replace(Exo.kMapName, self:GetTeamNumber(), false, Vector(self:GetOrigin()), { layout = layoutKey })

    if exo then
        for i = 1, #weapons do
            exo:StoreWeapon(weapons[i])
        end
    else
        for i = 1, #weapons do
            if weapons[i] and not weapons[i]:GetIsDestroyed() then
                weapons[i]:SetParent(self)
            end
        end
    end

    return exo
end

-- Vanilla GiveJetpack body, but returns the new JetpackMarine so callers can set
-- upgrade flags on it.
function Marine:GiveJetpack()

    local activeWeapon = self:GetActiveWeapon()
    local activeWeaponMapName
    local health = self:GetHealth()

    if activeWeapon ~= nil then
        activeWeaponMapName = activeWeapon:GetMapName()
    end

    local jetpackMarine = self:Replace(JetpackMarine.kMapName, self:GetTeamNumber(), true, Vector(self:GetOrigin()))

    if not jetpackMarine then
        return nil
    end

    jetpackMarine:SetActiveWeapon(activeWeaponMapName)
    jetpackMarine:SetHealth(health)

    return jetpackMarine
end

-- Apply the base item and return the carrier entity. For jetpack/exo the Replace
-- destroys the old Marine self; the returned carrier is the new entity. For cannon
-- the Marine self is preserved and the returned value is the Cannon weapon.
function Marine:ApplyPrototypeBase(baseTechId)

    if baseTechId == kTechId.Jetpack then
        return self:GiveJetpack()

    elseif baseTechId == kTechId.Cannon then
        return self:GiveItem(Cannon.kMapName)

    elseif kPrototypeExoCombos[baseTechId] then
        return self:GivePrototypeExo(kPrototypeExoCombos[baseTechId])

    end

    return nil
end

local baseAttemptToBuy = Marine.AttemptToBuy

function Marine:AttemptToBuy(techIds)

    local baseTechId = techIds and techIds[1]

    -- Not a prototype bundle -> vanilla.
    if not (baseTechId and kPrototypeBaseTechIds[baseTechId]) then
        return baseAttemptToBuy(self, techIds)
    end

    -- Track + speciality gate.
    local track = kPrototypeTrackForTechId[baseTechId]
    if not GetHasTech(self, kPrototypeSpecialityForTrack[track]) then
        return false
    end

    -- Extra research gate (authoritative): the Railgun exo combos require the Gauss (Cannon)
    -- tech. ProcessBuyAction routes prototype bundles straight here, bypassing the tech tree,
    -- so this must be checked explicitly or a client could buy a Railgun exo without Gauss.
    local reqTech = kPrototypeBaseRequiresTech and kPrototypeBaseRequiresTech[baseTechId]
    if reqTech and not GetHasTech(self, reqTech) then
        return false
    end

    -- Ownership guards: refuse duplicates.
    if baseTechId == kTechId.Jetpack and self:isa("JetpackMarine") then
        return false
    end
    if baseTechId == kTechId.Cannon and self:GetWeapon(Cannon.kMapName) then
        return false
    end

    -- Pre-game: all upgrades free (matches the pre-game 100 p-res rule).
    local preGame = false
    do
        local gr = GetGamerules and GetGamerules()
        preGame = gr and gr.GetGameState and gr:GetGameState() < kGameState.Started or false
    end
    local expTechId   = kPrototypeExperimentalForTrack and kPrototypeExperimentalForTrack[track]
    local expUnlocked = (expTechId and GetHasTech(self, expTechId)) or preGame

    local total = GetPrototypeCost(baseTechId)
    local upgrades = {}
    if expUnlocked then
        for i = 2, #techIds do
            local u = techIds[i]
            if u and kPrototypeTrackForTechId[u] == track and u ~= baseTechId
               and not kPrototypeBaseTechIds[u] then
                total = total + GetPrototypeCost(u)
                table.insert(upgrades, u)
            end
        end
    end

    if not preGame and self:GetResources() < total then
        return false
    end

    Shared.PlayPrivateSound(self, Marine.kSpendResourcesSoundName, nil, 1.0, self:GetOrigin())
    if not preGame then
        self:AddResources(-total)
    end

    local carrier = self:ApplyPrototypeBase(baseTechId)

    if not carrier then
        if not preGame and self.AddResources then
            self:AddResources(total)
        end
        return false
    end

    for _, u in ipairs(upgrades) do
        if carrier.SetPrototypeUpgrade then
            carrier:SetPrototypeUpgrade(u, true)
        end
    end
    if carrier.GetArmorAmount and carrier.SetMaxArmor then
        carrier:SetMaxArmor(carrier:GetArmorAmount())
        if carrier.SetArmor then carrier:SetArmor(carrier:GetMaxArmor()) end
    end
    if carrier.OnPrototypeUpgradesApplied then
        carrier:OnPrototypeUpgradesApplied()
    end
    return true
end

-- The "Buy" network message routes through Player:ProcessBuyAction, which validates
-- every techId against the tech tree and drops non-buyable ids. Bypass that for
-- prototype bundles and route straight to AttemptToBuy (which gates + charges itself).
function Marine:ProcessBuyAction(techIds)

    local baseTechId = techIds and techIds[1]

    if baseTechId and kPrototypeBaseTechIds[baseTechId] then
        return self:AttemptToBuy(techIds)
    end

    return Player.ProcessBuyAction(self, techIds)
end

end -- if Server
