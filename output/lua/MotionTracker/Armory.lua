local oldArmoryGetItemList = Armory.GetItemList
function Armory:GetItemList(forPlayer)

    local itemList = oldArmoryGetItemList(self, forPlayer)

    -- Advanced Armory ONLY. The tech tree already makes AdvancedArmory the prerequisite for buying a
    -- Motion Tracker (MarineTeam.lua: AddTargetedBuyNode(kTechId.MotionTracker, kTechId.AdvancedArmory,
    -- ...)), but this list previously offered it at a basic Armory too -- so the structure advertised
    -- something the tech gate would refuse. Gating on tech id here matches how vanilla's own
    -- Armory:GetItemList separates the basic and advanced weapon sets.
    if self:GetTechId() == kTechId.AdvancedArmory then
        table.insert(itemList, kTechId.MotionTracker)
    end

    return itemList

end

local oldAdvancedArmoryGetItemList = AdvancedArmory.GetItemList
function AdvancedArmory:GetItemList(forPlayer)

    local itemList = oldAdvancedArmoryGetItemList(self, forPlayer)

	if self:GetTechId() == kTechId.AdvancedArmory then
        table.insert(itemList, kTechId.MotionTracker)
    end

	return itemList

end