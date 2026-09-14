// IWZ-LOAD: map=cp_rave
main()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;

    replacefunc(scripts\cp\zombies\interaction_knife_throw::give_knife_throw_rewards,
        ::give_knife_throw_rewards);
    replacefunc(scripts\cp\zombies\interaction_knife_throw::_id_6955, ::finish_knife_game);
    replacefunc(scripts\cp\zombies\arcade_game_utility::restore_player_grenades_post_game,
        ::restore_arcade_equipment);
    replacefunc(scripts\cp\cp_interaction::remove_from_current_interaction_list_for_player,
        ::disable_interaction_for_player);
    replacefunc(scripts\cp\cp_interaction::add_to_current_interaction_list_for_player,
        ::enable_interaction_for_player);
    replacefunc(scripts\cp\maps\cp_rave\cp_rave_harpoon_quest::break_the_chains,
        ::break_the_chains);
    replacefunc(scripts\cp\maps\cp_rave\cp_rave_j_mem_quest::pick_up_charged_photo,
        ::pick_up_charged_photo);
    replacefunc(scripts\cp\maps\cp_rave\cp_rave_j_mem_quest::drop_photo_from_slasher,
        ::drop_photo_from_slasher);

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

post_load()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;
    level thread install_rave_interaction_callbacks();
    level thread listen_for_cabinet_tests();
}

install_rave_interaction_callbacks()
{
    level endon("game_ended");
    while (!isdefined(level.interactions) ||
        !isdefined(level.interactions["interaction_knife_throw"]) ||
        !isdefined(level.interactions["memory_quest_end_pos"]))
        wait(0.05);

    level.interactions["interaction_knife_throw"].hint_func = ::knife_game_hint;
    level.interactions["interaction_knife_throw"].can_use_override_func = ::can_play_knife_game;
    level.interactions["interaction_knife_throw"].activation_func = ::use_knife_game;
    level.interactions["memory_quest_end_pos"].activation_func = ::use_charm;
    level.guidedinteractionexclusion = ::rave_guided_interaction_allowed;
    scripts\cp\cp_interaction::register_interaction("iwz_rave_quest_use", undefined,
        undefined, ::quest_use_hint, ::accept_quest_use, 0, 0);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "installed knife-game protection, green rewards, unavailable hints, 5s charm descriptions, and shared cabinet/photo interactions");
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "guided prompts disabled for cabinet/photos and unavailable knife games; quest selection uses stock ground placement");
}

rave_guided_interaction_allowed(interaction, player, name)
{
    // This callback controls only the distant circular marker, not the close
    // use hint or the ability to interact with an item.
    if (isdefined(interaction.script_noteworthy) &&
        interaction.script_noteworthy == "iwz_rave_quest_use")
        return 0;
    if (is_knife_game(interaction) && !can_play_knife_game(interaction, player))
        return 0;
    return scripts\cp\maps\cp_rave\cp_rave::guidedinteractionsexclusions(interaction, player, name);
}

quest_use_hint(interaction, player)
{
    return interaction.iwz_hint;
}

accept_quest_use(interaction, player)
{
    if (!scripts\engine\utility::is_true(interaction.iwz_active))
        return;
    interaction.iwz_active = 0;
    scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
    player.interaction_trigger makeunusable();
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "quest interaction accepted type=" + interaction.iwz_context +
        " player=" + player getentitynumber() +
        " distance=" + distance(player.origin, interaction.origin) + " hint cleared before effects");
    interaction.iwz_entity notify("trigger", player);
}

wait_for_quest_use(entity, hint, context)
{
    // Give these native pickups one owner for selection, input, and hint
    // lifetime, using the map's regular interaction path.
    entity makeunusable();
    interaction = spawnstruct();
    // cp_interaction::_id_5CF3 does this for stock interaction structs at map
    // startup. These later-created structs miss that pass. Keeping the elevated
    // cabinet lock position makes its 72-unit feet-distance check unreachable.
    interaction.origin = scripts\engine\utility::drop_to_ground(entity.origin, 10, -200) + (0, 0, 1);
    interaction.script_noteworthy = "iwz_rave_quest_use";
    interaction.script_parameters = "default";
    interaction.name = "iwz_rave_quest_use";
    interaction.requires_power = 0;
    interaction.powered_on = 1;
    interaction.iwz_hint = hint;
    interaction.iwz_entity = entity;
    interaction.iwz_context = context;
    interaction.iwz_active = 1;
    scripts\cp\cp_interaction::add_to_current_interaction_list(interaction);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "quest interaction ready type=" + context +
        " authoredOrigin=" + entity.origin + " interactionOrigin=" + interaction.origin);
    reason = entity scripts\engine\utility::waittill_any_return_no_endon_death(
        "trigger", "iwz_quest_use_cancelled");
    interaction.iwz_active = 0;
    scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
    return reason == "trigger";
}

break_the_chains()
{
    level.iwz_vlad_interaction_active = 1;
    level thread scripts\cp\maps\cp_rave\cp_rave_harpoon_quest::spawn_chain_locks();
    scripts\engine\utility::flag_wait("chains_unlocked");
    cabinet_interaction();
}

cabinet_interaction()
{
    level.iwz_vlad_interaction_active = 1;
    chains = getentarray("harpoon_gun_quest_chains", "targetname");
    trigger = spawn("script_origin", (-332, -1435, 310));
    wait_for_quest_use(trigger, &"CP_RAVE_BREAK_LOCK", "Vlad cabinet");
    trigger delete();
    // A tag effect on a newly spawned entity cannot be resolved by clients
    // until that entity arrives in a snapshot. These stationary chains need no
    // attachment: publish the effect with its world transform.
    playsoundatpos(chains[0].origin, "harpoon_cabinet_unlock");
    // The stock sound has a one-second lead-in before the breaking effect.
    // Start it as soon as use is accepted, with the hint already dismissed.
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "Vlad cabinet unlock sound started; break effect follows in 1s");
    wait(1);
    playfx(level._effect["chain_dissolve"], chains[0].origin,
        anglestoforward(chains[0].angles), anglestoup(chains[0].angles));
    chains[0] hide();
    scripts\engine\utility::flag_set("harpoon_unlocked");
    level.iwz_vlad_interaction_active = 0;
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "Vlad cabinet world break effect started origin=" + chains[0].origin + "; unlocked");
}

listen_for_cabinet_tests()
{
    level endon("game_ended");
    for (;;)
    {
        level waittill("iwz_test_vlad_cabinet", player);
        if (!isdefined(player) || !isplayer(player))
            continue;
        if (!scripts\engine\utility::flag_exist("harpoon_unlocked") ||
            !isdefined(level.interactions) || !isdefined(level.interactions["iwz_rave_quest_use"]))
        {
            player iprintlnbold("The cabinet is still initializing");
            continue;
        }
        chains = getentarray("harpoon_gun_quest_chains", "targetname");
        if (!chains.size)
        {
            player iprintlnbold("The Vlad cabinet is unavailable in this mode");
            continue;
        }
        foreach (symbol in level.lock_spots)
        {
            if (isdefined(symbol))
                symbol delete();
        }
        level.lock_spots = [];
        level.harpoon_locks = 3;
        scripts\engine\utility::flag_clear("harpoon_unlocked");
        chains[0] show();
        scripts\engine\utility::flag_set("chains_unlocked");
        if (!scripts\engine\utility::is_true(level.iwz_vlad_interaction_active))
            level thread cabinet_interaction();
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "testVladCabinet prepared player=" + player getentitynumber() + " repeatable=1");
        player iprintlnbold("Vlad cabinet ready: interact with the locks in the cabin");
    }
}

pick_up_charged_photo(unused, model)
{
    photo = level.photo;
    photo show();
    photo setmodel(model);
    photo thread cancel_expired_photo_use();
    if (!wait_for_quest_use(photo, &"CP_RAVE_INSPECT_ITEM", "charged photograph"))
        return;
    photo hide();
    if (isdefined(level.photo_soul))
        level.photo_soul delete();
    level notify("slasher_photo_taken");
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "charged photograph taken; Slasher sequence released");
}

cancel_expired_photo_use()
{
    self endon("trigger");
    level endon("game_ended");
    level waittill("slasher_photo_timeout");
    self notify("iwz_quest_use_cancelled");
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "expired photograph interaction removed");
}

drop_photo_from_slasher(unused, model, quest)
{
    level.photo setmodel(model);
    level.photo show();
    level thread scripts\cp\loot::drop_loot(level.slasher_drop, undefined, "ammo_max");
    soul_tag = spawn("script_model", level.photo.origin);
    soul_tag setmodel("tag_origin_soultrail");
    wait_for_quest_use(level.photo, &"CP_RAVE_INSPECT_ITEM", "cleansed photograph");
    level.photo hide();
    soul_tag delete();
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "cleansed photograph taken; memory playback started");
    if (model == "cp_rave_quest_photo_03")
    {
        scripts\engine\utility::flag_set("photo_1_kev_given");
        if (level.slasher_level < 2)
            level.slasher_level = 2;
        scripts\cp\maps\cp_rave\cp_rave_j_mem_quest::play_jay_memory_after_slasher_fight("m10_jmewes_bff_2");
    }
    else if (model == "cp_rave_quest_photo_04")
    {
        scripts\engine\utility::flag_set("photo_2_kev_given");
        if (level.slasher_level < 3)
            level.slasher_level = 3;
        scripts\cp\maps\cp_rave\cp_rave_j_mem_quest::play_jay_memory_after_slasher_fight("m11_jmewes_bff_2");
    }
    else
        scripts\cp\maps\cp_rave\cp_rave_j_mem_quest::play_jay_memory_after_slasher_fight("m12_jmewes_bff_2");
    level.circle_fight_done[quest] = 1;
}

is_knife_game(machine)
{
    return isdefined(machine.script_noteworthy) &&
        machine.script_noteworthy == "interaction_knife_throw";
}

disable_interaction_for_player(machine, player)
{
    // Stock removes spent knife machines from the hint search entirely. Keep
    // them visible and enforce the same per-player, per-wave limit at use time.
    if (is_knife_game(machine))
    {
        if (!isdefined(player.iwz_spent_knife_machines))
            player.iwz_spent_knife_machines = [];
        player.iwz_spent_knife_machines = scripts\engine\utility::array_add(
            player.iwz_spent_knife_machines, machine);
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
            "knife game unavailable until next wave player=" + player getentitynumber());
        return;
    }
    player.disabled_interactions = scripts\engine\utility::array_add(player.disabled_interactions, machine);
}

enable_interaction_for_player(machine, player)
{
    if (is_knife_game(machine) && isdefined(player.iwz_spent_knife_machines))
        player.iwz_spent_knife_machines = scripts\engine\utility::array_remove(
            player.iwz_spent_knife_machines, machine);
    player.disabled_interactions = scripts\engine\utility::array_remove(player.disabled_interactions, machine);
    if (is_knife_game(machine) && isdefined(player.last_interaction_point) &&
        player.last_interaction_point == machine)
        player thread scripts\cp\cp_interaction::refresh_interaction();
}

knife_game_spent(machine, player)
{
    return isdefined(player.iwz_spent_knife_machines) &&
        scripts\engine\utility::array_contains(player.iwz_spent_knife_machines, machine);
}

knife_game_hint(machine, player)
{
    // The Spaceland localization asset is not guaranteed to be loaded on Rave.
    // Use its audited wording for both the cabinet and the player's cooldown.
    if (knife_game_spent(machine, player) || isdefined(machine.cooling_down) ||
        scripts\engine\utility::is_true(machine.out_of_order))
        return "Out of order";
    return scripts\cp\zombies\arcade_game_utility::arcade_game_hint_func(machine, player);
}

can_play_knife_game(machine, player)
{
    return !knife_game_spent(machine, player) &&
        !isdefined(machine.cooling_down) &&
        !scripts\engine\utility::is_true(machine.out_of_order) &&
        !(machine.requires_power && !machine.powered_on);
}

use_knife_game(machine, player)
{
    if (!can_play_knife_game(machine, player))
        return;
    player custom_scripts\cp\spaceland_runtime_fixes::enable_arcade_targeting_protection("weapon-save", 1);
    scripts\cp\zombies\interaction_knife_throw::use_knife_throw(machine, player);
}

finish_knife_game(machine, player, reason)
{
    machine._id_A6FB show();
    machine.knife_throw_target setcandamage(0);
    scripts\cp\zombies\interaction_knife_throw::turn_off_knife_throw_light(machine);
    if (isdefined(player) && isalive(player))
    {
        player takeweapon("iw7_cpknifethrow_mp");
        player scripts\cp\zombies\interaction_shooting_gallery::_id_FEBF(player);
        player setclientomnvar("zombie_ca_widget", 0);
        player.playing_game = undefined;
        player scripts\engine\utility::allow_weapon_switch(1);
        if (!player scripts\engine\utility::isusabilityallowed())
            player scripts\engine\utility::allow_usability(1);
        player scripts\cp\zombies\arcade_game_utility::give_player_back_weapon(player);
        player scripts\cp\zombies\arcade_game_utility::restore_player_grenades_post_game();
        playsoundatpos(machine.origin, "mp_slot_machine_coins");
        if (player.arcade_game_award_type == "soul_power")
            player scripts\cp\zombies\zombie_afterlife_arcade::give_soul_power(player, machine.score);
        else
            player scripts\cp\zombies\arcade_game_utility::give_player_tickets(player, machine.score);
        if (!player scripts\cp\utility::areinteractionsenabled())
            player scripts\cp\utility::allow_player_interactions(1);
    }
    player notify("arcade_game_over_for_player");
    if (machine.knife_throw_target.head_hit == 6)
        scripts\cp\loot::give_max_ammo_to_player(player);
    scripts\cp\zombies\interaction_knife_throw::stop_wheel_sfx(machine);

    // Keep the stock wheel reset animation, but expose an unavailable hint
    // during it instead of removing the machine from the interaction search.
    machine.cooling_down = 1;
    if (isdefined(player))
        disable_interaction_for_player(machine, player);
    scripts\cp\cp_interaction::add_to_current_interaction_list(machine);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "knife game ended; reset hint active");
    wait(3);
    machine._id_13CFD rotateto(machine._id_13CFF, 1);
    wait(3);
    machine.cooling_down = undefined;
    foreach (viewer in level.players)
    {
        if (isdefined(viewer.last_interaction_point) && viewer.last_interaction_point == machine)
            viewer thread scripts\cp\cp_interaction::refresh_interaction();
    }
}

give_knife_throw_rewards(target, hit_origin, player)
{
    location = scripts\cp\zombies\interaction_knife_throw::get_knife_hit_location(target, hit_origin);
    reward = scripts\cp\zombies\interaction_knife_throw::get_knife_hit_reward_point(location);
    if (location == "j_helmet")
        target.head_hit++;
    player iprintlnbold("^2+$" + reward + "^7");
    player scripts\cp\cp_persistence::give_player_currency(reward);
}

restore_arcade_equipment()
{
    scripts\cp\utility::restore_super_weapon();
    if (scripts\cp\cp_laststand::player_in_laststand(self))
        return;
    if (isdefined(self.pre_arcade_primary_power))
    {
        slot = level.powers[self.pre_arcade_primary_power].defaultslot;
        scripts\cp\powers\coop_powers::_id_4171(slot);
        scripts\cp\powers\coop_powers::givepower(self.pre_arcade_primary_power, slot,
            undefined, undefined, undefined, undefined, 1);
        scripts\cp\powers\coop_powers::power_adjustcharges(self.pre_arcade_primary_power_charges, slot, 1);
    }
    if (isdefined(self.pre_arcade_secondary_power))
    {
        power = self.pre_arcade_secondary_power;
        slot = level.powers[power].defaultslot;
        scripts\cp\powers\coop_powers::_id_4171(slot);
        cooldown = undefined;
        permanent = 0;
        // Match bait pickup and coop_powers::restore_powers. Stock arcade
        // restoration passes permanent=0, installing a remove-on-last-use
        // watcher, and also drops the cooldown that replenishes bait.
        if (power == "power_bait")
        {
            cooldown = 1;
            permanent = 1;
        }
        scripts\cp\powers\coop_powers::givepower(power, slot,
            undefined, undefined, undefined, cooldown, permanent);
        scripts\cp\powers\coop_powers::power_adjustcharges(self.pre_arcade_secondary_power_charges, slot, 1);
        if (power == "power_bait")
            custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
                "restored arcade bait player=" + self getentitynumber() +
                " charges=" + self.powers[power].charges + " cooldown=1 permanent=1");
    }
    self.pre_arcade_primary_power = undefined;
    self.pre_arcade_primary_power_charges = undefined;
    self.pre_arcade_secondary_power = undefined;
    self.pre_arcade_secondary_power_charges = undefined;
}

use_charm(charm, player)
{
    // Leave quest placement and attachment ownership with the stock callback.
    if (scripts\engine\utility::is_true(charm.quest_complete))
        player thread show_charm_description(charm.name);
    scripts\cp\maps\cp_rave\cp_rave_memory_quests::memories_end_use_func(charm, player);
}

charm_description(name)
{
    switch (name)
    {
        case "binoculars": return "Binoculars: Reloading shocks zombies near your teammates";
        case "lure": return "Fish lure: Gain speed while you keep sprinting";
        case "pool_ball": return "8-ball: Sliding into zombies damages and knocks them back";
        case "shovel": return "Shovel: Reviving a teammate knocks away nearby zombies";
        case "pacifier": return "Pacifier: Zombies that hit you take damage and stagger";
        case "ring": return "Ring: Melee hits restore your health";
        case "arrowhead": return "Arrowhead: Aim assist targets zombie heads";
        case "toad": return "Frog: Move freely through water and recover sprint faster";
        case "boots": return "Boots: Headshot kills make zombie heads explode";
        case "tiki_mask": return "Tiki mask: Stowed weapons slowly reload from reserve ammo";
    }
    return undefined;
}

show_charm_description(name)
{
    level endon("game_ended");
    description = charm_description(name);
    if (!isdefined(description))
        return;
    self notify("iwz_charm_hint_replaced");
    font = "default";
    if (isdefined(level.lowermessagefont))
        font = level.lowermessagefont;
    y = level.lowertexty;
    size = level.lowertextfontsize;
    if (level.splitscreen || self issplitscreenplayer() && !isai(self))
    {
        y -= 40;
        size *= 1.3;
    }
    hint = scripts\cp\utility::createfontstring(font, size);
    hint.archived = 0;
    hint.sort = 10;
    hint.showinkillcam = 0;
    hint.hidewheninmenu = 1;
    hint scripts\cp\utility::setpoint("CENTER", level.lowertextyalign, 0, y);
    hint settext(description);
    hint.alpha = 0.85;
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes",
        "charm description player=" + self getentitynumber() + " charm=" + name + " hold=5s fade=0.5s");
    events = ["death", "last_stand", "disconnect", "iwz_charm_hint_replaced"];
    reason = self scripts\engine\utility::waittill_any_in_array_or_timeout_no_endon_death(events, 5);
    if (reason == "timeout" && isdefined(hint))
    {
        hint fadeovertime(0.5);
        hint.alpha = 0;
        self scripts\engine\utility::waittill_any_in_array_or_timeout_no_endon_death(events, 0.5);
    }
    if (isdefined(hint))
        hint scripts\cp\utility::destroyelem();
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
