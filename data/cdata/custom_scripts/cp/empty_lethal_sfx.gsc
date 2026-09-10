main()
{
    precachesound("purchase_deny");
}

post_load()
{
    level thread monitor_players();
    lethal_sfx_log("installed empty_offhand listener slot=primary alias=purchase_deny");
}

lethal_sfx_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("EmptyLethalSFX", message);
}

monitor_players()
{
    level endon("game_ended");

    if (isdefined(level.players))
    {
        foreach (player in level.players)
            player thread monitor_empty_lethal();
    }

    for (;;)
    {
        level waittill("connected", player);
        player thread monitor_empty_lethal();
    }
}

monitor_empty_lethal()
{
    self endon("disconnect");
    level endon("game_ended");

    if (isdefined(self.iwz_empty_lethal_sfx_monitor))
        return;

    self.iwz_empty_lethal_sfx_monitor = true;

    for (;;)
    {
        // Use the engine's rejected-use event, so throwing the last grenade
        // cannot produce an empty-equipment cue when its charge is consumed.
        self waittill("empty_offhand");

        if (!self fragbuttonpressed() || !isalive(self) ||
            scripts\engine\utility::is_true(self.inlaststand) ||
            !scripts\engine\utility::isoffhandweaponsallowed() ||
            !scripts\engine\utility::isoffhandprimaryweaponsallowed() ||
            has_primary_charges())
        {
            continue;
        }

        self playlocalsound("purchase_deny");
        lethal_sfx_log("played player=" + self getentitynumber() +
            " alias=purchase_deny");

        // Ignore repeated empty events while the same press is held.
        while (self fragbuttonpressed())
            scripts\engine\utility::waitframe();
    }
}

has_primary_charges()
{
    if (!isdefined(self.powers) || !isdefined(level.powers))
        return false;

    foreach (power_name in getarraykeys(level.powers))
    {
        if (!isdefined(self.powers[power_name]))
            continue;

        power = self.powers[power_name];
        // The event is shared with tactical equipment. A simultaneous
        // tactical attempt must not report an empty lethal that has charges.
        if (isdefined(power.slot) && power.slot == "primary" &&
            isdefined(power.charges) && power.charges > 0)
        {
            return true;
        }
    }

    return false;
}
