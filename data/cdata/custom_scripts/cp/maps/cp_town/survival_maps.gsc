main()
{
    if (!getdvarint("iwz_survival_mode", 0) || getdvar("ui_mapname") != "cp_town")
        return;

    precacheitem("iw7_udm45_zm");
    precacheitem("iw7_cutie_zm+cutiecrank+cutiegrip+cutieplunger");
    precachemodel("tag_origin_portal");
    precachemodel("town_magic_wheel");
    precachemodel("town_magic_wheel_on");
    precachemodel("zmb_magic_wheel_spinner");
    precachemodel("cp_rave_woodboard_01");
    precachemodel("cp_disco_street_barricade");
    custom_scripts\cp\survival_perks::precache_perk_wall("p7_cafe_wall_menu_01");
    replacefunc(scripts\cp\zombies\zombies_spawning::_id_7CE3,
        ::get_survival_volume_spawners);
    replacefunc(scripts\cp\zombies\zombies_spawning::get_scored_goon_spawn_location,
        ::get_beach_crog_landing);
    // cp_town_boss_spawn uses its own copy of the goon selector, unlike eggs.
    replacefunc(scripts\cp\zombies\cp_town_spawning::get_scored_goon_spawn_location,
        ::get_beach_crog_landing);
    replacefunc(scripts\cp\zombies\cp_town_spawning::move_to_spot,
        ::place_beach_brute);
    replacefunc(scripts\cp\maps\cp_town\cp_town::cp_town_should_run_event,
        ::should_run_beach_event);
    replacefunc(scripts\cp\maps\cp_town\cp_town::rebalance_pillage_after_wave,
        ::keep_batteries_disabled);
    replacefunc(scripts\cp\maps\cp_town\cp_town_interactions::init_papanomaly,
        ::setup_beach_portal);
    replacefunc(scripts\cp\maps\cp_town\cp_town_interactions::get_valid_pap_return_spot,
        ::beach_pap_return_spots);
    // The fuse-button detour goes outside the survival area. Double PaP is
    // supplied directly, so this quest-only switch has no survival action.
    replacefunc(scripts\cp\maps\cp_town\cp_town_interactions::usepapfuseswitch,
        ::ignore_fuse_switch);
    replacefunc(scripts\cp\maps\cp_town\cp_town::init_magic_wheel,
        ::select_beach_wheel);
    replacefunc(scripts\cp\zombies\interaction_magicwheel::_id_BC3F,
        ::hold_beach_wheel);
    replacefunc(scripts\cp\zombies\directors_cut::allow_directors_cut,
        ::disallow_directors_cut);
    replacefunc(scripts\cp\maps\cp_town\cp_town::watchforpowerontriggers,
        ::configure_full_color);
    replacefunc(scripts\cp\maps\cp_town\cp_town::colorize_sound_state_change,
        ::full_color_sound_state);
    replacefunc(scripts\cp\maps\cp_town\cp_town_elvira::init_elvira_beach,
        ::setup_survival_elvira);
    survival_log("pre-load hooks installed map=cp_town portal=permanent-beach " +
        "papReturn=beach directorsCut=disabled color=full elvira=beach-pedestal " +
        "specialRounds=stock-without-tent-gate crogLandings=inside-barriers " +
        "bruteSpawns=inside-barriers-grounded batteries=disabled");
}

post_load()
{
    if (!getdvarint("iwz_survival_mode", 0) ||
        !isdefined(level.script) || level.script != "cp_town")
        return;

    level.initial_active_volumes = ["bridge_beach"];
    level.default_weapon = "iw7_udm45_zm";
    level.nextwheelweaponfunc = ::beach_wheelnextweapon;
    configure_full_color();
    foreach (character in level.player_character_info)
        character.starting_weapon = level.default_weapon;
    level.getspawnpoint = ::beach_spawnpoint;
    // cp_globallogic otherwise snaps this measured location to the navmesh.
    level.disable_start_spawn_on_navmesh = 1;
    level.force_respawn_location = ::beach_spawnpoint;
    level.iwz_beach_stock_onspawn = level.custom_onspawnplayer_func;
    level.custom_onspawnplayer_func = ::on_beach_spawn;
    level thread configure_beach();
    level thread configure_beach_wheel();
    level thread enable_survival_double_pap();
    custom_scripts\cp\survival_perks::install_survival_quick_revive_hooks();
    level thread setup_freestanding_perks();
    survival_log("Beach Bloodbath initialized startingWeapon=iw7_udm45_zm " +
        "spawn=(2834.67,1404.46,-94.0585) deathWish=(3123.71,2199.78,-45.2184) " +
        "wheelTrace=(2307.26,2521.61,-6.31389) madParts=crank-grip-plunger perks=freestanding " +
        "portal=(2555.31,3025.22,-180.442)");
}

survival_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("BeachBloodbath", message);
}

disallow_directors_cut()
{
    return 0;
}

ignore_fuse_switch(interaction, player)
{
    survival_log("PaP fuse detour suppressed player=" + (player getentitynumber()));
}

beach_spawnpoint(player)
{
    // Revised first trace: open sand, with the recorded view yaw.
    return beach_landing((2834.67,1404.46,-93.0585), 74.7677);
}

beach_landing(origin, yaw)
{
    level endon("game_ended");
    point = spawnstruct();
    point.angles = (0,yaw,0);
    offsets = [(0,0,0), (48,0,0), (-48,0,0), (0,48,0), (0,-48,0),
        (48,48,0), (-48,-48,0), (48,-48,0), (-48,48,0)];
    for (;;)
    {
        foreach (offset in offsets)
        {
            // Co-op offsets are grounded and collision-checked at runtime.
            candidate = scripts\engine\utility::drop_to_ground(origin + offset, 48, -96) + (0,0,1);
            if (abs(candidate[2] - origin[2]) <= 48 && canspawn(candidate) &&
                !positionwouldtelefrag(candidate))
            {
                point.origin = candidate;
                return point;
            }
        }
        wait 0.05;
    }
}

on_beach_spawn()
{
    if (isdefined(level.iwz_beach_stock_onspawn))
        self [[level.iwz_beach_stock_onspawn]]();
    if (getdvarint("scr_gameended", 0))
        return;
    self.iwz_beach_travelling = 0;
    self visionsetnakedforplayer("cp_town_color", 0);
    self setclientomnvar("zm_ui_dialpad_9", 2);
    survival_log("player spawned player=" + (self getentitynumber()) +
        " origin=" + self.origin + " configuredStartingWeapon=" + level.default_weapon +
        " vision=cp_town_color filmGrain=off");
}

configure_full_color()
{
    level.current_vision_set = "cp_town_color";
    level.vision_set_override = level.current_vision_set;
    level.film_grain_off = 1;
    setglobalsoundcontext("color", "full", 0);
    full_color_sound_state();
    survival_log("full color configured vision=cp_town_color startupAreaRequirement=removed");
}

full_color_sound_state(state, duration)
{
    // Also handles the stock delayed fullblackandwhite call at three seconds.
    setaudiotriggerstate("worldcolorstate", "color", 0);
    setglobalsoundcontext("color", "full", 0);
}

wait_for_flag(name)
{
    while (!scripts\engine\utility::flag_exist(name))
        wait 0.05;
    scripts\engine\utility::flag_wait(name);
}

should_run_beach_event(wave)
{
    // Preserve Attack's special-round cadence and its stock Crog/Max Ammo
    // handler. Opening Elvira's tent is impossible inside the survival area.
    if (wave < 5)
        return 0;
    gap = wave - level.last_event_wave;
    if (gap < 5)
        return 0;
    chance = (gap - 4) / 3 * 100;
    roll = randomint(100);
    selected = roll < chance;
    survival_log("special round check wave=" + wave + " lastEventWave=" +
        level.last_event_wave + " chance=" + chance + " roll=" + roll +
        " selected=" + selected + " type=crab_mini reward=stock-ammo_max");
    return selected;
}

keep_batteries_disabled(wave)
{
    // pillage_init registers Battery at weight zero. Its delayed rebalance is
    // the only path that raises that weight; retain the initial useful drops.
    survival_log("Battery drop rebalance suppressed scheduledWave=" + wave +
        " batteryWeight=0 clipWeight=33 explosiveWeight=33 moneyWeight=34");
}

get_beach_crog_landing()
{
    level endon("game_ended");
    level endon("force_spawn_wave_done");
    waiting = 0;
    for (;;)
    {
        points = [];
        excluded = 0;
        // Crogs use the active dog_spawner list, not normal volume.spawners.
        // launch_egg_sac snaps the destination onto navmesh before flight.
        foreach (point in level._id_162C)
        {
            if (!scripts\engine\utility::is_true(point.active) ||
                scripts\engine\utility::is_true(point.in_use))
                continue;
            landing = getclosestpointonnavmesh(point.origin);
            if (!isdefined(point.volume) || point.volume.basename != "bridge_beach" ||
                !isdefined(landing) || !ispointinvolume(landing, point.volume) ||
                vectordot(landing - (2680,645,0), (2,100,0)) < 0)
            {
                excluded++;
                continue;
            }
            points[points.size] = point;
        }
        if (points.size)
        {
            // Preserve stock distance/cooldown scoring and random fallback,
            // but both paths must draw from the validated landing points.
            point = scripts\cp\zombies\zombies_spawning::_id_8456(points);
            if (!isdefined(point))
                point = scripts\engine\utility::random(points);
            survival_log("Crog landing selected authored=" + point.origin +
                " landing=" + getclosestpointonnavmesh(point.origin) +
                " eligible=" + points.size + " excluded=" + excluded);
            return point;
        }
        if (!waiting)
            survival_log("Crog landing waiting: no free in-bounds landing points excluded=" + excluded);
        waiting = 1;
        wait 0.1;
    }
}

place_beach_brute(point)
{
    // Stock move_to_spot computes this navmesh position but discards it,
    // placing the Brute at the elevated/offset authored dog_spawner instead.
    // Use the same final position validated by get_beach_crog_landing.
    landing = getclosestpointonnavmesh(point.origin);
    self dontinterpolate();
    self setorigin(landing, 1);
    self scragentsetgoalpos(landing);
    self.ignoreall = 0;
    survival_log("Crog Brute placed entity=" + (self getentitynumber()) +
        " authored=" + point.origin + " landing=" + landing +
        " volume=" + point.volume.basename + " barrierSide=inside");
}

get_survival_volume_spawners()
{
    // Stock _id_7CE3 supplies the volume's permanent spawner list before it
    // is activated. Preserve entity/struct lookup and existing remove_me flags.
    if (!isdefined(self.target))
        return undefined;
    points = getentarray(self.target, "targetname");
    if (!isdefined(points) || !points.size)
        points = scripts\engine\utility::getstructarray(self.target, "targetname");
    result = [];
    removed = 0;
    foreach (point in points)
    {
        if (isdefined(point.remove_me))
            continue;
        // The barricade pair lies on the line through (2630,646) and
        // (2730,644). Spawn and all beach services are on its north side.
        // bridge_beach also contains nine authored spawns south of this line.
        if (self.target == "bridge_beach_spawn" &&
            vectordot(point.origin - (2680,645,0), (2,100,0)) < 0)
        {
            survival_log("outside boss barrier spawner excluded origin=" + point.origin);
            removed++;
            continue;
        }
        // Authored ground entrance directly beneath the new Magic Wheel.
        if (self.target == "bridge_beach_spawn" &&
            distancesquared(point.origin, (2323.7,2508.7,-7.1)) < 1)
        {
            survival_log("Magic Wheel ground spawner excluded origin=" + point.origin);
            removed++;
            continue;
        }
        result[result.size] = point;
    }
    if (self.target == "bridge_beach_spawn")
        survival_log("beach spawner list filtered kept=" + result.size + " excluded=" + removed +
            " expectedKept=24 expectedExcluded=10 boundary=boss-barrier-plane wheelSpawn=excluded");
    return result;
}

configure_beach()
{
    level endon("game_ended");
    setup_beach_boss_barriers();
    wait_for_flag("init_spawn_volumes_done");
    disabled = [];
    foreach (volume in level.active_spawn_volumes)
    {
        if (isdefined(volume.basename) && volume.basename != "bridge_beach")
            disabled[disabled.size] = volume.basename;
    }
    foreach (name in disabled)
        scripts\cp\zombies\zombies_spawning::deactivate_volume_by_name(name);
    scripts\cp\zombies\zombies_spawning::activate_volume_by_name("bridge_beach");
    scripts\cp\zombies\zombie_entrances::enable_windows_in_area("bridge_beach");
    survival_log("spawn volumes ready active=bridge_beach disabled=" + disabled.size);

    wait_for_flag("init_interaction_done");
    wait_for_flag("doors_initialized");
    // Decoded cp_town entity records: both sides of all four area exits.
    exits = ["pf1316_auto1205", "pf1316_auto1206", "pf1316_auto663", "pf1316_auto666"];
    count = 0;
    foreach (interaction in level.all_interaction_structs)
    {
        if (isdefined(interaction.target) &&
            scripts\engine\utility::array_contains(exits, interaction.target))
        {
            interaction.enabled = 0;
            scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
            count++;
        }
    }
    triggers = 0;
    foreach (trigger in getentarray("door_buy", "targetname"))
    {
        if (isdefined(trigger.target) &&
            scripts\engine\utility::array_contains(exits, trigger.target))
        {
            trigger makeunusable();
            triggers++;
        }
    }
    survival_log("exits locked interactions=" + count + " expected=8 triggers=" +
        triggers + " expected=4 collision=stock-closed");
}

setup_beach_boss_barriers()
{
    if (isdefined(level.iwz_beach_boss_barriers))
        return;

    // Second new trace (186650) matches the two death-wall barricades at
    // (2730,644,-30) and (2630,646,-26), including their authored terrain tilt.
    // The stock final-sequence function also raises a compound clip brush
    // across other beach paths. Use only this pair and their model physics.
    requested = (2693.18,661.246,-25.8831);
    placements = [];
    foreach (point in scripts\engine\utility::getstructarray("death_wall_door_model", "targetname"))
    {
        if (distance(point.origin, requested) < 128)
            placements[placements.size] = point;
    }
    if (placements.size != 2)
    {
        survival_log("boss barrier setup failed requested=" + requested +
            " reason=authored-pair-missing found=" + placements.size + " expected=2");
        return;
    }

    level.iwz_beach_boss_barriers = [];
    foreach (point in placements)
    {
        barrier = spawn("script_model", point.origin);
        barrier.angles = point.angles;
        barrier setmodel("cp_disco_street_barricade");
        barrier setnonstick(1);
        barrier solid();
        previous_contents = barrier setcontents(8321);
        level.iwz_beach_boss_barriers[level.iwz_beach_boss_barriers.size] = barrier;
        survival_log("boss barrier ready origin=" + barrier.origin + " angles=" + barrier.angles +
            " model=" + barrier.model + " contents=" + previous_contents +
            "->8321 collision=entity-and-physics-worlds purchasable=0");
    }
    survival_log("boss barrier pair enabled requested=" + requested +
        " count=2 source=death_wall_door_model bossFight=inactive");
}

setup_beach_portal()
{
    level endon("game_ended");
    level.secretpapstructs = [];
    scripts\engine\utility::flag_init("pap_portal_used");
    wait_for_flag("interactions_initialized");
    foreach (stock in scripts\engine\utility::getstructarray("fast_travel_panel", "script_noteworthy"))
        scripts\cp\cp_interaction::remove_from_current_interaction_list(stock);

    portal = spawnstruct();
    portal.origin = (2555.31,3025.22,-180.442);
    // All three stock Attack panels use -90 roll for this portal model.
    portal.angles = (0,282.541,-90);
    portal.name = "iwz_beach_pap";
    portal.script_noteworthy = portal.name;
    portal.script_parameters = "";
    portal.cost = 0;
    portal.spend_type = "null";
    portal.enabled = 1;
    portal.powered_on = 1;
    portal.requires_power = 0;
    portal.custom_search_dist = 96;
    portal.hint_func = ::beach_portal_hint;
    portal.activation_func = ::enter_beach_pap;
    portal.teleporter_active = 1;
    portal.revealed = 1;
    portal.model = spawn("script_model", portal.origin + (0,0,40));
    portal.model.angles = portal.angles;
    portal.model setmodel("tag_origin_portal");
    portal.model setscriptablepartstate("portal", "on");
    level.interactions[portal.name] = portal;
    level.secretpapstructs = [portal];
    level.active_pap_teleporter = portal;
    // Elvira must not try to reveal a portal that Survival already opened.
    level.anomaly_revealed = 1;
    level.iwz_beach_portal = portal;
    scripts\cp\cp_interaction::add_to_current_interaction_list(portal);
    survival_log("PaP portal ready surface=" + portal.origin + " modelOrigin=" +
        portal.model.origin + " angles=" + portal.angles +
        " model=tag_origin_portal state=portal/on timer=stock-30s return=beach");
}

beach_portal_hint(interaction, player)
{
    if (scripts\engine\utility::is_true(player.iwz_beach_travelling) ||
        isdefined(player.pap_timer_running))
        return &"COOP_INTERACTIONS_COOLDOWN";
    return &"CP_TOWN_INTERACTIONS_HIDDEN_TELEPORT";
}

enter_beach_pap(interaction, player)
{
    level endon("game_ended");
    player endon("disconnect");
    if (!isalive(player) || scripts\cp\cp_laststand::player_in_laststand(player) ||
        scripts\engine\utility::is_true(player.isrewinding) ||
        scripts\engine\utility::is_true(player.playing_game) ||
        scripts\engine\utility::is_true(player.is_in_pap) ||
        scripts\engine\utility::is_true(player.iwz_beach_travelling) ||
        isdefined(player.pap_timer_running) || !(player scripts\cp\utility::isteleportenabled()))
        return;
    player.iwz_beach_travelling = 1;
    survival_log("PaP entry player=" + (player getentitynumber()) + " from=" + player.origin);
    scripts\cp\maps\cp_town\cp_town_interactions::teleporttopaproom(player, interaction);
    player.iwz_beach_travelling = 0;
    survival_log("PaP arrived player=" + (player getentitynumber()) + " origin=" + player.origin);
}

beach_pap_return_spots(interaction, return_array)
{
    // Return to the measured player spawn, safely away from portal use range.
    point = beach_spawnpoint();
    survival_log("PaP return selected origin=" + point.origin + " destination=beach");
    if (scripts\engine\utility::is_true(return_array))
        return [point];
    return point;
}

enable_survival_double_pap()
{
    level endon("game_ended");
    while (!scripts\engine\utility::flag_exist("fuses_inserted") ||
        !isdefined(level.pap_max) || !isdefined(level.player_pap_machines) ||
        !level.player_pap_machines.size)
        wait 0.05;
    scripts\engine\utility::flag_set("fuses_inserted");
    level.placed_alien_fuses = 1;
    level.pap_max = 3;
    scripts\cp\maps\cp_town\cp_town_weapon_upgrade::upgrade_machine_for_all_players();
    scripts\cp\maps\cp_town\cp_town_weapon_upgrade::update_level_pap_machines("machine", "upgraded");
    scripts\cp\maps\cp_town\cp_town_weapon_upgrade::update_level_pap_machines("reels", "on");
    scripts\cp\maps\cp_town\cp_town_weapon_upgrade::update_level_pap_machines("door", "open_idle");
    survival_log("double PaP ready fusesInserted=1 placedAlienFuses=1 papMax=3 machines=" +
        level.player_pap_machines.size);
}

select_beach_wheel()
{
    // Stage an authored wheel until shared initialization has built its spinner.
    scripts\cp\zombies\interaction_magicwheel::set_magic_wheel_starting_location("camp_transition");
}

beach_wheelnextweapon(wheel, weapon, player)
{
    // Keep Attack's roll and ownership checks. Assemble only a selected M.A.D.
    weapon = scripts\cp\maps\cp_town\cp_town::town_wheelnextweapon(wheel, weapon, player);
    if (weapon != "iw7_cutie_zm")
        return weapon;

    assembled = "iw7_cutie_zm+cutiecrank+cutiegrip+cutieplunger";
    // The spinner finds the selected weapon by exact string in this list.
    // Replace its entry in place; stock rebuilds the list after every spin.
    foreach (index, entry in wheel._id_13C25)
    {
        if (entry == weapon)
            wheel._id_13C25[index] = assembled;
    }
    survival_log("M.A.D. wheel reward assembled player=" + (player getentitynumber()) +
        " weapon=" + assembled + " parts=3 selection=stock");
    return assembled;
}

configure_beach_wheel()
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

    wheel = undefined;
    foreach (candidate in level._id_B163)
    {
        if (isdefined(candidate.area_name) && candidate.area_name == "camp_transition")
            wheel = candidate;
    }
    if (!isdefined(wheel))
    {
        survival_log("wheel setup failed reason=camp-transition-controller-missing");
        return;
    }
    // Revised third trace hit the previous jar's plastic lid. That jar now
    // lives at trace two; ground the new cabinet at this exact X/Y instead.
    target = scripts\engine\utility::drop_to_ground(
        (2307.26,2521.61,-6.31389), 32, -128) + (0,0,0.15);
    probe = spawnstruct();
    probe.origin = target;
    if (scripts\cp\zombies\interaction_magicwheel::get_area(probe) != "bridge_beach")
    {
        survival_log("wheel setup failed reason=revised-point-outside-beach origin=" + target);
        return;
    }

    source_origin = wheel.origin;
    source_angles = wheel.angles;
    // The playtest showed the cabinet's back at the approach. Rotate the
    // whole assembly, including spinner, controller and FX, toward the player.
    target_angles = (0,229.5211,0);
    visual = spawn("script_model", target);
    visual.angles = target_angles;
    // Authored scriptable controllers report an empty .model. Like Rave,
    // explicitly create a new cabinet using the map's actual XModel asset.
    // cp_town.csv entries 26081/26083 identify these two cabinet models.
    visual setmodel("town_magic_wheel");
    visual setnonstick(1);
    visual solid();
    // Keep the stock model mask and add PLAYERCLIP, not SOLID: the separate
    // visible cabinet must block players without occluding Use traces to
    // the hidden wheel controller. Both physics worlds receive this mask.
    wheel_contents = 8320 | physics_createcontents(["physicscontents_playerclip"]);
    previous_contents = visual setcontents(wheel_contents);
    spinner = spawn("script_model", transform_wheel_point(wheel._id_10A03.origin,
        source_origin, source_angles, target, target_angles));
    spinner.angles = (wheel._id_10A03.angles[0],
        wheel._id_10A03.angles[1] + target_angles[1] - source_angles[1],
        wheel._id_10A03.angles[2]);
    spinner setmodel("zmb_magic_wheel_spinner");
    fx_spot = scripts\engine\utility::getclosest(source_origin,
        scripts\engine\utility::getstructarray("wheel_fx_spot", "targetname"));
    if (isdefined(fx_spot))
    {
        fx_spot.origin = transform_wheel_point(fx_spot.origin,
            source_origin, source_angles, target, target_angles);
        if (isdefined(fx_spot.angles))
            fx_spot.angles = (fx_spot.angles[0],
                fx_spot.angles[1] + target_angles[1] - source_angles[1], fx_spot.angles[2]);
    }
    foreach (authored in level._id_B163)
    {
        authored notify("delete_wheel");
        authored makeunusable();
        authored setscriptablepartstate("base", "off");
        authored setscriptablepartstate("fx", "off");
        authored._id_10A03 setscriptablepartstate("spinner", "off");
    }
    // As in Rave, the authored scriptable is only a hidden logic controller.
    // The cabinet and spinner above are entirely new entities on the beach.
    wheel.origin = target;
    wheel.angles = target_angles;
    wheel.area_name = "bridge_beach";
    wheel._id_10A03 = spinner;
    wheel.iwz_beach_visual = visual;
    level._id_B163 = [wheel];
    level._id_B160 = ["bridge_beach"];
    level.iwz_beach_wheel = wheel;
    wheel thread scripts\cp\zombies\interaction_magicwheel::_id_13643();
    hold_beach_wheel();
    wheel thread prevent_beach_wheel_teddy();
    survival_log("new wheel assembly ready controllerSource=" + source_origin + " target=" + target +
        " angles=" + target_angles + " model=" + visual.model +
        " spinnerOrigin=" + spinner.origin + " contents=" + previous_contents +
        "->" + wheel_contents + " collision=playerclip useTrace=unobstructed " +
        "cost=950 fireSale=10 relocation=disabled");
}

transform_wheel_point(point, origin, angles, target, target_angles)
{
    delta = point - origin;
    yaw = target_angles[1] - angles[1];
    return target + (delta[0] * cos(yaw) - delta[1] * sin(yaw),
        delta[0] * sin(yaw) + delta[1] * cos(yaw), delta[2]);
}

hold_beach_wheel()
{
    if (!isdefined(level.iwz_beach_wheel))
        return;
    wheel = level.iwz_beach_wheel;
    scripts\cp\zombies\interaction_magicwheel::set_magic_wheel_starting_location("bridge_beach");
    wheel setscriptablepartstate("base", "off");
    wheel setscriptablepartstate("fx", "off");
    wheel._id_10A03 setscriptablepartstate("spinner", "idle");
    wheel makeusable();
    wheel _meth_84A7("tag_use");
    wheel setusefov(60);
    wheel setuserange(72);
    if (scripts\engine\utility::flag("fire_sale"))
        wheel sethintstring(&"COOP_INTERACTIONS_SPIN_WHEEL_FIRE_SALE");
    else if (isdefined(level.magic_wheel_spin_hint))
        wheel sethintstring(level.magic_wheel_spin_hint);
    else
        wheel sethintstring(&"CP_ZMB_INTERACTIONS_SPIN_WHEEL");
    level.current_active_wheel = wheel;
    survival_log("wheel active origin=" + wheel.origin +
        " area=bridge_beach usable=1 hint=stock-normal-or-fire-sale range=72 fov=60");
}

prevent_beach_wheel_teddy()
{
    level endon("game_ended");
    for (;;)
    {
        self waittill("ready");
        level._id_13D01 = 0;
        level._id_B162 = 0;
        survival_log("wheel spin complete relocationCounters=reset");
    }
}

setup_freestanding_perks()
{
    level endon("game_ended");
    wait_for_flag("init_interaction_done");
    yaw = 7.69618;
    normal = anglestoforward((0,yaw,0)) * -1;
    // Search near the replacement trace, facing the recorded approach.
    requested = (3635.7,2284.01,-147.332);
    ground = find_perk_display_ground(requested, yaw);
    if (!isdefined(ground))
    {
        survival_log("perk display setup failed requested=" + requested + " reason=no-clear-nearby-display-space");
        return;
    }
    custom_scripts\cp\survival_perks::setup_perk_wall(
        ground + (0,0,46) - normal * 4, normal, yaw, "p7_cafe_wall_menu_01");

    // Measured XModel bounds: menu half-height 27.869, half-width 15.039;
    // woodboard_01 half-length 90.9765, half-width 6.72, half-depth 1.973.
    // Two full-size stakes are planted in the sand behind the menu. Their
    // tops stop below the menu frame; no model scaling or wall contact.
    right = anglestoright((0,yaw,0));
    foreach (side in [-1,1])
    {
        stake = spawn("script_model", ground - normal * 3 + right * (side * 8) +
            (0,0,46 + 27.869 - 1 - 90.9765));
        stake.angles = (90,yaw,0);
        stake setmodel("cp_rave_woodboard_01");
        stake setnonstick(1);
        stake solid();
        stake setcontents(8321);
    }
    survival_log("freestanding perks ready requested=" + requested + " ground=" + ground +
        " boardOrigin=" + level.iwz_survival_perk_board.origin +
        " yaw=" + yaw + " support=two-planted-wooden-stakes faceClearance=verified " +
        " perks=" + level.perk_purchase_structs.size);
}

find_perk_display_ground(requested, yaw)
{
    normal = anglestoforward((0,yaw,0)) * -1;
    right = anglestoright((0,yaw,0));
    candidates = [requested];
    // Expanding rings favor the open beach in front of the rocks. Static
    // traces ignore passing players/zombies, which must not hide the stand.
    foreach (radius in [32,64,96,128])
    {
        foreach (direction in [normal, (normal + right) * 0.707107,
            (normal - right) * 0.707107, right, right * -1])
            candidates[candidates.size] = requested + direction * radius;
    }
    // This nearby sand point already supported the full display in playtests.
    candidates[candidates.size] = (3551.79,2217.58,-152.151);
    bad_ground = 0;
    obstructed = 0;
    foreach (candidate in candidates)
    {
        floor_trace = bullettrace(candidate + (0,0,48), candidate - (0,0,64), 0, undefined);
        if (!isdefined(floor_trace) || floor_trace["fraction"] >= 1 ||
            floor_trace["normal"][2] < 0.9 || floor_trace["surfacetype"] != "sand")
        {
            bad_ground++;
            continue;
        }
        ground = floor_trace["position"];
        // A player spawn hull at ground+1 is not the stand's footprint and
        // can intersect sloping sand. Validate the board and approach space.
        if (!perk_display_is_clear(ground, yaw))
        {
            obstructed++;
            continue;
        }
        survival_log("perk display site selected requested=" + requested + " ground=" + ground +
            " distance=" + distance(requested, ground) + " rejectedGround=" + bad_ground +
            " rejectedDisplay=" + obstructed + " clearance=static-display-traces");
        return ground;
    }
    survival_log("perk display search exhausted candidates=" + candidates.size +
        " rejectedGround=" + bad_ground + " rejectedDisplay=" + obstructed);
    return undefined;
}

perk_display_is_clear(ground, yaw)
{
    normal = anglestoforward((0,yaw,0)) * -1;
    right = anglestoright((0,yaw,0));
    foreach (height in [17,46,75])
    {
        foreach (side in [-16,0,16])
        {
            point = ground + (0,0,height) + right * side;
            trace = bullettrace(point + normal * 32, point - normal * 8, 0, undefined);
            if (!isdefined(trace) || trace["fraction"] < 1)
                return 0;
        }
    }
    return 1;
}

setup_survival_elvira()
{
    level endon("game_ended");
    interaction = scripts\engine\utility::getstruct("elvira_beach", "script_noteworthy");
    if (!isdefined(interaction))
    {
        survival_log("Elvira setup failed reason=authored-beach-interaction-missing");
        return;
    }
    scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
    wait_for_flag("init_interaction_done");
    // init_elvira creates the couch actor and hides the spellbook after ten
    // seconds. Finish that setup before showing the book at its beach stand.
    while (!isdefined(level.elvira) || !isdefined(level.elvira_spellbook))
        wait 0.05;
    scripts\engine\utility::waitframe();
    book = level.elvira_spellbook;
    stand = getent("elvira_bookstand", "targetname");
    book_spot = scripts\engine\utility::getstruct("elvira_beach_book", "targetname");
    stand_spot = scripts\engine\utility::getstruct("elvira_beach_bookstand", "targetname");
    spawn_spot = scripts\engine\utility::getstruct("elvira_spawn_beach", "targetname");
    if (!isdefined(interaction) || !isdefined(stand) || !isdefined(book_spot) ||
        !isdefined(stand_spot) || !isdefined(spawn_spot))
    {
        survival_log("Elvira setup failed reason=authored-beach-pedestal-parts-missing");
        return;
    }
    book.origin = book_spot.origin;
    book.angles = book_spot.angles;
    book show();
    stand.origin = stand_spot.origin;
    stand.angles = stand_spot.angles;
    stand show();
    level.elvira_spawn_struct = spawn_spot;
    book_fx = spawnfx(level._effect["vfx_cp_town_book_idle"], book.origin + (0,0,10),
        anglestoforward(book.angles), anglestoup(book.angles));
    triggerfx(book_fx);
    level.interactions["elvira_beach"].hint_func = ::survival_elvira_hint;
    level.interactions["elvira_beach"].activation_func = ::summon_survival_elvira;
    interaction.enabled = 1;
    scripts\cp\cp_interaction::add_to_current_interaction_list(interaction);
    survival_log("Elvira pedestal ready stand=" + stand.origin + " book=" + book.origin +
        " interaction=" + interaction.origin + " spawn=" + spawn_spot.origin +
        " cost=0 vialRequired=0 lifespan=stock-120s cooldown=stock-300s bossFight=inactive");
}

survival_elvira_hint(interaction, player)
{
    if (isdefined(level.elvira_ai) || scripts\engine\utility::flag("elvira_summoned") ||
        (isdefined(level.elvira_available_again) && gettime() < level.elvira_available_again))
        return &"CP_TOWN_INTERACTIONS_ELVIRA_GONE";
    return &"CP_TOWN_INTERACTIONS_SUMMON_ELVIRA";
}

summon_survival_elvira(interaction, player)
{
    level endon("game_ended");
    if (isdefined(level.elvira_ai) || scripts\engine\utility::flag("elvira_summoned") ||
        (isdefined(level.elvira_available_again) && gettime() < level.elvira_available_again))
    {
        survival_log("Elvira summon waiting player=" + (player getentitynumber()) +
            " reason=active-or-cooldown");
        return;
    }
    // Stock finger-snap sets elvira_summoned before its first wait and reserves
    // the ally slot. Keep the stock AI, revival, departure and cooldown logic.
    // The quest's cleaver/vial cannot be collected inside this survival area.
    survival_log("Elvira summon accepted player=" + (player getentitynumber()) + " vialRequired=0");
    scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
    scripts\cp\maps\cp_town\cp_town_elvira::elvira_finger_snap();
    scripts\cp\maps\cp_town\cp_town_elvira::spawn_elvira();
    scripts\cp\cp_interaction::add_to_current_interaction_list(interaction);
    level thread scripts\cp\maps\cp_town\cp_town_elvira::play_elvira_sound_in_space_vo(
        "el_nag_beachboss_combat_inbound");
    survival_log("Elvira spawned entity=" + (level.elvira_ai getentitynumber()) +
        " origin=" + level.elvira_ai.origin + " canRevive=" + level.elvira_ai.can_revive);
    while (isdefined(level.elvira_ai))
        wait 0.5;
    survival_log("Elvira departed cooldown=stock-300s");
    scripts\engine\utility::flag_waitopen("elvira_summoned");
    survival_log("Elvira pedestal ready again");
}
