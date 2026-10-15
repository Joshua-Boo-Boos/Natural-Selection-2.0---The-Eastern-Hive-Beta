--[[
    ARC FACTORY SPECIALISATIONS - tech ids and the shared definitions every other ARCSpec file reads.

    Loaded post lua/TechTreeConstants.lua (after the mod's own hook there), so kTechId exists and every id below is
    appended before any networked class sizes its techId field from #kTechId.

    NETWORK BUDGET. This feature adds NO networked class and NO network variable:
      - An ARC Factory's specialisation is its tech id (TechMixin's existing networked field), exactly as vanilla turns a
        Robotics Factory into an ARC Factory.
      - An ARC's type is likewise its tech id, so every client knows it for the name, the skin and the tracer.
      - Upgrades live only in the team tech tree (server, plus the commander's own synced copy). They are deliberately NOT
        added to TeamInfo's kRelevantTechIdsMarine bitmask, which is already full.

    The three specialisations:
      hammer   - anti-structure. Shoots structures exactly like the normal ARC; stationary while deployed.
      vanguard - anti-personnel tank. Machine gun and cannon against lifeforms; moves while deployed.
      inferno  - anti-personnel flamethrower tank. Burns lifeforms and structures; moves while deployed.
]]

-- Specialisation researches (one per ARC Factory, instanced like UpgradeRoboticsFactory).
debug.appendtoenum(kTechId, "ARCSpecHammerUpgrade")
debug.appendtoenum(kTechId, "ARCSpecVanguardUpgrade")
debug.appendtoenum(kTechId, "ARCSpecInfernoUpgrade")

-- The specialised ARC Factories (a Robotics Factory tech id, like ARCRoboticsFactory).
debug.appendtoenum(kTechId, "ARCSpecHammerFactory")
debug.appendtoenum(kTechId, "ARCSpecVanguardFactory")
debug.appendtoenum(kTechId, "ARCSpecInfernoFactory")

-- The specialised ARCs (an ARC tech id).
debug.appendtoenum(kTechId, "ARCSpecHammerARC")
debug.appendtoenum(kTechId, "ARCSpecVanguardARC")
debug.appendtoenum(kTechId, "ARCSpecInfernoARC")

-- Four upgrades per specialisation, researched strictly in order.
debug.appendtoenum(kTechId, "ARCSpecHammer1")
debug.appendtoenum(kTechId, "ARCSpecHammer2")
debug.appendtoenum(kTechId, "ARCSpecHammer3")
debug.appendtoenum(kTechId, "ARCSpecHammer4")
debug.appendtoenum(kTechId, "ARCSpecVanguard1")
debug.appendtoenum(kTechId, "ARCSpecVanguard2")
debug.appendtoenum(kTechId, "ARCSpecVanguard3")
debug.appendtoenum(kTechId, "ARCSpecVanguard4")
debug.appendtoenum(kTechId, "ARCSpecInferno1")
debug.appendtoenum(kTechId, "ARCSpecInferno2")
debug.appendtoenum(kTechId, "ARCSpecInferno3")
debug.appendtoenum(kTechId, "ARCSpecInferno4")

ARCSpec = ARCSpec or {}

-- Balance. Specialised ARCs cost 18 team resources and take twice as long as a normal ARC (see ARCSpec_TechData.lua).
ARCSpec.kSpecResearchCost = 15
ARCSpec.kSpecResearchTime = 20
-- (2026-10-14) Every level costs the same and adds about the same power (see ARCSpec_ARC.lua).
ARCSpec.kUpgradeCosts = { 15, 15, 15, 15 }
ARCSpec.kUpgradeTimes = { 40, 40, 40, 40 }
ARCSpec.kARCCost = 18
ARCSpec.kARCBuildTimeScalar = 2

ARCSpec.kSpecs =
{
    hammer =
    {
        key = "hammer",
        upgrade = kTechId.ARCSpecHammerUpgrade,
        factory = kTechId.ARCSpecHammerFactory,
        arc = kTechId.ARCSpecHammerARC,
        upgrades = { kTechId.ARCSpecHammer1, kTechId.ARCSpecHammer2, kTechId.ARCSpecHammer3, kTechId.ARCSpecHammer4 },
        mobile = false,
    },
    vanguard =
    {
        key = "vanguard",
        upgrade = kTechId.ARCSpecVanguardUpgrade,
        factory = kTechId.ARCSpecVanguardFactory,
        arc = kTechId.ARCSpecVanguardARC,
        upgrades = { kTechId.ARCSpecVanguard1, kTechId.ARCSpecVanguard2, kTechId.ARCSpecVanguard3, kTechId.ARCSpecVanguard4 },
        mobile = true,
    },
    inferno =
    {
        key = "inferno",
        upgrade = kTechId.ARCSpecInfernoUpgrade,
        factory = kTechId.ARCSpecInfernoFactory,
        arc = kTechId.ARCSpecInfernoARC,
        upgrades = { kTechId.ARCSpecInferno1, kTechId.ARCSpecInferno2, kTechId.ARCSpecInferno3, kTechId.ARCSpecInferno4 },
        mobile = true,
    },
}

-- Root-grid order of the three specialisation buttons on an unspecialised ARC Factory (left to right).
ARCSpec.kSpecOrder = { ARCSpec.kSpecs.hammer, ARCSpec.kSpecs.vanguard, ARCSpec.kSpecs.inferno }

ARCSpec.kSpecByUpgrade = {}
ARCSpec.kSpecByFactory = {}
ARCSpec.kSpecByARC = {}
ARCSpec.kSpecByUpgradeTech = {}
for _, spec in pairs(ARCSpec.kSpecs) do
    ARCSpec.kSpecByUpgrade[spec.upgrade] = spec
    ARCSpec.kSpecByFactory[spec.factory] = spec
    ARCSpec.kSpecByARC[spec.arc] = spec
    for _, techId in ipairs(spec.upgrades) do
        ARCSpec.kSpecByUpgradeTech[techId] = spec
    end
end

-- The specialisation of an ARC (by its tech id), or nil for a normal ARC. Works on both realms.
function ARCSpec.GetARCSpec(arc)
    return arc and arc.GetTechId and ARCSpec.kSpecByARC[arc:GetTechId()] or nil
end

-- The specialisation of a Robotics Factory (by its tech id), or nil.
function ARCSpec.GetFactorySpec(factory)
    return factory and factory.GetTechId and ARCSpec.kSpecByFactory[factory:GetTechId()] or nil
end

-- Mobile specialisations move while deployed and use their own weapons instead of the siege cannon.
function ARCSpec.GetIsMobileARC(arc)
    local spec = ARCSpec.GetARCSpec(arc)
    return spec ~= nil and spec.mobile == true
end
