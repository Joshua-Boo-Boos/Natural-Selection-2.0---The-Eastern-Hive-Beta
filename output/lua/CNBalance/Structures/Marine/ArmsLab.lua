Script.Load("lua/BiomassHealthMixin.lua")

local baseOnCreate = ArmsLab.OnCreate
function ArmsLab:OnCreate()
    baseOnCreate(self)
    InitMixin(self, BiomassHealthMixin)
end

function ArmsLab:GetExtraHealth(techLevel,extraPlayers,recentWins)
    return kArmsLabHealthPerPlayerAdd * extraPlayers
end

-- ============================================================
-- Combat Engineers
-- ============================================================
-- In a CE round Arms Labs are the team's ENTIRE upgrade path and there are up to six of them, so
-- they are halved in toughness to stay a realistic alien target. Applied here rather than in
-- BalanceHealth.lua so non-CE rounds are completely untouched.
local function GetIsCombatEngineersLab(self)
    local team = self:GetTeam()
    return team ~= nil and team.IsCombatEngineers and team:IsCombatEngineers()
end

if Server then

    -- Max health/armour live as LiveMixin FIELDS seeded from tech data, not as an overridable
    -- getter, so the halving is applied by adjusting those fields. AdjustMaxHealth/AdjustMaxArmor
    -- preserve the current fraction, so a damaged lab stays proportionally damaged.
    --
    -- Guarded by a flag because this runs both when the lab initialises and when Combat Engineers
    -- completes (labs the commander built beforehand are halved too, so the ladder - which counts
    -- every Arms Lab regardless of who paid - never mixes tough and fragile labs).
    function ArmsLab:ApplyCombatEngineersHealth()

        if self.ceHealthApplied or not GetIsCombatEngineersLab(self) then
            return
        end

        self.ceHealthApplied = true

        self:AdjustMaxHealth(math.max(1, math.floor(self:GetMaxHealth() * kCombatEngineersArmsLabHealthScalar)))
        self:AdjustMaxArmor(math.max(0, math.floor(self:GetMaxArmor() * kCombatEngineersArmsLabHealthScalar)))
    end

    local baseOnInitialized = ArmsLab.OnInitialized
    function ArmsLab:OnInitialized()
        if baseOnInitialized then
            baseOnInitialized(self)
        end
        self:ApplyCombatEngineersHealth()
    end

    -- Every event that can change the count of BUILT, POWERED Arms Labs funnels into one recount on
    -- the team. The team recomputes from scratch, so no ordering of these can desync the ladder.
    local function UpdateLadder(self)
        local team = self:GetTeam()
        if team and team.UpdateCombatEngineerTechLevel then
            team:UpdateCombatEngineerTechLevel()
        end
    end

    local baseOnConstructionComplete = ArmsLab.OnConstructionComplete
    function ArmsLab:OnConstructionComplete()
        if baseOnConstructionComplete then
            baseOnConstructionComplete(self)
        end
        UpdateLadder(self)
    end

    --[[
        FORCE-CANCEL an unfinished research when the lab dies, refunding NOTHING.

        ResearchMixin's own OnKill already aborts without a refund, but only `if researchProgress > 0`
        -- a lab killed in the same tick it started still has progress at exactly 0, so nothing would
        -- clear it and the TECH NODE would be left flagged `researching` forever, silently blocking
        -- every future lab on that track from ever starting the same level. Clearing both sides here
        -- makes the cancellation unconditional.

        Deliberately no refund of any kind: no team resources (the research was free, so there is
        nothing to give back) and no personal resources to the marines who built it. Losing a lab
        mid-research loses the whole investment - that is the risk the p-res price is buying.
    ]]
    local function ForceCancelResearch(self)

        local researchingId = self.GetResearchingId and self:GetResearchingId()
        if not researchingId or researchingId == kTechId.None then
            return
        end

        local team     = self:GetTeam()
        local techTree = team and team.GetTechTree and team:GetTechTree()
        local node     = techTree and techTree:GetTechNode(researchingId)

        if node then
            node:ClearResearching(self:GetId())
            techTree:SetTechNodeChanged(node, "researching = false")
            techTree:SetTechChanged()
        end

        if self.ClearResearch then
            self:ClearResearch()
        end

    end

    local baseOnKill = ArmsLab.OnKill
    function ArmsLab:OnKill(attacker, doer, point, direction)
        -- Before the base call, while researchingId is still readable.
        ForceCancelResearch(self)
        if baseOnKill then
            baseOnKill(self, attacker, doer, point, direction)
        end
        -- Deferred by a tick: this entity is still in the team's entity list right now, so an
        -- immediate recount would still see it and the ladder would not drop.
        self:AddTimedCallback(function() UpdateLadder(self) return false end, 0)
    end

    local baseOnDestroy = ArmsLab.OnDestroy
    function ArmsLab:OnDestroy()
        -- A lab can leave by routes other than being killed (recycle, round reset). Same rule.
        ForceCancelResearch(self)
        local team = self:GetTeam()
        if baseOnDestroy then
            baseOnDestroy(self)
        end
        if team and team.UpdateCombatEngineerTechLevel then
            team:UpdateCombatEngineerTechLevel()
        end
    end

    local baseOnPowerOn = ArmsLab.OnPowerOn
    function ArmsLab:OnPowerOn()
        if baseOnPowerOn then
            baseOnPowerOn(self)
        end
        UpdateLadder(self)
    end

    local baseOnPowerOff = ArmsLab.OnPowerOff
    function ArmsLab:OnPowerOff()
        if baseOnPowerOff then
            baseOnPowerOff(self)
        end
        UpdateLadder(self)
    end

    -- The ladder's researches are free and driven entirely by the lab count, so an Arms Lab in a CE
    -- round must never show or accept the normal paid Armor/Weapons buttons.
    local baseGetTechButtons = ArmsLab.GetTechButtons
    function ArmsLab:GetTechButtons(techId)

        if GetIsCombatEngineersLab(self) then
            return { kTechId.None, kTechId.None, kTechId.None, kTechId.None,
                     kTechId.None, kTechId.None, kTechId.None, kTechId.None }
        end

        return baseGetTechButtons and baseGetTechButtons(self, techId) or nil
    end

end

-- ============================================================
-- Networked: which upgrade this Arms Lab already owns
-- ============================================================
-- Combat Engineers ties one completed upgrade to one Arms Lab, and the upgrade window has to GREY
-- ITSELF on a lab that is already occupied. That decision is made on the client, so the client has to
-- know - and nothing already networked carries it: ResearchMixin's researchingId and researchProgress
-- are both zeroed by ClearResearch the moment a research finishes, leaving no trace.
--
-- Added the way the game itself does it - rebuild the class's networkVars and re-link - exactly as
-- this mod already does for Extractor, Exo, Embryo, Hallucination and others.
--
-- The mixin list below MIRRORS VANILLA ArmsLab.lua EXACTLY. Re-linking replaces the class's variable
-- set outright, so any mixin omitted here would silently stop networking for Arms Labs. It is
-- deliberately vanilla's list and not "vanilla plus whatever this mod also InitMixins" -
-- BiomassHealthMixin is init'd on Arms Labs by this file but is NOT in vanilla's networked set, and
-- adding it here would quietly start networking a batch of new variables as a side effect of a
-- one-field change.
local networkVars =
{
    -- kTechId.None when this lab is free. Same type ResearchMixin uses for researchingId.
    ceOwnedTechId = "enum kTechId",

    -- Which upgrade track this lab was placed as: kCombatEngineersTrackNone / Armor / Weapon.
    -- Networked because the client labels the lab and greys its upgrade window from it.
    ceTrackIndex = "integer (0 to 2)",
}

AddMixinNetworkVars(BaseModelMixin, networkVars)
AddMixinNetworkVars(ClientModelMixin, networkVars)
AddMixinNetworkVars(LiveMixin, networkVars)
AddMixinNetworkVars(GameEffectsMixin, networkVars)
AddMixinNetworkVars(FlinchMixin, networkVars)
AddMixinNetworkVars(TeamMixin, networkVars)
AddMixinNetworkVars(LOSMixin, networkVars)
AddMixinNetworkVars(CorrodeMixin, networkVars)
AddMixinNetworkVars(ConstructMixin, networkVars)
AddMixinNetworkVars(ResearchMixin, networkVars)
AddMixinNetworkVars(RecycleMixin, networkVars)
AddMixinNetworkVars(CombatMixin, networkVars)
AddMixinNetworkVars(NanoShieldMixin, networkVars)
AddMixinNetworkVars(ObstacleMixin, networkVars)
AddMixinNetworkVars(DissolveMixin, networkVars)
AddMixinNetworkVars(GhostStructureMixin, networkVars)
AddMixinNetworkVars(PowerConsumerMixin, networkVars)
AddMixinNetworkVars(SelectableMixin, networkVars)
AddMixinNetworkVars(ParasiteMixin, networkVars)

-- Networked fields must have a value from creation or they read as nil on the client.
local baseOnCreateForOwnedTech = ArmsLab.OnCreate
function ArmsLab:OnCreate()
    baseOnCreateForOwnedTech(self)
    self.ceOwnedTechId = kTechId.None
    self.ceTrackIndex  = kCombatEngineersTrackNone or 0
end

--[[
    HOVER NAME: "Weapons Arms Lab" / "Armor Arms Lab".

    The two Combat Engineers Arms Labs are the SAME structure with the same model and differ only by
    the track they research, so on the field there is otherwise nothing to tell them apart - which
    matters, because a player deciding whether to build or defend one needs to know which it is.

    GetUnitNameOverride is the vanilla hook UnitStatusMixin:GetUnitName calls for the WHOLE name, so
    everything else about how the title is drawn - the team colour an alien sees it in, the position
    above the structure, the fade, the health/armour percentage that can replace it - is left to the
    existing unit-status system and is not reimplemented here. Only the text changes. This mirrors
    PrototypeLab:GetUnitNameOverride, which solves the same "which one of these is it" problem.

    ceTrackIndex is a networked field, so the track is known client-side where the name is drawn.
    A lab with no track - a vanilla Arms Lab, or any lab outside a CE round - falls through to the
    ordinary display name and reads exactly as it always has.
]]
function ArmsLab:GetUnitNameOverride(viewer)

    local track = GetCombatEngineersLabTrack and GetCombatEngineersLabTrack(self)

    local unitName
    if track == "weapon" then
        unitName = Locale.ResolveString("CE_ARMS_LAB_WEAPONS")
    elseif track == "armor" then
        unitName = Locale.ResolveString("CE_ARMS_LAB_ARMOR")
    else
        unitName = GetDisplayName(self)
    end

    -- Keep vanilla's "under construction" wording. Deliberately KEEPS the track in the name while
    -- unbuilt, unlike PrototypeLab's override which falls back to the plain name: which track a
    -- half-built lab belongs to is the most useful thing about it, since that is exactly when a
    -- player is deciding whether to finish it. No status line here - a lab that is not built yet is
    -- not doing anything, and "under construction" already says so.
    if HasMixin(self, "Construct") and self.GetIsBuilt and not self:GetIsBuilt() then
        return string.format(Locale.ResolveString("UNBUILT_STRUCTURE"), unitName)
    end

    -- Not a CE lab (vanilla Arms Lab, or any lab outside a CE round): name only, exactly as before.
    if not track then
        return unitName
    end

    --[[
        SECOND LINE: what this particular lab is doing.

        A newline inside the name is genuinely rendered as a second line rather than a stray glyph -
        vanilla's WordWrap joins its lines with a newline character and hands the result straight to
        SetText (Utility.lua), so GUIItem text is multi-line. Everything else about the drawing is untouched,
        so the second line inherits the same colour, centring and position as the first.

        Three states, because research is SEQUENTIAL per track: only one lab of a track researches at
        a time, so a second or third lab genuinely does sit idle waiting its turn, and without a word
        for that state it would look broken rather than deliberate.
    ]]
    local status
    local researchingId = self.GetResearchingId and self:GetResearchingId()

    if researchingId and researchingId ~= kTechId.None then
        status = Locale.ResolveString("CE_ARMS_LAB_RESEARCHING")
    elseif self.ceOwnedTechId and self.ceOwnedTechId ~= kTechId.None then
        status = Locale.ResolveString("CE_ARMS_LAB_RESEARCHED")
    else
        status = Locale.ResolveString("CE_ARMS_LAB_WAITING")
    end

    return unitName .. "\n" .. status
end

Shared.LinkClassToMap("ArmsLab", ArmsLab.kMapName, networkVars)
