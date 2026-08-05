-- CNBalance/CombatEngineers_Upgrade.lua
-- Combat Engineers: field marines research structure upgrades themselves.
--
-- With a Combat Builder equipped, right-clicking a friendly structure in range opens the upgrade
-- window (CNBalance/GUI/GUICEStructureUpgradeMenu.lua). Upgrades cost TEAM resources, not personal
-- ones - personal resources buy the structures, team resources upgrade them.
--
-- Loaded post lua/ResearchMixin.lua, which is where GetCanResearch / SetResearching live.

-- Range within which a marine may open a structure's upgrade window. Matches the build radius, so
-- "close enough to build it" and "close enough to upgrade it" are the same distance.
kCombatEngineersUpgradeRange = kMarineBuildRadius or 6

-- ============================================================
-- Which tech ids may be offered for a structure
-- ============================================================
-- The list comes from the structure's OWN GetTechButtons(), which this mod already maintains
-- correctly per structure - RoboticsFactory returns ARC + UpgradeRoboticsFactory with no MAC
-- (the MAC is auto-produced in NS2.0-TEH), Extractor returns PoweredExtractorUpgrade, and so on.
-- Hardcoding a parallel list here would duplicate that knowledge and drift from it.
local kExcludedTechIds =
{
    [kTechId.None]             = true,
    [kTechId.CollectResources] = true,   -- passive display entry, not an upgrade
    [kTechId.Cancel]           = true,
    [kTechId.Recycle]          = true,

    -- CommandStation:GetTechButtons() returns BOTH team-mode research nodes (they sit side by side
    -- on the commander's own grid too, see CommandStation.lua). This window can only ever be open
    -- during a CE round to begin with (GetCEStructureUpgradeAllowed requires GetCombatEngineersActive),
    -- so CombatEngineers is always already researched (nothing to click), and MilitaryProtocol must
    -- be PERMANENTLY unavailable, not merely unaffordable - a CE marine must never be able to research
    -- it from here, and this same list is what the server checks a submitted upgrade against, so
    -- excluding it here is also the authoritative fix, not just the visual one.
    [kTechId.MilitaryProtocol] = true,
    [kTechId.CombatEngineers]  = true,
}

-- Side-agnostic tech tree lookup.
--
-- The global GetTechTree has DIFFERENT signatures per side: on the client (Client.lua) it takes no
-- arguments and returns the local player's tree, but on the server (Server.lua) it is
-- GetTechTree(teamNumber) and returns NIL when called with no team. Calling a bare GetTechTree()
-- from shared code therefore worked client-side and silently returned nil server-side - which made
-- the server reject EVERY upgrade click (no tech node found -> "unavailable"), so nothing happened
-- and no team resources were ever taken. Passing the team number satisfies the server, and the
-- client's parameterless version simply ignores the extra argument.
local function GetTechTreeFor(entity)
    if not entity or not entity.GetTeamNumber then return nil end
    return GetTechTree and GetTechTree(entity:GetTeamNumber()) or nil
end

-- The Arms Lab is deliberately inert: its upgrades are driven entirely by the lab-count ladder and
-- are free, so a paid button there would contradict the mode.
function GetCEStructureUpgradeAllowed(structure)

    if not structure or not structure.GetTechButtons then
        return false
    end

    if structure:isa("ArmsLab") then
        return false
    end

    if structure.GetIsBuilt and not structure:GetIsBuilt() then
        return false
    end

    -- Must be BUILT AND POWERED. An unpowered structure cannot research anything (ResearchMixin's
    -- energy/activation checks would refuse it anyway), so the right-click window should not even
    -- offer to open on one - it would just show a grid of buttons none of which can ever be clicked.
    if structure.GetIsPowered and not structure:GetIsPowered() then
        return false
    end

    return true
end

-- Tech ids to show in the window, in the structure's own button order (so the grid matches the
-- commander's layout for the same structure).
function GetCEStructureUpgradeTechIds(structure)

    local result = {}

    if not GetCEStructureUpgradeAllowed(structure) then
        return result
    end

    -- kTechId.RootMenu, not the structure's own tech id: most structures' GetTechButtons ignore the
    -- argument entirely and derive their state from self:GetTechId() internally (Armory, Extractor,
    -- PrototypeLab, RoboticsFactory), so either value works for them - but Observatory's DOES branch
    -- on the argument (`if techId == kTechId.RootMenu then ... end`, matching how the commander
    -- calls it for its default button page) and returned nothing at all when passed its own tech id,
    -- which was silently emptying the CE upgrade window for every Observatory.
    local techButtons = structure:GetTechButtons(kTechId.RootMenu)
    if not techButtons then
        return result
    end

    local techTree = GetTechTreeFor(structure)

    for _, techId in ipairs(techButtons) do

        if techId and not kExcludedTechIds[techId] then

            local node = techTree and techTree:GetTechNode(techId)

            -- Research, upgrade and manufacture nodes only. Menus, activations and passives are not
            -- things a field marine can "buy" on a structure.
            if node and (node:GetIsResearch() or node:GetIsUpgrade() or node:GetIsManufacture()) then
                table.insert(result, techId)
            end
        end
    end

    return result
end

-- Can this specific upgrade be started right now? Split into two reasons so the window can show
-- GREY (tech unavailable) and RED (unaffordable) distinctly, as the commander grid does.
--   available  - prerequisites met and the structure is idle
--   affordable - the team can pay the t-res cost
function GetCEStructureUpgradeState(structure, techId, player)

    local techTree = GetTechTreeFor(structure)
    local node     = techTree and techTree:GetTechNode(techId)

    if not node or not structure then
        return false, false, 0
    end

    local cost = GetCostForTech(techId) or 0

    local available = node:GetAvailable()
                      and not node:GetResearched()
                      and not node:GetResearching()
                      and (structure.GetCanResearch == nil or structure:GetCanResearch(techId))

    local teamRes = 0
    if player then
        local teamInfo = GetTeamInfoEntity(player:GetTeamNumber())
        teamRes = (teamInfo and teamInfo:GetTeamResources()) or 0
    end

    return available, teamRes >= cost, cost
end

if Client then

    local kMenuScriptName = "CNBalance/GUI/GUICEStructureUpgradeMenu"
    local gUpgradeMenu = nil

    function CEStructureUpgrade_GetIsOpen()
        return gUpgradeMenu ~= nil
    end

    function CEStructureUpgrade_Close()
        if gUpgradeMenu then
            GetGUIManager():DestroyGUIScript(gUpgradeMenu)
            gUpgradeMenu = nil
        end
    end

    function CEStructureUpgrade_Open(structure)

        if gUpgradeMenu or not structure then
            return false
        end

        gUpgradeMenu = GetGUIManager():CreateGUIScript(kMenuScriptName)
        gUpgradeMenu:SetStructure(structure)

        return true
    end

    -- The structure a marine is currently aiming at, if it is a friendly, built, upgradeable one in
    -- range. Returns nil otherwise, which is the signal for right-click to fall through to its
    -- normal behaviour (switching back to the previous weapon).
    function CEStructureUpgrade_GetTargetStructure(player)

        if not player or not GetCombatEngineersActive(player) then
            return nil
        end

        local viewCoords = player:GetViewCoords()
        local startPoint = player:GetEyePos()
        local endPoint   = startPoint + viewCoords.zAxis * kCombatEngineersUpgradeRange

        local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Select,
                                      PhysicsMask.AllButPCsAndRagdolls, EntityFilterOne(player))

        local structure = trace.entity

        if not structure
           or structure:GetTeamNumber() ~= player:GetTeamNumber()
           or not GetCEStructureUpgradeAllowed(structure) then
            return nil
        end

        return structure
    end

end

if Server then

    -- Authoritative. Everything the window checked is checked again here: it is all client input.
    Server.HookNetworkMessage("CEStructureUpgrade", function(client, message)

        local player = client and client:GetControllingPlayer()
        if not player or not player:isa("Marine") then
            return
        end

        local team = player:GetTeam()
        if not team or not team.IsCombatEngineers or not team:IsCombatEngineers() then
            return
        end

        -- Must be holding a Combat Builder, as the window requires.
        if not player:GetWeapon(CombatBuilder.kMapName) then
            return
        end

        local structure = Shared.GetEntity(message.entityId)
        if not structure or not GetCEStructureUpgradeAllowed(structure) then
            return
        end

        -- Same team, and still in range: the marine could have walked away between opening the
        -- window and clicking.
        if structure:GetTeamNumber() ~= player:GetTeamNumber() then
            return
        end

        if (structure:GetOrigin() - player:GetOrigin()):GetLength() > kCombatEngineersUpgradeRange * 1.5 then
            return
        end

        -- The tech must be one this structure actually offers - not merely any researchable id.
        local allowed = false
        for _, techId in ipairs(GetCEStructureUpgradeTechIds(structure)) do
            if techId == message.techId then
                allowed = true
                break
            end
        end

        if not allowed then
            return
        end

        local techTree = team:GetTechTree()
        local node     = techTree and techTree:GetTechNode(message.techId)
        if not node then
            return
        end

        local available, affordable, cost = GetCEStructureUpgradeState(structure, message.techId, player)
        if not available or not affordable then
            return
        end

        -- Deliberately NOT routed through Commander:AttemptToResearchOrUpgrade: that is a Commander
        -- method assuming commander context (selection, menus, alerts). This is the same short
        -- sequence it ends up performing, without the commander-only scaffolding.
        structure:SetResearching(node, player)
        node:SetResearching(true)
        techTree:SetTechNodeChanged(node, "researching = true")

        team:AddTeamResources(-cost)

        -- Arms Lab ladder techs (A1..W3) never reach this handler at all - GetCEStructureUpgradeAllowed
        -- refuses ArmsLab outright (its research is auto-started by the lab-count ladder in
        -- CombatEngineers_Team.lua, which has its own dedicated ce_a1..ce_w3 sounds), so every research
        -- that gets here is by definition a normal paid CB right-click purchase. Private to the buyer.
        Server.PlayPrivateSound(player, kCombatEngineersTechPurchasedSound, player, 1.0, Vector(0, 0, 0))

    end)

end
