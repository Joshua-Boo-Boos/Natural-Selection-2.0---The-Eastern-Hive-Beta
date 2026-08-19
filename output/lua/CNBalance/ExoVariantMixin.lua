-- Fix: vanilla GetWeaponLoadoutClass returns the LEFT slot weapon class name.
-- For Claw-left configs, "Claw" has no precached cosmetic material → crash.
-- Remap to the appropriate skin class based on the RIGHT arm weapon:
--   Claw + Minigun  → "Minigun"  (exosuit_cm textures)
--   Claw + anything → "Railgun"  (exosuit_cr textures)
--
-- ALSO fixes the dropped Exosuit case: vanilla's Exosuit branch only handles
-- "_mm.model"/"_rr.model" model suffixes and returns nil for everything else.
-- Now that dropped Exosuits use the correct per-chassis _cm/_cr models
-- (CNBalance/Exosuit.lua), that nil spams "ERROR: Exo with invalid weapon
-- class, skin update failure" every render frame (the skin state never
-- resolves, so it re-dirties forever). Map _cm/_cr here too, and never return
-- nil (a safe default keeps the skin pipeline happy - claw chassis are forced
-- to the default variant elsewhere, so the cosmetic-material branch that would
-- need an exact class match is skipped anyway).
if Client then
    local baseGetWeaponLoadoutClass = ExoVariantMixin.GetWeaponLoadoutClass
    function ExoVariantMixin:GetWeaponLoadoutClass()

        -- Dropped Exosuit / ReadyRoomExo: resolve directly from the model
        -- suffix (base only knows _mm/_rr).
        if self:isa("Exosuit") or self:isa("ReadyRoomExo") then
            local modelName = self:GetModelName()
            if modelName then
                if StringEndsWith(modelName, "_mm.model")
                or StringEndsWith(modelName, "_cm.model") then
                    return "Minigun"
                elseif StringEndsWith(modelName, "_rr.model")
                    or StringEndsWith(modelName, "_cr.model") then
                    return "Railgun"
                end
            end
            return "Railgun"   -- safe fallback, never nil
        end

        -- pcall: vanilla does wep:GetLeftSlotWeapon():GetClassName() with no nil check, so a
        -- half-built or mid-transition exo (arms not attached yet) throws rather than returning.
        local ok, cls = pcall(baseGetWeaponLoadoutClass, self)
        if not ok then
            cls = nil
        end

        if cls == "Claw" then
            local wep = self:GetActiveWeapon()
            if wep then
                local right = wep.GetRightSlotWeapon and wep:GetRightSlotWeapon()
                if right and right:GetClassName() == "Minigun" then
                    return "Minigun"
                end
            end
            return "Railgun"
        end

        -- NEVER return nil/false. Vanilla's live-exo branch ends in `return false` when the exo has
        -- no active weapon yet, and OnUpdateRender treats that as a failure WITHOUT clearing
        -- dirtySkinState... so it re-dirties and logs "Exo with invalid weapon class" every single
        -- render frame. That is the flood in the server log. The Exosuit branch above already used a
        -- safe default for exactly this reason; the live-exo path needs the same.
        if not cls then
            return "Railgun"
        end

        return cls
    end

    -- Safety net requested for claw combos: if the resolved loadout class has NO
    -- cosmetic material for the player's chosen skin, render the STANDARD skin
    -- instead of letting the base render assert on the missing material. With the
    -- claw->Minigun/Railgun remap above, every real exo skin resolves, so this only
    -- fires for a genuinely missing texture - exactly the "use the standard skin"
    -- fallback. Applies to both the view and world models (both go through the base).
    local baseOnUpdateRender = ExoVariantMixin.OnUpdateRender
    function ExoVariantMixin:OnUpdateRender()
        if self.dirtySkinState and self.exoVariant ~= nil and self.exoVariant ~= kDefaultExoVariant then
            local weaponClass = self.GetWeaponLoadoutClass and self:GetWeaponLoadoutClass()
            -- Probe for the material: GetPrecachedCosmeticMaterial asserts if the
            -- class/skin has none, so a failed pcall means "genuinely missing".
            local hasMat = weaponClass ~= nil
                and pcall(GetPrecachedCosmeticMaterial, weaponClass, self.exoVariant)
            if not hasMat then
                local saved = self.exoVariant
                self.exoVariant       = kDefaultExoVariant
                baseOnUpdateRender(self)
                self.exoVariant       = saved
                self.clientExoVariant = saved   -- settle skin state (avoid a re-dirty loop)
                return
            end
        end
        baseOnUpdateRender(self)
    end
end

function ExoVariantMixin:SetExoVariant(variant)
    self.exoVariant = self.GetExoVariantOverride and self:GetExoVariantOverride(variant) or variant
end

if Server then
    function ExoVariantMixin:OnClientUpdated(client, isPickup)
        Player.OnClientUpdated(self, client, isPickup)

        local data = client.variantData
        if data == nil or isPickup then
            return
        end

        if GetHasVariant(kExoVariantsData, data.exoVariant, client) or client:GetIsVirtual() then
            self.exoVariant = self.GetExoVariantOverride and self:GetExoVariantOverride(data.exoVariant) or data.exoVariant
            self.lastExoVariant = self.exoVariant
        else
            Log("ERROR: Client tried to request Exo variant they do not have yet")
        end
    end
end