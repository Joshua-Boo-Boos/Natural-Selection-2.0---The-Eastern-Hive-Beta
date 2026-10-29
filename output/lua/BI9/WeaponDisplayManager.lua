-- Preload the BI9's on-gun ammo display (GUIBI9Display.lua).
local GetWeaponClassesToPreload = WeaponDisplayManager.GetWeaponClassesToPreload
function WeaponDisplayManager:GetWeaponClassesToPreload()
    local classList = GetWeaponClassesToPreload(self)
    if bi9 then
        table.insert(classList, bi9)
    end
    return classList
end
