-- Adds the Skulk Parasite "Infection" meter to Marine/JetpackMarine only.
-- Hooked on SetParasited (not OnTakeDamage) because every Parasite source —
-- a Skulk's weapon hit, a Drifter's periodic nearby-parasite pulse
-- (CNBalance/Structures/Alien/Drifter.lua:772-783), and vanilla Rupture
-- (NS2-Copy/ns2/lua/CommAbilities/Alien/Rupture.lua:42-56, not currently
-- present in this mod) — all funnel through SetParasited exactly once per
-- application. OnTakeDamage only ever sees the weapon-hit case; hooking it
-- (as an earlier version of this file did) silently misses Drifter/Rupture.
--
-- Fully separate from vanilla's own parasited/reveal system below — that
-- keeps running unmodified; this just listens on the same call.
--
-- This hook only RECORDS each hit (a timestamp, plus who gets credit) into
-- self.infectionHitTimestamps. Counting how many of those are still within
-- the trailing kInfectionHitWindowSeconds window, and deciding when that
-- reaches 3 (Infected!), happens continuously in Marine.lua's OnProcessMove
-- - that way a hit can also be forgotten by the mere passage of time (no new
-- hit needed to trigger re-evaluation), not just overwritten by a newer one.

-- BUG (found by the reported symptom "took 4 or 5 Parasite applications to
-- get the 3 damage ticks"): this was 1 second, but the Parasite WEAPON's own
-- fire rate (kParasiteFireRate, Balance.lua) is 0.54s - LESS than the
-- debounce window. So every other legitimate weapon hit was silently
-- swallowed as "too soon", requiring ~5 real hits to land 3 counted ones
-- (hits 1,3,5 count; 2,4 get debounced) instead of 3.
--
-- The comment this replaces assumed the Drifter's periodic nearby-parasite
-- pulse (Drifter.lua's ParasiteNearbyEnemy) calls SetParasited every single
-- server tick with no rate limit of its own - that's no longer true (or was
-- never true here): ParasiteNearbyEnemy is already self-throttled to
-- kDetectInterval (0.5s, Balance.lua) via its own kLastParasitedTime check,
-- and Rupture (CommAbilities/Alien/Rupture.lua) only calls SetParasited once
-- per burst (OnAbilityOptionalEnd), not repeatedly at all. Neither source
-- needs a 1s guard to avoid same-frame spam.
--
-- 0.1s is comfortably below both real per-hit intervals (Skulk weapon 0.54s,
-- Drifter pulse 0.5s), so every legitimate hit from any source now counts,
-- while still rejecting a genuine same-tick/re-entrant duplicate call.
local kInfectionMinHitSpacingSeconds = 0.1

-- Guard for the one legitimate case where Marine.lua/Exo.lua deliberately
-- pass a REAL Parasite weapon as `doer` to a damage tick (so the killfeed
-- shows the correct killer + Parasite icon) - that live doer's isa("Parasite")
-- re-triggers vanilla ParasiteMixin:OnTakeDamage -> SetParasited, which would
-- otherwise re-enter this same hook and log a spurious extra "hit" mid-DoT.
-- Marine.lua/Exo.lua set this true only around that specific call, then
-- immediately clear it - it does not affect real Parasite hits at all.
local baseParasiteMixinSetParasited = ParasiteMixin.SetParasited
function ParasiteMixin:SetParasited(fromPlayer, durationOverride)

    baseParasiteMixinSetParasited(self, fromPlayer, durationOverride)

    if Server and (self:isa("Marine") or self:isa("JetpackMarine"))
       and not self.infectionWasFullyInfected
       and not self.suppressInfectionReinfect then

        -- Locked (no new hits recorded) while already Infected! (Task 2's
        -- OnProcessMove clears infectionWasFullyInfected once fully decayed).
        self.infectionHitTimestamps = self.infectionHitTimestamps or {}

        local now = Shared.GetTime()
        local lastHit = self.infectionHitTimestamps[#self.infectionHitTimestamps]
        local tooSoon = lastHit and (now - lastHit) < kInfectionMinHitSpacingSeconds

        -- A debounced call (too soon after the last counted hit) does not
        -- count as a hit at all - no timestamp added, no credit change.
        if not tooSoon then
            table.insert(self.infectionHitTimestamps, now)

            if fromPlayer then
                -- Drifter/Rupture both pass their owning Commander as
                -- fromPlayer (SetParasited(self:GetOwner(), ...) in both
                -- cases) — a weapon hit passes the attacking Skulk, which is
                -- never a Commander. Credit reflects whichever hit most
                -- recently counted.
                self.infectionCreditedIsCommander = fromPlayer:isa("Commander")
                self.infectionCreditedAttackerId = self.infectionCreditedIsCommander
                    and Entity.invalidId or fromPlayer:GetId()
            end
        end

    end

end
