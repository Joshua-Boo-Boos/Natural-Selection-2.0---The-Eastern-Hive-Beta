

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
-- (kParasiteDamageType).
--
-- The effect NEITHER STACKS NOR REFRESHES. While a DoT is already running on a
-- target, re-parasiting it is ignored outright: the timer is not extended, the
-- damage is not re-applied, and no second ticker is started. A new DoT can only
-- begin once the previous one has finished.
-- ---------------------------------------------------------------------------
local kParasiteDotDuration    = 3    -- seconds
local kParasiteDotTotalDamage = 2    -- total (raw) damage over the duration
local kParasiteDotTicks       = 3    -- equal intervals across the duration

-- One tick per second, each dealing 2/3, so the full 2 damage lands in equal instalments.
local kParasiteDotInterval      = kParasiteDotDuration / kParasiteDotTicks
local kParasiteDotDamagePerTick = kParasiteDotTotalDamage / kParasiteDotTicks

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

    --[[
        COUNT TICKS, do not compare against an end time.

        The previous version stopped on `now >= endTime`, which silently DROPPED THE FINAL TICK: at
        0.5s intervals over 3s it dealt 5 ticks of 1/3 = 1.667 damage, not the intended 2. Counting
        instalments makes the total exact and independent of scheduler drift -- 3 ticks of 2/3 is
        always precisely 2.
    ]]
    local ticksLeft = self._parasiteDotTicksLeft or 0

    if ticksLeft <= 0 then
        self._parasiteDotActive = false
        return false
    end

    self._parasiteDotTicksLeft = ticksLeft - 1

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

    -- That was the last instalment; the full 2 damage has now been dealt.
    if self._parasiteDotTicksLeft <= 0 then
        self._parasiteDotActive = false
        return false
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

    -- ALREADY RUNNING -> IGNORE COMPLETELY.
    --
    -- Previously the end time was rewritten on every hit, so re-parasiting extended the DoT to a
    -- fresh 3 seconds each time. A target under sustained parasite fire could be held in the effect
    -- indefinitely, which is the "resets/reapplies on reproc" behaviour that is not wanted. Bailing
    -- out here means the current effect always runs exactly its 3 seconds and no longer, and a new
    -- one can only start after it has ended.
    if target._parasiteDotActive then return end

    target._parasiteDotActive     = true
    target._parasiteDotTicksLeft  = kParasiteDotTicks
    target._parasiteDotAttackerId = parent:GetId()

    target:AddTimedCallback(ParasiteDotTick, kParasiteDotInterval)
end