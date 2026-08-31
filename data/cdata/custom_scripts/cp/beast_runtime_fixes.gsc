main()
{
    if (getdvar("ui_mapname") != "cp_final")
        return;

    // CODIW-Source renames this retail asset/symbol to
    // zmb_zombie_agent::func_5774. The retail names preserved by the second
    // dump are zombie_agent::_id_5774; getfunction must use those names.
    dissolve_corpse = getfunction("scripts/mp/agents/zombie/zombie_agent", "_id_5774");
    create_disk_interaction = getfunction("scripts/cp/maps/cp_final/cp_final", "creatediskinteraction");
    init_bridge_pieces = getfunction("scripts/cp/maps/cp_final/cp_final_mpq", "initbridgepieces");
    set_in_pap_room = getfunction("scripts/cp/maps/cp_final/cp_final_fast_travel", "set_in_pap_room");
    final_starting_vo = getfunction("scripts/cp/maps/cp_final/cp_final_vo", "final_starting_vo");
    willard_intro_vo = getfunction("scripts/cp/maps/cp_final/cp_final_vo", "willard_intro_vo");
    new_wave_sound = getfunction("scripts/cp/zombies/zombies_spawning", "_id_BDD4");

    installed = 0;
    if (isdefined(dissolve_corpse))
    {
        replacefunc(dissolve_corpse, ::dissolve_corpse_without_hidden_collision);
        installed++;
        beast_fix_log("installed retail zombie_agent::_id_5774 dissolved-corpse deletion hook");
    }
    else
        beast_fix_log("corpse hook unavailable: retail zombie_agent::_id_5774 lookup failed");

    if (isdefined(create_disk_interaction))
    {
        replacefunc(create_disk_interaction, ::create_highlighted_disk_interaction);
        installed++;
        beast_fix_log("installed persistent Phantom-disk model and highlight hook");
    }
    else
        beast_fix_log("disk hook unavailable: creatediskinteraction stock lookup failed");

    if (isdefined(init_bridge_pieces))
    {
        replacefunc(init_bridge_pieces, ::init_bridge_pieces_with_accessible_focus);
        installed++;
        beast_fix_log("installed bridge-piece interaction focus hook");
    }
    else
        beast_fix_log("bridge hook unavailable: initbridgepieces lookup failed");

    if (isdefined(set_in_pap_room))
    {
        replacefunc(set_in_pap_room, ::set_in_pap_room_with_projector_audio);
        installed++;
        beast_fix_log("installed Pack-a-Punch projector audio-zone hook");
    }
    else
        beast_fix_log("Pack-a-Punch audio hook unavailable: set_in_pap_room lookup failed");

    if (isdefined(final_starting_vo) && isdefined(willard_intro_vo))
    {
        level.iwz_beast_stock_final_starting_vo = final_starting_vo;
        level.iwz_beast_stock_willard_intro_vo = willard_intro_vo;
        replacefunc(final_starting_vo, ::final_starting_vo_when_player_is_ready);
        installed++;
        beast_fix_log("installed synchronous solo spawn-VO hook");
    }
    else
        beast_fix_log("spawn-VO hook unavailable: final_starting_vo or willard_intro_vo lookup failed");

    if (isdefined(new_wave_sound))
    {
        replacefunc(new_wave_sound, ::play_beast_cross_script_new_wave_sound_once);
        installed++;
        beast_fix_log("installed cp_final Scene 1 duplicate cue gate");
    }
    else
        beast_fix_log("new-wave cue hook unavailable: retail zombies_spawning::_id_BDD4 lookup failed");

    beast_fix_log("pre-load installation complete hooks=" + installed +
        "/6 pendingPostLoad=interaction-properties");
}

post_load()
{
    if (getdvar("ui_mapname") != "cp_final")
        return;

    install_authoritative_dispatch_boundaries();
    level thread listen_for_beast_floppy_test_command();
    beast_fix_log("started Beast floppy test monitor; " +
        "Scene 1 audio owner=presented HUD splash " +
        "subsequentSceneOwner=cp_final spawning stock helper");
}

beast_fix_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("BeastFixes", message);
}

install_authoritative_dispatch_boundaries()
{
    installed = 0;

    if (isdefined(level.interaction_trigger_properties_func))
    {
        level.iwz_beast_stock_interaction_trigger_properties =
            level.interaction_trigger_properties_func;
        level.interaction_trigger_properties_func =
            ::interaction_trigger_properties_with_accessible_bridge_focus;
        installed++;
        beast_fix_log("installed bridge focus dispatch boundary " +
            "source=level.interaction_trigger_properties_func");
    }
    else
        beast_fix_log("bridge focus dispatch unavailable: stock " +
            "level.interaction_trigger_properties_func missing");

    beast_fix_log("post-load dispatch installation complete boundaries=" +
        installed + "/1");
}

interaction_trigger_properties_with_accessible_bridge_focus(
    trigger, interaction, offset)
{
    [[level.iwz_beast_stock_interaction_trigger_properties]](
        trigger, interaction, offset);

    if (!isdefined(interaction) || !isdefined(interaction.script_noteworthy) ||
        interaction.script_noteworthy != "pap_bridge")
        return;

    // cp_final's stock override uniquely leaves bridge debris at
    // require-look-at=1. The actual monitor places the use trigger at the
    // struct's X/Y but replaces Z with player eye height, so moving only the
    // authored Z cannot move the usable point out from behind the large panel.
    // Use the same non-directional trigger pattern as the map's other large
    // quest pickups; acquisition remains limited to this struct's search range.
    trigger usetriggerrequirelookat(0);
    trigger setusefov(360);

    if (!isdefined(interaction.iwz_accessible_focus_logged))
    {
        interaction.iwz_accessible_focus_logged = 1;
        piece_name = "undefined";
        if (isdefined(interaction.targetname))
            piece_name = interaction.targetname;

        player_ent = "undefined";
        if (isdefined(self) && isplayer(self))
            player_ent = self getentitynumber();

        beast_fix_log("activated accessible bridge focus piece=" + piece_name +
            " origin=" + interaction.origin + " player=" + player_ent +
            " searchDist=" + interaction.custom_search_dist +
            " requireLookAt=0 useFov=360");
    }
}

dissolve_corpse_without_hidden_collision(delay, traversing)
{
    if (!scripts\engine\utility::is_true(traversing))
        wait(delay);

    if (!isdefined(self))
        return;

    self setscriptablepartstate("death_fx", "active", 1);
    wait(0.1);

    if (!isdefined(self))
        return;

    // Stock zombie_agent::_id_5774 hides the cloned body at this point but
    // leaves the corpse entity alive. The concurrently scheduled ragdoll path
    // can then keep a flesh DObj in bullet traces. The dissolve has completed,
    // so remove the cloned body instead of retaining an invisible corpse.
    origin = self.origin;
    corpse_ent = self getentitynumber();
    self setcontents(0);
    self hide(1);
    beast_fix_log("deleted dissolved cryptid corpse ent=" + corpse_ent +
        " origin=" + origin + " delay=" + delay + " traversing=" + traversing);
    self delete();
}

create_highlighted_disk_interaction(model)
{
    // The thrown tag_origin_puzzle_piece wrapper is needed for the stock
    // physics launch, but its visible scriptable child is offset from the
    // wrapper origin. Once it has landed, use the same direct floppy XModels
    // used by spawnpuzzlepiece so the interaction and FX share the disk origin.
    disk_model = set_landed_phantom_disk_model(model, level.phantomdisk);

    interaction = spawnstruct();
    interaction.origin = model.origin;
    interaction.angles = model.angles;
    interaction.script_noteworthy = "puzzle_pieces";
    interaction.var_336 = "interaction";
    interaction.requires_power = 0;
    interaction.powered_on = 1;
    interaction.script_parameters = "default";
    interaction.state = level.phantomdisk;
    interaction.model = model;

    level.struct_class_names["targetname"]["interaction"][level.struct_class_names["targetname"]["interaction"].size] = interaction;
    level.struct_class_names["script_noteworthy"]["puzzle_pieces"][level.struct_class_names["script_noteworthy"]["puzzle_pieces"].size] = interaction;

    playfx(level._effect["generic_pickup"], interaction.origin + (0, 0, 24));
    fx_origin = interaction.origin + (0, 0, 2);
    interaction.iwz_floppy_fx = spawnfx(level._effect["powerup_additive_fx"], fx_origin);
    triggerfx(interaction.iwz_floppy_fx);
    interaction.iwz_floppy_fx setfxkilldefondelete();
    scripts\cp\cp_interaction::add_to_current_interaction_list(interaction);

    beast_fix_log("created Phantom disk interaction modelEnt=" +
        model getentitynumber() + " model=" + disk_model + " origin=" +
        interaction.origin + " fxOrigin=" + fx_origin + " persistentFx=powerup_additive_fx");
}

set_landed_phantom_disk_model(model, state)
{
    switch (int(state))
    {
        case 1: disk_model = "cp_final_floppydisk_01"; break;
        case 2: disk_model = "cp_final_floppydisk_02"; break;
        case 3: disk_model = "cp_final_floppydisk_03"; break;
        case 4: disk_model = "cp_final_floppydisk_04"; break;
        case 5: disk_model = "cp_final_floppydisk_05"; break;
        case 6: disk_model = "cp_final_floppydisk_06"; break;
        case 7: disk_model = "cp_final_floppydisk_07"; break;
        case 8: disk_model = "cp_final_floppydisk_08"; break;
        case 9: disk_model = "cp_final_floppydisk_09"; break;
        case 10: disk_model = "cp_final_floppydisk_10"; break;
        case 11: disk_model = "cp_final_floppydisk_11"; break;
        case 12: disk_model = "cp_final_floppydisk_12"; break;
        default:
            beast_fix_log("kept Phantom disk wrapper: invalid puzzle state=" + state);
            return "tag_origin_puzzle_piece";
    }

    model setmodel(disk_model);
    return disk_model;
}

init_bridge_pieces_with_accessible_focus()
{
    pieces = scripts\engine\utility::getstructarray("pap_bridge", "script_noteworthy");

    foreach (piece in pieces)
    {
        model_origin = piece.origin;
        piece.name = "pap_quest";
        // The map's level-specific monitor supports per-struct search radii.
        // 128 is the stock value used for other large quest objects such as
        // Spaceland's DJ speakers; the bridge panels otherwise use 72 units.
        piece.custom_search_dist = 128;

        model = spawn("script_model", model_origin);
        model setmodel("debris_exterior_damaged_metal_panels_08_scl50");
        model.angles = piece.angles;
        model.targetname = "pap_bridge_model";

        piece_name = "undefined";
        if (isdefined(piece.targetname))
            piece_name = piece.targetname;

        beast_fix_log("configured bridge interaction piece=" + piece_name +
            " authoredOrigin=" + model_origin + " angles=" + piece.angles +
            " modelEnt=" + model getentitynumber() +
            " searchDist=128 requireLookAtOverride=pending-focus");
    }

    scripts\engine\utility::flag_init("bridge_pieces_collected");
}

set_in_pap_room_with_projector_audio(player, in_pap)
{
    if (!isdefined(player) || !isplayer(player))
    {
        beast_fix_log("Pack-a-Punch audio state rejected: invalid player");
        return;
    }

    player.is_in_pap = in_pap;

    if (scripts\engine\utility::is_true(in_pap))
    {
        // The shared CP soundbank defines cp_zmb_projector_room specifically
        // for the hidden Pack-a-Punch room: pap_mix plus the basement interior
        // ambience. Beast's stock teleport only toggles is_in_pap, so the
        // exterior cp_final blizzard bed survives the off-grid teleport.
        player setclienttriggeraudiozone("cp_zmb_projector_room", 0.5);
        beast_fix_log("entered Pack-a-Punch audio zone player=" +
            player getentitynumber() + " zone=cp_zmb_projector_room");
    }
    else
    {
        player clearclienttriggeraudiozone(0.5);
        beast_fix_log("left Pack-a-Punch audio zone player=" +
            player getentitynumber() + " restored=map-trigger-zone");
    }
}

final_starting_vo_when_player_is_ready()
{
    level endon("game_ended");
    stock_final_starting_vo = level.iwz_beast_stock_final_starting_vo;
    if (!isdefined(stock_final_starting_vo))
    {
        beast_fix_log("spawn-VO readiness hook aborted: stock function pointer unavailable");
        return;
    }

    // final_starting_vo is launched once. Restore its retail entry immediately
    // so multiplayer retains the complete stock conversation path.
    replacefunc(stock_final_starting_vo, stock_final_starting_vo);
    scripts\engine\utility::flag_wait("intro_gesture_done");

    player_count = 0;
    if (isdefined(level.players))
        player_count = level.players.size;

    if (player_count != 1)
    {
        beast_fix_log("spawn-VO readiness hook retained stock multiplayer path players=" +
            player_count);
        [[stock_final_starting_vo]]();
        return;
    }

    player = level.players[0];
    ready_wait_started = gettime();
    while (isdefined(player) &&
        (player.sessionstate != "playing" ||
        !isdefined(player.vo_prefix) ||
        !isdefined(player.vo_system) ||
        !isdefined(player.vo_system.vo_queue) ||
        (isdefined(player.vo_system.is_playing) && player.vo_system.is_playing) ||
        !isdefined(level.vo_priority_level) ||
        (isdefined(player._id_C9CB) && player._id_C9CB)))
        wait(0.05);

    if (!isdefined(player))
    {
        beast_fix_log("spawn-VO readiness hook aborted: solo player disconnected");
        return;
    }

    spawn_alias = scripts\engine\utility::random(["spawn_intro", "spawn_solo_first"]);
    full_alias = player.vo_prefix + spawn_alias;
    if (!soundexists(full_alias))
    {
        beast_fix_log("solo spawn-VO synchronous path missing alias=" + full_alias +
            "; falling back to stock queue");
        [[stock_final_starting_vo]]();
        return;
    }

    // Stock final_starting_vo queues this one-time line on a child thread and
    // immediately starts its duration wait. On Beast that initial queue request
    // can disappear before the VO scheduler owns it. Other dialogue paths in
    // this same stock script use the synchronous native VO lifecycle below.
    // Use that path for solo spawn only, preserving the exact aliases and data.
    vo_data = scripts\cp\cp_vo::create_vo_data(full_alias, 20, 0, 1, spawn_alias);
    player scripts\cp\cp_vo::set_vo_system_playing(1);
    player scripts\cp\cp_vo::set_vo_currently_playing(vo_data);
    beast_fix_log("solo spawn-VO synchronous playback started player=" +
        player getentitynumber() + " alias=" + full_alias +
        " duration=" + scripts\cp\cp_vo::get_sound_length(full_alias) +
        " deferredMs=" + (gettime() - ready_wait_started));
    player scripts\cp\cp_vo::play_vo(vo_data);
    player scripts\cp\cp_vo::unset_vo_currently_playing();
    player scripts\cp\cp_vo::set_vo_system_playing(0);
    beast_fix_log("solo spawn-VO synchronous playback completed alias=" + full_alias);

    level thread [[level.iwz_beast_stock_willard_intro_vo]]();
}

play_beast_cross_script_new_wave_sound_once()
{
    current_wave = level.wave_num;
    if (current_wave == 1)
    {
        // Beast's custom spawner is the runtime owner of this helper. Wave 1
        // waits ten seconds before calling it, after the HUD has already
        // presented Scene 1 and played the missing initial cue. Suppress only
        // that delayed duplicate and preserve the completion notification.
        level notify("wave_start_sound_done");
        beast_fix_log("suppressed delayed Scene 1 duplicate new-wave cue " +
            "internalWave=1 displayedScene=1 owner=presented-HUD-splash " +
            "notification=preserved");
        return;
    }

    // cp_final_spawning is the sole observed runtime path on later waves. This
    // is the exact retail zombies_spawning::_id_BDD4 body from both dumps; it
    // remains inline because the replacefunc gate must stay installed.
    beast_fix_log("released stock new-wave cue internalWave=" + current_wave +
        " displayedScene=" + current_wave +
        " owner=cp_final-spawning-stock-helper");
    if (!scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight())
        scripts\cp\utility::playsoundinspace("mus_zombies_newwave", (0, 0, 0), 1);

    level notify("wave_start_sound_done");
}

listen_for_beast_floppy_test_command()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_spawn_beast_floppy", player);

        if (!isdefined(player) || !isplayer(player))
        {
            beast_fix_log("spawnBeastFloppy rejected: player unavailable");
            continue;
        }

        if (!isdefined(level.phantomdisk) || !isdefined(level._effect["powerup_additive_fx"]))
        {
            beast_fix_log("spawnBeastFloppy rejected: Phantom disk state or highlight FX unavailable");
            player iprintlnbold("Phantom disk state is not ready");
            continue;
        }

        player_angles = player getplayerangles();
        forward = anglestoforward(player_angles);
        spawn_origin = player.origin + (forward * 64) + (0, 0, 24);
        spawn_origin = scripts\engine\utility::drop_to_ground(spawn_origin, 48, -160);

        model = spawn("script_model", spawn_origin);
        model.angles = (0, player_angles[1], 0);
        model setmodel("tag_origin_puzzle_piece");
        model setscriptablepartstate("puzzle_pieces", level.phantomdisk);
        create_highlighted_disk_interaction(model);

        beast_fix_log("spawnBeastFloppy completed player=" +
            player getentitynumber() + " modelEnt=" + model getentitynumber() +
            " origin=" + spawn_origin);
        player iprintlnbold("Spawned Phantom floppy disk");
    }
}
