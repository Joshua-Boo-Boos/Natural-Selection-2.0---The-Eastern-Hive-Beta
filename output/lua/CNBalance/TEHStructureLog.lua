--[[
    (2026-10-28) [TEH Recycle Log] / [TEH Consume Log] - WHO RECYCLED OR CONSUMED WHAT, IN log-Server.txt ONLY.

    POST hook on BOTH lua/RecycleMixin.lua (Marine Commander recycling) and lua/ConsumeMixin.lua (Alien
    Commander consuming); each load wraps whichever mixin now exists, once.

      * SERVER ONLY. The file returns straight away on clients and predict, and the lines are written with
        Shared.Message on the server - so they go to the server's log and console only. Nothing is sent to any
        player's game, so nobody can see it in game or in their own log (no metagaming).
      * One line per structure: a Commander recycling 10 structures gives 10 lines.
      * The Commander is recorded when the recycle / consume is STARTED (the player who ordered it) and the line
        is written when it COMPLETES - a cancelled one logs nothing.
      * Player name, Steam ID ([U:1:<id>] - paste into steamid.io; "BOT" for a bot Commander), UK date and time
        (GMT, or BST in summer - worked out from UTC, so the server's own time zone does not matter), the
        structure, where it was, its team and the team res it gave back.
      * Search log-Server.txt for:  [TEH Recycle Log]   or   [TEH Consume Log]
      * Every step is pcall-guarded: logging can never break recycling or consuming.
]]

if not Server then return end

local function DayOfWeek(y, m, d)   -- 0 = Sunday (Sakamoto)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then y = y - 1 end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end

-- UK local time: BST from 01:00 UTC on the last Sunday of March to 01:00 UTC on the last Sunday of October.
local function UKTime()
    local ok, text = pcall(function()
        local now = os.time()
        local u = os.date("!*t", now)
        local marchSun = 31 - DayOfWeek(u.year, 3, 31)
        local octSun = 31 - DayOfWeek(u.year, 10, 31)
        local key = u.month * 1000000 + u.day * 10000 + u.hour * 100 + u.min
        if key >= 3 * 1000000 + marchSun * 10000 + 100 and key < 10 * 1000000 + octSun * 10000 + 100 then
            return os.date("!%d/%m/%Y %H:%M:%S", now + 3600) .. " BST"
        end
        return os.date("!%d/%m/%Y %H:%M:%S", now) .. " GMT"
    end)
    return ok and text or "unknown time"
end

local function Who(commander)
    if not commander then return "no Commander", "none" end
    local name = commander.GetName and commander:GetName() or "unknown"
    local client = commander.GetClient and commander:GetClient()
    if not client then return name, "unknown" end
    if client.GetIsVirtual and client:GetIsVirtual() then return name .. " (BOT)", "BOT" end
    local id = client.GetUserId and client:GetUserId() or 0
    return name, string.format("[U:1:%d]", id)
end

local function TeamRes(self)
    local team = self.GetTeam and self:GetTeam()
    return team and team.GetTeamResources and team:GetTeamResources() or nil
end

local function Remember(self)
    local team = self.GetTeam and self:GetTeam()
    self.tehStructLogName, self.tehStructLogSteamId = Who(team and team.GetCommander and team:GetCommander())
end

local function Write(self, tag, verb, resBefore)
    local name, steamId = self.tehStructLogName, self.tehStructLogSteamId
    if not name then
        Remember(self)
        name, steamId = self.tehStructLogName, self.tehStructLogSteamId
    end
    local what = EnumToString(kTechId, self:GetTechId()) or self:GetClassName()
    local where = self.GetLocationName and self:GetLocationName() or ""
    if where == "" then where = "unknown location" end
    local resAfter = TeamRes(self)
    local refund = (resBefore and resAfter) and math.floor(resAfter - resBefore + 0.5) or 0
    Shared.Message(string.format("%s %s | %s | Steam ID %s | %s %s (entity %d) in %s | team %d | refund %d t-res",
        tag, UKTime(), name, steamId, verb, what, self:GetId(), where, self:GetTeamNumber(), refund))
end

local function Wrap(mixin, techName, doneField, tag, verb)
    if not mixin or mixin.tehStructLogWrapped then return end
    mixin.tehStructLogWrapped = true

    local baseOnResearch = mixin.OnResearch
    mixin.OnResearch = function(self, researchId, ...)
        local result
        if baseOnResearch then result = baseOnResearch(self, researchId, ...) end
        if researchId == kTechId[techName] then pcall(Remember, self) end
        return result
    end

    local baseComplete = mixin.OnResearchComplete
    mixin.OnResearchComplete = function(self, researchId, ...)
        local isOurs = researchId == kTechId[techName]
        local resBefore = isOurs and select(2, pcall(TeamRes, self)) or nil
        local result = baseComplete and baseComplete(self, researchId, ...)
        if isOurs and self[doneField] and not self.tehStructLogDone then
            self.tehStructLogDone = true
            local ok, err = pcall(Write, self, tag, verb, type(resBefore) == "number" and resBefore or nil)
            if not ok then Shared.Message(tag .. " (logging error: " .. tostring(err) .. ")") end
        end
        return result
    end
end

if rawget(_G, "RecycleMixin") then Wrap(RecycleMixin, "Recycle", "recycled", "[TEH Recycle Log]", "recycled") end
if rawget(_G, "ConsumeMixin") then Wrap(ConsumeMixin, "Consume", "consumed", "[TEH Consume Log]", "consumed") end
