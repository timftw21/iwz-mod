post_load()
{
    if (!getdvarint("iwz_gns_arcade", 0))
        return;

    selection = getdvarint("iwz_gns_arcade_game", 0);
    expected_map = get_expected_map(selection);

    if (!isdefined(expected_map))
    {
        arcade_log("launch rejected: invalid selection=" + selection);
        return;
    }

    if (level.script != expected_map)
    {
        arcade_log("launch rejected: selection=" + selection + " expectedMap=" + expected_map + " actualMap=" + level.script);
        return;
    }

    level.iwz_gns_arcade_selection = selection;

    // Stock uses this runtime state for all direct-challenge presentation:
    // character intro music, normal Scene announcements, and endgame splashes.
    // post_load runs after direct_boss_fight::init(), so activating it here does
    // not start the stock Boss Battle staging setup alongside this mode.
    previous_direct_challenge_state = scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight();
    level.direct_to_boss_fight = 1;

    level.disable_start_spawn_on_navmesh = 1;
    level.getspawnpoint = ::get_arcade_staging_spawn_point;
    level.disableplayerdamage = 1;
    level.disable_consumables = 1;
    level.introscreen_text_func = ::arcade_introscreen_text;
    level.zombies_paused = 1;
    setnojiptime(1);
    setnojipscore(1);

    arcade_log("launch armed: selection=" + selection + " game='" + get_arcade_game_name(selection) + "' map=" + level.script + " staging=afterlife");
    arcade_log("direct challenge state activated post-load: previous=" + previous_direct_challenge_state + " introMusicSuppressed=1 scenePresentationSuppressed=1");
    level thread hold_normal_waves();
    level thread scripts\cp\zombies\direct_boss_fight::disable_things_in_afterlife_arcade();
    level thread launch_arcade_game();
}

get_arcade_staging_spawn_point()
{
    player = self;
    spawn_points = scripts\engine\utility::getstructarray("afterlife_arcade", "targetname");

    if (isdefined(level.additional_afterlife_arcade_start_point))
        spawn_points = scripts\engine\utility::array_combine(spawn_points, level.additional_afterlife_arcade_start_point);

    spawn_point = spawn_points[player getentitynumber()];

    if (!scripts\engine\utility::is_true(player.iwz_gns_staging_spawn_logged))
    {
        player.iwz_gns_staging_spawn_logged = true;
        arcade_log("player staged: ent=" + (player getentitynumber()) + " origin=" + vector_to_log_string(spawn_point.origin));
    }

    return spawn_point;
}

get_expected_map(selection)
{
    switch (selection)
    {
        case 1:
            return "cp_zmb";

        case 2:
            return "cp_rave";

        case 3:
            return "cp_disco";

        case 4:
            return "cp_town";

        case 5:
            return "cp_final";

        default:
            return undefined;
    }
}

get_arcade_game_name(selection)
{
    switch (selection)
    {
        case 1:
            return "GHOSTS N SKULLS";

        case 2:
            return "GHOSTS N SKULLS 2";

        case 3:
            return "SKULLBUSTER";

        case 4:
            return "SKULLHOP";

        case 5:
            return "SKULLBREAKER";

        default:
            return "GHOSTS N SKULLS ARCADE";
    }
}

get_arcade_objective_text()
{
    return "DEFEAT THE SKULLS!";
}

arcade_introscreen_text()
{
    lines = [];

    switch (level.script)
    {
        case "cp_zmb":
            wait(2);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_ZMB_INTRO_LINE_1", 1);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_ZMB_INTRO_LINE_2", 2);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_ZMB_INTRO_LINE_3", 3);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(get_arcade_objective_text(), 4);
            break;

        case "cp_rave":
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_RAVE_INTRO_LINE_1", 1);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_RAVE_INTRO_LINE_2", 2);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(get_arcade_objective_text(), 3);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_RAVE_INTRO_LINE_4", 4);
            break;

        case "cp_disco":
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_DISCO_INTRO_LINE_1", 1);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_DISCO_INTRO_LINE_2", 2);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_DISCO_INTRO_LINE_3", 3);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(get_arcade_objective_text(), 4);
            break;

        case "cp_town":
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_TOWN_INTRO_LINE_1", 1);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_TOWN_INTRO_LINE_2", 2);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(get_arcade_objective_text(), 3);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_TOWN_INTRO_LINE_4", 4);
            break;

        case "cp_final":
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_FINAL_INTRO_LINE_1", 1);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_FINAL_INTRO_LINE_2", 2);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(get_arcade_objective_text(), 3);
            wait(1);
            lines[lines.size] = scripts\cp\cp_hud_util::introscreen_corner_line(&"CP_FINAL_INTRO_LINE_4", 4);
            break;
    }

    arcade_log("intro objective shown: objective='" + get_arcade_objective_text() + "' game='" + get_arcade_game_name(level.iwz_gns_arcade_selection) + "' lineCount=" + lines.size);
    scripts\engine\utility::flag_wait("introscreen_over");

    foreach (line in lines)
    {
        line fadeovertime(2);
        line.alpha = 0;
    }

    wait(2);

    foreach (line in lines)
        line destroy();
}

hold_normal_waves()
{
    level endon("game_ended");
    arcade_log("normal wave hold active");
    intro_state_logged = false;

    for (;;)
    {
        level.zombies_paused = 1;

        if (scripts\engine\utility::flag_exist("pause_wave_progression"))
            scripts\engine\utility::flag_set("pause_wave_progression");

        if (!intro_state_logged && scripts\engine\utility::flag_exist("introscreen_over") && scripts\engine\utility::flag("introscreen_over"))
        {
            intro_state_logged = true;
            arcade_log("staging lifecycle verified: wave=" + level.wave_num + " zombiesPaused=" + level.zombies_paused + " directChallenge=" + scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight());
        }

        wait(0.25);
    }
}

launch_arcade_game()
{
    level endon("game_ended");

    deadline = gettime() + 60000;
    while (!arcade_system_ready())
    {
        if (gettime() >= deadline)
        {
            arcade_log("launch timed out waiting for native Ghosts N Skulls setup map=" + level.script);
            return;
        }

        wait(0.1);
    }

    arcade_log("native setup ready: waves=" + level.gns_num_of_wave + " map=" + level.script);
    scripts\engine\utility::flag_wait("introscreen_over");

    while (level.players.size == 0)
        scripts\engine\utility::waitframe();

    if (isdefined(level.gns_end_func))
        level.iwz_gns_original_end_func = level.gns_end_func;

    level.gns_end_func = ::arcade_game_ended;

    setup_arcade_activation_interaction();
}

setup_arcade_activation_interaction()
{
    while (!isdefined(level.interactions) || !isdefined(level.current_interaction_structs))
        scripts\engine\utility::waitframe();

    interaction_count_before = level.current_interaction_structs.size;
    scripts\cp\zombies\direct_boss_fight::disable_weapon_upgrade_interaction();
    arcade_log("staging interaction cleanup: removedWeaponUpgrade=" + (interaction_count_before - level.current_interaction_structs.size));

    door = scripts\engine\utility::getstruct("afterlife_spectate_door", "script_noteworthy");
    forward = anglestoforward(door.angles);
    right = anglestoright(door.angles);

    if (level.script == "cp_zmb")
        activation_origin = door.origin + forward * 130 + right * 165;
    else
        activation_origin = door.origin + forward * 125 + right * 228;

    activation_origin = scripts\engine\utility::drop_to_ground(activation_origin, 0, -300);

    interaction = spawnstruct();
    interaction.name = "boss_fight_activation";
    interaction.script_noteworthy = "boss_fight_activation";
    interaction.origin = activation_origin;
    interaction.cost = 0;
    interaction.powered_on = 1;
    interaction.spend_type = undefined;
    interaction.script_parameters = "";
    interaction.requires_power = 0;
    interaction.hint_func = ::arcade_activation_hint;
    interaction.activation_func = ::activate_arcade_game;
    interaction.enabled = 1;
    interaction.disable_guided_interactions = 0;
    interaction.custom_search_dist = 100;

    level.interactions["boss_fight_activation"] = interaction;
    level.iwz_gns_arcade_activation_interaction = interaction;
    scripts\cp\cp_interaction::add_to_current_interaction_list(interaction);

    arcade_log("staging door ready: game='" + get_arcade_game_name(level.iwz_gns_arcade_selection) + "' origin=" + vector_to_log_string(activation_origin));
}

arcade_activation_hint(interaction, player)
{
    switch (level.iwz_gns_arcade_selection)
    {
        case 1:
            return &"IWZ_GNS_ARCADE_START_SPACELAND";

        case 2:
            return &"IWZ_GNS_ARCADE_START_RAVE";

        case 3:
            return &"IWZ_GNS_ARCADE_START_SHAOLIN";

        case 4:
            return &"IWZ_GNS_ARCADE_START_ATTACK";

        case 5:
            return &"IWZ_GNS_ARCADE_START_BEAST";
    }

    return &"IWZ_GNS_ARCADE_START_GENERIC";
}

activate_arcade_game(interaction, player)
{
    if (scripts\engine\utility::is_true(level.iwz_gns_arcade_starting) || scripts\engine\utility::is_true(level.iwz_gns_arcade_started))
        return;

    level.iwz_gns_arcade_starting = true;
    scripts\cp\cp_interaction::remove_from_current_interaction_list(level.iwz_gns_arcade_activation_interaction);

    arcade_log("staging door activated: playerEnt=" + (player getentitynumber()) + " game='" + get_arcade_game_name(level.iwz_gns_arcade_selection) + "' players=" + level.players.size);
    level thread transition_players_to_arcade_game();
}

transition_players_to_arcade_game()
{
    destinations = scripts\engine\utility::getstructarray("ghost_wave_player_start", "targetname");
    level.iwz_gns_arcade_transition_count = 0;
    expected_transitions = level.players.size;

    foreach (player in level.players)
    {
        destination = destinations[player getentitynumber()];
        level thread transition_arcade_player(player, destination);
    }

    deadline = gettime() + 5000;
    while (level.iwz_gns_arcade_transition_count < expected_transitions && gettime() < deadline)
        wait(0.05);

    if (level.iwz_gns_arcade_transition_count < expected_transitions)
        arcade_log("portal transition timeout: completed=" + level.iwz_gns_arcade_transition_count + " expected=" + expected_transitions);
    else
        arcade_log("portal transition complete: players=" + expected_transitions);

    level.disableplayerdamage = undefined;
    level.disable_consumables = undefined;
    level.iwz_gns_arcade_started = true;
    level.iwz_gns_arcade_starting = undefined;

    arcade_log("starting native game: selection=" + level.iwz_gns_arcade_selection + " players=" + level.players.size);
    scripts\cp\maps\cp_zmb\cp_zmb_ghost_wave::start_ghost_wave();
}

transition_arcade_player(player, destination)
{
    player endon("disconnect");
    scripts\cp\zombies\direct_boss_fight::move_player_through_portal_tube(player, [destination]);
    level.iwz_gns_arcade_transition_count++;
    arcade_log("portal player complete: ent=" + (player getentitynumber()) + " completed=" + level.iwz_gns_arcade_transition_count);
}

arcade_system_ready()
{
    if (!isdefined(level.gns_num_of_wave))
        return false;

    if (!isdefined(level.moving_target_wave_info))
        return false;

    if (!isdefined(level.moving_target_wave_info[level.gns_num_of_wave]))
        return false;

    if (!isdefined(level.players))
        return false;

    return true;
}

arcade_game_ended()
{
    if (isdefined(level.iwz_gns_original_end_func))
        [[level.iwz_gns_original_end_func]]();

    if (scripts\engine\utility::is_true(level.iwz_gns_arcade_result_handled))
        return;

    level.iwz_gns_arcade_result_handled = true;
    // The stock win path assigns ghostskulls_complete_status only after
    // delay_end_ghost() invokes gns_end_func. The fail path sets this flag
    // before the callback, so processing_ghost_wave_failing is the reliable
    // result discriminator at this point for both paths.
    won = !scripts\engine\utility::is_true(level.processing_ghost_wave_failing);
    result = level.end_game_string_index["kia"];
    winning_team = "axis";

    if (won)
    {
        result = level.end_game_string_index["win"];
        winning_team = "allies";
    }

    splash = 6;
    if (won)
        splash = 5;

    setomnvar("zm_boss_id", level.iwz_gns_arcade_selection);
    setomnvar("zm_boss_splash", splash);

    arcade_log("native game completed: selection=" + level.iwz_gns_arcade_selection + " won=" + won + " failing=" + level.processing_ghost_wave_failing + " splash=" + splash + " result=" + result);

    // Stock Ghosts N Skulls has now restored player state and shown its score
    // splash. Finish through the same endgame path as Boss Battle so the normal
    // post-game Play Again and Exit actions retain all party/lobby behavior.
    level thread [[level.endgame]](winning_team, result);
}

vector_to_log_string(value)
{
    return "(" + value[0] + "," + value[1] + "," + value[2] + ")";
}

arcade_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("GhostsNSkullsArcade", message);
}
