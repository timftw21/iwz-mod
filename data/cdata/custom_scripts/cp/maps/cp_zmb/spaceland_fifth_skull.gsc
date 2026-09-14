main()
{
    if (getdvar("ui_mapname") != "cp_zmb")
        return;

    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_ghost_activation::hit_the_floating_skull_with_spaceland_laser, ::floating_skull);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_ufo::activate_spaceland_powernode, ::activate_powernodes);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_ufo::can_charge_power_nodes, ::can_charge_power_nodes);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_ufo::trigger_wmd, ::trigger_wmd);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_dj::init_match_ufo_tone, ::init_match_ufo_tone);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_ghost_activation::any_player_look_at_skull, ::any_player_look_at_skull);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb_ghost_wave::notify_activation_progress, ::notify_activation_progress);
    skull_log("installed fifth skull before EE; base pistols accepted only during skull step; boss suspension enabled");
}

post_load()
{
    if (level.script == "cp_zmb")
        level thread listen_for_test();
}

skull_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("SpacelandSkull5", message);
}

notify_activation_progress(skulls, unused_delay)
{
    // All six stock completion callbacks share this helper, including the
    // fifth-skull callback after floating_skull() returns. Preserve its sound
    // and cabinet update exactly; record the previously silent availability
    // check instead of guessing that an inaudible chime was never requested.
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ghost_wave::update_num_of_coin_inserted(skulls);
    alias = "ghosts_quest_step_notify";
    available = soundexists(alias);
    duration_ms = 0;
    recipients = 0;
    if (available)
    {
        duration_ms = lookupsoundlength(alias);
        foreach (player in level.players)
        {
            player playlocalsound(alias);
            recipients++;
        }
        // The test driver uses this boundary; natural quest progression never
        // waits for sound playback and its original timing stays intact.
        level.iwz_skull_sfx_until = gettime() + duration_ms + 100;
    }
    custom_scripts\cp\gsc_diagnostics::emit("SpacelandSkullAudio",
        "completion skulls=" + skulls + " alias=" + alias + " available=" + available +
        " durationMs=" + duration_ms + " playbackRequests=" + recipients +
        " test=" + scripts\engine\utility::is_true(level.iwz_skull5_test_advancing));
}

floating_skull()
{
    level endon("game_ended");
    level.iwz_skull5_active = true;
    level.iwz_skull5_hit = false;
    start_powernode_listener();
    wait(randomintrange(5, 10));
    while (!level.iwz_skull5_hit)
    {
        if (!scripts\engine\utility::is_true(level.iwz_skull5_boss) && !isdefined(level.iwz_skull5))
        {
            skull = spawn("script_model", (1007, 621, 901));
            skull setmodel("zmb_pixel_skull");
            skull.angles = (90, 340, 70);
            skull setcandamage(1);
            skull.health = 999999;
            level.iwz_skull5 = skull;
            skull thread scripts\cp\maps\cp_zmb\cp_zmb_ghost_activation::movement_logic(skull);
            skull thread scripts\cp\maps\cp_zmb\cp_zmb_ghost_activation::visibility_monitor(skull);
            skull thread skull_damage_monitor();
            skull_log("skull spawned; glasses required; EE completion not required");
        }
        wait(0.05);
    }
    level.iwz_skull5_active = false;
    reset_skull_laser();
    skull_log("fifth skull destroyed by Spaceland laser");
}

skull_damage_monitor()
{
    self endon("death");
    level endon("game_ended");
    for (;;)
    {
        self waittill("damage", damage, attacker, direction, point, mod, model, tag, part, inflictor, weapon);
        self.health = 999999;
        if (!scripts\engine\utility::is_true(level.iwz_skull5_boss) &&
            scripts\cp\maps\cp_zmb\cp_zmb_ghost_activation::can_floating_skull_be_destroyed(weapon))
        {
            playfx(level._effect["skull_discovered"], self.origin, anglestoforward(self.angles), anglestoup(self.angles));
            level.iwz_skull5_hit = true;
            self delete();
            return;
        }
    }
}

activate_powernodes()
{
    level.iwz_powernodes_ee_enabled = true;
    start_powernode_listener();
}

start_powernode_listener()
{
    // The EE calls this again after the Alien fight. There must be one damage
    // listener, otherwise a single shot can launch overlapping laser sequences.
    if (scripts\engine\utility::is_true(level.iwz_powernodes_started))
        return;
    level.iwz_powernodes_started = true;
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::spaceland_powernode_damage_monitor();
    skull_log("shared power-node listener started");
}

can_charge_power_nodes(weapon, player)
{
    if (!isdefined(weapon) || !isdefined(player) || !isplayer(player))
        return false;
    switch (getweaponbasename(weapon))
    {
        case "iw7_headcutter_zm_pap1":
        case "iw7_headcutter_zm":
        case "iw7_facemelter_zm_pap1":
        case "iw7_facemelter_zm":
        case "iw7_dischord_zm_pap1":
        case "iw7_dischord_zm":
        case "iw7_shredder_zm_pap1":
        case "iw7_shredder_zm":
            if (scripts\engine\utility::is_true(level.iwz_skull5_active) &&
                !scripts\engine\utility::is_true(level.iwz_skull5_boss) && isdefined(level.iwz_skull5))
            {
                skull_log("skull laser node accepted weapon=" + getweaponbasename(weapon));
                return true;
            }
            // Preserve the original weapon requirement for the UFO finale.
            return scripts\engine\utility::is_true(level.iwz_powernodes_ee_enabled) &&
                player scripts\cp\cp_weapon::get_weapon_level(weapon) == 2;
        default:
            return false;
    }
}

reset_skull_laser()
{
    level notify("iwz_skull5_cancel_laser");
    level notify("spaceland_arc_fired");
    if (isdefined(level.iwz_skull5_beam))
        level.iwz_skull5_beam delete();
    for (index = 1; index <= 5; index++)
    {
        node = scripts\engine\utility::getstruct("main_gate_powernode_" + index, "targetname");
        node.is_activated = false;
    }
    scripts\cp\maps\cp_zmb\cp_zmb_ufo::change_gate_light_scriptable_to_on_state();
}

init_match_ufo_tone()
{
    // Suspend synchronously before the UFO enters the skull's flight path.
    level.iwz_skull5_boss = true;
    level.iwz_powernodes_ee_enabled = false;
    if (isdefined(level.iwz_skull5))
        level.iwz_skull5 delete();
    reset_skull_laser();
    level thread resume_after_boss();
    skull_log("boss started: skull removed, pending skull laser cancelled and nodes reset");

    scripts\engine\utility::flag_init("ufo_listening");
    scripts\engine\utility::flag_init("tones_played_successfully");
    scripts\engine\utility::flag_init("ufo_intro_reach_center_portal");
    scripts\cp\maps\cp_zmb\cp_zmb_ufo::start_grey_fight_blocker_vfx();
    scripts\cp\maps\cp_zmb\cp_zmb_ufo::disableportals();
    scripts\cp\maps\cp_zmb\cp_zmb_ufo::setalltonestructstoneutralstate();
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::ufo_intro_fly_to_center_portal();
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::move_grey_fight_clip_down();
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::ufostopwavefromprogressing();
}

resume_after_boss()
{
    level endon("game_ended");
    scripts\engine\utility::flag_wait("ufo_destroyed");
    reset_skull_laser();
    level.iwz_skull5_boss = false;
    skull_log("boss/UFO sequence finished: unfinished fifth skull may resume");
}

trigger_wmd()
{
    level endon("game_ended");
    level endon("iwz_skull5_cancel_laser");
    // Stock laser timing and trajectory, with a cancellation boundary so a
    // charge begun for the skull cannot fire into the incoming boss sequence.
    left = (726, 1788, 154);
    right = (608, 1793, 154);
    top = (668, 1580, 154);
    middle = (669, 1237, 154);
    muzzle = (648, 611, 281);
    bottom = (647, 632, 86);
    node2 = scripts\engine\utility::getstruct("main_gate_powernode_2", "targetname");
    node3 = scripts\engine\utility::getstruct("main_gate_powernode_3", "targetname");
    node4 = scripts\engine\utility::getstruct("main_gate_powernode_4", "targetname");
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_medium", node2.origin, left, "spaceland_arc_fired");
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_medium", node4.origin, right, "spaceland_arc_fired");
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_medium", node3.origin, top, "spaceland_arc_fired");
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_medium", left, top, "spaceland_arc_fired");
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_medium", right, top, "spaceland_arc_fired");
    playsoundatpos(left, "zmb_ufo_spaceland_sign_build");
    wait(randomfloatrange(1.3, 1.7));
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_big", top, middle, "spaceland_arc_fired");
    wait(randomfloatrange(1.3, 1.7));
    level thread scripts\cp\maps\cp_zmb\cp_zmb_ufo::play_arc_vfx_between_points("powernode_arc_big", middle, bottom, "spaceland_arc_fired");
    for (index = 1; index <= 5; index++)
    {
        node = scripts\engine\utility::getstruct("main_gate_powernode_" + index, "targetname");
        node.is_activated = false;
    }
    if (scripts\engine\utility::is_true(level.iwz_skull5_active) &&
        !scripts\engine\utility::is_true(level.iwz_skull5_boss))
    {
        // Exploder 90's exact effect/transform from gen/cp_zmb_fx. Own the FX
        // entity for this step so boss entry can remove even an emitted beam.
        if (isdefined(level.iwz_skull5_beam))
            level.iwz_skull5_beam delete();
        beam_angles = (0, 93, 0);
        level.iwz_skull5_beam = spawnfx(level._effect["vfx_ufo_p_beam"],
            (645.854, 693.576, 51.044), anglestoforward(beam_angles), anglestoup(beam_angles));
        triggerfx(level.iwz_skull5_beam);
    }
    else
        scripts\engine\utility::exploder(90);
    wait(2);
    playsoundatpos(bottom, "zmb_ufo_spaceland_sign_wmd");
    level notify("spaceland_arc_fired");
    magicbullet("iw7_spaceland_wmd", muzzle + (0, 0, 50), muzzle + (0, 0, 2000));
    scripts\cp\maps\cp_zmb\cp_zmb_ufo::change_gate_light_scriptable_to_on_state();
    skull_log("laser fired boss=" + scripts\engine\utility::is_true(level.iwz_skull5_boss));
}

listen_for_test()
{
    level endon("game_ended");
    for (;;)
    {
        level waittill("iwz_test_skull5", player);
        if (!isdefined(player) || !isplayer(player))
            continue;
        if (scripts\engine\utility::is_true(level.iwz_skull5_boss) ||
            scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight() ||
            scripts\engine\utility::is_true(level.gns_active))
        {
            player iprintlnbold("Use testSkull5 in regular Spaceland outside the boss fight");
            skull_log("test rejected: boss or arcade active");
            continue;
        }
        if (!isdefined(level._id_13F1B["ghost"]))
        {
            player iprintlnbold("Ghosts N Skulls quest is not ready");
            skull_log("test rejected: ghost quest not running");
            continue;
        }
        if (level._id_13F1B["ghost"] > 4)
        {
            player iprintlnbold("The fifth skull is already complete; start a new match to repeat");
            skull_log("test ignored: fifth skull already completed");
            continue;
        }
        weapon = "iw7_shredder_zm";
        player scripts\cp\utility::_giveweapon(weapon);
        player givemaxammo(weapon);
        player switchtoweapon(weapon);
        if (!scripts\engine\utility::is_true(player.has_dischord_glasses))
            player scripts\cp\zombies\zombies_wor::give_glasses_power();
        if (!scripts\engine\utility::is_true(player.wearing_dischord_glasses))
            player thread scripts\cp\zombies\zombies_wor::put_glasses_on();
        if (!scripts\engine\utility::is_true(level.iwz_skull5_test_advancing))
            level thread prepare_test_quest(player);
    }
}

any_player_look_at_skull(skull)
{
    // Let the normal letter sequence finish and delete its own temporary model.
    // This test-only condition is cleared as soon as the first four steps end.
    if (scripts\engine\utility::is_true(level.iwz_skull5_test_advancing))
        return true;
    foreach (player in level.players)
    {
        if (scripts\cp\maps\cp_zmb\cp_zmb_ghost_activation::player_look_at_skull(skull, player))
            return true;
    }
    return false;
}

prepare_test_quest(player)
{
    level endon("game_ended");
    level.iwz_skull5_test_advancing = true;
    player iprintlnbold("Preparing four skulls in the machine...");
    deadline = gettime() + 30000;
    previous_step = -1;
    while (level._id_13F1B["ghost"] < 4 && gettime() < deadline)
    {
        step = level._id_13F1B["ghost"];
        if (step != previous_step)
        {
            skull_log("test advancing stock ghost quest step=" + step);
            previous_step = step;
            if (isdefined(level.iwz_skull_sfx_until) && level.iwz_skull_sfx_until > gettime())
                wait((level.iwz_skull_sfx_until - gettime()) / 1000.0);
        }
        // Satisfy the running stock step rather than launching a second quest
        // or setting only its display. Its completion callbacks own the cabinet
        // count and cleanup, then the quest itself enters floating_skull().
        switch (step)
        {
            case 0:
                level notify("balloon_popped");
                break;
            case 2:
                level notify("got_1_9_8_4_kills");
                break;
            case 3:
                foreach (arcade_game in ["zombie_zoom", "bowling_for_planets", "rings_of_saturn", "cryptid_attack", "black_hole"])
                {
                    level notify("beat_arcade_game", arcade_game);
                    wait(0.05);
                }
                break;
        }
        wait(0.05);
    }
    level.iwz_skull5_test_advancing = false;
    if (level._id_13F1B["ghost"] < 4)
    {
        skull_log("test preparation timed out at step=" + level._id_13F1B["ghost"]);
        if (isdefined(player))
            player iprintlnbold("Unable to prepare the fourth skull; see console log");
        return;
    }
    skull_log("test ready: stock quest step=" + level._id_13F1B["ghost"] +
        " cabinetSkulls=" + getomnvar("zm_num_ghost_n_skull_coin") + "; EE progress unchanged");
    if (isdefined(player))
        player iprintlnbold("Four skulls ready: shoot the five sign nodes and time the laser to hit skull 5");
}
