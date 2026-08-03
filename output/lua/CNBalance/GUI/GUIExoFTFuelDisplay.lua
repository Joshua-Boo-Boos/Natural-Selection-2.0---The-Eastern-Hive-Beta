-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIExoFTFuelDisplay.lua =======
--
-- Custom charge-circle display for the Exo FLAMETHROWER arm. Loaded into the arm's charge GUIView
-- (target texture "*exo_railgun_<slot>") by ExoSpecialWeapon.lua's OnUpdateRender instead of the
-- vanilla railgun display. It is a near-copy of lua/GUIRailgun.lua, with ONE change: the red PULSE
-- triggers when the circle is EMPTY (fuel ~0 = 100% heat / overheated) rather than when it's full.
--
-- We need a separate file rather than a hook because GUIRailgun.lua's pulse is computed inside its
-- UpdateCharge and recolours a FILE-LOCAL circle object (no seam to override), and that file is
-- shared with the real railgun (which must still flash when FULL). The FT is fed `chargeAmount` =
-- fuel (1 - heat) via SetGlobal.

Script.Load("lua/GUIDial.lua")

local kTexture = "models/marine/exosuit/exosuit_view_panel_rail2.dds"

chargeAmount = 0   -- fuel (1 - heat); set externally each frame

local chargeCircle
local time = 0

function Update(dt)

    local pulseAmt = (1 + math.cos(time * 20)) * 0.5
    -- INVERTED vs the railgun: pulse red when EMPTY (fuel near 0 = overheated), steady otherwise.
    local colorAmt = chargeAmount <= 0.05 and (pulseAmt * 0.5) or 1
    chargeCircle:GetLeftSide():SetColor(Color(1, colorAmt, colorAmt, 1))
    chargeCircle:GetRightSide():SetColor(Color(1, colorAmt, colorAmt, 1))

    chargeCircle:SetPercentage(chargeAmount)   -- fill = fuel: full when cool, empty at overheat
    chargeCircle:Update(dt)

    time = time + dt

end

local kWidth = 246
local kHeight = 256
local kTexWidth = 450
local kTexHeight = 452
function Initialize()

    GUI.SetSize(kWidth, kHeight)

    local settings = {}
    settings.BackgroundWidth = kWidth
    settings.BackgroundHeight = kHeight
    settings.BackgroundAnchorX = GUIItem.Left
    settings.BackgroundAnchorY = GUIItem.Bottom
    settings.BackgroundOffset = Vector(0, 0, 0)
    settings.BackgroundTextureName = kTexture
    settings.BackgroundTextureX1 = 0
    settings.BackgroundTextureY1 = 0
    settings.BackgroundTextureX2 = kTexWidth
    settings.BackgroundTextureY2 = kTexHeight
    settings.ForegroundTextureName = kTexture
    settings.ForegroundTextureWidth = kTexWidth
    settings.ForegroundTextureHeight = kTexHeight
    settings.ForegroundTextureX1 = kTexWidth
    settings.ForegroundTextureY1 = 0
    settings.ForegroundTextureX2 = kTexWidth * 2
    settings.ForegroundTextureY2 = kTexHeight
    settings.InheritParentAlpha = true

    chargeCircle = GUIDial()
    chargeCircle:Initialize(settings)
    chargeCircle:GetBackground():SetIsVisible(true)

end

Initialize()
