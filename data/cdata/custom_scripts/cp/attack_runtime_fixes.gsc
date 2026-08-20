main()
{
    if (getdvar("ui_mapname") != "cp_town")
        return;

    can_use_interaction = getfunction("scripts/cp/cp_interaction", "can_use_interaction");
    set_chemical = getfunction("scripts/cp/maps/cp_town/cp_town_chemistry", "set_chemical_carried_by_player");
    nuke_fx = getfunction("scripts/cp/loot", "nuke_fx");

    if (!isdefined(can_use_interaction) || !isdefined(set_chemical) ||
        !isdefined(nuke_fx))
    {
        attack_fix_log("installation failed: a required stock function was unavailable");
        return;
    }

    level.iwz_attack_set_chemical = set_chemical;
    replacefunc(can_use_interaction, ::can_use_interaction_stub);
    replacefunc(nuke_fx, ::nuke_fx_stub);
    attack_fix_log("installed airborne Alien Fuse use and off-grid nuke VFX patches; stock battery state preserved for UI filtering");
}

post_load()
{
    if (getdvar("ui_mapname") != "cp_town")
        return;

    level thread configure_attack_interaction_geometry();
    level thread listen_for_petn_command();
    attack_fix_log("started interaction-geometry and givePetn command listeners");
}

attack_fix_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("AttackFixes", message);
}

can_use_interaction_stub(interaction)
{
    if (!isdefined(interaction))
        return 0;

    if (scripts\engine\utility::is_true(self.iscarrying))
        return 0;

    if (scripts\engine\utility::is_true(interaction.disabled) ||
        !scripts\cp\utility::areinteractionsenabled() || self isinphase())
        return 0;

    if (self secondaryoffhandbuttonpressed() || self isthrowinggrenade() || self fragbuttonpressed())
        return 0;

    // Preserve the stock grounded requirement everywhere except the elevated
    // Alien Fuses, where jumping is the natural way to reach the authored prop.
    if (!self isonground() && interaction.script_noteworthy != "pap_fusebox")
        return 0;

    if (interaction.script_noteworthy == "game_race" &&
        distancesquared(self.origin, interaction.origin) > 576)
        return 0;

    if (interaction.script_noteworthy == "ritual_stone" &&
        scripts\engine\utility::is_true(self.rave_mode))
        return 0;

    return 1;
}

configure_attack_interaction_geometry()
{
    level endon("game_ended");
    scripts\engine\utility::flag_wait("interactions_initialized");

    // Elvira registers her interaction immediately after setting the shared
    // initialization flag, so allow that final registration to complete.
    wait(0.1);

    configure_alien_fuse_interactions();
    level thread monitor_elvira_mirror_interaction();
}

configure_alien_fuse_interactions()
{
    fuse_interactions = scripts\engine\utility::getstructarray("pap_fusebox", "script_noteworthy");
    fuse_models = getentarray("pap_fuses", "targetname");

    if (fuse_interactions.size == 0 || fuse_models.size == 0)
    {
        attack_fix_log("Alien Fuse geometry unavailable interactions=" + fuse_interactions.size +
            " models=" + fuse_models.size);
        return;
    }

    adjusted = 0;
    foreach (interaction in fuse_interactions)
    {
        closest_fuses = scripts\engine\utility::get_array_of_closest(interaction.origin, fuse_models, undefined, 2);
        if (closest_fuses.size == 0)
            continue;

        old_origin = interaction.origin;
        fuse_origin = closest_fuses[0].origin;
        if (closest_fuses.size > 1)
            fuse_origin = (closest_fuses[0].origin + closest_fuses[1].origin) * 0.5;

        // Keep the map-authored reachable height. Only correct the horizontal
        // position to the visible models and move it out through the cabinet
        // opening. Moving the use point to the model's elevated Z puts the native
        // interaction selection point inside the shelf and defeats jumping.
        outward = (old_origin[0] - fuse_origin[0], old_origin[1] - fuse_origin[1], 0);
        if (distancesquared((0, 0, 0), outward) > 0.01)
            outward = vectornormalize(outward) * 24;
        else
            outward = (0, 24, 0);

        interaction.origin = (fuse_origin[0] + outward[0],
            fuse_origin[1] + outward[1], old_origin[2]);
        interaction.custom_search_dist = 192;
        adjusted++;

        attack_fix_log("relocated Alien Fuse interaction old=" + old_origin +
            " modelCenter=" + fuse_origin + " new=" + interaction.origin +
            " searchDist=" + interaction.custom_search_dist);
    }

    attack_fix_log("Alien Fuse geometry configured interactions=" + adjusted +
        " models=" + fuse_models.size);
}

nuke_fx_stub(powerup, authored_anchors)
{
    if (!isdefined(authored_anchors))
        authored_anchors = [];

    local_anchors = [];
    valid_players = 0;
    off_grid_players = 0;
    fallback_players = 0;

    // Preserve the stock authored blast locations for players in the main map.
    // Attack's hidden Pack-a-Punch room is a separate off-grid space, so those
    // world-space effects cannot be seen there and must not be sent to it.
    foreach (anchor in authored_anchors)
    {
        if (!isdefined(anchor))
            continue;

        foreach (player in level.players)
        {
            if (!player scripts\cp\utility::is_valid_player() ||
                scripts\engine\utility::is_true(player.in_afterlife_arcade) ||
                scripts\engine\utility::is_true(player.is_off_grid))
                continue;

            playfxontagforclients(level._effect["big_explo"], anchor, "tag_origin", player);
        }

        scripts\engine\utility::waitframe();
    }

    foreach (player in level.players)
    {
        if (!player scripts\cp\utility::is_valid_player() ||
            scripts\engine\utility::is_true(player.in_afterlife_arcade))
            continue;

        valid_players++;
        needs_local_anchor = scripts\engine\utility::is_true(player.is_off_grid);
        if (needs_local_anchor)
            off_grid_players++;
        else if (!has_nearby_nuke_anchor(player, authored_anchors, 750))
            needs_local_anchor = 1;

        if (!needs_local_anchor)
            continue;

        view_angles = player getplayerangles();
        local_angles = (0, view_angles[1], 0);
        local_origin = player.origin + anglestoforward(local_angles) * 192 + (0, 0, 48);
        local_anchor = scripts\engine\utility::spawn_tag_origin(local_origin, local_angles);
        local_anchor show();
        local_anchor.iwz_nuke_player = player;
        local_anchors[local_anchors.size] = local_anchor;
        playfxontagforclients(level._effect["big_explo"], local_anchor, "tag_origin", player);
        fallback_players++;
    }

    attack_fix_log("nuke VFX dispatched authoredAnchors=" + authored_anchors.size +
        " validPlayers=" + valid_players + " localFallbacks=" + fallback_players +
        " offGridPlayers=" + off_grid_players);

    wait(5);

    foreach (anchor in authored_anchors)
    {
        if (!isdefined(anchor))
            continue;

        foreach (player in level.players)
        {
            if (isdefined(player))
                stopfxontagforclients(level._effect["big_explo"], anchor, "tag_origin", player);
        }

        anchor delete();
        scripts\engine\utility::waitframe();
    }

    foreach (local_anchor in local_anchors)
    {
        if (!isdefined(local_anchor))
            continue;

        if (isdefined(local_anchor.iwz_nuke_player))
            stopfxontagforclients(level._effect["big_explo"], local_anchor,
                "tag_origin", local_anchor.iwz_nuke_player);

        local_anchor delete();
    }
}

has_nearby_nuke_anchor(player, authored_anchors, max_distance)
{
    max_distance_squared = max_distance * max_distance;
    foreach (anchor in authored_anchors)
    {
        if (isdefined(anchor) &&
            distancesquared(player.origin, anchor.origin) <= max_distance_squared)
            return 1;
    }

    return 0;
}

monitor_elvira_mirror_interaction()
{
    level endon("game_ended");

    interaction_structs = scripts\engine\utility::getstructarray("elvira_talk", "script_noteworthy");
    while (interaction_structs.size == 0)
    {
        wait(0.1);
        interaction_structs = scripts\engine\utility::getstructarray("elvira_talk", "script_noteworthy");
    }

    interaction = interaction_structs[0];
    stock_origin = interaction.origin;
    stock_search_dist = undefined;
    if (isdefined(interaction.custom_search_dist))
        stock_search_dist = interaction.custom_search_dist;

    relocated = 0;
    for (;;)
    {
        mirror_models = getentarray("elvira_mirror", "targetname");
        mirror_picked_up = 0;
        if (isdefined(level.mirrors_picked_up) &&
            isdefined(level.mirrors_picked_up["elvira_mirror"]))
            mirror_picked_up = 1;

        mirror_pickup_active = 0;
        if (mirror_models.size > 0 && !mirror_picked_up)
        {
            if (isdefined(level.elvira_available_again) && gettime() < level.elvira_available_again)
                mirror_pickup_active = 1;
            else if (isdefined(level.elvira_ai))
                mirror_pickup_active = 1;
        }

        if (mirror_pickup_active && !relocated)
        {
            interaction.origin = mirror_models[0].origin;
            interaction.custom_search_dist = 140;
            relocated = 1;
            attack_fix_log("relocated couch mirror interaction old=" + stock_origin +
                " new=" + interaction.origin + " searchDist=" + interaction.custom_search_dist);
        }
        else if (relocated && !mirror_pickup_active)
        {
            interaction.origin = stock_origin;
            interaction.custom_search_dist = stock_search_dist;
            attack_fix_log("restored Elvira talk interaction after couch mirror pickup origin=" + stock_origin);
            return;
        }

        wait(0.1);
    }
}

listen_for_petn_command()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_give_petn", player);

        if (!isdefined(player) || !isdefined(level.iwz_attack_set_chemical) ||
            !isdefined(level.elements) || !isdefined(level.elements["petn"]))
        {
            attack_fix_log("givePetn rejected: player or chemistry state unavailable");
            continue;
        }

        [[level.iwz_attack_set_chemical]](player, "petn");
        attack_fix_log("givePetn awarded chemical=petn label=3,4-di-nitroxy-methyl-propane player=" +
            player getentitynumber());
    }
}
