
local GetPickupTextureCoordinates = debug.getupvaluex(GUIPickups.Update, "GetPickupTextureCoordinates")
local kPickupTypes = debug.getupvaluex(GetPickupTextureCoordinates, "kPickupTypes")
table.insert(kPickupTypes, "MotionTracker")
local kPickupTextureYOffsets = debug.getupvaluex(GetPickupTextureCoordinates, "kPickupTextureYOffsets")
kPickupTextureYOffsets["MotionTracker"] = 13