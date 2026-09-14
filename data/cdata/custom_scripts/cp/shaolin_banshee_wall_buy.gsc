// IWZ-LOAD: map=cp_disco
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
    banshee_wall_buy_log("installed world-model preload and bench placement correction");
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
    }
    else
        banshee_wall_buy_log("world models resident before stock setup weapon=" + banshee_weapon +
            " streamMs=" + (gettime() - stream_started));

    [[stock_setup]]();
    place_banshee_display(banshee_weapon);
}

place_banshee_display(banshee_weapon)
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

        display = interaction.trigger;
        original_origin = display.origin;
        // Streaming does not correct the authored origin. Find the seat under
        // that origin, then keep the rolled model's lower bound above it.
        // Ignore the display itself and players when tracing the bench.
        trace = bullettrace(original_origin + (0, 0, 32), original_origin - (0, 0, 32), 0, display);
        model = getweaponmodel(banshee_weapon);
        forward = anglestoforward(display.angles);
        right = anglestoright(display.angles);
        up = anglestoup(display.angles);
        bottom = iwzgetmodelbottomoffset(model, (forward[2], -right[2], up[2]));
        if (!isdefined(bottom) || trace["fraction"] == 1 || trace["normal"][2] < 0.9)
        {
            banshee_wall_buy_log("placement skipped: no valid model bounds or bench surface model=" + model +
                " origin=" + original_origin + " trace=" + trace["position"]);
            return;
        }
        lift = trace["position"][2] + 0.1 - (original_origin[2] + bottom);
        if (lift > 0)
            display.origin = original_origin + (0, 0, lift);
        banshee_wall_buy_log("bench placement ent=" + (display getentitynumber()) +
            " model=" + model + " original=" + original_origin + " origin=" + display.origin +
            " angles=" + display.angles + " surface=" + trace["position"] +
            " bottomOffset=" + bottom + " requiredLift=" + lift);
        return;
    }

    banshee_wall_buy_log("stock setup completed but the Banshee interaction was unavailable");
}
