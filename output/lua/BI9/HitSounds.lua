-- Hit sounds for the BI9. (Calls the previous function - the standalone mod returned the function itself, which
-- is always true and so enabled hit sounds for every weapon.)
if Server then
    local oldHitSound_IsEnabledForWeapon = HitSound_IsEnabledForWeapon
    function HitSound_IsEnabledForWeapon(techId)
        return (rawget(kTechId, "bi9") and techId == kTechId.bi9) or oldHitSound_IsEnabledForWeapon(techId)
    end
end
