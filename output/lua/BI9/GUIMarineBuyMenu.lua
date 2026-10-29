--[[
    The BI9's Armory buy button.

    The BI9 is one of three free, permanent secondaries (Pistol, Revolver, BI9). The Armory offers the two you do not
    have (CNBalance/GUI/GUIMarineBuyMenu.lua, GetArmorySecondaryChoices): the first in the top-left group's secondary
    slot, the second as an extra button placed here - in the left extra-button column, in the first row the
    Primary extras (the BIHC) leave free, which the background already has room for.

    Like lua/BIHK/ and lua/BIHC/ this adds a kTechIdInfo entry (button image, big picture, description) and relies on
    lua/MotionTracker/GUIMarineBuyMenu.lua's extra-button machinery, which must not be replaced. Its itemType is
    "Secondary" and it is left out of MotionTracker's own extra-button pass, because the BI9 is not always offered:
    the extra secondary button can be the Pistol or the Revolver instead.
]]

if not kCombatVersion then

    local kTechIdInfo = debug.getupvaluex(GUIMarineBuyMenu._GetButtonPixelCoordinatesForTechID, "kTechIdInfo")

    table.insert(kTechIdInfo,
            kTechId.bi9,
            {
                ButtonTextureIndex = 0,
                BigPictureIndex = 0,
                Description = "The Brazier Industries 9. A fully automatic machine pistol, perfect for close quarters combat against all Kharaa threats.\n\nFree, permanent secondary weapon: replaces the Pistol or Revolver and is kept through death until you choose another secondary.\n33 rounds (32 in the magazine and 1 in the chamber), full auto.",
                ButtonPath = PrecacheAsset("ui/buymenu_marine/bi9_Button.dds"),
                ButtonPixelWidth = 880,     -- native size of bi9_Button.dds
                ButtonPixelHeight = 112,
                BigInfoPath = PrecacheAsset("ui/buymenu_marine/bi9_Bigicon.dds"),
                BigInfoWidth = 660,         -- native size of bi9_Bigicon.dds
                BigInfoHeight = 334,
                techItem = kTechId.bi9,
                itemType = "Secondary",
                Stats = {   LifeFormDamage = 0.35,
                            StructureDamage = 0.2,
                            Range = 0.6,
                }
            }
    )

    -- The BI9's button image is 880x112. Older MotionTracker versions (NS2.0-TEH Beta) crop every extra-button image
    -- to 80x80, so the BI9 sets its own size after MotionTracker's _CreateButton.
    local old__CreateButton = GUIMarineBuyMenu._CreateButton
    function GUIMarineBuyMenu:_CreateButton(parent, buttonPosition, buttonTechId)
        local data = old__CreateButton(self, parent, buttonPosition, buttonTechId)
        if data and data.Button and buttonTechId == kTechId.bi9 then
            local info = kTechIdInfo[kTechId.bi9]
            data.Button:SetTexturePixelCoordinates(0, 0, info.ButtonPixelWidth, info.ButtonPixelHeight)
        end
        return data
    end

    -- MotionTracker's layout, for the extra secondary button (see lua/MotionTracker/GUIMarineBuyMenu.lua).
    local kExtraButtonPositions = { Vector(4, 4, 0) }
    local kExtraButtonFrameW = 449
    local kExtraButtonFrameH = 122
    local kExtraColumnX = 105
    local kExtraFirstRowY = 780
    local kExtraRowHeight = 117

    -- How many Primary extra buttons (the BIHC) MotionTracker stacks in the left column, and how many rows the
    -- background was grown by (the taller of the two columns, at least one).
    local function GetExtraColumnUse()
        local utility, primary = 0, 0
        for _, info in pairs(kTechIdInfo) do
            if type(info) == "table" and info.techItem then
                if info.itemType == "Utility" then utility = utility + 1
                elseif info.itemType == "Primary" then primary = primary + 1 end
            end
        end
        return primary, math.max(1, utility, primary)
    end

    local oldCreateExtraButton = GUIMarineBuyMenu.CreateExtraButton
    if oldCreateExtraButton then

        function GUIMarineBuyMenu:CreateExtraButton()

            -- MotionTracker's pass makes a button for every kTechIdInfo entry with a techItem; leave the BI9 out of it.
            local bi9Info = kTechIdInfo[kTechId.bi9]
            kTechIdInfo[kTechId.bi9] = nil
            local ok, err = pcall(oldCreateExtraButton, self)
            kTechIdInfo[kTechId.bi9] = bi9Info
            if not ok then
                Shared.Message("[BI9] CreateExtraButton: " .. tostring(err))
            end

            local techId = self.extraSecondaryTech
            if not techId or not self.background then
                return
            end

            local primaryRows, rows = GetExtraColumnUse()
            local row = math.min(primaryRows, rows - 1)

            local frame = self:CreateAnimatedGraphicItem()
            frame:SetIsScaling(false)
            frame:SetPosition(Vector(kExtraColumnX, kExtraFirstRowY + kExtraRowHeight * row, 0))
            frame:SetTexture(GUIMarineBuyMenu.kButtonGroupFrame_Unlabeled_x2)
            frame:SetTexturePixelCoordinates(0, 0, kExtraButtonFrameW, kExtraButtonFrameH)
            frame:SetSize(Vector(kExtraButtonFrameW, kExtraButtonFrameH, 0))
            frame:SetOptionFlag(GUIItem.CorrectScaling)
            self.background:AddChild(frame)
            self:_InitializeWeaponGroup(frame, kExtraButtonPositions, { techId })

        end

    end

end
