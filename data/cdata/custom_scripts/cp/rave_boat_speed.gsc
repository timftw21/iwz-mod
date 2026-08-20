main()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;

    boat_path_func = getfunction("scripts/cp/maps/cp_rave/cp_rave_boat", "packboat_path");
    boat_countdown_func = getfunction("scripts/cp/maps/cp_rave/cp_rave_boat", "packboat_countdown");
    setup_boat_sounds_func = getfunction("scripts/cp/maps/cp_rave/cp_rave_boat", "setup_boat_sounds");
    level.iwz_rave_boat_stop_and_drop_players = getfunction("scripts/cp/maps/cp_rave/cp_rave_boat", "stop_and_drop_players");
    level.iwz_rave_boat_stop_and_wait_for_use = getfunction("scripts/cp/maps/cp_rave/cp_rave_boat", "stop_and_wait_for_boat_use");

    if (!isdefined(boat_path_func) || !isdefined(boat_countdown_func) || !isdefined(setup_boat_sounds_func) ||
        !isdefined(level.iwz_rave_boat_stop_and_drop_players) || !isdefined(level.iwz_rave_boat_stop_and_wait_for_use))
    {
        boat_speed_log("installation failed: a stock Rave boat function was unavailable");
        return;
    }

    replacefunc(boat_path_func, ::packboat_path_boosted);
    replacefunc(boat_countdown_func, ::packboat_countdown_boosted);
    replacefunc(setup_boat_sounds_func, ::setup_boat_sounds_synchronized);
    boat_speed_log("installed map-safe Rave boat path, countdown, and audio replacements");
}

post_load()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;

    level thread install_rave_boat_speed();
}

boat_speed_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("RaveBoatSpeed", message);
}

install_rave_boat_speed()
{
    level endon("game_ended");

    while (!isdefined(level.boat_vehicle) || !isdefined(level.boat_start_node))
        scripts\engine\utility::waitframe();

    level.iwz_rave_boat_path_nodes = [];
    node = level.boat_start_node;
    path_node_count = 0;

    // Rave's looping boat path stores explicit speed values on selected nodes;
    // nodes without one inherit the preceding segment's speed.
    for (;;)
    {
        path_node_count++;

        path_node = spawnstruct();
        path_node.node = node;
        path_node.name = "unnamed";

        if (isdefined(node.targetname))
            path_node.name = node.targetname;

        level.iwz_rave_boat_path_nodes[level.iwz_rave_boat_path_nodes.size] = path_node;

        if (isdefined(node.speed))
            boat_speed_log("captured node=" + path_node.name + " stockUnits=" + node.speed + " boostedMph=" + node.speed * 4.0 / 17.6);

        if (!isdefined(node.target))
            break;

        node = getvehiclenode(node.target, "targetname");

        if (!isdefined(node) || node == level.boat_start_node || path_node_count >= 32)
            break;
    }

    if (level.iwz_rave_boat_path_nodes.size == 0)
    {
        boat_speed_log("installation failed: no path nodes found");
        return;
    }

    boat_speed_log("installed multiplier=4.0 pathNodes=" + path_node_count + " controller=vehicle_setspeedimmediate");
    level thread monitor_rave_boat_speed();
}

setup_boat_sounds_synchronized()
{
    if (!isdefined(level.boat_vehicle.sfx_front))
        level.boat_vehicle.sfx_front = spawn("script_model", level.boat_vehicle.origin);

    if (!isdefined(level.boat_vehicle.sfx_rear))
        level.boat_vehicle.sfx_rear = spawn("script_model", level.boat_vehicle.origin);

    wait(0.05);
    level.boat_vehicle.sfx_front linkto(level.boat_vehicle, "tag_body");
    level.boat_vehicle.sfx_rear linkto(level.boat_vehicle, "tag_motor");
    wait(0.05);
    level.boat_vehicle.sfx_front playsound("scn_boatride_startup");
    level.boat_vehicle.sfx_rear playsound("scn_boatride_startup_lsrs");

    mode = get_active_rave_boat_speed_mode();
    handoff_time = 5.15;

    if (mode == "boosted")
        handoff_time = 1.25;

    boat_speed_log("audio cue=startup mode=" + mode + " handoff=" + handoff_time);
    wait handoff_time;

    if (mode == "boosted")
        stop_rave_boat_scene_sounds("startup-to-moving");

    level.boat_vehicle thread boatride_sfx_synchronized();
}

boatride_sfx_synchronized()
{
    level endon("boatride_over");
    level endon("game_ended");

    mode = get_active_rave_boat_speed_mode();

    if (isdefined(level.boat_vehicle.sfx_front))
    {
        level.boat_vehicle.sfx_front playsoundonmovingent("scn_boatride_01");
        level.boat_vehicle.sfx_rear playsoundonmovingent("scn_boatride_01_lsrs");
        boat_speed_log("audio cue=scn_boatride_01 mode=" + mode);
    }

    path_node = getvehiclenode(level.boat_start_node.target, "targetname");

    for (;;)
    {
        path_node waittill("trigger");

        if (isdefined(path_node.name) && path_node.name == "rave_boat_sound_2")
        {
            if (mode == "boosted")
                stop_rave_boat_scene_sounds("moving-01-to-moving-02");

            if (isdefined(level.boat_vehicle.sfx_front))
            {
                level.boat_vehicle.sfx_front playsoundonmovingent("scn_boatride_02");
                level.boat_vehicle.sfx_rear playsoundonmovingent("scn_boatride_02_lsrs");
                boat_speed_log("audio cue=scn_boatride_02 mode=" + mode + " node=" + get_rave_boat_node_name(path_node));
            }
        }

        if (!isdefined(path_node.target))
            break;

        path_node = getvehiclenode(path_node.target, "targetname");
    }
}

stop_rave_boat_scene_sounds(context)
{
    stopped_emitters = 0;

    if (isdefined(level.boat_vehicle.sfx_front))
    {
        level.boat_vehicle.sfx_front stopsounds();
        stopped_emitters++;
    }

    if (isdefined(level.boat_vehicle.sfx_rear))
    {
        level.boat_vehicle.sfx_rear stopsounds();
        stopped_emitters++;
    }

    boat_speed_log("audio stopped obsolete cue context=" + context + " emitters=" + stopped_emitters);
}

packboat_path_boosted(boat_interaction)
{
    path_node = getvehiclenode(level.boat_start_node.target, "targetname");
    level thread apply_rave_boat_segment_speed(path_node, "path-start");

    for (;;)
    {
        path_node waittill("trigger");

        if (isdefined(path_node.script_noteworthy))
        {
            switch (path_node.script_noteworthy)
            {
                case "island_stop":
                    if (get_active_rave_boat_speed_mode() == "boosted")
                        stop_rave_boat_scene_sounds("moving-02-to-island-return");

                    [[level.iwz_rave_boat_stop_and_drop_players]]("island_dropoff_player");
                    break;

                case "pier_stop":
                    [[level.iwz_rave_boat_stop_and_wait_for_use]](boat_interaction);
                    break;

                default:
                    break;
            }
        }

        if (!isdefined(path_node.target))
            break;

        path_node = getvehiclenode(path_node.target, "targetname");
        apply_rave_boat_segment_speed(path_node, "node-transition");
    }
}

apply_rave_boat_segment_speed(path_node, context)
{
    // The initial call is threaded immediately before the stock startpath call.
    // One frame lets startpath establish its stock target before we override it.
    if (context == "path-start")
        scripts\engine\utility::waitframe();

    if (!isdefined(level.boat_vehicle) || get_rave_boat_linked_player_count() == 0)
        return;

    mode = get_active_rave_boat_speed_mode();

    if (mode != "boosted")
    {
        boat_speed_log("segment stock mode=" + mode + " node=" + get_rave_boat_node_name(path_node) + " context=" + context);
        return;
    }

    if (!isdefined(path_node) || !isdefined(path_node.speed))
    {
        boat_speed_log("segment boost skipped: missing node speed context=" + context);
        return;
    }

    // Vehicle path-node speed is exposed in inches/sec; vehicle_setspeed uses MPH.
    stock_speed_mph = path_node.speed / 17.6;
    boosted_speed_mph = stock_speed_mph * 4.0;

    // The long final approach uses a 2 MPH stock node. Give that one segment
    // a 12 MPH floor so the complete occupied trip stays comfortably sub-15s.
    if (isdefined(path_node.script_noteworthy) && path_node.script_noteworthy == "island_stop" && boosted_speed_mph < 12.0)
        boosted_speed_mph = 12.0;

    level.boat_vehicle vehicle_setspeedimmediate(boosted_speed_mph, 1, 1);
    boat_speed_log("segment boosted node=" + get_rave_boat_node_name(path_node) + " stockMph=" + stock_speed_mph + " boostedMph=" + boosted_speed_mph + " context=" + context);
}

packboat_countdown_boosted()
{
    mode = get_active_rave_boat_speed_mode();
    countdown_time = 5.0;
    flag_time = 1.0;

    if (mode == "boosted")
    {
        countdown_time = 1.25;
        flag_time = 0.25;
    }

    boat_speed_log("boarding countdown mode=" + mode + " wait=" + countdown_time);
    wait countdown_time;
    scripts\engine\utility::flag_set("packboat_started");
    wait flag_time;
    scripts\engine\utility::flag_clear("packboat_started");
    level.boat_countdown_started = undefined;
}

monitor_rave_boat_speed()
{
    level endon("game_ended");

    was_occupied = false;
    ride_mode = undefined;
    ride_start_time = 0;
    set_rave_boat_speed_mode(get_requested_rave_boat_speed_mode(), "initial-state");

    for (;;)
    {
        linked_player_count = get_rave_boat_linked_player_count();
        is_occupied = linked_player_count > 0;

        if (is_occupied && !was_occupied)
        {
            // Latch the mode for the whole occupied ride. Ghost-n-Skulls clears
            // its callback as soon as the step completes, which may be mid-route.
            ride_mode = get_requested_rave_boat_speed_mode();
            level.iwz_rave_boat_ride_mode = ride_mode;
            ride_start_time = gettime();
            set_rave_boat_speed_mode(ride_mode, "ride-start");
            boat_speed_log("ride started mode=" + ride_mode + " players=" + linked_player_count + " origin=" + level.boat_vehicle.origin);
        }
        else if (!is_occupied && was_occupied)
        {
            ride_duration = (gettime() - ride_start_time) / 1000.0;
            boat_speed_log("ride ended mode=" + ride_mode + " duration=" + ride_duration + " origin=" + level.boat_vehicle.origin);
            ride_mode = undefined;
            level.iwz_rave_boat_ride_mode = undefined;
            set_rave_boat_speed_mode(get_requested_rave_boat_speed_mode(), "ride-end");
        }
        else if (!is_occupied)
        {
            set_rave_boat_speed_mode(get_requested_rave_boat_speed_mode(), "idle-state-change");
        }

        was_occupied = is_occupied;
        scripts\engine\utility::waitframe();
    }
}

get_requested_rave_boat_speed_mode()
{
    // The Kevin Smith trip drives a synchronized boss-intro sequence.
    if (scripts\engine\utility::flag_exist("survivor_released") && scripts\engine\utility::flag("survivor_released"))
        return "kevin-smith";

    // Ghost-n-Skulls installs this callback while its boat-shooting step is active.
    if (isdefined(level.start_boat_ride_func))
        return "ghosts-n-skulls";

    return "boosted";
}

get_active_rave_boat_speed_mode()
{
    if (get_rave_boat_linked_player_count() > 0 && isdefined(level.iwz_rave_boat_ride_mode))
        return level.iwz_rave_boat_ride_mode;

    return get_requested_rave_boat_speed_mode();
}

set_rave_boat_speed_mode(mode, context)
{
    if (isdefined(level.iwz_rave_boat_speed_mode) && level.iwz_rave_boat_speed_mode == mode)
        return;

    level.iwz_rave_boat_speed_mode = mode;
    boat_speed_log("speed mode=" + mode + " context=" + context);
}

get_rave_boat_node_name(path_node)
{
    if (isdefined(path_node) && isdefined(path_node.targetname))
        return path_node.targetname;

    return "unnamed";
}

get_rave_boat_linked_player_count()
{
    if (!isdefined(level.boat_vehicle) || !isdefined(level.boat_vehicle.linked_players))
        return 0;

    return level.boat_vehicle.linked_players.size;
}
