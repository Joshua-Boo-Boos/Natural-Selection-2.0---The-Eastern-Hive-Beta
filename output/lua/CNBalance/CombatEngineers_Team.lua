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
-- Broadcast sound helper
-- ============================================================
-- Plays a sound privately to one player, defended against everything that can silently stop a
-- broadcast loop part-way through.
--
-- The CE sounds are delivered by looping over players and calling Server.PlayPrivateSound for each,
-- so ONE bad entity in the middle of that loop takes the sound away from every player after it -
-- which is exactly the "not everyone hears it" symptom. Bots are the obvious hazard: they are real
-- player entities in the list but have no client behind them, and a server running bots hits that on
-- essentially every broadcast. Dead/disconnecting players are the same class of problem.
--
-- Anchoring the sound to the LISTENER (soundParent = the player being played to) rather than to some
-- world position also matters: it puts the emitter at that player's own location, so no one loses it
-- to 3D distance attenuation regardless of where on the map they are.
--[[
    Delegates the whole decision to CombatEngineers_ClaimSound (CombatEngineers_SoundPref.lua): the
    bot guard, the Options -> Mods opt-out, once-per-life for ordinary cues and once-per-round for the
    research cue all live there in one place.

    This used to carry its own copy of the bot guard and the opt-out, which is exactly how two call
    sites drift apart - the once-per-life rule would have had to be written twice and stayed correct
    in both. Playing is now the only thing left here.
]]
local function PlayCombatEngineersSoundFor(player, soundName)

    if not CombatEngineers_ClaimSound or not CombatEngineers_ClaimSound(player, soundName) then
        return
    end

    Server.PlayPrivateSound(player, soundName, player, kCombatEngineersSoundVolume or 1.0, Vector(0, 0, 0))

end

-- Every player on the SERVER - both teams, spectators included - each hearing their own copy.
local function PlayCombatEngineersSoundForEveryone(soundName)

    for _, anyPlayer in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
        PlayCombatEngineersSoundFor(anyPlayer, soundName)
    end

end

-- Every player on this team, each hearing their own copy.
local function PlayCombatEngineersSoundForTeam(self, soundName)

    for _, player in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do
        PlayCombatEngineersSoundFor(player, soundName)
    end

end

--[[
    THE TWO BOUNDARIES THAT CLEAR THE SOUND LEDGERS.

    A LIFE begins at Team.RespawnPlayer - every respawn on every team funnels through it
    (PlayingTeam:RespawnPlayer computes a spawn point and then calls it), so one post-hook covers
    marines, aliens, the initial spawn on joining a team and every respawn after. Deliberately NOT
    hooked on the player entity being created: that also happens on a class change, and a marine
    buying an Exo has not started a new life and should not get the whole set of cues again.

    A ROUND begins at Team.ResetPreservePlayers, which is what NS2Gamerules:ResetGame actually calls
    on both teams (Team.Reset is a different, rarer path and is hooked too rather than guessed at).
    Clearing here rather than from a gamerules hook keeps this next to the respawn hook and away from
    load-order trouble - NS2Gamerules is not loaded yet when the CE files run.
]]
local baseTeamRespawnPlayer = Team.RespawnPlayer

function Team:RespawnPlayer(player, origin, angles)

    local success = baseTeamRespawnPlayer(self, player, origin, angles)

    -- Only on a spawn that actually happened; a refused respawn is not a new life.
    if success and CombatEngineers_ResetSoundHistoryForPlayer then
        CombatEngineers_ResetSoundHistoryForPlayer(player)
    end

    return success
end

local baseTeamReset = Team.Reset

function Team:Reset()

    if CombatEngineers_ResetSoundHistory then
        CombatEngineers_ResetSoundHistory()
    end

    return baseTeamReset(self)
end

local baseTeamResetPreservePlayers = Team.ResetPreservePlayers

function Team:ResetPreservePlayers(techPoint)

    if CombatEngineers_ResetSoundHistory then
        CombatEngineers_ResetSoundHistory()
    end

    return baseTeamResetPreservePlayers(self, techPoint)
end

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

-- The last player to occupy the command chair who is still on this team, or nil. See the tracking in
-- MarineTeam:Update above.
function MarineTeam:GetLastCommander()

    if not self.ceLastCommanderId then
        return nil
    end

    local commander = Shared.GetEntity(self.ceLastCommanderId)
    if commander and commander:isa("Player") then
        return commander
    end

    return nil
end

-- Keep the Combat Builder tech reading as OWNED for as long as Combat Engineers is researched.
--
-- The node is declared with an Armory prerequisite (MarineTeam:InitTechTree), and TechNode:GetHasTech
-- returns self.hasTech, which the tech tree RECOMPUTES from prerequisites. So marking it researched
-- when CE completes is not enough on its own: with no Armory built the recompute clears hasTech again
-- and the J-menu icon stays dark until an Armory happens to exist. In a CE round every marine is
-- issued a builder regardless of whether the team owns an Armory, so the tech being shown as unowned
-- is simply wrong.
--
-- Re-asserted on the periodic pass rather than once at research time, precisely because the recompute
-- can undo it at any point.
function MarineTeam:UpdateCombatEngineerBuilderTech()

    if not self:IsCombatEngineers() then return end

    local techTree = self:GetTechTree()
    local node = techTree and techTree:GetTechNode(kTechId.CombatBuilderTech)

    if not node then return end

    local changed = false

    if not node:GetResearched() then
        node:SetResearched(true)
        changed = true
    end

    if not node:GetHasTech() then
        node:SetHasTech(true)
        changed = true
    end

    if changed then
        techTree:SetTechNodeChanged(node, "researched = true")
    end

end

function MarineTeam:UpdateCombatEngineerBuilderGrants()

    if not self:IsCombatEngineers() then return end

    self:UpdateCombatEngineerBuilderTech()

    -- GetEntitiesForTeam("Marine", ...) matches the EXACT registered engine classname, which would
    -- silently skip JetpackMarine (its own separate class, if a Marine subclass in Lua terms) - so
    -- this walks every PLAYER on the team and uses :isa(), which is polymorphic, to find anyone who
    -- counts as a field marine instead.
    for _, player in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do

        if player:isa("Marine") and not player:isa("MarineCommander") then

            -- SAFETY NET: strip a Combat Builder off any bot that has somehow acquired one.
            --
            -- Every known route is blocked at Marine:GiveItem, but this runs every couple of seconds
            -- and removes one regardless of HOW it was obtained - a route nobody anticipated, a
            -- server-side gift, an entity that existed before a fix landed, anything. Blocking the
            -- doors is the real fix; this is the guarantee that the invariant "no bot ever holds a
            -- Combat Builder" holds in practice even if a door is missed.
            if player.GetIsVirtual and player:GetIsVirtual() then

                local builder = player:GetWeapon(CombatBuilder.kMapName)
                if builder then
                    player:RemoveWeapon(builder)
                    DestroyEntity(builder)
                end

            elseif player.GiveCombatEngineerBuilder then
                player:GiveCombatEngineerBuilder()
            end

        end

    end

end

local baseTeamUpdate = MarineTeam.Update

function MarineTeam:Update(timePassed)

    baseTeamUpdate(self, timePassed)

    -- Remember whoever last held the chair, for as long as they remain on this team. ARCs credit
    -- their kills to this when the chair is empty (ARC:GetOwner in Structures/Marine/ARC.lua); with
    -- nobody ever recorded it stays nil and the killfeed shows the ARC itself, which is the intended
    -- fallback. Cleared when that player leaves the team so a kill is never credited to someone who
    -- has gone to the aliens or to the ready room.
    local currentCommander = self.GetCommander and self:GetCommander()
    if currentCommander then
        self.ceLastCommanderId = currentCommander:GetId()
    elseif self.ceLastCommanderId then
        local remembered = Shared.GetEntity(self.ceLastCommanderId)
        if not remembered or remembered:GetTeamNumber() ~= self:GetTeamNumber() then
            self.ceLastCommanderId = nil
        end
    end

    self.timeNextCombatEngineerBuilderCheck = self.timeNextCombatEngineerBuilderCheck or 0
    if Shared.GetTime() >= self.timeNextCombatEngineerBuilderCheck then
        self.timeNextCombatEngineerBuilderCheck = Shared.GetTime() + kCombatEngineersBuilderCheckInterval
        self:UpdateCombatEngineerBuilderGrants()

        -- Defensive recount on the same tick. Every real change (a lab finishing, dying, gaining or
        -- losing power) already calls this directly from ArmsLab.lua; this just guarantees the levels
        -- cannot stay wrong if some path is ever missed. Cheap: it returns immediately unless CE is
        -- active, and does nothing further unless the levels and the lab count actually disagree.
        self:UpdateCombatEngineerTechLevel()
    end

    -- Fires once, kCombatEngineersExplanationDelay after ce_researched started playing (queued by
    -- OnCombatEngineersResearched below) - a plain Update poll rather than a timed entity callback,
    -- since MarineTeam is not an Entity and has no AddTimedCallback of its own.
    if self.timeCombatEngineersExplanationSound and Shared.GetTime() >= self.timeCombatEngineersExplanationSound then

        self.timeCombatEngineersExplanationSound = nil

        PlayCombatEngineersSoundForTeam(self, kCombatEngineersExplanationSound)

    end

end

-- ============================================================
-- Arms Lab ladder
-- ============================================================
-- Two INDEPENDENT levels are tracked, ceArmorLevel and ceWeaponLevel (each 0..3). Each built,
-- powered Arms Lab supports exactly one level, so their sum can never exceed the lab count.
--
-- Which tech each lab researches is CHOSEN by the marine placing it and paid for in team resources at
-- that moment (see the placement re-check in CombatBuilder.lua), rather than being dictated by a
-- fixed order. What is lost when a lab dies is decided by the shared rule in
-- GetCombatEngineersTechToLose - highest level first, weapons winning ties - deliberately independent
-- of WHICH lab was destroyed.
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

-- Arms Labs on ONE track, built or not. Blueprints count: the track is stamped at placement, so a
-- lab that is queued but not yet standing already occupies its slot on the ladder and cannot be
-- undercut by a second player placing another before the first finishes.
function MarineTeam:GetArmsLabCountForTrack(track)

    local count = 0

    for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do
        if GetCombatEngineersLabTrack(armsLab) == track then
            count = count + 1
        end
    end

    return count
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
local function ApplyTrackTechs(self)

    local techTree = self:GetTechTree()
    if not techTree then return end

    local function ApplyTrack(list, level)

        for i, techId in ipairs(list) do

            local node = techTree:GetTechNode(techId)
            if node then

                local shouldBeResearched = i <= level

                if node:GetResearched() ~= shouldBeResearched then
                    node:SetResearched(shouldBeResearched)
                    techTree:SetTechNodeChanged(node, string.format("researched = %s", tostring(shouldBeResearched)))
                end
            end
        end

    end

    ApplyTrack(kCombatEngineersArmorTrack,  self.ceArmorLevel or 0)
    ApplyTrack(kCombatEngineersWeaponTrack, self.ceWeaponLevel or 0)

    -- No manual armour refresh is needed. MarineTeam:Update already recomputes GetArmorLevel(self)
    -- and calls UpdateArmorAmount on every player EVERY TICK, so both losing and regaining an
    -- Armor1..3 node reaches live marines on its own - including the "disabled until another Arms
    -- Lab replaces it" case, which is the whole point of clearing the node rather than tracking a
    -- separate flag.
end

--[[
    ARMS LAB LADDER, derived from the labs themselves.

    Each CE Arms Lab is placed as a WEAPONS lab or an ARMOUR lab and researches that track on its own.
    A track's level is simply HOW MANY OF ITS LABS HAVE FINISHED RESEARCHING - not a counter that is
    raised on completion and shed on loss. Deriving it fixes two bugs that a stored counter could not:

      * A lab researching level N did nothing when the lab that held level N-1 was destroyed. The
        counter had been shed, so the completion had nothing to attach to. Now completion always
        counts, because the level IS the count -- lose the first lab and the second simply becomes
        level 1.

      * Two labs could both offer to research after one was rebuilt, when one of them should have
        reported its tech as already taken. There is no longer anything to choose: a lab's job is
        fixed by the track it was placed as, so the situation cannot arise.

    A lab counts only while BUILT, ALIVE and POWERED, so losing power behaves exactly like losing the
    lab and is undone the moment power returns.
]]
local function GetCETrackLabs(self)

    local armor, weapon = {}, {}

    for _, armsLab in ipairs(GetEntitiesForTeam("ArmsLab", self:GetTeamNumber())) do

        if armsLab:GetIsBuilt() and armsLab:GetIsAlive()
           and (not armsLab.GetIsPowered or armsLab:GetIsPowered()) then

            local track = GetCombatEngineersLabTrack(armsLab)

            if track == "armor" then
                table.insert(armor, armsLab)
            elseif track == "weapon" then
                table.insert(weapon, armsLab)
            end

        end

    end

    return armor, weapon
end

-- Has this lab finished its research? ceOwnedTechId is set on completion and is the only durable
-- record of it: ResearchMixin zeroes researchingId and researchProgress as soon as a research ends.
local function GetCELabResearchDone(armsLab)
    local owned = armsLab and armsLab.ceOwnedTechId
    return owned ~= nil and owned ~= kTechId.None
end

local function GetCETrackLevel(labs)

    local done = 0

    for _, armsLab in ipairs(labs) do
        if GetCELabResearchDone(armsLab) then
            done = done + 1
        end
    end

    return math.min(done, kCombatEngineersMaxTrackLevel)
end

--[[
    Start the next research on any idle lab of a track.

    The target level is (finished + already researching + 1), so two labs on the same track never
    chase the same upgrade. A lab beyond the third on its track has nothing left to research and
    simply sits idle -- it still counts as a lab for pricing and for the six-lab cap.
]]
local function StartTrackResearch(self, labs, trackList, floor)

    local techTree = self:GetTechTree()
    if not techTree then return end

    -- ResearchMixin:SetResearching does `player:GetId()` unconditionally, so a nil player errors.
    -- Nothing here is initiated by a marine, so any team member serves purely as the attribution
    -- the mixin insists on. If the team is somehow empty the research simply waits for the next
    -- recount, which MarineTeam:Update runs on a timer regardless.
    local researcher = GetEntitiesForTeam("Marine", self:GetTeamNumber())[1]
    if not researcher then return end

    local finished, researching, idle = 0, 0, {}

    for _, armsLab in ipairs(labs) do

        local researchingId = armsLab.GetResearchingId and armsLab:GetResearchingId()

        if GetCELabResearchDone(armsLab) then
            finished = finished + 1
        elseif researchingId and researchingId ~= kTechId.None then
            researching = researching + 1
        else
            table.insert(idle, armsLab)
        end

    end

    -- Never aim below the pre-CE floor: those levels are already researched, and a lab sent after one
    -- of them would burn its whole research on tech the team already has.
    local nextLevel = math.max(finished + researching, floor or 0) + 1

    for _, armsLab in ipairs(idle) do

        if nextLevel > kCombatEngineersMaxTrackLevel then
            break
        end

        local techId = trackList[nextLevel]
        local node   = techId and techTree:GetTechNode(techId)

        -- GetCanResearch keeps ResearchMixin's own rules (idle, powered, not recycling) authoritative
        -- rather than reimplementing them here.
        if node and (not armsLab.GetCanResearch or armsLab:GetCanResearch(techId)) then

            armsLab:SetResearching(node, researcher)
            node:SetResearching(true)
            techTree:SetTechNodeChanged(node, "researching = true")

            nextLevel = nextLevel + 1

        end

    end

end

function MarineTeam:UpdateCombatEngineerTechLevel()

    if not self:IsCombatEngineers() then return end

    local armorLabs, weaponLabs = GetCETrackLabs(self)

    --[[
        The floors protect upgrades the team researched BEFORE Combat Engineers was enabled.

        Those came from an ordinary Arms Lab, which carries no track and so counts toward neither
        side of the derived total. Without a floor, switching CE on mid-game would strip a team of
        armour and weapon levels it had legitimately earned. The floors are seeded once at
        conversion (below) and only ever raised past by CE labs of the team's own.
    ]]
    self.ceArmorLevel  = math.max(GetCETrackLevel(armorLabs),  self.ceArmorFloor  or 0)
    self.ceWeaponLevel = math.max(GetCETrackLevel(weaponLabs), self.ceWeaponFloor or 0)

    ApplyTrackTechs(self)

    -- Kick any idle lab into its next research. Safe to run every recount: a lab that is already
    -- researching or already finished is skipped, so this only ever fills a genuine gap.
    StartTrackResearch(self, armorLabs,  kCombatEngineersArmorTrack,  self.ceArmorFloor  or 0)
    StartTrackResearch(self, weaponLabs, kCombatEngineersWeaponTrack, self.ceWeaponFloor or 0)

end


-- Record the completion on the lab that finished it, then recount. Handles CE itself completing too.
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

    --[[
        A ladder research finishing does NOT raise a counter any more. It only marks THIS LAB as
        done; UpdateCombatEngineerTechLevel then recounts the finished labs on each track and the
        level falls out of that count.

        This is what fixes the "research completed but nothing happened" bug. Previously the level
        was a high-water mark taken from the FINISHED TECH'S OWN LEVEL, so a lab that completed
        Weapons2 after the Weapons1 lab had been destroyed raised the mark to 2 while only one lab
        existed to support it -- and the shed pass immediately took it straight back off, leaving the
        team with nothing to show for the research. Counting labs instead means that same completion
        now simply makes the team's first weapons level, which is the sensible outcome.

        Marked on completion rather than at research start, so a research that is cancelled or
        interrupted leaves the lab free to start over.
    ]]
    local track = GetCombatEngineersTrackForTech(researchId)

    if track then

        if structure then
            structure.ceOwnedTechId = researchId
        end

        self:UpdateCombatEngineerTechLevel()

        -- The ce_a1..ce_w3 voice cue, to the WHOLE TEAM - an armour or weapon level going up affects
        -- everyone. It used to fire from the upgrade handler when a marine STARTED the research; that
        -- handler now refuses ladder techs outright (nobody starts them by hand any more), so without
        -- this the cues would simply never play. Completion is the better moment for them regardless:
        -- it is when the level actually arrives.
        local ladderSound = GetCombatEngineersTechSound and GetCombatEngineersTechSound(researchId)

        if ladderSound and CombatEngineers_PlaySoundForTeamNumber then
            CombatEngineers_PlaySoundForTeamNumber(self:GetTeamNumber(), ladderSound)
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

    PlayCombatEngineersSoundForEveryone(kCombatEngineersResearchedSound)
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
    -- CE. Seeding both tracks at 0 would UN-research everything the instant CE completes and force
    -- the team to buy it all again.
    --
    -- Seed each track's FLOOR from what the team has actually researched already, so a team arriving
    -- with A2 and W1 keeps exactly A2 and W1. CE Arms Labs built from here on add on top of that
    -- floor; nothing can push a track back below it, since those levels were not earned with CE labs
    -- and so are invisible to the lab-derived count.
    self.ceArmorFloor  = GetCombatEngineersTrackLevel(self, "armor")
    self.ceWeaponFloor = GetCombatEngineersTrackLevel(self, "weapon")

    self:UpdateCombatEngineerTechLevel()
end

end -- if Server
