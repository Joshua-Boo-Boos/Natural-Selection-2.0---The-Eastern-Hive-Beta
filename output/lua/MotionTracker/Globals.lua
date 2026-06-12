debug.appendtoenum(kPlayerStatus, "MotionTracker")
debug.appendtoenum(kDeathMessageIcon, "MotionTracker")
-- Registered the same way the BI9 pistol_mod does. The mod loads LAST (.entry
-- Priority 0), so this kDeathMessageIcon append comes after CNBalance's entries and
-- does not shift their atlas cells. NS2Utility.lua points the tracker's
-- inventory/death-atlas position at kDeathMessageIcon.MotionTracker (BI9 pattern).

-- Motion Tracker armory/buy-menu description. Both language variants live here;
-- GUIMarineBuyMenu.lua picks one based on the client's locale (zhCN -> Chinese).
kMotionTrackerArmoryDescription =
    "Detection device — no damage. Adv. Armory required.\n" ..
    "[Primary]: scan 15.5 m, 48 deg yaw-only arc.\n" ..
    "Pitch ignored — aliens above/below still detected.\n" ..
    "Sees through walls. Detects fully cloaked aliens.\n" ..
    "[Secondary]: toggle continuous scan on/off.\n" ..
    "Charge drains while scanning; refills at Armories.\n" ..
    "\n" ..
    "Screen: Distance (top), Charge % (bottom),\n" ..
    "LEFT: UP/EQUAL/DOWN — alien elevation,\n" ..
    "RIGHT: lifeform — SKULK, LERK, FADE, etc."

kMotionTrackerArmoryDescriptionCH =
    "探测装置——无伤害。需要高级军械库。\n" ..
    "[主键]：扫描15.5米，48度偏航弧。\n" ..
    "俯仰角忽略——上下方外星人仍可探测。\n" ..
    "可穿墙。可探测完全隐形的外星人。\n" ..
    "[副键]：切换持续扫描模式开/关。\n" ..
    "扫描消耗能量；军械库补充。\n" ..
    "\n" ..
    "屏幕：距离(上)，充能%(下)，\n" ..
    "左：UP/EQUAL/DOWN — 外星人高度，\n" ..
    "右：生命形态 — SKULK、LERK、FADE等。"