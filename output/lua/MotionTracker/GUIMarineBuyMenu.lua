
if not kCombatVersion then

    local kArmoryBigPicturesTexture        = PrecacheAsset("ui/buymenu_marine/armory_bigicons.dds")

    -- Reuse the existing 2-slot unlabeled frame, cropped to just the top slot,
    -- so the Motion Tracker button gets the same dark background as other groups.
    -- kButtonGroupFrame_Unlabeled_x2 is 449x239; the first button starts at y=4
    -- and the second at y=122, so the top slot is 122px tall.
    local kExtraButtonPositions = { Vector(4, 4, 0) }
    local kExtraButtonFrameW    = 449
    local kExtraButtonFrameH    = 122

    local kTechIdInfo = debug.getupvaluex(GUIMarineBuyMenu._GetButtonPixelCoordinatesForTechID, "kTechIdInfo")

    function GUIMarineBuyMenu:CreateExtraButton()
        local paddingX = 105
        local buttonNumUtility = 0
        local buttonNumPrimary = 0
        local buttonHeight = 117
        for i, extraButtonsTechID in pairs(kTechIdInfo) do
            if extraButtonsTechID.techItem then
                local frame = self:CreateAnimatedGraphicItem()
                frame:SetIsScaling(false)
                if extraButtonsTechID.itemType == "Utility" then
                    frame:SetPosition(Vector(585, 780 + buttonHeight * buttonNumUtility, 0))
                    buttonNumUtility = buttonNumUtility + 1
                elseif extraButtonsTechID.itemType == "Primary" then
                    frame:SetPosition(Vector(paddingX, 780 + buttonHeight * buttonNumPrimary, 0))
                    buttonNumPrimary = buttonNumPrimary + 1
                end
                frame:SetTexture(GUIMarineBuyMenu.kButtonGroupFrame_Unlabeled_x2)
                frame:SetTexturePixelCoordinates(0, 0, kExtraButtonFrameW, kExtraButtonFrameH)
                frame:SetSize(Vector(kExtraButtonFrameW, kExtraButtonFrameH, 0))
                frame:SetOptionFlag(GUIItem.CorrectScaling)
                self.background:AddChild(frame)
                self:_InitializeWeaponGroup(frame, kExtraButtonPositions, {extraButtonsTechID.techItem})
            end
        end
    end



    local old__SetDetailsSectionTechId = GUIMarineBuyMenu._SetDetailsSectionTechId
    function GUIMarineBuyMenu:_SetDetailsSectionTechId(techId, techCost)
        local techIdBigPicture = kTechIdInfo[techId]

        if self.hostStructure:isa("PrototypeLab") then
            old__SetDetailsSectionTechId(self, techId, techCost)
        else
            if techIdBigPicture.techItem then
                -- Let the base lay out the panel first (it sizes bigPicture to the
                -- armory atlas cell), then swap in our standalone portrait and fit
                -- the WHOLE image to that panel width (preserving aspect) so it does
                -- not overflow the detail background.
                old__SetDetailsSectionTechId(self, techId, techCost)
                self.bigPicture:SetTexture(techIdBigPicture.BigInfoPath)
                local iw = techIdBigPicture.BigInfoWidth or self.bigPicture:GetSize().x
                local ih = techIdBigPicture.BigInfoHeight or self.bigPicture:GetSize().y
                local panelW = self.bigPicture:GetSize().x
                self.bigPicture:SetTexturePixelCoordinates(0, 0, iw, ih)
                self.bigPicture:SetSize(Vector(panelW, panelW * ih / iw, 0))
            else
                self.bigPicture:SetTexture(kArmoryBigPicturesTexture)
                old__SetDetailsSectionTechId(self, techId, techCost)
            end

        end
    end

    local old__CreateButton = GUIMarineBuyMenu._CreateButton
    function GUIMarineBuyMenu:_CreateButton(parent, buttonPosition, buttonTechId)
        local data = old__CreateButton(self, parent, buttonPosition, buttonTechId)
        local techButtonData = kTechIdInfo[buttonTechId]

        if techButtonData and techButtonData.techItem then
            data.Button:SetTexture(techButtonData.ButtonPath)
            data.Button:SetTexturePixelCoordinates(0, 0, 80, 80)
            data.Button:SetColor(kIconColors[kMarineTeamType])
        end
        return data
    end

    -- _UpdateRealTimeElements resets buttonItem color to white every frame.
    -- Re-apply the blue tint afterwards for the Motion Tracker.
    local old__UpdateRealTimeElements = GUIMarineBuyMenu._UpdateRealTimeElements
    function GUIMarineBuyMenu:_UpdateRealTimeElements(buttonTable, techId, techAvailable, currentMoney, techCost)
        old__UpdateRealTimeElements(self, buttonTable, techId, techAvailable, currentMoney, techCost)
        if techId == kTechId.MotionTracker and techAvailable then
            buttonTable.Button:SetColor(kIconColors[kMarineTeamType])
        end
    end


    function GUIMarineBuyMenu:SetHostStructure(hostStructure)

        assert(hostStructure)

        self.hostStructure = hostStructure

        if self.hostStructure:isa("Armory") then
            self:CreateArmoryUI()
            -- Enlarge ONLY the background panel image; all child items keep their
            -- original screen positions and sizes (SetSize, not SetScale).
            -- With hotspot (0.5,0.5), growing the size shifts the top-left corner;
            -- compensate by offsetting position so the left/top edges stay flush and
            -- the background expands right + downward to enclose the extra button row.
            if self.background and self.customScaleVector then
                local sz        = self.background:GetSize()
                local kBgScaleX = 1.0   -- no width change
                local kBgScaleY = 1.2   -- height +20% to enclose the extra button row
                local K         = self.customScaleVector.x
                self.background:SetSize(Vector(sz.x * kBgScaleX, sz.y * kBgScaleY, 0))
                -- Compensate hotspot shift so left/top edges stay flush.
                local dx = (kBgScaleX - 1.0) * 0.5 * sz.x * K   -- 0 when X unchanged
                local dy = (kBgScaleY - 1.0) * 0.5 * sz.y * K
                self.background:SetPosition(Vector(dx, dy, 0))
            end
            self:CreateExtraButton()
        elseif self.hostStructure:isa("PrototypeLab") then
            self:CreatePrototypeLabUI()
        else
            Log(string.format("ERROR: No generator found for class: %s", self.hostStructure:GetClassName()))
        end

        if hostStructure:isa("PrototypeLab") and self._InitializeExoModularButtons then
            self:_InitializeExoModularButtons()
            self:_RefreshExoModularButtons()
        end
    end

    local kTechIdInfo = debug.getupvaluex(GUIMarineBuyMenu._GetButtonPixelCoordinatesForTechID, "kTechIdInfo")

    local kMotionTrackerNewButtonImage =  PrecacheAsset("ui/motion_tracker/motion_tracker_Button.dds")
    local kMotionTrackerNewBigInfoImage = PrecacheAsset("ui/motion_tracker/motion_tracker_Bigicon.dds")

    -- Concise armory description, localised. Both strings are defined in
    -- lua/MotionTracker/Globals.lua; pick Chinese when the client locale is zhCN.
    local kMotionTrackerDescription = kMotionTrackerArmoryDescription
    if Client.GetOptionString("locale", "enUS") == "zhCN" then
        kMotionTrackerDescription = kMotionTrackerArmoryDescriptionCH
    end

    table.insert(kTechIdInfo,
            kTechId.MotionTracker,
            {
                ButtonTextureIndex = 0,
                BigPictureIndex = 0,
                Description = kMotionTrackerDescription,
                ButtonPath = kMotionTrackerNewButtonImage,
                BigInfoPath = kMotionTrackerNewBigInfoImage,
                BigInfoWidth = 660,   -- native size of motion_tracker_Bigicon.dds
                BigInfoHeight = 334,
                techItem = kTechId.MotionTracker,
                itemType = "Utility",
                -- No Stats table: this weapon deals no damage, so the damage/range
                -- bars are intentionally hidden (the description takes their place).
            }
    )

else
	local bigIconWidth = 400
	local bigIconHeight = 300   
	local smallIconHeight = 80
	local smallIconWidth = 80
	local MotionTrackerTexture = PrecacheAsset("ui/motion_tracker/motion_tracker_Button.dds")

    local kMotionTrackerNewBigInfoImage = PrecacheAsset("ui/motion_tracker/motion_tracker_Bigicon.dds")

	local old_InitializeItemButtons = GUIMarineBuyMenu._InitializeItemButtons
    function GUIMarineBuyMenu:_InitializeItemButtons()
        old_InitializeItemButtons(self)
        
        if self.itemButtons then
            for i, item in ipairs(self.itemButtons) do
                if item.TechId == kTechId.MotionTracker then
                    item.Button:SetTexture(MotionTrackerTexture)
                    item.Button:SetTexturePixelCoordinates(0, 0, smallIconWidth, smallIconHeight)
                end
            end
        end
    end
    
    local old_InitializeEquipped = GUIMarineBuyMenu._InitializeEquipped
    function GUIMarineBuyMenu:_InitializeEquipped()
        old_InitializeEquipped(self)
        
        if self.equipped then
            for i, item in ipairs(self.equipped) do
                if item.TechId == kTechId.MotionTracker then
                    item.Graphic:SetTexture(MotionTrackerTexture)
                    item.Graphic:SetTexturePixelCoordinates(0, 0, smallIconWidth, smallIconHeight)
                end
            end
        end
    end
    
    local old_UpdateContent = GUIMarineBuyMenu._UpdateContent
    function GUIMarineBuyMenu:_UpdateContent(deltaTime)
        old_UpdateContent(self, deltaTime)
        local techId = self.hoverItem
        if not self.hoverItem then
            techId = self.selectedItem
        end
        if techId ~= nil and techId ~= kTechId.None and self.portrait then
            if techId == kTechId.MotionTracker then
                self.portrait:SetTexture(kMotionTrackerNewBigInfoImage)
                self.portrait:SetTexturePixelCoordinates(0, 0, bigIconWidth, bigIconHeight)
            else
                self.portrait:SetTexture(GUIMarineBuyMenu.kBigIconTexture)
            end
        end
    end
end
