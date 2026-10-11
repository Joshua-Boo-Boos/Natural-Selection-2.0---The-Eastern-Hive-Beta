--[[
    ARCUS (ARC Upgrade System) - specialised ARC Factory skins.

    Loaded post lua/RoboticsFactory.lua (after the other ARCSpec RoboticsFactory hook). The skin follows the factory's own
    tech id, which every client already has (no network variable). Client only.

      Hammerworks Siege Foundry  Tundra  (rf_hammer_tundra.material)
      Vanguard Armour Works      Chroma  (rf_vanguard_chroma.material)
      Inferno Forge              Forge   (rf_inferno_forge.material)
    Each is the Robotics Factory texture recoloured in that skin's scheme. Any other Robotics Factory is left untouched.
]]

local kFactoryMaterial =
{
    [kTechId.ARCSpecHammerFactory] = PrecacheAsset("models/marine/arc_spec/rf_hammer_tundra.material"),
    [kTechId.ARCSpecVanguardFactory] = PrecacheAsset("models/marine/arc_spec/rf_vanguard_chroma.material"),
    [kTechId.ARCSpecInfernoFactory] = PrecacheAsset("models/marine/arc_spec/rf_inferno_forge.material"),
}

if Client then

    local baseOnUpdateRender = RoboticsFactory.OnUpdateRender

    function RoboticsFactory:OnUpdateRender()

        if baseOnUpdateRender then
            baseOnUpdateRender(self)
        end

        local material = kFactoryMaterial[self:GetTechId()]
        if self.arcSpecSkin == material then
            return
        end

        local model = self.GetRenderModel and self:GetRenderModel()
        if not model or not model:GetReadyForOverrideMaterials() then
            return
        end

        if material then
            model:SetOverrideMaterial(0, material)
        else
            model:ClearOverrideMaterials()
        end

        if self.SetHighlightNeedsUpdate then
            self:SetHighlightNeedsUpdate()
        end

        self.arcSpecSkin = material

    end

end
