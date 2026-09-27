local kAdditionalEffects =
{
    -- The stomach loop's FMOD event is /abilities/alien/onos/devour (see sound/ns2plus.soundinfo). The old path
    -- "abilities/onos/devour" (no "alien") named no event, so neither loop ever played.
    combat_devour_stomach_outside =
    {
        devourOutsideEffects =
        {
            {parented_sound = "sound/ns2plus.fev/abilities/alien/onos/devour", volume = 0.2, done = true},
        },
    },

    combat_devour_stomach_inside =
    {
        devourInsideEffects =
        {
            {private_sound = "sound/ns2plus.fev/abilities/alien/onos/devour", done = true},
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
            {sound = "sound/ns2plus.fev/common/alien/devour_in"},
            {cinematic = "cinematics/alien/onos/devour_escape.cinematic", done = true},
        },
    },
    
    combat_devour_escape = 
    {
        devourEscapeEffects = 
        {
            {sound = "sound/ns2plus.fev/common/alien/devour_out"},
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
