-- ======= NS2.0-TEH-Beta: CNBalance/GUI/GUIExoThruster.lua =======
--
-- Post-hook on lua/GUIExoThruster.lua (the Exo Fuel / thruster HUD bar).
--
-- Publishes the fuel bar's ACTUAL absolute top-edge Y (screen pixels) into a global
-- so the "Brazier Industries Exosuit" info panel (CNBalance/GUI/GUIExoHUD.lua) can
-- park its bottom edge a fixed margin ABOVE the fuel bar and grow upward from there.
-- Deriving the line from the real element means the panel can never clip the fuel
-- bar at any resolution or GUIScale, no matter how many upgrades the exo carries.
--
-- The fuel bar's background is anchored Middle/Bottom, so the anchor origin is the
-- screen bottom (y = screenHeight) and SetPosition places its top-left relative to
-- that anchor with a negative y.  Hence: absTop = screenHeight + position.y.

local kFuelBarSafetyPad = 2   -- design px; tiny extra so rounding never overlaps

local function PublishFuelBarTop(self)
    if not self.background then return end
    local pos = self.background:GetPosition()
    local absTop = Client.GetScreenHeight() + pos.y - GUIScale(kFuelBarSafetyPad)
    _G.gExoFuelBarTopAbsY = absTop
end

local baseInitialize = GUIExoThruster.Initialize
function GUIExoThruster:Initialize()
    baseInitialize(self)
    PublishFuelBarTop(self)
end

-- Re-publish on Update too, so a mid-game resolution / GUIScale change is tracked
-- (the background is repositioned on re-init; this keeps the global current cheaply).
local baseUpdate = GUIExoThruster.Update
function GUIExoThruster:Update(deltaTime)
    baseUpdate(self, deltaTime)
    PublishFuelBarTop(self)
end

local baseUninitialize = GUIExoThruster.Uninitialize
function GUIExoThruster:Uninitialize()
    _G.gExoFuelBarTopAbsY = nil
    baseUninitialize(self)
end
