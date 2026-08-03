-- ======= NS2.0-TEH-Beta: CNBalance/Mixin/RagdollMixin.lua =======
--
-- Post-hook on lua/RagdollMixin.lua.
--
-- PROBLEM: the Exo Flamethrower special arm is a Railgun-class entity running in
-- Flamethrower mode (weaponMode == kExoSpecialMode.Flamethrower).  The vanilla death
-- cinematics table (GeneralEffects.lua -> generalDeathCinematicEffects) matches the
-- gib / "explode" disintegration cinematics on `doer = "Railgun"`, so an alien killed
-- by an FT Exo arm wrongly disintegrates as though hit by an actual Railgun.
--
-- FIX: re-implement Server RagdollMixin:OnKill (verbatim vanilla) except that when the
-- killing doer is a Railgun in Flamethrower mode we feed a NON-"Railgun" classname
-- ("Flamethrower") into the "death" TriggerEffects filter.  That makes the railgun
-- explode entries fail to match, so the alien plays its normal death instead.  The
-- ragdoll/impulse behaviour is otherwise byte-for-byte the vanilla path.
--
-- (Only the effect-filter classname is changed; the entity's real GetClassName is
--  untouched, so scoring / kill attribution are unaffected.)

if Server then

    -- File-local in vanilla RagdollMixin.lua; not visible to a post-hook, so re-declared
    -- with the same math.
    local function GetDamageImpulse(doer, point)
        if doer and point then
            return GetNormalizedVector(doer:GetOrigin() - point) * 1.5 * 0.01
        end
        return nil
    end

    -- True when `doer` is an Exo special arm currently in Flamethrower mode.
    local function GetIsFlamethrowerDoer(doer)
        return doer ~= nil
            and doer.isa and doer:isa("Railgun")
            and doer.GetWeaponMode
            and kExoSpecialMode
            and doer:GetWeaponMode() == kExoSpecialMode.Flamethrower
    end

    function RagdollMixin:OnKill(attacker, doer, point, direction)

        if point then

            self.deathImpulse = GetDamageImpulse(doer, point)
            self.deathPoint = Vector(point)

            if doer then
                self.doerClassName = doer:GetClassName()
            end

        end

        local doerClassName

        if doer ~= nil then
            doerClassName = doer:GetClassName()
            -- FT Exo arm: don't let the "Railgun" gib/disintegration cinematic match.
            if GetIsFlamethrowerDoer(doer) then
                doerClassName = "Flamethrower"
            end
        end

        if not self.consumed then
            self:TriggerEffects("death", { classname = self:GetClassName(), effecthostcoords = Coords.GetTranslation(self:GetOrigin()), doer = doerClassName })
        end

        -- Server does not process any tags when the model is client side animated. assume death animation takes 0.5 seconds and switch then to ragdoll mode.
        if self.GetHasClientModel and self:GetHasClientModel() and (not HasMixin(self, "GhostStructure") or not self:GetIsGhostStructure()) then

            CreateRagdoll(self)
            self.ragdollCreated = true

        end

    end

end
