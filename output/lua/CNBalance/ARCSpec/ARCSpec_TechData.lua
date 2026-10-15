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
        researchTip = "Converts this ARC Factory into a Hammerworks Siege Foundry. Builds H.A.M.M.E.R. (Hive-Assault Mobile Mortar & Explosive Rig) siege ARCs against alien structures, never players. Stationary when deployed. Unlocks four upgrades: Deflector Plating, Fragmentation Casings, Thermobaric Payload and Hivebreaker Warheads. One permanent specialisation per factory.",
        factory = "Hammerworks Siege Foundry",
        factoryTip = "Builds H.A.M.M.E.R.s. Researches Hammerworks upgrades.",
        arc = "H.A.M.M.E.R.",
        arcTip = "Siege ARC: 550 splash, 7 m blast. All alien structures; never players or Babblers. Immobile when deployed.",
        upgrades =
        {
            { "Deflector Plating",     "H.A.M.M.E.R.s take 25% less damage." },
            { "Fragmentation Casings", "Blast radius 7 m -> 10 m." },
            { "Thermobaric Payload",   "+20% blast damage. Sets targets on fire." },
            { "Hivebreaker Warheads",  "+25% damage to Hives." },
        },
    },
    vanguard =
    {
        research = "Vanguard Conversion",
        researchTip = "Converts this ARC Factory into Vanguard Armour Works. Builds V.A.T. (Vanguard Assault Tank) tanks against alien lifeforms and Babblers, never structures. Moves while deployed; spores block fire. Unlocks four upgrades: Coaxial Machine Gun, Cannon Shells, Autoloader and Railgun Sabots. One permanent specialisation per factory.",
        factory = "Vanguard Armour Works",
        factoryTip = "Builds V.A.T.s. Researches Vanguard upgrades.",
        arc = "V.A.T.",
        arcTip = "Tank: machine gun 1.6 dmg, 5 rounds/s, 12 m. Lifeforms, then Babblers; never structures. Moves deployed. Spores block fire.",
        upgrades =
        {
            { "Coaxial Machine Gun",    "Machine gun: 2.1 dmg, ~7 rounds/s, 20 m." },
            { "Cannon Shells",          "Cannon: 23.6 normal, 1 s charge, 6 s cooldown, 22.5 m. Lifeforms only." },
            { "Autoloader",             "Machine gun 10 rounds/s (1.8 dmg), 30 m. Cannon cooldown 4.5 s." },
            { "Railgun Sabots",         "Cannon: 36.8 heavy. Railgun tracer." },
        },
    },
    inferno =
    {
        research = "Inferno Conversion",
        researchTip = "Converts this ARC Factory into an Inferno Forge. Builds H.E.L.L. (Heavy Embedded Liquid-fire Launcher) tanks against alien lifeforms and structures, burning projectiles and clouds. Moves while deployed. Unlocks four upgrades: Igniter Burst, Pressurised Flame Jet, Napalm Gel and Thermite Lance. One permanent specialisation per factory.",
        factory = "Inferno Forge",
        factoryTip = "Builds H.E.L.L.s. Researches Inferno upgrades.",
        arc = "H.E.L.L.",
        arcTip = "Tank: Pilot Flame 7.9 dmg a second + sets on fire, 5 m. Burns bile, Acid Spray, spores, Umbra, Vortex and " ..
                 "other projectiles and clouds. Attack order overrides. Moves deployed.",
        upgrades =
        {
            { "Igniter Burst",          "Flame: 3 x 4.7 dmg every second (14.2 dps), 7 m." },
            { "Pressurised Flame Jet",  "Flame: 3 x 6.3 dmg every second (18.9 dps), 10 m." },
            { "Napalm Gel",             "Flame: 3 x 7.9 dmg every second (23.6 dps), 12 m." },
            { "Thermite Lance",         "Continuous flame, no cooldown: 26.3 dmg/s, 14 m. Instantly burns every bile, spore, cloud and projectile in range." },
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
        [1] = { { "armour", "Takes 25% less damage" } },
        [2] = { { "radius", "10 m blast" } },
        [3] = { { "damage", "660 splash damage (+20%)" }, { "fire", "Sets targets on fire" } },
        [4] = { { "hive", "+25% damage to Hives" } },
    },
    vanguard =
    {
        [0] = { { "mg", "MG: 1.6 dmg, 5 rounds/s (7.9 dps), 12 m" }, { "targets", "Lifeforms, then Babblers" }, { "spores", "Spores block fire" } },
        [1] = { { "mg", "MG: 2.1 dmg, ~7 rounds/s (14 dps), 20 m" } },
        [2] = { { "cannon", "Cannon: 23.6 normal dmg, 22.5 m, 6 s cooldown" } },
        [3] = { { "mg", "MG: 1.8 dmg, 10 rounds/s (18.4 dps), 30 m" }, { "cannon", "Cannon: 23.6 normal dmg, 22.5 m, 4.5 s cooldown" } },
        [4] = { { "cannon", "Cannon: 36.8 heavy dmg railgun, 22.5 m, 4.5 s cooldown" } },
    },
    inferno =
    {
        [0] = { { "flame", "Pilot Flame: 7.9 dmg every second, 5 m" }, { "ignite", "Always sets targets on fire" },
                { "targets", "Projectiles > lifeforms > clouds > Babblers > structures" } },
        [1] = { { "flame", "Flame: 3 x 4.7 dmg every second (14.2 dps), 7 m" } },
        [2] = { { "flame", "Flame: 3 x 6.3 dmg every second (18.9 dps), 10 m" } },
        [3] = { { "flame", "Flame: 3 x 7.9 dmg every second (23.6 dps), 12 m" } },
        [4] = { { "flame", "Continuous flame: 26.3 dmg/s, 14 m, no cooldown" },
                { "sweep", "Burns every projectile and cloud in range at once" } },
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
