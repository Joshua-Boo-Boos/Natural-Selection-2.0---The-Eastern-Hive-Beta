local kAdditionalEffects =
{
    -- The stomach loop is /Devour/devour in sound/Devour.fev, shipped in this mod's sound folder. The game's own
    -- ns2plus.fev has no devour event, so the old ns2plus paths never played and logged Event not found.
    combat_devour_stomach_outside =
    {
        devourOutsideEffects =
        {
            {parented_sound = "sound/Devour.fev/Devour/devour_ambience", volume = 0.2, done = true},
        },
    },

    combat_devour_stomach_inside =
    {
        devourInsideEffects =
        {
            {private_sound = "sound/Devour.fev/Devour/devour_ambience", done = true},
        },
    },

    -- Triggered by Devour whenever a marine leaves the stomach; stops the looping sounds on the triggering entity.
    -- It was missing from this table, so those triggers did nothing.
    combat_stop_effects =
    {
        stopEffects =
        {
            {stop_effects = ""},
        },
    },
    
    combat_devour_eat = 
    {
        devourEatEffects = 
        {
            {sound = "sound/Devour.fev/Devour/devour_in"},
            {cinematic = "cinematics/alien/onos/devour_escape.cinematic", done = true},
        },
    },
    
    combat_devour_escape = 
    {
        devourEscapeEffects = 
        {
            {sound = "sound/Devour.fev/Devour/devour_out"},
            {cinematic = "cinematics/alien/onos/devour_escape.cinematic", done = true},
        },
    },
    
    volley_attack =
    {
        volleyHitSounds = 
        {
            {sound = "sound/NS2.fev/alien/skulk/parasite", done = true},
        },
    },

    draw = 
    {
		alienWeaponDrawSounds =
        {
			{player_sound = "sound/ns2plus.fev/abilities/fade/acid_rocket/deploy", classname = "AcidRocket", done = true},
        }
    },

    acidrocket_attack =
    {
        bilebombFireEffects = 
        {   
            {sound = "", silenceupgrade = true, done = true}, 
            {player_sound = "sound/ns2plus.fev/abilities/fade/acid_rocket/rocket_fire"},
        },
    },

    acidrocket_hit =
    {
        bilebombHitEffects = 
        {          
            {cinematic = "cinematics/alien/gorge/bilebomb_impact.cinematic"},
            {parented_sound = "sound/ns2plus.fev/abilities/fade/acid_rocket/rocket_hit", done = true},
        },
    },
}

GetEffectManager():AddEffectData("kAdditionalEffects", kAdditionalEffects)
