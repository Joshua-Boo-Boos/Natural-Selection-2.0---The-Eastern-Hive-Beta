-- The "pick up" hint for a BI9 on the floor uses the Pistol's icon.
local old_GUIActionIcon_ShowIcon = GUIActionIcon.ShowIcon
function GUIActionIcon:ShowIcon(buttonText, weaponType, hintText, holdFraction)
    if weaponType == "bi9" then
        weaponType = "Pistol"
    end
    return old_GUIActionIcon_ShowIcon(self, buttonText, weaponType, hintText, holdFraction)
end
