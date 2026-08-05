-- CNBalance/CombatEngineers_Build.lua
-- Combat Engineers: the Combat Builder grant, personal-resource construction, and the MAC guard.
-- Loaded post lua/Marine_Server.lua, which is late enough for Marine:InitWeapons and for
-- lua/ConstructMixin.lua (pulled in long before any Marine file).

if Server then

-- ============================================================
-- Every marine spawns with a Combat Builder
-- ============================================================
local function GetTeamIsCombatEngineers(entity)
    local team = entity and entity:GetTeam()
    return team ~= nil and team.IsCombatEngineers ~= nil and team:IsCombatEngineers()
end

-- AUTOMATIC grants only (spawn, the periodic enforcement pass below, a Commander leaving the
-- chair, an Exo player ejecting). Mines and the Combat Builder share HUD slot 4
-- (LayMines:GetHUDSlot() == CombatBuilder:GetHUDSlot() == 4), and Player:AddWeapon silently evicts
-- whatever already occupies a new item's slot - so an unconditional GiveItem here would delete a
-- marine's Mines out from under them the moment CE finished researching or they respawned.
-- A DELIBERATE purchase of the Combat Builder from an Armory/Advanced Armory (the normal buy-node
-- path, Marine:AttemptToBuy -> GiveItem, entirely untouched by this file) is NOT covered by this
-- guard and keeps its existing vanilla behaviour: buying the Combat Builder while holding Mines
-- replaces them, exactly as any other slot-4 item swap always has. Only the AUTOMATIC path is
-- taught to wait instead.
function Marine:GiveCombatEngineerBuilder()

    if not GetTeamIsCombatEngineers(self) then
        return
    end

    -- Bots have no code path to open the build menu or place a ghost, and CombatBuilder itself
    -- refuses them via GetIsValidRecipient. Handing them one would only give them a weapon slot to
    -- get stuck holding.
    if self.isVirtual then
        return
    end

    if self:GetWeapon(CombatBuilder.kMapName) then
        return
    end

    -- A DELIBERATE drop (CombatBuilder:Dropped, the vanilla weapon-drop key) sets this and must NOT
    -- be auto-reissued here - only an Armory/AdvancedArmory resupply (Armory.lua) clears it. Without
    -- this guard, the periodic pass below would hand a dropped builder straight back within
    -- kCombatEngineersBuilderCheckInterval seconds, making the drop key pointless.
    if self.ceBuilderDropped then
        return
    end

    -- Slot 4 is already spoken for by something that is not a Combat Builder (Mines) - leave it
    -- alone. The periodic enforcement pass will grant the Combat Builder automatically the moment
    -- that stops being true (mines used up, dropped, or the marine dies and respawns clean).
    local slotFourWeapon = self:GetWeaponInHUDSlot(4)
    if slotFourWeapon and not slotFourWeapon:isa("CombatBuilder") then
        return
    end

    self:GiveItem(CombatBuilder.kMapName)
end

local baseInitWeapons = Marine.InitWeapons

function Marine:InitWeapons()
    baseInitWeapons(self)
    self:GiveCombatEngineerBuilder()
end

-- Mines and the Combat Builder share HUD slot 4, and WeaponOwnerMixin:AddWeapon evicts whatever
-- already holds a new item's slot by DROPPING it into the world (`self:Drop(hasWeapon, true, true)`),
-- not by destroying it. That is right for a bought weapon, but wrong for the Combat Builder in a CE
-- round: it is standing issue rather than loot, so buying Mines used to leave a Combat Builder lying
-- on the floor for anyone to collect - and the owner still "had" one in the world.
--
-- Removing it FIRST means AddWeapon finds slot 4 empty and drops nothing. Getting it back is already
-- handled: the periodic grant pass in CombatEngineers_Team.lua re-issues a Combat Builder to any
-- field marine whose slot 4 is free, so it returns automatically once the Mines are used up or
-- dropped - no Armory visit required, though visiting one obviously works too.
local baseGiveItem = Marine.GiveItem

function Marine:GiveItem(itemMapName, setActive, suppressError)

    if itemMapName == LayMines.kMapName and GetTeamIsCombatEngineers(self) then

        local builder = self:GetWeapon(CombatBuilder.kMapName)
        if builder then
            self:RemoveWeapon(builder)
            DestroyEntity(builder)
        end

    end

    return baseGiveItem(self, itemMapName, setActive, suppressError)
end

-- ============================================================
-- Personal-resource construction
-- ============================================================
-- A CE-placed structure is FREE to place and starts at 0%. It is built by marines interacting with
-- it (welding), and EVERY personal resource it costs is charged at that point, in proportion to the
-- construction progress each marine personally causes. Any number of marines can contribute at once;
-- each pays only for their own share.
--
-- The price is NOT stamped at placement - it is the structure's CURRENT price (team size, and for an
-- Arms Lab its fixed ladder position), read fresh every tick. Progress is tracked as a running total
-- of PERSONAL RESOURCES SPENT rather than as a locked build-fraction ratio, specifically so that if
-- the team shrinks mid-build (players leaving) and the structure's price drops as a result, res
-- already spent can push it straight to completion - a half-built structure that was fully paid for
-- under a bigger team finishes immediately once the team is small enough that its price has fallen
-- to what was already spent.

-- The structure's price RIGHT NOW, given the team it belongs to.
function GetCombatEngineersStructureCurrentCost(structure)

    local team = structure:GetTeam()
    if not team then return 0 end

    local techId = structure:GetTechId()

    return GetCombatEngineersStructureCost(techId, team:GetTeamNumber(), structure.ceArmsLabIndex, nil)
end

-- Charge the builder for the progress `elapsedTime` would produce under the structure's CURRENT
-- price, and return the elapsed time actually earned this tick (which may be MORE than a naive
-- proportional share if the price has just dropped and past spending covers it). Returns 0 when
-- nothing can be afforded and nothing is already banked.
local function ChargeForConstruction(structure, elapsedTime, builder)

    -- Only players pay, and only players build (MACs are refused outright below).
    if not builder or not builder.GetResources or not builder.AddResources then
        return 0
    end

    local totalCost = GetCombatEngineersStructureCurrentCost(structure)
    if totalCost <= 0 then
        return elapsedTime
    end

    local buildTime = structure:GetTotalConstructionTime()
    if not buildTime or buildTime <= 0 then
        return elapsedTime
    end

    structure.ceResSpent = structure.ceResSpent or 0

    -- Price may have fallen (team shrank) below what is already banked - the structure is simply
    -- done; nothing more to charge, and the build fraction jumps straight to complete below.
    if structure.ceResSpent >= totalCost then
        return buildTime
    end

    local desiredCost = (elapsedTime / buildTime) * totalCost
    local available    = builder:GetResources() or 0

    if available <= 0 then
        return 0
    end

    -- Partial funding: scale the progress down to exactly what they can pay for, rather than
    -- refusing outright. Personal resources are floats, so sub-1-res ticks are not lost to rounding.
    local actualCost = desiredCost
    if available < desiredCost then
        elapsedTime = elapsedTime * (available / desiredCost)
        actualCost  = available
    end

    -- Never bank more than the structure actually needs.
    local remaining = totalCost - structure.ceResSpent
    if actualCost > remaining then
        elapsedTime = elapsedTime * (remaining / actualCost)
        actualCost  = remaining
    end

    builder:AddResources(-actualCost)
    structure.ceResSpent = structure.ceResSpent + actualCost

    return elapsedTime
end

local baseConstruct = ConstructMixin.Construct

function ConstructMixin:Construct(elapsedTime, builder)

    if self.ceIsCombatEngineersStructure then

        elapsedTime = ChargeForConstruction(self, elapsedTime, builder)

        -- Nothing affordable this tick and nothing already banked covers it: no progress, no
        -- resources taken.
        if elapsedTime <= 0 then
            return false, false
        end
    end

    return baseConstruct(self, elapsedTime, builder)
end

end -- if Server

-- ============================================================
-- MACs repair but never construct
-- ============================================================
-- NS2 already splits these cleanly: MAC:UpdateOrders picks kTechId.Construct (via ConstructMixin,
-- only ever while a structure is UNBUILT) or kTechId.Weld / AutoWeld / FollowAndWeld (via
-- WeldableMixin, only for already-built damaged structures). The two never overlap.
--
-- Blocking here rather than zeroing build progress matters: MAC:UpdateOrders filters its
-- construct-target scan through GetCanConstruct, so MACs never even TARGET a CE blueprint instead of
-- pathing to it and miming construction forever. Welding is untouched - a MAC still auto-welds any
-- BUILT CE structure that has taken damage.
local baseGetCanConstruct = ConstructMixin.GetCanConstruct

function ConstructMixin:GetCanConstruct(constructor)

    if self.ceIsCombatEngineersStructure and constructor and constructor:isa("MAC") then
        return false
    end

    return baseGetCanConstruct(self, constructor)
end
