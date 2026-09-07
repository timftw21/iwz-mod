main()
{
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    if (getdvar("ui_mapname") != "cp_disco")
        return;

    precacheitem("iw7_g18c_zm");
    // Shaolin's _05 board shares the original _01 mesh and physics bounds.
    custom_scripts\cp\survival_perks::precache_perk_wall("p7_cafe_wall_menu_05");
    // Shaolin already loads this complete PaP image/energy effect. Its chi
    // door scriptable has no usable "active" state in the installed assets.
    level._effect["iwz_subway_pap"] = loadfx(
        "vfx/iw7/levels/cp_rave/vfx_rave_portal_02.vfx");

    replacefunc(scripts\cp\maps\cp_disco\cp_disco::init_magic_wheel,
        ::select_subway_wheel);
    replacefunc(scripts\cp\zombies\interaction_magicwheel::_id_BC3F,
        ::hold_subway_wheel);
    replacefunc(scripts\cp\maps\cp_disco\cp_disco_fast_travel::init_teleport_portals,
        ::setup_subway_portal);
    // Keep the stock tube, timer, protection and cleanup. Only its destination
    // changes, covering both early departure and the automatic 30-second exit.
    replacefunc(scripts\cp\maps\cp_disco\cp_disco::teleport_to_safe_spot,
        ::return_to_subway);
    replacefunc(scripts\cp\maps\cp_disco\cp_disco::subway_trains,
        ::survival_subway_trains);
    replacefunc(scripts\cp\zombies\directors_cut::allow_directors_cut,
        ::disallow_directors_cut);

    survival_log("pre-load hooks installed map=cp_disco portal=disco-subway-to-pap " +
        "papExit=subway wheel=authored-subway train=power-independent directorsCut=disabled");
}

post_load()
{
    if (!getdvarint("iwz_survival_mode", 0) ||
        !isdefined(level.script) || level.script != "cp_disco")
        return;

    level.initial_active_volumes = ["disco_subway"];
    level.default_weapon = "iw7_g18c_zm";
    foreach (character in level.player_character_info)
        character.starting_weapon = level.default_weapon;
    level.getspawnpoint = ::subway_spawnpoint;
    level.force_respawn_location = ::subway_spawnpoint;
    if (isdefined(level.custom_onspawnplayer_func))
        level.iwz_subway_stock_onspawn = level.custom_onspawnplayer_func;
    level.custom_onspawnplayer_func = ::on_subway_spawn;

    level thread configure_subway_interactions();
    level thread configure_subway_spawning();
    level thread configure_subway_wheel();
    level thread enable_survival_double_pap();
    custom_scripts\cp\survival_perks::install_survival_quick_revive_hooks();
    // Logged ceramic wall normal is +Y; the board faces along -forward.
    level thread custom_scripts\cp\survival_perks::setup_perk_wall(
        (-2905.23, 3422, 554.262), (0, 1, 0), 270, "p7_cafe_wall_menu_05");
    survival_log("Subway Shuffle initialized initialVolume=disco_subway " +
        "spawn=(-2540.01,2963.56,253.999) switch=pf45_auto1205 " +
        "portal=pf143_auto19 gourd=(-2289,2534,301) " +
        "wheel=pf18_auto2 deathWish=(-2557.49,2745.64,276.273) " +
        "startingWeapon=iw7_g18c_zm perkWall=(-2905.23,3422,554.262)");
}

survival_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("SubwayShuffle", message);
}

disallow_directors_cut()
{
    return 0;
}

subway_spawnpoint(player)
{
    point = spawnstruct();
    point.origin = (-2540.01, 2963.56, 254.999);
    point.angles = (0, -115.013, 0);
    // The first trace is the primary spawn. The stock portal's four authored
    // landing spots provide co-op alternatives without guessing extra floors.
    if (!positionwouldtelefrag(point.origin))
        return point;

    return subway_portal_landing();
}

subway_portal_landing()
{
    // cp_disco_fast_travel::script_add_teleport_spots, pf143_auto19.
    locations = [(-2332,3146,266), (-2308,3146,266),
        (-2332,3122,266), (-2356,3146,266)];
    point = spawnstruct();
    point.angles = (0, 270, 0);
    for (attempt = 0; attempt < 40; attempt++)
    {
        foreach (origin in locations)
        {
            if (canspawn(origin) && !positionwouldtelefrag(origin))
            {
                point.origin = origin;
                return point;
            }
        }
        wait 0.05;
    }
    point.origin = locations[0];
    survival_log("landing fallback reason=all-authored-spots-occupied origin=" + point.origin);
    return point;
}

on_subway_spawn()
{
    if (isdefined(level.iwz_subway_stock_onspawn))
        self [[level.iwz_subway_stock_onspawn]]();
    if (getdvarint("scr_gameended", 0))
        return;

    // getspawnpoint handles initial placement; this also covers forced respawns
    // and map callbacks that supply their own origin after spawn selection.
    if (distance(self.origin, (-2540.01,2963.56,254.999)) > 2)
    {
        point = subway_spawnpoint(self);
        self dontinterpolate();
        self setorigin(point.origin);
        self setplayerangles(point.angles);
    }
    self.iwz_subway_travelling = 0;
    // This callback runs before the intro/loadout finishes. The player's
    // default_starting_pistol does not exist yet; log the configured weapon.
    survival_log("player spawned player=" + (self getentitynumber()) +
        " origin=" + self.origin + " scene=" + level.wave_num +
        " configuredStartingWeapon=" + level.default_weapon);
    self thread enable_subway_gourd_for_player();
}

configure_subway_spawning()
{
    level endon("game_ended");
    while (!scripts\engine\utility::flag_exist("init_spawn_volumes_done"))
        wait 0.05;
    scripts\engine\utility::flag_wait("init_spawn_volumes_done");
    disabled = [];
    foreach (volume in level.active_spawn_volumes)
    {
        if (isdefined(volume.basename) && volume.basename != "disco_subway")
            disabled[disabled.size] = volume.basename;
    }
    foreach (name in disabled)
        scripts\cp\zombies\zombies_spawning::deactivate_volume_by_name(name);
    scripts\cp\zombies\zombies_spawning::activate_volume_by_name("disco_subway");
    scripts\cp\zombies\zombie_entrances::enable_windows_in_area("disco_subway");
    survival_log("spawn volumes ready active=disco_subway disabled=" + disabled.size);
}

wait_for_interactions()
{
    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        wait 0.05;
    scripts\engine\utility::flag_wait("init_interaction_done");
}

configure_subway_interactions()
{
    level endon("game_ended");
    wait_for_interactions();
    // zombie_doors snapshots current_interaction_structs while initializing
    // each purchase trigger. Retiring a door before that snapshot leaves its
    // price/activation lookup empty. Wait for the actual completion flag.
    while (!scripts\engine\utility::flag_exist("doors_initialized"))
        wait 0.05;
    scripts\engine\utility::flag_wait("doors_initialized");
    disabled_switches = 0;
    disabled_exits = 0;
    foreach (interaction in level.all_interaction_structs)
    {
        if (isdefined(interaction.target) && interaction.target == "pf45_auto1205")
        {
            interaction.enabled = 0;
            scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
            disabled_switches++;
            survival_log("power switch disabled target=" + interaction.target +
                " origin=" + interaction.origin + " powerAreas=" + interaction.script_parameters);
        }
        // Both sides of the northern staircase share this barrier. Its lower
        // trigger is reachable beside the wheel even with the generator off.
        if (isdefined(interaction.target) && interaction.target == "pf24_auto766")
        {
            interaction.enabled = 0;
            scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
            disabled_exits++;
        }
    }
    disabled_triggers = 0;
    foreach (trigger in getentarray("door_buy", "targetname"))
    {
        if (isdefined(trigger.target) && trigger.target == "pf24_auto766")
        {
            trigger makeunusable();
            disabled_triggers++;
        }
    }
    survival_log("exit containment ready disabledSwitches=" + disabled_switches +
        " expected=1 power=off exitGates=stock-closed staircase=pf24_auto766 " +
        " disabledExitInteractions=" + disabled_exits + " disabledExitTriggers=" + disabled_triggers);

    // The refill station has no usable hint until a style is selected. Unlock
    // the same flag as Pam's first conversation, then retain stock cooldown,
    // inventory, gestures and progression. No later quest stages are skipped.
    while (!isdefined(level.all_gourds) ||
        !scripts\engine\utility::flag_exist("skq_phase_1"))
        wait 0.05;
    gourd = scripts\engine\utility::getclosest(
        (-2289,2534,301), level.all_gourds, 32);
    if (!isdefined(gourd))
    {
        survival_log("gourd setup failed reason=authored-station-missing");
        return;
    }
    scripts\engine\utility::flag_set("skq_phase_1");
    // Shaolin dispatches through the registered interaction type, not the
    // individual station's activation_func field.
    level.interactions["gourd_station"].activation_func = ::use_subway_gourd;
    level.iwz_subway_gourd = gourd;
    survival_log("gourd ready origin=" + gourd.origin +
        " style=tiger unlock=Scene-1 cost=stock cooldown=stock");
}

enable_subway_gourd_for_player()
{
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");
    while (!isdefined(level.iwz_subway_gourd) ||
        !isdefined(self.kung_fu_progression) || !isdefined(self.disabled_interactions) ||
        !isdefined(self.interaction_trigger))
        wait 0.05;
    if (!isdefined(self.kung_fu_progression.active_discipline))
    {
        self.kung_fu_progression.active_discipline = "tiger";
        self setclientomnvar("ui_intel_active_index", 3);
        self thread scripts\cp\maps\cp_disco\cp_disco_challenges::chi_challenge_activate(self);
    }
    scripts\cp\cp_interaction::add_to_current_interaction_list_for_player(
        level.iwz_subway_gourd, self);
    self scripts\cp\cp_interaction::refresh_interaction();
    self thread scripts\cp\maps\cp_disco\cp_disco::update_special_mode_for_player(self);
    survival_log("gourd enabled player=" + (self getentitynumber()) +
        " style=" + self.kung_fu_progression.active_discipline + " scene=" + level.wave_num);
}

use_subway_gourd(interaction, player)
{
    scripts\cp\maps\cp_disco\kung_fu_mode::usegourdstation(interaction, player);
    survival_log("gourd used player=" + (player getentitynumber()) +
        " hasGourd=" + scripts\engine\utility::is_true(player.has_gourd) +
        " cooldown=" + scripts\engine\utility::is_true(player.kung_fu_cooldown));
}

select_subway_wheel()
{
    scripts\cp\zombies\interaction_magicwheel::set_magic_wheel_starting_location("disco_subway");
    survival_log("wheel startup forced area=disco_subway reference=pf18_auto2");
}

configure_subway_wheel()
{
    level endon("game_ended");
    while (!isdefined(level._id_B163) || !level._id_B163.size)
        wait 0.05;
    foreach (wheel in level._id_B163)
    {
        while (!isdefined(wheel._id_10A03))
            wait 0.05;
    }
    while (!scripts\engine\utility::flag_exist("fire_sale"))
        wait 0.05;
    // Fifth trace hits the authored wheel front; pf18_auto2 is its sign brush.
    wheel = scripts\engine\utility::getclosest((-2452,3657,531), level._id_B163, 128);
    if (!isdefined(wheel) || !isdefined(wheel.area_name) || wheel.area_name != "disco_subway")
    {
        survival_log("wheel setup failed reason=authored-subway-wheel-missing");
        return;
    }
    level.iwz_subway_wheel = wheel;
    hold_subway_wheel();
    wheel thread prevent_wheel_relocation();
}

hold_subway_wheel()
{
    if (!isdefined(level.iwz_subway_wheel))
        return;
    wheel = level.iwz_subway_wheel;
    select_subway_wheel();
    scripts\cp\zombies\interaction_magicwheel::init_magic_wheel(wheel);
    level.current_active_wheel = wheel;
    survival_log("wheel active entity=" + (wheel getentitynumber()) +
        " origin=" + wheel.origin + " area=" + wheel.area_name +
        " base=" + (wheel getscriptablepartstate("base")) + " teddy=disabled");
}

prevent_wheel_relocation()
{
    level endon("game_ended");
    for (;;)
    {
        self waittill("ready");
        // Arcade Attack and Rave Rampage use the Fire Sale no-teddy counters.
        level._id_13D01 = 0;
        level._id_B162 = 0;
        survival_log("wheel spin complete relocationCounters=reset");
    }
}

setup_subway_portal()
{
    level endon("game_ended");
    wait_for_interactions();
    portal = scripts\engine\utility::getstruct("disco_subway", "script_noteworthy");
    if (!isdefined(portal) || !isdefined(portal.target) || portal.target != "pf143_auto19")
    {
        survival_log("portal setup failed reason=pf143_auto19-missing");
        return;
    }
    trigger = scripts\engine\utility::getclosest(portal.origin,
        getentarray("chi_door_fast_travel_portal_trigger", "targetname"), 128);
    door = scripts\engine\utility::getclosest(portal.origin,
        getentarray("chi_door_fast_travel", "targetname"), 128);
    spot = scripts\engine\utility::getclosest(portal.origin,
        scripts\engine\utility::getstructarray("chi_door_fast_travel_portal_spot", "targetname"), 128);
    exit = getent("hidden_room_portal", "targetname");
    destination = scripts\engine\utility::getstruct("hidden_room_spot", "targetname");
    if (!isdefined(trigger) || !isdefined(door) || !isdefined(spot) ||
        !isdefined(exit) || !isdefined(destination))
    {
        survival_log("portal setup failed reason=authored-door-trigger-or-pap-destination-missing");
        return;
    }
    symbol = scripts\engine\utility::getclosest(portal.origin,
        getentarray("chi_door_fast_travel_symbol", "targetname"), 128);
    // Preserve the authored door until the same kung-fu/shuriken strike that
    // opens a normal Shaolin chi door. The portal cannot be entered while shut.
    door setcandamage(1);
    door setcanradiusdamage(1);
    door.health = 10000000;
    survival_log("PaP door ready state=closed origin=" + door.origin +
        " opening=stock-kung-fu-or-shuriken");
    for (;;)
    {
        door waittill("damage", amount, attacker, direction, hit, means,
            model, part, tag, flags, weapon);
        if (scripts\cp\maps\cp_disco\cp_disco_fast_travel::is_shuriken(weapon) ||
            (isdefined(attacker) && isplayer(attacker) &&
            scripts\engine\utility::is_true(attacker.kung_fu_mode)))
            break;
        wait 0.05;
    }
    door hide();
    if (isdefined(symbol))
        symbol hide();
    visual = spawn("script_model", spot.origin + (0,0,53));
    visual.angles = portal.angles;
    visual setmodel("tag_origin_chi_portal");
    visual setscriptablepartstate("portal", "door_break");
    playsoundatpos(spot.origin, "cp_disco_doorbuy_wood_break");
    wait 1;
    // The trace hits Y=3188.5, facing -Y. Place the image two units behind
    // that plane and at the authored door's center height (floor+53).
    // vfx_rave_portal_02's image emitter has zero baked position offset.
    fx_origin = (spot.origin[0], 3190.5, spot.origin[2] + 53);
    portal.iwz_pap_fx = spawnfx(level._effect["iwz_subway_pap"],
        fx_origin, (0, -1, 0), (0, 0, 1));
    triggerfx(portal.iwz_pap_fx);
    survival_log("PaP door opened image=vfx_energy_rave_portal_paproom " +
        "effect=vfx_rave_portal_02 fxOrigin=" + fx_origin +
        " forward=(0,-1,0) doorwayInset=2 bakedImageOffset=0");
    level thread scripts\cp\maps\cp_disco\cp_disco::turn_on_room_exit_portal();
    survival_log("portal ready origin=" + portal.origin + " destination=" + destination.origin +
        " return=pf143_auto19 manualExit=enabled timer=stock-30s");
    for (;;)
    {
        trigger waittill("trigger", player);
        if (isdefined(player) && isplayer(player) && isalive(player) &&
            !scripts\cp\cp_laststand::player_in_laststand(player) &&
            !scripts\engine\utility::is_true(player.is_in_pap) &&
            !scripts\engine\utility::is_true(player.iwz_subway_travelling) &&
            player scripts\cp\utility::isteleportenabled())
        {
            // Stock pap_timer_start stays alive for 30 seconds after expiry.
            // Re-entering during that period would create a visitor with no
            // timer. Respect its cooldown before starting another visit.
            if (isdefined(player.pap_timer_running))
            {
                if (!isdefined(player.iwz_subway_cooldown_hint) ||
                    gettime() >= player.iwz_subway_cooldown_hint)
                {
                    player.iwz_subway_cooldown_hint = gettime() + 5000;
                    player iprintlnbold("Pack-a-Punch is cooling down");
                    survival_log("PaP entry waiting player=" + (player getentitynumber()) +
                        " reason=stock-timer-cooldown");
                }
                wait 0.05;
                continue;
            }
            player.iwz_subway_travelling = 1;
            portal thread enter_subway_pap(player);
        }
        wait 0.05;
    }
}

enter_subway_pap(player)
{
    level endon("game_ended");
    player endon("disconnect");
    survival_log("PaP entry player=" + (player getentitynumber()) + " from=" + player.origin);
    player thread scripts\cp\maps\cp_disco\cp_disco::disable_teleportation(
        player, 0.5, "fast_travel_complete");
    scripts\cp\maps\cp_disco\cp_disco::travel_through_hidden_tube(player);
    player.iwz_subway_travelling = 0;
    survival_log("PaP arrived player=" + (player getentitynumber()) + " origin=" + player.origin);
}

return_to_subway(player)
{
    point = subway_portal_landing();
    // The organized dump mislabels the native playershow as gold_teeth_pickup.
    // The second dump and IW7 method table identify the actual builtin.
    player playershow();
    player unlink();
    player dontinterpolate();
    player setorigin(point.origin);
    player setplayerangles(point.angles);
    player.disable_consumables = undefined;
    player scripts\cp\powers\coop_powers::power_enablepower();
    survival_log("PaP returned player=" + (player getentitynumber()) +
        " origin=" + player.origin + " timedExit=" + scripts\engine\utility::is_true(player.kicked_out));
}

enable_survival_double_pap()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("fuses_inserted") ||
        !isdefined(level.pap_max) ||
        !isdefined(level.player_pap_machines) ||
        !level.player_pap_machines.size)
    {
        scripts\engine\utility::waitframe();
    }

    previous_pap_max = level.pap_max;
    placed_fuses_before = scripts\engine\utility::is_true(
        level.placed_alien_fuses);

    // Like Rave Rampage, upgrade each player's private machine using the
    // map's stock fuse sequence. Shaolin has no pap_fixed flag to wait for.
    // placed_alien_fuses also upgrades clones created for later joiners.
    scripts\engine\utility::flag_set("fuses_inserted");
    level.placed_alien_fuses = 1;
    level.pap_max = 3;
    scripts\cp\maps\cp_disco\cp_disco_weapon_upgrade::
        upgrade_machine_for_all_players();
    scripts\cp\maps\cp_disco\cp_disco_weapon_upgrade::
        update_level_pap_machines("door", "close");
    wait(0.5);
    scripts\cp\maps\cp_disco\cp_disco_weapon_upgrade::
        update_level_pap_machines("machine", "upgraded");
    wait(0.25);
    scripts\cp\maps\cp_disco\cp_disco_weapon_upgrade::
        update_level_pap_machines("reels", "neutral");
    wait(0.25);
    scripts\cp\maps\cp_disco\cp_disco_weapon_upgrade::
        update_level_pap_machines("reels", "on");
    wait(0.25);
    scripts\cp\maps\cp_disco\cp_disco_weapon_upgrade::
        update_level_pap_machines("door", "open_idle");

    pap_machine = level.player_pap_machines[0];
    survival_log("double PaP enabled papMax=" + previous_pap_max + "->" +
        level.pap_max + " fusesInserted=" +
        scripts\engine\utility::flag("fuses_inserted") +
        " placedAlienFuses=" + placed_fuses_before + "->" +
        level.placed_alien_fuses + " machineCount=" +
        level.player_pap_machines.size + " model=" + pap_machine.model +
        " states=machine=" +
        (pap_machine getscriptablepartstate("machine")) + " reels=" +
        (pap_machine getscriptablepartstate("reels")) + " door=" +
        (pap_machine getscriptablepartstate("door")) +
        " activationPath=shaolin-fuses-and-player-clones");
}

// Preserve the authored train sequence and stock hazard helpers. Only its
// startup dependency changes: broadcasting power_on would also unlock exits.
survival_subway_trains()
{
    level endon("game_ended");
    front_car = spawn( "script_model", ( -2794, -3203, 191 ) );
    front_car.angles = ( 0, 0, 0 );
    scripts\engine\utility::waitframe();
    middle_car = spawn( "script_model", ( -2794, -3975, 191 ) );
    middle_car.angles = ( 0, 180, 0 );
    scripts\engine\utility::waitframe();
    rear_car = spawn( "script_model", ( -2794, -4747, 191 ) );
    rear_car.angles = ( 0, 0, 0 );
    scripts\engine\utility::waitframe();
    front_car setmodel( "cp_disco_subway_train_bsp2xmodel" );
    front_sound = spawn( "script_model", front_car.origin );
    middle_car setmodel( "cp_disco_subway_train_bsp2xmodel" );
    middle_sound = spawn( "script_model", middle_car.origin );
    rear_car setmodel( "cp_disco_subway_train_bsp2xmodel" );
    rear_sound = spawn( "script_model", rear_car.origin );
    scripts\engine\utility::waitframe();
    middle_car linkto( front_car );
    rear_car linkto( middle_car );
    while (!scripts\engine\utility::flag_exist("introscreen_over"))
        scripts\engine\utility::waitframe();
    scripts\engine\utility::flag_wait("introscreen_over");
    front_sound linkto( front_car, "tag_origin", ( 0, 420, 100 ), ( 0, 0, 0 ) );
    middle_sound linkto( middle_car, "tag_origin", ( -91, 0, 180 ), ( 0, 0, 0 ) );
    rear_sound linkto( rear_car, "tag_origin", ( 0, -420, 100 ), ( 0, 0, 0 ) );
    front_gates = getentarray( "subway_power_gates_front", "targetname" );
    rear_gates = getentarray( "subway_power_gates_rear", "targetname" );

    foreach ( gate in front_gates )
    {
        if ( gate.script_noteworthy == "left" )
        {
            gate rotateyaw( 90, 1 );
            playsoundatpos( gate.origin, "power_buy_subway_track_gate_open_left" );
        }
        else
            gate rotateyaw( -90, 1 );

        wait 0.15;
    }

    foreach ( gate in rear_gates )
    {
        if ( gate.script_noteworthy == "left" )
        {
            gate rotateyaw( 90, 1 );
            playsoundatpos( gate.origin, "power_buy_subway_track_gate_open_right" );
        }
        else
            gate rotateyaw( -90, 1 );

        wait 0.15;
    }

    front_far_lights = getscriptablearray( "train_lights_front_far", "targetname" );
    front_near_lights = getscriptablearray( "train_lights_front_near", "targetname" );
    back_near_lights = getscriptablearray( "train_lights_back_near", "targetname" );
    back_far_lights = getscriptablearray( "train_lights_back_far", "targetname" );

    foreach ( light in front_far_lights )
        light setscriptablepartstate( "root", "red" );

    foreach ( light in front_near_lights )
        light setscriptablepartstate( "root", "red" );

    wait 1;

    foreach ( light in back_near_lights )
        light setscriptablepartstate( "root", "red" );

    foreach ( light in back_far_lights )
        light setscriptablepartstate( "root", "red" );

    wait 1;
    survival_log("train enabled power=independent startup=intro-complete " +
        "trackGates=" + (front_gates.size + rear_gates.size) +
        " exitGates=closed damage=stock prePassWait=30");

    for (;;)
    {
        wait 1;
        front_car.origin = ( -2794, -3203, 192 );
        scripts\cp\maps\cp_disco\cp_disco_ghost_activation::try_set_up_skull_in_front_of_train( front_car );
        scripts\engine\utility::waitframe();
        front_car setscriptablepartstate( "root", "front_fx" );
        rear_car setscriptablepartstate( "root", "rear_fx" );
        scripts\engine\utility::waitframe();
        front_car setscriptablepartstate( "sparks", "on" );
        middle_car setscriptablepartstate( "sparks", "on" );
        rear_car setscriptablepartstate( "sparks", "on" );
        wait 30;
        survival_log("train pass started scene=" + level.wave_num +
            " origin=" + front_car.origin + " travelSeconds=12 damage=stock");
        level thread scripts\cp\maps\cp_disco\cp_disco::watch_for_train_player_damage( front_car, middle_car, rear_car );
        level thread scripts\cp\maps\cp_disco\cp_disco::watch_for_train_zombie_damage( front_car, middle_car, rear_car );
        level thread scripts\cp\maps\cp_disco\cp_disco::train_light_sequence();
        front_car movey( front_car.origin[1] + 14000, 12 );
        level thread scripts\cp\maps\cp_disco\cp_disco::rumble_quake_subway();
        wait 2;
        playsoundatpos( ( -2815, 1982, 314 ), "train_trap_horn_blast" );
        wait 2;
        front_sound playsoundonmovingent( "train_trap_passby_front" );
        wait 1;
        middle_sound playsoundonmovingent( "train_trap_passby_middle" );
        wait 1;
        rear_sound playsoundonmovingent( "train_trap_passby_back" );
        wait 2;
        playsoundatpos( ( -2772, 3459, 314 ), "train_trap_away_tunnel" );
        wait 2;
        level notify( "stop_rumble_quake" );
        earthquake( 0.18, 3, ( -2808, 2680, 204 ), 784 );
        wait 5;
        scripts\engine\utility::waitframe();
        front_car setscriptablepartstate( "root", "off" );
        rear_car setscriptablepartstate( "root", "off" );
        scripts\engine\utility::waitframe();
        front_car setscriptablepartstate( "sparks", "off" );
        middle_car setscriptablepartstate( "sparks", "off" );
        rear_car setscriptablepartstate( "sparks", "off" );
        scripts\engine\utility::waitframe();
        front_car moveto( front_car.origin + ( 0, 0, -300 ), 0.1 );
        front_car waittill( "movedone" );
        front_car moveto( ( -2794, -3203, -108 ), 0.1 );
        front_car waittill( "movedone" );
    }
}
