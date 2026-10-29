--[[
    (2026-10-28) MEDPACK MODE SWITCH - CLIENT ONLY. POST hook on lua/GUIMinimapFrame.lua, registered AFTER the
    mod's own GUIMinimapFrame hooks so it wraps them.

      * Marine Commander: tap MMB to switch modes on release without selecting a medpack.
        Hold MMB for 0.3 seconds to ping once, without switching. Big-map order wheel is unchanged.
      * Every new Commander starts in Multi Medpack.
      * The switch changes, at once:
          - the medpack button's icon (ui/buildmenu.dds cell 223 = Multi Medpack, cell 224 = Area Heal);
          - its name and tooltip (Locale.lua: TEH_MEDMODE_MULTI_* / TEH_MEDMODE_AREA_*);
          - the "Medpack Mode:" line in the bottom-right of the Commander's screen, above the map order hints;
          - the server's copy of the mode (network message "TEHMedMode"), which decides what the drop does.
]]

if not Client then return end
if TEHMedModeInstalled then return end
TEHMedModeInstalled = true

local kMultiCell, kAreaCell = 223, 224
local areaHeal = false
local lastCommanderId
local lastBigMapOpen = -1
local label

function TEHMedMode_IsAreaHeal()
    return areaHeal
end

local function ApplyLocally()
    pcall(function()
        local offsets = debug.getupvaluex(GetMaterialXYOffset, "kTechIdToMaterialOffset")
        if offsets then offsets[kTechId.MedPack] = areaHeal and kAreaCell or kMultiCell end
    end)
    -- The Commander's placement ghost: the sentry battery for Area Heal, the medpack for Multi Medpack. The ghost reads
    -- the model from the tech data every frame (GhostModel:Update), so it changes even while the medpack is primed.
    pcall(function()
        local model = areaHeal and MedPack.kFieldModelName or MedPack.kModelName
        if model then SetCachedTechData(kTechId.MedPack, kTechDataModel, model, true) end
    end)
    -- The cost shown on the button's tooltip and the placement ghost (both read the tech data on the Commander's own
    -- game): Area Heal 2, Multi Medpack 1 (per medpack). Display only - this game's copy; the server charges as before
    -- (the drop 1, and a field 1 more).
    pcall(function()
        local cost = areaHeal and (kMedFieldCost or 2) or (kMedPackCost or 1)
        SetCachedTechData(kTechId.MedPack, kTechDataCostKey, cost, true)
    end)
    if kLocales then
        local prefix = areaHeal and "TEH_MEDMODE_AREA" or "TEH_MEDMODE_MULTI"
        kLocales["MED_PACK"] = rawget(kLocales, prefix .. "_NAME") or kLocales["MED_PACK"]
        kLocales["MED_PACK_TOOLTIP"] = rawget(kLocales, prefix .. "_TOOLTIP") or kLocales["MED_PACK_TOOLTIP"]
    end
end

function TEHMedMode_Set(value)
    areaHeal = value == true
    ApplyLocally()
    Client.SendNetworkMessage("TEHMedMode", { areaHeal = areaHeal }, true)
end

local function GetMarineCommander()
    local player = Client.GetLocalPlayer()
    return player and player.isa and player:isa("MarineCommander") and player or nil
end

local function IsBigMapOpen(self)
    return self.comMode == GUIMinimapFrame.kModeBig
        and self.GetBackground and self:GetBackground() ~= nil
        and self:GetBackground():GetIsVisible()
end

local function LabelText()
    return "Medpack Mode: " .. (areaHeal and "Area-Heal" or "Multi-Med") .. "   (Tap MMB: med mode / Hold 0.3s: ping)"
end

local labelBack

-- The top of the Commander's button tooltip box on screen while it is showing, else nil.
local function GetTooltipTop()
    local script = GetGUIManager():GetGUIScriptSingle("GUICommanderTooltip")
    local back = script and script.background
    if not back or not back:GetIsVisible() then return nil end
    return back:GetScreenPosition(Client.GetScreenWidth(), Client.GetScreenHeight()).y
end

local function UpdateLabel(show)
    if show and not label then
        -- A dark panel behind the text so it reads clearly over any scene.
        labelBack = GetGUIManager():CreateGraphicItem()
        labelBack:SetAnchor(GUIItem.Right, GUIItem.Bottom)
        labelBack:SetColor(Color(0, 0.03, 0.06, 0.7))
        labelBack:SetLayer(kGUILayerBigMap + 1)
        label = GetGUIManager():CreateTextItem()
        label:SetAnchor(GUIItem.Right, GUIItem.Bottom)
        label:SetFontName(Fonts.kAgencyFB_Small)
        label:SetTextAlignmentX(GUIItem.Align_Max)
        label:SetTextAlignmentY(GUIItem.Align_Min)
        label:SetLayer(kGUILayerBigMap + 2)
        label:SetColor(Color(0.6, 0.92, 1.0, 1))
    end
    if label then
        label:SetIsVisible(show)
        labelBack:SetIsVisible(show)
        if show then
            local text = LabelText()
            local scale = GUIScale(Vector(1, 1, 1))
            label:SetScale(scale)
            label:SetText(text)
            local width = label:GetTextWidth(text) * scale.x
            local height = label:GetTextHeight(text) * scale.y
            local pad = GUIScale(6)

            -- Bottom-right, one row above the map order hints (CNBalance/GUIMinimapFrame.lua: rows at -360 + 26 * row).
            -- While a button's tooltip box is showing it moves up to sit just above that box, and back when it closes.
            local y = -GUIScale(360)
            local ok, top = pcall(GetTooltipTop)
            if ok and top then
                y = math.min(y, top - Client.GetScreenHeight() - height - GUIScale(12))
            end
            label:SetPosition(Vector(-GUIScale(24), y, 0))
            labelBack:SetPosition(Vector(-GUIScale(24) - width - pad, y - pad * 0.5, 0))
            labelBack:SetSize(Vector(width + pad * 2, height + pad, 0))
        end
    end
end

--[[
    (2026-10-28) STICKY MEDPACK / AMMO PACK. NS2 clears the Commander's selected button after every placement
    (Commander:SendTargetedAction -> SetCurrentTech(kTechId.None)). For the Medpack and the Ammo Pack, a selection that
    was cleared BY A PLACEMENT (timeLastTargetedAction moved on) is selected again at once, so the Commander can keep
    left-clicking to drop more. Escape, right-click, another button or another menu clear or change it without a
    placement, so they still end it. Done each frame here rather than by changing the Commander class.
]]
local kStickyTech = { [kTechId.MedPack] = true, [kTechId.AmmoPack] = true }
local stickyLastTech, stickyLastActionTime
reselectMedPackAt = nil   -- (2026-10-28) the mode switch's deselect / reselect (crash fix, GUIMinimapFrame:SendKeyEvent)

local function UpdateReselect(commander)
    if not reselectMedPackAt or Shared.GetTime() < reselectMedPackAt then return end
    reselectMedPackAt = nil
    -- Only if nothing else was chosen meanwhile.
    if commander.currentTechId == kTechId.None then
        commander:SetCurrentTech(kTechId.MedPack)
        stickyLastTech = kTechId.MedPack
    end
end

local function UpdateSticky(commander)
    local current = commander.currentTechId
    local actionTime = commander.timeLastTargetedAction or 0
    if current == kTechId.None and stickyLastTech and kStickyTech[stickyLastTech]
            and stickyLastActionTime and actionTime > stickyLastActionTime then
        commander:SetCurrentTech(stickyLastTech)
        current = stickyLastTech
    end
    stickyLastTech, stickyLastActionTime = current, actionTime
end

local middlePress, middleCommander, middlePinged
local kPingHoldTime = 0.3

local function CancelMiddle()
    middlePress, middleCommander, middlePinged = nil, nil, nil
end

local function MiddleAllowed()
    local commander = GetMarineCommander()
    return commander and not ChatUI_EnteringChatMessage()
        and Shared.GetTime() - lastBigMapOpen > 0.2 and commander
end

local function UpdateMiddle()
    if not middlePress then return end
    local commander = MiddleAllowed()
    if not commander or commander:GetId() ~= middleCommander then CancelMiddle(); return end
    if not middlePinged and Shared.GetTime() - middlePress >= kPingHoldTime then
        middlePinged = true
        TEHMedMode_SendPing()
    end
end

function TEHMedMode_HandleMiddle(key, down)
    if key ~= InputKey.MouseButton2 then return false end
    local commander = MiddleAllowed()
    if not commander then CancelMiddle(); return false end
    if down then
        if not middlePress then
            middlePress, middleCommander, middlePinged = Shared.GetTime(), commander:GetId(), false
        end
    elseif middlePress then
        UpdateMiddle() -- A release after the threshold is still a hold, even between frames.
        if middlePress and not middlePinged then
            local selected = commander.currentTechId == kTechId.MedPack
            -- Destroy the old placement ghost before changing its model (engine crash workaround).
            if selected then commander:SetCurrentTech(kTechId.None) end
            TEHMedMode_Set(not areaHeal)
            if selected then reselectMedPackAt = Shared.GetTime() + 0.1 end
        end
        CancelMiddle()
    end
    return true
end

-- New Commander -> Multi Medpack; the label follows the local player being the Marine Commander.
Event.Hook("UpdateClient", function()
    local ok, err = pcall(function()
        UpdateMiddle()
        local commander = GetMarineCommander()
        if commander then
            UpdateReselect(commander)
            UpdateSticky(commander)
            local id = commander:GetId()
            if id ~= lastCommanderId then
                lastCommanderId = id
                TEHMedMode_Set(false)
            end
        else
            lastCommanderId = nil
            stickyLastTech, stickyLastActionTime = nil, nil
            reselectMedPackAt = nil
        end
        UpdateLabel(commander ~= nil)
    end)
    if not ok and not TEHMedModeError then
        TEHMedModeError = true
        Shared.Message("[Medpack Mode] " .. tostring(err))
    end
end)

local baseUpdate = GUIMinimapFrame.Update
function GUIMinimapFrame:Update(deltaTime)
    baseUpdate(self, deltaTime)
    if IsBigMapOpen(self) then lastBigMapOpen = Shared.GetTime(); CancelMiddle() end
end

local baseSendKeyEvent = GUIMinimapFrame.SendKeyEvent
function GUIMinimapFrame:SendKeyEvent(key, down)
    if IsBigMapOpen(self) then
        lastBigMapOpen = Shared.GetTime()
        CancelMiddle()
    elseif TEHMedMode_HandleMiddle(key, down) then
        return true
    end
    return baseSendKeyEvent(self, key, down)
end
