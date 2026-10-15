--[[
    BMAC character: Exo exit. Post-hook on Exo.lua, AFTER CNBalance/Exo.lua (whose AttemptToKill and
    PerformEject wraps these sit on top of).

    Both exit paths replace the Exo with a Marine and then set its armour from prevPlayerMaxArmor /
    prevPlayerArmor. For a BMAC that would be wrong (no BMAC bonus recompute, and 0 AP on the forced path).
    Replace destroys the Exo, so the saved entry AP and the owning client are read BEFORE the base runs;
    afterwards the new Marine is the client's controlling player.
]]

if not Server then
    return
end

local function SaveExitState(exo)
    return {
        armor = exo.prevPlayerArmor,   -- the BMAC's own AP, recorded on entry by Exo:CopyPlayerDataFrom
        client = Server.GetOwner(exo),
    }
end

local function RestoreExitState(saved)
    local client = saved.client
    local marine = client and client.GetControllingPlayer and client:GetControllingPlayer()
    if marine and marine:isa("Marine") then
        BMAC_RestoreAfterExoExit(marine, saved.armor)
    end
end

-- Ordinary ejection.
local basePerformEject = Exo.PerformEject
function Exo:PerformEject()
    local saved = SaveExitState(self)
    basePerformEject(self)
    RestoreExitState(saved)
end

-- Forced ejection on destruction (Emergency Ejection). Returns false when it replaced the Exo.
local baseAttemptToKill = Exo.AttemptToKill
if baseAttemptToKill then
    function Exo:AttemptToKill(damage, attacker, doer, point)
        local saved = SaveExitState(self)
        local allowKill = baseAttemptToKill(self, damage, attacker, doer, point)
        if allowKill == false then
            RestoreExitState(saved)
        end
        return allowKill
    end
end
