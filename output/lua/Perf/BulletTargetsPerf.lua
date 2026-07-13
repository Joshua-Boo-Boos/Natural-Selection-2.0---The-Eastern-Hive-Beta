-- Behavior-identical rewrite of vanilla GetBulletTargets
-- (NS2-Copy/ns2/lua/NS2Utility.lua:3225). Called for EVERY bullet fired on
-- both server and client. Changes vs vanilla, all allocation-only:
--   * traceFilter closure(s) built once per call, not once per iteration
--     (EntityFilterList captures the targets table by reference, so hits
--     added during the loop are still filtered on later iterations).
--   * directed extents computed once per call, not per iteration.
-- Trace types, masks, order and break conditions are copied verbatim.
--
-- kClientSideCaliberAdjustment is `local` in vanilla NS2Utility.lua (not a
-- global), so it isn't visible here - redeclared with vanilla's value.
local kClientSideCaliberAdjustment = 0.00

function GetBulletTargets(startPoint, endPoint, spreadDirection, bulletSize, filter)

    local targets = {}
    local hitPoints = {}
    local trace

    if Client then
        if bulletSize < 2 * kClientSideCaliberAdjustment then
            bulletSize = bulletSize / 2
        else
            bulletSize = bulletSize - kClientSideCaliberAdjustment
        end
    end

    local listFilter = EntityFilterList(targets)
    local traceFilter
    if filter then
        traceFilter = function(test)
            return listFilter(test) or filter(test)
        end
    else
        traceFilter = listFilter
    end

    local extents = GetDirectedExtentsForDiameter(spreadDirection, bulletSize)

    for _ = 1, 20 do

        trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Damage, PhysicsMask.Bullets, traceFilter)
        if not trace.entity then

            -- Limit the box trace to the point where the ray hit as an optimization.
            local boxTraceEndPoint = trace.fraction ~= 1 and trace.endPoint or endPoint
            trace = Shared.TraceBox(extents, startPoint, boxTraceEndPoint, CollisionRep.Damage, PhysicsMask.Bullets, traceFilter)

        end

        if trace.entity and not table.icontains(targets, trace.entity) then

            table.insert(targets, trace.entity)
            table.insert(hitPoints, trace.endPoint)

        end

        local deadTarget = trace.entity and HasMixin(trace.entity, "Live") and not trace.entity:GetIsAlive()
        local softTarget = trace.entity and HasMixin(trace.entity, "SoftTarget")
        local ragdollTarget = trace.entity and trace.entity:isa("Ragdoll")
        if (not trace.entity or not (deadTarget or softTarget or ragdollTarget)) or trace.fraction == 1 then
            break
        end

    end

    return targets, trace, hitPoints

end
