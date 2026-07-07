Skulk.kBountyThreshold = kBountyClaimMinSkulk
Skulk.kKDRatioMaxDamageReduction = 0.66

Skulk.kAdrenalineEnergyRecuperationRate = 30

function Skulk:ModifyDamageTaken(damageTable, attacker, doer, damageType, hitPoint) -- dud
    local reduction = kSkulkDamageReduction[doer:GetClassName()]
    if reduction then
        damageTable.damage = damageTable.damage * reduction
        return
    end
end

function Skulk:GetExtraHealth(techLevel,extraPlayers,recentWins)
    return techLevel * kSkulkHealthPerBioMass 
            + Clamp((extraPlayers - recentWins * 2) * 1.5,-15,25)
end

local baseOnKill = Skulk.OnKill
function Skulk:OnKill(attacker,doer,point, direction)
    baseOnKill(self,attacker,doer,point, direction)

    -- OLD BEHAVIOR (kept for reference / toggle): once the Xenocide tech was
    -- unlocked, EVERY dying Skulk dropped an enzyme cloud.
    -- local xenocide = GetIsTechUnlocked(self,kTechId.Xenocide)
    -- if xenocide then
    --     CreateEntity(EnzymeCloud.kMapName, self:GetOrigin(), self:GetTeamNumber())
    -- end

    -- NEW BEHAVIOR: a Skulk that actually carries the Xenocide weapon explodes on
    -- death, so it should NOT also drop an enzyme cloud. Only spawn the enzyme
    -- cloud for Xenocide-teched Skulks that are NOT carrying the Xenocide weapon.
    local xenocide = GetIsTechUnlocked(self,kTechId.Xenocide)
    local hasXenocideWeapon = self:GetWeapon((XenocideLeap and XenocideLeap.kMapName) or "xenocide") ~= nil
    if xenocide and not hasXenocideWeapon then
        CreateEntity(EnzymeCloud.kMapName, self:GetOrigin(), self:GetTeamNumber())
    end

    --if not attacker or not attacker:isa("Player") then return end
    --if not HasMixin(attacker, "ParasiteAble") then return end
    --
    --local dist = (self:GetOrigin() - attacker:GetOrigin()):GetLength()
    --if dist > 5 then return end
    --attacker:SetParasited(self)
end

-- ── Leap impact damage ───────────────────────────────────────────────────────
-- Vanilla Leap (LeapMixin/Skulk:OnLeap) is a pure movement burst with no damage
-- of its own. This adds: 25 Normal damage to the first Marine-team "Live" entity
-- the Skulk impacts while leaping, gated by a forward-facing cone (a leap where
-- the Skulk's face points away from the target does not hit it), with only one
-- hit allowed per leap (cleared the next time the Skulk leaps again).
local kLeapImpactDamage   = 25
local kLeapImpactRange    = 1.8    -- slightly larger than Bite's own 1.42m range
local kLeapImpactConeDot  = 0.3    -- ~72.5° half-angle forward cone (dot product)

local baseSkulkOnLeap = Skulk.OnLeap
function Skulk:OnLeap()
    baseSkulkOnLeap(self)
    -- Fresh leap: allow exactly one impact hit until the next OnLeap() call.
    self._leapHasHit = false
end

-- Find the Skulk's currently-equipped Leap-capable weapon (Bite or, before it
-- detonates, Xenocide — both extend BiteLeap and carry LeapMixin) to use as the
-- DoDamage "doer", so the killfeed icon logic on that weapon class applies.
local function GetSkulkLeapWeapon(self)
    local weapons = self:GetWeapons()
    for i = 1, #weapons do
        if weapons[i]:isa("BiteLeap") then
            return weapons[i]
        end
    end
    return nil
end

-- Checked in PostUpdateMove (after this tick's movement is applied, not before)
-- so the impact check uses the Skulk's up-to-date position for this frame,
-- matching "impacts" rather than lagging a frame behind. Neither Skulk nor its
-- Alien base class define PostUpdateMove, so there is no base to preserve.
local baseSkulkPostUpdateMove = Skulk.PostUpdateMove
function Skulk:PostUpdateMove(input, runningPrediction)

    if baseSkulkPostUpdateMove then
        baseSkulkPostUpdateMove(self, input, runningPrediction)
    end

    if Server and self.leaping and not self._leapHasHit and self:GetIsAlive() then

        local origin  = self:GetOrigin()
        local forward = self:GetViewAngles():GetCoords().zAxis
        local nearby  = GetEntitiesWithMixinWithinRange("Live", origin, kLeapImpactRange)

        for _, target in ipairs(nearby) do

            if target ~= self and GetAreEnemies(self, target) and target:GetCanTakeDamage() then

                local targetOrigin = GetTargetOrigin(target)
                local toTarget = targetOrigin - origin
                if toTarget:GetLengthSquared() > 0.0001 then

                    toTarget:Normalize()
                    local dot = forward:DotProduct(toTarget)

                    -- Cone check: only hit targets roughly in front of the Skulk.
                    -- A leap where the Skulk's face points away from the target
                    -- (dot below the threshold, including anything behind it)
                    -- deals no damage.
                    if dot >= kLeapImpactConeDot then

                        self._leapHasHit = true

                        local weapon = GetSkulkLeapWeapon(self)
                        if weapon then
                            -- Flag the weapon so its GetDeathIconIndex override
                            -- (BiteLeap.lua / XenocideLeap.lua) reports the Leap
                            -- icon in the killfeed for this specific kill, then
                            -- clear it immediately — DoDamage/Kill/OnEntityKilled
                            -- all run synchronously within this call.
                            weapon._isLeapImpact = true
                            weapon:DoDamage(kLeapImpactDamage, target, targetOrigin, toTarget, "none")
                            weapon._isLeapImpact = false
                        end

                        -- Only one target hit per leap.
                        break

                    end

                end

            end

        end

    end

end