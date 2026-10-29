-- Register the "TEHGuide" binding with the vanilla bindings system (same approach as CommNom). Default "0" - NS2 names
-- the main-row number keys "0".."9". Changed in Options -> Mods -> NS2.0-TEH -> Guide.
local defaults = debug.getupvaluex(GetDefaultInputValue, "defaults")
table.insert(defaults, { "TEHGuide", "0" })

local bindings = BindingsUI_GetBindingsData()
for i, v in ipairs {
    "TEHGuide", "input", "Open the NS2.0-TEH Guide", "0",
} do
    table.insert(bindings, i, v)
end
