// IWZ-LOAD: survival-only
main()
{
    if (!getdvarint("iwz_survival_mode", 0) || getdvar("ui_mapname") != "cp_final")
        return;

    custom_scripts\cp\survival_perks::precache_perk_wall("p7_cafe_wall_menu_01");
    custom_scripts\cp\death_wish::precache_death_wish(0);
    precacheitem("iw7_venomx_zm_pap2+camo34");
    // Cargo supplies the rare Venom roll directly; do not let the later stock
    // quest-gated branch replace it with an unupgraded Venom-X.
    replacefunc(scripts\cp\zombies\interaction_magicwheel::can_have_venomx, ::disallow_directors_cut);
    // The small cargo zone supplies Subway Shuffle's complete PaP image FX
    // and model, referencing materials and geometry already present in Beast.
    // The ordinary portal points at the theater and must not own these visuals.
    level._effect["iwz_cargo_pap"] = loadfx(
        "vfx/iw7/levels/cp_rave/vfx_rave_portal_02.vfx");
    level._effect["vfx_pap_return_portal"] = loadfx(
        "vfx/iw7/levels/cp_disco/vfx_paproom_portal.vfx");
    level._effect["death_ray_cannon_beam"] = loadfx(
        "vfx/iw7/levels/cp_town/death_ray_cannon_beam.vfx");
    level._effect["death_ray_cannon_rock_impact"] = loadfx(
        "vfx/iw7/levels/cp_final/rhino/vfx_metal_impact.vfx");
    replacefunc(scripts\cp\maps\cp_final\cp_final::init_magic_wheel, ::select_cargo_wheel);
    replacefunc(scripts\cp\zombies\interaction_magicwheel::_id_BC3F, ::hold_cargo_wheel);
    replacefunc(scripts\cp\maps\cp_final\cp_final_fast_travel::init_teleport_portals, ::init_teleport_portals);
    replacefunc(scripts\cp\maps\cp_final\cp_final_fast_travel::portal_console_init_func, ::disable_portal_glyphs);
    replacefunc(scripts\cp\maps\cp_final\cp_final_fast_travel::teleport_to_safe_spot, ::teleport_to_safe_spot);
    // Complete the two normal power prerequisites. The stock completion
    // handlers own the head model, console state, power flags and area events.
    replacefunc(scripts\cp\maps\cp_final\cp_final_mpq::retrieveneilshead, ::retrieveneilshead);
    replacefunc(scripts\cp\maps\cp_final\cp_final_mpq::placeneilshead, ::placeneilshead);
    replacefunc(scripts\cp\zombies\directors_cut::allow_directors_cut, ::disallow_directors_cut);
    survival_log("hooks installed map=cp_final wheel=cargo portal=PaP return=cargo " +
        "power=stock-neil-sequence firstScene=generic-zombies directorsCut=disabled");
}

post_load()
{
    if (!getdvarint("iwz_survival_mode", 0) || !isdefined(level.script) || level.script != "cp_final")
        return;

    level.initial_active_volumes = ["cargo"];
    level.disable_start_spawn_on_navmesh = 1;
    level.getspawnpoint = ::cargo_spawnpoint;
    level.force_respawn_location = ::cargo_spawnpoint;
    level.custom_onspawnplayer_func = ::cp_final_onplayerspawned;
    level thread configure_cargo_spawning();
    level thread configure_cargo_door();
    level thread configure_cargo_wheel();
    level thread enable_survival_double_pap();
    level thread enable_cargo_entangler();
    level.nextwheelweaponfunc = ::cargo_wheelnextweapon;
    custom_scripts\cp\survival_perks::install_survival_quick_revive_hooks();
    // The screenshot places the board one board-width left of the cargo
    // panel's middle strap. Move 32 units right in the player's facing plane,
    // keeping the measured height, wall depth and surface normal.
    perk_surface = (1016.51,2146.27,-121.799) + anglestoright((0,222.6,0)) * 32;
    level thread custom_scripts\cp\survival_perks::setup_perk_wall(
        perk_surface, (0.736097,0.676876,0), 222.6, "p7_cafe_wall_menu_01");
    settings = spawnstruct();
    settings.map = "cp_final";
    settings.surface = (1269.19,3138.23,-128.711);
    settings.use_barrel = 0;
    settings.jar_yaw = 87.121;
    settings.sound_on = "zmb_trap_laser_start";
    settings.sound_off = "zmb_trap_laser_end";
    custom_scripts\cp\death_wish::start_death_wish(settings);
    survival_log("Cargo Chaos initialized spawn=(1615.91,3415.9,16.998) " +
        "wheelTrace=(1490.66,3600.26,-133.512) portal=cargo_room/pf4_auto1 " +
        "door=pf28_auto667 perkWall=" + perk_surface + " perkWallShiftRight=32 " +
        "deathWish=(1269.19,3138.23,-128.711) startingWeapon=" + level.default_weapon);
}

survival_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("CargoChaos", message);
}

disallow_directors_cut()
{
    return 0;
}

cargo_spawnpoint(player)
{
    point = spawnstruct();
    point.origin = (1615.91,3415.9,16.998);
    point.angles = (0,-89.1986,0);
    if (!positionwouldtelefrag(point.origin))
        return point;
    return cargo_portal_landing();
}

cargo_portal_landing()
{
    // Authored cargo portal destinations, including the correction applied by
    // cp_final_fast_travel::trigger_when_player_close_by to its second spot.
    locations = [(1696,1886,64), (1752,1918,64), (1728,1918,64), (1776,1918,64)];
    point = spawnstruct();
    point.angles = (0,90,0);
    for (;;)
    {
        foreach (origin in locations)
        {
            grounded = scripts\engine\utility::drop_to_ground(origin, 32, -128) + (0,0,1);
            if (canspawn(grounded) && !positionwouldtelefrag(grounded))
            {
                point.origin = grounded;
                return point;
            }
        }
        wait 0.05;
    }
}

cp_final_onplayerspawned()
{
    self scripts\cp\maps\cp_final\cp_final::cp_final_onplayerspawned();
    if (getdvarint("scr_gameended", 0))
        return;
    if (distance(self.origin, (1615.91,3415.9,16.998)) > 2)
    {
        point = cargo_spawnpoint(self);
        self dontinterpolate();
        self setorigin(point.origin);
        self setplayerangles(point.angles);
    }
    self.currentlocation = "facility";
    survival_log("player spawned player=" + (self getentitynumber()) +
        " origin=" + self.origin + " angles=" + self.angles + " scene=" + level.wave_num);
}

configure_cargo_spawning()
{
    level endon("game_ended");
    while (!scripts\engine\utility::flag_exist("init_spawn_volumes_done"))
        wait 0.05;
    scripts\engine\utility::flag_wait("init_spawn_volumes_done");
    disabled = [];
    foreach (volume in level.active_spawn_volumes)
    {
        if (isdefined(volume.basename) && volume.basename != "cargo")
            disabled[disabled.size] = volume.basename;
    }
    foreach (name in disabled)
        scripts\cp\zombies\zombies_spawning::deactivate_volume_by_name(name);
    scripts\cp\zombies\zombies_spawning::activate_volume_by_name("cargo");
    scripts\cp\zombies\zombie_entrances::enable_windows_in_area("cargo");
    survival_log("spawn volumes ready active=cargo disabled=" + disabled.size);
    // Record actual round setup, including the stock cryptid budget and power
    // flag that controls its music, spawn count and last-kill Max Ammo drop.
    scene = -1;
    for (;;)
    {
        level waittill("agent_spawned", agent);
        if (level.wave_num != scene)
        {
            scene = level.wave_num;
            survival_log("round ready scene=" + scene + " type=" + agent.agent_type +
                " event=" + level.spawn_event_running + " total=" + level.desired_enemy_deaths_this_wave +
                " specialRound=" + level.specialroundcounter +
                " power=" + scripts\engine\utility::flag("power_on"));
        }
    }
}

retrieveneilshead()
{
    // initmpqsystems creates the pickup after interactions_initialized. Waiting
    // for its model avoids completing retrieval before that model exists.
    level endon("game_ended");
    scripts\engine\utility::flag_wait("interactions_initialized");
    // spawnn31lhead chooses ONE of the candidate structs and publishes it here.
    while (!isdefined(level._id_BEC5))
        wait 0.05;
    scripts\engine\utility::flag_set("neil_head_found");
    survival_log("NEIL retrieval completed source=survival-start headOrigin=" + level._id_BEC5.origin);
}

placeneilshead()
{
    level endon("game_ended");
    // zombie_power::_id_96F4 initializes power_on after its startup wait.
    // Completing the quest earlier sets an uninitialized flag, then loses it
    // when that initializer resets the flag to zero.
    while (!scripts\engine\utility::flag_exist("power_on"))
        wait 0.05;
    scripts\engine\utility::flag_set("neil_head_placed");
    level thread log_power_ready();
}

log_power_ready()
{
    level endon("game_ended");
    scripts\engine\utility::flag_wait("power_on");
    while (!isdefined(level._id_BEC5) || !isdefined(level.currentneilstate))
        wait 0.05;
    survival_log("power ready global=" + scripts\engine\utility::flag("power_on") +
        " headPlaced=" + scripts\engine\utility::flag("neil_head_placed") +
        " headOrigin=" + level._id_BEC5.origin + " neilState=" + level.currentneilstate);
}

enable_cargo_entangler()
{
    level endon("game_ended");
    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        wait 0.05;
    scripts\engine\utility::flag_wait("init_interaction_done");
    pickup = scripts\engine\utility::getstruct("entangler_spawner", "script_noteworthy");
    if (!isdefined(pickup))
    {
        survival_log("ERROR Entangler setup failed reason=authored-spawner-missing");
        return;
    }
    // crafted_entangler::init already started the stock one-shot listener.
    // Send its normal unlock only after MPQ and interaction initialization,
    // which would otherwise remove the pickup from the interaction list.
    level notify("complete_stay_on_pressure_plates");
    while (!isdefined(pickup._id_870F))
        wait 0.05;
    survival_log("Entangler ready origin=" + pickup.origin +
        " model=" + pickup._id_870F.model + " source=stock-pressure-plate-unlock");
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
    scripts\cp\maps\cp_final\cp_final_weapon_upgrade::upgrade_machine_for_all_players();
    scripts\cp\maps\cp_final\cp_final_weapon_upgrade::update_level_pap_machines("machine", "upgraded");
    scripts\cp\maps\cp_final\cp_final_weapon_upgrade::update_level_pap_machines("reels", "on");
    scripts\cp\maps\cp_final\cp_final_weapon_upgrade::update_level_pap_machines("door", "open_idle");
    survival_log("double PaP ready fusesInserted=1 placedAlienFuses=1 papMax=3 machines=" +
        level.player_pap_machines.size);
}

configure_cargo_door()
{
    level endon("game_ended");
    scripts\engine\utility::flag_wait("interactions_initialized");
    while (!scripts\engine\utility::flag_exist("doors_initialized"))
        wait 0.05;
    scripts\engine\utility::flag_wait("doors_initialized");
    disabled = 0;
    foreach (interaction in level.all_interaction_structs)
    {
        if (isdefined(interaction.target) && interaction.target == "pf28_auto667")
        {
            interaction.enabled = 0;
            scripts\cp\cp_interaction::remove_from_current_interaction_list(interaction);
            disabled++;
            survival_log("exit disabled target=" + interaction.target + " origin=" + interaction.origin);
        }
    }
    survival_log("containment ready door=pf28_auto667 interactions=" + disabled +
        " expected=2 collision=stock-closed");
}

cargo_wheelnextweapon(wheel, weapon, player)
{
    owns_venom = scripts\cp\zombies\interaction_magicwheel::has_venomx_in_loadout(player);
    if (owns_venom && issubstr(weapon, "venomx"))
    {
        ordinary = [];
        foreach (entry in wheel._id_13C25)
        {
            if (!issubstr(entry, "venomx"))
                ordinary[ordinary.size] = entry;
        }
        weapon = scripts\engine\utility::random(ordinary);
    }
    // Same 4% rare roll as Beast, retaining its per-player ownership limit.
    if (!owns_venom &&
        (issubstr(weapon, "venomx") || randomint(100) > 95))
    {
        weapon = "iw7_venomx_zm_pap2+camo34";
        foreach (index, entry in wheel._id_13C25)
        {
            if (issubstr(entry, "venomx"))
                wheel._id_13C25[index] = weapon;
        }
        wheel._id_13C25 = scripts\engine\utility::array_add(wheel._id_13C25, weapon);
        survival_log("wheel Venom-Z selected player=" + (player getentitynumber()) + " weapon=" + weapon);
    }
    return weapon;
}

select_cargo_wheel()
{
    scripts\cp\zombies\interaction_magicwheel::set_magic_wheel_starting_location("cargo");
    survival_log("wheel starting location=cargo reference=pf19_auto2");
}

configure_cargo_wheel()
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
    wheel = scripts\engine\utility::getclosest((1490.66,3600.26,-133.512), level._id_B163, 128);
    if (!isdefined(wheel) || !isdefined(wheel.area_name) || wheel.area_name != "cargo")
    {
        survival_log("ERROR wheel setup failed reason=authored-cargo-wheel-missing");
        return;
    }
    level.iwz_cargo_wheel = wheel;
    hold_cargo_wheel();
    for (;;)
    {
        wheel waittill("ready");
        level._id_13D01 = 0;
        level._id_B162 = 0;
        survival_log("wheel spin complete relocationCounters=reset teddy=disabled");
    }
}

hold_cargo_wheel()
{
    if (!isdefined(level.iwz_cargo_wheel))
        return;
    select_cargo_wheel();
    wheel = level.iwz_cargo_wheel;
    scripts\cp\zombies\interaction_magicwheel::init_magic_wheel(wheel);
    level.current_active_wheel = wheel;
    survival_log("wheel active entity=" + (wheel getentitynumber()) + " origin=" + wheel.origin +
        " area=" + wheel.area_name + " base=" + (wheel getscriptablepartstate("base")));
}

disable_portal_glyphs()
{
    // These remote glyphs unlock paired theater routes. Cargo owns only the
    // laser entrance, so their FX and endpoint watchers must not be started.
    survival_log("remote portal glyphs disabled routes=cargo-PaP-only");
}

init_teleport_portals()
{
    level endon("game_ended");
    scripts\engine\utility::flag_wait("interactions_initialized");
    portal = scripts\engine\utility::getstruct("cargo_room", "script_noteworthy");
    if (!isdefined(portal) || !isdefined(portal.target) || portal.target != "pf4_auto1")
    {
        survival_log("ERROR portal setup failed reason=cargo_room/pf4_auto1-missing");
        return;
    }
    trigger = scripts\engine\utility::getclosest(portal.origin,
        getentarray("fast_travel_portal_trigger", "targetname"), 128);
    clip = scripts\engine\utility::getclosest(portal.origin, getentarray("portal_clip", "targetname"), 128);
    // The stock laser completion marks both endpoint structs open. Retain
    // that pair without starting the theater travel route.
    portal.end_point = scripts\engine\utility::getstruct(portal.script_parameters, "script_noteworthy");
    if (!isdefined(trigger) || !isdefined(clip) || !isdefined(portal.end_point))
    {
        survival_log("ERROR portal setup failed reason=authored-trigger-clip-or-endpoint-missing");
        return;
    }
    while (!scripts\engine\utility::flag_exist("power_on"))
        wait 0.05;
    scripts\engine\utility::flag_wait("power_on");
    // Aim the visible ring at the cannon's authored doorway center. The
    // first three FX emitters spawn an average 12.15 units along forward
    // (their serialized spawn boxes), so compensate for that built-in depth.
    image_origin = (1745,1827,68) - anglestoforward(portal.angles) * 12.15;
    portal.fx = spawnfx(level._effect["iwz_cargo_pap"], image_origin, anglestoforward(portal.angles));
    triggerfx(portal.fx);
    portal scripts\cp\maps\cp_final\cp_final_fast_travel::wait_for_portal_doors_open();
    survival_log("portal visible imageOrigin=" + image_origin +
        " travel=locked waiting=laser-button buttonOrigin=(1918,3506,72)");
    // Keep the image visible through the cracked leaves. Only collision and
    // travel wait for the real button, cannon charge and door destruction.
    scripts\cp\maps\cp_final\cp_final_fast_travel::blast_doors_with_gun();
    clip notsolid();
    level thread scripts\cp\maps\cp_final\cp_final_fast_travel::turn_on_room_exit_portal();
    survival_log("portal ready target=" + portal.target + " triggerOrigin=" + trigger.origin +
        " imageOrigin=" + image_origin + " ringCenter=(1745,1827,68) image=Subway-Shuffle-PaP destination=pap_spawners " +
        " return=cargo manualExit=enabled timer=stock-30s theaterRoute=disabled");
    for (;;)
    {
        trigger waittill("trigger", player);
        if (isdefined(player) && isplayer(player) && isalive(player) &&
            !scripts\cp\cp_laststand::player_in_laststand(player) &&
            !scripts\engine\utility::is_true(player.is_in_pap) &&
            !scripts\engine\utility::is_true(player.isfasttravelling) &&
            player scripts\cp\utility::isteleportenabled())
        {
            // Beast's timer also stays alive for 30 seconds after expiring.
            if (isdefined(player.pap_timer_running))
            {
                if (!isdefined(player.iwz_cargo_cooldown_hint) || gettime() >= player.iwz_cargo_cooldown_hint)
                {
                    player.iwz_cargo_cooldown_hint = gettime() + 5000;
                    player iprintlnbold("Pack-a-Punch is cooling down");
                    survival_log("PaP entry waiting player=" + (player getentitynumber()) + " reason=stock-timer-cooldown");
                }
            }
            else
            {
                player.isfasttravelling = 1;
                portal thread enter_cargo_pap(player);
            }
        }
        wait 0.05;
    }
}

enter_cargo_pap(player)
{
    level endon("game_ended");
    player endon("disconnect");
    survival_log("PaP entry player=" + (player getentitynumber()) + " from=" + player.origin);
    player thread scripts\cp\maps\cp_final\cp_final_fast_travel::disable_teleportation(player, 0.5, "fast_travel_complete");
    scripts\cp\maps\cp_final\cp_final_fast_travel::travel_through_hidden_tube(player);
    survival_log("PaP arrived player=" + (player getentitynumber()) + " origin=" + player.origin);
}

teleport_to_safe_spot(player)
{
    point = cargo_portal_landing();
    player playershow();
    player unlink();
    player dontinterpolate();
    player setorigin(point.origin);
    player setplayerangles(point.angles);
    player.currentlocation = "facility";
    player.disable_consumables = undefined;
    player scripts\cp\powers\coop_powers::power_enablepower();
    survival_log("PaP returned player=" + (player getentitynumber()) + " origin=" + player.origin +
        " timedExit=" + scripts\engine\utility::is_true(player.kicked_out));
}
