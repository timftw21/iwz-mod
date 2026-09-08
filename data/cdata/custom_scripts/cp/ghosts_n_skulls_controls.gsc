post_load()
{
    // The listener is available for both the IWZ arcade launch and a Ghosts N
    // Skulls game entered from the stock maps. GSC performs the authoritative
    // active-game check so the native command cannot force unrelated endgames.
    level thread listen_for_gns_win_requests();
    arcade_log("winGNS listener installed map=" + level.script + " arcadeMode=" + getdvarint("iwz_gns_arcade", 0));

}

listen_for_gns_win_requests()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_gns_win", player);
        player force_gns_win();
    }
}

force_gns_win()
{
    if (!isdefined(self) || !isplayer(self))
    {
        arcade_log("winGNS rejected: invalid player");
        return;
    }

    if (!scripts\engine\utility::is_true(level.gns_active))
    {
        arcade_log("winGNS rejected: Ghosts N Skulls is not active playerEnt=" + (self getentitynumber()) + " map=" + level.script);
        self iprintlnbold("Ghosts N Skulls is not active");
        return;
    }

    if (scripts\engine\utility::is_true(level.processing_ghost_wave_failing))
    {
        arcade_log("winGNS rejected: failure cleanup already active playerEnt=" + (self getentitynumber()) + " map=" + level.script);
        self iprintlnbold("Ghosts N Skulls is already ending");
        return;
    }

    if (scripts\engine\utility::is_true(level.iwz_gns_win_pending))
    {
        arcade_log("winGNS ignored: victory sequence already pending playerEnt=" + (self getentitynumber()) + " map=" + level.script);
        return;
    }

    level.iwz_gns_win_pending = true;
    arcade_log("winGNS accepted: playerEnt=" + (self getentitynumber()) + " map=" + level.script + " arcadeMode=" + getdvarint("iwz_gns_arcade", 0) + " configuredWaves=" + level.gns_num_of_wave);
    self iprintlnbold("Ghosts N Skulls victory triggered");

    // Use the stock success entry point. It owns HUD teardown, score display,
    // player restoration, analytics, each map's reward callback, and gns_end_func.
    scripts\cp\maps\cp_zmb\cp_zmb_ghost_wave::game_won_sequence();
    level thread observe_forced_win_completion();
}

observe_forced_win_completion()
{
    level endon("game_ended");

    while (scripts\engine\utility::is_true(level.gns_active))
        scripts\engine\utility::waitframe();

    level.iwz_gns_win_pending = undefined;
    arcade_log("winGNS native completion observed map=" + level.script);
}

arcade_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("GhostsNSkullsArcade", message);
}
