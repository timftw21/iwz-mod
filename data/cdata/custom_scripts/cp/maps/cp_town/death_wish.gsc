main()
{
    custom_scripts\cp\death_wish::precache_death_wish(0);
}

post_load()
{
    settings = spawnstruct();
    settings.map = "cp_town";
    // Revised second trace: the measured flat surface now supports the jar.
    settings.surface = (3123.71,2199.78,-45.2184);
    settings.use_barrel = 0;
    settings.jar_yaw = 224.1103;
    // Attack's violet-ray trap supplies the matching activation/shutdown pair.
    settings.sound_on = "town_xray_activate";
    settings.sound_off = "town_xray_deactivate";
    custom_scripts\cp\death_wish::start_death_wish(settings);
}
