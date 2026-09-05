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

-- The upgrade a lab already owns, or nil. Reads the NETWORKED ceOwnedTechId, so client and server
-- get the same answer with no request/response and no chance of the two disagreeing.
function GetCombatEngineersLabOwnedTech(structure)

    local owned = structure and structure.ceOwnedTechId

    if owned and owned ~= kTechId.None then
        return owned
    end

    return nil
end

function GetCEStructureUpgradeAllowed(structure)

    if not structure or not structure.GetTechButtons then
        return false
    end

    -- The Arms Lab USED to be refused outright here, which meant right-clicking one did nothing at
    -- all - no window, no feedback, indistinguishable from the feature being broken. It now opens
    -- like any other structure and simply reports "no upgrades available", the same as an Infantry
    -- Portal. Its ladder techs (Armor1..Weapons3) stay unbuyable, but that is enforced where it
    -- belongs - in the tech-id filter below - rather than by hiding the whole window.

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

    --[[
        THE ARMS LAB OFFERS NOTHING. Its research is no longer chosen by a marine at all.

        A CE Arms Lab is placed from the Combat Builder menu as either a WEAPONS lab or an ARMOUR
        lab, and starts the next research on its own track the moment it finishes building
        (MarineTeam:UpdateCombatEngineerTechLevel). There is therefore nothing left to pick, and
        returning the six choices here would only re-open the bug this redesign removes: two labs
        both offering the same upgrade, or a lab offering one the team already holds.

        An empty list leaves the upgrade window with no buttons, which is the correct report -- the
        lab's job was decided when it was placed.
    ]]
    if structure:isa("ArmsLab") then
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

    --[[
        Arms Lab ladder techs are never offered here any more, so they are refused outright.

        A CE Arms Lab picks its own research from the track it was placed as, starts it for free the
        moment it finishes building, and lists nothing in its upgrade window. The elaborate rule that
        used to live here - next-step-in-track, no other lab researching it, spare lab capacity, this
        lab not already owning an upgrade - existed only to police a manual choice that no longer
        exists. Refusing is what keeps the server handler honest: even a hand-crafted upgrade message
        naming Armor2 cannot buy a ladder tech, which is what makes them free-and-automatic rather
        than free-and-buyable.
    ]]
    if GetCombatEngineersTrackForTech(techId) then
        return false, false, 0
    end

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

    -- Page flip, driven from CombatBuilder:OverrideInput. The mouse wheel arrives as a MOVE command
    -- (Move.SelectNextWeapon / SelectPrevWeapon), not a key event, so the window cannot see it on its
    -- own - the weapon has to hand it over, exactly as it already does for the build menu.
    function CEStructureUpgrade_ChangePage(delta)

        if gUpgradeMenu and gUpgradeMenu.SetPage then
            gUpgradeMenu:SetPage(gUpgradeMenu:GetPage() + delta)
            return true
        end

        return false
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

    -- "Take Credits": convert a fixed slice of TEAM resources into PERSONAL resources for the marine
    -- who asked. Authoritative - the client sends no payload at all, so every term is established
    -- here.
    Server.HookNetworkMessage("CETakeCredits", function(client, message)

        local player = client and client:GetControllingPlayer()
        if not player or not player:isa("Marine") or player:isa("MarineCommander") then
            return
        end

        if not player:GetIsAlive() then
            return
        end

        -- Same gate as every other Combat Builder action: CE round, and actually holding a builder.
        if not GetCombatEngineersActive(player) then
            return
        end

        if not player:GetWeapon(CombatBuilder.kMapName) then
            return
        end

        local team = player:GetTeam()
        if not team or not team.GetTeamResources or not team.AddTeamResources then
            return
        end

        -- The amount is whatever can actually be exchanged, NOT a fixed 20: a marine on 95 of 100
        -- takes 5 so the other 15 are not burned for nothing, and one already at the cap takes
        -- nothing at all and gets no announcement. Authoritative - the client greys the button on the
        -- same helper, but this is the value that counts.
        local amount = GetCombatEngineersCreditsExchangeAmount(player)

        if amount <= 0 then
            return
        end

        -- Deduct before granting, so a failure part-way can never mint resources.
        team:AddTeamResources(-amount)
        player:AddResources(amount)

        -- Everyone on the team hears it and is told who spent the pool's resources - the same
        -- accountability the alien Origin Form fetch announcement provides.
        -- Everyone EXCEPT the initiator: they already played it locally the instant they clicked
        -- (GUIMarineBuildMenu), so broadcasting to them as well would double it up.
        if CombatEngineers_PlaySoundFor then
            for _, teamPlayer in ipairs(GetEntitiesForTeam("Player", player:GetTeamNumber())) do
                if teamPlayer ~= player then
                    CombatEngineers_PlaySoundFor(teamPlayer, kCombatEngineersCreditsTakenSound)
                end
            end
        end

        if CombatEngineers_SendTeamMessage then
            CombatEngineers_SendTeamMessage(team, CombatEngineers_FormatTeamMessage(
                string.format("%s has taken %d team resources for %d personal resources",
                              player:GetName(), amount, amount)))
        end

    end)

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

        -- Deliberately NOT marking the lab as owning the tech here. Ownership is granted when the
        -- research COMPLETES (MarineTeam:OnResearchComplete); a research still in flight is already
        -- covered by the "this lab is researching" and "no lab is researching this tech" checks
        -- above, so nothing can be double-queued in the meantime - and a research that never
        -- finishes leaves no trace to brick the lab with.

        team:AddTeamResources(-cost)

        -- Arms Lab ladder techs (A1..W3) never reach this handler at all - GetCEStructureUpgradeAllowed
        -- refuses ArmsLab outright (its research is auto-started by the lab-count ladder in
        -- CombatEngineers_Team.lua, which has its own dedicated ce_a1..ce_w3 sounds), so every research
        -- that gets here is by definition a normal paid CB right-click purchase. Private to the buyer.
        -- The six Arms Lab upgrades have their own dedicated voice cue (ce_a1..ce_w3) and it plays to
        -- the WHOLE TEAM, since an armour or weapon level going up affects everyone. Everything else
        -- is a structure upgrade that only concerns the marine who bought it.
        local ladderSound = GetCombatEngineersTechSound and GetCombatEngineersTechSound(message.techId)

        if ladderSound then
            if CombatEngineers_PlaySoundForTeamNumber then
                CombatEngineers_PlaySoundForTeamNumber(player:GetTeamNumber(), ladderSound)
            end
        elseif CombatEngineers_PlaySoundFor then
            CombatEngineers_PlaySoundFor(player, kCombatEngineersTechPurchasedSound)
        end

        if CombatEngineers_SendTeamMessage then

            CombatEngineers_SendTeamMessage(team, CombatEngineers_FormatTeamMessage(
                string.format("%s started the research %s on the %s in %s - The cost to research was %d t-res",
                              player:GetName(),
                              CombatEngineers_GetDisplayName(message.techId),
                              CombatEngineers_GetDisplayName(structure:GetTechId()),
                              CombatEngineers_GetLocationName(structure:GetOrigin()),
                              cost)))

        end

    end)

end
