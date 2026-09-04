main()
{
    custom_scripts\cp\death_wish::precache_death_wish(1);
}

post_load()
{
    settings = spawnstruct();
    settings.map = "cp_rave";
    // CrosshairCoords 191400: requested dirt surface.
    settings.surface = (-5081.9, 4590.32, -129.811);
    settings.use_barrel = 1;
    settings.barrel_yaw = 258.297;
    settings.jar_yaw = 29.294;
    settings.sound_on = "zmb_superslasher_summon_activate";
    settings.sound_off = "zmb_superslasher_summon_deactivate";
    custom_scripts\cp\death_wish::start_death_wish(settings);
}
