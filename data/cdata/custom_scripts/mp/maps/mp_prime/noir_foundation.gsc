// IWZ-LOAD: dvar=iwz_noir_foundation
// Opt-in movement restrictions and foundation measurements.

init()
{
    // Stock's empty extension point runs before it applies the live class.
    // This changes the match loadout, without writing the player's saved MP rig.
    replacefunc(scripts\mp\class::loadout_giveextraweapons, ::foundation_loadout);
}

foundation_loadout(loadout)
{
    loadout.loadoutarchetype = "archetype_assassin";
    loadout.loadoutsuper = "super_atomizer";
    loadout.loadoutrigtrait = "specialty_null";
    // Stock bots otherwise pick a random payload after this extension point.
    if (isbot(self))
    {
        self.loadoutsuper = loadout.loadoutsuper;
        self.loadoutrigtrait = loadout.loadoutrigtrait;
    }
    noir_log("live loadout forced player=" + self getentitynumber() + " rig=FTL payload=Eraser trait=none");
}

post_load()
{
    if (!getdvarint("iwz_noir_foundation", 0))
        return;

    noir_log("foundation enabled; FTL / Eraser and zombie combat in the MP runtime");
    level thread audit_navigation();
    level thread watch_connections();
}

noir_log(message)
{
    level notify("iwz_gsc_log", "[IWZ][Noir] " + gettime() + " " + message);
}

audit_navigation()
{
    level endon("game_ended");
    setdvar("iwz_noir_nav_available", 0);
    setdvar("iwz_noir_audit_requested", 1);
    deadline = gettime() + 15000;
    while (getdvarint("iwz_noir_audit_requested") && gettime() < deadline)
        wait 0.1;

    if (getdvarint("iwz_noir_audit_requested"))
    {
        setdvar("iwz_noir_audit_requested", 0);
        noir_log("asset audit timed out; restart using the matching iw7-mod.exe");
        return;
    }

    noir_log("engine agent capacity=" + getmaxagents());
    if (!getdvarint("iwz_noir_nav_available"))
    {
        noir_log("no ground navigation resource reported; point queries skipped");
        return;
    }

    // These are authored Noir TDM spawn origins from the exported spawnList.
    // Nearest-point queries check registration only, not routes or zombie access.
    sample_navigation("authored_allies_start_0", (832, -2264, 40));
    sample_navigation("authored_allies_start_1", (880, -2344, 40));
    sample_navigation("authored_axis_start", (498, 3816, 144));
    sample_navigation("authored_upper_spawn", (124, 3680, 160));
}

sample_navigation(label, origin)
{
    point = getclosestpointonnavmesh(origin);
    if (!isdefined(point))
    {
        noir_log("nav sample=" + label + " origin=" + origin + " nearest=undefined");
        return;
    }
    noir_log("nav sample=" + label + " origin=" + origin + " nearest=" + point +
        " distance=" + distance(origin, point));
}

watch_connections()
{
    level endon("game_ended");
    if (isdefined(level.players))
    {
        foreach (player in level.players)
            player attach_probe();
    }
    for (;;)
    {
        level waittill("connected", player);
        player attach_probe();
    }
}

attach_probe()
{
    if (isdefined(self.iwz_noir_probe_attached))
        return;
    self.iwz_noir_probe_attached = 1;
    self thread watch_spawns();
}

watch_spawns()
{
    self endon("disconnect");
    level endon("game_ended");
    if (isalive(self))
        self thread probe_life();
    for (;;)
    {
        self waittill("spawned_player");
        self thread probe_life();
    }
}

probe_life()
{
    self notify("iwz_noir_new_life");
    self endon("iwz_noir_new_life");
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");
    wait 0.05;
    if (!getdvarint("iwz_noir_foundation", 0))
        return;

    self allowdoublejump(0);
    self allowwallrun(0);
    self allowdodge(0);
    rig = "undefined";
    payload = "undefined";
    if (isdefined(self.loadoutarchetype))
        rig = self.loadoutarchetype;
    if (isdefined(self.loadoutsuper))
        payload = self.loadoutsuper;
    noir_log("player=" + self getentitynumber() + " rig=" + rig + " payload=" + payload +
        " doubleJump=disabled wallRun=disabled dodge=disabled");
    if (rig != "archetype_assassin" || payload != "super_atomizer")
        noir_log("ERROR live loadout did not retain FTL / Eraser");
    else
        self iprintlnbold("FTL / Eraser foundation test: advanced movement disabled");

    last_sample = self.origin + (0, 0, 10000);
    // Keep manual corner/stair measurements bounded; a restart starts a fresh run.
    for (sample = 0; sample < 60 && getdvarint("iwz_noir_foundation", 0); sample++)
    {
        if (getdvarint("iwz_noir_nav_available") && distance(self.origin, last_sample) >= 128)
        {
            sample_navigation("player_" + self getentitynumber(), self.origin);
            last_sample = self.origin;
        }
        wait 2;
    }
}
