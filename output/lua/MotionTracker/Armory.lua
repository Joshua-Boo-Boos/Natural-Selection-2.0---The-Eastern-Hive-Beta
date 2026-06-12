local oldArmoryGetItemList = Armory.GetItemList
function Armory:GetItemList(forPlayer)

    local itemList = oldArmoryGetItemList(self, forPlayer)

    table.insert(itemList, kTechId.MotionTracker)

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