post_load()
{
    double_xp_log("post-load map=" + getdvar("ui_mapname") + " enabled=" + getdvarint("iwz_double_xp", 0));

    level thread monitor_double_xp_players();

    if (isdefined(level.players))
    {
        foreach (player in level.players)
            player thread apply_double_xp_setting();
    }
}

double_xp_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("DoubleXP", message);
}

monitor_double_xp_players()
{
    level endon("game_ended");
    double_xp_log("player monitor installed");

    for (;;)
    {
        level waittill("connected", player);
        player thread apply_double_xp_setting();
    }
}

apply_double_xp_setting()
{
    self endon("disconnect");
    level endon("game_ended");

    if (isdefined(self.iwz_double_xp_monitor))
        return;

    self.iwz_double_xp_monitor = true;

    // Stock Zombies assigns both scales in its connected listener. Waiting one
    // frame lets that listener finish and preserves any stock event/party scale.
    scripts\engine\utility::waitframe();

    if (!isdefined(self.xpscale))
        self.xpscale = getdvarint("online_zombies_xpscale", 1);

    if (!isdefined(self.weaponxpscale))
        self.weaponxpscale = getdvarint("online_zombie_weapon_xpscale", 1);

    base_level_scale = self.xpscale;
    base_weapon_scale = self.weaponxpscale;
    previous_enabled = -1;

    double_xp_log("captured base scales player=" + self getentitynumber() + " level=" + base_level_scale + " weapon=" + base_weapon_scale);

    for (;;)
    {
        enabled = getdvarint("iwz_double_xp", 0) != 0;

        if (enabled != previous_enabled)
        {
            multiplier = 1;

            if (enabled)
                multiplier = 2;

            self.xpscale = base_level_scale * multiplier;
            self.weaponxpscale = base_weapon_scale * multiplier;
            previous_enabled = enabled;

            double_xp_log("applied player=" + self getentitynumber() + " enabled=" + enabled + " levelScale=" + self.xpscale + " weaponScale=" + self.weaponxpscale);
        }

        wait(0.25);
    }
}
