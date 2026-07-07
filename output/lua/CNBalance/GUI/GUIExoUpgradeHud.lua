-- CNBalance/GUI/GUIExoUpgradeHud.lua
-- Exosuit combo name + equipped Prototype upgrade panel for the local Exo player.
-- Styled to match the marine upgrade panel (GUIMarineHUD): a subtle dark backing
-- with right-aligned text, anchored to the RIGHT edge in the lower half so it does
-- not overlap the centre/upper HUD elements.
--
-- Combo name is derived CLIENT-SIDE from the equipped ExoWeaponHolder's
-- leftWeaponId / rightWeaponId (both networked entityids).
--
-- Registered in CNBalance/ClientUI.lua under kShowAsClass["Exo"].

class 'GUIExoUpgradeHud' (GUIScript)

-- Panel uses Middle/Center anchor (the only root-item anchor that reliably maps
-- to screen coordinates in NS2).  Positioned at the same bottom-left corner as
-- the marine Jetpack panel so the Exo player sees their info in the same spot.
local kPanelW          = 230
local kPanelLeftInset  = 185    -- px from screen left edge (matches kJPPanelLeftInset)
local kPanelBottomInset= 48     -- px from screen bottom     (matches kJPPanelBottomInset)
local kPadX            = 12
local kPadY            = 10
local kLineHeight      = 20     -- px per line (pre-scale)

local kFontName     = Fonts.kAgencyFB_Small
local kFontScale    = GUIScale(Vector(1, 1, 0))
local kColorText    = Color(0.85, 0.9, 0.95, 0.95)
local kBgColor      = Color(0.05, 0.09, 0.12, 0.55)

-- Weapon-slot → display name. Railgun entities carry a networked weaponMode
-- (kExoSpecialMode) that selects the name; mode==Railgun (or absent) → "Railgun".
local function GetSlotDisplayName(entity)
    if not entity then return "?" end
    if entity:isa("Minigun") then
        return "Minigun"
    elseif entity:isa("Railgun") then
        local mode = entity.GetWeaponMode and entity:GetWeaponMode() or (kExoSpecialMode and kExoSpecialMode.Railgun)
        if kExoSpecialMode and mode == kExoSpecialMode.Flamethrower then
            return "Flamethrower"
        elseif kExoSpecialMode and mode == kExoSpecialMode.Welder then
            return "Welder"
        elseif kExoSpecialMode and mode == kExoSpecialMode.Grenade then
            return "Grenade Launcher"
        else
            return "Railgun"
        end
    elseif entity:isa("Claw") then
        return "Claw"
    end
    return tostring(entity:GetClassName())
end

function GUIExoUpgradeHud:Initialize()

    -- Middle/Center anchor: same reliable screen-space approach as the marine panels.
    -- Position is updated each frame in Update using Client.GetScreen{Width,Height}.
    self.background = GetGUIManager():CreateGraphicItem()
    self.background:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.background:SetColor(kBgColor)
    self.background:SetSize(GUIScale(Vector(kPanelW, 0, 0)))
    self.background:SetLayer(kGUILayerPlayerHUDForeground2)
    self.background:SetIsVisible(false)

    self.text = GetGUIManager():CreateTextItem()
    self.text:SetFontName(kFontName)
    self.text:SetScale(kFontScale)
    self.text:SetColor(kColorText)
    self.text:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.text:SetTextAlignmentX(GUIItem.Align_Min)
    self.text:SetTextAlignmentY(GUIItem.Align_Min)
    self.text:SetPosition(GUIScale(Vector(kPadX, kPadY, 0)))
    self.text:SetText("")
    self.background:AddChild(self.text)

    -- Welding percentage window — a small centered box below the crosshair (mirrors
    -- the Cannon Charge-Shot readout).  Shown only while an active welder arm is
    -- pointed at a friendly weldable target; displays that target's repair %.
    self.weldBoxW = 170
    self.weldBoxH = 40
    self.weldBg = GetGUIManager():CreateGraphicItem()
    self.weldBg:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.weldBg:SetSize(GUIScale(Vector(self.weldBoxW, self.weldBoxH, 0)))
    self.weldBg:SetPosition(GUIScale(Vector(-self.weldBoxW * 0.5, 96, 0)))
    self.weldBg:SetColor(Color(0, 0, 0, 0.5))
    self.weldBg:SetLayer(kGUILayerPlayerHUDForeground2)
    self.weldBg:SetIsVisible(false)

    self.weldText = GetGUIManager():CreateTextItem()
    self.weldText:SetFontName(Fonts.kAgencyFB_Small)
    self.weldText:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.weldText:SetTextAlignmentX(GUIItem.Align_Center)
    self.weldText:SetTextAlignmentY(GUIItem.Align_Center)
    self.weldText:SetPosition(Vector(0, 0, 0))
    self.weldText:SetColor(Color(0.6, 0.92, 1.0, 1))
    self.weldText:SetText("WELDING 0%")
    self.weldBg:AddChild(self.weldText)

    self.isVisible = false
end

function GUIExoUpgradeHud:Uninitialize()
    if self.background then
        GUI.DestroyItem(self.background)   -- text child destroyed with it
        self.background = nil
        self.text       = nil
    end
    if self.weldBg then
        GUI.DestroyItem(self.weldBg)       -- weldText child destroyed with it
        self.weldBg   = nil
        self.weldText = nil
    end
end

function GUIExoUpgradeHud:GetIsVisible()
    return self.isVisible
end

function GUIExoUpgradeHud:SetIsVisible(isVisible)
    self.isVisible = isVisible
    if self.background then
        self.background:SetIsVisible(isVisible)
    end
end

function GUIExoUpgradeHud:Update(_deltaTime)

    local player = Client.GetLocalPlayer()
    local isExo  = player and player:isa("Exo")

    if not isExo then
        if self.isVisible then
            self.isVisible = false
            self.background:SetIsVisible(false)
        end
        if self.weldBg then self.weldBg:SetIsVisible(false) end
        return
    end

    local lines = { "EXOSUIT" }

    -- Combo name from the equipped weapons.
    local holder = player.GetActiveWeapon and player:GetActiveWeapon()
    if holder and holder:isa("ExoWeaponHolder") then
        local leftEnt  = Shared.GetEntity(holder.leftWeaponId)
        local rightEnt = Shared.GetEntity(holder.rightWeaponId)
        table.insert(lines, GetSlotDisplayName(leftEnt) .. " / " .. GetSlotDisplayName(rightEnt))
    end

    -- Equipped prototype upgrades.
    if player.GetPrototypeUpgradeList then
        for _, techId in ipairs(player:GetPrototypeUpgradeList()) do
            table.insert(lines, GetDisplayNameForTechId(techId))
        end
    end

    self.text:SetText(table.concat(lines, "\n"))

    -- Dynamic width: widest line (text is left-aligned at kPadX) + margin each side.
    local textScale = self.text:GetScale().x
    local maxW = 0
    for _, line in ipairs(lines) do
        maxW = math.max(maxW, self.text:GetTextWidth(line) * textScale)
    end
    local w  = maxW + GUIScale(kPadX) * 2

    local h  = #lines * GUIScale(kLineHeight) + GUIScale(kPadY) * 2
    local sw = Client.GetScreenWidth()
    local sh = Client.GetScreenHeight()
    self.background:SetSize(Vector(w, h, 0))
    -- Middle/Center anchor: X = -sw/2 + leftInset, Y = sh/2 - bottomInset - h
    self.background:SetPosition(Vector(
        -sw * 0.5 + GUIScale(kPanelLeftInset),
         sh * 0.5 - GUIScale(kPanelBottomInset) - h,
        0))

    if not self.isVisible then
        self.isVisible = true
        self.background:SetIsVisible(true)
    end

    -- ── Welding percentage window ────────────────────────────────────────────
    -- Visible only while an active welder-mode arm is pointed at a friendly
    -- weldable target; shows that target's repair progress (health scalar).
    if self.weldBg then
        -- Show weld display whenever any arm is in Welder mode (regardless of button).
        -- We removed railgunAttacking from Welder, so detect mode presence alone.
        local welding = false
        if holder and holder:isa("ExoWeaponHolder") and kExoSpecialMode then
            for _, wid in ipairs({ holder.leftWeaponId, holder.rightWeaponId }) do
                local w = Shared.GetEntity(wid)
                if w and w:isa("Railgun") and w.GetWeaponMode
                   and w:GetWeaponMode() == kExoSpecialMode.Welder then
                    welding = true
                    break
                end
            end
        end

        local show, pct = false, 0
        if welding then
            local startPoint = player:GetEyePos()
            local viewCoords = player:GetViewCoords()
            local endPoint   = startPoint + viewCoords.zAxis * 2.8   -- ~kExoWeldRange
            local trace = Shared.TraceRay(startPoint, endPoint, CollisionRep.Default,
                                          PhysicsMask.AllButPCsAndRagdolls, EntityFilterOne(player))
            local target = trace.entity
            if target and HasMixin(target, "Weldable") and HasMixin(target, "Team")
               and target:GetTeamNumber() == player:GetTeamNumber() and target.GetHealthScalar then
                show = true
                pct  = math.floor(Clamp(target:GetHealthScalar(), 0, 1) * 100 + 0.5)
            end
        end

        self.weldBg:SetIsVisible(show)
        if show then
            self.weldText:SetText(string.format("WELDED %d%%", pct))
        end
    end
end
