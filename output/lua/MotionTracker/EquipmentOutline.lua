local origUpdateModel = EquipmentOutline_UpdateModel()
function EquipmentOutline_UpdateModel(forEntity)
	if weaponclass == 'MotionTracker' then
		weaponclass = 'Pistol'
	end

	return origUpdateModel(forEntity)
end
