post_load()
{
    setdvar("iwz_zombies_remaining", -1);
    level thread monitor_remaining_zombies();
    custom_scripts\cp\gsc_diagnostics::emit("ZombieCounter", "scene counter started; source=required-deaths minus completed-deaths; includes pending spawns");
}

monitor_remaining_zombies()
{
    level endon("game_ended");
    last_wave = undefined;
    for (;;)
    {
        remaining = -1;
        // These are the same counters stock spawning uses to finish a scene.
        // Despawned enemies awaiting respawn have not contributed a death.
        if (isdefined(level.desired_enemy_deaths_this_wave) && isdefined(level.current_enemy_deaths))
            remaining = int(max(0, level.desired_enemy_deaths_this_wave - level.current_enemy_deaths));

        if (isdefined(level.players))
        {
            foreach (player in level.players)
            {
                if (!isdefined(player.iwz_zombies_remaining) || player.iwz_zombies_remaining != remaining)
                {
                    player setclientdvar("iwz_zombies_remaining", remaining);
                    player.iwz_zombies_remaining = remaining;
                }
            }
        }

        if (isdefined(level.wave_num) && (!isdefined(last_wave) || last_wave != level.wave_num))
        {
            last_wave = level.wave_num;
            custom_scripts\cp\gsc_diagnostics::emit("ZombieCounter", "scene=" + last_wave + " remaining=" + remaining);
        }
        wait(0.25);
    }
}
