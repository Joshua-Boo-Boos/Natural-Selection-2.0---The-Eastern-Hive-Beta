--[[
    BMAC character: when the per-round Marine choice window (GUIBMACRoundChoice.lua) appears. Post-hook on
    Player_Client.lua (client only).

    - It opens once when the player is in the ready room before a round has started (so everyone gets it, in case the
      shuffle puts them on Marines; the Commander too, who can leave the Chair mid-round).
    - It does not open again until the current round has ended; then it opens the next time they are in the ready room.
    - It closes when the countdown starts. Anything not chosen by then is random (server side).
    Per-frame cost: one game-state read and a few comparisons; nothing is allocated.
]]

if not Client then
    return
end

local gRoundChoice = { shown = false, roundRunning = false, script = nil, ownedSent = false }

--[[
    (2026-10-15) Tell the server which Marine skins this player owns: the server cannot check (vanilla GetOwnsItem is
    always true there), so without this its random pick could hand out a DLC skin the player doesn't own. Only the
    client can ask Steam. A "0"/"1" string by kMarineVariants id. Sent once after connecting and again every time the
    choice window opens (Steam's inventory may still be loading right after connecting). Not per frame.
]]
local function SendOwnedSkins()
    if not kMarineVariantsData or not kBMACOwnedSkinsMax then
        return
    end
    local bits = {}
    for variant = 1, kBMACOwnedSkinsMax do
        local owned = kMarineVariantsData[variant] ~= nil and GetHasVariant(kMarineVariantsData, variant)
        bits[variant] = owned and "1" or "0"
    end
    Client.SendNetworkMessage("BMACOwnedSkins", { owned = table.concat(bits) }, true)
end

local function CloseWindow()
    if gRoundChoice.script then
        GetGUIManager():DestroyGUIScript(gRoundChoice.script)
        gRoundChoice.script = nil
    end
end

local function UpdateRoundChoiceWindow()
    local gameInfo = GetGameInfoEntity()
    if not gameInfo then
        return
    end

    if not gRoundChoice.ownedSent and Client.GetLocalPlayer() then
        gRoundChoice.ownedSent = true
        SendOwnedSkins()
    end

    local state = gameInfo:GetState()
    if state == kGameState.Countdown or state == kGameState.Started then
        gRoundChoice.roundRunning = true
        CloseWindow()
        return
    end

    -- A round has just ended (won, drawn or reset): the window may open again.
    if gRoundChoice.roundRunning then
        gRoundChoice.roundRunning = false
        gRoundChoice.shown = false
    end

    if gRoundChoice.script and gRoundChoice.script.closed then
        CloseWindow()
    end

    if not gRoundChoice.shown then
        local player = Client.GetLocalPlayer()
        if player and player:GetTeamNumber() == kTeamReadyRoom then
            gRoundChoice.shown = true
            SendOwnedSkins()
            gRoundChoice.script = GetGUIManager():CreateGUIScript("CNBalance/BMAC/GUIBMACRoundChoice")
        end
    end
end

Event.Hook("UpdateClient", UpdateRoundChoiceWindow)
