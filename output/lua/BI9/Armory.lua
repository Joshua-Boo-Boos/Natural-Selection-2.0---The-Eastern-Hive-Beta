-- Sold where the Revolver is: every Armory, and the Advanced Armory (whose list does not include the basic one's).
local oldArmoryGetItemList = Armory.GetItemList
function Armory:GetItemList(forPlayer)
    local itemList = oldArmoryGetItemList(self, forPlayer)
    table.insert(itemList, kTechId.bi9)
    return itemList
end

local oldAdvancedArmoryGetItemList = AdvancedArmory.GetItemList
function AdvancedArmory:GetItemList(forPlayer)
    local itemList = oldAdvancedArmoryGetItemList(self, forPlayer)
    if self:GetTechId() == kTechId.AdvancedArmory then
        table.insert(itemList, kTechId.bi9)
    end
    return itemList
end
