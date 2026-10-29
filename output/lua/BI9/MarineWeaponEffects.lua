-- BI9 muzzle flash for everyone else: the vanilla pistol muzzle flash on the world model's "weapon_compensator"
-- attach point, once per bullet. The shooter's own copy is created in BI9.lua (PlayMuzzleEffect).
GetEffectManager():AddEffectData("BI9MuzzleEffects", {
    bi9_muzzle =
    {
        bi9MuzzleEffects =
        {
            {weapon_cinematic = "cinematics/marine/pistol/muzzle_flash.cinematic", attach_point = "weapon_compensator"},
        },
    },
})
