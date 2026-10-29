-- Adds the "NS2.0-TEH" tab to Options -> Mods (Siege2.0-TEH / Defense2.0-TEH in those mods), containing the "Guide"
-- keybind (default 0) that opens the guide window (CNBalance/GUI/GUITEHGuide.lua) and the "Show Guide Upon Join"
-- switch (default on). The option path is a literal and must match the "TEHGuide" binding registered in
-- CNBalance/TEHGuide_Bindings.lua.
--
-- Post-hooked onto lua/menu2/NavBar/Screens/Options/Mods/ModsMenuData.lua, the file vanilla invites mods to extend.
local menu =
{
    categoryName = "ns2_teh",
    entryConfig =
    {
        name = "ns2TehModEntry",
        class = GUIMenuCategoryDisplayBoxEntry,
        params =
        {
            label = "NS2.0-TEH",
        },
    },
    contentsConfig = ModsMenuUtils.CreateBasicModsMenuContents
    {
        layoutName = "ns2TehOptions",
        contents =
        {
            {
                name = "ns2TehGuideKey",
                class = OP_Keybind,
                params =
                {
                    optionPath = "input/TEHGuide",
                    optionType = "string",
                    default = "0",

                    bindGroup = "general",
                },
                properties =
                {
                    { "Label", "Guide" },
                },
            },
            {
                -- ON (default): the guide opens by itself every time you join one of our servers. OFF: it only opens
                -- with the Guide key, !guide or the guide console command. Must match kShowOnJoinOption in
                -- CNBalance/TEHGuide_Client.lua.
                name = "ns2TehGuideShowOnJoin",
                class = OP_Checkbox,
                params =
                {
                    useResetButton = true,
                    optionPath = "TEHGuide/ShowOnJoin",
                    optionType = "bool",
                    default = true,
                },
                properties =
                {
                    { "Label", "Show Guide Upon Join" },
                },
            },
        },
    }
}
table.insert(gModsCategories, menu)
