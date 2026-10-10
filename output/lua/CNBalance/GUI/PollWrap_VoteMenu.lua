--[[
    POLL LINE WRAPPING - part 2 of 2 (post hook on lua/GUIVoteMenu.lua; part 1 is PollWrap_Voting.lua).

    Vanilla lays the vote box out for a single title line. For a wrapped poll, straight after vanilla's own layout, this
    makes the title area one line taller for every extra line, grows the box to match, keeps the F1 (Yes) and F2 (No) rows
    underneath the text, and sizes the width to the longest wrapped line. Other votes are left exactly as vanilla draws them.

    Client only, wrapped in pcall (a layout problem can never break the vote box), installed once across mods.
]]

if not Client or gPollWrapVoteMenuInstalled or not GUIVoteMenu then return end
gPollWrapVoteMenuInstalled = true

local function RelayoutPoll(self)

    local text = self.lastCurrentVoteQuery
    if not text or not gPollWrapTexts or not gPollWrapTexts[text] then return end
    if not (self.background and self.titleText and self.titleBackground and self.yesBackground and self.noBackground) then return end

    local lines = {}
    for line in string.gmatch(text, "[^\n]+") do
        table.insert(lines, line)
    end
    if #lines <= 1 then return end

    local title = self.titleText
    local scale = title:GetScale()

    local widest = 0
    for _, line in ipairs(lines) do
        widest = math.max(widest, title:GetTextWidth(line) * scale.x)
    end

    --[[
        The height the wrapped title really needs. The font's line spacing is taller than one line's glyphs
        ("Ag"), so counting lines x glyph height under-measured and the last lines ran into the Yes row. The line
        advance is measured from two lines minus one, and the block gets a margin above and below. The title text
        is centred in the title area, so growing the area keeps every line inside it.
    ]]
    local oneLine = title:GetTextHeight("Ag") * scale.y
    local lineAdvance = math.max(oneLine, title:GetTextHeight("Ag\nAg") * scale.y - oneLine)
    local blockHeight = oneLine + (#lines - 1) * lineAdvance + GUIScale(8)

    local titleHeight = self.titleBackground:GetSize().y
    local extra = math.max(0, blockHeight - titleHeight)

    local timeWidth = self.timeText and self.timeText:GetTextWidth(" ##") * self.timeText:GetScale().x or 0
    local width = math.max(Client.GetScreenWidth() * 0.15, widest + timeWidth + GUIScale(20))

    local size = self.background:GetSize()
    local newSize = Vector(width, size.y + extra, 0)
    self.background:SetSize(newSize)
    self.background:SetPosition(Vector(GUIScale(2), -newSize.y, 0))

    local titleSize = self.titleBackground:GetSize()
    self.titleBackground:SetSize(Vector(width - GUIScale(4), titleSize.y + extra, 0))

    for _, row in ipairs({ self.yesBackground, self.noBackground }) do
        local rowSize = row:GetSize()
        row:SetSize(Vector(width - GUIScale(4), rowSize.y, 0))
        local rowPos = row:GetPosition()
        row:SetPosition(Vector(rowPos.x, rowPos.y + extra, 0))
    end

end

local oldUpdate = GUIVoteMenu.Update
function GUIVoteMenu:Update(deltaTime)

    oldUpdate(self, deltaTime)

    -- Vanilla lays the box out once per new vote; do the poll layout once, straight after it.
    if self.background and self.background:GetIsVisible() and self.pollWrapLaidOut ~= self.lastCurrentVoteQuery then
        self.pollWrapLaidOut = self.lastCurrentVoteQuery
        pcall(RelayoutPoll, self)
    end

end

local oldOnResolutionChanged = GUIVoteMenu.OnResolutionChanged
function GUIVoteMenu:OnResolutionChanged(oldX, oldY, newX, newY)

    oldOnResolutionChanged(self, oldX, oldY, newX, newY)
    pcall(RelayoutPoll, self)

end
