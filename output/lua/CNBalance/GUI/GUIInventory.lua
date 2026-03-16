local oldLocalAdjust = GUIInventory.LocalAdjustSlot

local kCombatInjectorTexture = PrecacheAsset("ui/inventory_icon_combat_injector.dds")

function GUIInventory:LocalAdjustSlot(index, hudSlot, techId, isActive, resetAnimations, alienStyle)
	oldLocalAdjust(self, index, hudSlot, techId, isActive, resetAnimations, alienStyle)

	if techId == kTechId.CombatInjector then
		local inventoryItem = self.inventoryIcons[index]
		inventoryItem.Graphic:SetTexture(kCombatInjectorTexture)
		inventoryItem.Graphic:SetTexturePixelCoordinates(0,0,128,64)
	end
end
