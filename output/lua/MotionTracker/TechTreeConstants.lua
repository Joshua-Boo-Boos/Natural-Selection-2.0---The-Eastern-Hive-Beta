if not EnumUtils then
    Script.Load("lua/MotionTracker/EnumUtils.lua")
end

local newTechIds = {
    "MotionTracker",
    "MotionTrackerTech",
    'DropMotionTracker',
}

for _,v in ipairs(newTechIds) do
    EnumUtils.AppendToEnum(kTechId, v)
end
