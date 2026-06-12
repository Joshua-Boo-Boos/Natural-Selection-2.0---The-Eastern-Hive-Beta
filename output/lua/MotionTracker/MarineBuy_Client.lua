local oldMarineBuy_GetWeaponDescription = MarineBuy_GetWeaponDescription
function MarineBuy_GetWeaponDescription(techId)
    if techId ~= kTechId.MotionTracker then
        return oldMarineBuy_GetWeaponDescription(techId)
    end
    
    local description = ""

    local techTree = GetTechTree()
    local requires = techTree:GetRequiresText(techId)

    if requires ~= "" then
        description = string.format(Locale.ResolveString("Advanced Armoury Required!"), requires:lower(), description)
    end

    
    return description
    
end


local oldOnItemSelect = MarineBuy_OnItemSelect
function MarineBuy_OnItemSelect(techId)
	if techId ~= kTechId.MotionTracker then
		StartSoundEffect(kMarineBuyMenuSounds.SelectWeapon)
	end
    oldOnItemSelect(self, techId)
end

