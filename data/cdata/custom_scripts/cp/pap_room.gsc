post_load()
{
    setup_pap_timer_housing();
    level thread listen_for_pap_room_requests();
    pap_room_log("teleport listener installed map=" + getdvar("ui_mapname"));
}

setup_pap_timer_housing()
{
    map_name = getdvar("ui_mapname");
    if (map_name == "cp_zmb")
    {
        pap_timer_log("native housing retained map=" + map_name);
        return;
    }

    if (map_name != "cp_rave" && map_name != "cp_disco" &&
        map_name != "cp_town" && map_name != "cp_final")
    {
        pap_timer_log("housing skipped unsupported map=" + map_name);
        return;
    }

    model_name = "iwz_pap_timer_housing";
    precachemodel(model_name);

    origin = (-10142, 929.5, -1544);
    if (map_name == "cp_final")
    {
        // The Beast from Beyond moves the stock LUI root. Preserve the same
        // (0, 2.5, 6) housing offset measured in Spaceland.
        origin = (5237.5, -5002.1, 370);
    }

    level.iwz_pap_timer_housing = spawn("script_model", origin);
    level.iwz_pap_timer_housing setmodel(model_name);
    level.iwz_pap_timer_housing.angles = (0, 0, 0);

    pap_timer_log("housing spawned map=" + map_name +
        " ent=" + level.iwz_pap_timer_housing getentitynumber() +
        " model=" + model_name + " origin=" + origin);
}

pap_timer_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("PaPTimer", message);
}

pap_room_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("PaPRoom", message);
}

listen_for_pap_room_requests()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_paproom", player);
        player teleport_to_pap_room();
    }
}

teleport_to_pap_room()
{
    if (!isdefined(self) || !isplayer(self))
    {
        pap_room_log("teleport rejected: invalid player");
        return;
    }

    destination = scripts\engine\utility::getstruct("hidden_room_spot", "targetname");
    source_name = "hidden_room_spot";

    if (!isdefined(destination))
    {
        destinations = scripts\engine\utility::getstructarray("pap_spawners", "targetname");
        if (isdefined(destinations) && destinations.size)
        {
            destination = destinations[0];
            source_name = "pap_spawners[0]";
        }
    }

    if (!isdefined(destination))
    {
        destination = scripts\engine\utility::getstruct("hidden_room_portal", "targetname");
        source_name = "hidden_room_portal";
    }

    if (!isdefined(destination))
    {
        pap_room_log("teleport failed player=" + self getentitynumber() + " destination unavailable");
        self iprintlnbold("Pack-a-Punch room destination unavailable");
        return;
    }

    self setorigin(destination.origin + (0, 0, 8));
    self setplayerangles(destination.angles);
    self setclientomnvar("zombie_papTimer", 30);

    pap_room_log("teleported player=" + self getentitynumber() +
        " source=" + source_name + " origin=" + self.origin + " angles=" + self.angles);
    self iprintlnbold("Teleported to Pack-a-Punch room");
}
