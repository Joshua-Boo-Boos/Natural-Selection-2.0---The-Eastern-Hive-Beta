-- Behavior-identical rewrite of vanilla AttackMeleeCapsule
-- (NS2-Copy/ns2/lua/NS2Utility.lua:2612). This is the alien-side equivalent
-- of the GetBulletTargets fix: it runs for EVERY melee swing (Skulk bite,
-- Fade swipe, Lerk bite, Onos gore, Gorge heal-spray, etc.) on both server
-- and client, and each swing fans out to up to 20 CheckMeleeCapsule calls,
-- each firing 9 box traces (the 3x3 kTraceOrder grid).
--
-- The only change is allocation, and it is provably hit-identical:
--   * Vanilla rebuilds `traceFilter` once per loop iteration (up to 20x), and
--     inside it calls EntityFilterList(targets) on EVERY entity the engine
--     trace tests - allocating a fresh closure per test. Since
--     EntityFilterList(list) returns `function(test) table.icontains(list,test) end`
--     it closes over the SAME `targets` table by reference and reads it live
--     via table.icontains at call time. Building that closure ONCE and reusing
--     it therefore returns exactly the same result as targets accumulate -
--     no target can be dropped or double-counted. Identical to the reasoning
--     already proven safe in BulletTargetsPerf.lua.
--
-- Trace order, priority function, surface logic, DoDamage calls, break
-- conditions, hitreg analysis and the accuracy-stat tail are copied verbatim.
-- CheckMeleeCapsule / PerformGradualMeleeAttack are intentionally left as
-- vanilla.

function AttackMeleeCapsule(weapon, player, damage, range, optionalCoords, altMode, filter)

    local targets = {}
    local didHit, target, endPoint, direction, surface, startPoint, trace

    if not filter then
        filter = EntityFilterTwo(player, weapon)
    end

    -- EntityFilterList captures `targets` by reference and reads it live, so
    -- these two closures are built once and reused across every iteration and
    -- every engine trace test (vs. vanilla allocating per test).
    local listFilter = EntityFilterList(targets)
    local traceFilter = function(test)
        return listFilter(test) or filter(test)
    end

    -- loop upto 20 times just to go through any soft targets.
    -- Stops as soon as nothing is hit or a non-soft target is hit
    for i = 1, 20 do

        -- Enable tracing on this capsule check, last argument.
        didHit, target, endPoint, direction, surface, startPoint, trace = CheckMeleeCapsule(weapon, player, damage, range, optionalCoords, true, 1, nil, traceFilter)
        local alreadyHitTarget = target ~= nil and table.icontains(targets, target)

        if didHit and not alreadyHitTarget then
            weapon:DoDamage(damage, target, endPoint, direction, surface, altMode)
        end

        if target and not alreadyHitTarget then
            table.insert(targets, target)
        end

        if not target or not HasMixin(target, "SoftTarget") then
            break
        end

    end

    HandleHitregAnalysis(player, startPoint, endPoint, trace)

    local lastTarget = targets[#targets]

    -- Handle Stats
    if Server then

        local parent = weapon and weapon.GetParent and weapon:GetParent()
        if parent and weapon.GetTechId then

            -- Drifters, buildings and teammates don't count towards accuracy as hits or misses
            if (lastTarget and lastTarget:isa("Player") and GetAreEnemies(parent, lastTarget)) or lastTarget == nil then

                local steamId = parent:GetSteamId()
                if steamId then
                    StatsUI_AddAccuracyStat(steamId, weapon:GetTechId(), lastTarget ~= nil, lastTarget and lastTarget:isa("Onos"), weapon:GetParent():GetTeamNumber())
                end
            end
            GetBotAccuracyTracker():AddAccuracyStat(parent:GetClient(), lastTarget ~= nil, kBotAccWeaponGroup.Melee)
        end
    end

    return didHit, lastTarget, endPoint, surface

end
