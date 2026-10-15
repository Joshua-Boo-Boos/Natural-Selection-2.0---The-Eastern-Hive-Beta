--[[
    BOT FIX: "lua/bots/CommonActions.lua:334: attempt to index local 'locGroup' (a nil value)". POST hook on
    lua/bots/LocationContention.lua (server, bots).

    The explore action (vanilla CommonActions.lua, and Combat's replacement of it) picks the next room from the map's
    location GRAPH, then asks the location CONTENTION tracker for that room's group and uses it without a nil check. On
    some maps a room is in the graph but the tracker never registered a group for it (seen: "Pit", reached from
    "Extraction"), so GetLocationGroup returned nil and every exploring bot raised a script error each think.

    Fix at the source: asking for a room the tracker does not know creates an EMPTY group for it on the spot (the
    tracker's own AddLocationGroup), so every caller gets a valid group - no players, no structures, not stale - and the
    bot simply treats that room as an ordinary empty one. Rooms the tracker already knows are untouched. An empty or
    missing name still returns nil, as before.
]]

if not LocationContention or not LocationContention.GetLocationGroup or LocationContention.tehMissingGroupFix then
    return
end
LocationContention.tehMissingGroupFix = true

local baseGetLocationGroup = LocationContention.GetLocationGroup

function LocationContention:GetLocationGroup(groupName)

    local locationGroup = baseGetLocationGroup(self, groupName)
    if locationGroup or type(groupName) ~= "string" or groupName == "" then
        return locationGroup
    end

    if self.locationGroupsByName and self.AddLocationGroup then
        self:AddLocationGroup(groupName)
        return self.locationGroupsByName[groupName]
    end

    return nil

end
