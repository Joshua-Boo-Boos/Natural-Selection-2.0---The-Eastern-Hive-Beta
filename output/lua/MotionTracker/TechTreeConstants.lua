-- NS2.0-TEH root-cause fix (Motion Tracker showing the wrong tooltip/name):
--
-- These kTechId entries used to be registered with the mod's custom
-- EnumUtils.AppendToEnum, while CNBalance and every other NS2 mod (and the engine
-- convention) use debug.appendtoenum. The two appenders track the "next enum value"
-- differently (EnumUtils reads kTechId.Max, which debug.appendtoenum does not keep in
-- sync), so mixing them assigned a NUMERIC kTechId value to MotionTrackerTech that
-- collided with another, real tech. LookupTechData is keyed by that numeric id, so the
-- other tech's commander button resolved to MotionTrackerTech's TechData and displayed
-- its "Allows the Frontiersmen to purchase the Motion Tracker..." tooltip / name.
--
-- Using the same appender as everything else keeps every kTechId value unique.

local newTechIds = {
    "MotionTracker",
    "MotionTrackerTech",
    "DropMotionTracker",
}

for _, v in ipairs(newTechIds) do
    debug.appendtoenum(kTechId, v)
end
