-- The BI9's tech id, added with the same appender as lua/BIHC/TechTreeConstants.lua (see its notes): it takes
-- Max's slot when that is free and then moves Max above everything, so it can never share a number with
-- another mod's tech id whichever appender that mod uses or whichever order the mods load in.
-- Named "bi9" like the standalone mod, so its weapon file (BI9.lua) is used unchanged.
local function AppendTechId(tbl, key)

    if rawget(tbl, key) ~= nil then return end

    local highest = 0
    for k in next, tbl do
        if type(k) == "number" and k > highest then highest = k end
    end

    local maxVal = rawget(tbl, "Max")

    -- Max's slot is only taken if Max has it to itself. Another mod's earlier EnumUtils call may already have
    -- moved Max onto a number a debug.appendtoenum id holds; that shared number is never handed out again.
    local maxSlotFree = type(maxVal) == "number"
    if maxSlotFree then
        for k, v in next, tbl do
            if v == maxVal and k ~= "Max" then maxSlotFree = false break end
        end
    end

    if maxSlotFree then
        rawset(tbl, key, maxVal)
        rawset(tbl, maxVal, key)
        rawset(tbl, "Max", highest + 1)
        rawset(tbl, highest + 1, "Max")
    else
        rawset(tbl, key, highest + 1)
        rawset(tbl, highest + 1, key)
        if type(maxVal) == "number" then
            rawset(tbl, "Max", highest + 2)
            rawset(tbl, highest + 2, "Max")
        end
    end

end

AppendTechId(kTechId, "bi9")
