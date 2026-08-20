main()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;

    level thread monitor_rave_power_activation();
    rave_power_sfx_log("installed activation listener alias=zm_generator_on");
}

rave_power_sfx_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("RavePowerSFX", message);
}

monitor_rave_power_activation()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("power_on_scriptable_and_light", power_regions, player);

        if (!isdefined(level.generators) || level.generators.size == 0)
        {
            rave_power_sfx_log("activation skipped: stock generator list unavailable regions=" + power_regions);
            continue;
        }

        generator = level.generators[0];
        sound_origin = generator.origin;

        if (isdefined(generator.handle))
            sound_origin = generator.handle.origin;

        playsoundatpos(sound_origin, "zm_generator_on");

        player_ent = -1;

        if (isdefined(player))
            player_ent = player getentitynumber();

        rave_power_sfx_log("played alias=zm_generator_on player=" + player_ent + " regions=" + power_regions + " origin=" + sound_origin);
    }
}
