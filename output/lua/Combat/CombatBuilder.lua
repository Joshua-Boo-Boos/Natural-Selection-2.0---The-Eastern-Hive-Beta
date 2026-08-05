Script.Load("lua/Combat/SentryAbility.lua")
Script.Load("lua/Combat/ArmoryAbility.lua")
Script.Load("lua/Combat/CEStructureAbilities.lua")
Script.Load("lua/PickupableWeaponMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/BuilderVariantMixin.lua")
Script.Load("lua/PointGiverMixin.lua")

class 'CombatBuilder' (Weapon)

local kDropCooldown = 1

local kAnimationGraph = PrecacheAsset("models/marine/welder/welder_view.animation_graph")
CombatBuilder.kViewModel = GenerateMarineViewModelPaths("welder")

CombatBuilder.kMapName = "combatbuilder"
CombatBuilder.kModelName = PrecacheAsset("models/marine/welder/builder_sandstorm.model")

local kCreateFailSound = PrecacheAsset("sound/NS2.fev/alien/gorge/create_fail")

-- Index in this list IS the structureIndex sent over the network, so entries must never be
-- reordered or conditionally omitted: the list is the SAME in every round, and Combat Engineers
-- structures are hidden in non-CE rounds by their IsAllowed check (and by the build menu's
-- visibility filter), not by shortening the list.
--
-- The ten CE structures come FIRST and the two vanilla Combat structures (Sentry, Supply Depot)
-- LAST, so in the build menu's 5-per-page layout Sentry Battery and Command Station (the first two
-- entries in kCEStructureAbilityOrder) land on page 1 where Sentry/Supply Depot used to be, and
-- Sentry/Supply Depot land on page 3 where Sentry Battery/Command Station used to be.
CombatBuilder.kSupportedStructures = {}

for _, ability in ipairs(kCEStructureAbilityOrder) do
    table.insert(CombatBuilder.kSupportedStructures, ability)
end

table.insert(CombatBuilder.kSupportedStructures, SentryAbility)
table.insert(CombatBuilder.kSupportedStructures, ArmoryAbility)

local kPhaseGateBlockRadius = 2.4

-- ============================================================
-- Structure cost (personal resources)
-- ============================================================
-- Sentry and Supply Depot keep their long-standing fixed kTechDataPersonalCostKey prices. Every
-- Combat Engineers structure is priced by the team-size model in CombatEngineers_Shared.lua, and
-- Arms Labs additionally by LADDER POSITION - the Nth lab carries the research it unlocks for free,
-- so it costs more than the last.
--
-- Both sides compute this identically: the lab count comes from the networked MarineTeamInfo counter
-- rather than from counting entities, which client-side would miss labs outside relevance range.
function CombatBuilder.GetArmsLabIndexForTeam(teamNumber)

    local teamInfo = GetTeamInfoEntity(teamNumber)
    local built = (teamInfo and teamInfo.numArmsLabs) or 0

    return math.min(built + 1, kCombatEngineersMaxArmsLabs)
end

function CombatBuilder.GetStructureCost(techId, teamNumber, scalarOverride)

    if not kCombatEngineersStructureBaseCost or not GetCombatEngineersStructureCost then
        return LookupTechData(techId, kTechDataPersonalCostKey, 0)
    end

    local armsLabIndex = (techId == kTechId.ArmsLab) and CombatBuilder.GetArmsLabIndexForTeam(teamNumber) or nil

    return GetCombatEngineersStructureCost(techId, teamNumber, armsLabIndex, scalarOverride)
end

local networkVars =
{
    numSentriesLeft = "private integer (0 to 16)",
    numMiniArmoriesLeft = "private integer (0 to 16)",
	-- numPhaseGatesLeft = string.format("private integer (0 to %d)", kMaxStructures[kTechId.PhaseGate]),
	-- numObservatoriesLeft = string.format("private integer (0 to %d)", kMaxStructures[kTechId.Observatory]),
}

AddMixinNetworkVars(BuilderVariantMixin, networkVars)
AddMixinNetworkVars(PickupableWeaponMixin, networkVars)
AddMixinNetworkVars(PointGiverMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)

function CombatBuilder:GetAnimationGraphName()
    return kAnimationGraph
end

function CombatBuilder:GetActiveStructure()

    if self.activeStructure == nil then
        return nil
    else
        return CombatBuilder.kSupportedStructures[self.activeStructure]
    end

end

function CombatBuilder:OnCreate()

    Weapon.OnCreate(self)
    
    self.dropping = false
    self.activeStructure = nil

    InitMixin(self, BuilderVariantMixin)
    InitMixin(self, PickupableWeaponMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, PointGiverMixin)
    
    if Server then
        self.lastCreatedId = Entity.invalidId
    end
        
    self.numSentriesLeft = 0
    self.numMiniArmoriesLeft = 0
	-- self.numPhaseGatesLeft = 0
    -- self.numObservatoriesLeft = 0
    self.lastClickedPosition = nil
    self.lastClickedNormal = nil

end

function CombatBuilder:OnInitialized()
    Weapon.OnInitialized(self)
    self:SetModel(CombatBuilder.kModelName)
end

function CombatBuilder:GetViewModelName(sex, variant)
    return CombatBuilder.kViewModel[sex][variant]
end

function CombatBuilder:GetAnimationGraphName()
    return kAnimationGraph
end

function CombatBuilder:GetDeathIconIndex()
    return kDeathMessageIcon.CombatBuilder
end

function CombatBuilder:SetActiveStructure(structureNum)

    self.activeStructure = structureNum

    -- A fresh choice from the menu always starts at the POSITION step, never inherits a rotation
    -- lock left over from a previous, different structure (or a cancelled placement of this one).
    self.lastClickedPosition = nil
    self.lastClickedNormal = nil

    -- Belt and braces alongside the explicit reset in MarineBuild_SendSelect: OnUpdateRender
    -- recreates self.buildMenu the moment it is nil (CreateBuildMenu has no other guard), so ANY
    -- path that picks a structure while the chooser is open must also clear menuActive, or the
    -- freshly recreated instance inherits the stale "true" and reopens itself immediately.
    self.menuActive = false

end

function CombatBuilder:GetHasDropCooldown()
    return self.timeLastDrop ~= nil and self.timeLastDrop + kDropCooldown > Shared.GetTime()
end

function CombatBuilder:GetSecondaryTechId()
    return kTechId.None
end

function CombatBuilder:GetNumStructuresBuilt(techId)

    if techId == kTechId.MarineSentry then
        return self.numSentriesLeft
    end
	
	if techId == kTechId.WeaponCache then
        return self.numMiniArmoriesLeft
    end
	
	-- if techId == kTechId.PhaseGate then
    --     return self.numPhaseGatesLeft
    -- end

    -- if techId == kTechId.Observatory then
    --     return self.numObservatoriesLeft
    -- end

    return -1
end

function CombatBuilder:GetNumStructuresCanDrop(techId,player)

    if techId == kTechId.MarineSentry then
        return SentryAbility.GetMaxStructures(nil,player)
    end

    if techId == kTechId.WeaponCache then
        return ArmoryAbility.GetMaxStructures(nil,player)
    end
    
    -- unlimited
    return -1
end

function CombatBuilder:OnPrimaryAttack(player)

    if not Client then return end

    -- OnPrimaryAttack fires every tick the button is held (continuous, not once per press), AND it
    -- fires on every client-side PREDICTION/RECONCILIATION pass of that same tick, not just the one
    -- pass that actually counts. A plain Lua flag on this weapon (self.mouseDown) has no protection
    -- against that second part: prediction replay could run this function's body twice for what was
    -- a single real click, toggling self.menuActive twice and undoing itself - the exact "menu
    -- flickers open and closed, have to time the click just right" bug reported.
    --
    -- Prediction passes are skipped outright, and the press edge is detected with a CLIENT-LOCAL
    -- flag cleared in OverrideInput (which sees the raw input bits every frame). The player's
    -- networked primaryAttackLastFrame is deliberately NOT used: it is a "compensated boolean" the
    -- engine saves and restores around prediction replay, so it can read back false during a held
    -- button and let this fire every frame.
    if Shared.GetIsRunningPrediction() then
        return
    end

    if self.cePrimaryHeld then
        return
    end
    self.cePrimaryHeld = true

    -- The two Combat Builder windows are mutually exclusive. While the upgrade window is up, a left
    -- click belongs to ITS research buttons (handled by its own SendKeyEvent) and must not also
    -- open the structure chooser behind it.
    if CEStructureUpgrade_GetIsOpen and CEStructureUpgrade_GetIsOpen() then
        return
    end

    if self.activeStructure ~= nil then

        if self:PerformPrimaryAttack(player) then
            self.dropping = true
        else
            player:TriggerInvalidSound()
        end

    else

        -- Nothing chosen yet: a click TOGGLES the structure chooser - one click opens it, a second
        -- click (with nothing since selected) closes it again, openable with a further click.
        self:CreateBuildMenu()
        self.menuActive = not self.menuActive

        if self.menuActive then
            if MarineBuild_OnSelect then MarineBuild_OnSelect() end

            -- CE-specific menu-open sound, local to this player only. Deliberately NOT folded into
            -- MarineBuild_OnSelect above - that same function also fires for a plain structure pick
            -- inside the already-open chooser, and this sound is only for the initial open, and only
            -- for a CE Marine (standard/MP Marines share this same chooser for Sentry/Supply Depot).
            if GetCombatEngineersActive(player) then
                Shared.PlaySound(nil, kCombatEngineersBuyStructuresSound)
            end
        else
            if MarineBuild_OnClose then MarineBuild_OnClose() end
        end

    end

end

function CombatBuilder:OnPrimaryAttackEnd(player)

    if not Shared.GetIsRunningPrediction() then

        if Client and self.dropping then
            self:OnSetActive()
        end

        self.dropping = false

    end

end

function CombatBuilder:GetIsDropping()
    return self.dropping
end

function CombatBuilder:GetHUDSlot()
    return 4
end


function CombatBuilder:GetIsDroppable()
    return true
end

function CombatBuilder:Dropped(prevOwner)

    Weapon.Dropped(self, prevOwner)
    -- prevOwner:GetTeam():ClearMarineStructure(prevOwner)

    -- Marks a DELIBERATE drop (the vanilla weapon-drop key), as opposed to simply never having had a
    -- Combat Builder yet this life. CombatEngineers_Team.lua's periodic grant pass checks this flag and
    -- refuses to auto-reissue one while it is set - a CE marine who drops their builder must visit an
    -- Armory/AdvancedArmory (which clears the flag on resupply) to get another, rather than having it
    -- silently reappear within a couple of seconds. A fresh respawn, commander step-down or Exo eject
    -- all create a brand new Marine entity, so this flag naturally starts unset for them - only an
    -- actual drop on a still-living marine sets it.
    if Server and prevOwner and prevOwner.isa and prevOwner:isa("Marine") then
        prevOwner.ceBuilderDropped = true

        -- A CE marine's Combat Builder is standard issue, not loot - leaving it lying in the world
        -- (dropped deliberately, or on death) would let ANY marine pick it up via the normal
        -- WeaponOwnerMixin auto-pickup, including a bot: this mod never auto-grants bots a builder
        -- (Marine:GiveCombatEngineerBuilder checks isVirtual) and bots never buy one (it is not in
        -- MarineBrain_Data.lua's hardcoded purchasable-weapon list), so picking a dropped one up off
        -- the ground was the only way a bot could ever end up holding one. Destroying it immediately
        -- closes that off entirely - the dropper must visit an Armory/AdvancedArmory for a new one.
        if GetCombatEngineersActive(prevOwner) then
            DestroyEntity(self)
            return
        end
    end

    self.dropping = false
    self.activeStructure = nil
    if Server then
        self.lastCreatedId = Entity.invalidId
    end
        
    self.numSentriesLeft = 0
    self.numMiniArmoriesLeft = 0
	-- self.numPhaseGatesLeft = 0
    -- self.numObservatoriesLeft = 0
    self.lastClickedPosition = nil
    self.lastClickedNormal = nil
end


function CombatBuilder:GetHasSecondary(player)
    return true
end

function CombatBuilder:OnSecondaryAttack(player)

    if not player then
        return
    end

    if not (Client and player:GetIsLocalPlayer()) then
        return
    end

    -- Prediction passes REPLAY this same tick's input, so this must be skipped on them or a single
    -- physical click runs the toggle below more than once and undoes itself.
    if Shared.GetIsRunningPrediction() then
        return
    end

    -- Press-edge detection uses a CLIENT-LOCAL field, deliberately NOT the player's networked
    -- secondaryAttackLastFrame. That field is a "compensated boolean" - the engine saves and
    -- RESTORES it around prediction replay, so during a held button it can keep reading back as
    -- false on the client and this function fires every single frame. That is what actually caused
    -- "have to hold right-click to keep the window open": the window was being destroyed and
    -- rebuilt continuously, which also swallowed every click aimed at its research buttons. A plain
    -- local flag, cleared only in OnSecondaryAttackEnd, is not subject to that restore.
    if self.ceSecondaryHeld then
        return
    end
    self.ceSecondaryHeld = true

    -- A second click while the window is already open CLOSES it (matches left-click's toggle).
    if CEStructureUpgrade_GetIsOpen and CEStructureUpgrade_GetIsOpen() then
        CEStructureUpgrade_Close()
        return
    end

    -- Mutually exclusive with the structure chooser: opening the upgrade window closes that one.
    if self.menuActive then
        self.menuActive = false
        if MarineBuild_OnClose then MarineBuild_OnClose() end
    end

    -- Aiming at a friendly, built, POWERED, upgradeable structure in range opens its upgrade window.
    -- Aiming at anything else does NOTHING - right-click is the upgrade-window button while the
    -- Combat Builder is out, and nothing more. (It used to fall through to "switch to primary
    -- weapon" here, which meant every right-click that missed a structure silently put the builder
    -- away.)
    local structure = CEStructureUpgrade_GetTargetStructure and CEStructureUpgrade_GetTargetStructure(player)

    if structure then
        CEStructureUpgrade_Open(structure)
    end
end

function CombatBuilder:OnSecondaryAttackEnd(player)
    -- The ceSecondaryHeld guard is cleared in OverrideInput, off the raw input bits - not here.
    Weapon.OnSecondaryAttackEnd(self, player)
end

function CombatBuilder:PerformPrimaryAttack(player)

    if self.activeStructure == nil then
        return false
    end

    local success = false

    -- Ensure the current location is valid for placement.
    local coords, valid = self:GetPositionForStructure(player:GetEyePos(), player:GetViewCoords().zAxis, self:GetActiveStructure(), self.lastClickedPosition, self.lastClickedNormal)

    local structureID = self:GetActiveStructure().GetDropStructureId()
    local ability      = self:GetActiveStructure()

    -- Two-click flow: FIRST click locks position+normal and returns (nothing placed yet, the ghost
    -- starts rotating instead); SECOND click (self.lastClickedPosition already set) confirms the
    -- currently-showing orientation. Structures that don't require it (attach abilities, and
    -- anything still using the legacy kTechDataSpecifyOrientation flag) place on a single click.
    local requiresOrientationClick = (ability.GetRequiresOrientationClick and ability:GetRequiresOrientationClick())
                                     or LookupTechData(structureID, kTechDataSpecifyOrientation, false)

    local secondClick = true
    if requiresOrientationClick then
        secondClick = self.lastClickedPosition ~= nil
    end

    if secondClick then

        if valid then

            -- Ensure they have enough resources. Combat Engineers structures cost NOTHING to place -
            -- every personal resource they need is charged while they are physically being built -
            -- so the check is skipped entirely for them.
             local cost = CombatBuilder.GetStructureCost(structureID, player:GetTeamNumber())
             if GetCombatEngineersStructureHasDynamicCost(structureID) then
                 cost = 0
             end
             if player:GetResources() >= cost then --and not self:GetHasDropCooldown() then
                local message = BuildMarineDropStructureMessage(player:GetEyePos(), player:GetViewCoords().zAxis, self.activeStructure, self.lastClickedPosition, self.lastClickedNormal)
                Client.SendNetworkMessage("MarineBuildStructure", message, true)
                self.timeLastDrop = Shared.GetTime()
                success = true

             end

        end

        -- Placed (or the confirm attempt failed outright) - either way the rotation lock is spent.
        -- On a FAILED confirm the player is left free to click a fresh position rather than being
        -- stuck re-confirming an invalid one.
        self.lastClickedPosition = nil
        self.lastClickedNormal = nil

    else
        -- First click: lock position AND the normal that was used to build these coords (coords'
        -- own yAxis, since Coords.GetLookIn sets yAxis from the surface normal passed to it) so
        -- later frames rotate around a FIXED point instead of the origin continuing to follow the
        -- player's aim.
        self.lastClickedPosition = Vector(coords.origin)
        self.lastClickedNormal = Vector(coords.yAxis)
    end

    if not valid then
        player:TriggerInvalidSound()
    end

    return success
    
end

local function DropStructure(self, player, origin, direction, structureAbility, lastClickedPosition, lastClickedNormal)

    -- If we have enough resources
    if Server then

        local coords, valid, onEntity = self:GetPositionForStructure(origin, direction, structureAbility, lastClickedPosition, lastClickedNormal)
        local techId = structureAbility:GetDropStructureId()
        local maxStructures = structureAbility:GetMaxStructures(self:GetParent())
        
        local isCEStructure = GetCombatEngineersStructureHasDynamicCost(techId)

        -- CE structures are FREE to place - the whole cost is charged while they are physically
        -- being built (ChargeForConstruction in CombatEngineers_Build.lua), recomputed LIVE every
        -- tick from the team's current player count. Nothing is stamped: if the team shrinks
        -- mid-build the structure's price shrinks with it, and p-res already spent can push a
        -- structure that is no longer "full price" straight to completion.
        local cost = isCEStructure and 0 or CombatBuilder.GetStructureCost(techId, player:GetTeamNumber())
        local enoughRes = player:GetResources() >= cost


        if valid and enoughRes and structureAbility:IsAllowed(player) and not self:GetHasDropCooldown() then

            -- Create structure
            local structure = self:CreateStructure(coords, player, structureAbility)
            if structure then

                structure:SetOwner(player)

                -- Marks this as a CE-priced structure and starts its spent-resource ledger. Stamped
                -- BEFORE the kick-off Construct call below, or that first tick would be built free
                -- (the construction charge hook keys off ceIsCombatEngineersStructure being set).
                -- techId is kept too, since ArmsLab needs its LADDER POSITION (fixed at the moment
                -- it was placed - the price of an already-placed lab does not change if more labs
                -- go up after it) to price itself.
                if isCEStructure then
                    structure.ceIsCombatEngineersStructure = true
                    structure.ceResSpent = 0
                    if techId == kTechId.ArmsLab then
                        local team = player:GetTeam()
                        structure.ceArmsLabIndex = team and team.GetArmsLabCount and team:GetArmsLabCount() or 1
                    end
                end

                structure:Construct(0.01,player)

                -- Per-player ownership tracking is only for structures with a PER-PLAYER cap
                -- (Sentry, Supply Depot). CE structures are team property: registering them here
                -- would let AddMarineStructure destroy the oldest one when a player placed another,
                -- and would tear the team's base down when that player left.
                if maxStructures and maxStructures > 0 then
                    player:GetTeam():AddMarineStructure(player, structure,maxStructures)
                end

                -- Check for space
                if structure:SpaceClearForEntity(coords.origin) then

                    local angles = Angles()
                    angles:BuildFromCoords(coords)
                    structure:SetAngles(angles)

                    -- CE structures are paid for during construction, so nothing is taken here.
                    if not isCEStructure then
                        player:AddResources(-cost)
                    end

                    if structureAbility:GetStoreBuildId() then
                        self.lastCreatedId = structure:GetId()
                    end
                    
                    -- self:TriggerEffects("spawn", {effecthostcoords = Coords.GetLookIn(origin, direction)} )
                    
                    if structureAbility.OnStructureCreated then
                        structureAbility:OnStructureCreated(structure, lastClickedPosition)
                    end
                    
                    self.timeLastDrop = Shared.GetTime()

                    -- Only NOW is this a genuinely, successfully placed structure - space was clear
                    -- and its rotation (angles) is set, not merely "reached the rotation-confirm
                    -- click". Private to the placing player only. Gated on the PLAYER being a CE
                    -- Marine using the CB, not on isCEStructure - Marine Sentry and Supply Depot are
                    -- always flat-cost (isCEStructure is false for them), but they are still placed
                    -- via this same CB and still count for a CE Marine.
                    if GetCombatEngineersActive(player) then
                        Server.PlayPrivateSound(player, kCombatEngineersStructurePlacedSound, player, 1.0, Vector(0, 0, 0))
                    end

                    return true
                    
                else
                
                    player:TriggerInvalidSound()
                    DestroyEntity(structure)
                    
                end
                
            else
                player:TriggerInvalidSound()
            end
            
        else
        
            if not valid then
                player:TriggerInvalidSound()
            elseif not enoughRes then
                player:TriggerInvalidSound()
            end
            
        end
        
    end
    
    return true
    
end

function CombatBuilder:OnDropStructure(origin, direction, structureIndex, lastClickedPosition, lastClickedNormal)

    local player = self:GetParent()

    if player then

        local structureAbility = CombatBuilder.kSupportedStructures[structureIndex]
        if structureAbility then
             DropStructure(self, player, origin, direction, structureAbility, lastClickedPosition, lastClickedNormal)
        end

    end

end

function CombatBuilder:CreateStructure(coords, player, structureAbility, lastClickedPosition)
    local created_structure = structureAbility:CreateStructure(coords, player, lastClickedPosition)
    if created_structure then 
        return created_structure
    else
        return CreateEntity(structureAbility:GetDropMapName(), coords.origin, player:GetTeamNumber())
    end
end

local function FilterBabblersAndTwo(ent1, ent2)
    return function (test) return test == ent1 or test == ent2 or test:isa("Babbler") end
end

-- Given a gorge player's position and view angles, return a position and orientation
-- for structure. Used to preview placement via a ghost structure and then to create it.
-- Also returns bool if it's a valid position or not.
function CombatBuilder:GetPositionForStructure(startPosition, direction, structureAbility, lastClickedPosition, lastClickedNormal)

    PROFILE("CombatBuilder:GetPositionForStructure")

    -- Two-click "place then rotate" structures (every free-placement CE structure) LOCK their
    -- position and surface normal at the first click; from then on only the FACING varies as the
    -- player looks around, re-validated every frame (backfacing in particular can flip from valid
    -- to invalid as the player orbits a locked point), until the second click confirms whatever
    -- orientation is currently showing. Attach structures never reach this - GetRequiresOrientationClick
    -- is false for them, so lastClickedPosition is never set for them by PerformPrimaryAttack.
    local rotating = lastClickedPosition ~= nil and lastClickedNormal ~= nil
                     and structureAbility.GetRequiresOrientationClick
                     and structureAbility:GetRequiresOrientationClick()

    local validPosition = false
    local player = self:GetParent()
    local displayOrigin, normal, hitEntity

    if rotating then

        displayOrigin = Vector(lastClickedPosition)
        normal = Vector(lastClickedNormal)
        hitEntity = nil
        validPosition = true

    else

        local range = structureAbility.GetDropRange()
        local origin = startPosition + direction * range

        -- Trace short distance in front
        local trace = Shared.TraceRay(player:GetEyePos(), origin, CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, FilterBabblersAndTwo(player, self))

        displayOrigin = trace.endPoint

        -- If we hit nothing, trace down to place on ground
        if trace.fraction == 1 then

            origin = startPosition + direction * range
            trace = Shared.TraceRay(origin, origin - Vector(0, range, 0), CollisionRep.Default, PhysicsMask.AllButPCsAndRagdolls, EntityFilterTwo(player, self))

        end

        -- Attach abilities (Extractor -> Resource Point, Command Station -> Tech Point) are the one
        -- case where hitting an ENTITY (the attach point's own collision) is expected and correct,
        -- not a foul - GetIsPositionValid below is their sole authority instead of the
        -- bare-world-only rule.
        local allowsAttachEntityHit = structureAbility.GetAllowsAttachEntityHit
                                      and structureAbility:GetAllowsAttachEntityHit()

        -- If it hits something, position on this surface (must be the world or another structure)
        if trace.fraction < 1 then

            if trace.entity == nil or allowsAttachEntityHit then
                validPosition = true
            end

            displayOrigin = trace.endPoint

        end

        if not structureAbility.AllowBackfacing() and trace.normal:DotProduct(GetNormalizedVector(startPosition - trace.endPoint)) < 0 then
            validPosition = false
        end

        -- Don't allow dropped structures to go too close to techpoints and resource nozzles -
        -- EXCEPT for the ability whose entire job is to attach to exactly one (Extractor, Command
        -- Station).
        if not allowsAttachEntityHit and GetPointBlocksAttachEntities(displayOrigin) then
            validPosition = false
        end

        normal    = trace.normal
        hitEntity = trace.entity

    end

    -- Do not allow building too close to any PhaseGate (preview and actual build)
    if validPosition and #GetEntitiesWithinRange("PhaseGate", displayOrigin, kPhaseGateBlockRadius) > 0 then
        validPosition = false
    end

    -- While rotating, re-check backfacing against the CURRENT viewpoint even though the position and
    -- normal are locked - orbiting round to the far side of a locked point can turn a valid facing
    -- invalid, which is exactly the "some rotations are not valid" behaviour a rotation step implies.
    if rotating and not structureAbility.AllowBackfacing()
       and normal:DotProduct(GetNormalizedVector(startPosition - displayOrigin)) < 0 then
        validPosition = false
    end

    if not structureAbility:GetIsPositionValid(displayOrigin, player, normal, lastClickedPosition, hitEntity) then
        validPosition = false
    end

    -- Don't allow placing above or below us and don't draw either
    local structureFacing = Vector(direction)

    if math.abs(Math.DotProduct(normal, structureFacing)) > 0.9 then
        structureFacing = normal:GetPerpendicular()
    end

    -- Coords.GetLookIn will prioritize the direction when constructing the coords,
    -- so make sure the facing direction is perpendicular to the normal so we get
    -- the correct y-axis.
    local perp = Math.CrossProduct( normal, structureFacing )
    structureFacing = Math.CrossProduct( perp, normal )

    local coords = Coords.GetLookIn( displayOrigin, structureFacing, normal )

    if structureAbility.ModifyCoords then
        structureAbility:ModifyCoords(coords, lastClickedPosition)
    end

    return coords, validPosition, hitEntity

end

function CombatBuilder:OnDraw(player, previousWeaponMapName)

    Weapon.OnDraw(self, player, previousWeaponMapName)
	
	-- Attach weapon to parent's hand
    self:SetAttachPoint(Weapon.kHumanAttachPoint)

    self.previousWeaponMapName = previousWeaponMapName
    self.dropping = false
    self.activeStructure = nil

end


function CombatBuilder:OnUpdateAnimationInput(modelMixin)

    PROFILE("CombatBuilder:OnUpdateAnimationInput")
	
	local parent = self:GetParent()
    local sprinting = parent ~= nil and HasMixin(parent, "Sprint") and parent:GetIsSprinting()
    local activity = (self:GetActiveStructure() ~= nil and not sprinting) and "primary" or "none"
    
    modelMixin:SetAnimationInput("activity", activity)
    modelMixin:SetAnimationInput("welder", false)
    
end

function CombatBuilder:UpdateViewModelPoseParameters(viewModel)
    viewModel:SetPoseParam("welder", 0)    
end

function CombatBuilder:OnUpdatePoseParameters(viewModel)

    PROFILE("Welder:OnUpdatePoseParameters")
    self:SetPoseParam("welder", 0)
    
end

-- for marine third person model pose, "builder" fits perfectly for this.
function CombatBuilder:OverrideWeaponName()
    return "builder"
end

function CombatBuilder:ProcessMoveOnWeapon(input)

    -- Show ghost if we're able to create structure, and if menu is not visible
    local player = self:GetParent()
    if player then
    
        if Server then

            -- This is where you limit the number of entities that are alive
			local team = player:GetTeam()
            --local numAllowedSentries = LookupTechData(kTechId.MarineSentry, kTechDataMaxAmount, -1) 
            --local numAllowedMiniArmories = LookupTechData(kTechId.WeaponCache, kTechDataMaxAmount, -1) 
            -- local numAllowedPhaseGates = LookupTechData(kTechId.PhaseGate, kTechDataMaxAmount, -1) 
            -- local numAllowedObservatories = LookupTechData(kTechId.Observatory, kTechDataMaxAmount, -1) 

            --if numAllowedSentries >= 0 then     
                self.numSentriesLeft = team:GetNumDroppedMarineStructures(player, kTechId.MarineSentry)           
            --end
   
            --if numAllowedMiniArmories >= 0 then     
                self.numMiniArmoriesLeft = team:GetNumDroppedMarineStructures(player, kTechId.WeaponCache)           
            --end
            
            -- if numAllowedPhaseGates >= 0 then     
            --     self.numPhaseGatesLeft = team:GetNumDroppedMarineStructures(player, kTechId.PhaseGate)           
            -- end
            
            -- if numAllowedObservatories >= 0 then     
            --     self.numObservatoriesLeft = team:GetNumDroppedMarineStructures(player, kTechId.Observatory)           
            -- end
            
        end
        
    end    
    
end

function CombatBuilder:GetShowGhostModel()
    return self.activeStructure ~= nil and not self:GetHasDropCooldown()
end

function CombatBuilder:GetGhostModelCoords()
    return self.ghostCoords
end   

function CombatBuilder:GetIsPlacementValid()
    return self.placementValid
end

function CombatBuilder:GetGhostModelTechId()

    if self.activeStructure == nil then
        return nil
    else
        return self:GetActiveStructure():GetDropStructureId()
    end

end

if Client then

    function CombatBuilder:GetUIDisplaySettings()
        return { xSize = 512, ySize = 512, script = "lua/GUIWelderDisplay.lua", textureNameOverride = "welder" }
    end

    function CombatBuilder:OnProcessIntermediate(input)

        local player = self:GetParent()
        local viewDirection = player:GetViewCoords().zAxis

        if player and self.activeStructure then

            self.ghostCoords, self.placementValid = self:GetPositionForStructure(player:GetEyePos(), viewDirection, self:GetActiveStructure(), self.lastClickedPosition, self.lastClickedNormal)
            
             local techId = self:GetActiveStructure():GetDropStructureId()

             -- Mirror the server's placement rule exactly: CE structures are FREE to place.
             if not GetCombatEngineersStructureHasDynamicCost(techId) then
                 local cost = CombatBuilder.GetStructureCost(techId, player:GetTeamNumber())
                 if player:GetResources() < cost then
                     self.placementValid = false
                 end
             end
        
        end
        
    end
    
    function CombatBuilder:CreateBuildMenu()
    
        if not self.buildMenu then        
            self.buildMenu = GetGUIManager():CreateGUIScript("Combat/GUIMarineBuildMenu")            
        end
        
    end
    
    function CombatBuilder:DestroyBuildMenu()

        if self.buildMenu ~= nil then
        
            GetGUIManager():DestroyGUIScript(self.buildMenu)
            self.buildMenu = nil
        
        end
    
    end

    function CombatBuilder:OnDestroy()
    
        self:DestroyBuildMenu()        
        Weapon.OnDestroy(self)
        
    end
    
    function CombatBuilder:OnKillClient()
        self.menuActive = false
    end
    
    function CombatBuilder:OnDrawClient()

        Weapon.OnDrawClient(self)

        -- Equipping the builder no longer auto-opens the chooser - only a genuine left CLICK does
        -- (see OnPrimaryAttack). Switching TO this weapon should not carry over a stale "menu open"
        -- state from before it was last holstered, though, so explicitly close it here.
        self.menuActive = false

    end
    
    local function UpdateGUI(self, player)

        local localPlayer = Client.GetLocalPlayer()
        if localPlayer == player then
            self:CreateBuildMenu()
        end
 
        if self.buildMenu then
            self.buildMenu:SetIsVisible(player and localPlayer == player and player:isa("Marine") and self.menuActive)
        end
    
    end

    function CombatBuilder:OnHolsterClient()
    
        self.menuActive = false
        Weapon.OnHolsterClient(self)
        
    end
    
    function CombatBuilder:OnSetActive()
    end
    
    function CombatBuilder:OverrideInput(input)

        -- Re-pressing this weapon's own slot key used to force the chooser back open even when a
        -- structure was already selected (and its ghost showing) - which threw the current
        -- selection away without the player asking for that. Opening is now LEFT-CLICK's job only
        -- (OnPrimaryAttack); re-pressing the slot key while already on this weapon does nothing,
        -- like switching to any other already-active weapon.
        --
        -- self.menuActive is DELIBERATELY not touched here. OnPrimaryAttack's own edge-guarded
        -- toggle is the single source of truth for opening/closing this menu; a selection closes
        -- it via MarineBuild_Close() (which destroys the GUI object outright) inside
        -- GUIMarineBuildMenu:OverrideInput below. Forcing self.menuActive = not selected here used
        -- to fight that: whenever nothing was hit this tick (selected == false, including the tick
        -- right after a click had just TOGGLED the menu closed), it unconditionally forced
        -- menuActive back to true, undoing the close.
        -- Authoritative press-edge tracking for BOTH mouse buttons, driven straight off the raw
        -- input bits. OverrideInput runs every client frame with the real, un-replayed commands, so
        -- clearing the guards here is reliable in a way that depending on OnPrimaryAttackEnd /
        -- OnSecondaryAttackEnd is not: those only fire when the engine's own compensated
        -- primaryAttackLastFrame / secondaryAttackLastFrame flags happen to survive prediction
        -- replay intact, and if one is missed the corresponding guard would latch on forever and
        -- that mouse button would stop working entirely for the rest of the round.
        if not HasMoveCommand( input.commands, Move.PrimaryAttack ) then
            self.cePrimaryHeld = false
        end

        if not HasMoveCommand( input.commands, Move.SecondaryAttack ) then
            self.ceSecondaryHeld = false
        end

        if self.buildMenu and self.buildMenu:GetIsVisible() then
            input = self.buildMenu:OverrideInput(input)
        end

        -- While the structure UPGRADE window is open, strip the attack bits so they never reach the
        -- weapon. A mouse button produces BOTH a key event and a move-command bit: the window's own
        -- SendKeyEvent consumes the key event (which is what actually clicks its research buttons),
        -- but that does nothing about the move bit, which would still reach OnPrimaryAttack and pop
        -- the structure CHOOSER open on top of the upgrade window - the second half of why clicking
        -- a research button appeared to do nothing.
        if CEStructureUpgrade_GetIsOpen and CEStructureUpgrade_GetIsOpen() then
            input.commands = RemoveMoveCommand( input.commands, Move.PrimaryAttack )
            -- SecondaryAttack is deliberately LEFT ALONE: OnSecondaryAttack is what toggles this
            -- window shut again, so stripping it here would make the window impossible to close.
        end

        return input

    end
    
    function CombatBuilder:OnUpdateRender()
        UpdateGUI(self, self:GetParent())    
    end
    
end

if Server then

    function CombatBuilder:GetIsValidRecipient(recipient)
        return not recipient.isVirtual      --Don't give this to bot
    end
    
    function CombatBuilder:GetDestroyOnKill()
        return true
    end
    
    function CombatBuilder:GetSendDeathMessageOverride()
        return false
    end 
        
end

Shared.LinkClassToMap("CombatBuilder", CombatBuilder.kMapName, networkVars)
