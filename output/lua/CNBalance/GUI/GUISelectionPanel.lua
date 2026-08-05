-- GUISelectionPanel (NS2.0-TEH Beta post-hook)
--
-- The commander selection panel's small status icon (shown inside the researching / upgrading /
-- constructing progress bar, bottom-right) builds from the shared atlas via
-- GetTextureCoordinatesForIcon. Combat Engineers has no atlas cell of its own - its
-- kTechIdToMaterialOffset entry points at the Combat Builder's cell purely as a fallback - so
-- without this it shows the Combat Builder icon while Combat Engineers is researching.
--
-- Unlike the research tray, self.statusIcon is a SINGLE, permanently-reused GUIItem whose texture
-- coordinates are re-set on every UpdateSingleSelection call, so this cannot be applied once and
-- left: it must be re-asserted after each base call, AND reverted whenever the panel is showing any
-- other tech, or the standalone texture would stick to unrelated selections.

local kCombatEngineersIconTexture = PrecacheAsset("ui/combat_engineers/combat_engineers_icon.dds")
local kCombatEngineersIconSize = 100
local kDefaultIconTexture = "ui/buildmenu.dds"

local baseUpdateSingleSelection = GUISelectionPanel.UpdateSingleSelection
function GUISelectionPanel:UpdateSingleSelection(entity)

    baseUpdateSingleSelection(self, entity)

    if not self.statusIcon then
        return
    end

    -- CommanderUI_GetSelectedBargraphs returns the same [text, percentage, techId] triple the base
    -- method already used internally to decide what to display, so calling it again here is the only
    -- way to recover which techId this update was for.
    local selectedBargraphs = CommanderUI_GetSelectedBargraphs(entity)
    local statusTechId = selectedBargraphs and selectedBargraphs[3]

    if statusTechId == kTechId.CombatEngineers then
        self.statusIcon:SetTexture(kCombatEngineersIconTexture)
        self.statusIcon:SetTexturePixelCoordinates(0, 0, kCombatEngineersIconSize, kCombatEngineersIconSize)
    else
        self.statusIcon:SetTexture(kDefaultIconTexture)
    end

end
