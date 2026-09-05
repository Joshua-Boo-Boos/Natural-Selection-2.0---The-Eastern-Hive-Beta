-- GUIProduction (NS2.0-TEH Beta post-hook)
--
-- The small research in-progress / complete tray (bottom-left HUD) builds each entry's icon from the
-- shared atlas via GetTextureCoordinatesForIcon(techId). Combat Engineers has no atlas cell of its
-- own - its kTechIdToMaterialOffset entry points at the Combat Builder's cell purely as a fallback -
-- so without this it shows the Combat Builder icon.
--
-- Entries are created lazily the moment a tech starts researching, by `createTech`, a file-local in
-- the vanilla file that cannot be overridden directly. UpdateTech is the class method that calls it,
-- and it inserts into self.InProgress / self.Complete (both GUIList instances whose raw items are on
-- `.list`, each carrying the techId it was built for as `.Id`), so re-scanning both lists straight
-- after the base call catches an entry the moment it is created, however it got there.

local kCombatEngineersIconTexture = PrecacheAsset("ui/combat_engineers/combat_engineers_icon.dds")
local kCombatEngineersIconSize = 100

local function FixCombatEngineersIconInList(list)

    if not list or not list.list then return end

    for _, tech in ipairs(list.list) do
        if tech.Id == kTechId.CombatEngineers and tech.Icon and not tech._combatEngineersReskinned then
            tech.Icon:SetTexture(kCombatEngineersIconTexture)
            tech.Icon:SetTexturePixelCoordinates(0, 0, kCombatEngineersIconSize, kCombatEngineersIconSize)
            tech._combatEngineersReskinned = true
        end
    end

end

local baseUpdateTech = GUIProduction.UpdateTech
function GUIProduction:UpdateTech(onChange)

    baseUpdateTech(self, onChange)

    FixCombatEngineersIconInList(self.InProgress)
    FixCombatEngineersIconInList(self.Complete)

end
