main()
{
    custom_scripts\cp\death_wish::precache_death_wish(0);
}

post_load()
{
    settings = spawnstruct();
    settings.map = "cp_disco";
    // Sixth September 4 trace: the existing wooden surface supports the jar.
    settings.surface = (-2557.49, 2745.64, 276.273);
    settings.use_barrel = 0;
    settings.jar_yaw = 179.02;
    // Map-local on/off aliases used by cp_disco_interactions' electric trap.
    settings.sound_on = "disco_gen_electric_trap_power_up";
    settings.sound_off = "disco_gen_electric_trap_power_down";
    custom_scripts\cp\death_wish::start_death_wish(settings);
}
