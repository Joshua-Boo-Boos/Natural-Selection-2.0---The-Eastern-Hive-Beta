-- Post hook on lua/GUIAlienHUD.lua. CNBalance (inside GUIAlienHUD) wraps the shared
-- GUIInventory:LocalAdjustSlot and resets every slot each frame. This hook runs after
-- that reset and re-applies the Motion Tracker icon. Signature matches the updated
-- 3-param MotionTracker_ApplyInventoryIcon(item, isActive, index).

if GUIInventory and not GUIInventory.kMotionTrackerAfterCNPatched then

    GUIInventory.kMotionTrackerAfterCNPatched = true

    local baseLocalAdjustSlot = GUIInventory.LocalAdjustSlot

    function GUIInventory:LocalAdjustSlot(index, hudSlot, techId, isActive, resetAnimations, alienStyle)

        baseLocalAdjustSlot(self, index, hudSlot, techId, isActive, resetAnimations, alienStyle)

        if techId == kTechId.MotionTracker and MotionTracker_ApplyInventoryIcon then
            MotionTracker_ApplyInventoryIcon(self.inventoryIcons[index], isActive, index)
        end

    end

end
