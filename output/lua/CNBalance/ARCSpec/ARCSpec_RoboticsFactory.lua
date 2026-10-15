--[[
    ARC FACTORY SPECIALISATIONS - the Robotics Factory side.

    Loaded post lua/RoboticsFactory.lua, after the mod's own RoboticsFactory hook, so every function here wraps the mod's.

    THE 2x4 GRID (root level only, no submenus):
      ARC Factory (unspecialised):
          [Hammerworks] [Vanguard] [Inferno] [ ]
          [Buy ARC    ] [        ] [       ] [ ]
        Starting one conversion hides the other two. When it finishes the factory's tech id becomes the specialised one.

      Specialised factory:
          [Upgrade 1] [Upgrade 2] [Upgrade 3] [Upgrade 4]
          [Buy <specialised ARC>] [ ] [ ] [ ]
        Upgrades are research nodes chained 1 -> 2 -> 3 -> 4 (ARCSpec_MarineTeam.lua), so only the next one in order can
        be started; a researched upgrade's button is cleared and the rest keep their places.
]]

local kEmptyGrid = function()
    return { kTechId.None, kTechId.None, kTechId.None, kTechId.None,
             kTechId.None, kTechId.None, kTechId.None, kTechId.None }
end

local baseGetTechButtons = RoboticsFactory.GetTechButtons

-- (2026-10-14, Siege port) A mod whose own ARC Factory buttons include Buy MAC (Siege puts the MAC button back on ARC
-- Factories) keeps it, in the bottom row next to Buy ARC. NS2.0-TEH Main/Beta/Event have no MAC button there, so
-- nothing changes for them.
local function GetBaseHasMAC(self, techId)
    local ok, base = pcall(baseGetTechButtons, self, techId)
    if not ok or type(base) ~= "table" then return false end
    for _, buttonTechId in ipairs(base) do
        if buttonTechId == kTechId.MAC then return true end
    end
    return false
end

function RoboticsFactory:GetTechButtons(techId)

    local myTechId = self:GetTechId()

    if myTechId == kTechId.ARCRoboticsFactory then

        local buttons = kEmptyGrid()

        -- While a conversion is running only its own button stays (the others disappear, as requested).
        local researchingId = self.GetIsResearching and self:GetIsResearching() and self:GetResearchingId() or nil
        local converting = researchingId and ARCSpec.kSpecByUpgrade[researchingId] or nil

        for i, spec in ipairs(ARCSpec.kSpecOrder) do
            if not converting or converting == spec then
                buttons[i] = spec.upgrade
            end
        end

        buttons[5] = kTechId.ARC
        if GetBaseHasMAC(self, techId) then buttons[6] = kTechId.MAC end
        return buttons

    end

    local spec = ARCSpec.kSpecByFactory[myTechId]
    if spec then

        local buttons = kEmptyGrid()

        for i, upgradeTechId in ipairs(spec.upgrades) do
            if not GetHasTech(self, upgradeTechId, true) then
                buttons[i] = upgradeTechId
            end
        end

        buttons[5] = spec.arc
        if GetBaseHasMAC(self, techId) then buttons[6] = kTechId.MAC end
        return buttons

    end

    return baseGetTechButtons(self, techId)

end

local baseGetTechAllowed = RoboticsFactory.GetTechAllowed
function RoboticsFactory:GetTechAllowed(techId, techNode, player)

    local allowed, canAfford = baseGetTechAllowed(self, techId, techNode, player)
    local myTechId = self:GetTechId()

    if ARCSpec.kSpecByUpgrade[techId] then

        -- One conversion per factory, and only from a plain ARC Factory.
        allowed = allowed and myTechId == kTechId.ARCRoboticsFactory

    else

        local arcSpec = ARCSpec.kSpecByARC[techId]
        if arcSpec then

            -- A specialised ARC is built only at a factory of its own specialisation, inside the global ARC limit (every
            -- ARC of every type counts towards kMaxARCs).
            allowed = allowed and myTechId == arcSpec.factory
            allowed = allowed and #GetEntitiesForTeam("ARC", self:GetTeamNumber()) < kMaxARCs

        else

            local upgradeSpec = ARCSpec.kSpecByUpgradeTech[techId]
            if upgradeSpec then
                allowed = allowed and myTechId == upgradeSpec.factory
            end

        end

    end

    return allowed, canAfford

end

if Server then

    -- The mod gives every Robotics Factory except an ARC Factory a free MAC. A specialised factory is still an ARC Factory.
    local baseOnUpdate = RoboticsFactory.OnUpdate
    function RoboticsFactory:OnUpdate(deltaTime)
        if ARCSpec.kSpecByFactory[self:GetTechId()] then
            return
        end
        if baseOnUpdate then
            return baseOnUpdate(self, deltaTime)
        end
    end

    -- A conversion's progress shows on the specialised factory's node (vanilla does the same for the ARC Factory upgrade).
    local baseUpdateResearch = RoboticsFactory.UpdateResearch
    function RoboticsFactory:UpdateResearch(deltaTime)

        local spec = ARCSpec.kSpecByUpgrade[self:GetResearchingId()]
        if spec then

            local team = self:GetTeam()
            local techTree = team and team:GetTechTree()
            local node = techTree and techTree:GetTechNode(spec.factory)
            if node then
                node:SetResearchProgress(self.researchProgress)
                techTree:SetTechNodeChanged(node, string.format("researchProgress = %.2f", self.researchProgress))
            end
            return

        end

        if baseUpdateResearch then
            return baseUpdateResearch(self, deltaTime)
        end

    end

    local baseOnResearchCancel = RoboticsFactory.OnResearchCancel
    function RoboticsFactory:OnResearchCancel(researchId)

        local spec = ARCSpec.kSpecByUpgrade[researchId]
        if spec then

            local team = self:GetTeam()
            local techTree = team and team:GetTechTree()
            local node = techTree and techTree:GetTechNode(spec.factory)
            if node then
                node:ClearResearching()
                techTree:SetTechNodeChanged(node, string.format("researchProgress = %.2f", 0))
            end
            return

        end

        if baseOnResearchCancel then
            return baseOnResearchCancel(self, researchId)
        end

    end

    local baseOnResearchComplete = RoboticsFactory.OnResearchComplete
    function RoboticsFactory:OnResearchComplete(researchId)

        local spec = ARCSpec.kSpecByUpgrade[researchId]
        if spec then
            if self:GetTechId() == kTechId.ARCRoboticsFactory then
                self:UpgradeToTechId(spec.factory)
            end
            return
        end

        if baseOnResearchComplete then
            return baseOnResearchComplete(self, researchId)
        end

    end

end

--[[
    Building a specialised ARC. The entity is created exactly as a normal ARC is (map name "arc", owner, rollout), then given
    its specialised tech id. self.researchId is the FACTORY's own record of what it is rolling out (vanilla reads its map
    name in ManufactureEntity), so it is pointed at the normal ARC for the creation.
]]
local baseOverrideCreateManufactureEntity = RoboticsFactory.OverrideCreateManufactureEntity
function RoboticsFactory:OverrideCreateManufactureEntity(techId)

    local spec = ARCSpec.kSpecByARC[techId]
    if not spec then
        return baseOverrideCreateManufactureEntity(self, techId)
    end

    self.researchId = kTechId.ARC
    self.open = true

    self.builtEntity = self:ManufactureEntity()

    if self.builtEntity and Server and self.builtEntity.SetTechId then
        self.builtEntity:SetTechId(spec.arc)
    end

    return self.builtEntity

end
