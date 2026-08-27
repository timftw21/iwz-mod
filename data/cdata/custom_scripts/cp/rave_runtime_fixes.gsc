main()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;

    knife_animation_func = getfunction("scripts/cp/zombies/interaction_knife_throw", "load_animation");
    collect_bait_func = getfunction("scripts/cp/maps/cp_rave/cp_rave_harpoon_quest", "collect_bait");
    spawn_slasher_func = getfunction("scripts/cp/maps/cp_rave/cp_rave", "spawn_slasher_after_timer");
    slash_perk_func = getfunction("scripts/cp/maps/cp_rave/cp_rave_j_mem_quest", "slash_a_perk");
    play_slasher_vo_func = getfunction("scripts/cp/maps/cp_rave/cp_rave", "play_slasher_vo");
    clear_slasher_on_death_func = getfunction("scripts/cp/maps/cp_rave/cp_rave", "clear_slasher_on_death");
    slasher_enemy_monitor_func = getfunction("scripts/cp/maps/cp_rave/cp_rave", "slasher_enemy_monitor");
    slasher_audio_monitor_func = getfunction("scripts/cp/maps/cp_rave/cp_rave", "slasher_audio_monitor");

    if (!isdefined(knife_animation_func) || !isdefined(collect_bait_func) ||
        !isdefined(spawn_slasher_func) || !isdefined(slash_perk_func) ||
        !isdefined(play_slasher_vo_func) ||
        !isdefined(clear_slasher_on_death_func) ||
        !isdefined(slasher_enemy_monitor_func) ||
        !isdefined(slasher_audio_monitor_func))
    {
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "installation failed: a stock Rave function was unavailable");
        return;
    }

    level.iwz_rave_play_slasher_vo = play_slasher_vo_func;
    level.iwz_rave_clear_slasher_on_death = clear_slasher_on_death_func;
    level.iwz_rave_slasher_enemy_monitor = slasher_enemy_monitor_func;
    level.iwz_rave_slasher_audio_monitor = slasher_audio_monitor_func;
    replacefunc(knife_animation_func, ::load_knife_throw_animation_stub);
    replacefunc(collect_bait_func, ::collect_bait_stub);
    replacefunc(spawn_slasher_func, ::spawn_slasher_after_timer_scene_25);
    replacefunc(slash_perk_func, ::preserve_perks_after_quest_failure);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "installed knife-precache suppression, hidden bait interaction, Scene-25 automatic Slasher gate, and quest-failure perk protection");
}

load_knife_throw_animation_stub()
{
    // These stock precache calls raise runtime errors on Rave. The animation
    // assets are already present in cp_dlc1_zombie and play correctly by name.
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "suppressed invalid knife-game animation precaches");
}

preserve_perks_after_quest_failure(player)
{
    if (!isdefined(player) || !isplayer(player))
    {
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "quest-failure perk protection skipped: player unavailable");
        return;
    }

    perk_count = 0;
    if (isdefined(player.zombies_perks))
        perk_count = player.zombies_perks.size;

    // Stock slash_a_perk selects one random zombies_perks key and passes it to
    // take_zombies_perk. Keep the failure flow intact while suppressing only
    // that punishment and its slashed-perk HUD state.
    player setclientomnvar("zombie_coaster_ticket_earned", -1);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "suppressed quest-failure perk loss player=" +
        player getentitynumber() + " preservedPerks=" + perk_count);
}

spawn_slasher_after_timer_scene_25(delay, authored_origin, authored_angles)
{
    // The automatic Rave-mode call supplies only its five-second delay. The
    // Jay memory quest supplies an authored origin and must remain able to
    // spawn its required Slasher before Scene 25.
    is_automatic_rave_spawn = !isdefined(authored_origin);
    if (is_automatic_rave_spawn &&
        (!isdefined(level.wave_num) || level.wave_num < 25))
    {
        current_scene = -1;
        if (isdefined(level.wave_num))
            current_scene = level.wave_num;

        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "suppressed automatic Rave-mode Slasher scene=" + current_scene +
            " requiredScene=25");
        return;
    }

    requested_scene = -1;
    if (isdefined(level.wave_num))
        requested_scene = level.wave_num;

    wait(delay);
    if (isdefined(level.slasher))
    {
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "Slasher request ignored: one is already active source=" +
            get_slasher_request_source(is_automatic_rave_spawn) +
            " scene=" + requested_scene);
        return;
    }

    if (level.no_slasher)
    {
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "Slasher request blocked by stock no_slasher state source=" +
            get_slasher_request_source(is_automatic_rave_spawn) +
            " scene=" + requested_scene);
        return;
    }

    scripts\cp\zombies\zombies_spawning::increase_reserved_spawn_slots(1);
    while (scripts\mp\mp_agent::getfreeagentcount() < 1)
        wait(0.1);

    spawn_location = scripts\cp\zombies\zombies_spawning::get_scored_goon_spawn_location();
    if (isdefined(spawn_location) && !isdefined(level.slasher))
    {
        spawn_origin = spawn_location.origin;
        if (isdefined(authored_origin))
            spawn_origin = authored_origin;

        spawn_angles = spawn_location.angles;
        if (isdefined(authored_angles))
            spawn_angles = authored_angles;

        spawn_origin = getclosestpointonnavmesh(spawn_origin);
        level.slasher = scripts\mp\mp_agent::spawnnewagent(
            "slasher", "axis", spawn_origin, spawn_angles);
        level thread [[level.iwz_rave_play_slasher_vo]]();
        if (isdefined(level.slasher))
        {
            if (!isdefined(level.zombie_slasher_vo_prefix))
                level.zombie_slasher_vo_prefix = "zmb_vo_slasher_";

            level.slasher setethereal(1);
            level.slasher.voprefix = level.zombie_slasher_vo_prefix;
            level.slasher thread [[level.iwz_rave_clear_slasher_on_death]]();
            level.slasher thread [[level.iwz_rave_slasher_enemy_monitor]]();
            level.slasher thread [[level.iwz_rave_slasher_audio_monitor]]();
            custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
                "Slasher spawned source=" +
                get_slasher_request_source(is_automatic_rave_spawn) +
                " scene=" + requested_scene + " ent=" +
                level.slasher getentitynumber() + " origin=" + spawn_origin);
            return;
        }

        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "Slasher spawnnewagent failed source=" +
            get_slasher_request_source(is_automatic_rave_spawn) +
            " scene=" + requested_scene + " origin=" + spawn_origin);
        return;
    }

    scripts\cp\zombies\zombies_spawning::decrease_reserved_spawn_slots(1);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "Slasher spawn location unavailable source=" +
        get_slasher_request_source(is_automatic_rave_spawn) +
        " scene=" + requested_scene);
}

get_slasher_request_source(is_automatic_rave_spawn)
{
    if (is_automatic_rave_spawn)
        return "rave-mode";

    return "memory-quest";
}

collect_bait_stub()
{
    bait_loc = scripts\engine\utility::getstruct("bait_loc", "targetname");
    bait_trigger = spawn("script_model", bait_loc.origin);
    bait_trigger setmodel("tag_origin");
    bait_trigger makeusable();

    // Retail leaves this usable trigger's hint index unset. The missing
    // CP_RAVE_PICK_UP_BAIT localization is intentional and should not be
    // replaced with a visible internal or literal prompt.
    level.bait_model = getent("bait_pickup", "targetname");
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "created bait trigger with intentionally hidden use hint");

    for (;;)
    {
        bait_trigger waittill("trigger", player);
        player.has_bait = 1;
        player thread scripts\cp\utility::usegrenadegesture(player, "iw7_pickup_zm");
        player thread scripts\cp\powers\coop_powers::givepower("power_bait", "secondary", undefined, undefined, undefined, 1, 1);
        wait(0.1);
        level.bait_model hidefromplayer(player);
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "bait collected player=" + player getentitynumber());
    }
}
