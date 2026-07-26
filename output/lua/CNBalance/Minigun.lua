-- CNBalance/Minigun.lua
-- Post-hook on lua/Weapons/Marine/Minigun.lua.
--
-- FIX: Minigun permanently stuck overheated on CLAW exo layouts (Minigun + Claw).
--
-- ROOT CAUSE
-- ----------
-- Vanilla sets self.overheated = true when heatAmount reaches 1 (UpdateOverheated), and clears it
-- in EXACTLY ONE place - Minigun:OnTag, when the VIEW model's animation graph emits the
-- "left_overheat_end" / "right_overheat_end" tag:
--
--     if self:GetIsLeftSlot()  and tagName == "left_overheat_end" or
--        self:GetIsRightSlot() and tagName == "right_overheat_end" then
--         self.overheated = false
--     end
--
-- That tag only exists in the DUAL-MINIGUN view graph. Checking the shipped assets:
--
--     exosuit_mm_view.animation_graph  ->  left_overheat_end + right_overheat_end  PRESENT
--     exosuit_cm_view.animation_graph  ->  NO overheat_end tags at all
--
-- So on a Minigun + Claw exo (chassis "cm") the tag is NEVER emitted, Minigun:OnTag never runs
-- that branch, and self.overheated stays true FOREVER. Minigun:OnPrimaryAttack is gated on
-- `not self.overheated`, so the gun can never fire again. The only way out was leaving and
-- re-entering the exo, which builds a fresh Minigun entity (OnCreate sets overheated = false).
-- Dual Minigun (chassis "mm") is unaffected because its graph does emit the tag.
--
-- THE FIX
-- -------
-- Stop depending on an animation tag that some graphs simply do not contain, and drive the
-- recovery off the weapon's ACTUAL HEAT STATE instead - which is what "overheated" means.
--
-- This reproduces vanilla's timing exactly rather than inventing a new one. While overheated the
-- player cannot shoot, so ProcessMoveOnWeapon subtracts kCoolDownRate every tick. Vanilla's
-- overheat animation runs kOverheatDuration seconds, so vanilla effectively clears the flag at:
--
--     heat = 1.0 - kOverheatDuration * kCoolDownRate  =  1.0 - 2.0 * 0.4  =  0.2
--
-- We clear at that same heat level. On "mm" the animation tag still fires at that same moment
-- (clearing an already-cleared flag is a no-op), so dual-minigun behaviour is byte-for-byte
-- unchanged; on "cm" the weapon now recovers correctly instead of locking up forever.

if Server then

    -- The heat level at which vanilla's overheat animation would have ended.
    local kOverheatClearHeat = math.max(0,
        1.0 - (Minigun.kOverheatDuration or 2.0) * (Minigun.kCoolDownRate or 0.4))

    local baseMinigunProcessMoveOnWeapon = Minigun.ProcessMoveOnWeapon

    function Minigun:ProcessMoveOnWeapon(player, input)

        baseMinigunProcessMoveOnWeapon(self, player, input)

        -- Recover from overheat once the weapon has actually cooled to the vanilla clear point.
        -- (UpdateOverheated only re-arms at heatAmount == 1, so clearing here cannot immediately
        -- re-lock the weapon.)
        if self.overheated and (self.heatAmount or 0) <= kOverheatClearHeat then
            self.overheated = false
        end

    end

end
