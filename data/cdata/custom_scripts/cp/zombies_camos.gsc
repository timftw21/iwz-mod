post_load()
{
    level thread initialize_zombies_camo_progression();
}

zombies_camo_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("ZombiesCamos", message);
}

initialize_zombies_camo_progression()
{
    level endon("game_ended");

    level thread monitor_zombies_camo_reset_requests();

    // post_load can run on either side of the first connected notification.
    // Attach to existing players first, then follow stock CP's join lifecycle.
    if (isdefined(level.players))
    {
        foreach (player in level.players)
            player thread monitor_m1_camo_headshots();
    }

    for (;;)
    {
        level waittill("connected", player);
        player thread monitor_m1_camo_headshots();
    }
}

get_current_m1_match_headshots()
{
    if (!isdefined(self.headshots) || !isdefined(self.headshots["iw7_m1c"]))
        return 0;

    return int(self.headshots["iw7_m1c"]);
}

monitor_m1_camo_headshots()
{
    self endon("disconnect");
    self endon("iwz_neon_rot_progress_reset");
    level endon("game_ended");

    if (isdefined(self.iwz_m1_camo_monitor_attached))
        return;

    self.iwz_m1_camo_monitor_attached = true;
    neon_rot_required_headshots = 5;
    // Neon Rot lives in IWZ-owned saved state. Borrowing a weapon analytics
    // bucket would either fail DDL validation or collide with real weapon data.
    neon_rot_stored_headshots = getdvarint("iwz_neon_rot_headshots", 0);
    match_headshots = self get_current_m1_match_headshots();

    neon_rot_camo_row = tablelookuprownum("mp/camotable.csv", 1, "camo253");
    neon_rot_menu_row = tablelookuprownum("mp/menucamos.csv", 0, "253");
    neon_rot_unlock_row = tablelookuprownum("mp/unlocks/camounlocks.csv", 0,
        "iw7_m1c+camo253");
    neon_rot_splash_row = tablelookuprownum("cp/zombies/zombie_splashtable.csv", 0,
        "iwz_camo_neon_rot_unlock");
    zombies_camo_log("runtime table audit player=" + self getentitynumber() +
        " neonRot=" + neon_rot_camo_row + "/" + neon_rot_menu_row + "/" +
        neon_rot_unlock_row + "/" + neon_rot_splash_row);

    zombies_camo_log("monitor attached player=" + self getentitynumber() +
        " weapon=M1 eventRef=iw7_m1c nativeMatch=" + match_headshots +
        " neonRot=iwz_neon_rot_headshots:" +
        neon_rot_stored_headshots + "/" + neon_rot_required_headshots);

    neon_rot_unlocked = neon_rot_stored_headshots >= neon_rot_required_headshots;
    if (neon_rot_unlocked)
    {
        zombies_camo_log("already unlocked player=" + self getentitynumber() +
            " camo=Neon_Rot progressSource=saved-dvar progressRef=iwz_neon_rot_headshots stored=" +
            neon_rot_stored_headshots);
        return;
    }

    last_match_headshots = match_headshots;
    for (;;)
    {
        // The fifth buffered kill argument is the weapon. Stock Zombies updates
        // the iw7_m1c headshot counter before dispatching this notification.
        self waittill("kill_event_buffered", victim, attacker, inflictor, means_of_death, weapon);
        base_weapon = scripts\cp\utility::getbaseweaponname(weapon);
        if (base_weapon != "iw7_m1c")
            continue;

        match_headshots = self get_current_m1_match_headshots();
        if (!isdefined(self.iwz_m1_camo_event_verified))
        {
            self.iwz_m1_camo_event_verified = true;
            zombies_camo_log("event verified player=" + self getentitynumber() +
                " weapon=" + weapon + " base=" + base_weapon +
                " nativeMatch=" + match_headshots);
        }

        if (match_headshots == last_match_headshots)
            continue;

        new_headshots = match_headshots - last_match_headshots;
        last_match_headshots = match_headshots;
        neon_rot_stored_headshots = neon_rot_stored_headshots + new_headshots;
        if (neon_rot_stored_headshots > neon_rot_required_headshots)
            neon_rot_stored_headshots = neon_rot_required_headshots;

        setdvar("iwz_neon_rot_headshots", neon_rot_stored_headshots);
        zombies_camo_log("progress player=" + self getentitynumber() +
            " weapon=M1 camo=Neon_Rot progressSource=saved-dvar" +
            " progressRef=iwz_neon_rot_headshots" +
            " nativeMatch=" + match_headshots + " stored=" + neon_rot_stored_headshots +
            "/" + neon_rot_required_headshots);

        if (neon_rot_stored_headshots >= neon_rot_required_headshots)
        {
            self unlock_neon_rot_camo(neon_rot_stored_headshots, match_headshots);
            return;
        }
    }
}

unlock_neon_rot_camo(stored_headshots, match_headshots)
{
    if (isdefined(self.iwz_neon_rot_camo_unlocked_this_match))
        return;

    self.iwz_neon_rot_camo_unlocked_this_match = true;
    splash_row = tablelookuprownum("cp/zombies/zombie_splashtable.csv", 0,
        "iwz_camo_neon_rot_unlock");
    zombies_camo_log("notification dispatch player=" + self getentitynumber() +
        " splashRow=" + splash_row + " ref=iwz_camo_neon_rot_unlock");
    self scripts\cp\cp_hud_message::showsplash("iwz_camo_neon_rot_unlock");
    zombies_camo_log("unlocked player=" + self getentitynumber() +
        " weapon=M1 camo=camo253 name=Neon_Rot progressSource=saved-dvar" +
        " progressRef=iwz_neon_rot_headshots stored=" +
        stored_headshots + " nativeMatch=" + match_headshots + " threshold=5" +
        " notification=film_local_player_splash_hex_icon");
}

monitor_zombies_camo_reset_requests()
{
    level endon("game_ended");

    for (;;)
    {
        reset_neon_rot = getdvarint("iwz_neon_rot_reset_requested", 0);
        if (!reset_neon_rot)
        {
            wait(0.1);
            continue;
        }

        setdvar("iwz_neon_rot_reset_requested", 0);
        if (!isdefined(level.players))
        {
            zombies_camo_log("in-game reset consumed players=0 camo=Neon_Rot target=0");
            wait(0.1);
            continue;
        }

        neon_rot_previous = getdvarint("iwz_neon_rot_headshots", 0);
        setdvar("iwz_neon_rot_headshots", 0);

        reset_players = 0;
        foreach (player in level.players)
        {
            player notify("iwz_neon_rot_progress_reset");
            player.iwz_m1_camo_monitor_attached = undefined;
            player.iwz_m1_camo_event_verified = undefined;
            player.iwz_neon_rot_camo_unlocked_this_match = undefined;
            zombies_camo_log("in-game reset player=" + player getentitynumber() +
                " camo=Neon_Rot progressSource=saved-dvar" +
                " progressRef=iwz_neon_rot_headshots previous=" +
                neon_rot_previous + " target=0");

            player thread monitor_m1_camo_headshots();
            reset_players++;
        }

        zombies_camo_log("in-game reset completed players=" + reset_players +
            " camo=Neon_Rot target=0");
        wait(0.1);
    }
}
