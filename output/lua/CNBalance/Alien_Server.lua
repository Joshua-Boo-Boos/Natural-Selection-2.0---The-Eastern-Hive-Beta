local oldAlienCopyPlayerDataForReadyRoomFrom = Alien.CopyPlayerDataForReadyRoomFrom
function Alien:CopyPlayerDataForReadyRoomFrom(player)

    oldAlienCopyPlayerDataForReadyRoomFrom(self, player)
    
    local respawnMapName = ReadyRoomTeam.GetRespawnMapName(nil,player)
    local gestationMapName = respawnMapName == ReadyRoomEmbryo.kMapName and player.gestationClass or nil
    local isProwler = respawnMapName == Prowler.kMapName or gestationMapName == Prowler.kMapName
    local rappel = isProwler and 
                   ( player.twoHives or GetIsTechUnlocked( player, kTechId.Rappel ) )   

    self.twoHives = self.twoHives or rappel
    self.gestationClass = isProwler and gestationMapName or self.gestationClass

end

------------------------------------------------------------------------------------
-- TEH: AUTHORITATIVE alien-bot lifeform cap (anti Gorge-flood)
--
-- Enforced at the real evolution chokepoint (Alien:ProcessBuyAction) inside this
-- hooked, always-loaded core file -- NOT in the bot brain (which may not be loaded
-- on the server). A bot Alien physically cannot evolve into a lifeform the team is
-- already full of: its purchase is redirected to the cheapest open, available
-- lifeform, or rejected so it stays put and saves.
--
-- Lifeforms, cheapest -> most expensive: {techId, className (for :isa), mapName (for
-- gestationClass of in-progress eggs)}. Counts include alive evolved lifeforms AND
-- gestating eggs, so a simultaneous wave of evolutions cannot all slip through.
------------------------------------------------------------------------------------
local function TEH_GetLifeformList()
    local raw =
    {
        { kTechId.Gorge,   "Gorge",   "gorge"   },
        { kTechId.Prowler, "Prowler", "prowler" },
        { kTechId.Lerk,    "Lerk",    "lerk"    },
        { kTechId.Fade,    "Fade",    "fade"    },
        { kTechId.Vokex,   "Vokex",   "vokex"   },
        { kTechId.Onos,    "Onos",    "onos"    },
    }
    local list = {}
    for i = 1, #raw do
        if raw[i][1] ~= nil then list[#list + 1] = raw[i] end
    end
    return list
end

local function TEH_CountAndCaps(alien)
    local team = alien:GetTeamNumber()
    local list = TEH_GetLifeformList()
    local L = #list

    local counts, techForClass, techForMap = {}, {}, {}
    for i = 1, L do
        counts[list[i][1]]      = 0
        techForClass[list[i][2]] = list[i][1]
        techForMap[list[i][3]]   = list[i][1]
    end

    local N = 0
    for _, p in ipairs(GetEntitiesForTeam("Player", team)) do
        if not p:isa("Commander") then N = N + 1 end           -- field player (alive or dead)
        if p ~= alien and p.GetIsAlive and p:GetIsAlive() then
            if p:isa("Embryo") then
                local tech = p.gestationClass and techForMap[p.gestationClass]  -- map name!
                if tech then counts[tech] = counts[tech] + 1 end
            else
                for i = 1, L do
                    if p:isa(list[i][2]) then counts[list[i][1]] = counts[list[i][1]] + 1; break end
                end
            end
        end
    end

    local caps = {}
    if N > 0 and L > 0 then
        local base, rem = math.floor(N / L), N % L
        for idx = 1, L do
            local cap = base + ((idx > (L - rem)) and 1 or 0)   -- remainder to expensive lifeforms
            if cap < 1 then cap = 1 end
            caps[list[idx][1]] = cap
        end
    else
        for i = 1, L do caps[list[i][1]] = 0 end
    end

    return counts, caps, list
end

local function TEH_IsLifeformAvailable(alien, tech)
    local tree = alien.GetTechTree and alien:GetTechTree()
    local node = tree and tree:GetTechNode(tech)
    return node ~= nil and node:GetAvailable(alien, tech, false) == true
end

local kTEH_BaseAlienProcessBuyAction = Alien.ProcessBuyAction
function Alien:ProcessBuyAction(techIds)

    if Server and type(techIds) == "table" and self.GetIsVirtual and self:GetIsVirtual() then

        local counts, caps, list = TEH_CountAndCaps(self)

        -- Find the lifeform-gestate tech in this purchase (if any).
        local lifeIdx, lifeTech
        for i = 1, #techIds do
            for j = 1, #list do
                if techIds[i] == list[j][1] then lifeIdx, lifeTech = i, list[j][1]; break end
            end
            if lifeTech then break end
        end

        if lifeTech and (counts[lifeTech] or 0) >= (caps[lifeTech] or 0) then
            -- Over cap: redirect to the most underrepresented open + available lifeform.
            local swap, bestDeficit, bestCount
            for j = 1, #list do
                local t = list[j][1]
                local count = counts[t] or 0
                local cap = caps[t] or 0
                local deficit = cap - count
                if deficit > 0 and TEH_IsLifeformAvailable(self, t)
                        and (not swap or deficit > bestDeficit or (deficit == bestDeficit and count < bestCount)) then
                    swap = t
                    bestDeficit = deficit
                    bestCount = count
                end
            end
            if swap then
                techIds[lifeIdx] = swap
            else
                -- ...or, if the whole team is full, reject so the bot stays and saves.
                return false
            end
        end
    end

    return kTEH_BaseAlienProcessBuyAction(self, techIds)
end
