-- CNBalance/PrototypeBuyServer.lua
-- Task 6: Server-side bundle purchase handler for the Prototype Lab buy window.
-- Loaded post lua/Marine_Server.lua (where vanilla Marine:AttemptToBuy,
-- Marine:GiveJetpack, and the resource accessors live).
--
-- Hard rules:
--   * No new networked class.
--   * self:Replace(...) destroys old self; charge resources and read self BEFORE
--     applying the base, set upgrade flags on the RETURNED carrier only.
--   * Marine:GivePrototypeExo is implemented in a later task (Task 19).
--     The exo branch calls it at runtime; until Task 19 lands it will error
--     for exo-combo purchases, but jetpack and cannon work now.
--   * Non-bundle techIds fall through to the saved vanilla AttemptToBuy unchanged.

if Server then

-- ============================================================
-- B0. Marine:GivePrototypeExo(layoutKey) — Task 19
--     Replaces the Marine with an Exo carrying the requested combo layout.
--     layoutKey must be a key in kPrototypeExoLayouts (e.g. "DualMinigun").
--     self.layout is applied from extraValues before OnInitialized, so
--     InitExoModel and InitWeapons pick it up — identical to how vanilla
--     GiveExo passes { layout = "MinigunMinigun" } (Marine_Server.lua).
--     Returns the new Exo entity so AttemptToBuy can set upgrade flags on it.
-- ============================================================
function Marine:GivePrototypeExo(layoutKey)
    -- Preserve the marine's current weapons across the exo transition so they are
    -- restored when the player ejects — mirrors vanilla Marine:BuyExo
    -- (Marine_Server.lua ~line 278).  Capture + unparent BEFORE Replace (which
    -- would otherwise destroy them as children), then StoreWeapon them on the new
    -- Exo.  Without this the Cannon (and rifle/pistol/etc.) vanish on eject.
    local weapons = self:GetWeapons()
    for i = 1, #weapons do
        weapons[i]:SetParent(nil)
    end

    -- Pass the marine's current origin explicitly (matches GiveJetpack); a nil
    -- origin can leave the replaced Exo without a valid spawn position.
    local exo = self:Replace(Exo.kMapName, self:GetTeamNumber(), false, Vector(self:GetOrigin()), { layout = layoutKey })

    if exo then
        for i = 1, #weapons do
            exo:StoreWeapon(weapons[i])
        end
    else
        -- Replace failed: `self` (the Marine) still exists but its weapons were
        -- just un-parented above and would otherwise be left orphaned/floating.
        -- Re-parent them so the marine keeps its loadout, and return nil so the
        -- caller (AttemptToBuy) refunds the resources instead of silently eating
        -- both the weapons and the p-res.
        for i = 1, #weapons do
            if weapons[i] and not weapons[i]:GetIsDestroyed() then
                weapons[i]:SetParent(self)
            end
        end
    end

    return exo
end

-- ============================================================
-- B1. Marine:GiveJetpack override — mirrors vanilla body exactly
--     but returns the new JetpackMarine entity so callers can set
--     upgrade flags on it.
--     Vanilla body confirmed in NS2-Copy/ns2/lua/Marine_Server.lua ~line 512:
--       local activeWeapon = self:GetActiveWeapon()
--       local activeWeaponMapName
--       local health = self:GetHealth()
--       if activeWeapon ~= nil then
--           activeWeaponMapName = activeWeapon:GetMapName()
--       end
--       local jetpackMarine = self:Replace(JetpackMarine.kMapName, ...)
--       jetpackMarine:SetActiveWeapon(activeWeaponMapName)
--       jetpackMarine:SetHealth(health)
--     Vanilla did NOT return jetpackMarine; we add that return.
-- ============================================================
function Marine:GiveJetpack()

    local activeWeapon = self:GetActiveWeapon()
    local activeWeaponMapName
    local health = self:GetHealth()

    if activeWeapon ~= nil then
        activeWeaponMapName = activeWeapon:GetMapName()
    end

    local jetpackMarine = self:Replace(JetpackMarine.kMapName, self:GetTeamNumber(), true, Vector(self:GetOrigin()))

    -- Guard against a nil Replace (should never happen for a jetpack, but a bare
    -- jetpackMarine:SetActiveWeapon would hard-error instead of letting the caller
    -- refund - return nil cleanly so AttemptToBuy's refund path handles it).
    if not jetpackMarine then
        return nil
    end

    jetpackMarine:SetActiveWeapon(activeWeaponMapName)
    jetpackMarine:SetHealth(health)

    return jetpackMarine

end

-- ============================================================
-- B2. Marine:ApplyPrototypeBase(baseTechId) -> carrier entity
--     Applies the base item and returns the carrier entity.
--     IMPORTANT: for jetpack/exo the Replace call destroys the old
--     Marine self; the returned carrier is the new entity.
--     For cannon the Marine self is preserved; the returned value
--     is the Cannon weapon entity (used for setting upgrades).
-- ============================================================
function Marine:ApplyPrototypeBase(baseTechId)

    if baseTechId == kTechId.Jetpack then
        -- GiveJetpack now returns the new JetpackMarine (B1 above).
        return self:GiveJetpack()

    elseif baseTechId == kTechId.Cannon then
        -- Marine stays; GiveItem returns the weapon entity.
        return self:GiveItem(Cannon.kMapName)

    elseif kPrototypeExoCombos[baseTechId] then
        -- Implemented in Task 19. Calling here is safe; Lua resolves the
        -- method at call time. Until Task 19 lands, exo-combo purchases
        -- will runtime-error in this branch but jet/cannon work fine.
        return self:GivePrototypeExo(kPrototypeExoCombos[baseTechId])

    end

    return nil

end

-- ============================================================
-- B3. Marine:AttemptToBuy override — intercepts bundle purchases.
--     Non-bundle techIds are forwarded to the saved vanilla function
--     so Armory/vanilla purchases are completely unaffected.
--
-- Resource API names confirmed from vanilla Marine_Server.lua:
--   self:AddResources(-GetCostForTech(techId))  (line 277 in BuyExo,
--                                                line 343 in AttemptToBuy jetpack branch)
--   self:GetResources() — via ResourcesMixin (used in vanilla guards)
-- Sound constant confirmed from Marine.lua line 68 + Marine_Server.lua line 333:
--   Marine.kSpendResourcesSoundName
-- GetWeapon confirmed from WeaponOwnerMixin:GetWeapon(weaponMapName) line 349.
-- ============================================================
local baseAttemptToBuy = Marine.AttemptToBuy

function Marine:AttemptToBuy(techIds)

    local baseTechId = techIds and techIds[1]

    -- If this is not a prototype-bundle purchase, let vanilla handle it.
    if not (baseTechId and kPrototypeBaseTechIds[baseTechId]) then
        return baseAttemptToBuy(self, techIds)
    end

    -- Determine track and required speciality tech.
    local track = kPrototypeTrackForTechId[baseTechId]
    if not GetHasTech(self, kPrototypeSpecialityForTrack[track]) then
        return false
    end

    -- Ownership guards: refuse duplicate purchases.
    if baseTechId == kTechId.Jetpack and self:isa("JetpackMarine") then
        return false
    end
    if baseTechId == kTechId.Cannon and self:GetWeapon(Cannon.kMapName) then
        return false
    end

    -- Sum cost: base cost plus only the upgrades that belong to the same track
    -- (ignore any stray ids in slots beyond the bundle).  Upgrades are only
    -- allowed when the track's Experimental Technologies research is complete;
    -- otherwise the base item is still bought but the upgrades are ignored.
    -- During the pre-game, allow all upgrades for free testing (mirrors the
    -- pre-game 100 p-res rule); after the round starts the research is required.
    local preGame = false
    do
        local gr = GetGamerules and GetGamerules()
        preGame = gr and gr.GetGameState and gr:GetGameState() < kGameState.Started or false
    end
    local expTechId  = kPrototypeExperimentalForTrack and kPrototypeExperimentalForTrack[track]
    local expUnlocked = (expTechId and GetHasTech(self, expTechId)) or preGame
    local total = GetPrototypeCost(baseTechId)
    local upgrades = {}
    if expUnlocked then
        for i = 2, #techIds do
            local u = techIds[i]
            if u and kPrototypeTrackForTechId[u] == track and u ~= baseTechId then
                total = total + GetPrototypeCost(u)
                table.insert(upgrades, u)
            end
        end
    end

    -- Funds check (skipped during pre-game; purchases are free then).
    -- self:GetResources() is the personal-resource getter from ResourcesMixin,
    -- matching the vanilla buy path's self:AddResources(-GetCostForTech(techId)).
    if not preGame and self:GetResources() < total then
        return false
    end

    -- Charge resources + play the spend sound BEFORE Replace, while `self` (the
    -- Marine) is still guaranteed valid and owns the personal-resource pool
    -- (which carries over to the JetpackMarine/Exo via copyPlayerData on Replace).
    -- Skip the charge entirely during pre-game so purchases are genuinely free
    -- then (matches the funds-check skip above). If the base application later
    -- fails, we refund below.
    Shared.PlayPrivateSound(self, Marine.kSpendResourcesSoundName, nil, 1.0, self:GetOrigin())
    if not preGame then
        self:AddResources(-total)
    end

    -- Apply base item. For jetpack/exo, self is destroyed here and carrier is
    -- the new entity. For cannon, self is still valid but we don't use it after.
    local carrier = self:ApplyPrototypeBase(baseTechId)

    if not carrier then
        -- Base application failed. Crucially, carrier is nil ONLY when the
        -- Replace/GiveItem did NOT succeed - which means `self` was NOT destroyed
        -- and is still valid - so refund the resources we just charged (no-op in
        -- pre-game since nothing was charged) instead of eating the player's p-res.
        if not preGame and self.AddResources then
            self:AddResources(total)
        end
        return false
    end

    -- Set upgrade flags on the returned carrier, never on old self.
    for _, u in ipairs(upgrades) do
        if carrier.SetPrototypeUpgrade then
            carrier:SetPrototypeUpgrade(u, true)
        end
    end
    -- Task 7: Armor refresh — after all flags are set, recompute max armor so that
    -- upgrades like PrototypeJetpackArmour (+25 AP) take effect immediately.
    -- Cannon has no GetArmorAmount so this block is silently skipped for it.
    if carrier.GetArmorAmount and carrier.SetMaxArmor then
        carrier:SetMaxArmor(carrier:GetArmorAmount())
        if carrier.SetArmor then carrier:SetArmor(carrier:GetMaxArmor()) end
    end
    -- Task 10: Let the carrier refresh clip/ammo after all upgrade flags are set
    -- (e.g. Cannon:OnPrototypeUpgradesApplied refills clip to the new GetClipSize()).
    if carrier.OnPrototypeUpgradesApplied then
        carrier:OnPrototypeUpgradesApplied()
    end
    return true

end

-- ============================================================
-- B4. Marine:ProcessBuyAction override — bypass the vanilla tech-tree gate
--     for prototype bundles.
--
-- CRITICAL: the "Buy" network message handler (NetworkMessages_Server.lua:340)
-- calls player:ProcessBuyAction(techIds), NOT AttemptToBuy directly.  Vanilla
-- Player:ProcessBuyAction (Player_Server.lua:726) validates EVERY techId against
-- the tech tree — `techNode ~= nil and techNode.available` — and on the first id
-- that fails it sets buyAllowed=false and BREAKS, dropping that id (and all that
-- follow) from the list it finally passes to AttemptToBuy.
--
-- Our prototype base + upgrade techIds are NOT available tech-tree buy nodes, so
-- the vanilla gate stripped the upgrades (and exo-combo bases entirely) before
-- our bundle handler ever saw them.  THAT is why cannon upgrades did nothing
-- (only the bare Cannon survived) and exo combos would not purchase at all.
--
-- For a prototype bundle we bypass the vanilla gate completely and route straight
-- to AttemptToBuy, which does its own speciality / cost / ownership gating AND
-- charges resources itself — so we must NOT also run the vanilla AddResources.
-- Non-prototype purchases delegate unchanged to the inherited vanilla logic.
-- ============================================================
function Marine:ProcessBuyAction(techIds)

    local baseTechId = techIds and techIds[1]

    if baseTechId and kPrototypeBaseTechIds[baseTechId] then
        -- Prototype bundle — AttemptToBuy handles gating + charging itself.
        return self:AttemptToBuy(techIds)
    end

    -- Everything else: vanilla behaviour (inherited from Player).
    return Player.ProcessBuyAction(self, techIds)

end

end -- if Server
