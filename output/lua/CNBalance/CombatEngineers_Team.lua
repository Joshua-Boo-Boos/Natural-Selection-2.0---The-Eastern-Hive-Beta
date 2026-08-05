-- CNBalance/CombatEngineers_Team.lua
-- Combat Engineers: the mode flag, the halved team-resource income, and the Arms Lab upgrade ladder.
-- Loaded post lua/MarineTeam.lua (after the mod's own MarineTeam hook), so MarineTeam:InitTechTree,
-- MarineTeam:CollectTeamResources and MarineTeam:OnResearchComplete all already exist.

-- ============================================================
-- Mode flag
-- ============================================================
-- Mirrors AlienTeam:IsOriginForm() exactly: a cached tech node, tested for researched.
local baseInitTechTree = MarineTeam.InitTechTree

function MarineTeam:InitTechTree()

    baseInitTechTree(self)

    -- Free, and fast enough that a misclick can be cancelled but slow enough to notice.
    self.techTree:AddResearchNode(kTechId.CombatEngineers, kTechId.CommandStation)
    self.combatEngineersTechNode = self.techTree:GetTechNode(kTechId.CombatEngineers)
end

function MarineTeam:IsCombatEngineers()

    -- Warmup makes TechNode:GetResearched() return true for EVERY tech (TechNode.lua:105), so
    -- without this the pre-game would run with halved team resources and the Arms Lab ladder live.
    if GetCombatEngineersWarmup() then
        return false
    end

    return (self.combatEngineersTechNode and self.combatEngineersTechNode:GetResearched()) == true
end

-- "Chosen" includes research still in progress. Without the in-progress half a commander could start
-- both modes inside the 10 second window and end up with both.
function MarineTeam:GetCombatEngineersChosen()
    if not self.combatEngineersTechNode or GetCombatEngineersWarmup() then return false end
    return self.combatEngineersTechNode:GetResearched() or self.combatEngineersTechNode:GetResearching()
end

function MarineTeam:GetMilitaryProtocolChosen()
    if not self.militaryProtocolTechNode or GetCombatEngineersWarmup() then return false end
    return self.militaryProtocolTechNode:GetResearched() or self.militaryProtocolTechNode:GetResearching()
end

-- ============================================================
-- Halved team-resource income
-- ============================================================
-- MarineTeam:CollectTeamResources is ALREADY the per-mode income hook - Military Protocol rewrites
-- income there, and AlienTeam does the same for Origin Form - so CE slots in beside it as an
-- elseif, which structurally guarantees the two modes can never both apply.
local baseCollectTeamResources = MarineTeam.CollectTeamResources

function MarineTeam:CollectTeamResources(teamRes, playerRes, rtActiveCount)

    -- Only TEAM resources are scaled. Halving upstream in PlayingTeam:UpdateResTick would halve
    -- playerRes too, which would wreck the personal-resource structure economy this mode runs on.
    -- (Military Protocol is the mirror image: playerRes = 0, full teamRes.)
    if not self:IsMilitaryProtocol() and self:IsCombatEngineers() then

        -- rtActiveCount > 0 preserves the no-tower starvation floor at full value. When a team holds
        -- no towers PlayingTeam substitutes kTeamResourceWithoutTower (0.5); halving that would make
        -- a comeback from nothing nearly impossible.
        if (rtActiveCount or 0) > 0 then
            teamRes = teamRes * kCombatEngineersTeamResScalar
        end
    end

    baseCollectTeamResources(self, teamRes, playerRes, rtActiveCount)
end

if Server then

-- ============================================================
-- Combat Builder is a standing invariant, not a one-off grant
-- ============================================================
-- Every field marine ALWAYS carries a Combat Builder once CE is active - not just at the moment CE
-- finishes researching. Handing it out once (originally only via Marine:InitWeapons, i.e. on
-- spawn) missed every other way a player can arrive at "field marine, no builder": a Commander
-- stepping down from the chair, an Exo player ejecting back into a Marine/JetpackMarine, or simply
-- dropping the one they had. Rather than hunting down and hooking each of those transformation
-- entry points individually (fragile - it is easy to miss one, which is exactly how the commander
-- case was missed the first time), this re-asserts the invariant for the whole team on a short
-- timer: whoever is currently a field marine and lacks one gets one, covering all of the above (and
-- anything else that can put a marine on the field) from a single place.
--
-- MarineCommander is deliberately EXCLUDED (isa("Marine") is true for it too, since it is a
-- subclass) - the seated commander never carries a Combat Builder; the moment they log out they
-- become a plain Marine entity and are picked up by this same pass.
local kCombatEngineersBuilderCheckInterval = 2

function MarineTeam:UpdateCombatEngineerBuilderGrants()

    if not self:IsCombatEngineers() then return end

    -- GetEntitiesForTeam("Marine", ...) matches the EXACT registered engine classname, which would
    -- silently skip JetpackMarine (its own separate class, if a Marine subclass in Lua terms) - so
    -- this walks every PLAYER on the team and uses :isa(), which is polymorphic, to find anyone who
    -- counts as a field marine instead.
    for _, player in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do
        if player:isa("Marine") and not player:isa("MarineCommander") and player.GiveCombatEngineerBuilder then
            player:GiveCombatEngineerBuilder()
        end
    end

end

local baseTeamUpdate = MarineTeam.Update

function MarineTeam:Update(timePassed)

    baseTeamUpdate(self, timePassed)

    self.timeNextCombatEngineerBuilderCheck = self.timeNextCombatEngineerBuilderCheck or 0
    if Shared.GetTime() >= self.timeNextCombatEngineerBuilderCheck then
        self.timeNextCombatEngineerBuilderCheck = Shared.GetTime() + kCombatEngineersBuilderCheckInterval
        self:UpdateCombatEngineerBuilderGrants()
    end

    -- Fires once, kCombatEngineersExplanationDelay after ce_researched started playing (queued by
    -- OnCombatEngineersResearched below) - a plain Update poll rather than a timed entity callback,
    -- since MarineTeam is not an Entity and has no AddTimedCallback of its own.
    if self.timeCombatEngineersExplanationSound and Shared.GetTime() >= self.timeCombatEngineersExplanationSound then

        self.timeCombatEngineersExplanationSound = nil

        for _, marine in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do
            Server.PlayPrivateSound(marine, kCombatEngineersExplanationSound, marine, 1.0, Vector(0, 0, 0))
        end

    end

end

-- ============================================================
-- Arms Lab ladder
-- ============================================================
-- Tech level is a function of HOW MANY built, powered Arms Labs exist - never of WHICH one died.
--
-- Two numbers are tracked:
--   ceResearchedLevel - a monotonic high-water mark, raised only when a research completes. This is
--                       what makes "techs do not need to be researched again" work.
--   activeLevel       - min(ceResearchedLevel, builtPoweredLabCount). This is what is actually
--                       granted, so losing a lab disables the LATEST tech and regaining one restores
--                       it instantly without re-researching.
--
-- The lab count is recomputed FROM SCRATCH on every relevant event, so no ordering of
-- build/destroy/power/unpower events can leave the team in an inconsistent state.

function MarineTeam:GetBuiltPoweredArmsLabCount()

    local count = 0

    for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do
        if armsLab:GetIsBuilt() and armsLab:GetIsAlive()
           and (not armsLab.GetIsPowered or armsLab:GetIsPowered()) then
            count = count + 1
        end
    end

    return math.min(count, kCombatEngineersMaxArmsLabs)
end

-- Total number of Arms Labs the team owns, built or not. Used for pricing the NEXT one and for
-- enforcing the cap at placement time.
function MarineTeam:GetArmsLabCount()
    return #GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())
end

function MarineTeam:GetCanBuildAnotherArmsLab()
    return self:GetArmsLabCount() < kCombatEngineersMaxArmsLabs
end

-- TOTAL Infantry Portals the team owns, built or not. Deliberately NOT
-- MarineTeam:GetNumActiveInfantryPortals, which counts only ACTIVE ones: an unbuilt blueprint has to
-- count against the cap or players could queue up any number of them.
function MarineTeam:GetInfantryPortalCount()

    local count = 0

    for _, ip in ipairs(GetEntitiesForTeam("InfantryPortal", self:GetTeamNumber())) do
        if ip:GetIsAlive() then
            count = count + 1
        end
    end

    return count
end

function MarineTeam:GetCanBuildAnotherInfantryPortal()
    return self:GetInfantryPortalCount() < kCombatEngineersMaxInfantryPortals
end

-- Find an Arms Lab that can host a research (any built, powered one that is idle).
-- A lab is eligible to host the NEXT ladder research only if it has never hosted one before
-- (ceHasHostedLadderResearch). Without this, ANY idle built+powered lab was picked - including one
-- that had already finished an earlier tech and gone idle again - so a single Arms Lab could end up
-- researching A1, then W1, then A2 and so on by itself. Binding is PERMANENT and per-entity: once a
-- lab has hosted a research, it is retired from hosting any other, for the rest of its life.
--
-- Among the eligible labs, the OLDEST one (lowest entity id, i.e. the one built first) is chosen, so
-- build order maps onto ladder order exactly as long as labs are not dying out of order: the 1st
-- Arms Lab ever built hosts Armor 1, the 2nd hosts Weapons 1, and so on. If a lab dies before its
-- neighbours, the survivors are NOT renumbered or reassigned - only the COUNT of alive labs matters
-- for which techs stay active (see ApplyLadderTechs), never which specific lab is missing. A newly
-- built REPLACEMENT lab is simply the next "never hosted" lab in creation order and takes whatever
-- the next open slot is.
local function GetFreeArmsLab(self)

    local best = nil

    for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do
        if armsLab:GetIsBuilt() and armsLab:GetIsAlive()
           and (not armsLab.GetIsPowered or armsLab:GetIsPowered())
           and not armsLab:GetIsResearching()
           and not armsLab.ceHasHostedLadderResearch then

            if not best or armsLab:GetId() < best:GetId() then
                best = armsLab
            end
        end
    end

    return best
end

-- Apply activeLevel to the tech tree: everything at or below it is researched, everything above is
-- cleared. Called after every recount.
local function ApplyLadderTechs(self, activeLevel)

    local techTree = self:GetTechTree()
    if not techTree then return end

    for level, techId in ipairs(kCombatEngineersArmsLabLadder) do

        local node = techTree:GetTechNode(techId)
        if node then

            local shouldBeResearched = level <= activeLevel

            if node:GetResearched() ~= shouldBeResearched then
                node:SetResearched(shouldBeResearched)
                techTree:SetTechNodeChanged(node, string.format("researched = %s", tostring(shouldBeResearched)))
            end
        end
    end

    -- No manual armour refresh is needed. MarineTeam:Update already recomputes GetArmorLevel(self)
    -- and calls UpdateArmorAmount on every player EVERY TICK, so both losing and regaining an
    -- Armor1..3 node reaches live marines on its own - including the "disabled until another Arms
    -- Lab replaces it" case, which is the whole point of clearing the node rather than tracking a
    -- separate flag.
end

function MarineTeam:UpdateCombatEngineerTechLevel()

    if not self:IsCombatEngineers() then return end

    self.ceResearchedLevel = self.ceResearchedLevel or 0

    local labCount = self:GetBuiltPoweredArmsLabCount()

    -- Lost labs: cancel anything still researching above the new count, then drop the active level.
    if labCount < self.ceResearchedLevel then

        for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do
            local researchingId = armsLab:GetResearchingId()
            if researchingId and table.contains(kCombatEngineersArmsLabLadder, researchingId) then
                armsLab:ClearResearch()
            end
        end
    end

    local activeLevel = math.min(self.ceResearchedLevel, labCount)
    ApplyLadderTechs(self, activeLevel)

    -- Gained labs: start the next research if one is not already running. NO t-res is charged.
    if labCount > self.ceResearchedLevel then

        local nextLevel = self.ceResearchedLevel + 1
        local techId    = kCombatEngineersArmsLabLadder[nextLevel]

        if techId then

            local alreadyResearching = false
            for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do
                if armsLab:GetResearchingId() == techId then
                    alreadyResearching = true
                    break
                end
            end

            if not alreadyResearching then

                local host = GetFreeArmsLab(self)
                local node = host and self:GetTechTree():GetTechNode(techId)

                if host and node then
                    host:SetResearching(node, host)
                    node:SetResearching(true)
                    self:GetTechTree():SetTechNodeChanged(node, "researching = true")

                    -- Retire this lab from ever hosting another ladder research. Permanent for the
                    -- rest of its life, even across power loss/regain - this is the flag that stops
                    -- a single Arms Lab researching A1, then W1, then A2 and so on by itself.
                    host.ceHasHostedLadderResearch = true

                    -- Only reached when a lab COUNT INCREASE genuinely kicks off a new ladder
                    -- research - never for ApplyLadderTechs' instant grants (the CE-conversion seed in
                    -- OnCombatEngineersResearched, or simply catching up to an already-satisfied
                    -- level), since those never pass through this branch at all. Every Marine hears
                    -- their own private copy.
                    local ladderSound = kCombatEngineersArmsLabLadderSounds[nextLevel]
                    if ladderSound then
                        for _, marine in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do
                            Server.PlayPrivateSound(marine, ladderSound, marine, 1.0, Vector(0, 0, 0))
                        end
                    end
                end
            end
        end
    end
end

-- Raise the high-water mark when a ladder research completes, and handle CE itself completing.
local baseOnResearchComplete = MarineTeam.OnResearchComplete

function MarineTeam:OnResearchComplete(structure, researchId)

    -- Base FIRST: it is what actually marks the node researched, so IsCombatEngineers() and the
    -- ladder checks below must run after it or they would read the pre-completion state.
    local result = baseOnResearchComplete(self, structure, researchId)

    if researchId == kTechId.CombatEngineers then
        self:OnCombatEngineersResearched()
        return result
    end

    if not self:IsCombatEngineers() then
        return result
    end

    for level, techId in ipairs(kCombatEngineersArmsLabLadder) do
        if techId == researchId then

            self.ceResearchedLevel = math.max(self.ceResearchedLevel or 0, level)

            -- Recount immediately: a further lab may already be standing and owed the next research.
            self:UpdateCombatEngineerTechLevel()
            break
        end
    end

    return result
end

-- On CE completing, give the team the Combat Builder tech if it does not already have it, and hand
-- every living marine a builder. Also kicks the ladder in case Arms Labs already exist.
-- ce_researched is heard by the WHOLE SERVER (every player, marine, alien or spectator), each their
-- own private copy - unlike every other CE sound, which is scoped to a team or a single player. The
-- explanation is queued kCombatEngineersExplanationDelay seconds later (ce_researched's own runtime,
-- 2.328s, plus the requested 2.5s gap after it finishes - update this if the audio file changes) and
-- fires from MarineTeam:Update above, for every Marine only.
local kCombatEngineersExplanationDelay = 2.328 + 2.5

function MarineTeam:OnCombatEngineersResearched()

    for _, anyPlayer in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
        Server.PlayPrivateSound(anyPlayer, kCombatEngineersResearchedSound, anyPlayer, 1.0, Vector(0, 0, 0))
    end
    self.timeCombatEngineersExplanationSound = Shared.GetTime() + kCombatEngineersExplanationDelay

    local techTree = self:GetTechTree()
    if techTree then
        local node = techTree:GetTechNode(kTechId.CombatBuilderTech)
        if node and not node:GetResearched() then
            node:SetResearched(true)
            techTree:SetTechNodeChanged(node, "researched = true")
        end
    end

    -- Immediate grant so field marines do not wait out the periodic pass's interval for their
    -- first Combat Builder; UpdateCombatEngineerBuilderGrants (above) keeps re-asserting this from
    -- here on, covering everyone this moment misses (mid-respawn, in an Exo, etc).
    self:UpdateCombatEngineerBuilderGrants()

    -- Halve any Arms Labs the commander built BEFORE the mode was chosen. The ladder counts every
    -- Arms Lab regardless of who paid for it, so without this the team could field a mix of tough
    -- and fragile labs granting identical upgrades.
    for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do
        if armsLab.ApplyCombatEngineersHealth then
            armsLab:ApplyCombatEngineersHealth()
        end
    end

    -- Honour research the team already legitimately paid for as standard/MP Marines BEFORE choosing
    -- CE. Starting this at 0 (as if no Arms Lab had ever researched anything) would make
    -- ApplyLadderTechs immediately UN-research every ladder tech the instant CE completes, then force
    -- the team to re-earn them one at a time via a lab's research time - stripping progress that was
    -- already paid for. Instead, seed the level straight from the CURRENT built+powered lab count: 5
    -- built+powered labs means levels 1-5 (A1, W1, A2, W2, A3) apply instantly, in ladder ORDER
    -- (position in kCombatEngineersArmsLabLadder), regardless of which specific techs were actually
    -- researched or in what order - exactly mirroring a fresh CE team that had built 5 labs from
    -- scratch. Level 6 (W3) is correctly withheld until a 6th lab is built and powered.
    self.ceResearchedLevel = math.min(self:GetBuiltPoweredArmsLabCount(), #kCombatEngineersArmsLabLadder)
    self:UpdateCombatEngineerTechLevel()
end

end -- if Server
