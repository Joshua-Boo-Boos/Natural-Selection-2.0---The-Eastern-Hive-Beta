local oldGetStatusDesc = Marine.GetPlayerStatusDesc

-- CNBalance's GetPlayerStatusDesc iterates slots 1-3 and returns on the FIRST
-- weapon found. "MotionTracker" is not in its kWeaponToStatusDesc table, so when
-- slot 1 is empty and the MT occupies slot 2 it returns nil -> "Unknown status".
-- Fix: base status on the ACTIVE weapon, using CNBalance's own lookup table for
-- all non-MT weapons so we stay consistent with everything else it handles.
function Marine:GetPlayerStatusDesc()
    if not self:GetIsAlive() then
        return kPlayerStatus.Dead
    end

    local activeWeapon = self:GetActiveWeapon()

    -- MT held directly.
    if activeWeapon and activeWeapon:isa("MotionTracker") then
        return kPlayerStatus.MotionTracker
    end

    -- No primary weapon (slot 1 empty) but MT is in slot 2.
    -- The MT defines this loadout; show "MT" even when the marine is holding
    -- their slot-3 melee weapon (Axe, Knife, Welder, etc.).
    if not self:GetWeaponInHUDSlot(1) then
        local slot2 = self:GetWeaponInHUDSlot(2)
        if slot2 and slot2:isa("MotionTracker") then
            return kPlayerStatus.MotionTracker
        end
    end

    -- Primary weapon is present OR no MT in slot 2: look up the active weapon
    -- in CNBalance's table directly, bypassing its slot-order iteration which
    -- would find the MT in slot 2 before slot 3 and return nil for it.
    if activeWeapon then
        local statusMap = debug.getupvaluex(oldGetStatusDesc, "kWeaponToStatusDesc")
        if statusMap then
            return statusMap[activeWeapon:GetClassName()] or kPlayerStatus.Void
        end
    end

    -- statusMap unavailable: delegate only when slot 1 is populated so CNBalance
    -- returns before it can stumble on the MT in slot 2.
    if self:GetWeaponInHUDSlot(1) then
        return oldGetStatusDesc(self)
    end

    return kPlayerStatus.Void
end

