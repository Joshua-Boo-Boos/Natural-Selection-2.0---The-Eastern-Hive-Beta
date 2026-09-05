-- CNBalance/CombatEngineers_Chat.lua
-- Renders Combat Engineers announcements as "[Com. Eng.]: ..." in the marine team colour.
--
-- Neither of the two obvious routes gives both halves of that:
--
--   * The vanilla "Chat" network message is team-coloured, but Chat.lua ALWAYS prepends
--     "(Team) " / "(All) " (`teamOnly and locationNameText or "(All) "`) with no way to suppress it,
--     so announcements came out as "(Team) : [Com. Eng.] ...".
--   * ChatUI_AddSystemMessage writes a bare line with no prefix, but hard-codes the gold system
--     colour.
--
-- The message list those both write into (`chatMessages`) is a file-local in Chat.lua. It is however
-- an UPVALUE of ChatUI_AddSystemMessage, so debug.getupvaluex reaches it - the same technique this
-- mod already uses to reach kTechIdToMaterialOffset in TechTreeButtons.lua. That gives full control
-- over both the text and the colours, which is all that was missing.
--
-- Loaded post lua/Chat.lua.

if not Client then
    return
end

-- Re-fetched on EVERY call, never cached. ChatUI_GetMessages flushes the queue by REBINDING the
-- upvalue (`chatMessages = { }`), so a reference captured once would point at a discarded table from
-- the first flush onwards and every later announcement would silently vanish.
local function GetChatMessages()

    if not ChatUI_AddSystemMessage or not debug or not debug.getupvaluex then
        return nil
    end

    return debug.getupvaluex(ChatUI_AddSystemMessage, "chatMessages")
end

-- One entry is EIGHT values, matching what Chat.lua's own OnChatMessageInternal pushes:
--   prefix colour, prefix text, body colour, body text, isCommander, drawRookie, reserved, reserved
--
-- The prefix slot is left empty and the whole line carried as the body, which is what removes the
-- "(Team) " that the normal chat path is hard-wired to add.
function CombatEngineers_AddTeamChatLine(text)

    local chatMessages = GetChatMessages()
    if not chatMessages or not text then
        return false
    end

    local player = Client.GetLocalPlayer()
    if not player then
        return false
    end

    local teamNumber = player:GetTeamNumber()
    -- player.GetTeamType (DOT) for the existence test, player:GetTeamType() (COLON) for the call.
    -- Colon syntax in Lua is a call, not a member reference, so `player:GetTeamType and ...` is a
    -- syntax error - which took this whole file out of the build.
    local teamType   = player.GetTeamType and player:GetTeamType() or kMarineTeamType

    table.insert(chatMessages, GetColorForTeamNumber(teamNumber))
    table.insert(chatMessages, "")

    table.insert(chatMessages, kChatTextColor[teamType] or kChatTextColor[kMarineTeamType])
    table.insert(chatMessages, text)

    table.insert(chatMessages, false)
    table.insert(chatMessages, false)
    -- Reserved, as per Chat.lua.
    table.insert(chatMessages, 0)
    table.insert(chatMessages, 0)

    StartSoundEffect(player:GetChatSound())

    return true
end
