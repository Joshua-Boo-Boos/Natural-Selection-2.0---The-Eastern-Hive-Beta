-- Adds the "Com Eng" tab to Options -> Mods, containing a single checkbox that turns the Combat
-- Engineers sound cues on or off. Default ON.
--
-- Post-hooked onto lua/menu2/NavBar/Screens/Options/Mods/ModsMenuData.lua, which is the file that
-- vanilla explicitly invites mods to extend ("Modders: post-hook this file and add to the list").
-- gModsCategories and ModsMenuUtils both exist by then.
--
-- The preference is CLIENT side, but most CE sounds are played from the SERVER via
-- Server.PlayPrivateSound - a client cannot simply decline those. So every change is forwarded to
-- the server (CESoundPref), which records it per player and skips that player when broadcasting.
-- See CombatEngineers_SoundPref.lua for both halves of that.

local menu =
{
    categoryName = "com_eng",
    entryConfig =
    {
        name = "comEngModEntry",
        class = GUIMenuCategoryDisplayBoxEntry,
        params =
        {
            label = "COM ENG",
        },
    },
    contentsConfig = ModsMenuUtils.CreateBasicModsMenuContents
    {
        layoutName = "comEngOptions",
        contents =
        {
            {
                name = "comEngPlaySounds",
                class = OP_Checkbox,
                params =
                {
                    useResetButton = true,
                    -- Literal, NOT the kCombatEngineersSoundOptionPath global. This file is hooked
                    -- on a menu2 file while that constant is defined in a hook on lua/TechData.lua,
                    -- and the relative order of two unrelated hook targets is not guaranteed - a nil
                    -- optionPath here would silently break the checkbox. Must stay identical to the
                    -- value in CombatEngineers_SoundPref.lua.
                    optionPath = "CombatEngineers/PlaySounds",
                    optionType = "bool",
                    default = true,

                    -- Fires the moment the box is ticked, so the setting takes effect without
                    -- needing a reconnect.
                    immediateUpdate = function(self)
                        if CombatEngineers_SendSoundPref then
                            CombatEngineers_SendSoundPref(self:GetValue() == true)
                        end
                    end,
                },

                properties =
                {
                    -- LITERAL, not Locale.ResolveString. This file is hooked on a menu2 file while the
                    -- mod's locale tables are populated from a hook on lua/TechData.lua, and the menu
                    -- is built before those entries exist. The `or` fallback that used to be here
                    -- never fired, because Locale.ResolveString returns the KEY itself when a string
                    -- is missing - which is truthy - so the button simply displayed
                    -- "CE OPTION PLAY SOUNDS". CommNom's tab uses a literal for the same reason.
                    { "Label", "Combat Engineers Related Sounds" },
                },
            },
        },
    }
}

table.insert(gModsCategories, menu)
