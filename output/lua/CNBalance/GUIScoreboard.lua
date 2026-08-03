-- ======= NS2.0-TEH-Beta: CNBalance/GUIScoreboard.lua =======
--
-- Post-hook on lua/GUIScoreboard.lua.
--
-- Exo:GetPlayerStatusDesc (CNBalance/Exo.lua) reports the exact combo name for an exo
-- ("Dual-FT Exo", "Claw-Minigun Exo+", …), and Scoreboard_ReloadPlayerData resolves it
-- to that clean string. Every code path in the latest vanilla + this mod leaves it clean.
--
-- However, an EXTERNAL scoreboard add-on (a CHUD/Workshop "show weapon on scoreboard"
-- feature that is NOT part of this source tree) appends the exo's underlying weapon name
-- ("Rail"/"Minigun"/…) onto the status column, producing e.g. "Dual-FT Exo+Rail" that
-- overruns into the score column. We cannot edit that add-on at its source, so we scrub
-- the status text back to the pure combo name AFTER each team update: for any status row
-- that begins with one of our combo names, we force the label to exactly that name.
-- (No-op for every non-exo row and when no external add-on is present.)

-- Longest-first so the "…+" (Experimental Tech) variants win before their non-"+" base.
local kExoStatusLocaleKeys =
{
    "STATUS_EXO_DUAL_MINIGUN_PLUS", "STATUS_EXO_DUAL_RAIL_PLUS", "STATUS_EXO_DUAL_FT_PLUS",
    "STATUS_EXO_CLAW_MINIGUN_PLUS", "STATUS_EXO_CLAW_RAIL_PLUS", "STATUS_EXO_CLAW_FT_PLUS",
    "STATUS_EXO_DUAL_MINIGUN", "STATUS_EXO_DUAL_RAIL", "STATUS_EXO_DUAL_FT",
    "STATUS_EXO_CLAW_MINIGUN", "STATUS_EXO_CLAW_RAIL", "STATUS_EXO_CLAW_FT",
}

-- Resolved once, then sorted longest-first (so "Dual-Minigun Exo+" is tested before
-- "Dual-Minigun Exo", and neither is shadowed by a shorter prefix).
local gExoStatusNames
local function GetExoStatusNames()
    if not gExoStatusNames then
        gExoStatusNames = {}
        for _, key in ipairs(kExoStatusLocaleKeys) do
            local name = Locale.ResolveString(key)
            if name and name ~= "" and name ~= key then
                table.insert(gExoStatusNames, name)
            end
        end
        table.sort(gExoStatusNames, function(a, b) return #a > #b end)
    end
    return gExoStatusNames
end

-- Exo combo names are wide; at full size the trailing "+" runs under the Score column. We
-- shrink ONLY exo status labels (not the numeric columns or headers, so nothing misaligns and
-- the name is never touched) so the whole name incl. "+" fits its existing column space.
local kExoStatusFontScale = 0.82

local function ScrubExoStatus(player)
    local statusItem = player and player["Status"]
    if not statusItem then return end

    local text = statusItem:GetText()
    local isExo = false
    if text and text ~= "" then
        for _, name in ipairs(GetExoStatusNames()) do
            if text == name then
                isExo = true
                break
            elseif string.sub(text, 1, #name) == name then
                -- Row begins with a known combo name but has trailing add-on text → trim it.
                statusItem:SetText(name)
                isExo = true
                break
            end
        end
    end

    local scale = GUIScoreboard.kScalingFactor or 1
    if isExo then
        statusItem:SetScale(Vector(kExoStatusFontScale, kExoStatusFontScale, 1) * scale)
    else
        -- Reset any previously-shrunk row back to the normal status size.
        statusItem:SetScale(Vector(1, 1, 1) * scale)
    end
end

local baseUpdateTeam = GUIScoreboard.UpdateTeam
function GUIScoreboard:UpdateTeam(updateTeam)
    baseUpdateTeam(self, updateTeam)

    local playerList = updateTeam and updateTeam["PlayerList"]
    if playerList then
        for _, player in ipairs(playerList) do
            ScrubExoStatus(player)
        end
    end
end

