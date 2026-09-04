precache_death_wish(use_barrel)
{
    setdvar("iwz_directors_death_active", 0);
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    if (use_barrel)
        precachemodel("com_barrel_black");
    precachemodel("zmb_soul_jar_no_horns");
    level.iwz_directors_death_fx = loadfx("vfx/iwz/directors_death_jar_red.vfx");
}

start_death_wish(settings)
{
    level.iwz_directors_death_active = 0;
    level thread directors_death_client_sync();
    if (!getdvarint("iwz_survival_mode", 0) ||
        !isdefined(level.script) || level.script != settings.map)
        return;

    level thread setup_directors_death(settings);
}

directors_death_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("DeathWish", message);
}

setup_directors_death(settings)
{
    level endon("game_ended");
    directors_death_log("setup waiting for interactions and zombie movement map=" + settings.map);

    // Wait for the interaction list and movement table, not an optional entry.
    // zombie_agent::registerscriptedagent clears movemodefunc on Spaceland;
    // zombie_dlc1_agent re-registers generic_zombie on Rave. The stock movement
    // loop supports an unset callback and keeps its naturally selected speed.
    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        wait 0.05;
    scripts\engine\utility::flag_wait("init_interaction_done");
    directors_death_log("interactions ready map=" + settings.map +
        " movementTableReady=" + isdefined(level.movemodefunc));
    while (!isdefined(level.movemodefunc))
        wait 0.05;

    level.iwz_directors_death_active = 0;
    level.iwz_directors_death_generation = 0;
    level.iwz_directors_death_logged_moves = 0;
    level.iwz_directors_death_next_use = 0;
    level.iwz_directors_death_stock_move =
        level.movemodefunc["generic_zombie"];
    level.movemodefunc["generic_zombie"] = ::directors_death_move_mode;
    directors_death_log("movement hook installed map=" + settings.map +
        " stockCallback=" + isdefined(level.iwz_directors_death_stock_move));
    level thread directors_death_spawn_monitor();

    // XModel bounds: barrel Z=0.047756..44.013859, jar Z=0.003633..17.899171.
    // Rave adds a barrel; Arcade uses the existing table at the logged surface.
    barrel_origin = "none";
    jar_origin = settings.surface - (0, 0, 0.003633);
    if (settings.use_barrel)
    {
        barrel = spawn("script_model", settings.surface - (0, 0, 0.047756));
        barrel setmodel("com_barrel_black");
        barrel.angles = (0, settings.barrel_yaw, 0);
        barrel solid();
        barrel.iwz_player_blocker = create_directors_death_barrel_collision(barrel);
        barrel_origin = barrel.origin;
        jar_origin = barrel.origin + (0, 0, 44.013859 - 0.003633);
    }
    jar = spawn("script_model", jar_origin);
    jar setmodel("zmb_soul_jar_no_horns");
    jar.angles = (0, settings.jar_yaw, 0);
    jar solid();

    // directors_cut::set_up_soul_jar_interaction uses this same registration
    // route; this separate interaction has no Director's Cut/profile effects.
    interaction = spawnstruct();
    interaction.name = "iwz_directors_death";
    interaction.script_noteworthy = interaction.name;
    interaction.origin = jar.origin + (0, 0, 8.951402);
    interaction.cost = 0;
    interaction.powered_on = 1;
    interaction.requires_power = 0;
    interaction.spend_type = "null";
    interaction.script_parameters = "";
    interaction.enabled = 1;
    interaction.disable_guided_interactions = 0;
    interaction.custom_search_dist = 96;
    interaction.hint_func = ::directors_death_hint;
    interaction.activation_func = ::toggle_directors_death;
    interaction.sound_on = settings.sound_on;
    interaction.sound_off = settings.sound_off;
    // gen/cp_rave_fx's soul-jar exploder is 13.64 above the model origin.
    // Rotate its original (.5, .584) offset and 275-degree yaw with the jar.
    rotation = (0, jar.angles[1] - 270, 0);
    interaction.fx_origin = jar.origin +
        anglestoforward(rotation) * 0.5 - anglestoright(rotation) * 0.584 + (0, 0, 13.64);
    interaction.fx_angles = (0, jar.angles[1] + 5, 0);
    level.interactions[interaction.name] = interaction;
    scripts\cp\cp_interaction::add_to_current_interaction_list(interaction);
    level thread directors_death_cleanup(interaction);

    directors_death_log("ready map=" + settings.map + " mode=survival active=0 " +
        "useBarrel=" + settings.use_barrel + " barrelOrigin=" + barrel_origin +
        " jar=zmb_soul_jar_no_horns jarOrigin=" + jar.origin +
        " hintOrigin=" + interaction.origin +
        " radius=96 cost=0 movement=movemodefunc movementField=movemode minimum=run" +
        " fx=vfx/iwz/directors_death_jar_red fxOrigin=" + interaction.fx_origin +
        " feedback=red-jar,summon-sfx,red-scene");
}

create_directors_death_barrel_collision(barrel)
{
    // cp_rave::fix_map_exploits clones the map's authored playerclip brushes.
    // solid() on a script_model uses contents 0x2080, not player collision.
    clip_template = getent("player32x32x128", "targetname");
    if (!isdefined(clip_template))
    {
        directors_death_log("barrel player collision failed reason=player32x32x128-template-missing");
        return undefined;
    }

    blocker = spawn("script_model", (0, 0, 0));
    blocker clonebrushmodeltoscriptmodel(clip_template);
    // Rave cmodel *44 bounds: midpoint (0,0,64), half-size (17,17,65).
    // Align its upper bound (129) to the barrel top; surplus height is underground.
    blocker.origin = barrel.origin + (0, 0, 44.013859 - 129);
    blocker.angles = barrel.angles;
    directors_death_log("barrel player collision created barrelEnt=" +
        (barrel getentitynumber()) + " blockerEnt=" + (blocker getentitynumber()) +
        " origin=" + blocker.origin + " angles=" + blocker.angles +
        " brush=player32x32x128 contents=authored-playerclip top=barrel-lid");
    return blocker;
}

directors_death_client_sync()
{
    level endon("game_ended");
    if (isdefined(level.players))
    {
        foreach (player in level.players)
            player setclientdvar("iwz_directors_death_active", level.iwz_directors_death_active);
    }
    for (;;)
    {
        level waittill("connected", player);
        player setclientdvar("iwz_directors_death_active", level.iwz_directors_death_active);
        directors_death_log("HUD sync player=" + (player getentitynumber()) +
            " active=" + level.iwz_directors_death_active);
    }
}

directors_death_cleanup(interaction)
{
    level waittill("game_ended");
    level.iwz_directors_death_active = 0;
    if (isdefined(interaction.fx_ent))
        interaction.fx_ent delete();
    foreach (player in level.players)
        player setclientdvar("iwz_directors_death_active", 0);
    directors_death_log("match ended feedback reset active=0");
}

directors_death_feedback(interaction)
{
    if (level.iwz_directors_death_active)
    {
        // Stock Rave portals use spawnfx/triggerfx and delete to stop loops.
        interaction.fx_ent = spawnfx(level.iwz_directors_death_fx, interaction.fx_origin,
            anglestoforward(interaction.fx_angles), anglestoup(interaction.fx_angles));
        triggerfx(interaction.fx_ent);
        sound = interaction.sound_on;
    }
    else
    {
        if (isdefined(interaction.fx_ent))
            interaction.fx_ent delete();
        interaction.fx_ent = undefined;
        sound = interaction.sound_off;
    }
    playsoundatpos(interaction.origin, sound);
    foreach (player in level.players)
        player setclientdvar("iwz_directors_death_active", level.iwz_directors_death_active);
    directors_death_log("feedback active=" + level.iwz_directors_death_active +
        " sound=" + sound + " redParticles=" + isdefined(interaction.fx_ent) +
        " hudPlayers=" + level.players.size);
}

directors_death_hint(interaction, player)
{
    if (level.iwz_directors_death_active)
        return "Hold [{+usereload,+activate}] to deactivate Death Wish";

    return "Hold [{+usereload,+activate}] to activate Death Wish";
}

toggle_directors_death(interaction, player)
{
    if (!isdefined(player) || !isplayer(player) || !isalive(player) ||
        scripts\cp\cp_laststand::player_in_laststand(player) ||
        distance(player.origin, interaction.origin) > interaction.custom_search_dist)
        return;

    // Both maps' stock listeners return after activation, including rejected
    // requests. Re-arm it after releasing Use so a nearby player can toggle again.
    player thread directors_death_rearm(interaction);
    if (gettime() < level.iwz_directors_death_next_use)
        return;

    level.iwz_directors_death_next_use = gettime() + 1000;
    level.iwz_directors_death_active = !level.iwz_directors_death_active;
    level.iwz_directors_death_generation++;
    level.iwz_directors_death_logged_moves = 0;
    directors_death_feedback(interaction);

    awake = 0;
    foreach (agent in level.spawned_enemies)
    {
        if (isdefined(agent) && isalive(agent) &&
            isdefined(agent.agent_type) && agent.agent_type == "generic_zombie")
        {
            // Wake the stock movement loop. It handles animation changes,
            // traversal, frozen zombies, rate scales and crawler restrictions.
            agent notify("speed_debuffs_changed");
            awake++;
        }
    }

    foreach (other_player in level.players)
    {
        if (isdefined(other_player.last_interaction_point) &&
            other_player.last_interaction_point == interaction &&
            isdefined(other_player.interaction_trigger))
        {
            other_player.interaction_trigger sethintstring(
                directors_death_hint(interaction, other_player));
        }
    }

    directors_death_log("toggle active=" + level.iwz_directors_death_active +
        " player=" + (player getentitynumber()) + " scene=" + level.wave_num +
        " generation=" + level.iwz_directors_death_generation +
        " existingZombiesNotified=" + awake + " futureSpawns=covered");
}

directors_death_rearm(interaction)
{
    self notify("iwz_directors_death_rearm");
    self endon("iwz_directors_death_rearm");
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");
    // Both stock wait_for_interaction_triggered listeners finish after 0.1s.
    wait 0.15;
    while (self usebuttonpressed() || gettime() < level.iwz_directors_death_next_use)
        wait 0.05;

    if (isdefined(self.last_interaction_point) &&
        self.last_interaction_point == interaction)
        self.last_interaction_point = undefined;
}

directors_death_spawn_monitor()
{
    level endon("game_ended");
    for (;;)
    {
        level waittill("agent_spawned", agent);
        // Agent slots are reused. Clear our state before the stock movement
        // loop's initial waitframe, including spawns while the toggle is off.
        agent.iwz_directors_death_normal_move = undefined;
        agent.iwz_directors_death_logged_generation = undefined;
    }
}

directors_death_move_mode(speed_round)
{
    // zombie_agent::_id_13F55 calls this after choosing the natural spawn
    // speed, and again whenever speed_debuffs_changed fires. Like the stock
    // final-boss override, return a move mode instead of forcing animation rates.
    // Field token 0x01F5 is movemode. CODIW-Source incorrectly labels it with
    // the separate builtin-function name synctransients (also numbered 0x01F5).
    if (level.iwz_directors_death_active)
    {
        if (!isdefined(self.iwz_directors_death_normal_move))
            self.iwz_directors_death_normal_move = self.movemode;

        mode = "run";
        if (self.iwz_directors_death_normal_move == "sprint")
            mode = "sprint";
    }
    else
    {
        mode = undefined;
        if (isdefined(self.iwz_directors_death_normal_move))
        {
            mode = self.iwz_directors_death_normal_move;
            self.iwz_directors_death_normal_move = undefined;
        }

        // Preserve the stock last-zombie acceleration and later-round behavior.
        if (isdefined(level.iwz_directors_death_stock_move))
        {
            stock_mode = [[level.iwz_directors_death_stock_move]](speed_round);
            if (isdefined(stock_mode))
                mode = stock_mode;
        }
    }

    if (isdefined(mode) &&
        (!isdefined(self.iwz_directors_death_logged_generation) ||
        self.iwz_directors_death_logged_generation != level.iwz_directors_death_generation))
    {
        self.iwz_directors_death_logged_generation = level.iwz_directors_death_generation;
        if (level.iwz_directors_death_logged_moves < 8)
        {
            level.iwz_directors_death_logged_moves++;
            directors_death_log("movement ent=" + (self getentitynumber()) +
                " active=" + level.iwz_directors_death_active +
                " from=" + self.movemode + " to=" + mode +
                " generation=" + level.iwz_directors_death_generation);
        }
    }
    return mode;
}
