-- PrimalScreamMixin
--
-- PrimalScream piggybacks on the vanilla enzyme machinery so the receiving
-- alien gets the enzyme shader, HUD timer, and standard enzyme bookkeeping
-- for free. The attack-speed override (Alien.lua / Vokex.lua) then halves the
-- enzyme delta so PrimalScream is ~50% as strong as real enzyme.
--
-- IMPORTANT: this mixin's per-entity state (enzymeIsFromPrimalScream,
-- primalScreamEndTime) is SERVER-ONLY. The mixin is added at runtime via
-- InitMixin and its fields are never merged into the Alien network spec, so
-- they don't sync. Client-facing state + sounds are delivered through the
-- explicit PrimalScreamFX network message (see PrimalScreamFX.lua).
--
-- Real enzyme overrides PrimalScream: see Alien.lua's TriggerEnzyme hook,
-- which clears the flag (and broadcasts a clear) whenever a non-PrimalScream
-- caller invokes TriggerEnzyme on the same alien.

PrimalScreamMixin = {}
PrimalScreamMixin.type = "PrimalScream"

function PrimalScreamMixin:__initmixin()
    self.enzymeIsFromPrimalScream = false
    self.primalScreamEndTime = 0
end

if Server then

    function PrimalScreamMixin:ApplyPrimalScream(duration)

        duration = duration or 8

        -- Don't downgrade a player who already has real enzyme.
        if self.GetIsEnzymed and self:GetIsEnzymed()
           and not self.enzymeIsFromPrimalScream then
            return
        end

        -- Match TriggerEnzyme's guards.
        if self.GetIsOnFire and self:GetIsOnFire() then return end
        if self.GetElectrified and self:GetElectrified() then return end

        -- Drive the same field vanilla TriggerEnzyme writes so the shader,
        -- HUD timer, and self.enzymed flag all light up.
        self.timeWhenEnzymeExpires =
            math.max(self.timeWhenEnzymeExpires or 0, duration + Shared.GetTime())

        self.enzymeIsFromPrimalScream = true
        self.primalScreamEndTime = Shared.GetTime() + duration

        -- Tell clients the primal window so the attack-speed override predicts
        -- the half-strength buff instead of full enzyme.
        if SendPrimalScreamFX then
            SendPrimalScreamFX(self, duration)
        end

    end

    -- Called from Alien.lua's TriggerEnzyme hook when real enzyme lands, so
    -- real enzyme takes over at full strength.
    function PrimalScreamMixin:ClearPrimalScreamFlag()
        if not self.enzymeIsFromPrimalScream then return end
        self.enzymeIsFromPrimalScream = false
        self.primalScreamEndTime = 0
        if SendPrimalScreamFX then
            SendPrimalScreamFX(self, 0)
        end
    end

end

function PrimalScreamMixin:GetEnzymeIsFromPrimalScream()
    return self.enzymeIsFromPrimalScream == true
end

-- True only when the alien is currently enzymed *because* of PrimalScream.
-- Server uses the authoritative flag; the client reads the networked window.
function PrimalScreamMixin:GetHasPrimalScream()

    if not (self.GetIsEnzymed and self:GetIsEnzymed()) then return false end

    if Server then
        return self.enzymeIsFromPrimalScream == true
    end

    if GetIsClientPrimalScreamed then
        return GetIsClientPrimalScreamed(self:GetId())
    end

    return false

end
