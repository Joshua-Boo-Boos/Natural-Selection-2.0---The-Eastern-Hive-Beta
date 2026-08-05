Script.Load("lua/GUIAnimatedScript.lua")

-- Combat Builder build menu.
--
-- Reworked for Combat Engineers, which raised the buildable list from two structures to twelve:
--
--   * PAGED, five per page. Five is not arbitrary: selection hotkeys are Move.Weapon1..Weapon5 and
--     there is no sixth weapon-slot command to add, so a page of five means EVERY visible entry has
--     a hotkey. Mouse wheel flips pages; clicking a button works on any page.
--   * ICONS come from the COMMANDER ATLAS (ui/buildmenu.dds via GetTextureCoordinatesForIcon). The
--     old ui/Combat/BuildMenu/marine_build_menu.dds sheet has only 2 columns x 4 rows with a
--     hardcoded techId->row table, and its `math.min(row, 4)` silently drew every structure past the
--     fourth with the PhaseGate icon. The Marine Sentry and Supply Depot keep their own bespoke
--     artwork from that sheet, scaled down to match.
--   * A single background PANEL sits behind the page so it reads as one window.
--   * VISIBILITY is filtered per round: Combat Engineers structures only appear in a CE round.
--     The underlying CombatBuilder.kSupportedStructures list is NEVER shortened, because its index
--     is the structureIndex sent over the network.

local kMouseOverSound = "sound/NS2.fev/common/hovar"
local kSelectSound = "sound/NS2.fev/common/open"
local kCloseSound = "sound/NS2.fev/common/tooltip"
local kFontName = Fonts.kAgencyFB_Small
Client.PrecacheLocalSound(kMouseOverSound)
Client.PrecacheLocalSound(kSelectSound)
Client.PrecacheLocalSound(kCloseSound)

function MarineBuild_OnClose()
    Shared.PlaySound(nil, kCloseSound)
end

function MarineBuild_OnSelect()
    Shared.PlaySound(nil, kSelectSound)
end

function MarineBuild_OnMouseOver()
    --Shared.PlaySound(nil, kMouseOverSound)
end

function MarineBuild_Close()

    local player = Client.GetLocalPlayer()
    local dropStructureAbility = player and player:GetWeapon(CombatBuilder.kMapName)

    if dropStructureAbility then
        dropStructureAbility:DestroyBuildMenu()
    end

end

function MarineBuild_SendSelect(index)

    local player = Client.GetLocalPlayer()

    if player then

        local dropStructureAbility = player:GetWeapon(CombatBuilder.kMapName)
        if dropStructureAbility then
            dropStructureAbility:SetActiveStructure(index)

            -- CombatBuilder:OnUpdateRender recreates self.buildMenu on the VERY NEXT render frame
            -- whenever it is nil (CreateBuildMenu has no other guard), and MarineBuild_Close (called
            -- right after this by whichever caller made the selection) destroys and nils it. Without
            -- clearing menuActive here too, that freshly recreated instance inherited the OLD true
            -- value and was made visible again immediately - the chooser reopening itself right after
            -- a structure was picked, which is what "the buy menu stays open" actually was.
            dropStructureAbility.menuActive = false
        end

    end

end

function MarineBuild_GetIsAbilityAvailable(index)

    local ability = CombatBuilder.kSupportedStructures[index]
    return ability ~= nil and ability:IsAllowed(Client.GetLocalPlayer())

end

-- Whether this entry belongs in the menu AT ALL this round. Sentry and Supply Depot are always
-- offered; the ten Combat Engineers structures only in a CE round. This is a per-round property, so
-- it is safe to evaluate when the page is laid out - unlike IsAllowed, which also folds in tech
-- prerequisites and the Arms Lab / Infantry Portal caps and must keep GREYING its button rather
-- than removing it.
function MarineBuild_GetIsAbilityVisible(index)

    local ability = CombatBuilder.kSupportedStructures[index]
    if not ability then return false end

    local techId = ability:GetDropStructureId()

    if techId == kTechId.MarineSentry or techId == kTechId.WeaponCache then
        return true
    end

    return GetCombatEngineersActive(Client.GetLocalPlayer())

end

function MarineBuild_AllowConsumeDrop(techId)
    return LookupTechData(techId, kTechDataAllowConsumeDrop, false)
end

function MarineBuild_GetStructureCost(techId)

    local player = Client.GetLocalPlayer()
    if not player then return 0 end

    return CombatBuilder.GetStructureCost(techId, player:GetTeamNumber())

end

-- Affordability mirrors the SERVER's placement rule exactly: a CE structure is FREE to place, so
-- its button is never greyed out for lack of p-res - only the legacy Sentry/Supply Depot prices
-- (paid up front, as always) are checked here.
function MarineBuild_GetCanAffordAbility(techId)

    local player = Client.GetLocalPlayer()
    if not player then return false end

    if GetCombatEngineersStructureHasDynamicCost(techId) then
        return true
    end

    return Shared.GetCheatsEnabled() or player:GetResources() >= MarineBuild_GetStructureCost(techId)

end

-- Count and cap shown under a button, e.g. "3/6" for Arms Labs or "5/12" for Infantry Portals.
-- Returns nil when the structure has no cap worth showing.
function MarineBuild_GetStructureCount(techId)

    local player = Client.GetLocalPlayer()
    if not player then return nil, nil end

    -- Team-wide caps (Arms Lab, Infantry Portal) come from the networked MarineTeamInfo counters, so
    -- the client shows exactly the number the server enforces against.
    local count, max = GetCombatEngineersStructureCount(techId, player:GetTeamNumber())
    if count then
        return count, max
    end

    -- Per-player caps (Sentry, Supply Depot) live on the Combat Builder itself.
    local weapon = player:GetActiveWeapon()
    if weapon and weapon:isa("CombatBuilder") then
        local built = weapon:GetNumStructuresBuilt(techId)
        if built and built >= 0 then
            return built, weapon:GetNumStructuresCanDrop(techId, player)
        end
    end

    return nil, nil

end

class 'GUIMarineBuildMenu' (GUIAnimatedScript)

GUIMarineBuildMenu.kBaseYResolution = 1200

-- FIVE structures per page - one per weapon-slot hotkey. Paging is mouse-wheel only (no dedicated
-- on-screen page button/hotkey - the wheel already pages cleanly and a whole slot given over to a
-- page-flip button was one less structure visible per page for no real benefit).
GUIMarineBuildMenu.kPageSize = 5

GUIMarineBuildMenu.kButtonWidth = 170
-- Must cover the FULL stacked content of a button: icon (96, starting 14px down) + label (+16
-- below the icon) + the weapon-key hint number (+34 below the icon, plus its own ~32px height).
-- The previous 190 undershot that real extent, which is what pushed the page indicator and key
-- icons at the bottom of the panel past its edge - the panel's height was computed FROM this
-- constant, so a plain content underestimate directly produced the reported "text at/above the
-- edge of the background image".
GUIMarineBuildMenu.kButtonHeight = 230
GUIMarineBuildMenu.kIconSize = 96

GUIMarineBuildMenu.kIconTexture = "ui/buildmenu.dds"

-- The Marine Sentry and Supply Depot keep their ORIGINAL bespoke artwork from the Combat build
-- sheet - they have no equivalent on the commander atlas, and the existing images are better. Its
-- cells are 128px against the atlas's 80px, but both are drawn at kIconSize, so they simply scale
-- down to match every other button.
GUIMarineBuildMenu.kCombatIconTexture = "ui/Combat/BuildMenu/marine_build_menu.dds"
GUIMarineBuildMenu.kCombatIconPixelSize = 128

GUIMarineBuildMenu.kPanelPadding = 34
GUIMarineBuildMenu.kPanelTexture = "ui/buymenu_marine/prototypelab_background.dds"

-- The panel is laid out as three stacked bands: title / button grid / footer. Both the title and
-- the FOOTER are explicitly sized here and added to the panel's height, so the text drawn in them
-- is always inside the background image. (The footer band is what the page indicator lives in -
-- before it existed, that text was positioned into space the panel was never sized to contain.)
GUIMarineBuildMenu.kTitleBandHeight = 60
GUIMarineBuildMenu.kFooterBandHeight = 46
-- Measured DOWNWARD from the panel's TOP edge (the title item is anchored GUIItem.Top), so this
-- MUST be positive to sit inside the panel. It was negative, which is precisely why the title
-- rendered above the background image instead of within it.
GUIMarineBuildMenu.kTitleTextInset = 26
GUIMarineBuildMenu.kFooterTextHalfHeight = 12     -- half a line of 24pt text, to centre it in the band

-- A background tile behind EVERY icon (commander atlas ones included), not just the Sentry/Supply
-- Depot artwork which already bakes a background into its own sprite. Reuses the same button-back
-- texture the commander HUD grid uses, so a plain atlas icon reads as a proper button instead of a
-- naked picture floating on the panel.
GUIMarineBuildMenu.kButtonBackgroundTexture = "ui/marine_buildmenu_buttonbg.dds"
GUIMarineBuildMenu.kButtonBackgroundSize = 128
-- Same blue family as the Sentry/Supply Depot sprite's own baked-in background.
GUIMarineBuildMenu.kIconBackgroundColor = Color(0.13, 0.40, 0.72, 0.65)

GUIMarineBuildMenu.kAvailableColor = kMarineTeamColorFloat
GUIMarineBuildMenu.kTooExpensiveColor = Color(1, 0.3, 0.3, 1)
GUIMarineBuildMenu.kUnavailableColor = Color(0.4, 0.4, 0.4, 0.7)
GUIMarineBuildMenu.kHoverColor = Color(1, 1, 1, 1)
GUIMarineBuildMenu.kPanelColor = Color(0.55, 0.60, 0.65, 0.92)
GUIMarineBuildMenu.kPageTextColor = Color(0.72, 0.88, 0.95, 1)
-- The window title uses the standard marine team blue (the same colour the structure name labels
-- and the rest of the marine HUD use), rather than the paler cyan the page indicator uses.
GUIMarineBuildMenu.kTitleTextColor = kMarineTeamColorFloat

GUIMarineBuildMenu.kPersonalResourceIcon = { Width = 32, Height = 32, Coords = { X1 = 144, Y1 = 363, X2 = 192, Y2 = 411} }
GUIMarineBuildMenu.kResourceTexture = "ui/alien_commander_textures.dds"
GUIMarineBuildMenu.kIconTextXOffset = 12

local kCenteredStructureCountPos = Vector(0, -22, 0)

-- Row in kCombatIconTexture, keyed by tech id. Column 1 is the "available" artwork; state is
-- conveyed by the colour tint applied in UpdateButton, so the sheet's second (greyed) column is not
-- needed. Built lazily because kTechId entries are appended at load time.
local gCombatIconRow = nil

local function GetCombatIconRow(techId)

    if not gCombatIconRow then
        gCombatIconRow = {}
        gCombatIconRow[kTechId.MarineSentry] = 1
        gCombatIconRow[kTechId.WeaponCache]  = 2
    end

    return gCombatIconRow[techId]

end

-- Master indices of every entry visible this round, in list order.
local function GetVisibleIndices()

    local visible = {}

    for index = 1, #CombatBuilder.kSupportedStructures do
        if MarineBuild_GetIsAbilityVisible(index) then
            table.insert(visible, index)
        end
    end

    return visible

end

function GUIMarineBuildMenu:Initialize()

    GUIAnimatedScript.Initialize(self)

    self.scale = Client.GetScreenHeight() / GUIMarineBuildMenu.kBaseYResolution

    self.background = self:CreateAnimatedGraphicItem()
    self.background:SetAnchor(GUIItem.Middle, GUIItem.Center)
    self.background:SetColor(Color(0,0,0,0))

    -- One panel behind the page, so the menu reads as a single window rather than loose icons.
    self.panel = self:CreateAnimatedGraphicItem()
    self.panel:SetAnchor(GUIItem.Left, GUIItem.Top)
    self.panel:SetTexture(GUIMarineBuildMenu.kPanelTexture)
    self.panel:SetColor(GUIMarineBuildMenu.kPanelColor)
    self.background:AddChild(self.panel)

    self.titleText = self:CreateAnimatedTextItem()
    self.titleText:SetAnchor(GUIItem.Middle, GUIItem.Top)
    self.titleText:SetTextAlignmentX(GUIItem.Align_Center)
    self.titleText:SetTextAlignmentY(GUIItem.Align_Min)
    self.titleText:SetFontName(kFontName)
    self.titleText:SetFontSize(26)
    self.titleText:SetFontIsBold(true)
    self.titleText:SetColor(GUIMarineBuildMenu.kTitleTextColor)
    self.titleText:SetText("BRAZIER INDUSTRIES COMBAT ENGINEER STRUCTURE PLACEMENT")
    self.panel:AddChild(self.titleText)

    self.pageText = self:CreateAnimatedTextItem()
    self.pageText:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    self.pageText:SetTextAlignmentX(GUIItem.Align_Center)
    self.pageText:SetTextAlignmentY(GUIItem.Align_Min)
    self.pageText:SetFontName(kFontName)
    self.pageText:SetFontSize(24)
    self.pageText:SetFontIsBold(true)
    self.pageText:SetColor(GUIMarineBuildMenu.kPageTextColor)
    self.panel:AddChild(self.pageText)

    self.buttons     = {}
    self.page        = 1

    self:Reset()

end

function GUIMarineBuildMenu:Uninitialize()

    GUIAnimatedScript.Uninitialize(self)

end

function GUIMarineBuildMenu:GetIsVisible()
    return self.background:GetIsVisible()
end

function GUIMarineBuildMenu:SetIsVisible(isVisible)
    self.background:SetIsVisible(isVisible == true)
end

function GUIMarineBuildMenu:_HandleMouseOver(onItem)

    if onItem ~= self.lastActiveItem then
        MarineBuild_OnMouseOver()
        self.lastActiveItem = onItem
    end

end

function GUIMarineBuildMenu:GetPageCount()
    local visible = GetVisibleIndices()
    return math.max(1, math.ceil(#visible / GUIMarineBuildMenu.kPageSize)), #visible
end

function GUIMarineBuildMenu:SetPage(page)

    local pages = self:GetPageCount()

    -- Wrap, so the wheel cycles endlessly in both directions.
    if page < 1 then page = pages end
    if page > pages then page = 1 end

    if page ~= self.page then
        self.page = page
        self:Reset()
        MarineBuild_OnMouseOver()
    end

end

local function UpdateButton(button, hovered)

    local techId = button.techId
    local color  = GUIMarineBuildMenu.kAvailableColor

    if not MarineBuild_GetCanAffordAbility(techId) then
        color = GUIMarineBuildMenu.kTooExpensiveColor
    end

    -- Availability (tech prerequisites plus the Arms Lab and Infantry Portal caps) outranks
    -- affordability: an unavailable button reads as dead, not merely unaffordable.
    if not MarineBuild_GetIsAbilityAvailable(button.index) then
        color = GUIMarineBuildMenu.kUnavailableColor
    elseif hovered then
        color = GUIMarineBuildMenu.kHoverColor
    end

    button.graphicItem:SetColor(color)
    button.description:SetColor(color)
    button.costIcon:SetColor(color)
    button.costText:SetColor(color)

    local count, max = MarineBuild_GetStructureCount(techId)

    if count then

        button.structuresLeft:SetIsVisible(true)

        local amountString = ToString(count)
        if max and max > 0 then
            amountString = amountString .. "/" .. ToString(max)
        end

        button.structuresLeft:SetText(amountString)
        button.structuresLeft:SetColor((max and count >= max) and GUIMarineBuildMenu.kTooExpensiveColor or color)

    else
        button.structuresLeft:SetIsVisible(false)
    end

    local cost = MarineBuild_GetStructureCost(techId)
    if cost == 0 then
        button.costIcon:SetIsVisible(false)
    else
        button.costIcon:SetIsVisible(true)
        button.costText:SetText(ToString(cost))
    end

end

function GUIMarineBuildMenu:Update(deltaTime)

    GUIAnimatedScript.Update(self, deltaTime)

    -- Rebuild when the visible set changes - Combat Engineers completing mid-round, or simply the
    -- tech tree not having arrived when the menu was first created. Without this the menu would sit
    -- on a stale two-entry page until the player happened to switch weapons.
    local signature = table.concat(GetVisibleIndices(), ",")
    if signature ~= self.visibleSignature then
        self:Reset()
    end

    for _, button in ipairs(self.buttons) do

        local hovered = self:_GetIsMouseOver(button.graphicItem)

        UpdateButton(button, hovered)

        if hovered then
            self:_HandleMouseOver(button.graphicItem)
        end

    end

end

function GUIMarineBuildMenu:Reset()

    -- Tear the previous page down rather than leaking it on every rebuild.
    --
    -- Animated items MUST go through GUIAnimatedItem:Destroy(), which de-registers them from the
    -- script's guiItems list. GUI.DestroyItem would kill the underlying item but leave the wrapper
    -- registered, and GUIAnimatedScript:Uninitialize would then destroy it a second time. Key icons
    -- come from GUICreateButtonIcon (a plain GUIManager item) and are freed the other way.
    if self.pageAnimatedItems then
        for _, item in ipairs(self.pageAnimatedItems) do
            item:Destroy()
        end
    end

    if self.pageRawItems then
        for _, item in ipairs(self.pageRawItems) do
            GUI.DestroyItem(item)
        end
    end

    self.pageAnimatedItems = {}
    self.pageRawItems      = {}
    self.buttons           = {}

    local visible = GetVisibleIndices()
    self.visibleSignature = table.concat(visible, ",")

    local pageSize = GUIMarineBuildMenu.kPageSize
    local pages    = math.max(1, math.ceil(#visible / pageSize))

    -- Structures disappearing (a round ending, say) can leave us past the last page.
    self.page = math.max(1, math.min(self.page or 1, pages))

    self.background:SetUniformScale(self.scale)
    self.panel:SetUniformScale(self.scale)

    local firstSlot = (self.page - 1) * pageSize
    local shown     = 0

    for offset = 1, pageSize do

        local index = visible[firstSlot + offset]

        if index then

            local ability = CombatBuilder.kSupportedStructures[index]

            table.insert(self.buttons, self:CreateButton(ability:GetDropStructureId(), index,
                                                         self.scale, self.background,
                                                         "Weapon" .. ToString(offset),
                                                         offset - 1))
            shown = shown + 1
        end

    end

    -- Sized to a FULL page (kPageSize), not merely how many buttons this particular page happens to
    -- have - otherwise a short last page (e.g. the CE menu's page 3, which only holds two structures)
    -- rendered a visibly narrower panel than the earlier, full pages instead of just leaving the
    -- unused button slots as empty space on the right.
    local columns = math.max(1, GUIMarineBuildMenu.kPageSize)
    local gridW   = columns * GUIMarineBuildMenu.kButtonWidth
    local gridH   = GUIMarineBuildMenu.kButtonHeight

    -- A short page's buttons were left flush against the left edge of the now-full-width panel
    -- (each still positioned as `column * kButtonWidth` from x=0) - re-centre them as a group within
    -- the full grid width instead.
    if shown > 0 and shown < columns then
        local centerOffsetX = (gridW - shown * GUIMarineBuildMenu.kButtonWidth) * 0.5
        for _, button in ipairs(self.buttons) do
            local pos = button.frame:GetPosition()
            button.frame:SetPosition(Vector(pos.x + centerOffsetX, pos.y, pos.z))
        end
    end

    local padding    = GUIMarineBuildMenu.kPanelPadding
    local titleSpace = GUIMarineBuildMenu.kTitleBandHeight
    local footerSpace = GUIMarineBuildMenu.kFooterBandHeight

    -- The panel gets THREE bands, not two: a title band above the grid, the grid itself, and a
    -- dedicated FOOTER band below it for the page indicator. The footer band is the fix - the page
    -- text was previously positioned a fraction of `padding` up from the panel's bottom edge, into
    -- space the panel had never been sized to contain, so it rendered on or past the edge no matter
    -- how much kButtonHeight grew (growing that only moved the grid AND the bottom edge down
    -- together, never opening a gap between them).
    self.panel:SetSize(Vector(gridW + padding * 2,
                              titleSpace + gridH + footerSpace + padding * 2, 0))
    self.panel:SetPosition(Vector(-padding, -padding - titleSpace, 0))

    self.titleText:SetPosition(Vector(0, GUIMarineBuildMenu.kTitleTextInset, 0))

    -- Sits INSIDE the footer band, measured up from the panel's bottom edge: the band is
    -- footerSpace + padding tall, and the text is placed a little above the middle of it so its
    -- full glyph height clears the bottom edge comfortably.
    self.pageText:SetPosition(Vector(0, -(footerSpace + padding) * 0.5 - GUIMarineBuildMenu.kFooterTextHalfHeight, 0))
    self.pageText:SetText(pages > 1 and string.format("PAGE %d / %d   [scroll to change page]", self.page, pages) or "")
    self.pageText:SetIsVisible(pages > 1)

    -- Centre the page on screen.
    self.background:SetPosition(Vector(gridW * -0.5, gridH * -0.5, 0))

end

function GUIMarineBuildMenu:OnResolutionChanged(oldX, oldY, newX, newY)

    self.scale = newY / GUIMarineBuildMenu.kBaseYResolution
    self:Reset()

end

function GUIMarineBuildMenu:CreateButton(techId, index, scale, frame, keybind, column)

    local button =
    {
        frame = self:CreateAnimatedGraphicItem(),
        iconBackground = self:CreateAnimatedGraphicItem(),
        graphicItem = self:CreateAnimatedGraphicItem(),
        description = self:CreateAnimatedTextItem(),
        keyIcon = GUICreateButtonIcon(keybind, false),
        keybind = keybind,
        techId = techId,
        index = index,
        structuresLeft = self:CreateAnimatedTextItem(),
        costIcon = self:CreateAnimatedGraphicItem(),
        costText = self:CreateAnimatedTextItem(),
    }

    table.insert(self.pageAnimatedItems, button.frame)
    table.insert(self.pageAnimatedItems, button.iconBackground)
    table.insert(self.pageAnimatedItems, button.graphicItem)
    table.insert(self.pageAnimatedItems, button.description)
    table.insert(self.pageAnimatedItems, button.structuresLeft)
    table.insert(self.pageAnimatedItems, button.costIcon)
    table.insert(self.pageAnimatedItems, button.costText)
    if button.keyIcon then
        table.insert(self.pageRawItems, button.keyIcon)
    end

    button.frame:SetUniformScale(scale)
    button.frame:SetSize(Vector(GUIMarineBuildMenu.kButtonWidth, GUIMarineBuildMenu.kButtonHeight, 0))
    button.frame:SetColor(Color(1,1,1,0))
    button.frame:SetPosition(Vector(column * GUIMarineBuildMenu.kButtonWidth, 0, 0))
    frame:AddChild(button.frame)

    -- A background tile behind the icon, TINTED to the same blue the Sentry/Supply Depot artwork
    -- already bakes into its own sprite - there is no separate "just the background" layer to lift
    -- out of that art (the sheet's cells are icon and background baked together as one image), so
    -- this reproduces the LOOK (a blue box behind the picture) with a plain texture + colour tint
    -- rather than the exact pixels. A plain atlas icon (Armory, etc.) now reads as a proper coloured
    -- button instead of a bare picture floating on the panel; on Sentry/Supply Depot it sits behind
    -- their own fully-opaque sprite at no visual cost.
    button.iconBackground:SetUniformScale(scale)
    button.iconBackground:SetSize(Vector(GUIMarineBuildMenu.kButtonBackgroundSize, GUIMarineBuildMenu.kButtonBackgroundSize, 0))
    button.iconBackground:SetAnchor(GUIItem.Middle, GUIItem.Top)
    button.iconBackground:SetPosition(Vector(-GUIMarineBuildMenu.kButtonBackgroundSize * 0.5, 0, 0))
    button.iconBackground:SetTexture(GUIMarineBuildMenu.kButtonBackgroundTexture)
    button.iconBackground:SetColor(GUIMarineBuildMenu.kIconBackgroundColor)
    button.frame:AddChild(button.iconBackground)

    button.graphicItem:SetUniformScale(scale)
    button.graphicItem:SetSize(Vector(GUIMarineBuildMenu.kIconSize, GUIMarineBuildMenu.kIconSize, 0))
    button.graphicItem:SetAnchor(GUIItem.Middle, GUIItem.Top)
    button.graphicItem:SetPosition(Vector(-GUIMarineBuildMenu.kIconSize * 0.5, 14, 0))

    local combatIconRow = GetCombatIconRow(techId)

    if combatIconRow then
        button.graphicItem:SetTexture(GUIMarineBuildMenu.kCombatIconTexture)
        button.graphicItem:SetTexturePixelCoordinates(GUIGetSprite(1, combatIconRow,
            GUIMarineBuildMenu.kCombatIconPixelSize, GUIMarineBuildMenu.kCombatIconPixelSize))
    else
        button.graphicItem:SetTexture(GUIMarineBuildMenu.kIconTexture)
        button.graphicItem:SetTexturePixelCoordinates(GUIUnpackCoords(GetTextureCoordinatesForIcon(techId)))
    end

    button.frame:AddChild(button.graphicItem)

    button.description:SetUniformScale(scale)
    button.description:SetText(Locale.ResolveString(LookupTechData(techId, kTechDataDisplayName, "")))
    button.description:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    button.description:SetTextAlignmentX(GUIItem.Align_Center)
    button.description:SetTextAlignmentY(GUIItem.Align_Center)
    button.description:SetFontSize(20)
    button.description:SetFontName(kFontName)
    button.description:SetPosition(Vector(0, 16, 0))
    button.description:SetFontIsBold(true)
    button.graphicItem:AddChild(button.description)

    if button.keyIcon then
        button.keyIcon:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
        button.keyIcon:SetFontName(kFontName)
        button.keyIcon:SetPosition(Vector(-button.keyIcon:GetSize().x/2, 0.5*button.keyIcon:GetSize().y + 34, 0))
        button.graphicItem:AddChild(button.keyIcon)
    end

    button.structuresLeft:SetAnchor(GUIItem.Middle, GUIItem.Bottom)
    button.structuresLeft:SetTextAlignmentX(GUIItem.Align_Center)
    button.structuresLeft:SetTextAlignmentY(GUIItem.Align_Center)
    button.structuresLeft:SetFontSize(24)
    button.structuresLeft:SetFontName(kFontName)
    button.structuresLeft:SetPosition(kCenteredStructureCountPos)
    button.structuresLeft:SetFontIsBold(true)
    button.structuresLeft:SetColor(GUIMarineBuildMenu.kAvailableColor)
    button.graphicItem:AddChild(button.structuresLeft)

    button.costIcon:SetUniformScale(scale)
    button.costIcon:SetSize(Vector(GUIMarineBuildMenu.kPersonalResourceIcon.Width, GUIMarineBuildMenu.kPersonalResourceIcon.Height, 0))
    button.costIcon:SetAnchor(GUIItem.Middle, GUIItem.Top)
    button.costIcon:SetTexture(GUIMarineBuildMenu.kResourceTexture)
    button.costIcon:SetPosition(Vector(0, GUIMarineBuildMenu.kPersonalResourceIcon.Height * .5 + 4, 0))
    GUISetTextureCoordinatesTable(button.costIcon, GUIMarineBuildMenu.kPersonalResourceIcon.Coords)
    button.graphicItem:AddChild(button.costIcon)

    button.costText:SetUniformScale(scale)
    button.costText:SetAnchor(GUIItem.Middle, GUIItem.Middle)
    button.costText:SetTextAlignmentX(GUIItem.Align_Min)
    button.costText:SetTextAlignmentY(GUIItem.Align_Center)
    button.costText:SetPosition(Vector(GUIMarineBuildMenu.kIconTextXOffset, 3, 0))
    button.costText:SetFontIsBold(true)
    button.costText:SetFontSize(24)
    button.costText:SetFontName(kFontName)
    button.costText:SetColor(GUIMarineBuildMenu.kAvailableColor)
    button.costIcon:AddChild(button.costText)

    return button

end

-- Select the entry under the cursor, if it is available and affordable. Returns true when the click
-- was consumed (including on a dead button, so it does not leak to the world behind the menu).
function GUIMarineBuildMenu:SelectHoveredButton()

    for _, button in ipairs(self.buttons) do

        if self:_GetIsMouseOver(button.graphicItem) then

            if MarineBuild_GetIsAbilityAvailable(button.index)
               and MarineBuild_GetCanAffordAbility(button.techId) then

                MarineBuild_SendSelect(button.index)
                MarineBuild_OnSelect()
                return true, true
            end

            return true, false
        end

    end

    return false, false

end

function GUIMarineBuildMenu:OverrideInput(input)

    -- Mouse wheel pages through the list instead of closing the menu. With twelve structures and
    -- only five hotkeys, flipping pages is what a player actually wants the wheel for here.
    if HasMoveCommand( input.commands, Move.SelectNextWeapon ) then
        self:SetPage(self.page + 1)
        input.commands = RemoveMoveCommand( input.commands, Move.SelectNextWeapon )
        return input, false
    end

    if HasMoveCommand( input.commands, Move.SelectPrevWeapon ) then
        self:SetPage(self.page - 1)
        input.commands = RemoveMoveCommand( input.commands, Move.SelectPrevWeapon )
        return input, false
    end

    local weaponSwitchCommands = { Move.Weapon1, Move.Weapon2, Move.Weapon3, Move.Weapon4, Move.Weapon5 }

    local selectPressed = false

    -- Hotkeys address the CURRENT PAGE's five structure slots.
    for slot, weaponSwitchCommand in ipairs(weaponSwitchCommands) do

        if HasMoveCommand( input.commands, weaponSwitchCommand ) then

            local button = self.buttons[slot]

            if button and MarineBuild_GetIsAbilityAvailable(button.index)
               and MarineBuild_GetCanAffordAbility(button.techId) then

                MarineBuild_SendSelect(button.index)
                input.commands = RemoveMoveCommand( input.commands, weaponSwitchCommand )
                selectPressed = true

            end

            break

        end

    end

    -- Mouse selection: the primary way to choose, since paging means the hotkeys only ever cover
    -- the five entries currently on screen.
    if not selectPressed and HasMoveCommand( input.commands, Move.PrimaryAttack ) then

        local consumed, selected = self:SelectHoveredButton()

        if consumed then
            -- Hit an actual button (dead or clickable) - swallow the click either way so it never
            -- reaches the world behind the menu.
            input.commands = RemoveMoveCommand( input.commands, Move.PrimaryAttack )
            selectPressed = selected
        end

        -- Missed every button entirely: DO NOT touch input.commands here, and do NOT close the
        -- menu or synthesize a SecondaryAttack. This used to fall through to a "close and pass the
        -- click through as secondary attack" branch left over from before the menu had its own
        -- open/close toggle - which meant clicking anywhere that wasn't a button (including the
        -- very click that had JUST opened the menu, if the button was still physically down on the
        -- next simulated tick) closed the menu again AND fired a synthetic secondary attack, which
        -- CombatBuilder:OnSecondaryAttack then turned into "switch to the primary weapon". Letting
        -- the PrimaryAttack bit flow through UNCHANGED means CombatBuilder:OnPrimaryAttack's own
        -- edge-guarded toggle is the ONLY thing that opens or closes this menu - one source of
        -- truth instead of two disagreeing ones.

    end

    if selectPressed then
        MarineBuild_OnClose()
        MarineBuild_Close()
    end

    return input, selectPressed

end

function GUIMarineBuildMenu:_GetIsMouseOver(overItem)

    return GUIItemContainsPoint(overItem, Client.GetCursorPosScreen())

end

function GUIMarineBuildMenu:OnAnimationCompleted(animatedItem, animationName, itemHandle)
end

-- called when the last animation remaining has completed this frame
function GUIMarineBuildMenu:OnAnimationsEnd(item)
end
