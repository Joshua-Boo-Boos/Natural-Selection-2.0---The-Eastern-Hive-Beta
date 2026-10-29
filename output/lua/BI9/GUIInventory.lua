--[[
    The BI9's icon in the weapon bar (bottom of the HUD), done the same way as lua/BIHK/GUIInventory.lua (see its notes):
    the slot is recognised by the weapon actually in it (isa("bi9")) as well as by the tech id, and the icon is set
    in LocalAdjustSlot AND again at the end of GUIInventory:Update, so no later LocalAdjustSlot wrapper paints over it.
]]

local kBI9Texture = PrecacheAsset("ui/inventory_icon_bi9.dds")

local function GetIsBI9Slot(hudSlot, techId)

    if techId ~= nil and rawget(kTechId, "bi9") and techId == kTechId.bi9 then
        return true
    end

    local player = Client.GetLocalPlayer()
    local weapon = player and hudSlot and player.GetWeaponInHUDSlot and player:GetWeaponInHUDSlot(hudSlot)
    return weapon ~= nil and weapon:isa("bi9")

end

local function ApplyBI9Icon(inventoryItem)
    if inventoryItem and inventoryItem.Graphic then
        inventoryItem.Graphic:SetTexture(kBI9Texture)
        inventoryItem.Graphic:SetTexturePixelCoordinates(0, 0, 128, 64)
    end
end

local oldLocalAdjust = GUIInventory.LocalAdjustSlot
function GUIInventory:LocalAdjustSlot(index, hudSlot, techId, isActive, resetAnimations, alienStyle)
    oldLocalAdjust(self, index, hudSlot, techId, isActive, resetAnimations, alienStyle)

    if GetIsBI9Slot(hudSlot, techId) then
        ApplyBI9Icon(self.inventoryIcons[index])
    end
end

local oldUpdate = GUIInventory.Update
function GUIInventory:Update(deltaTime, parameters)
    oldUpdate(self, deltaTime, parameters)

    local inventoryTechIds = parameters and parameters[2]
    if not inventoryTechIds or not self.inventoryIcons or GUIInventory.kInventoryMode == 1 then return end

    for index, inventoryItem in ipairs(inventoryTechIds) do
        if GetIsBI9Slot(inventoryItem.HUDSlot, inventoryItem.TechId) then
            ApplyBI9Icon(self.inventoryIcons[index])
        end
    end
end
