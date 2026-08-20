main()
{
    if (getdvar("ui_mapname") != "cp_disco")
        return;

    stock_setup = getfunction("scripts/cp/zombies/coop_wall_buys", "_id_23DA");
    if (!isdefined(stock_setup))
    {
        banshee_wall_buy_log("installation failed: stock wall-buy setup was unavailable");
        return;
    }

    level.iwz_shaolin_stock_wall_buy_setup = stock_setup;
    replacefunc(stock_setup, ::wall_buy_setup_with_banshee_preload);
    banshee_wall_buy_log("installed pre-spawn world-model streaming hook");
}

banshee_wall_buy_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("ShaolinBanshee", message);
}

wall_buy_setup_with_banshee_preload()
{
    level endon("game_ended");

    stock_setup = level.iwz_shaolin_stock_wall_buy_setup;

    // This setup runs once per level. Restore the stock entry before waiting so
    // the original function can be invoked after the Banshee world DObj is ready.
    replacefunc(stock_setup, stock_setup);

    // cp_disco's authored wall display is always this Banshee world build. Load
    // it before the stock setup reaches its first-player wait and creates the
    // static script_weapon DObj.
    banshee_weapon = "iw7_sonic_zmr+sonicrscope_camo";
    stream_started = gettime();
    loadworldweapons([banshee_weapon]);
    banshee_wall_buy_log("requested pre-spawn world models weapon=" + banshee_weapon);

    stream_deadline = stream_started + 10000;
    while (!areworldweaponsloaded([banshee_weapon]) && gettime() < stream_deadline)
        wait(0.05);

    if (!areworldweaponsloaded([banshee_weapon]))
    {
        banshee_wall_buy_log("preload timed out weapon=" + banshee_weapon + "; continuing stock setup");
        [[stock_setup]]();
        return;
    }

    banshee_wall_buy_log("world models resident before stock setup weapon=" + banshee_weapon +
        " streamMs=" + (gettime() - stream_started));

    [[stock_setup]]();
    log_spawned_banshee_display(banshee_weapon);
}

log_spawned_banshee_display(banshee_weapon)
{
    interactions = scripts\engine\utility::getstructarray("interaction", "targetname");
    foreach (interaction in interactions)
    {
        if (!isdefined(interaction.script_noteworthy) || interaction.script_noteworthy != "iw7_sonic_zmr")
            continue;

        if (!isdefined(interaction.trigger))
        {
            banshee_wall_buy_log("stock setup completed without a Banshee display trigger");
            return;
        }

        banshee_wall_buy_log("stock display spawned after streaming ent=" + (interaction.trigger getentitynumber()) +
            " weapon=" + banshee_weapon + " origin=" + interaction.trigger.origin +
            " angles=" + interaction.trigger.angles);
        return;
    }

    banshee_wall_buy_log("stock setup completed but the Banshee interaction was unavailable");
}
