post_load()
{
    level thread listen_for_pap_room_requests();
    pap_room_log("teleport listener installed map=" + getdvar("ui_mapname"));
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
