-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIInsight_PlayerFrames.lua =======
--
-- Post-hook on lua/GUIInsight_PlayerFrames.lua (spectator player list).
--
-- Exo:GetPlayerStatusDesc (CNBalance/Exo.lua) now reports per-combo statuses
-- ("Dual-FT Exo", "Claw-Minigun Exo+", …) instead of a flat "Exo".  The spectator
-- player-frame per-row weapon icon is chosen from a file-local kIconCoords table
-- keyed by the RESOLVED status text, so those new combo strings would miss the
-- table and draw no icon.  Re-map every combo status text (with and without the
-- "+" experimental-tech suffix) to the SAME Exo icon the flat "Exo" status used.

local kIconCoords = debug.getupvaluex(GUIInsight_PlayerFrames.UpdatePlayer, "kIconCoords")

if kIconCoords then

    local exoCoords = kIconCoords[Locale.ResolveString("STATUS_EXO")]
    if exoCoords then
        local comboKeys = {
            "STATUS_EXO_DUAL_MINIGUN", "STATUS_EXO_DUAL_RAIL", "STATUS_EXO_DUAL_FT",
            "STATUS_EXO_CLAW_MINIGUN", "STATUS_EXO_CLAW_RAIL", "STATUS_EXO_CLAW_FT",
            "STATUS_EXO_DUAL_MINIGUN_PLUS", "STATUS_EXO_DUAL_RAIL_PLUS", "STATUS_EXO_DUAL_FT_PLUS",
            "STATUS_EXO_CLAW_MINIGUN_PLUS", "STATUS_EXO_CLAW_RAIL_PLUS", "STATUS_EXO_CLAW_FT_PLUS",
        }
        for _, key in ipairs(comboKeys) do
            kIconCoords[Locale.ResolveString(key)] = exoCoords
        end
    end

    debug.setupvaluex(GUIInsight_PlayerFrames.UpdatePlayer, "kIconCoords", kIconCoords)
end
