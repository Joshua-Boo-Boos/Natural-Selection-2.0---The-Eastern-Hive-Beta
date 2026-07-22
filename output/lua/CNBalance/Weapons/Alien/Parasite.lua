

function Parasite:OnHolster(player)

    Ability.OnHolster(self, player)
    self.timeLastAttack = 0
end

function Parasite:GetEnergyCost()
    local player = self:GetParent()
    if player and player.hasAdrenalineUpgrade then
        return kAdrenalineParasiteEnergyCost
    end
    return kParasiteEnergyCost
end

-- ---------------------------------------------------------------------------
-- Parasite damage-over-time.
-- On top of the direct parasite hit, marine-team targets take an additional
-- 2 damage spread over 3 seconds, of the SAME damage type as the parasite
-- (kParasiteDamageType). The effect does not stack: re-parasiting a target that
-- already has the DoT just refreshes its timer back to the full 3 seconds.
-- ---------------------------------------------------------------------------
local kParasiteDotDuration    = 3    -- seconds
local kParasiteDotTotalDamage = 2    -- total (raw) damage over the duration
local kParasiteDotInterval    = 0.5  -- tick period
local kParasiteDotDamagePerTick = kParasiteDotTotalDamage * (kParasiteDotInterval / kParasiteDotDuration)

-- Runs on the target entity (self == target). Returns the next interval to keep
-- ticking, or false to stop.
--
-- Entity-conversion safety: a player changing form (Marine <-> JetpackMarine <->
-- Exo) is a full entity REPLACE - Player:Replace() DestroyEntity()s the old entity
-- (which cancels this callback) and builds a fresh one, and Player:CopyPlayerDataFrom
-- only copies a fixed whitelist, so the new entity carries NONE of the _parasiteDot*
-- fields. The DoT therefore never carries over. The guards below are belt-and-braces:
-- even if this ever fired on a destroyed/converted/invalid reference it exits cleanly
-- (HasMixin is nil-safe; every method is existence-checked) rather than erroring.
local function ParasiteDotTick(self)

    if not Server then return false end

    -- Target must still be a valid, living, damageable entity.
    if not self or not HasMixin(self, "Live") or not self.GetIsAlive or not self:GetIsAlive() then
        if self then self._parasiteDotActive = false end
        return false
    end

    local now = Shared.GetTime()

    -- Stop once the (possibly refreshed) timer has elapsed.
    if now >= (self._parasiteDotEndTime or 0) then
        self._parasiteDotActive = false
        return false
    end

    -- Resolve the alien that applied the parasite; needed for the damage pipeline
    -- (damage attribution + friendly-fire rules). If it is gone or itself converted
    -- to another entity (its id no longer resolves / lost its team), end the DoT.
    local attacker = self._parasiteDotAttackerId and Shared.GetEntity(self._parasiteDotAttackerId)
    if not attacker or not attacker.GetTeamType then
        self._parasiteDotActive = false
        return false
    end

    local point = self:GetOrigin()
    local damage, armorUsed, healthUsed =
        GetDamageByType(self, attacker, attacker, kParasiteDotDamagePerTick, kParasiteDamageType, point, nil)

    if damage > 0 then
        self:TakeDamage(damage, attacker, attacker, point, nil, armorUsed, healthUsed, kParasiteDamageType, true)
    end

    return kParasiteDotInterval
end

local baseParasitePostDoDamage = Parasite.PostDoDamage
function Parasite:PostDoDamage(target, damage)

    if baseParasitePostDoDamage then
        baseParasitePostDoDamage(self, target, damage)
    end

    if not Server then return end
    if not target or not HasMixin(target, "Live") or not target:GetIsAlive() then return end

    -- Only marine-team entities (enemies of the parasiting alien) get the DoT.
    local parent = self.GetParent and self:GetParent()
    if not parent or not GetAreEnemies(parent, target) then return end

    -- Refresh (never stack) the timer, and start the ticking loop if not running.
    target._parasiteDotEndTime    = Shared.GetTime() + kParasiteDotDuration
    target._parasiteDotAttackerId = parent:GetId()

    if not target._parasiteDotActive then
        target._parasiteDotActive = true
        target:AddTimedCallback(ParasiteDotTick, kParasiteDotInterval)
    end
end