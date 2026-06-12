if Server and DamageMixin and not DamageMixin.kCNBalanceSpectatorOwnerGuard then

    DamageMixin.kCNBalanceSpectatorOwnerGuard = true

    local baseDoDamage = DamageMixin.DoDamage
    local nullSpectatorOwner =
    {
        GetSpectatingPlayer = function()
            return nil
        end
    }

    local function GetOwnerGuarded(baseGetOwner, entity)
        local owner = baseGetOwner(entity)
        if not owner and entity and entity:isa("Spectator") then
            return nullSpectatorOwner
        end
        return owner
    end

    function DamageMixin:DoDamage(...)

        local baseGetOwner = Server.GetOwner
        Server.GetOwner = function(entity)
            return GetOwnerGuarded(baseGetOwner, entity)
        end

        local args = { ... }
        local success, result = pcall(function()
            return baseDoDamage(self, unpack(args))
        end)

        Server.GetOwner = baseGetOwner

        if not success then
            error(result)
        end

        return result

    end

end
