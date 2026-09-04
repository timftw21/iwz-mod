main()
{
    custom_scripts\cp\death_wish::precache_death_wish(0);
}

post_load()
{
    settings = spawnstruct();
    settings.map = "cp_zmb";
    // CrosshairCoords 78550 hit park_arcade_table_top_01, static model 1388.
    // Its surface supports the jar directly. Face the logged player position.
    settings.surface = (2314.22, -1400.7, 143.263);
    settings.use_barrel = 0;
    settings.jar_yaw = 179.832;
    // Spaceland's aliases use the same energy-ring samples as Rave's summons.
    settings.sound_on = "zmb_grey_energy_ring_activate";
    settings.sound_off = "zmb_grey_energy_ring_deactivate";
    custom_scripts\cp\death_wish::start_death_wish(settings);
}
