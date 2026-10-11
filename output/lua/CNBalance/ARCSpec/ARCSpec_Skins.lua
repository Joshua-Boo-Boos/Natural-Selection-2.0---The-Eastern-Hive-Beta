--[[
    ARC FACTORY SPECIALISATIONS - per-ARC skins.

    Loaded post lua/ARCVariantMixin.lua. Mixin functions are copied into the ARC class when the first ARC is created, so
    replacing ARCVariantMixin.OnUpdateRender here (at load) is what every ARC then uses.

    The skin follows each ARC's OWN tech id, which every client already has (no network variable):
      H.A.M.M.E.R.  Tundra   (models/marine/arc_spec/arc_hammer_tundra.material - the ARC texture recoloured in the
                              Tundra Exo's scheme: the Exo texture itself is laid out for the Exo model and cannot be used)
      V.A.T.        Chroma   (the game's own arc_chroma.material)
      H.E.L.L.      Forge    (models/marine/arc_spec/arc_hell_forge.material, recoloured in the Forge Exo's scheme)
      normal ARC    always the standard ARC skin - the commander's ARC cosmetic is ignored, so no normal ARC can be mistaken
                    for a specialised one (e.g. a Chroma cosmetic looked exactly like a V.A.T.)
]]

local kSkinMaterial =
{
    -- Normal ARCs always show the standard skin, whatever ARC cosmetic the commander has chosen: a Chroma cosmetic would
    -- otherwise make every normal ARC look exactly like a V.A.T. ("" = clear any override = the standard skin).
    [kTechId.ARC] = "",
    [kTechId.ARCSpecHammerARC] = PrecacheAsset("models/marine/arc_spec/arc_hammer_tundra.material"),
    [kTechId.ARCSpecVanguardARC] = PrecacheAsset("models/marine/arc/arc_chroma.material"),
    [kTechId.ARCSpecInfernoARC] = PrecacheAsset("models/marine/arc_spec/arc_hell_forge.material"),
}

if Client then

    local baseOnUpdateRender = ARCVariantMixin.OnUpdateRender

    function ARCVariantMixin:OnUpdateRender()

        local material = self.GetTechId and kSkinMaterial[self:GetTechId()] or nil

        if material == nil then
            -- A normal ARC. If it ever showed a specialised skin, let the team cosmetic be applied again.
            if self.arcSpecSkin ~= nil then
                self.arcSpecSkin = nil
                self.dirtySkinState = true
            end
            if baseOnUpdateRender then
                return baseOnUpdateRender(self)
            end
            return
        end

        if self.arcSpecSkin == material or not self:GetIsAlive() then
            return
        end

        local model = self:GetRenderModel()
        if model and model:GetReadyForOverrideMaterials() then

            if material == "" then
                model:ClearOverrideMaterials()
            else
                model:SetOverrideMaterial(0, material)
            end

            if self.SetHighlightNeedsUpdate then
                self:SetHighlightNeedsUpdate()
            end

            self.arcSpecSkin = material
            self.dirtySkinState = false

        end

    end

    -- A model change (or the cosmetic changing) re-applies the specialised skin next frame.
    local baseOnArcSkinChanged = ARCVariantMixin.OnArcSkinChanged
    function ARCVariantMixin:OnArcSkinChanged()
        self.arcSpecSkin = nil
        if baseOnArcSkinChanged then
            return baseOnArcSkinChanged(self)
        end
        self.dirtySkinState = true
        return true
    end

end
