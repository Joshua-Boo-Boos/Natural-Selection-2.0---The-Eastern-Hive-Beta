function Flamethrower:CreateFlame(player, position, normal, direction)

    -- create flame entity, but prevent spamming:
    local nearbyFlames = GetEntitiesForTeamWithinRange("Flame", self:GetTeamNumber(), position, 1.7)

    if (#nearbyFlames == 0) then

        local flame = CreateEntity(Flame.kMapName, position, player:GetTeamNumber())
        flame:SetOwner(player)

        local coords = Coords.GetTranslation(position)

        if math.abs(Math.DotProduct(normal, direction)) > 0.9999 then
            direction = normal:GetPerpendicular()
        end

        coords.yAxis = normal
        coords.zAxis = direction

        coords.xAxis = coords.yAxis:CrossProduct(coords.zAxis)
        coords.xAxis:Normalize()

        coords.zAxis = coords.xAxis:CrossProduct(coords.yAxis)
        coords.zAxis:Normalize()

        flame:SetCoords(coords)

    end

end

-- Perf: identical burn behavior, but classes with zero live instances are
-- skipped via a cheap C-side count instead of paying a radius query per
-- flame step. Merge order of non-empty classes is preserved, so the
-- destroy/effect order matches the original exactly.
local kBurnBombClasses = {
    "Bomb", "WhipBomb", "AcidMissile", "AcidRocketBomb",
    "BabblerPheromone", "Spit", "DotMarker"
}

local kBurnCloudClasses -- { className, radius } pairs; built lazily so the
                        -- class constants referenced are already loaded.
local function GetBurnCloudClasses()
    if not kBurnCloudClasses then
        kBurnCloudClasses = {
            { "CragUmbra", CragUmbra.kRadius },
            { "StormCloud", StormCloud.kRadius },
            { "MucousMembrane", MucousMembrane.kRadius },
            { "EnzymeCloud", EnzymeCloud.kRadius },
            { "Vortex", Vortex.kRadius },
        }
    end
    return kBurnCloudClasses
end

function Flamethrower:BurnSporesAndUmbra(startPoint, endPoint)

    local now = Shared.GetTime()
    local timeLastBurn = self.timeLastBurn and now - self.timeLastBurn or 0
    self.timeLastBurn = now

    -- Which classes have any live instance at all this attack tick.
    local anySpores = Shared.GetEntitiesWithClassname("SporeCloud"):GetSize() > 0

    local liveBombClasses = {}
    for i = 1, #kBurnBombClasses do
        local name = kBurnBombClasses[i]
        if Shared.GetEntitiesWithClassname(name):GetSize() > 0 then
            liveBombClasses[#liveBombClasses + 1] = name
        end
    end

    local cloudClasses = GetBurnCloudClasses()
    local liveCloudClasses = {}
    for i = 1, #cloudClasses do
        local entry = cloudClasses[i]
        if Shared.GetEntitiesWithClassname(entry[1]):GetSize() > 0 then
            liveCloudClasses[#liveCloudClasses + 1] = entry
        end
    end

    if not anySpores and #liveBombClasses == 0 and #liveCloudClasses == 0 then
        return
    end

    local toTarget = endPoint - startPoint
    local length = toTarget:GetLength()
    toTarget:Normalize()

    local stepLength = 2
    for i = 1, 5 do

        -- stop when target has reached, any spores would be behind
        if length < i * stepLength then
            break
        end

        local burnSpent = false
        local checkAtPoint = startPoint + toTarget * i * stepLength

        if anySpores then
            local spores = GetEntitiesWithinRange("SporeCloud", checkAtPoint, kSporesDustCloudRadius)
            for j = 1, #spores do
                local spore = spores[j]
                self:DoDamage(kFlamethrowerSporeDamagePerSecond * timeLastBurn, spore, endPoint, nil)
            end
        end

        local bombs
        for j = 1, #liveBombClasses do
            local found = GetEntitiesWithinRange(liveBombClasses[j], checkAtPoint, 1.6)
            if bombs then
                table.copy(found, bombs, true)
            else
                bombs = found
            end
        end

        if bombs then
            for j = 1, #bombs do
                local bomb = bombs[j]
                bomb:TriggerEffects("burn_bomb", { effecthostcoords = Coords.GetTranslation(bomb:GetOrigin()) } )
                DestroyEntity(bomb)
                burnSpent = true
            end
        end

        local clouds
        for j = 1, #liveCloudClasses do
            local entry = liveCloudClasses[j]
            local found = GetEntitiesWithinRange(entry[1], checkAtPoint, entry[2])
            if clouds then
                table.copy(found, clouds, true)
            else
                clouds = found
            end
        end

        if clouds then
            for j = 1, #clouds do
                local cloud = clouds[j]
                self:TriggerEffects("burn_umbra", { effecthostcoords = Coords.GetTranslation(cloud:GetOrigin()) } )
                DestroyEntity(cloud)
                burnSpent = true
            end
        end

        if burnSpent then
            local owner = self:GetParent()
            if owner then
                owner:AddContinuousScore("FlameThrowerBurns",kFlameThrowerEntityBurnReward, kFlameThrowerEntityBurnRewardInterval,kFlameThrowerEntityBurnScoreRewardEachInterval,kFlameThrowerEntityBurnPResRewardEachInterval)
            end
            break
        end

    end

end
