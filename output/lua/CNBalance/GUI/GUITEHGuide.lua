-- CNBalance/GUI/GUITEHGuide.lua
-- The in-game guide window: a title, a row of page buttons and a scrollable column of centred text.
--
-- Opened and closed with the "Guide" key (Options -> Mods -> NS2.0-TEH, default 0), the !guide chat command or the
-- "guide" console command (CNBalance/TEHGuide_Client.lua). Esc or the X button also close it. Works at any time:
-- Ready Room, either team, dead, spectating or commanding.
--
-- The text itself lives in kTEHGuide (CNBalance/GUI/TEHGuide_Content.lua), which is the only file that differs
-- between NS2.0-TEH (Main/Beta/Event), Siege2.0-TEH and Defense2.0-TEH. This file is identical in all five mods.
--
-- Client only. A plain GUIScript, not a networked class, so it costs nothing against the network class limit.

Script.Load("lua/CNBalance/GUI/TEHGuide_Content.lua")

class 'GUITEHGuide' (GUIScript)

local kPanelColor    = Color(0.04, 0.06, 0.09, 0.96)
local kBorderColor   = Color(0.35, 0.55, 0.75, 0.9)
local kViewColor     = Color(0, 0, 0, 0.35)
local kButtonColor   = Color(0.16, 0.2, 0.28, 0.95)
local kButtonHover   = Color(0.24, 0.3, 0.4, 1)
local kButtonActive  = Color(0.22, 0.42, 0.6, 1)
local kTrackColor    = Color(1, 1, 1, 0.08)
local kThumbColor    = Color(0.6, 0.75, 0.9, 0.7)
local kTitleColor    = Color(1, 0.85, 0.35, 1)
local kWhite         = Color(1, 1, 1, 1)

-- Named colours the content file can use for headings and paragraphs.
kTEHGuideColors =
{
    marine  = Color(147 / 255, 206 / 255, 1, 1),    -- NS2's Marine team text colour
    alien   = Color(1, 0.62, 0.24, 1),               -- Kharaa orange
    cyan    = Color(0.45, 0.9, 0.85, 1),
    gold    = Color(1, 0.85, 0.35, 1),
    green   = Color(0.45, 1, 0.5, 1),
    red     = Color(1, 0.4, 0.4, 1),
    purple  = Color(0.8, 0.6, 1, 1),
    text    = Color(0.9, 0.92, 0.95, 1),
    dim     = Color(0.65, 0.7, 0.75, 1),
}

-- Text styles: font, scale (before GUIScale), bold, gap above the block and the default colour. A heading ("h") also
-- gets a thin rule in its own colour underneath it.
local kStyles =
{
    title   = { font = Fonts.kAgencyFB_Large,  scale = 1.1,  bold = true,  gap = 0,  color = "gold" },
    h       = { font = Fonts.kAgencyFB_Large,  scale = 0.8,  bold = true,  gap = 34, color = "cyan" },
    s       = { font = Fonts.kAgencyFB_Medium, scale = 0.9,  bold = true,  gap = 16, color = "gold" },
    p       = { font = Fonts.kAgencyFB_Small,  scale = 1.05, bold = false, gap = 6,  color = "text" },
}
local kRuleWidth = 0.45     -- fraction of the text width
local kRuleGap = 6          -- pixels below the heading

local kLayerPanel  = kGUILayerScoreboard
local kLayerWidget = kGUILayerCountDown
local kLayerText   = kGUILayerTestEvents

-- (2026-10-26) The "Show Guide Upon Join" checkbox at the bottom of the window. The same option as the switch in
-- Options -> Mods (CNBalance/TEHGuide_ModsMenuData.lua) - read and written here directly, so the two always agree.
-- The literal must match kShowOnJoinOption in CNBalance/TEHGuide_Client.lua.
local kShowOnJoinOption = "TEHGuide/ShowOnJoin"
local kShowOnJoinLabel = "Show Guide Upon Join"
local kShowOnJoinWidget = "ns2TehGuideShowOnJoin"   -- the Options -> Mods checkbox's name

local kScrollStep = 60      -- pixels (before GUIScale) per mouse wheel notch / arrow key
local kLineSpacing = 4      -- extra pixels between wrapped lines

local function CreateBox(layer, color)
    local item = GetGUIManager():CreateGraphicItem()
    item:SetLayer(layer)
    item:SetColor(color)
    item:SetIsVisible(false)
    return item
end

local function CreateText(layer, font)
    local item = GetGUIManager():CreateTextItem()
    item:SetLayer(layer)
    item:SetFontName(font or Fonts.kAgencyFB_Small)
    item:SetTextAlignmentX(GUIItem.Align_Center)
    item:SetTextAlignmentY(GUIItem.Align_Center)
    item:SetIsVisible(false)
    return item
end

local function IsInside(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

function GUITEHGuide:Initialize()

    GUIScript.Initialize(self)

    self.open = false
    self.pageIndex = 1
    self.scroll = 0
    self.lines = {}
    self.textPool = {}
    self.rulePool = {}
    self.measure = {}

    self.background = CreateBox(kLayerPanel, kBorderColor)
    self.panel = CreateBox(kLayerPanel, kPanelColor)
    self.view = CreateBox(kLayerPanel, kViewColor)
    self.track = CreateBox(kLayerWidget, kTrackColor)
    self.thumb = CreateBox(kLayerWidget, kThumbColor)

    self.title = CreateText(kLayerText, kStyles.title.font)
    self.title:SetFontIsBold(true)
    self.title:SetColor(kTitleColor)

    self.closeBox = CreateBox(kLayerWidget, kButtonColor)
    self.closeText = CreateText(kLayerText, Fonts.kAgencyFB_Small)
    self.closeText:SetText("X")
    self.closeText:SetFontIsBold(true)

    self.hint = CreateText(kLayerText, Fonts.kAgencyFB_Small)
    self.hint:SetColor(kTEHGuideColors.dim)
    self.hint:SetTextAlignmentX(GUIItem.Align_Max)   -- bottom-right; the checkbox has the bottom-left

    self.checkBox = CreateBox(kLayerWidget, kButtonColor)
    self.checkMark = CreateText(kLayerText, Fonts.kAgencyFB_Small)
    self.checkMark:SetText("X")
    self.checkMark:SetFontIsBold(true)
    self.checkMark:SetColor(kTEHGuideColors.green)
    self.checkLabel = CreateText(kLayerText, Fonts.kAgencyFB_Small)
    self.checkLabel:SetText(kShowOnJoinLabel)
    self.checkLabel:SetTextAlignmentX(GUIItem.Align_Min)
    self.checkLabel:SetColor(kTEHGuideColors.text)

    self.buttons = {}
    for i, page in ipairs(kTEHGuide.pages) do
        local box = CreateBox(kLayerWidget, kButtonColor)
        local text = CreateText(kLayerText, Fonts.kAgencyFB_Small)
        text:SetText(page.button)
        text:SetFontIsBold(true)
        self.buttons[i] = { box = box, text = text }
    end

    self:Layout()

end

function GUITEHGuide:Uninitialize()

    self:SetOpen(false)

    local function Destroy(item) if item then GUI.DestroyItem(item) end end
    Destroy(self.background)
    Destroy(self.panel)
    Destroy(self.view)
    Destroy(self.track)
    Destroy(self.thumb)
    Destroy(self.title)
    Destroy(self.closeBox)
    Destroy(self.closeText)
    Destroy(self.hint)
    Destroy(self.checkBox)
    Destroy(self.checkMark)
    Destroy(self.checkLabel)
    for _, button in ipairs(self.buttons) do
        Destroy(button.box)
        Destroy(button.text)
    end
    for _, item in ipairs(self.textPool) do
        Destroy(item)
    end
    for _, item in ipairs(self.rulePool) do
        Destroy(item)
    end
    for _, item in pairs(self.measure) do
        Destroy(item)
    end

    GUIScript.Uninitialize(self)

end

function GUITEHGuide:GetIsOpen()
    return self.open
end

function GUITEHGuide:SetOpen(open)

    open = open == true
    if open == self.open then return end
    self.open = open

    -- The cursor stack is push/pop, so every open is matched by exactly one close.
    if open then
        MouseTracker_SetIsVisible(true, "ui/Cursor_MenuDefault.dds", true)
    else
        MouseTracker_SetIsVisible(false)
        self.dragging = nil
        self.pressed = nil
    end

    self:UpdateVisibility()
    if open then
        self:Layout()
    end

end

function GUITEHGuide:Toggle()
    self:SetOpen(not self.open)
end

function GUITEHGuide:SetPage(index)
    if not kTEHGuide.pages[index] then return end
    self.pageIndex = index
    self.scroll = 0
    self:Layout()
end

function GUITEHGuide:UpdateVisibility()
    local open = self.open
    self.background:SetIsVisible(open)
    self.panel:SetIsVisible(open)
    self.view:SetIsVisible(open)
    self.title:SetIsVisible(open)
    self.closeBox:SetIsVisible(open)
    self.closeText:SetIsVisible(open)
    self.hint:SetIsVisible(open)
    self.checkBox:SetIsVisible(open)
    self.checkLabel:SetIsVisible(open)
    self.checkMark:SetIsVisible(open and Client.GetOptionBoolean(kShowOnJoinOption, true))
    for _, button in ipairs(self.buttons) do
        button.box:SetIsVisible(open)
        button.text:SetIsVisible(open)
    end
    if not open then
        self.track:SetIsVisible(false)
        self.thumb:SetIsVisible(false)
        for _, item in ipairs(self.textPool) do
            item:SetIsVisible(false)
        end
        for _, item in ipairs(self.rulePool) do
            item:SetIsVisible(false)
        end
    end
end

-- A hidden text item per font, used only to measure text widths for word wrapping.
function GUITEHGuide:GetMeasure(font)
    local item = self.measure[font]
    if not item then
        item = GetGUIManager():CreateTextItem()
        item:SetFontName(font)
        item:SetIsVisible(false)
        self.measure[font] = item
    end
    return item
end

function GUITEHGuide:WrapText(text, style, scale, maxWidth)

    local measure = self:GetMeasure(style.font)
    measure:SetFontIsBold(style.bold)
    local function Width(str) return measure:GetTextWidth(str) * scale end

    local lines = {}
    -- "\n" in the content forces a line break.
    for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
        local current = ""
        for word in string.gmatch(paragraph, "%S+") do
            local candidate = current == "" and word or (current .. " " .. word)
            if current ~= "" and Width(candidate) > maxWidth then
                lines[#lines + 1] = current
                current = word
            else
                current = candidate
            end
        end
        lines[#lines + 1] = current
    end
    return lines

end

-- Positions every fixed element and rebuilds the wrapped lines of the current page.
function GUITEHGuide:Layout()

    local sw, sh = Client.GetScreenWidth(), Client.GetScreenHeight()
    local s = GUIScale(1)
    self.uiScale = s

    local w = math.min(sw - GUIScale(40), GUIScale(1240))
    local h = sh * 0.86
    local x = (sw - w) / 2
    local y = (sh - h) / 2
    self.rect = { x = x, y = y, w = w, h = h }

    local border = math.max(2, GUIScale(2))
    self.background:SetPosition(Vector(x - border, y - border, 0))
    self.background:SetSize(Vector(w + border * 2, h + border * 2, 0))
    self.panel:SetPosition(Vector(x, y, 0))
    self.panel:SetSize(Vector(w, h, 0))

    -- Title
    local titleScale = kStyles.title.scale * s
    self.title:SetText(kTEHGuide.title)
    self.title:SetScale(Vector(titleScale, titleScale, 0))
    local titleH = self.title:GetTextHeight(kTEHGuide.title) * titleScale
    self.title:SetPosition(Vector(x + w / 2, y + GUIScale(14) + titleH / 2, 0))

    -- Close button
    local closeSize = GUIScale(40)
    self.closeRect = { x = x + w - closeSize - GUIScale(10), y = y + GUIScale(10), w = closeSize, h = closeSize }
    self.closeBox:SetPosition(Vector(self.closeRect.x, self.closeRect.y, 0))
    self.closeBox:SetSize(Vector(closeSize, closeSize, 0))
    self.closeText:SetScale(Vector(1.2 * s, 1.2 * s, 0))
    self.closeText:SetPosition(Vector(self.closeRect.x + closeSize / 2, self.closeRect.y + closeSize / 2, 0))

    -- Page buttons, one row, evenly spaced
    local count = #self.buttons
    local margin = GUIScale(20)
    local gap = GUIScale(10)
    local buttonY = y + GUIScale(24) + titleH
    local buttonH = GUIScale(44)
    local buttonW = (w - margin * 2 - gap * (count - 1)) / count
    for i, button in ipairs(self.buttons) do
        local bx = x + margin + (i - 1) * (buttonW + gap)
        button.rect = { x = bx, y = buttonY, w = buttonW, h = buttonH }
        button.box:SetPosition(Vector(bx, buttonY, 0))
        button.box:SetSize(Vector(buttonW, buttonH, 0))
        -- Labels that are wider than the button are shrunk to fit inside it.
        local textScale = 1.1 * s
        local labelWidth = button.text:GetTextWidth(kTEHGuide.pages[i].button) * textScale
        if labelWidth > buttonW - GUIScale(12) then
            textScale = textScale * (buttonW - GUIScale(12)) / labelWidth
        end
        button.text:SetScale(Vector(textScale, textScale, 0))
        button.text:SetPosition(Vector(bx + buttonW / 2, buttonY + buttonH / 2, 0))
    end

    -- Hint along the bottom edge
    local hintScale = 0.9 * s
    local hintText = kTEHGuide.hint or "Mouse wheel or drag the bar to scroll.  Esc, X or the Guide key to close."
    self.hint:SetText(hintText)
    self.hint:SetScale(Vector(hintScale, hintScale, 0))
    local hintH = self.hint:GetTextHeight(hintText) * hintScale
    local rowY = y + h - GUIScale(10) - hintH / 2
    self.hint:SetPosition(Vector(x + w - margin, rowY, 0))

    -- "Show Guide Upon Join" checkbox, bottom-left on the same row. The label is part of the click area too.
    local checkSize = GUIScale(24)
    local labelScale = 0.95 * s
    self.checkBox:SetPosition(Vector(x + margin, rowY - checkSize / 2, 0))
    self.checkBox:SetSize(Vector(checkSize, checkSize, 0))
    self.checkMark:SetScale(Vector(s, s, 0))
    self.checkMark:SetPosition(Vector(x + margin + checkSize / 2, rowY, 0))
    self.checkLabel:SetScale(Vector(labelScale, labelScale, 0))
    self.checkLabel:SetPosition(Vector(x + margin + checkSize + GUIScale(10), rowY, 0))
    local labelW = self.checkLabel:GetTextWidth(kShowOnJoinLabel) * labelScale
    self.checkRect = { x = x + margin, y = rowY - checkSize / 2, w = checkSize + GUIScale(10) + labelW, h = checkSize }

    -- Scrollable text area
    local viewX = x + margin
    local viewY = buttonY + buttonH + GUIScale(14)
    local viewW = w - margin * 2
    local viewH = (y + h - GUIScale(20) - hintH) - viewY
    self.viewRect = { x = viewX, y = viewY, w = viewW, h = viewH }
    self.view:SetPosition(Vector(viewX, viewY, 0))
    self.view:SetSize(Vector(viewW, viewH, 0))

    local trackW = GUIScale(10)
    self.trackRect = { x = viewX + viewW - trackW - GUIScale(4), y = viewY + GUIScale(4), w = trackW, h = viewH - GUIScale(8) }

    -- Wrap the page into lines. Each line remembers its own style, colour and height.
    local textWidth = viewW - GUIScale(80)
    local lines = {}
    local cursorY = GUIScale(16)
    local page = kTEHGuide.pages[self.pageIndex]
    for _, block in ipairs(page.blocks) do
        local style = kStyles[block[1]] or kStyles.p
        if block[1] == "gap" then
            cursorY = cursorY + GUIScale(block[2] or 12)
        else
            local scale = style.scale * s
            local color = kTEHGuideColors[block[3] or style.color] or kWhite
            local measure = self:GetMeasure(style.font)
            local lineH = measure:GetTextHeight("Ay") * scale + GUIScale(kLineSpacing)
            cursorY = cursorY + GUIScale(style.gap)
            for _, text in ipairs(self:WrapText(block[2], style, scale, textWidth)) do
                lines[#lines + 1] = { text = text, style = style, scale = scale, color = color, y = cursorY, h = lineH }
                cursorY = cursorY + lineH
            end
            if block[1] == "h" then
                local ruleH = math.max(1, GUIScale(2))
                lines[#lines + 1] = { rule = true, color = color, y = cursorY + GUIScale(kRuleGap) / 2,
                                      h = ruleH, w = textWidth * kRuleWidth }
                cursorY = cursorY + GUIScale(kRuleGap) + ruleH
            end
        end
    end
    self.lines = lines
    self.contentHeight = cursorY + GUIScale(24)

    self:ClampScroll()
    self:Render()

end

function GUITEHGuide:GetMaxScroll()
    return math.max(0, (self.contentHeight or 0) - self.viewRect.h)
end

function GUITEHGuide:ClampScroll()
    self.scroll = Clamp(self.scroll or 0, 0, self:GetMaxScroll())
end

function GUITEHGuide:GetTextItem(index)
    local item = self.textPool[index]
    if not item then
        item = CreateText(kLayerText)
        self.textPool[index] = item
    end
    return item
end

-- Places the lines that fit fully inside the text area; everything else is hidden.
function GUITEHGuide:Render()

    if not self.open then return end

    local view = self.viewRect
    local centerX = view.x + view.w / 2
    local used = 0
    local rulesUsed = 0
    for _, line in ipairs(self.lines) do
        local top = view.y + line.y - self.scroll
        if line.rule then
            if top >= view.y and top + line.h <= view.y + view.h then
                rulesUsed = rulesUsed + 1
                local rule = self.rulePool[rulesUsed]
                if not rule then
                    rule = CreateBox(kLayerWidget, line.color)
                    self.rulePool[rulesUsed] = rule
                end
                rule:SetColor(Color(line.color.r, line.color.g, line.color.b, 0.6))
                rule:SetPosition(Vector(centerX - line.w / 2, top, 0))
                rule:SetSize(Vector(line.w, line.h, 0))
                rule:SetIsVisible(true)
            end
        elseif top >= view.y and top + line.h <= view.y + view.h and line.text ~= "" then
            used = used + 1
            local item = self:GetTextItem(used)
            item:SetFontName(line.style.font)
            item:SetFontIsBold(line.style.bold)
            item:SetScale(Vector(line.scale, line.scale, 0))
            item:SetColor(line.color)
            item:SetText(line.text)
            item:SetPosition(Vector(centerX, top + line.h / 2, 0))
            item:SetIsVisible(true)
        end
    end
    for i = used + 1, #self.textPool do
        self.textPool[i]:SetIsVisible(false)
    end
    for i = rulesUsed + 1, #self.rulePool do
        self.rulePool[i]:SetIsVisible(false)
    end

    -- Scroll bar, only when the page is longer than the text area.
    local maxScroll = self:GetMaxScroll()
    local track = self.trackRect
    if maxScroll > 0 then
        local thumbH = math.max(GUIScale(30), track.h * view.h / self.contentHeight)
        local thumbY = track.y + (track.h - thumbH) * (self.scroll / maxScroll)
        self.thumbRect = { x = track.x, y = thumbY, w = track.w, h = thumbH }
        self.track:SetPosition(Vector(track.x, track.y, 0))
        self.track:SetSize(Vector(track.w, track.h, 0))
        self.thumb:SetPosition(Vector(track.x, thumbY, 0))
        self.thumb:SetSize(Vector(track.w, thumbH, 0))
        self.track:SetIsVisible(true)
        self.thumb:SetIsVisible(true)
    else
        self.thumbRect = nil
        self.track:SetIsVisible(false)
        self.thumb:SetIsVisible(false)
    end

end

function GUITEHGuide:ScrollBy(amount)
    self.scroll = (self.scroll or 0) + amount
    self:ClampScroll()
    self:Render()
end

function GUITEHGuide:Update(deltaTime)

    if not self.open then return end

    local mx, my = Client.GetCursorPosScreen()

    -- Dragging the scroll bar thumb
    if self.dragging then
        local track = self.trackRect
        local thumbH = self.thumbRect and self.thumbRect.h or 0
        local range = track.h - thumbH
        if range > 0 then
            local fraction = Clamp((my - self.dragging - track.y) / range, 0, 1)
            local target = fraction * self:GetMaxScroll()
            if math.abs(target - self.scroll) >= 1 then
                self.scroll = target
                self:Render()
            end
        end
    end

    -- Button hover / active colours
    for i, button in ipairs(self.buttons) do
        local color = kButtonColor
        if i == self.pageIndex then
            color = kButtonActive
        elseif IsInside(mx, my, button.rect.x, button.rect.y, button.rect.w, button.rect.h) then
            color = kButtonHover
        end
        button.box:SetColor(color)
    end
    local c = self.closeRect
    self.closeBox:SetColor(IsInside(mx, my, c.x, c.y, c.w, c.h) and kButtonHover or kButtonColor)
    local r = self.checkRect
    self.checkBox:SetColor(r and IsInside(mx, my, r.x, r.y, r.w, r.h) and kButtonHover or kButtonColor)

end

-- What the cursor is over: "close", a page index, "thumb", "track" or nil.
function GUITEHGuide:HitTest(mx, my)
    local c = self.closeRect
    if IsInside(mx, my, c.x, c.y, c.w, c.h) then return "close" end
    local cb = self.checkRect
    if cb and IsInside(mx, my, cb.x, cb.y, cb.w, cb.h) then return "checkbox" end
    for i, button in ipairs(self.buttons) do
        local r = button.rect
        if IsInside(mx, my, r.x, r.y, r.w, r.h) then return i end
    end
    local t = self.thumbRect
    if t and IsInside(mx, my, t.x - GUIScale(6), t.y, t.w + GUIScale(12), t.h) then return "thumb" end
    local tr = self.trackRect
    if t and IsInside(mx, my, tr.x - GUIScale(6), tr.y, tr.w + GUIScale(12), tr.h) then return "track" end
    return nil
end

function GUITEHGuide:SendKeyEvent(key, down)

    if MainMenu_GetIsOpened and MainMenu_GetIsOpened() then
        return false
    end

    -- The Guide key toggles the window at any time (not while typing a chat message).
    if down and GetIsBinding and GetIsBinding(key, "TEHGuide")
            and not (ChatUI_EnteringChatMessage and ChatUI_EnteringChatMessage()) then
        self:Toggle()
        return true
    end

    if not self.open then
        return false
    end

    if key == InputKey.Escape then
        if down then
            self:SetOpen(false)
        end
        return true
    end

    local step = GUIScale(kScrollStep)
    if key == InputKey.MouseWheelUp then
        self:ScrollBy(-step)
        return true
    elseif key == InputKey.MouseWheelDown then
        self:ScrollBy(step)
        return true
    elseif down and key == InputKey.Up then
        self:ScrollBy(-step)
        return true
    elseif down and key == InputKey.Down then
        self:ScrollBy(step)
        return true
    elseif down and key == InputKey.PageUp then
        self:ScrollBy(-self.viewRect.h * 0.9)
        return true
    elseif down and key == InputKey.PageDown then
        self:ScrollBy(self.viewRect.h * 0.9)
        return true
    elseif down and key == InputKey.Home then
        self:ScrollBy(-self:GetMaxScroll())
        return true
    elseif down and key == InputKey.End then
        self:ScrollBy(self:GetMaxScroll())
        return true
    end

    if key == InputKey.MouseButton0 then
        local mx, my = Client.GetCursorPosScreen()
        if down then
            local hit = self:HitTest(mx, my)
            self.pressed = hit
            if hit == "thumb" then
                self.dragging = my - self.thumbRect.y
            elseif hit == "track" then
                -- Clicking the bar jumps the thumb's centre to the cursor, then keeps dragging.
                self.dragging = self.thumbRect.h / 2
            end
        else
            -- A click fires on release, and only on the same thing it was pressed on.
            local hit = self:HitTest(mx, my)
            if hit ~= nil and hit == self.pressed then
                if hit == "close" then
                    self:SetOpen(false)
                elseif hit == "checkbox" then
                    local show = not Client.GetOptionBoolean(kShowOnJoinOption, true)
                    Client.SetOptionBoolean(kShowOnJoinOption, show)
                    self.checkMark:SetIsVisible(self.open and show)
                    -- The Options -> Mods checkbox shows its own copy of the value (read when the menu was built):
                    -- set it too, so the two agree straight away. Its name is the one in TEHGuide_ModsMenuData.lua.
                    pcall(function()
                        local optionsMenu = GetOptionsMenu and GetOptionsMenu()
                        local widget = optionsMenu and optionsMenu:GetOptionWidget(kShowOnJoinWidget)
                        if widget and widget.SetValue then widget:SetValue(show) end
                    end)
                elseif type(hit) == "number" then
                    self:SetPage(hit)
                end
            end
            self.pressed = nil
            self.dragging = nil
        end
        -- Clicks never reach the game while the window is open, so they cannot fire a weapon.
        return true
    end

    if key == InputKey.MouseButton1 or key == InputKey.MouseButton2 then
        return true
    end

    return false

end

function GUITEHGuide:OnResolutionChanged(oldX, oldY, newX, newY)
    self:Layout()
end
