-- CNBalance/CommanderExoDrop.lua
-- Marine Commander Exo drop.
--
-- The ProtosMenu used to hold TWO fixed Exo buttons (Dual Minigun, Dual Railgun). It now holds
-- ONE, kTechId.DropDualMinigunExosuit, repurposed as a generic "Exosuit" button:
--
--   1. The button greys out with no researched Exosuit Prototype Lab (the tech tree already
--      does this - DropDualMinigunExosuit is gated on it) and turns RED when the team cannot
--      afford even the cheapest configuration. GUICommanderButtons refuses the click in both
--      states, so the window can only open when a drop is actually possible.
--   2. Clicking it opens GUICommanderExoDropMenu - the Prototype Lab buy window with the
--      jetpack and cannon tracks removed - where the commander picks the combo and its
--      Experimental Technologies upgrades and pays in TEAM resources.
--   3. BUY sends the configuration to the server and arms the normal placement ghost.
--   4. Placing it creates an Exosuit carrying EXACTLY that configuration.
--
-- Loaded as a "post" hook on lua/MarineCommander.lua, which is late enough for all of:
-- lua/Commander_Client.lua and lua/Commander_Buttons.lua (loaded via lua/Commander.lua),
-- lua/MarineCommander_Server.lua, and the mod's own "replace" of lua/MarineCommander.lua.

-- Resolved LAZILY, never captured into a file-local at load time.
--
-- kTechId.DropDualMinigunExosuit does not exist in the base game - it is appended to the enum by
-- debug.appendtoenum in CNBalance/TechTreeConstants.lua, which is a hook on a DIFFERENT file
-- (lua/TechTreeConstants.lua) than this one (lua/MarineCommander.lua). Reading it at load time
-- therefore depends on the relative order of two unrelated file hooks, and when this file won that
-- race the local was silently nil - so the tech-id comparison was always false, the Exo button
-- fell straight through to the normal targeted-activation path, and the configuration window never
-- opened while the placement ghost armed anyway. Exactly the reported behaviour.
local function GetExoDropTechId()
    return kTechId.DropDualMinigunExosuit
end

local kExoTrack = "exo"

-- ============================================================
-- Shared validation
-- ============================================================
-- Whether `player`'s team may drop this combo at all: it must be a real exo combo, the
-- Exosuit Prototype Lab must be researched, and the combo's extra research gate (the Gauss
-- tech, for the two railgun combos) must be met. Same rules the marine buy window applies -
-- read from the SHARED tables in PrototypeTechData.lua so the two can never drift apart.
function GetCommanderExoDropComboAllowed(player, baseTechId)

    if not player or not kPrototypeExoCombos[baseTechId] then
        return false
    end

    if not GetHasTech(player, kPrototypeSpecialityForTrack[kExoTrack]) then
        return false
    end

    local requiredTech = kPrototypeBaseRequiresTech and kPrototypeBaseRequiresTech[baseTechId]
    if requiredTech and not GetHasTech(player, requiredTech) then
        return false
    end

    return true
end

-- Whether the Experimental Technologies upgrades may be picked at all.
-- NOTE: unlike the marine buy window there is NO pre-game exception here. The marine window
-- makes upgrades free before the round starts to go with its pre-game 100 p-res rule; the
-- commander pays team resources, which have no such rule, so a second pricing mode would only
-- create a case where the window and the server disagree about what an upgrade costs.
function GetCommanderExoDropExperimentalUnlocked(player)
    local experimentalTechId = kPrototypeExperimentalForTrack and kPrototypeExperimentalForTrack[kExoTrack]
    return (player and experimentalTechId and GetHasTech(player, experimentalTechId)) == true
end

-- Decode an upgrade bitmask into the list of upgrade techIds it names, DROPPING everything
-- the team has not researched. Both sides call this, so the window's running total and the
-- server's charge are computed from the same filtered list.
function GetCommanderExoDropUpgrades(player, upgradeBits)

    local upgrades = {}

    if not GetCommanderExoDropExperimentalUnlocked(player) then
        return upgrades
    end

    for _, techId in ipairs(kPrototypeUpgradesForTrack[kExoTrack] or {}) do
        local bit = PrototypeUpgradesMixin.kBit[techId]
        if bit and math.floor((upgradeBits or 0) / 2 ^ bit) % 2 == 1 then
            table.insert(upgrades, techId)
        end
    end

    return upgrades
end

-- Re-encode a list of upgrade techIds as a bitmask.
function GetCommanderExoDropBits(upgrades)
    local bits = 0
    for _, techId in ipairs(upgrades or {}) do
        local bit = PrototypeUpgradesMixin.kBit[techId]
        if bit then
            bits = bits + 2 ^ bit
        end
    end
    return bits
end

-- ============================================================
-- Server
-- ============================================================
if Server then

    -- Armour for a freshly dropped Exosuit. Vanilla Exosuit:OnInitialized sets a FLAT
    -- kExosuitArmor, which ignores the team's armour upgrades AND the Armour Plating
    -- experimental upgrade - and Exosuit:OnUseDeferred hands that stored value straight to the
    -- Exo the marine becomes. Without this the commander could pay 13 t-res for Armour Plating
    -- and the marine would receive none of it. Mirrors Exo:GetArmorAmount (CNBalance/Exo.lua).
    local function GetDroppedExosuitArmor(commander, hasArmourPlating)

        local armorLevels = 0
        if GetHasTech(commander, kTechId.Armor3, true) then
            armorLevels = 3
        elseif GetHasTech(commander, kTechId.Armor2, true) then
            armorLevels = 2
        elseif GetHasTech(commander, kTechId.Armor1, true) then
            armorLevels = 1
        end

        local platingBonus = hasArmourPlating and kPrototypeExoArmourPlatingBonus or 0

        if GetHasTech(commander, kTechId.MilitaryProtocol) then
            return kExosuitMPArmor + armorLevels * kExosuitMPArmorPerUpgradeLevel + platingBonus
        end

        return kExosuitArmor + armorLevels * kExosuitArmorPerUpgradeLevel + platingBonus
    end

    -- The configuration the commander last confirmed in the buy window. Advisory: every field
    -- is re-validated at placement time below.
    Server.HookNetworkMessage("CommanderExoConfig", function(client, message)

        local player = client and client:GetControllingPlayer()
        if not player or not player:isa("MarineCommander") then
            return
        end

        player.pendingExoDropBase = message.baseTechId
        player.pendingExoDropBits = message.upgradeBits

    end)

    -- Stamp the configuration onto the Exosuit the placement just created.
    local function ApplyConfigToExosuit(commander, exosuit, baseTechId, upgrades)

        -- Sets the arms/world model for the combo. It also copies _G.gEjectingExoPrototypeBits
        -- if that global is live from some earlier eject, so the upgrade bits are written
        -- AFTERWARDS to guarantee this drop's configuration wins.
        exosuit:SetLayout(kPrototypeExoCombos[baseTechId])

        local hasArmourPlating = false
        local hasResupply      = false
        for _, techId in ipairs(upgrades) do
            hasArmourPlating = hasArmourPlating or techId == kTechId.PrototypeExoArmour
            hasResupply      = hasResupply      or techId == kTechId.PrototypeResupply
        end

        exosuit.storedPrototypeUpgradeBits = GetCommanderExoDropBits(upgrades)

        -- Resupply ships with a full magazine of charges, as it does when bought by a marine.
        if hasResupply then
            exosuit.storedResupplyCharges = kResupplyMaxCharges
        end

        local armor = GetDroppedExosuitArmor(commander, hasArmourPlating)
        exosuit:SetMaxArmor(armor)
        exosuit:SetArmor(armor)
    end

    local baseProcessTechTreeActionForEntity = MarineCommander.ProcessTechTreeActionForEntity

    function MarineCommander:ProcessTechTreeActionForEntity(techNode, position, normal, pickVec, orientation, entity, trace, targetId)

        if techNode:GetTechId() ~= GetExoDropTechId() then
            return baseProcessTechTreeActionForEntity(self, techNode, position, normal, pickVec, orientation, entity, trace, targetId)
        end

        local baseTechId = self.pendingExoDropBase

        -- AUTHORITATIVE re-check. The buy window performs the same checks so the commander
        -- never sees an impossible option, but everything it sends is client input: without
        -- these a crafted CommanderExoConfig could drop an unresearched or free Exo.
        if not GetCommanderExoDropComboAllowed(self, baseTechId) then
            self:TriggerInvalidSound()
            return false, false
        end

        local upgrades = GetCommanderExoDropUpgrades(self, self.pendingExoDropBits)
        local cost     = GetCommanderExoDropTotal(baseTechId, upgrades)
        local team     = self:GetTeam()

        -- Re-checked HERE, not when the window's BUY button was clicked, so the drop is paid
        -- for at the moment it happens: cancelling the ghost costs nothing, and a teammate's
        -- spend between BUY and placement cannot put the team into negative resources.
        if team:GetTeamResources() < cost then
            self:TriggerNotEnoughResourcesAlert()
            return false, false
        end

        local success, createdEntityId = self:AttemptToBuild(GetExoDropTechId(), position, normal, orientation, pickVec, false, entity)

        if not success then
            return false, false
        end

        local exosuit = createdEntityId and Shared.GetEntity(createdEntityId)
        if not exosuit or not exosuit.SetLayout then
            -- The entity exists but is not the Exosuit we expected; destroy it rather than
            -- leave a mis-configured (and unpaid-for) suit on the floor.
            if exosuit then
                DestroyEntity(exosuit)
            end
            self:TriggerInvalidSound()
            return false, false
        end

        ApplyConfigToExosuit(self, exosuit, baseTechId, upgrades)

        team:AddTeamResources(-cost)
        Shared.PlayPrivateSound(self, self:GetSpendTeamResourcesSoundName(), nil, 1.0, self:GetOrigin())
        self:TriggerEffects("spawn_weapon", { effecthostcoords = Coords.GetTranslation(position) })

        -- One configuration, one Exo. The commander must re-open the window to drop another,
        -- so a stale configuration can never be spent by a later, unrelated click.
        self.pendingExoDropBase = nil
        self.pendingExoDropBits = nil

        -- NOT routed through ProcessSuccessAction: that charges GetCostForTech(techId), which
        -- is deliberately 0 for this button because the price depends on the configuration.
        return true, false
    end

end

-- ============================================================
-- Client
-- ============================================================
if Client then

    local kMenuScriptName = "CNBalance/GUI/GUICommanderExoDropMenu"
    local gExoDropMenu = nil

    function MarineCommanderExoDrop_GetIsOpen()
        return gExoDropMenu ~= nil
    end

    function MarineCommanderExoDrop_Close()
        if gExoDropMenu then
            GetGUIManager():DestroyGUIScript(gExoDropMenu)
            gExoDropMenu = nil
        end
    end

    function MarineCommanderExoDrop_Open()
        if gExoDropMenu then
            return
        end
        gExoDropMenu = GetGUIManager():CreateGUIScript(kMenuScriptName)
    end

    -- Called by the buy window's BUY button. Sends the configuration, then arms the normal
    -- placement ghost via SetCurrentTech - exoDropConfigured tells the hook below to let that
    -- call through instead of re-opening the window.
    function MarineCommanderExoDrop_Confirm(baseTechId, upgradeBits)

        Client.SendNetworkMessage("CommanderExoConfig",
            { baseTechId = baseTechId, upgradeBits = upgradeBits }, true)

        MarineCommanderExoDrop_Close()

        local player = Client.GetLocalPlayer()
        if player and player.SetCurrentTech then
            player.exoDropConfigured = true
            player:SetCurrentTech(GetExoDropTechId())
        end
    end

    -- Hooked on MarineCommander, NOT on Commander.
    --
    -- `class 'MarineCommander' (Commander)` has ALREADY run by the time this post-hook file loads,
    -- and NS2's class system resolves inherited methods into the derived class at that point -
    -- so replacing Commander.SetCurrentTech afterwards is invisible to a MarineCommander instance,
    -- which keeps calling the base implementation it captured earlier. That is why the Exo button
    -- kept arming the placement ghost with no configuration window: this hook was simply never
    -- running. Defining the override directly on MarineCommander is correct either way - if the
    -- method was inherited by reference instead, this just shadows it, which is equally fine.
    local baseSetCurrentTech = MarineCommander.SetCurrentTech or Commander.SetCurrentTech

    function MarineCommander:SetCurrentTech(techId)

        if techId == GetExoDropTechId() then

            -- Nothing configured yet -> this is the button click. Open the window and
            -- swallow the action; the ghost is armed later, from the BUY button.
            if not self.exoDropConfigured then
                MarineCommanderExoDrop_Open()
                return
            end

        else
            -- Any other tech (including the SetCurrentTech(kTechId.None) that Commander's
            -- targeted-action send performs) retires the configuration, so one BUY places
            -- exactly one Exo and an abandoned ghost leaves nothing armed.
            self.exoDropConfigured = nil
            MarineCommanderExoDrop_Close()
        end

        baseSetCurrentTech(self, techId)
    end

    -- Button colour. The tech tree already greys the button out without a researched Exosuit
    -- Prototype Lab (status 3), and GUICommanderButtons refuses clicks on anything that is not
    -- status 1 - so only the affordability half needs overriding. It has to be overridden
    -- because the button's tech-node cost is 0 (the real price depends on the configuration),
    -- which would otherwise make it look affordable at 0 team resources.
    local baseMenuButtonStatus = CommanderUI_MenuButtonStatus

    function CommanderUI_MenuButtonStatus(index)

        local status = baseMenuButtonStatus(index)

        -- Only reinterpret "available" (1) and "unaffordable" (2). Leave "hidden" (0),
        -- "greyed" (3) and "passive" (4) exactly as the tech tree decided them.
        if status ~= 1 and status ~= 2 then
            return status
        end

        local player = Client.GetLocalPlayer()
        if not player or not player.menuTechButtons or player.menuTechButtons[index] ~= GetExoDropTechId() then
            return status
        end

        -- Red unless the team can afford the cheapest possible configuration (a bare claw
        -- combo). Anything more expensive is gated inside the window itself.
        return PlayerUI_GetTeamResources() >= GetCommanderExoDropCheapest() and 1 or 2
    end

end
