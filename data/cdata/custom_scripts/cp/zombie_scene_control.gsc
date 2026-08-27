post_load()
{
    level thread install_zombie_sprint_speed_tuning();
    level thread listen_for_scene_requests();
    scene_log("runtime installed map=" + getdvar("ui_mapname"));
}

scene_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Scenes", message);
}

install_zombie_sprint_speed_tuning()
{
    level endon("game_ended");

    while (!isdefined(level.agent_definition) || !isdefined(level._id_BCE5))
        scripts\engine\utility::waitframe();

    level.iwz_sprint_tuned_types = [];
    tuned_count = 0;
    foreach (agent_type, definition in level.agent_definition)
    {
        if (!is_standard_zombie_definition(definition))
            continue;

        level.iwz_sprint_tuned_types[agent_type] = true;
        tuned_count++;
    }

    // Stock standard zombies occasionally add a hard-coded 1.15 sprint burst.
    // Remove that second multiplier so the live root-motion scale remains the
    // sole sprint-speed control and does not produce sudden speed spikes.
    replacefunc(scripts\mp\agents\zombie\zombie_agent::speed_up_every_now_and_then, ::control_standard_zombie_sprint_burst);
    level thread maintain_standard_zombie_sprint_speed();
    scene_log("sprint tuning installed definitions=" + tuned_count + " scale=" + getdvarfloat("iwz_zombie_sprint_speed_scale") + " standardBurst=disabled");
}

is_standard_zombie_definition(definition)
{
    if (!isdefined(definition["asm"]))
        return false;

    asm_name = definition["asm"];
    return asm_name == "zombie" || asm_name == "zombie_dlc1" || asm_name == "zombie_dlc2" || asm_name == "zombie_dlc3" || asm_name == "zombie_dlc4";
}

maintain_standard_zombie_sprint_speed()
{
    level endon("game_ended");

    last_scale = undefined;
    active_reported = false;
    for (;;)
    {
        scale = getdvarfloat("iwz_zombie_sprint_speed_scale");
        scale_changed = !isdefined(last_scale) || scale != last_scale;
        sprinting_count = 0;
        locomotion_count = 0;
        adjusted_count = 0;

        if (isdefined(level.spawned_enemies))
        {
            enemies = level.spawned_enemies;
            foreach (enemy in enemies)
            {
                if (!isdefined(enemy) || !isalive(enemy) || !isdefined(enemy.agent_type))
                    continue;

                if (!isdefined(level.iwz_sprint_tuned_types[enemy.agent_type]))
                    continue;

                // The runtime script uses movemode. The organized source dump
                // aliases this field as synctransients, but that name does not
                // resolve to the live IW7 field.
                is_sprinting = isdefined(enemy.movemode) && enemy.movemode == "sprint";
                if (is_sprinting)
                    sprinting_count++;

                // Standard zombie movement is animation-root-motion driven.
                // scragentsetanimscale applies immediately to the live root
                // motion, unlike moveratescale/moveplaybackrate, which the ASM
                // only samples when entering a new movement animation.
                is_sprint_locomotion = is_sprinting && isdefined(enemy.aistate) && enemy.aistate == "move" &&
                    isdefined(enemy.asm) && isdefined(enemy.asm.cur_move_mode) && enemy.asm.cur_move_mode == "sprint";
                if (is_sprint_locomotion)
                {
                    locomotion_count++;
                    enemy scragentsetanimscale(scale, 1);
                    enemy.iwz_sprint_anim_scale_applied = true;
                    adjusted_count++;
                }
                else if (isdefined(enemy.iwz_sprint_anim_scale_applied))
                {
                    enemy scragentsetanimscale(1, 1);
                    enemy.iwz_sprint_anim_scale_applied = undefined;
                }
            }
        }

        if (scale_changed)
        {
            previous_scale = "unset";
            if (isdefined(last_scale))
                previous_scale = "" + last_scale;

            scene_log("sprint scale changed previous=" + previous_scale + " current=" + scale + " sprinting=" + sprinting_count + " locomotion=" + locomotion_count + " adjusted=" + adjusted_count);
        }
        else if (!active_reported && locomotion_count > 0)
        {
            scene_log("sprint scaling active scale=" + scale + " sprinting=" + sprinting_count + " locomotion=" + locomotion_count + " adjusted=" + adjusted_count);
            active_reported = true;
        }

        last_scale = scale;
        wait(0.05);
    }
}

control_standard_zombie_sprint_burst()
{
    // Only standard zombies are tuned. Preserve the stock burst behavior for
    // bosses and other enemies that share the base zombie setup function.
    if (isdefined(level.iwz_sprint_tuned_types[self.agent_type]))
        return;

    self endon("death");
    for (;;)
    {
        if (!isdefined(self.speedup) && randomint(100) < 25)
        {
            self.speedup = 1;
            wait(5);
            self.speedup = 0;
        }

        wait(5);
    }
}

listen_for_scene_requests()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_set_scene", player, target_scene);
        advance_to_scene(player, target_scene);
    }
}

advance_to_scene(player, target_scene)
{
    if (!isdefined(level.wave_num))
    {
        scene_log("scene rejected target=" + target_scene + " reason=wave manager unavailable");
        print_scene_error(player, "Scene manager is not ready");
        return;
    }

    if (!isdefined(target_scene) || int(target_scene) < 1)
    {
        scene_log("scene rejected target=" + target_scene + " reason=invalid target");
        print_scene_error(player, "Scene must be a positive whole number");
        return;
    }

    target_scene = int(target_scene);
    if (level.wave_num >= target_scene)
    {
        scene_log("scene ignored current=" + level.wave_num + " target=" + target_scene + " reason=target is not ahead");
        print_scene_error(player, "Target must be above Scene " + level.wave_num);
        return;
    }

    old_scene = level.wave_num;
    predecessor_scene = target_scene - 1;
    level.wave_num = predecessor_scene;

    // A large jump would otherwise guarantee an event scene because the stock
    // selector compares wave_num against last_event_wave. Stage the requested
    // target as a normal scene so map behavior can be tested deterministically.
    if (isdefined(level.last_event_wave))
        level.last_event_wave = predecessor_scene;

    // Event cleanup writes its original scene back to last_event_wave after the
    // force notification. Keep the staged value stable through that cleanup.
    level thread hold_scene_event_window(target_scene, predecessor_scene);

    scene_log("scene staged current=" + old_scene + " target=" + target_scene + " predecessor=" + predecessor_scene);
    complete_scene_for_skip(player, old_scene, target_scene);
}

hold_scene_event_window(target_scene, predecessor_scene)
{
    level endon("game_ended");

    while (isdefined(level.wave_num) && level.wave_num < target_scene)
    {
        if (isdefined(level.last_event_wave))
            level.last_event_wave = predecessor_scene;

        scripts\engine\utility::waitframe();
    }
}

complete_scene_for_skip(player, original_scene, target_scene)
{
    if (!isdefined(level.wave_num))
    {
        scene_log("scene rejected target=" + target_scene + " reason=wave state unavailable during completion");
        print_scene_error(player, "Scene manager is not ready");
        return;
    }

    desired_deaths = -1;
    current_deaths = -1;
    if (isdefined(level.desired_enemy_deaths_this_wave))
        desired_deaths = level.desired_enemy_deaths_this_wave;
    if (isdefined(level.current_enemy_deaths))
        current_deaths = level.current_enemy_deaths;
    killed_count = 0;
    protected_count = 0;

    level.stop_spawning = 1;

    if (isdefined(level.spawned_enemies))
    {
        enemies = level.spawned_enemies;
        foreach (enemy in enemies)
        {
            if (!isdefined(enemy) || !isalive(enemy))
                continue;

            // Quest-controlled enemies deliberately opt out of stock cleanup.
            if (isdefined(enemy.dont_scriptkill))
            {
                protected_count++;
                continue;
            }

            // A poorly-killed zombie is queued for respawn by the stock death
            // callback. Clear that state so this cleanup counts as a real death.
            enemy.died_poorly = 0;
            enemy dodamage(enemy.health + 1000, enemy.origin, enemy, enemy, "MOD_SUICIDE");
            killed_count++;
        }
    }

    // Every regular and map-specific wave spawner listens for this stock notify.
    // The owning wave loop then performs its normal intermission and increments.
    level notify("force_spawn_wave_done");

    scene_log("scene completion forced original=" + original_scene + " target=" + target_scene +
        " staged=" + level.wave_num + " deaths=" + current_deaths + "/" + desired_deaths +
        " killed=" + killed_count + " protected=" + protected_count);
    if (isdefined(player) && isplayer(player))
        player iprintlnbold("Advancing to Scene " + target_scene);
}

print_scene_error(player, message)
{
    if (isdefined(player) && isplayer(player))
        player iprintlnbold(message);
}
