--[[
    (2026-10-28) THE MARINE COMMANDER BOT AND THE TWO MEDPACK MODES (CNBalance/MedPack.lua). Post-hook on
    lua/bots/CommanderBrain.lua. The bot switches its own mode (MedPack_SetServerAreaHeal - it has no game to send it)
    and picks, for every medpack it drops:

      * WHEN IT DROPS (its own medpack logic - who needs one, when, saving up - bots/MarineCommanderBrain_Data.lua - is
        left as it is; every medpack it decides on passes through CommanderBrain:ExecuteTechId, where this plans it):
          - AREA HEAL (2 team res) when the team can pay it and either kMinAreaGroup (3) or more hurt Marines are inside
            the 4.5 m ring, or any hurt Marine there is within kHiveRushRange (20 m) of an enemy Hive (a Hive rush:
            sustained healing while they shoot). Placed at the middle of the hurt Marines.
          - MULTI MEDPACK otherwise: at the middle of the Marines who need a medpack (each gets one, 1 team res each,
            nearest the middle first if team res runs short). Marines there but none needs one: nothing is dropped (the
            medpack would refuse it). Nobody there at all: where the bot aimed (left on the ground to pick up).
        Who a drop reaches is measured exactly as the medpack does (MedPack_GetColumnTargets: the floor under the click,
        the 4.5 m heal column up to 12 m, line of sight).
      * HIVE RUSHES - placed on its own, every kRushCheckInterval (1.5 s): when 2 or more Marines are within kHiveRushRange
        of an enemy Hive and any of them is hurt, the bot places an Area Heal at the middle of the hurt ones, so they
        keep shooting at full health. Never two fields over the same Marines (a new one only where no field of the team
        already covers the spot, and at most one every kRushFieldGap (4 s) - a field lasts 5), and always keeping
        kRushResReserve (2) team res back beyond the field's cost.

    Field Marine bots: a hurt bot already heads for the nearest visible medpack - an Area Heal field is a MedPack too, so
    it walks into the ring (bots/MarineBrain_Data.lua, FIND MEDPACK, skips fields it is already inside -
    MedPack_BotShouldSeek). Multi Medpacks heal them where they stand.
]]

if not Server then return end

local kMinAreaGroup = 3
local kHiveRushRange = 20
local kRushCheckInterval = 1.5
local kRushFieldGap = 4
local kRushResReserve = 2

local function IsMarineTarget(player)
    return player:isa("Marine") and not player:isa("Exo") and player.GetIsAlive and player:GetIsAlive()
end

local function IsHurt(player)
    if GetIsBMACMarine and GetIsBMACMarine(player) then return player:GetArmor() < player:GetMaxArmor() end
    return player:GetHealth() < player:GetMaxHealth()
end

local function NeedsMed(player)
    return MedPack.GetIsValidRecipient(MedPack, player)
end

local function TeamRes(commander)
    return commander.GetTeamResources and commander:GetTeamResources() or 0
end

local function SetMode(commander, areaHeal)
    local client = commander.GetClient and commander:GetClient()
    if client and MedPack_SetServerAreaHeal then MedPack_SetServerAreaHeal(client, areaHeal) end
end

local function GetEnemyHiveNear(team, position, range)
    for _, hive in ientitylist(Shared.GetEntitiesWithClassname("Hive")) do
        if hive:GetTeamNumber() ~= team and hive:GetIsAlive() and (hive:GetOrigin() - position):GetLength() < range then
            return hive
        end
    end
    return nil
end

local function Middle(players)
    local sum = Vector(0, 0, 0)
    for _, player in ipairs(players) do sum = sum + player:GetOrigin() end
    return sum / #players
end

local function FieldCovers(team, position)
    for _, field in ientitylist(Shared.GetEntitiesWithClassname("MedPack")) do
        if field.tehIsField and field:GetTeamNumber() == team
                and (field:GetOrigin() - position):GetLengthXZ() < kMedFieldRadius then
            return true
        end
    end
    return false
end

-- The Marines a drop at `spot` would reach: exactly the medpack's own rule (floor under the click, 4.5 m heal column,
-- line of sight - MedPack_GetColumnTargets); a flat circle if that is not loaded.
local function GetReached(team, spot)
    if MedPack_GetColumnTargets then return MedPack_GetColumnTargets(team, spot, kMultiMedRadius) end
    local reached = {}
    for _, player in ipairs(GetEntitiesForTeamWithinXZRange("Player", team, spot, kMultiMedRadius)) do
        if IsMarineTarget(player) then reached[#reached + 1] = player end
    end
    return reached
end

--[[
    For a medpack the bot decided to drop around `spot`: Area Heal or not, and where - or nil to drop nothing.
      * Area Heal: hurt Marines there and the team can pay, with 3+ hurt or an enemy Hive near (middle of the hurt).
      * Multi Medpack: at the middle of the Marines who need one (each gets one; short of team res, the nearest the
        middle first). Marines there but none needs one -> nothing (the medpack would refuse it). Nobody there at all
        -> the spot itself (it is left on the ground to pick up).
]]
local function PlanDrop(commander, spot)
    local team = commander:GetTeamNumber()
    local reached = GetReached(team, spot)
    local hurt, needy = {}, {}
    for _, player in ipairs(reached) do
        if IsHurt(player) then
            hurt[#hurt + 1] = player
            if NeedsMed(player) then needy[#needy + 1] = player end
        end
    end
    if #hurt > 0 and TeamRes(commander) >= kMedFieldCost
            and (#hurt >= kMinAreaGroup or GetEnemyHiveNear(team, spot, kHiveRushRange)) then
        return true, Middle(hurt)
    end
    if #needy > 0 then return false, Middle(needy) end
    if #reached > 0 then return false, nil end
    return false, spot
end

local baseExecuteTechId = CommanderBrain.ExecuteTechId
function CommanderBrain:ExecuteTechId(commander, techId, position, hostEntity, targetId, trace)

    if techId == kTechId.MedPack and commander and commander:isa("MarineCommander") then
        local spot = position
        local target = targetId and Shared.GetEntity(targetId)
        if target and target.GetOrigin then spot = target:GetOrigin() end
        if spot then
            local ok, areaHeal, where = pcall(PlanDrop, commander, spot)
            if not ok then
                Shared.Message("[Medpack] commander bot: " .. tostring(areaHeal))
            elseif where then
                SetMode(commander, areaHeal)
                return baseExecuteTechId(self, commander, techId, where, hostEntity, nil, trace)
            else
                return   -- Marines there but none needs a medpack: drop nothing (it would be refused)
            end
        end
    end

    return baseExecuteTechId(self, commander, techId, position, hostEntity, targetId, trace)

end

-- ---- Hive rushes: the bot places Area Heals on its own -----------------------------------------------------------
local function RushTick(brain, bot)

    local now = Shared.GetTime()
    if (brain.tehRushNextCheck or 0) > now then return end
    brain.tehRushNextCheck = now + kRushCheckInterval
    if now < (brain.tehRushLastField or -100) + kRushFieldGap then return end

    local commander = bot.GetPlayer and bot:GetPlayer()
    if not commander or not commander:isa("MarineCommander") then return end
    if TeamRes(commander) < kMedFieldCost + kRushResReserve then return end

    local team = commander:GetTeamNumber()
    for _, hive in ientitylist(Shared.GetEntitiesWithClassname("Hive")) do
        if hive:GetTeamNumber() ~= team and hive:GetIsAlive() then
            local rushers, hurt = {}, {}
            for _, player in ipairs(GetEntitiesForTeamWithinRange("Player", team, hive:GetOrigin(), kHiveRushRange)) do
                if IsMarineTarget(player) then
                    rushers[#rushers + 1] = player
                    if IsHurt(player) then hurt[#hurt + 1] = player end
                end
            end
            if #rushers >= 2 and #hurt > 0 then
                local spot = Middle(hurt)
                if not FieldCovers(team, spot) then
                    brain.tehRushLastField = now
                    brain:ExecuteTechId(commander, kTechId.MedPack, spot, commander, nil, nil)
                    return
                end
            end
        end
    end

end

local baseUpdate = CommanderBrain.Update
function CommanderBrain:Update(bot, move, player)
    local result = baseUpdate(self, bot, move, player)
    local ok, err = pcall(RushTick, self, bot)
    if not ok and not CommanderBrain.tehRushError then
        CommanderBrain.tehRushError = true
        Shared.Message("[Medpack] commander bot hive rush: " .. tostring(err))
    end
    return result
end
