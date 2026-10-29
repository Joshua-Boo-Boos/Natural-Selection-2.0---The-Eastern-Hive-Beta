-- Umbra reduces BI9 bullets like every other bullet weapon.
local kUmbraModifier = debug.getupvaluex(UmbraMixin.ModifyDamageTaken, "kUmbraModifier")
if kUmbraModifier then
    kUmbraModifier["bi9"] = kUmbraBulletModifier
end
