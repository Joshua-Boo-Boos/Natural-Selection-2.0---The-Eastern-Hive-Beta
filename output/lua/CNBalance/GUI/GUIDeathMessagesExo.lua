-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIDeathMessagesExo.lua =======
--
-- Post-hook on lua/GUIDeathMessages.lua (loaded after GUIDeathMessagesLeap.lua
-- and MotionTracker/GUIDeathMessages.lua - this override calls whatever the
-- previous GUIDeathMessages.AddMessage was for every non-Exo kill, so hook
-- order does not matter for those).
--
-- Renders every Exo-weapon kill as a single horizontal row:
--
--     Killer_Name  EXO  [icon(s)]  Victim_Name
--
--   - "EXO" is bold + white, sitting immediately before the weapon icon.
--   - Minigun / Railgun / Flamethrower / GrenadeLauncher / Claw each show their
--     own single weapon icon.
--   - A flamethrower FIRE-POOL (damage-over-time) kill additionally shows a
--     skull icon between "EXO" and the flamethrower icon.
--   - Self-Destruct keeps its plain None-icon row (no EXO prefix), unchanged.
--
-- Vanilla GUIDeathMessages:AddMessage (and MotionTracker's AddMessageCustom)
-- only ever build ONE icon per row and rely on file-local layout constants we
-- cannot reach from a hook, so this file re-declares those constants (identical
-- values, copied from MotionTracker/GUIDeathMessages.lua) and builds the Exo
-- rows itself, giving full control over the icon count and spacing (the user
-- reported the previous None+icon pairing left far too much horizontal gap).
--
-- Console death-message text is EnumToString(kDeathMessageIcon, iconIndex)
-- (DeathMessage_Client.lua), i.e. the enum key name - so the enum names chosen
-- in CNBalance/Globals.lua already produce the requested console text, EXCEPT
-- ExoFlamethrowerBurn (fire-pool), which is remapped back to "ExoFlamethrower"
-- by the narrow EnumToString wrap at the bottom so ALL flamethrower kills read
-- identically in the console.

-- ── Layout constants (copied from MotionTracker/GUIDeathMessages.lua) ─────────
local kKillHighlight        = PrecacheAsset("ui/killfeed_highlight.dds")
local kKillLeftBorderCoords   = { 0, 0, 15, 64 }
local kKillMiddleBorderCoords = { 16, 0, 112, 64 }
local kKillRightBorderCoords  = { 113, 0, 128, 64 }
local kFontName             = Fonts.kAgencyFB_Small
local kExoLabelFont         = Fonts.kAgencyFB_Large_Bold   -- only bold Agency variant near this size
local kBackgroundHeight     = GUIScale(32)
local kScreenOffset         = GUIScale(40)
local kScreenOffsetX        = GUIScale(38)
local kSustainTime          = 4

-- Skull texture for fire-pool (DOT) flamethrower kills. Standalone texture
-- (not the inventory-icon atlas), so it is drawn with full [0..1] UVs.
local kSkullTexture = PrecacheAsset("cinematics/vfx_materials/skull.dds")

-- Each death-message icon cell in kInventoryIconsTexture is 128 wide x 64 tall
-- (DeathMessage_Client.lua kSubImageWidth/Height), the glyph roughly centred
-- with wide transparent side padding. Rendering the full 2:1 cell is what made
-- the previous paired icons look far apart, so we crop each icon to its central
-- SQUARE (the middle 64px) - this both tightens the spacing and keeps the icons
-- undistorted (assumes the glyph is centred in its cell, which holds for these).
local kCellW = 128
local kCellH = 64
-- Central horizontal crop width of each 128px cell. Wider than the previous
-- square (64) so icons render noticeably wider/bigger, while still trimming the
-- outermost side padding that made the full 128px cells look too far apart.
local kIconCropW = 104

-- Leap kill icon zoom: the tech-tree Leap icon (buildmenu.dds cell) renders
-- small because its glyph sits with padding inside the cell. To make the VISUAL
-- ~2x bigger WITHOUT changing the icon's box footprint (so it stays within the
-- killfeed row), we crop to the central (1/zoom) region of the cell and let it
-- fill the same box - a 2x zoom shows the central 50%. (inset per side below.)
local kLeapIconZoom = 2.0

-- Small horizontal gaps between row elements (design px, scaled at use).
local kGapAfterName   = 4
local kGapAfterExo    = 4
local kGapBetweenIcon = 2
local kGapBeforeName  = 4

-- ── Exo kill icon table ──────────────────────────────────────────────────────
-- base   = the vanilla kDeathMessageIcon whose atlas cell supplies the weapon icon
-- skull  = show the skull icon before the weapon icon (fire-pool DOT)
-- exo    = show the bold "EXO" prefix label
-- cropW  = optional per-icon horizontal crop width (defaults to kIconCropW) -
--          the None cell's glyph is wider than the default crop, so a wider
--          crop shows it at natural width instead of clipped/thin.
local kExoKillIcons = {
    [kDeathMessageIcon.Minigun]             = { base = kDeathMessageIcon.Minigun,      skull = false, exo = true  },
    [kDeathMessageIcon.Railgun]             = { base = kDeathMessageIcon.Railgun,      skull = false, exo = true  },
    [kDeathMessageIcon.Claw]                = { base = kDeathMessageIcon.Claw,         skull = false, exo = true  },
    [kDeathMessageIcon.ExoFlamethrower]     = { base = kDeathMessageIcon.Flamethrower, skull = false, exo = true  },
    [kDeathMessageIcon.ExoFlamethrowerBurn] = { base = kDeathMessageIcon.Flamethrower, skull = true,  exo = true  },
    [kDeathMessageIcon.ExoWelder]           = { base = kDeathMessageIcon.Welder,       skull = false, exo = true  },
    -- Grenade Launcher: the Pulse Grenade icon (the Exo grenade is a pulse-grenade
    -- copy), NOT the GL grenade icon.
    [kDeathMessageIcon.ExoGrenadeLauncher]  = { base = kDeathMessageIcon.PulseGrenade, skull = false, exo = true  },
    -- Self-Destruct: plain None icon, no EXO prefix (kept as-is by request).
    -- Wider crop (128 = full cell) so the None glyph is not clipped thin.
    [kDeathMessageIcon.ExoSelfDestruct]     = { base = kDeathMessageIcon.None,         skull = false, exo = false, cropW = 128 },
}

-- Central pixel rect (cropW wide x kCellH tall) for a death-message icon.
local function GetIconRect(iconIndex, cropW)
    cropW = cropW or kIconCropW
    local yTop  = (iconIndex - 1) * kCellH
    local xLeft = (kCellW - cropW) * 0.5    -- crop to the central cropW column
    return xLeft, yTop, xLeft + cropW, yTop + kCellH
end

-- ── Custom Exo row builder ───────────────────────────────────────────────────
local function BuildExoRow(self, killerColor, killerName, targetColor, targetName, spec, targetIsPlayer)

    local m = { Background = nil, Killer = nil, Weapon = nil, Target = nil, Time = 0 }
    if table.icount(self.reuseMessages) > 0 then
        m = self.reuseMessages[1]
        m["Time"] = 0
        m["Background"]:SetIsVisible(self.visible)
        table.remove(self.reuseMessages, 1)
    end

    local rowScale  = GetScaledVector() * self.scale
    -- Icon dimensions: taller than before (the user wanted bigger icons) and
    -- WIDER than tall - each atlas cell is 128x64 with the glyph roughly
    -- centred; cropping to the central kIconCropW-wide slice (see
    -- GetIconRect) keeps them wide while trimming the excess side padding that
    -- made the previous full-cell version look too spaced out.
    local iconH    = kBackgroundHeight - GUIScale(2)
    local iconCropW = spec.cropW or kIconCropW
    local iconW    = iconH * (iconCropW / kCellH)

    -- Killer text.
    if m["Killer"] == nil then m["Killer"] = GUIManager:CreateTextItem() end
    m["Killer"]:SetFontName(kFontName)
    m["Killer"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    m["Killer"]:SetTextAlignmentX(GUIItem.Align_Min)
    m["Killer"]:SetTextAlignmentY(GUIItem.Align_Center)
    m["Killer"]:SetColor(ColorIntToColor(killerColor))
    m["Killer"]:SetText(killerName)
    m["Killer"]:SetScale(rowScale)
    GUIMakeFontScale(m["Killer"])

    -- "EXO" bold-white label. Agency FB has no small-bold face, so use the
    -- large-bold face scaled down to roughly the small line height (27/41).
    if m["ExoLabel"] == nil then m["ExoLabel"] = GUIManager:CreateTextItem() end
    local exoScale = rowScale * (27 / 41)
    m["ExoLabel"]:SetFontName(kExoLabelFont)
    m["ExoLabel"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    m["ExoLabel"]:SetTextAlignmentX(GUIItem.Align_Min)
    m["ExoLabel"]:SetTextAlignmentY(GUIItem.Align_Center)
    m["ExoLabel"]:SetColor(Color(1, 1, 1, 1))
    m["ExoLabel"]:SetText("EXO")
    m["ExoLabel"]:SetScale(exoScale)
    GUIMakeFontScale(m["ExoLabel"])
    m["ExoLabel"]:SetIsVisible(spec.exo)

    -- Skull icon (fire-pool DOT only). Square (its texture is square), same
    -- height as the weapon icon.
    if m["ExoSkull"] == nil then m["ExoSkull"] = GUIManager:CreateGraphicItem() end
    m["ExoSkull"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    m["ExoSkull"]:SetSize(Vector(iconH, iconH, 0))
    m["ExoSkull"]:SetTexture(kSkullTexture)
    m["ExoSkull"]:SetColor(Color(1, 1, 1, 1))
    m["ExoSkull"]:SetIsVisible(spec.skull)

    -- Weapon icon (wide: iconW x iconH, cropped central slice of the cell).
    if m["Weapon"] == nil then m["Weapon"] = GUIManager:CreateGraphicItem() end
    m["Weapon"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    m["Weapon"]:SetSize(Vector(iconW, iconH, 0))
    m["Weapon"]:SetTexture(kInventoryIconsTexture)
    m["Weapon"]:SetTexturePixelCoordinates(GetIconRect(spec.base, iconCropW))
    m["Weapon"]:SetColor(Color(1, 1, 1, 1))
    m["Weapon"]:SetIsVisible(true)

    -- Target text.
    if m["Target"] == nil then m["Target"] = GUIManager:CreateTextItem() end
    m["Target"]:SetFontName(kFontName)
    m["Target"]:SetAnchor(GUIItem.Left, GUIItem.Center)
    m["Target"]:SetTextAlignmentX(GUIItem.Align_Min)
    m["Target"]:SetTextAlignmentY(GUIItem.Align_Center)
    m["Target"]:SetColor(ColorIntToColor(targetColor))
    m["Target"]:SetText(targetName)
    m["Target"]:SetScale(rowScale)
    GUIMakeFontScale(m["Target"])

    -- Create the Background + borders once.
    if m["Background"] == nil then
        m["Background"] = GUIManager:CreateGraphicItem()
        m["Background"]:SetLayer(kGUILayerPlayerHUD)
        m["Background"].left = GUIManager:CreateGraphicItem()
        m["Background"].left:SetAnchor(GUIItem.Left, GUIItem.Top)
        m["Background"].right = GUIManager:CreateGraphicItem()
        m["Background"].right:SetAnchor(GUIItem.Right, GUIItem.Top)
        m["Background"]:AddChild(m["Background"].right)
        m["Background"]:AddChild(m["Background"].left)
        self.anchor:AddChild(m["Background"])
    end

    -- Parent all content items directly to Background EVERY build (not guarded):
    -- self.reuseMessages is shared with the vanilla/MotionTracker builders, which
    -- parent Killer/Target as children of Weapon instead. Re-establishing our own
    -- flat structure each time a pooled table is reused keeps positions (which we
    -- set relative to Background below) correct regardless of the table's history.
    -- Detach Killer/Target from whatever they're currently parented to (Weapon, if
    -- this table last held a vanilla/MotionTracker row) before re-attaching -
    -- AddChild alone does not guarantee a clean re-parent (see the AddMessage
    -- override below for the same fix in the opposite direction).
    for _, key in ipairs({ "Killer", "Target" }) do
        if m[key] and m[key].GetParent then
            local oldParent = m[key]:GetParent()
            if oldParent and oldParent ~= m["Background"] then oldParent:RemoveChild(m[key]) end
        end
    end
    m["Background"]:AddChild(m["Killer"])
    m["Background"]:AddChild(m["ExoLabel"])
    m["Background"]:AddChild(m["ExoSkull"])
    m["Background"]:AddChild(m["Weapon"])
    m["Background"]:AddChild(m["Target"])

    -- Measure widths using each item's ACTUAL scale after GUIMakeFontScale
    -- (which changes the scale from what SetScale was given) - measuring with
    -- the pre-adjustment rowScale/exoScale over-reports the width and was what
    -- opened the large empty gap between the killer name and "EXO".
    local killerW = m["Killer"]:GetTextWidth(killerName) * m["Killer"]:GetScale().x
    local exoW    = spec.exo and (m["ExoLabel"]:GetTextWidth("EXO") * m["ExoLabel"]:GetScale().x) or 0
    local targetW = m["Target"]:GetTextWidth(targetName) * m["Target"]:GetScale().x

    -- Lay out left-to-right, accumulating x.
    local x = 0
    m["Killer"]:SetPosition(Vector(x, 0, 0))
    x = x + killerW + GUIScale(kGapAfterName)

    if spec.exo then
        m["ExoLabel"]:SetPosition(Vector(x, 0, 0))
        x = x + exoW + GUIScale(kGapAfterExo)
    end

    if spec.skull then
        m["ExoSkull"]:SetPosition(Vector(x, -iconH / 2, 0))
        x = x + iconH + GUIScale(kGapBetweenIcon)
    end

    m["Weapon"]:SetPosition(Vector(x, -iconH / 2, 0))
    x = x + iconW + GUIScale(kGapBeforeName)

    m["Target"]:SetPosition(Vector(x, 0, 0))
    x = x + targetW

    -- Background sizing / positioning / borders (mirrors MotionTracker's).
    local player = Client.GetLocalPlayer()
    local backgroundColor = ConditionalValue(GUIDeathMessages.kKillfeedCustomColorEnabled, GUIDeathMessages.kKillfeedCustomColor, ColorIntToColor(killerColor))
    backgroundColor.a = ConditionalValue(player and GUIDeathMessages.kKillfeedHighlightEnabled and Client.GetIsControllingPlayer() and player:GetName() == killerName and targetIsPlayer and killerColor ~= targetColor, 1, 0)

    local totalWidth = x
    m["BackgroundWidth"]   = totalWidth
    m["Background"]:SetSize(Vector(totalWidth, kBackgroundHeight, 0))
    m["Background"]:SetAnchor(GUIItem.Right, GUIItem.Top)
    m["BackgroundXOffset"] = -totalWidth - kScreenOffset - kScreenOffsetX
    m["Background"]:SetPosition(Vector(m["BackgroundXOffset"], 0, 0))
    m["Background"]:SetColor(backgroundColor)
    m["Background"]:SetTexture(kKillHighlight)
    m["Background"]:SetTexturePixelCoordinates(GUIUnpackCoords(kKillMiddleBorderCoords))

    m["Background"].left:SetColor(backgroundColor)
    m["Background"].left:SetTexture(kKillHighlight)
    m["Background"].left:SetTexturePixelCoordinates(GUIUnpackCoords(kKillLeftBorderCoords))
    m["Background"].left:SetSize(Vector(GUIScale(8), kBackgroundHeight, 0))
    m["Background"].left:SetInheritsParentAlpha(true)
    m["Background"].left:SetPosition(Vector(-GUIScale(8), 0, 0))

    m["Background"].right:SetColor(backgroundColor)
    m["Background"].right:SetTexture(kKillHighlight)
    m["Background"].right:SetTexturePixelCoordinates(GUIUnpackCoords(kKillRightBorderCoords))
    m["Background"].right:SetSize(Vector(GUIScale(8), kBackgroundHeight, 0))
    m["Background"].right:SetInheritsParentAlpha(true)
    m.sustainTime = kSustainTime

    table.insert(self.messages, m)
end

-- ── AddMessage override ──────────────────────────────────────────────────────
local baseExoAddMessage = GUIDeathMessages.AddMessage
function GUIDeathMessages:AddMessage(killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)

    local spec = iconIndex and kExoKillIcons[iconIndex]
    if spec then
        BuildExoRow(self, killerColor, killerName, targetColor, targetName, spec, targetIsPlayer)
        return
    end

    -- Non-Exo kill: defer to the existing chain. If a recycled table previously
    -- held an Exo row, its Killer/Target were re-parented to Background (our flat
    -- structure) and it carries extra Exo items - the base builder only re-parents
    -- when Background is nil (skipped on reuse), so restore the vanilla structure
    -- (Killer/Target as children of Weapon) and hide the Exo-only items, or the
    -- recycled row would render mispositioned.
    baseExoAddMessage(self, killerColor, killerName, targetColor, targetName, iconIndex, targetIsPlayer)
    local m = self.messages[#self.messages]
    if m then
        -- Detach from the OLD parent before re-attaching to Weapon. Every other
        -- re-parenting call in NS2's own GUI code (GUIScoreboard.lua,
        -- GUIInsight_*.lua, etc.) calls RemoveChild before AddChild - AddChild
        -- alone does not guarantee a clean re-parent, and if this recycled table
        -- last held an Exo row, Killer/Target's parent is still Background (our
        -- flat structure). Leaving that stale parent link was very likely why the
        -- victim (and/or killer) name rendered wrong or went missing entirely on a
        -- recycled table - not just the stale-position bug fixed below.
        if m["Killer"] and m["Killer"].GetParent then
            local oldParent = m["Killer"]:GetParent()
            if oldParent and oldParent ~= m["Weapon"] then oldParent:RemoveChild(m["Killer"]) end
        end
        if m["Target"] and m["Target"].GetParent then
            local oldParent = m["Target"]:GetParent()
            if oldParent and oldParent ~= m["Weapon"] then oldParent:RemoveChild(m["Target"]) end
        end
        if m["Weapon"] and m["Killer"] then m["Weapon"]:AddChild(m["Killer"]) end
        if m["Weapon"] and m["Target"] then m["Weapon"]:AddChild(m["Target"]) end
        -- CRITICAL: vanilla's reuse path positions Killer/Target purely via their
        -- anchors and never calls SetPosition, so it leaves whatever position the
        -- item already had. Our Exo builder DID SetPosition the Target to a large
        -- accumulated-width x (and Killer to 0). If this recycled table last held
        -- an Exo row, that stale x survives and shoves the victim name ~a full row
        -- width to the right - off-screen, only the first character visible, with
        -- empty space before it. Reset both to (0,0,0) so they sit at their anchors
        -- exactly as a fresh vanilla row would.
        if m["Killer"] then m["Killer"]:SetPosition(Vector(0, 0, 0)) end
        if m["Target"] then m["Target"]:SetPosition(Vector(0, 0, 0)) end
        if m["ExoLabel"] then m["ExoLabel"]:SetIsVisible(false) end
        if m["ExoSkull"] then m["ExoSkull"]:SetIsVisible(false) end

        -- Leap kills are routed to the tech-tree Leap icon (buildmenu.dds cell
        -- 7,5 -> x0=560,y0=400) by GUIDeathMessagesLeap.lua's AddMessageCustom,
        -- which sets the correct full-cell texture coordinates. That icon renders
        -- small because its glyph is padded inside the cell, so zoom into the
        -- central 1/kLeapIconZoom region to make the visual ~2x bigger while
        -- KEEPING the icon's box footprint (it stays within the killfeed row).
        -- CRITICAL vs the old broken crop: use the cell's ACTUAL x0/y0 offsets
        -- (from the Leap-overridden DeathMsgUI_GetTechOffset* functions), not an
        -- assumed 0 x-offset - otherwise the crop lands on the wrong cell/column.
        if iconIndex == kDeathMessageIcon.Leap and m["Weapon"] then
            local x0 = DeathMsgUI_GetTechOffsetX(iconIndex)
            local y0 = DeathMsgUI_GetTechOffsetY(iconIndex)
            local w  = DeathMsgUI_GetTechWidth(iconIndex)
            local h  = DeathMsgUI_GetTechHeight(iconIndex)
            local insetX = w * (1 - 1 / kLeapIconZoom) * 0.5
            local insetY = h * (1 - 1 / kLeapIconZoom) * 0.5
            m["Weapon"]:SetTexturePixelCoordinates(
                x0 + insetX, y0 + insetY, x0 + w - insetX, y0 + h - insetY)
        end
    end
end

-- ── Console text: fire-pool flamethrower kills read "ExoFlamethrower" ─────────
-- Console death text is EnumToString(kDeathMessageIcon, iconIndex). The
-- fire-pool DOT uses a distinct icon enum (ExoFlamethrowerBurn) so the killfeed
-- can add the skull, but the user wants ALL flamethrower kills to read
-- "ExoFlamethrower" in the console - so remap just that one pair. Narrow guard
-- (exact enum table + value) keeps every other EnumToString caller untouched.
local baseEnumToString = EnumToString
function EnumToString(enumTable, enumNumber)
    if enumTable == kDeathMessageIcon and enumNumber == kDeathMessageIcon.ExoFlamethrowerBurn then
        return "ExoFlamethrower"
    end
    return baseEnumToString(enumTable, enumNumber)
end
