-- ======= NS2.0-TEH-Beta: CNBalance/Weapons/Alien/BiteLeap.lua =======
--
-- Post-hook on lua/Weapons/Alien/BiteLeap.lua.
--
-- Adds killfeed-icon support for Leap-impact kills (see CNBalance/Lifeforms/Skulk.lua,
-- which deals the actual Leap-impact damage).  The Skulk's PreUpdateMove hook uses
-- this weapon instance as the DoDamage "doer" and briefly flags it (self._isLeapImpact)
-- immediately around the killing hit, so GetDeathIconIndex reports the Leap icon
-- for that specific kill instead of the normal Bite icon.
-- ============================================================

local baseGetDeathIconIndex = BiteLeap.GetDeathIconIndex
function BiteLeap:GetDeathIconIndex()
    if self._isLeapImpact then
        return kDeathMessageIcon.Leap
    end
    return baseGetDeathIconIndex(self)
end
