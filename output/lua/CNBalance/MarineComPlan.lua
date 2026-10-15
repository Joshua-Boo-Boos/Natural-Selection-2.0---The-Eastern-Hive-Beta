--[[
    MARINES COMMANDER BOT BUILD ORDERS (2026-10-14)

    The Marines' counterpart of CNBalance/AlienComPlan.lua. At the start of a round (or as soon as a Marines Commander bot
    takes the chair mid-round) the bot picks one of five build orders, tells the Marines team in team chat
    (kMarineComPlanAnnounce; off in Siege2.0-TEH, where the bot simply gets everything) and works through it step by step.
    Steps that stay impossible while the team can afford them are reported once and skipped. When the plan is complete
    (or after kPlanTimeLimit) the bot goes for everything else on the J-menu - except Military Protocol and Combat
    Engineers - including custom Exo drops and every ARCUS specialisation the mod has (2026-10-15: none in NS2.0-TEH
    Main/Beta/Event; V.A.T. and H.E.L.L. in Siege2.0-TEH - see GetAvailableSpecs).

    Plans: Phase rush, Weapons and armour, Jetpack push, Exo push, ARC siege (with an ARCUS specialisation where the mod
    has ARCUS, plain ARCs otherwise).

    No networking, no new entities. Every entry point is called by the Commander brain through pcall
    (MarineCommanderBrain_Data.lua, MarineComPlanCall) and every tech id is resolved with rawget, so a tech that does not
    exist in a mod is simply skipped.
]]

if not Server then return end

MarineComPlan = MarineComPlan or {}
local P = MarineComPlan

-- Siege2.0-TEH sets this to false (no plan messages; the bot goes straight for everything).
if kMarineComPlanAnnounce == nil then kMarineComPlanAnnounce = true end

local kPlanTimeLimit = 20 * 60      -- seconds of game time before an unfinished plan gives way to "everything"
local kStepGiveUpTime = 120         -- a step that is affordable but impossible for this long is reported and skipped
local kStationBuildDist = 15
local kNoticeRepeat = 30
local kEverythingTries, kEverythingRest = 8, 60

local function T(name) return rawget(kTechId, name) end

-- Never researched by the bot (requested): Military Protocol and Combat Engineers.
local kNeverResearch = {}
for _, name in ipairs({ "MilitaryProtocol", "CombatEngineers", "CombatEngineersCredits", "Recycle" }) do
    local id = T(name)
    if id then kNeverResearch[id] = true end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------------------

local function Epoch()
    local rules = GetGamerules and GetGamerules()
    return rules and rules.GetGameStartTime and rules:GetGameStartTime() or 0
end

local function Say(team, text)
    if kMarineComPlanAnnounce and OriginGorgeTeamMessage then
        OriginGorgeTeamMessage(team, string.sub(text, 1, 220))
    end
end

function P.Notice(team, text)
    if not kMarineComPlanAnnounce then return end
    local now = Shared.GetTime()
    P.lastNotices = P.lastNotices or {}
    if P.lastNotices[text] and now - P.lastNotices[text] < kNoticeRepeat then return end
    P.lastNotices[text] = now
    Say(team, text)
end

local function Researched(teamNumber, techId)
    local tree = techId and GetTechTree(teamNumber)
    local node = tree and tree:GetTechNode(techId)
    return node ~= nil and node:GetResearched() and tree:GetHasTech(techId)
end

local function Researching(teamNumber, techId)
    local tree = techId and GetTechTree(teamNumber)
    local node = tree and tree:GetTechNode(techId)
    return node ~= nil and node:GetResearching()
end

-- Built, living entities of a class (optionally with one of a set of tech ids).
local function Count(teamNumber, className, techIds, includeUnbuilt)
    local count = 0
    for _, ent in ipairs(GetEntitiesForTeam(className, teamNumber)) do
        if ent:GetIsAlive() and (includeUnbuilt or not ent.GetIsBuilt or ent:GetIsBuilt())
           and (not techIds or techIds[ent:GetTechId()]) then
            count = count + 1
        end
    end
    return count
end

local function Set(...)
    local s = {}
    for _, name in ipairs({ ... }) do
        local id = T(name)
        if id then s[id] = true end
    end
    return s
end

local function Cost(techId)
    return LookupTechData(techId, kTechDataCostKey, 0) or 0
end

-- An idle unit that can do techId right now (doables lists only allowed AND affordable ones).
local function IdleUnit(doables, techId, filter)
    local units = techId and doables[techId]
    if type(units) ~= "table" then return nil end
    for _, unit in ipairs(units) do
        if not (unit.GetIsResearching and unit:GetIsResearching()) and (not filter or filter(unit)) then
            return unit
        end
    end
end

local function MainCC(senses)
    return senses:Get("mainCommandStation")
end

local function LocationName(entity)
    local name = entity and entity.GetLocationName and entity:GetLocationName() or ""
    return (name ~= "" and name) or "our base"
end

-- ---------------------------------------------------------------------------------------------------------------
-- Step types. Each step: { text, Done(ctx) -> bool, Act(ctx) -> action table or nil (nil = nothing doable now),
-- techId (for the affordability check) }. ctx = { brain, com, team, n, senses, doables, plan }.
-- An action table is { perform = function() ... end } and is run by the brain's plan action.
-- ---------------------------------------------------------------------------------------------------------------

local function ExecuteAt(ctx, techId, pos, host, targetId)
    return { perform = function() ctx.brain:ExecuteTechId(ctx.com, techId, pos, host, targetId) end }
end

local function BuildInBase(ctx, techId)
    if not ctx.doables[techId] then return nil end
    local cc = MainCC(ctx.senses)
    if not cc then return nil end
    local pos = GetRandomBuildPosition(techId, cc:GetOrigin(), kStationBuildDist)
    if not pos then return nil end
    return ExecuteAt(ctx, techId, pos, ctx.com)
end

local function StepBuild(text, techName, className, count, techIdsFilter)
    local techId = T(techName)
    return {
        text = text, techId = techId,
        Done = function(ctx)
            return not techId or Count(ctx.n, className, techIdsFilter, false) >= (count or 1)
        end,
        Act = function(ctx)
            -- One at a time: wait while one is still being built.
            if Count(ctx.n, className, techIdsFilter, true) > Count(ctx.n, className, techIdsFilter, false) then return nil end
            return BuildInBase(ctx, techId)
        end,
    }
end

local function StepResearch(text, techName, unitFilter)
    local techId = T(techName)
    return {
        text = text, techId = techId,
        Done = function(ctx) return not techId or Researched(ctx.n, techId) end,
        Act = function(ctx)
            if Researching(ctx.n, techId) then return nil end
            local unit = IdleUnit(ctx.doables, techId, unitFilter)
            return unit and ExecuteAt(ctx, techId, Vector(0, 0, 0), unit) or nil
        end,
    }
end

-- An "upgrade" research that turns a structure into another tech id (Advanced Armory, Prototype Lab speciality, ARC
-- Factory). Done once a structure with resultTechId exists.
local function StepUpgrade(text, techName, className, resultName, unitFilter)
    local techId, result = T(techName), T(resultName)
    return {
        text = text, techId = techId,
        Done = function(ctx) return not techId or not result or Count(ctx.n, className, { [result] = true }, true) > 0 end,
        Act = function(ctx)
            local unit = IdleUnit(ctx.doables, techId, unitFilter)
            return unit and ExecuteAt(ctx, techId, Vector(0, 0, 0), unit) or nil
        end,
    }
end

local function IsPlainLab(unit) return unit:GetTechId() == kTechId.PrototypeLab end

local function StepPhaseGates(text, count)
    return {
        text = text, techId = kTechId.PhaseGate,
        Done = function(ctx) return Count(ctx.n, "PhaseGate", nil, false) >= count end,
        Act = function(ctx)
            if not ctx.doables[kTechId.PhaseGate] then return nil end
            if Count(ctx.n, "PhaseGate", nil, true) > Count(ctx.n, "PhaseGate", nil, false) then return nil end
            -- The first in base, the rest at safe tech points without one.
            if Count(ctx.n, "PhaseGate", nil, true) == 0 then return BuildInBase(ctx, kTechId.PhaseGate) end
            for _, tp in ipairs(ctx.senses:Get("safeTechPoints") or {}) do
                if #GetEntitiesForTeamByLocation("PhaseGate", ctx.n, tp:GetLocationId()) == 0 then
                    local pos = GetRandomBuildPosition(kTechId.PhaseGate, tp:GetOrigin(), kStationBuildDist)
                    if pos then return ExecuteAt(ctx, kTechId.PhaseGate, pos, ctx.com) end
                end
            end
            return nil
        end,
    }
end

-- Supplies dropped at a Prototype Lab (Jetpacks): counted by the plan, as dropped items get picked up.
local function DropNear(ctx, techId, lab, radius)
    local pos = GetRandomSpawnForCapsule(radius, radius, lab:GetOrigin(), 0.01, kArmoryWeaponAttachRange * 0.65,
        EntityFilterAll(), nil)
    return pos
end

local function StepJetpacks(text, count)
    return {
        text = text, techId = kTechId.DropJetpack,
        Done = function(ctx) return (ctx.plan.jetpacksDropped or 0) >= count end,
        Act = function(ctx)
            if not ctx.doables[kTechId.DropJetpack] then return nil end
            local labs = ctx.senses:Get("builtPrototypeLabs") or {}
            local lab = labs[1]
            local pos = lab and DropNear(ctx, kTechId.DropJetpack, lab, 0.5)
            if not pos then return nil end
            return { perform = function()
                if ctx.brain:ExecuteTechId(ctx.com, kTechId.DropJetpack, pos, ctx.com, lab:GetId()) then
                    ctx.plan.jetpacksDropped = (ctx.plan.jetpacksDropped or 0) + 1
                end
            end }
        end,
    }
end

-- A custom Exo, configured and paid for exactly as the Commander's Exo window does it (CNBalance/CommanderExoDrop.lua).
function P.ExoDropAction(ctx)
    local dropTechId = T("DropDualMinigunExosuit")
    if not dropTechId or not ctx.doables[dropTechId] then return nil end
    local now = Shared.GetTime()
    if now < (ctx.plan.nextExoDropTime or 0) then return nil end
    if #(ctx.senses:Get("activeInfantryPortals") or {}) == 0 then return nil end
    local loose = Count(ctx.n, "Exosuit", nil, true)
    local occupied = Count(ctx.n, "Exo", nil, true)
    -- Save for base recovery, and do not pile up suits without prospective pilots.
    local pilots = Count(ctx.n, "Marine", nil, true)
    if loose >= math.min(2, pilots) or loose + occupied >= 3 then return nil end
    local budget = ctx.team:GetTeamResources() - 20

    -- A mod without the custom Exo window (no CommanderExoDrop.lua): the button is a plain, fixed-price Exo drop.
    if not kPrototypeExoCombos or not GetCommanderExoDropComboAllowed or not GetCommanderExoDropTotal then
        local plainLab = (ctx.senses:Get("builtPrototypeLabs") or {})[1]
        local plainPos = plainLab and DropNear(ctx, dropTechId, plainLab, 1.2)
        if not plainPos then return nil end
        return { perform = function()
            if ctx.brain:ExecuteTechId(ctx.com, dropTechId, plainPos, ctx.com, plainLab:GetId()) then
                ctx.plan.exosDropped = (ctx.plan.exosDropped or 0) + 1
            end
        end }
    end
    local combos = {}
    for baseTechId in pairs(kPrototypeExoCombos) do
        if GetCommanderExoDropComboAllowed(ctx.com, baseTechId)
                and GetCommanderExoDropTotal(baseTechId, {}) <= budget then
            combos[#combos + 1] = baseTechId
        end
    end
    if #combos == 0 then return nil end
    local baseTechId = combos[math.random(#combos)]
    -- Prefer sustained anti-structure fire for the Exo push; afterwards vary
    -- among researched, affordable configurations.
    if ctx.plan.name == "ExoPush" and not ctx.plan.done then
        for _, id in ipairs(combos) do
            if id == T("DualMinigunExosuit") then baseTechId = id break end
        end
    end
    local upgrades = {}
    local armour = T("PrototypeExoArmour")
    if armour and GetCommanderExoDropExperimentalUnlocked and GetCommanderExoDropExperimentalUnlocked(ctx.com) then
        upgrades[1] = armour
    end
    local cost = GetCommanderExoDropTotal(baseTechId, upgrades)
    if budget < cost then
        upgrades = {}
        cost = GetCommanderExoDropTotal(baseTechId, upgrades)
        if budget < cost then return nil end
    end
    local lab
    for _, candidate in ipairs(ctx.senses:Get("builtPrototypeLabs") or {}) do
        if candidate:GetIsAlive() and candidate:GetIsBuilt() and GetIsUnitActive(candidate)
                and not candidate:GetIsUnderFire() then
            if candidate:GetTechId() == T("ExosuitPrototypeLab") then lab = candidate break end
            lab = lab or candidate
        end
    end
    local pos = lab and DropNear(ctx, dropTechId, lab, 1.2)
    if not pos then return nil end
    return { perform = function()
        -- Senses/choices may be stale by execution time. The shared drop handler
        -- rechecks research, cost and placement too; this preserves bot reserves.
        if not lab:GetIsAlive() or not lab:GetIsBuilt() or not GetIsUnitActive(lab)
                or lab:GetIsUnderFire() or ctx.team:GetTeamResources() < cost + 20 then return end
        ctx.com.pendingExoDropBase = baseTechId
        ctx.com.pendingExoDropBits = GetCommanderExoDropBits(upgrades)
        local ok, success = pcall(ctx.brain.ExecuteTechId, ctx.brain, ctx.com, dropTechId, pos, ctx.com, lab:GetId())
        ctx.com.pendingExoDropBase = nil
        ctx.com.pendingExoDropBits = nil
        ctx.plan.nextExoDropTime = Shared.GetTime() + (ok and success and 15 or 5)
        if not ok then error(success) end
        if success then ctx.plan.exosDropped = (ctx.plan.exosDropped or 0) + 1 end
    end }
end

local function StepExos(text, count)
    return {
        text = text, techId = nil,
        Done = function(ctx) return (ctx.plan.exosDropped or 0) >= count end,
        Act = function(ctx) return P.ExoDropAction(ctx) end,
    }
end

-- ARC Factory: a Robotics Factory in base, then its ARC Factory upgrade.
local function IsARCFactory(unit)
    local techId = unit:GetTechId()
    return techId == kTechId.ARCRoboticsFactory or (ARCSpec and ARCSpec.kSpecByFactory and ARCSpec.kSpecByFactory[techId] ~= nil)
end

local function StepARCFactory(text)
    return {
        text = text, techId = kTechId.RoboticsFactory,
        Done = function(ctx)
            for _, rf in ipairs(GetEntitiesForTeam("RoboticsFactory", ctx.n)) do
                if rf:GetIsAlive() and IsARCFactory(rf) then return true end
            end
            return false
        end,
        Act = function(ctx)
            if Count(ctx.n, "RoboticsFactory", nil, true) == 0 then return BuildInBase(ctx, kTechId.RoboticsFactory) end
            local upgrade = T("UpgradeRoboticsFactory")
            local unit = IdleUnit(ctx.doables, upgrade)
            return unit and ExecuteAt(ctx, upgrade, Vector(0, 0, 0), unit) or nil
        end,
    }
end

-- ARCUS: convert an ARC Factory to a specialisation.
local function StepARCSpec(text, specKey)
    return {
        text = text,
        Done = function(ctx)
            local spec = ARCSpec and ARCSpec.kSpecs and ARCSpec.kSpecs[specKey]
            return not spec or Count(ctx.n, "RoboticsFactory", { [spec.factory] = true }, true) > 0
        end,
        Act = function(ctx)
            local spec = ARCSpec and ARCSpec.kSpecs and ARCSpec.kSpecs[specKey]
            if not spec then return nil end
            local unit = IdleUnit(ctx.doables, spec.upgrade, function(u) return u:GetTechId() == kTechId.ARCRoboticsFactory end)
            return unit and ExecuteAt(ctx, spec.upgrade, Vector(0, 0, 0), unit) or nil
        end,
    }
end

local function StepARCSpecLevel(text, specKey, level)
    return {
        text = text,
        Done = function(ctx)
            local spec = ARCSpec and ARCSpec.kSpecs and ARCSpec.kSpecs[specKey]
            return not spec or Researched(ctx.n, spec.upgrades[level])
        end,
        Act = function(ctx)
            local spec = ARCSpec and ARCSpec.kSpecs and ARCSpec.kSpecs[specKey]
            if not spec or Researching(ctx.n, spec.upgrades[level]) then return nil end
            local unit = IdleUnit(ctx.doables, spec.upgrades[level])
            return unit and ExecuteAt(ctx, spec.upgrades[level], Vector(0, 0, 0), unit) or nil
        end,
    }
end

-- Build ARCs (of a specialisation, or plain ones) up to count.
local function ARCTechId(specKey)
    if specKey and ARCSpec and ARCSpec.kSpecs and ARCSpec.kSpecs[specKey] then return ARCSpec.kSpecs[specKey].arc end
    return kTechId.ARC
end

local function StepARCs(text, specKey, count)
    return {
        text = text,
        Done = function(ctx) return Count(ctx.n, "ARC", { [ARCTechId(specKey)] = true }, true) >= count end,
        Act = function(ctx)
            local techId = ARCTechId(specKey)
            local unit = IdleUnit(ctx.doables, techId)
            return unit and ExecuteAt(ctx, techId, Vector(0, 0, 0), unit) or nil
        end,
    }
end

--[[
    (2026-10-14) CHAIR UPGRADES. Each Command Station can become ONE Station (Standard / Armor / Electronic / Explosive
    Supply), and the team can have one of each - so a Station type is done once a Command Station of that type exists.
    A plain Command Station is converted; with none spare, a new Command Station is built on a safe free tech point.
]]
local kStationOfSupply = { StandardSupply = "StandardStation", ArmorSupply = "ArmorStation",
                           ElectronicSupply = "ElectronicStation", ExplosiveSupply = "ExplosiveStation" }
local kStationNames = { StandardSupply = "Standard Station", ArmorSupply = "Armor Station",
                        ElectronicSupply = "Electronic Station", ExplosiveSupply = "Explosive Station" }

local function BuildCommandStation(ctx)
    if not ctx.doables[kTechId.CommandStation] then return nil end
    if Count(ctx.n, "CommandStation", nil, true) > Count(ctx.n, "CommandStation", nil, false) then return nil end
    for _, tp in ipairs(ctx.senses:Get("safeTechPoints") or {}) do
        if not tp:GetAttached() then return ExecuteAt(ctx, kTechId.CommandStation, tp:GetOrigin(), ctx.com) end
    end
end

local function StepStation(supplyName)
    local supply, station = T(supplyName), T(kStationOfSupply[supplyName])
    return {
        text = "the " .. kStationNames[supplyName], techId = supply,
        Done = function(ctx) return not supply or not station or Count(ctx.n, "CommandStation", { [station] = true }, true) > 0 end,
        Act = function(ctx)
            local unit = IdleUnit(ctx.doables, supply, function(u) return u:GetTechId() == kTechId.CommandStation end)
            if unit then return ExecuteAt(ctx, supply, Vector(0, 0, 0), unit) end
            -- No plain Command Station to convert: build one.
            for _, cc in ipairs(GetEntitiesForTeam("CommandStation", ctx.n)) do
                if cc:GetIsAlive() and cc:GetTechId() == kTechId.CommandStation then return nil end   -- busy / not yet built
            end
            return BuildCommandStation(ctx)
        end,
    }
end

--[[
    (2026-10-14) ELECTRIFIED RT OUTPOSTS (Electronic Station). The bot electrifies Extractors away from the main base and
    puts a Phase Gate by each of them, so Marines can phase straight to a defended RT: an electrified RT gets a Phase Gate
    in its room, and an RT that is to get a Phase Gate is electrified first. Up to `count` outposts.
]]
local function IsRemoteExtractor(ctx, extractor)
    local mainId = ctx.brain.GetStartingLocationId and ctx.brain:GetStartingLocationId() or 0
    return extractor:GetIsAlive() and extractor:GetIsBuilt() and extractor:GetLocationId() ~= mainId
end

local function StepRTOutposts(text, count)
    local upgrade, powered = T("PoweredExtractorUpgrade"), T("PoweredExtractor")
    local function Outposts(ctx)
        local done, candidates = 0, {}
        for _, rt in ipairs(GetEntitiesForTeam("Extractor", ctx.n)) do
            if IsRemoteExtractor(ctx, rt) then
                local hasGate = #GetEntitiesForTeamByLocation("PhaseGate", ctx.n, rt:GetLocationId()) > 0
                local isPowered = rt:GetTechId() == powered
                if isPowered and hasGate then done = done + 1 else candidates[#candidates + 1] = rt end
            end
        end
        return done, candidates
    end
    return {
        text = text, techId = upgrade,
        Done = function(ctx)
            if not upgrade or not powered then return true end
            return (Outposts(ctx)) >= count
        end,
        Act = function(ctx)
            if not upgrade or not powered then return nil end
            local _, candidates = Outposts(ctx)
            for _, rt in ipairs(candidates) do
                if rt:GetTechId() ~= powered then
                    -- Electrify it first (one Extractor at a time).
                    if not (rt.GetIsResearching and rt:GetIsResearching()) then
                        local unit = IdleUnit(ctx.doables, upgrade, function(u) return u == rt end)
                        if unit then return ExecuteAt(ctx, upgrade, Vector(0, 0, 0), unit) end
                    end
                elseif ctx.doables[kTechId.PhaseGate]
                       and Count(ctx.n, "PhaseGate", nil, true) == Count(ctx.n, "PhaseGate", nil, false) then
                    local pos = GetRandomBuildPosition(kTechId.PhaseGate, rt:GetOrigin(), 10)
                    if pos then return ExecuteAt(ctx, kTechId.PhaseGate, pos, ctx.com) end
                end
            end
            return nil
        end,
    }
end

-- Siege: done once a siege ARC has deployed within range of a known Hive (set by P.ManageARCs).
local function StepSiege(text)
    return {
        text = text,
        Done = function(ctx) return ctx.plan.sieged == true end,
        Act = function() return nil end,   -- the ARC manager does this; nothing to buy
        passive = true,
    }
end

-- ---------------------------------------------------------------------------------------------------------------
-- The five plans
-- ---------------------------------------------------------------------------------------------------------------

local kSpecNames = { hammer = "H.A.M.M.E.R.", vanguard = "V.A.T.", inferno = "H.E.L.L." }

--[[
    (2026-10-15) Which ARCUS specialisations this mod has. NS2.0-TEH Main/Beta/Event have no ARCUS at all (removed);
    Siege2.0-TEH has the V.A.T. and H.E.L.L. but no H.A.M.M.E.R. Plans only ever use what exists, and plain ARCs
    otherwise - so the chat never mentions ARCUS where there is none.
]]
local function GetAvailableSpecs()
    local keys = {}
    if ARCSpec and ARCSpec.kSpecs then
        for _, key in ipairs({ "hammer", "inferno", "vanguard" }) do
            if ARCSpec.kSpecs[key] then keys[#keys + 1] = key end
        end
    end
    return keys
end

local function ARCsText()
    return #GetAvailableSpecs() > 0 and "ARCUS ARCs" or "ARCs"
end

local function NewPlan(allTech)
    local plan = { epoch = Epoch(), allTech = allTech, done = allTech, skipped = {} }
    local names = { "PhaseRush", "WeaponsArmour", "JetpackPush", "ExoPush", "ARCSiege" }
    plan.name = names[math.random(#names)]
    local specs = GetAvailableSpecs()
    if #specs == 3 then
        local roll = math.random()
        plan.spec = roll < 0.6 and "hammer" or (roll < 0.8 and "inferno" or "vanguard")
    elseif #specs > 0 then
        plan.spec = specs[math.random(#specs)]
    end
    return plan
end

local function BuildSteps(plan)
    if plan.name == "PhaseRush" then
        return "Phase rush", {
            StepBuild("an Armory", "Armory", "Armory"),
            StepBuild("an Observatory", "Observatory", "Observatory"),
            StepResearch("Phase Tech", "PhaseTech"),
            StepPhaseGates("3 Phase Gates (base + 2 forward)", 3),
            StepResearch("Shotguns", "ShotgunTech"),
            StepBuild("an Arms Lab", "ArmsLab", "ArmsLab"),
            StepResearch("Weapons 1", "Weapons1"),
            StepResearch("Armour 1", "Armor1"),
            StepStation("ElectronicSupply"),
            StepRTOutposts("2 electrified RTs with Phase Gates", 2),
            StepResearch("Motion Tracking", "MotionTrack"),
        }, {
            "Armory and Observatory, then Phase Tech straight away",
            "Phase Gates in base and 2 forward tech points, Shotguns",
            "Arms Lab, then Weapons 1 and Armour 1",
            "Electronic Station: 2 electrified RTs, each with a Phase Gate, and Motion Tracking",
            "Then the rest of the J-menu, all Chair upgrades, " .. ARCsText() .. " and Exos",
        }
    elseif plan.name == "WeaponsArmour" then
        return "Weapons and armour", {
            StepBuild("an Arms Lab", "ArmsLab", "ArmsLab"),
            StepResearch("Weapons 1", "Weapons1"),
            StepResearch("Armour 1", "Armor1"),
            StepBuild("an Armory", "Armory", "Armory"),
            StepResearch("Weapons 2", "Weapons2"),
            StepResearch("Armour 2", "Armor2"),
            StepUpgrade("an Advanced Armory", "AdvancedArmoryUpgrade", "Armory", "AdvancedArmory"),
            StepStation("ArmorSupply"),
            StepResearch("Nano Armour", "ArmorRegen"),
            StepResearch("Weapons 3", "Weapons3"),
            StepResearch("Armour 3", "Armor3"),
        }, {
            "Arms Lab, Weapons 1 and Armour 1 first",
            "Weapons 2 and Armour 2, then an Advanced Armory for heavy weapons",
            "Armor Station and Nano Armour",
            "Weapons 3 and Armour 3",
            "Then the rest of the J-menu, all Chair upgrades, " .. ARCsText() .. " and Exos",
        }
    elseif plan.name == "JetpackPush" then
        return "Jetpack push", {
            StepBuild("an Armory", "Armory", "Armory"),
            StepBuild("an Arms Lab", "ArmsLab", "ArmsLab"),
            StepResearch("Weapons 1", "Weapons1"),
            StepUpgrade("an Advanced Armory", "AdvancedArmoryUpgrade", "Armory", "AdvancedArmory"),
            StepBuild("a Prototype Lab", "PrototypeLab", "PrototypeLab"),
            StepUpgrade("the Jetpack Prototype Lab", "JetpackProtoUpgrade", "PrototypeLab", "JetpackPrototypeLab", IsPlainLab),
            StepJetpacks("4 Jetpacks dropped", 4),
            StepResearch("Weapons 2", "Weapons2"),
            StepStation("StandardSupply"),
            StepResearch("Fire Bullets", "DragonBreath"),
        }, {
            "Armory, Arms Lab and Weapons 1",
            "Advanced Armory, a Prototype Lab and the Jetpack Prototype Lab",
            "4 Jetpacks dropped at the Prototype Lab",
            "Weapons 2, then a Standard Station and Fire Bullets",
            "Then the rest of the J-menu, all Chair upgrades, " .. ARCsText() .. " and Exos",
        }
    elseif plan.name == "ExoPush" then
        return "Exo push", {
            StepBuild("an Armory", "Armory", "Armory"),
            StepBuild("an Arms Lab", "ArmsLab", "ArmsLab"),
            StepResearch("Armour 1", "Armor1"),
            StepUpgrade("an Advanced Armory", "AdvancedArmoryUpgrade", "Armory", "AdvancedArmory"),
            StepBuild("a Prototype Lab", "PrototypeLab", "PrototypeLab"),
            StepUpgrade("the Exosuit Prototype Lab", "ExosuitProtoUpgrade", "PrototypeLab", "ExosuitPrototypeLab", IsPlainLab),
            StepResearch("Exosuit Experimental Tech", "ExosuitExperimentalTech"),
            StepExos("2 custom Exos dropped", 2),
            StepResearch("Armour 2", "Armor2"),
            StepStation("ArmorSupply"),
            StepResearch("Nano Armour", "ArmorRegen"),
        }, {
            "Armory, Arms Lab and Armour 1",
            "Advanced Armory, a Prototype Lab and the Exosuit Prototype Lab with its Experimental Tech",
            "2 custom Exos dropped at the Prototype Lab",
            "Armour 2, then an Armor Station and Nano Armour",
            "Then the rest of the J-menu, all Chair upgrades and " .. ARCsText(),
        }
    end
    if not plan.spec then
        -- No ARCUS in this mod: the siege uses plain ARCs.
        return "ARC siege", {
            StepBuild("an Armory", "Armory", "Armory"),
            StepARCFactory("an ARC Factory"),
            StepARCs("3 ARCs", nil, 3),
            StepBuild("an Observatory", "Observatory", "Observatory"),
            StepResearch("Motion Tracking", "MotionTrack"),
            StepStation("ExplosiveSupply"),
            StepResearch("the Grenade Launcher upgrade", "GrenadeLauncherUpgrade"),
            StepSiege("siege the nearest known Hive"),
        }, {
            "ARC Factory, then 3 ARCs",
            "Observatory and Motion Tracking to find the Hives",
            "Explosive Station and the Grenade Launcher upgrade, then the ARCs siege the nearest Hive we have seen",
            "Then the rest of the J-menu, all Chair upgrades and Exos",
        }
    end
    local specName = kSpecNames[plan.spec]
    local spec = ARCSpec.kSpecs[plan.spec]
    --[[
        (2026-10-15) A tank specialisation (V.A.T. / H.E.L.L. - Siege2.0-TEH's only ones) cannot shell a Hive, so the
        plan first builds 2 normal siege ARCs from the still-plain ARC Factory (a converted factory builds only its own
        ARC), then converts it and adds 3 tanks to escort them: 5 ARCs, the shared limit.
    ]]
    local tankEscort = spec and spec.mobile
    local steps = {
        StepBuild("an Armory", "Armory", "Armory"),
        StepARCFactory("an ARC Factory"),
    }
    if tankEscort then
        steps[#steps + 1] = StepARCs("2 ARCs for the siege", nil, 2)
    end
    for _, step in ipairs({
        StepARCSpec("the " .. specName .. " conversion", plan.spec),
        StepARCSpecLevel(specName .. " level 1", plan.spec, 1),
        StepARCs("3 " .. specName .. "s", plan.spec, 3),
        StepARCSpecLevel(specName .. " level 2", plan.spec, 2),
        StepBuild("an Observatory", "Observatory", "Observatory"),
        StepResearch("Motion Tracking", "MotionTrack"),
        StepStation("ExplosiveSupply"),
        StepResearch("the Grenade Launcher upgrade", "GrenadeLauncherUpgrade"),
        StepSiege("siege the nearest known Hive"),
    }) do
        steps[#steps + 1] = step
    end
    return "ARC siege", steps, {
        tankEscort and string.format("ARC Factory and 2 ARCs, then the ARCUS %s conversion and its level 1", specName)
            or string.format("ARC Factory, then the ARCUS %s conversion and its level 1", specName),
        tankEscort and string.format("3 %ss to escort the ARCs, then %s level 2", specName, specName)
            or string.format("3 %ss, then %s level 2", specName, specName),
        "Observatory and Motion Tracking to find the Hives",
        "Explosive Station and the Grenade Launcher upgrade, then the ARCs siege the nearest Hive we have seen",
        "Then the rest of the J-menu, all Chair upgrades, more ARCUS specialisations and Exos",
    }
end

local function EnsureSteps(plan)
    if not plan.steps then
        plan.title, plan.steps, plan.lines = BuildSteps(plan)
        plan.stepState = {}
    end
end

function P.Get(team)
    if not team or not team.GetTeamNumber then return nil end
    local plan = team.marineComPlan
    if not plan or plan.epoch ~= Epoch() then
        plan = NewPlan(not kMarineComPlanAnnounce)
        team.marineComPlan = plan
    end
    EnsureSteps(plan)
    return plan
end

-- ---------------------------------------------------------------------------------------------------------------
-- "Everything" mode: the rest of the J-menu (never Military Protocol or Combat Engineers).
-- ---------------------------------------------------------------------------------------------------------------

local function EverythingSteps()
    if P.everything then return P.everything end
    local steps = {
        StepBuild("an Arms Lab", "ArmsLab", "ArmsLab"),
        StepBuild("an Armory", "Armory", "Armory"),
        StepBuild("an Observatory", "Observatory", "Observatory"),
        StepResearch("Weapons 1", "Weapons1"), StepResearch("Armour 1", "Armor1"),
        StepResearch("Phase Tech", "PhaseTech"),
        StepPhaseGates("Phase Gates", 3),
        StepResearch("Weapons 2", "Weapons2"), StepResearch("Armour 2", "Armor2"),
        StepResearch("Shotguns", "ShotgunTech"), StepResearch("Mines", "MinesTech"), StepResearch("Grenades", "GrenadeTech"),
        StepResearch("Combat Builder", "CombatBuilderTech"),
        StepUpgrade("an Advanced Armory", "AdvancedArmoryUpgrade", "Armory", "AdvancedArmory"),
        StepResearch("Weapons 3", "Weapons3"), StepResearch("Armour 3", "Armor3"),
        StepResearch("Motion Tracking", "MotionTrack"),
        -- Three Prototype Labs, one of each speciality.
        StepBuild("a Prototype Lab", "PrototypeLab", "PrototypeLab", 1),
        StepUpgrade("the Jetpack Prototype Lab", "JetpackProtoUpgrade", "PrototypeLab", "JetpackPrototypeLab", IsPlainLab),
        StepBuild("a 2nd Prototype Lab", "PrototypeLab", "PrototypeLab", 2),
        StepUpgrade("the Exosuit Prototype Lab", "ExosuitProtoUpgrade", "PrototypeLab", "ExosuitPrototypeLab", IsPlainLab),
        StepResearch("Exosuit Experimental Tech", "ExosuitExperimentalTech"),
        StepBuild("a 3rd Prototype Lab", "PrototypeLab", "PrototypeLab", 3),
        StepUpgrade("the Cannon Prototype Lab", "CannonProtoUpgrade", "PrototypeLab", "CannonPrototypeLab", IsPlainLab),
        -- ARCUS: a factory of each specialisation, their levels, and ARCs.
        StepARCFactory("an ARC Factory"),
    }
    for _, key in ipairs(GetAvailableSpecs()) do
        steps[#steps + 1] = {   -- a fresh ARC Factory for each further specialisation
            text = "an ARC Factory for " .. kSpecNames[key],
            Done = function(ctx)
                local spec = ARCSpec and ARCSpec.kSpecs and ARCSpec.kSpecs[key]
                return not spec or Count(ctx.n, "RoboticsFactory", { [spec.factory] = true }, true) > 0
                    or Count(ctx.n, "RoboticsFactory", { [kTechId.ARCRoboticsFactory] = true }, true) > 0
            end,
            Act = function(ctx)
                if Count(ctx.n, "RoboticsFactory", nil, true) >= 3 then return nil end
                local unbuilt = Count(ctx.n, "RoboticsFactory", nil, true) > Count(ctx.n, "RoboticsFactory", nil, false)
                if unbuilt then return nil end
                for _, rf in ipairs(GetEntitiesForTeam("RoboticsFactory", ctx.n)) do
                    if rf:GetIsAlive() and rf:GetTechId() == kTechId.RoboticsFactory then
                        local upgrade = T("UpgradeRoboticsFactory")
                        local unit = IdleUnit(ctx.doables, upgrade)
                        return unit and ExecuteAt(ctx, upgrade, Vector(0, 0, 0), unit) or nil
                    end
                end
                return BuildInBase(ctx, kTechId.RoboticsFactory)
            end,
        }
        steps[#steps + 1] = StepARCSpec("the " .. kSpecNames[key] .. " conversion", key)
        for level = 1, 4 do
            steps[#steps + 1] = StepARCSpecLevel(kSpecNames[key] .. " level " .. level, key, level)
        end
    end
    -- All four Chair upgrades (one Command Station each - new ones are built on safe tech points as needed), then
    -- each Station's research. The passive ones (LMG, Life Sustain, Mines upgrade, Powered Extractor tech) come with
    -- the Station itself.
    for _, pair in ipairs({ { "ElectronicSupply", "MACEMPBlast" }, { "ArmorSupply", "ArmorRegen" },
                            { "StandardSupply", "DragonBreath" }, { "ExplosiveSupply", "GrenadeLauncherUpgrade" } }) do
        steps[#steps + 1] = StepStation(pair[1])
        steps[#steps + 1] = StepResearch(pair[2], pair[2])
    end
    -- Electrified RTs with Phase Gates around the map (needs the Electronic Station).
    steps[#steps + 1] = StepRTOutposts("electrified RTs with Phase Gates", 4)
    P.everything = steps
    return steps
end

-- Anything else researchable that the lists above missed (another mod's research): Research-type only, never the
-- excluded ones, never ARCUS conversions (those are chosen above).
local function AnyOtherResearch(ctx)
    local tree = GetTechTree(ctx.n)
    for techId, units in pairs(ctx.doables) do
        if not kNeverResearch[techId] and type(units) == "table"
           and not (ARCSpec and ARCSpec.kSpecByUpgrade and ARCSpec.kSpecByUpgrade[techId]) then
            local node = tree and tree:GetTechNode(techId)
            if node and node:GetIsResearch() and node:GetTechType() == kTechType.Research and not node:GetResearched()
               and not node:GetResearching() then
                local unit = IdleUnit(ctx.doables, techId)
                if unit then return ExecuteAt(ctx, techId, Vector(0, 0, 0), unit) end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Brain entry points
-- ---------------------------------------------------------------------------------------------------------------

local function Context(brain, com, plan)
    local senses = brain:GetSenses()
    return { brain = brain, com = com, team = com:GetTeam(), n = com:GetTeamNumber(), senses = senses,
             doables = senses:Get("doableTechIds") or {}, plan = plan }
end

function P.Announce(plan, team)
    if not kMarineComPlanAnnounce then return end
    Say(team, string.format("[Marines Commander Bot build order]: %s", plan.title))
    for i, line in ipairs(plan.lines) do
        Say(team, string.format("%d. %s", i, line))
    end
end

-- The first step of the plan that is not done (and not skipped).
local function CurrentStep(plan, ctx)
    for i, step in ipairs(plan.steps) do
        if not plan.skipped[i] and not step.Done(ctx) then return i, step end
    end
end

-- Upkeep: create / announce / complete the plan. Called every think.
function P.Update(brain, com)
    local team = com:GetTeam()
    local rules = GetGamerules and GetGamerules()
    if not team or not rules or not rules:GetGameStarted() then return end
    local plan = P.Get(team)
    if brain.marineComPlanAnnounced ~= plan.epoch then
        brain.marineComPlanAnnounced = plan.epoch
        if not plan.done then P.Announce(plan, team) end
    end
    if plan.done then return end
    local ctx = Context(brain, com, plan)
    if not CurrentStep(plan, ctx) then
        plan.done = true
        Say(team, "[Marines Commander Bot build order]: plan complete - now the rest of the J-menu, " .. ARCsText() .. " and Exos")
    elseif Shared.GetTime() - plan.epoch >= kPlanTimeLimit then
        plan.done = true
        Say(team, "[Marines Commander Bot build order]: out of time for the plan - now the rest of the J-menu, " .. ARCsText() .. " and Exos")
    end
end

--[[
    What the plan wants to do right now, or nil. Returns an action table the brain performs.
    A step that the team CAN afford but that stays impossible for kStepGiveUpTime is reported and skipped.
]]
function P.NextAction(brain, com)
    local team = com:GetTeam()
    local rules = GetGamerules and GetGamerules()
    if not team or not rules or not rules:GetGameStarted() then return nil end
    local plan = P.Get(team)
    local ctx = Context(brain, com, plan)
    local now = Shared.GetTime()

    if not plan.done then
        local index, step = CurrentStep(plan, ctx)
        if not step then return nil end
        local action = step.Act(ctx)
        local state = plan.stepState[index] or {}
        plan.stepState[index] = state
        if action or step.passive then
            state.stuckSince = nil
            return action
        end
        -- Impossible right now. Only counts while the team could pay for it (saving up is not "impossible").
        local affordable = not step.techId or team:GetTeamResources() >= Cost(step.techId)
        if affordable then
            state.stuckSince = state.stuckSince or now
            if now - state.stuckSince >= kStepGiveUpTime then
                plan.skipped[index] = true
                local _, nextStep = CurrentStep(plan, ctx)
                P.Notice(team, string.format("[Marines Commander Bot]: %s not possible now - next: %s",
                    step.text, nextStep and nextStep.text or "the rest of the J-menu"))
            end
        else
            state.stuckSince = nil
        end
        return nil
    end

    --[[
        Everything mode. (2026-10-14) A step whose action keeps being tried without the step finishing (e.g. a Phase Gate
        position the game refuses - an unpowered room) is rested for kEverythingRest seconds after kEverythingTries goes,
        so it cannot starve every step after it.
    ]]
    plan.everythingTries = plan.everythingTries or {}
    plan.everythingRest = plan.everythingRest or {}
    for i, step in ipairs(EverythingSteps()) do
        if now >= (plan.everythingRest[i] or 0) and not step.Done(ctx) then
            local action = step.Act(ctx)
            if action then
                local tries = (plan.everythingTries[i] or 0) + 1
                plan.everythingTries[i] = tries
                if tries >= kEverythingTries then
                    plan.everythingTries[i] = 0
                    plan.everythingRest[i] = now + kEverythingRest
                end
                return action
            end
        else
            plan.everythingTries[i] = 0
        end
    end
    -- Custom Exos when t-res is plentiful (never more than 3 Exos out at once).
    if team:GetTeamResources() >= 120 and Count(ctx.n, "Exosuit", nil, true) + Count(ctx.n, "Exo", nil, true) < 3 then
        local action = P.ExoDropAction(ctx)
        if action then return action end
    end
    -- Specialised ARCs up to the ARC limit, from whichever specialised factories exist.
    if team:GetTeamResources() >= 40 and ARCSpec and ARCSpec.kSpecOrder and Count(ctx.n, "ARC", nil, true) < (kMaxARCs or 5) then
        for _, spec in ipairs(ARCSpec.kSpecOrder) do
            local unit = IdleUnit(ctx.doables, spec.arc)
            if unit then return ExecuteAt(ctx, spec.arc, Vector(0, 0, 0), unit) end
        end
    end
    return AnyOtherResearch(ctx)
end

--[[
    (2026-10-14) DEFENCE DISPATCH. When a Marine structure is under attack, the Commander bot orders the nearest free
    Marine bots to it - Phase Gates first (losing one cuts the map in half), then Command Stations, Infantry Portals,
    Extractors and everything else. Bots path through Phase Gates when that is quicker (MarineBrain PerformMove /
    GetPhaseDistanceForMarine), so they phase across the map to save the structure and fight the Aliens there; the
    Move order completes when they arrive and they fight as normal.

    Only bots with no order already, not fighting where they are, and not already there are sent; up to
    kDefendersPerStructure per structure every kDefendRedispatch seconds. Human players are never ordered.
]]
local kDispatchInterval = 2
local kDefendersPerStructure = 3
local kDefendRedispatch = 25
local kAlreadyThere = 15
local kStructurePriority = { PhaseGate = 1, CommandStation = 2, InfantryPortal = 3, Extractor = 4 }

function P.DispatchDefenders(brain, com)
    local now = Shared.GetTime()
    if now < (brain.marineComNextDispatch or 0) then return end
    brain.marineComNextDispatch = now + kDispatchInterval
    brain.marineComDispatched = brain.marineComDispatched or {}

    local n = com:GetTeamNumber()

    -- Structures under attack, most important first.
    local attacked = {}
    for _, ent in ipairs(GetEntitiesWithMixinForTeam("Construct", n)) do
        if ent:GetIsAlive() and ent:GetIsBuilt() and HasMixin(ent, "Combat") and ent:GetIsUnderFire()
           and now >= (brain.marineComDispatched[ent:GetId()] or 0) then
            attacked[#attacked + 1] = ent
        end
    end
    if #attacked == 0 then return end
    table.sort(attacked, function(a, b)
        return (kStructurePriority[a:GetClassName()] or 9) < (kStructurePriority[b:GetClassName()] or 9)
    end)

    -- Free Marine bots.
    local free = {}
    for _, marine in ipairs(GetEntitiesForTeam("Marine", n)) do
        local client = marine:GetIsAlive() and Server.GetOwner(marine)
        if client and client:GetIsVirtual() and not (marine.GetHasOrder and marine:GetHasOrder())
           and not marine:GetIsInCombat() then
            free[#free + 1] = marine
        end
    end

    for _, structure in ipairs(attacked) do
        if #free == 0 then break end
        local target = structure:GetOrigin()
        local function Reach(marine)
            if GetPhaseDistanceForMarine then
                local ok, dist = pcall(GetPhaseDistanceForMarine, marine, target)
                if ok and dist then return dist end
            end
            return (marine:GetOrigin() - target):GetLength()
        end
        table.sort(free, function(a, b) return Reach(a) < Reach(b) end)
        local sent = 0
        local i = 1
        while i <= #free and sent < kDefendersPerStructure do
            local marine = free[i]
            if (marine:GetOrigin() - target):GetLength() > kAlreadyThere then
                marine:GiveOrder(kTechId.Move, nil, Pathing.GetClosestPoint(target), nil, true, true)
                table.remove(free, i)
                sent = sent + 1
            else
                i = i + 1
            end
        end
        brain.marineComDispatched[structure:GetId()] = now + kDefendRedispatch
    end
end

--[[
    ARCs. Uses only Hives the team has SEEN (its memories), never hidden information:
      - siege ARCs (every non-tank ARC) drive to the nearest known Hive and deploy once in firing range;
      - mobile ARCs (V.A.T. / H.E.L.L.) deploy and keep with the siege ARCs (or the nearest Marines);
      - with no known Hive, ARCs wait in base.
]]
local kARCManageInterval = 2
function P.ManageARCs(brain, com)
    local now = Shared.GetTime()
    if now < (brain.marineComNextARCManage or 0) then return end
    brain.marineComNextARCManage = now + kARCManageInterval

    local n = com:GetTeamNumber()
    local arcs = GetEntitiesForTeam("ARC", n)
    if #arcs == 0 then return end

    -- Known Hives (memories of the enemy team).
    local hives = {}
    for _, memory in ipairs(GetTeamMemories(n) or {}) do
        local ent = memory.entId and Shared.GetEntity(memory.entId)
        if ent and ent:isa("Hive") and ent:GetIsAlive() then hives[#hives + 1] = ent end
    end

    local plan = P.Get(com:GetTeam())
    local siegeCenter
    local fireRange = ARC.kFireRange or 26

    for _, arc in ipairs(arcs) do
        if arc:GetIsAlive() then
            local mobile = ARCSpec and ARCSpec.GetIsMobileARC and ARCSpec.GetIsMobileARC(arc)
            if not mobile then
                local nearest, best
                for _, hive in ipairs(hives) do
                    local d = (hive:GetOrigin() - arc:GetOrigin()):GetLength()
                    if not best or d < best then nearest, best = hive, d end
                end
                if nearest then
                    siegeCenter = siegeCenter or arc:GetOrigin()
                    if best <= fireRange - 2 then
                        if arc.deployMode == ARC.kDeployMode.Undeployed then
                            brain:ExecuteTechId(com, kTechId.ARCDeploy, arc:GetOrigin(), arc)
                        elseif arc.deployMode == ARC.kDeployMode.Deployed and plan then
                            plan.sieged = true
                        end
                    elseif arc.deployMode == ARC.kDeployMode.Undeployed and not arc:GetHasOrder() then
                        -- Drive to a point short of the Hive, along the way there.
                        local dir = arc:GetOrigin() - nearest:GetOrigin()
                        dir.y = 0
                        if dir:GetLength() > 0.1 then dir:Normalize() end
                        local target = Pathing.GetClosestPoint(nearest:GetOrigin() + dir * (fireRange - 6))
                        arc:GiveOrder(kTechId.Move, nil, target, nil, true, true)
                    elseif arc.deployMode == ARC.kDeployMode.Deployed and best > fireRange then
                        brain:ExecuteTechId(com, kTechId.ARCUndeploy, arc:GetOrigin(), arc)
                    end
                elseif arc.deployMode == ARC.kDeployMode.Deployed then
                    brain:ExecuteTechId(com, kTechId.ARCUndeploy, arc:GetOrigin(), arc)
                end
            end
        end
    end

    -- Mobile ARCs: deployed (they move deployed), escorting the siege or the nearest Marines.
    for _, arc in ipairs(arcs) do
        if arc:GetIsAlive() and ARCSpec and ARCSpec.GetIsMobileARC and ARCSpec.GetIsMobileARC(arc) then
            if arc.deployMode == ARC.kDeployMode.Undeployed then
                brain:ExecuteTechId(com, kTechId.ARCDeploy, arc:GetOrigin(), arc)
            elseif arc.deployMode == ARC.kDeployMode.Deployed and not arc:GetHasOrder() then
                local escort = siegeCenter
                if not escort then
                    local marine = GetNearest(arc:GetOrigin(), "Marine", n, function(m) return m:GetIsAlive() end)
                    escort = marine and marine:GetOrigin()
                end
                if escort and (escort - arc:GetOrigin()):GetLength() > 8 then
                    arc:GiveOrder(kTechId.Move, nil, Pathing.GetClosestPoint(escort), nil, true, true)
                end
            end
        end
    end
end
