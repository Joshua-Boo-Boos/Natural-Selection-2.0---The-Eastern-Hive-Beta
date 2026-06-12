local old_GUIActionIcon_ShowIcon = GUIActionIcon.ShowIcon
function GUIActionIcon:ShowIcon(buttonText, weaponType, hintText, holdFraction)

    if weaponType == 'MotionTracker' then
        weaponType = 'Pistol'
    end
    return old_GUIActionIcon_ShowIcon(self, buttonText, weaponType, hintText, holdFraction)
end
