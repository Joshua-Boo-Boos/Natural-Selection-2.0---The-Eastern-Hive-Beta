local GetWeaponClassesToPreload = WeaponDisplayManager.GetWeaponClassesToPreload
function WeaponDisplayManager:GetWeaponClassesToPreload()

    local classList = GetWeaponClassesToPreload(self)

    assert(MotionTracker)
    table.insert(classList, MotionTracker)
    
    return classList
    
end