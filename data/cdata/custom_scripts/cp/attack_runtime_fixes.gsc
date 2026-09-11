// IWZ-LOAD: map=cp_town
main()
{
    if (getdvar("ui_mapname") != "cp_town")
        return;

    can_use_interaction = getfunction("scripts/cp/cp_interaction", "can_use_interaction");
    set_chemical = getfunction("scripts/cp/maps/cp_town/cp_town_chemistry", "set_chemical_carried_by_player");
    nuke_fx = getfunction("scripts/cp/loot", "nuke_fx");
    nuke_fx_points = getfunction("scripts/cp/loot", "get_fx_points");
    ray_gun_terminal = getfunction("scripts/cp/maps/cp_town/cp_town_mpq", "ray_gun_terminal");
    exit_ray_gun_terminal = getfunction("scripts/cp/maps/cp_town/cp_town_mpq", "exit_enter_bomb_code");
    enter_detonate_bomb_sequence = getfunction("scripts/cp/maps/cp_town/cp_town_mpq", "enter_detonate_bomb_sequence");
    enter_bomb_code_internal = getfunction("scripts/cp/maps/cp_town/cp_town_mpq", "enter_bomb_code_internal");
    end_detonate_bomb = getfunction("scripts/cp/maps/cp_town/cp_town_mpq", "end_detonate_bomb");
    delay_enable_interaction = getfunction("scripts/cp/maps/cp_town/cp_town_mpq", "delay_enable_interaction");

    if (isdefined(can_use_interaction))
    {
        replacefunc(can_use_interaction, ::can_use_interaction_with_airborne_fuses);
        attack_fix_log("installed airborne Alien Fuse interaction exception target=pap_fusebox");
    }
    else
        attack_fix_log("Alien Fuse hook unavailable: can_use_interaction lookup failed");

    if (!isdefined(set_chemical) ||
        !isdefined(nuke_fx) || !isdefined(nuke_fx_points) || !isdefined(ray_gun_terminal) ||
        !isdefined(exit_ray_gun_terminal) ||
        !isdefined(enter_detonate_bomb_sequence) ||
        !isdefined(enter_bomb_code_internal) ||
        !isdefined(end_detonate_bomb) ||
        !isdefined(delay_enable_interaction))
    {
        attack_fix_log("installation failed: a required stock function was unavailable");
        return;
    }

    level.iwz_attack_set_chemical = set_chemical;
    level.iwz_attack_enter_detonate_bomb_sequence = enter_detonate_bomb_sequence;
    level.iwz_attack_enter_bomb_code_internal = enter_bomb_code_internal;
    level.iwz_attack_end_detonate_bomb = end_detonate_bomb;
    level.iwz_attack_delay_enable_interaction = delay_enable_interaction;
    replacefunc(nuke_fx, ::nuke_fx_stub);
    replacefunc(nuke_fx_points, ::get_attack_nuke_fx_points);
    replacefunc(ray_gun_terminal, ::ray_gun_terminal_with_targeting_protection);
    replacefunc(exit_ray_gun_terminal, ::exit_ray_gun_terminal_with_targeting_restore);
    attack_fix_log("installed scoped Attack interaction-use, view-linked nuke VFX with stock preparation timing, and ray-gun terminal targeting patches; stock battery state preserved for UI filtering");
}

post_load()
{
    if (getdvar("ui_mapname") != "cp_town")
        return;

    install_alien_fuse_interaction_focus();
    level thread configure_attack_interaction_geometry();
    level thread listen_for_petn_command();
    level thread listen_for_attack_computer_test_command();
    attack_fix_log("started interaction-geometry, givePetn, and testAttackComputer command listeners");
}

attack_fix_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("AttackFixes", message);
}

ray_gun_terminal_with_targeting_protection(interaction, player)
{
    player enable_attack_terminal_targeting_protection();

    // cp_town_mpq::ray_gun_terminal is only this two-call handoff in both GSC
    // dumps. Keep the stock terminal state machine intact after owning one
    // reference to the game's normal player-ignore API.
    [[level.iwz_attack_enter_detonate_bomb_sequence]](interaction, player);
    [[level.iwz_attack_enter_bomb_code_internal]](interaction, player);
}

exit_ray_gun_terminal_with_targeting_restore(interaction, player)
{
    // This is the one exit shared by successful entry, three wrong digits,
    // explicit UI cancellation, and the stock damage-cancel monitor.
    [[level.iwz_attack_end_detonate_bomb]](player);
    interaction.anchor delete();
    player.bomb_interaction_struct = undefined;
    thread [[level.iwz_attack_delay_enable_interaction]](interaction);
    interaction notify("stop_bomb_counter");

    player disable_attack_terminal_targeting_protection("terminal-exit");
}

enable_attack_terminal_targeting_protection()
{
    if (!isdefined(self) || !isplayer(self))
        return;

    if (scripts\engine\utility::is_true(self.iwz_attack_terminal_ignore_active))
    {
        attack_fix_log("ray-gun terminal targeting already disabled player=" +
            self getentitynumber());
        return;
    }

    // allow_player_ignore_me is reference-counted and is also used by stock
    // last-stand/coaster systems. Own exactly one reference for this terminal.
    self.iwz_attack_terminal_ignore_active = 1;
    self scripts\cp\utility::allow_player_ignore_me(1);
    attack_fix_log("ray-gun terminal targeting disabled player=" +
        self getentitynumber() + " ignoreEnabled=" +
        self scripts\cp\utility::isignoremeenabled());
}

disable_attack_terminal_targeting_protection(reason)
{
    if (!isdefined(self) || !isplayer(self) ||
        !scripts\engine\utility::is_true(self.iwz_attack_terminal_ignore_active))
    {
        return;
    }

    self.iwz_attack_terminal_ignore_active = undefined;
    self scripts\cp\utility::allow_player_ignore_me(0);
    attack_fix_log("ray-gun terminal targeting restored player=" +
        self getentitynumber() + " reason=" + reason + " ignoreEnabled=" +
        self scripts\cp\utility::isignoremeenabled());
}

can_use_interaction_with_airborne_fuses(interaction)
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
    airborne = !self isonground();
    if (airborne && interaction.script_noteworthy != "pap_fusebox")
        return 0;

    if (interaction.script_noteworthy == "game_race" &&
        distancesquared(self.origin, interaction.origin) > 576)
        return 0;

    if (interaction.script_noteworthy == "ritual_stone" &&
        scripts\engine\utility::is_true(self.rave_mode))
        return 0;

    if (airborne && !isdefined(self.iwz_attack_airborne_fuse_logged))
    {
        self.iwz_attack_airborne_fuse_logged = 1;
        attack_fix_log("airborne Alien Fuse interaction allowed player=" +
            (self getentitynumber()) + " origin=" + self.origin +
            " interactionOrigin=" + interaction.origin);
    }
    return 1;
}

install_alien_fuse_interaction_focus()
{
    if (!isdefined(level.interaction_trigger_properties_func))
    {
        attack_fix_log("Alien Fuse focus hook unavailable: map interaction properties missing");
        return;
    }

    level.iwz_attack_stock_interaction_trigger_properties = level.interaction_trigger_properties_func;
    level.interaction_trigger_properties_func = ::interaction_trigger_properties_with_accessible_fuses;
    attack_fix_log("installed Alien Fuse focus callback source=level.interaction_trigger_properties_func " +
        "selector=stock searchRange=stock triggerHeight=stock requireLookAt=0 useFov=360");
}

interaction_trigger_properties_with_accessible_fuses(trigger, interaction, offset)
{
    [[level.iwz_attack_stock_interaction_trigger_properties]](trigger, interaction, offset);
    if (!isdefined(interaction) || !isdefined(interaction.script_noteworthy) ||
        interaction.script_noteworthy != "pap_fusebox")
        return;

    // Match Beast's fuse trigger: the stock selector stays near the player's
    // feet, and set_interaction_point places the use trigger at eye height.
    // Aiming up at the wall box must not lose that trigger. Configure it here,
    // before it becomes usable, instead of moving it from a background loop.
    trigger usetriggerrequirelookat(0);
    trigger setusefov(360);
}

configure_attack_interaction_geometry()
{
    level endon("game_ended");
    scripts\engine\utility::flag_wait("interactions_initialized");

    // cp_interaction starts a background pass that drops every interaction
    // struct to the floor. Attack's stock update_struct_positions waits ten
    // seconds before repairing quest selectors for exactly that reason; run
    // our model-aligned corrections after the same pass has settled.
    wait(10.25);

    configure_bomb_part_interactions();
    level thread monitor_car_mirror_interaction();
    level thread monitor_elvira_mirror_interaction();
}

configure_bomb_part_interactions()
{
    part_interactions = scripts\engine\utility::getstructarray("bomb_teleporter_part", "script_noteworthy");
    adjusted = 0;

    foreach (interaction in part_interactions)
    {
        if (!isdefined(interaction.target))
            continue;

        part = getent(interaction.target, "targetname");
        if (!isdefined(part))
            continue;

        old_origin = interaction.origin;

        // cp_interaction drops every interaction struct to the floor during
        // startup. Put these small quest-part selectors back on their linked
        // visible models so the use trigger is not hidden below nearby terrain.
        interaction.origin = part.origin;
        interaction.custom_search_dist = 128;
        adjusted++;

        attack_fix_log("aligned bomb-part interaction target=" + interaction.target +
            " model=" + part.model + " old=" + old_origin + " new=" + interaction.origin +
            " searchDist=" + interaction.custom_search_dist);
    }

    if (isdefined(level.interactions) &&
        isdefined(level.interactions["bomb_teleporter_part"]))
    {
        // The stock projector-part callback silently rejects every stance but
        // prone. The selector is already a normal look-at use trigger, so keep
        // the quest behavior while removing that undocumented stance gate.
        level.interactions["bomb_teleporter_part"].activation_func = ::take_bomb_part_stub;
        attack_fix_log("removed prone-only gate from the projector bomb part");
    }
    else
        attack_fix_log("bomb-part callback unavailable during geometry setup");

    attack_fix_log("bomb-part geometry configured interactions=" + adjusted +
        " discovered=" + part_interactions.size);
}

take_bomb_part_stub(interaction, player)
{
    if (!isdefined(interaction) || !isdefined(player) || !isdefined(interaction.target))
        return;

    part = getent(interaction.target, "targetname");
    if (!isdefined(part))
        return;

    part_model = part.model;
    switch (part_model)
    {
        case "cp_town_teleporter_device_projector":
            scripts\cp\utility::set_quest_icon(16);
            break;
        case "cp_town_teleporter_device_pipes":
            scripts\cp\utility::set_quest_icon(17);
            break;
        default:
            scripts\cp\utility::set_quest_icon(18);
            break;
    }

    playfx(level._effect["generic_pickup"], part.origin);
    pickup_sound = "zmb_item_pickup";
    if (!soundexists(pickup_sound))
        pickup_sound = "part_pickup";

    if (soundexists(pickup_sound))
        player playlocalsound(pickup_sound);
    else
        attack_fix_log("bomb-part pickup sound unavailable aliases=zmb_item_pickup,part_pickup");

    level.teleporter_pieces_found++;
    scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
    part delete();

    attack_fix_log("collected bomb part target=" + interaction.target +
        " model=" + part_model + " player=" + player getentitynumber());
}

monitor_car_mirror_interaction()
{
    level endon("game_ended");

    mirror_interactions = scripts\engine\utility::getstructarray("mirror", "script_noteworthy");
    car_interaction = undefined;
    foreach (interaction in mirror_interactions)
    {
        if (isdefined(interaction.name) && interaction.name == "car_mirror")
        {
            car_interaction = interaction;
            break;
        }
    }

    if (!isdefined(car_interaction))
    {
        attack_fix_log("car-mirror interaction unavailable candidates=" + mirror_interactions.size);
        return;
    }

    while (!scripts\engine\utility::is_true(level.car_mirror_hit))
        wait(0.1);

    ground_mirror = getent("car_mirror_ground", "targetname");
    if (!isdefined(ground_mirror))
    {
        attack_fix_log("fallen car-mirror model unavailable after crowbar hit");
        return;
    }

    old_origin = car_interaction.origin;
    car_interaction.origin = ground_mirror.origin;
    car_interaction.custom_search_dist = 120;
    attack_fix_log("aligned fallen car-mirror interaction old=" + old_origin +
        " new=" + car_interaction.origin + " searchDist=" + car_interaction.custom_search_dist);

    while (!isdefined(level.mirrors_picked_up) ||
        !isdefined(level.mirrors_picked_up["car_mirror"]))
        wait(0.1);

    scripts\cp\cp_interaction::remove_from_current_interaction_list(car_interaction);
    attack_fix_log("removed collected car-mirror selector from the active interaction list");
}

get_attack_nuke_fx_points(powerup, key, field, max_points, range)
{
    // Preserve loot::get_fx_points' world selection. Its only stock caller is
    // kill_closest_enemies, which then waits one second before nuke_fx. Prepare
    // the view sources here too, so clients receive their models before FX.
    anchors = [];
    points = scripts\engine\utility::getstructarray(key, field);
    points[points.size] = powerup;
    foreach (point in points)
    {
        nearby = scripts\engine\utility::get_array_of_closest(
            point.origin, level.players, undefined, 1, range, 1);
        if (!nearby.size)
            continue;
        if (!isdefined(point.angles))
            point.angles = (0,0,0);
        anchor = scripts\engine\utility::spawn_tag_origin(point.origin, point.angles);
        anchor show();
        anchors[anchors.size] = anchor;
        if (isdefined(max_points) && anchors.size >= max_points)
            break;
    }
    anchors = sortbydistance(anchors, powerup.origin);
    world_count = anchors.size;
    effect_locations = scripts\engine\utility::getstructarray("effect_loc", "targetname");
    foreach (player in level.players)
    {
        if (!player scripts\cp\utility::is_valid_player() ||
            scripts\engine\utility::is_true(player.in_afterlife_arcade))
            continue;
        if (effect_locations.size && !scripts\engine\utility::is_true(player.is_off_grid))
            continue;
        if (!scripts\cp\utility::has_tag(player.model, "tag_eye"))
        {
            attack_fix_log("nuke view source unavailable player=" +
                (player getentitynumber()) + " reason=missing-tag_eye");
            continue;
        }

        // The old point was left 56 units in front of the player at detonation.
        // Moving/turning left it behind; the mist starts 1-2 seconds later.
        // Native bone linking follows movement and view
        // rotation on each client, without a server-side position polling loop.
        anchor = scripts\engine\utility::spawn_tag_origin(player geteye(), player getplayerangles());
        anchor linkto(player, "tag_eye", (56,0,0), (0,0,0));
        anchor show();
        anchor.iwz_nuke_view_source = 1;
        anchor.iwz_nuke_player = player;
        anchors[anchors.size] = anchor;
    }
    attack_fix_log("nuke sources prepared world=" + world_count +
        " viewLinked=" + (anchors.size - world_count) +
        " mapEffectLocations=" + effect_locations.size + " leadIn=stock-1s");
    return anchors;
}

nuke_fx_stub(powerup, anchors)
{
    if (!isdefined(anchors))
        anchors = [];
    world_count = 0;
    view_count = 0;
    foreach (anchor in anchors)
    {
        if (!isdefined(anchor))
            continue;
        if (isdefined(anchor.iwz_nuke_view_source))
        {
            player = anchor.iwz_nuke_player;
            if (!isdefined(player) || !player scripts\cp\utility::is_valid_player() ||
                scripts\engine\utility::is_true(player.in_afterlife_arcade))
                continue;
            playfxontagforclients(level._effect["big_explo"], anchor, "tag_origin", player);
            view_count++;
            attack_fix_log("nuke view blast player=" + (player getentitynumber()) +
                " anchor=" + (anchor getentitynumber()) + " origin=" + anchor.origin +
                " eye=" + (player geteye()) + " velocity=" + (player getvelocity()) +
                " source=linked-tag_eye offset=56");
        }
        else
        {
            foreach (player in level.players)
            {
                if (!player scripts\cp\utility::is_valid_player() ||
                    scripts\engine\utility::is_true(player.in_afterlife_arcade) ||
                    scripts\engine\utility::is_true(player.is_off_grid))
                    continue;
                playfxontagforclients(level._effect["big_explo"], anchor, "tag_origin", player);
            }
            world_count++;
            scripts\engine\utility::waitframe();
        }
    }
    attack_fix_log("nuke VFX dispatched world=" + world_count +
        " viewLinked=" + view_count + " lifetime=5s");
    wait(5);
    foreach (anchor in anchors)
    {
        if (!isdefined(anchor))
            continue;
        if (isdefined(anchor.iwz_nuke_view_source))
        {
            if (isdefined(anchor.iwz_nuke_player))
                stopfxontagforclients(level._effect["big_explo"], anchor,
                    "tag_origin", anchor.iwz_nuke_player);
        }
        else
        {
            foreach (player in level.players)
            {
                if (isdefined(player))
                    stopfxontagforclients(level._effect["big_explo"], anchor, "tag_origin", player);
            }
        }
        anchor delete();
        scripts\engine\utility::waitframe();
    }
    attack_fix_log("nuke VFX sources cleaned count=" + anchors.size);
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

listen_for_attack_computer_test_command()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_test_attack_computer", player);

        if (!isdefined(player) || !isplayer(player))
        {
            attack_fix_log("testAttackComputer rejected: player unavailable");
            continue;
        }

        if (scripts\engine\utility::is_true(player.iwz_attack_terminal_ignore_active) ||
            isdefined(player.bomb_interaction_struct))
        {
            attack_fix_log("testAttackComputer rejected: terminal already active player=" +
                player getentitynumber());
            player iprintlnbold("Attack computer is already active");
            continue;
        }

        // Retail ray_gun_init_func clears level.ray_gun_interaction_structs but
        // never appends to it; it decorates the live ray_gun_start structs in
        // place. Rediscover those exact structs instead of trusting the empty
        // tracking array.
        interaction_structs = scripts\engine\utility::getstructarray(
            "ray_gun_start", "script_noteworthy");
        if (!isdefined(interaction_structs) || interaction_structs.size == 0 ||
            !isdefined(level.liferaycode))
        {
            interaction_count = 0;
            if (isdefined(interaction_structs))
                interaction_count = interaction_structs.size;

            attack_fix_log("testAttackComputer rejected: stock terminal state unavailable interactions=" +
                interaction_count + " codeReady=" + isdefined(level.liferaycode));
            player iprintlnbold("Attack computer is not ready");
            continue;
        }

        interaction = scripts\engine\utility::getclosest(
            player.origin, interaction_structs);
        if (!isdefined(interaction) || !isdefined(interaction.bomb_counter) ||
            !isdefined(interaction.bomb_status))
        {
            attack_fix_log("testAttackComputer rejected: nearest terminal geometry unavailable player=" +
                player getentitynumber());
            player iprintlnbold("Attack computer geometry is not ready");
            continue;
        }

        attack_fix_log("testAttackComputer starting stock ray-gun terminal player=" +
            player getentitynumber() + " terminal=" + interaction.origin +
            " interactions=" + interaction_structs.size +
            " terminalUnlocked=" + isdefined(level.terminal_unlocked));
        ray_gun_terminal_with_targeting_protection(interaction, player);
        player iprintlnbold("Attack computer test started");
    }
}
