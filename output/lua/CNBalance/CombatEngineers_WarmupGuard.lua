-- CNBalance/CombatEngineers_WarmupGuard.lua
-- TechNode:GetResearched() and TechNode:GetHasTech() both hard-code "if GetWarmupActive() then
-- return true end" (vanilla TechNode.lua), so that pre-game "all tech" cheat mode lets players buy
-- and use anything. For MOST tech that is harmless and intentional. For the two mutually exclusive
-- team-mode researches it is not: it made the pre-game report BOTH Military Protocol and Combat
-- Engineers as already researched, which cascaded into real bugs - marines got the full CE build
-- menu and Combat Builder before any commander had chosen anything, which is what actually crashed
-- the client (GUIMarineBuildMenu indexing a structure list that assumed a real round state).
--
-- This is the single, central fix: these tech ids are carved out of the warmup shortcut here, at
-- its only two call sites, rather than re-deriving "is it actually warmup" in every caller that
-- happens to check their state (which is exactly how the bug above slipped through in the first
-- place - a guard was added in several places, but not this one).
--
-- kTechId.CombatBuilderTech is exempted for the same reason as the two team modes: the Armory's
-- buy node for CombatBuilder is gated on GetHasTech(player, CombatBuilderTech), so the warmup
-- shortcut let a marine buy and equip a Combat Builder before any commander or vote had actually
-- researched it - which is what fed the pre-game GUIMarineBuildMenu crash in the first place. Unlike
-- the two mode techs, CombatBuilderTech's OWN CombatBuilder buy node stays exempt too implicitly:
-- LookupTechData-driven buy availability reads THIS node's hasTech, so nothing extra is needed here.
local kWarmupExemptTechIds =
{
    [kTechId.MilitaryProtocol]  = true,
    [kTechId.CombatEngineers]   = true,
    [kTechId.CombatBuilderTech] = true,
}

local baseGetResearched = TechNode.GetResearched

function TechNode:GetResearched()

    if kWarmupExemptTechIds[self.techId] and GetWarmupActive() then
        return self.researched == true
    end

    return baseGetResearched(self)
end

local baseGetHasTech = TechNode.GetHasTech

function TechNode:GetHasTech()

    if kWarmupExemptTechIds[self.techId] and GetWarmupActive() then
        return self.hasTech == true
    end

    return baseGetHasTech(self)
end
