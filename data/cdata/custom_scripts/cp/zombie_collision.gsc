post_load()
{
    // Stock zombie setup reads this dvar for every newly spawned agent.
    setdvar("scr_zombie_traversal_push", 0);

    // Disable the engine's additional character-capsule bounce pass. The clown
    // spawn listener separates normal clown spawns that overlap a player.
    setdvar("bg_playerEjection", 0);

    collision_log("post-load entry map=" + getdvar("ui_mapname") + " traversalPush=" + getdvar("scr_zombie_traversal_push") + " playerEjection=" + getdvar("bg_playerEjection"));

    level thread listen_for_clown_spawn_requests();
    level thread monitor_zombie_spawns();
    level thread tune_zombie_collision_capsules();
    level thread log_runtime_ready();
    install_zombie_melee_knockback_patch();
}

collision_log(message)
{
    if (!getdvarint("iwz_collision_debug", 1))
        return;

    custom_scripts\cp\gsc_diagnostics::emit("Collision", message);
}

log_runtime_ready()
{
    level endon("game_ended");
    scripts\engine\utility::waitframe();
    collision_log("runtime threads survived first frame");
}

tune_zombie_collision_capsules()
{
    level endon("game_ended");

    if (!isdefined(level.agent_definition))
    {
        collision_log("waiting for scripted_agents_initialized");
        level waittill("scripted_agents_initialized");
    }

    tuned_count = 0;
    foreach (agent_type, definition in level.agent_definition)
    {
        // This field becomes the physical capsule passed to giveplaceable when
        // the scripted agent is spawned. AI avoidance and melee reach are separate.
        if (isdefined(definition["species"]) && definition["species"] == "zombie" && definition["radius"] == 15)
        {
            level.agent_definition[agent_type]["radius"] = 12;
            tuned_count++;
        }
    }

    collision_log("tuned radius 15->12 for " + tuned_count + " zombie definitions");
}

monitor_zombie_spawns()
{
    level endon("game_ended");
    collision_log("agent_spawned monitor installed");

    for (;;)
    {
        level waittill("agent_spawned", agent);

        if (!isdefined(agent) || !isdefined(agent.agent_type) || !isdefined(level.agent_definition) || !isdefined(level.agent_definition[agent.agent_type]))
            continue;

        definition = level.agent_definition[agent.agent_type];
        if (isdefined(definition["species"]) && definition["species"] == "zombie")
        {
            agent disable_zombie_player_push();
            collision_log("monitor attached ent=" + agent getentitynumber() + " type=" + agent.agent_type + " playerPush=disabled distance=" + agent.preventplayerpushdist);
            agent thread monitor_zombie_traversal();
        }

        if (agent.agent_type == "zombie_clown" && !scripts\engine\utility::is_true(agent.iwz_allow_spawn_overlap))
            agent resolve_clown_spawn_overlap();
    }
}

disable_zombie_player_push()
{
    // IW uses this engine method for large enemies immediately before their
    // root-motion melee and jump attacks. Keep it enabled for zombies at all
    // times so neither attacks nor ordinary movement can displace a player.
    self.preventplayerpushdist = 12;
    self _meth_85C9(self.preventplayerpushdist);
}

monitor_zombie_traversal()
{
    self endon("death");
    level endon("game_ended");

    for (;;)
    {
        // The stock traversal-push thread listens to these same notifications.
        self waittill("traverse_begin");
        collision_log("traversal began with solid collision retained ent=" + self getentitynumber() + " type=" + self.agent_type + " origin=" + self.origin);
        self waittill("traverse_end");
        collision_log("traversal ended ent=" + self getentitynumber() + " type=" + self.agent_type + " origin=" + self.origin);
    }
}

install_zombie_melee_knockback_patch()
{
    if (!isdefined(level.callbackplayerdamage) || !isdefined(level.idflags_no_knockback))
    {
        collision_log("could not install melee knockback patch: damage callback or flag unavailable");
        return;
    }

    level.iwz_original_callbackplayerdamage = level.callbackplayerdamage;
    level.callbackplayerdamage = ::player_damage_without_zombie_melee_knockback;
    collision_log("installed zombie melee knockback patch flag=" + level.idflags_no_knockback);
}

player_damage_without_zombie_melee_knockback(param_00, param_01, param_02, param_03, param_04, param_05, param_06, param_07, param_08, param_09, param_0A, param_0B)
{
    if (is_zombie_melee_damage(param_01, param_04))
    {
        param_03 = param_03 | level.idflags_no_knockback;
        collision_log("suppressed melee knockback player=" + self getentitynumber() + " attacker=" + param_01 getentitynumber() + " type=" + param_01.agent_type + " mod=" + param_04 + " dflags=" + param_03);
    }

    self [[level.iwz_original_callbackplayerdamage]](param_00, param_01, param_02, param_03, param_04, param_05, param_06, param_07, param_08, param_09, param_0A, param_0B);
}

is_zombie_melee_damage(attacker, means_of_death)
{
    // Stock zombie melee uses MOD_IMPACT; retain MOD_MELEE for zombie variants
    // that route their attacks through the same player-damage callback.
    if ((means_of_death != "MOD_IMPACT" && means_of_death != "MOD_MELEE") || !isdefined(attacker) || !isagent(attacker) || !isdefined(attacker.agent_type))
        return false;

    if (isdefined(attacker.species) && (attacker.species == "zombie" || attacker.species == "zombie_grey"))
        return true;

    return attacker.agent_type == "zombie_brute";
}

resolve_clown_spawn_overlap()
{
    overlaps_player = false;

    foreach (player in level.players)
    {
        if (abs(self.origin[2] - player.origin[2]) < 80 && distance2dsquared(self.origin, player.origin) < 1024)
        {
            overlaps_player = true;
            break;
        }
    }

    if (!overlaps_player)
        return;

    spawn_origin = self.origin;
    offsets = [];
    offsets[0] = (48, 0, 0);
    offsets[1] = (-48, 0, 0);
    offsets[2] = (0, 48, 0);
    offsets[3] = (0, -48, 0);
    offsets[4] = (48, 48, 0);
    offsets[5] = (48, -48, 0);
    offsets[6] = (-48, 48, 0);
    offsets[7] = (-48, -48, 0);
    offsets[8] = (72, 0, 0);
    offsets[9] = (-72, 0, 0);
    offsets[10] = (0, 72, 0);
    offsets[11] = (0, -72, 0);

    foreach (offset in offsets)
    {
        candidate = getclosestpointonnavmesh(spawn_origin + offset);

        if (!positionwouldtelefrag(candidate))
        {
            self setorigin(candidate + (0, 0, 5), 1);
            collision_log("moved overlapping clown ent=" + self getentitynumber() + " origin=" + self.origin);
            return;
        }
    }

    collision_log("could not resolve clown overlap ent=" + self getentitynumber() + " origin=" + self.origin);
}

listen_for_clown_spawn_requests()
{
    level endon("game_ended");
    collision_log("iwz_spawn_clown listener installed");

    for (;;)
    {
        level waittill("iwz_spawn_clown", player);
        player spawn_clown_at_player();
    }
}

spawn_clown_at_player()
{
    if (!isdefined(self) || !isplayer(self))
    {
        collision_log("clown request rejected: invalid player");
        return 0;
    }

    collision_log("clown request player=" + self getentitynumber() + " origin=" + self.origin);

    if (!isdefined(level.agent_definition["zombie_clown"]))
    {
        collision_log("clown request failed: zombie_clown definition unavailable");
        self iprintlnbold("Unable to spawn clown: definition unavailable");
        return 0;
    }

    clown = scripts\cp\zombies\zombies_spawning::_id_13F53("zombie_clown", self.origin, self.angles, "axis", undefined);
    if (!isdefined(clown))
    {
        collision_log("clown request failed: no free agent slot");
        self iprintlnbold("Unable to spawn clown: no free agent slot");
        return 0;
    }

    // This command intentionally reproduces overlap, so bypass the normal safety move.
    clown.iwz_allow_spawn_overlap = 1;
    clown thread scripts\cp\zombies\zombies_spawning::_id_64E7("zombie_clown");
    level notify("agent_spawned", clown);
    collision_log("clown spawned ent=" + clown getentitynumber() + " origin=" + clown.origin);
    self iprintlnbold("Clown spawned at your position");
    return 1;
}
