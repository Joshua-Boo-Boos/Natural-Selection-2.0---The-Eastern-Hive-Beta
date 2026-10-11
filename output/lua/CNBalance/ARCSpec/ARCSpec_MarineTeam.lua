--[[
    ARC FACTORY SPECIALISATIONS - the marine tech tree nodes.

    Loaded post lua/MarineTeam.lua, after the mod's own MarineTeam hook and Combat Engineers' wrap, so it extends the final
    InitTechTree. Nodes are added after that function's SetComplete(), exactly as Combat Engineers does: every id here was
    appended to kTechId after all existing ids, so the tech id list stays sorted.

    How the pieces fit, mirroring vanilla's Robotics Factory -> ARC Factory upgrade and the mod's Prototype Lab variants:
      - <Spec>Upgrade is an instanced upgrade research on an ARC Factory; when it completes the factory's tech id becomes
        <Spec>Factory (see ARCSpec_RoboticsFactory.lua).
      - <Spec>Factory inherits ARCRoboticsFactory and RoboticsFactory, so everything that needs those (Sentries, MACs...)
        still sees one.
      - <Spec>ARC is manufactured only at a <Spec>Factory. With every such factory gone its prerequisite fails and it cannot
        be built, until another factory converts.
      - <Spec>1..4 are team research, each needing the one before it, the first needing a <Spec>Factory. While no factory of
        that specialisation exists, no further upgrade can be researched. Specialised ARCs already built keep every level
        researched (ARCSpec.GetUpgradeTier reads the researched flag, not GetHasTech), and a newly converted factory
        continues from the last researched level.
]]

local baseInitTechTree = MarineTeam.InitTechTree
function MarineTeam:InitTechTree()

    baseInitTechTree(self)

    local tree = self.techTree

    -- Appended ids are added in ascending order so the sorted tech id list stays sorted.
    for _, spec in ipairs(ARCSpec.kSpecOrder) do
        tree:AddUpgradeNode(spec.upgrade, kTechId.ARCRoboticsFactory)
    end

    for _, spec in ipairs(ARCSpec.kSpecOrder) do
        tree:AddBuildNode(spec.factory, kTechId.None, kTechId.RoboticsFactory)
        tree:AddTechInheritance(kTechId.RoboticsFactory, spec.factory)
        tree:AddTechInheritance(kTechId.ARCRoboticsFactory, spec.factory)
    end

    for _, spec in ipairs(ARCSpec.kSpecOrder) do
        tree:AddManufactureNode(spec.arc, spec.factory, kTechId.None, true)
    end

    for _, spec in ipairs(ARCSpec.kSpecOrder) do
        local upgrades = spec.upgrades
        tree:AddResearchNode(upgrades[1], spec.factory, kTechId.None)
        tree:AddResearchNode(upgrades[2], upgrades[1], kTechId.None)
        tree:AddResearchNode(upgrades[3], upgrades[2], kTechId.None)
        tree:AddResearchNode(upgrades[4], upgrades[3], kTechId.None)
    end

end

if Server then

    --[[
        THE RESEARCH TRAY STATE (commander / spectator HUD, see ARCSpec_Production.lua). Checked once a second; sent to
        every client when it changes, and every kStateResendInterval anyway so a player who joins mid-round gets it.
          state  0 never had a factory of that specialisation, 1 one stands, 2 had one but all are gone (lost)
          level  upgrades researched (0-4), kept while lost - they come back with a new factory
    ]]
    local kStateCheckInterval = 1
    local kStateResendInterval = 10

    local function GetSpecState(team, techTree, spec)

        team.arcSpecEverOwned = team.arcSpecEverOwned or {}
        if techTree:GetHasTech(spec.factory) then
            team.arcSpecEverOwned[spec.key] = true
        end

        local state = 0
        if techTree:GetHasTech(spec.factory) then
            state = 1
        elseif team.arcSpecEverOwned[spec.key] then
            state = 2
        end

        local level = 0
        for i = #spec.upgrades, 1, -1 do
            local node = techTree:GetTechNode(spec.upgrades[i])
            if node and node:GetResearched() then
                level = i
                break
            end
        end

        return state, level

    end

    local function SendTeamState(team)

        local techTree = team:GetTechTree()
        if not techTree then return end

        local now = Shared.GetTime()
        if team.arcSpecNextStateCheck and now < team.arcSpecNextStateCheck then return end
        team.arcSpecNextStateCheck = now + kStateCheckInterval

        local message = { teamNumber = team:GetTeamNumber() }
        message.hammerState, message.hammerLevel = GetSpecState(team, techTree, ARCSpec.kSpecs.hammer)
        message.vanguardState, message.vanguardLevel = GetSpecState(team, techTree, ARCSpec.kSpecs.vanguard)
        message.infernoState, message.infernoLevel = GetSpecState(team, techTree, ARCSpec.kSpecs.inferno)

        local key = string.format("%d%d%d%d%d%d", message.hammerState, message.hammerLevel, message.vanguardState,
                                  message.vanguardLevel, message.infernoState, message.infernoLevel)

        if key ~= team.arcSpecLastStateKey or now >= (team.arcSpecNextStateResend or 0) then
            team.arcSpecLastStateKey = key
            team.arcSpecNextStateResend = now + kStateResendInterval
            Server.SendNetworkMessage("ARCSpecTeamState", message, true)
        end

    end

    local baseUpdate = MarineTeam.Update
    function MarineTeam:Update(timePassed)
        baseUpdate(self, timePassed)
        SendTeamState(self)
    end

    -- A new round starts clean: no specialisation has been owned yet.
    local baseResetTeam = MarineTeam.ResetTeam
    if baseResetTeam then
        function MarineTeam:ResetTeam(...)
            self.arcSpecEverOwned = nil
            self.arcSpecLastStateKey = nil
            self.arcSpecNextStateResend = nil
            return baseResetTeam(self, ...)
        end
    end

end
