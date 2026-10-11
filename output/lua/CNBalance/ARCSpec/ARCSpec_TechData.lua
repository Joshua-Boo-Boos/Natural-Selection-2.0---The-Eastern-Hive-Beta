--[[
    ARC FACTORY SPECIALISATIONS - tech data (names, tooltips, costs, research times).

    Loaded post lua/TechData.lua, after the mod's own TechData hooks, so this BuildTechData wraps theirs.

    The specialised ARC Factories and ARCs are built by COPYING the live ARCRoboticsFactory / ARC entries (whatever the mod
    has made them), so their health, armour, supply, model and point value can never drift from the normal ones.

    kTechDataMapName is deliberately LEFT OUT of every copied entry. TechMixin gives a newly created entity the tech id
    whose map name matches (LookupTechId), so a second "arc" map name could hand a plain ARC one of these ids. The specialised
    ids are only ever set explicitly (RoboticsFactory and ARC hooks), never looked up by map name.
]]

local function CopyEntry(techData, sourceTechId)
    for _, entry in ipairs(techData) do
        if entry[kTechDataId] == sourceTechId then
            local copy = {}
            for k, v in pairs(entry) do
                copy[k] = v
            end
            copy[kTechDataMapName] = nil
            copy[kTechDataHotkey] = nil
            return copy
        end
    end
    return {}
end

ARCSpec.kNames =
{
    hammer =
    {
        research = "Hammerworks Conversion",
        researchTip = "Anti-structure. Factory builds H.A.M.M.E.R. siege ARCs. One conversion per factory.",
        factory = "Hammerworks Siege Foundry",
        factoryTip = "Builds H.A.M.M.E.R.s. Researches Hammerworks upgrades.",
        arc = "H.A.M.M.E.R.",
        arcTip = "Siege ARC: 550 splash, 7 m blast. All alien structures; never players or Babblers. Immobile when deployed.",
        upgrades =
        {
            { "Hivebreaker Warheads",  "+25% damage to Hives." },
            { "Fragmentation Casings", "Blast radius 7 m -> 10 m." },
            { "Deflector Plating",     "H.A.M.M.E.R.s take 25% less damage." },
            { "Thermobaric Payload",   "+20% blast damage. Sets targets on fire." },
        },
    },
    vanguard =
    {
        research = "Vanguard Conversion",
        researchTip = "Anti-personnel. Factory builds V.A.T. tanks. One conversion per factory.",
        factory = "Vanguard Armour Works",
        factoryTip = "Builds V.A.T.s. Researches Vanguard upgrades.",
        arc = "V.A.T.",
        arcTip = "Tank: machine gun 10 dmg / 4 s, 6 m. Lifeforms, then Babblers; never structures. Moves deployed. Spores block fire.",
        upgrades =
        {
            { "Coaxial Machine Gun",    "Machine gun: every 2 s, 30 m." },
            { "Light Cannon Shells",    "Cannon: 25 light, 1 s charge, 5 s cooldown, 22.5 m. Lifeforms only." },
            { "Standard Cannon Shells", "Cannon: 30 normal." },
            { "Railgun Sabots",         "Cannon: 65 heavy. Railgun tracer." },
        },
    },
    inferno =
    {
        research = "Inferno Conversion",
        researchTip = "Flamethrower tanks. Factory builds H.E.L.L. tanks. One conversion per factory.",
        factory = "Inferno Forge",
        factoryTip = "Builds H.E.L.L.s. Researches Inferno upgrades.",
        arc = "H.E.L.L.",
        arcTip = "Tank: Pilot Flame ignites, 0 dmg, 4 m, every 3 s. Bile bombs > lifeforms > spores > Babblers > structures. " ..
                 "Attack order overrides. Moves deployed.",
        upgrades =
        {
            { "Igniter Burst",          "Flame: 20 dmg, 0.25 s burst, 6 m, every 2 s." },
            { "Pressurised Flame Jet",  "Flame: 3 x 15 dmg, 0.75 s burst, 10 m, every 2.5 s." },
            { "Napalm Gel",             "Flame: 3 x 18 dmg. Ignites targets." },
            { "Thermite Lance",         "Flame: 3 x 22 dmg, 14 m." },
        },
    },
}

--[[
    What each level gives, for the research tray tooltip (ARCSpec_Production.lua). Index = levels researched. Each line is
    { slot, text }: a later level's line REPLACES an earlier one in the same slot, so the tooltip only ever shows what is
    current (Railgun Sabots' 65 heavy cannon, never the 25 / 30 it replaced). Keep in step with the numbers in ARCSpec_ARC.lua.
]]
ARCSpec.kLevelEffects =
{
    hammer =
    {
        [0] = { { "damage", "550 splash damage" }, { "radius", "7 m blast" }, { "targets", "All structures, never players" } },
        [1] = { { "hive", "+25% damage to Hives" } },
        [2] = { { "radius", "10 m blast" } },
        [3] = { { "armour", "Takes 25% less damage" } },
        [4] = { { "damage", "660 splash damage (+20%)" }, { "fire", "Sets targets on fire" } },
    },
    vanguard =
    {
        [0] = { { "mg", "MG: 10 dmg every 4 s, 6 m" }, { "targets", "Lifeforms, then Babblers" }, { "spores", "Spores block fire" } },
        [1] = { { "mg", "MG: 10 dmg every 2 s, 30 m" } },
        [2] = { { "cannon", "Cannon: 25 light dmg, 22.5 m, 5 s cooldown" } },
        [3] = { { "cannon", "Cannon: 30 normal dmg, 22.5 m, 5 s cooldown" } },
        [4] = { { "cannon", "Cannon: 65 heavy dmg railgun, 22.5 m, 5 s cooldown" } },
    },
    inferno =
    {
        [0] = { { "flame", "Pilot Flame: ignites, 0 dmg, 4 m, every 3 s" }, { "targets", "Bile bombs > lifeforms > spores > Babblers > structures" } },
        [1] = { { "flame", "Flame: 20 dmg, 6 m, every 2 s" } },
        [2] = { { "flame", "Flame: 3 x 15 dmg, 10 m, every 2.5 s" } },
        [3] = { { "flame", "Flame: 3 x 18 dmg, 10 m, every 2.5 s" }, { "ignite", "Ignites targets" } },
        [4] = { { "flame", "Flame: 3 x 22 dmg, 14 m, every 2.5 s" } },
    },
}

-- Tooltip text for a specialisation at a level: its factory name, then one "- effect" line per current effect.
function ARCSpec.GetLevelTooltip(key, level)
    local names = ARCSpec.kNames[key]
    local effects = ARCSpec.kLevelEffects[key]
    if not names or not effects then return nil end

    local order, textBySlot = {}, {}
    for i = 0, Clamp(level or 0, 0, 4) do
        for _, line in ipairs(effects[i] or {}) do
            if not textBySlot[line[1]] then
                order[#order + 1] = line[1]
            end
            textBySlot[line[1]] = line[2]
        end
    end

    local lines = { string.format("%s (Level %d)", names.factory, Clamp(level or 0, 0, 4)) }
    for _, slot in ipairs(order) do
        lines[#lines + 1] = "- " .. textBySlot[slot]
    end
    return table.concat(lines, "\n")
end

local oldBuildTechData = BuildTechData
function BuildTechData()

    local techData = oldBuildTechData()

    local factorySource = CopyEntry(techData, kTechId.ARCRoboticsFactory)
    local arcSource = CopyEntry(techData, kTechId.ARC)

    local arcTime = arcSource[kTechDataResearchTimeKey] or kARCBuildTime or 5

    for _, spec in ipairs(ARCSpec.kSpecOrder) do

        local names = ARCSpec.kNames[spec.key]

        -- The conversion research (per factory).
        table.insert(techData, {
            [kTechDataId] = spec.upgrade,
            [kTechDataDisplayName] = names.research,
            [kTechDataResearchName] = names.research,
            [kTechDataTooltipInfo] = names.researchTip,
            [kTechDataCostKey] = ARCSpec.kSpecResearchCost,
            [kTechDataResearchTimeKey] = ARCSpec.kSpecResearchTime,
            [kTechIDShowEnables] = false,
        })

        -- The specialised factory: the ARC Factory entry, renamed, recycling back the conversion too.
        local factory = {}
        for k, v in pairs(factorySource) do factory[k] = v end
        factory[kTechDataId] = spec.factory
        factory[kTechDataUpgradeTech] = kTechId.ARCRoboticsFactory
        factory[kTechDataCostKey] = (factorySource[kTechDataCostKey] or 0) + ARCSpec.kSpecResearchCost
        factory[kTechDataDisplayName] = names.factory
        factory[kTechDataTooltipInfo] = names.factoryTip
        factory[kTechDataHint] = names.factoryTip
        factory[kTechIDShowEnables] = false
        table.insert(techData, factory)

        -- The specialised ARC: the ARC entry, renamed, with a fixed cost and twice as slow to build.
        local arc = {}
        for k, v in pairs(arcSource) do arc[k] = v end
        arc[kTechDataId] = spec.arc
        arc[kTechDataDisplayName] = names.arc
        arc[kTechDataTooltipInfo] = names.arcTip
        arc[kTechDataHint] = names.arcTip
        arc[kTechDataCostKey] = ARCSpec.kARCCost
        arc[kTechDataResearchTimeKey] = arcTime * ARCSpec.kARCBuildTimeScalar
        -- The range circle in the tech data shows the tank's longest reach (a placed ARC shows its current reach instead,
        -- ARC:GetVisualRadius in ARCSpec_ARC.lua). The siege ARC keeps the normal ARC range.
        if spec == ARCSpec.kSpecs.vanguard then
            arc[kVisualRange] = 30
        elseif spec == ARCSpec.kSpecs.inferno then
            arc[kVisualRange] = 14
        end
        table.insert(techData, arc)

        -- The four upgrades, team-wide researches at a factory of this specialisation.
        for i, techId in ipairs(spec.upgrades) do
            table.insert(techData, {
                [kTechDataId] = techId,
                [kTechDataDisplayName] = names.upgrades[i][1],
                [kTechDataResearchName] = names.upgrades[i][1],
                [kTechDataTooltipInfo] = names.upgrades[i][2],
                [kTechDataCostKey] = ARCSpec.kUpgradeCosts[i],
                [kTechDataResearchTimeKey] = ARCSpec.kUpgradeTimes[i],
            })
        end

    end

    return techData
end
