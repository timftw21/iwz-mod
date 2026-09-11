// IWZ-LOAD: dvar=iwz_noir_foundation
// Stock scripted zombie agents hosted by Noir's multiplayer runtime.

init()
{
    precachemodel("zombie_male_outfit_1");
}

post_load()
{
    log_event("registering stock zombie behavior and animation state machine");
    scripts\mp\agents\zombie\zombie_agent::registerscriptedagent();
    level thread start_combat();
}

log_event(message)
{
    level notify("iwz_gsc_log", "[IWZ][NoirCombat] " + gettime() + " " + message);
}

start_combat()
{
    level endon("game_ended");
    wait 0.1;
    level.agent_funcs["generic_zombie"]["on_damaged_finished"] = ::zombie_damage;
    level.agent_funcs["generic_zombie"]["gametype_on_killed"] = ::zombie_killed;
    level.iwz_noir_normal_death = level.onnormaldeath;
    level.onnormaldeath = ::player_death;
    level.zombiedlclevel = 0;
    level.wave_num = 1;
    level.iwz_noir_alive = 0;
    level.iwz_noir_spawned = 0;
    level.iwz_noir_target = 3;
    level.generic_zombie_model_override_list = ["zombie_male_outfit_1"];
    level thread watch_players();
    if (getdvarint("iwz_noir_test_bot", 0))
    {
        log_event("adding local test bot");
        scripts\mp\bots\bots::spawn_bots(1, "autoassign");
        // The normal bot lobby waits for a human. This local server test has none.
        level.ready_to_start = 1;
    }
    wait 1;
    if (!getdvarint("iwz_noir_zombie_assets") || !getdvarint("iwz_noir_nav_available"))
    {
        log_event("combat stopped: zombie assets or ground navigation missing; check Noir audit");
        return;
    }
    log_event("ready; agent slots=" + getmaxagents());
    if (!scripts\mp\utility::gameflag("prematch_done"))
        level waittill("prematch_over");
    log_event("match started; spawning enabled");
    for (;;)
    {
        player = living_player();
        if (!isdefined(player))
        {
            wait 1;
            continue;
        }
        if (level.iwz_noir_spawned < level.iwz_noir_target && level.iwz_noir_alive < 3)
        {
            origin = spawn_position(player);
            if (isdefined(origin))
            {
                team = "axis";
                if (isdefined(player.team) && player.team == "axis")
                    team = "allies";
                spawner = spawnstruct();
                spawner.script_parameters = "no_boards";
                level.agent_definition["generic_zombie"]["health"] = 150 + 50 * level.wave_num;
                log_event("spawning at=" + origin + " freeAgents=" + scripts\mp\mp_agent::getfreeagentcount());
                zombie = scripts\mp\mp_agent::spawnnewagent("generic_zombie", team, origin,
                    vectortoangles(player.origin - origin), undefined, spawner);
                if (isdefined(zombie))
                {
                    zombie.iwz_noir_counted_dead = 0;
                    zombie.iwz_noir_hits = 0;
                    zombie.entered_playspace = 1;
                    zombie.can_be_killed = 1;
                    level.iwz_noir_alive++;
                    level.iwz_noir_spawned++;
                    log_event("spawn scene=" + level.wave_num + " agent=" + zombie getentitynumber() +
                        " origin=" + zombie.origin + " health=" + zombie.health + " alive=" + level.iwz_noir_alive);
                    zombie thread observe_zombie();
                }
                else
                    log_event("spawn waiting: no free agent slot");
            }
            else
                log_event("spawn waiting: no clear nearby ground navigation point");
        }
        if (level.iwz_noir_spawned == level.iwz_noir_target && level.iwz_noir_alive == 0)
        {
            log_event("scene complete=" + level.wave_num + " kills=" + level.iwz_noir_target);
            iprintlnbold("Scene " + level.wave_num + " complete");
            wait 8;
            level.wave_num++;
            level.iwz_noir_spawned = 0;
            level.iwz_noir_target = int(min(3 + (level.wave_num - 1) * 2, 12));
            iprintlnbold("Scene " + level.wave_num);
        }
        wait 2;
    }
}

living_player()
{
    foreach (player in level.players)
        if (isalive(player) && player.sessionstate == "playing" &&
            (!isdefined(player.iwz_noir_down) || !player.iwz_noir_down))
            return player;
    return undefined;
}

spawn_position(player)
{
    if (getdvarint("iwz_noir_placement"))
    {
        if (!isdefined(level.iwz_noir_layout_ready)) return undefined;
        count = level.iwz_noir_zombie_spawns.size;
        for (i = 0; i < count; i++)
        {
            item = level.iwz_noir_zombie_spawns[(level.iwz_noir_spawned + i) % count];
            point = item.spawn_origin;
            if (!capsuletracepassed(point, 16, 64, undefined, 1, 0, 0, point + (0, 0, 1))) continue;
            crowded = 0;
            foreach (other in level.players)
                if (isalive(other) && distance(other.origin, point) < 256) crowded = 1;
            foreach (other in level.agentarray)
                if (isdefined(other.isactive) && other.isactive && distance(other.origin, point) < 48) crowded = 1;
            if (crowded) continue;
            log_event("authored spawn marker=" + item.id + " origin=" + point);
            return point;
        }
        // Authored layouts never silently fall back to random points elsewhere.
        return undefined;
    }
    for (i = 0; i < 12; i++)
    {
        direction = anglestoforward((0, player.angles[1] + 180 + i * 30, 0));
        desired = player.origin + direction * 480;
        point = getclosestpointonnavmesh(desired);
        if (!isdefined(point) || distance(point, desired) > 96 || distance(point, player.origin) < 300)
            continue;
        clear = capsuletracepassed(point + (0, 0, 8), 16, 64, undefined, 1, 0, 0, point + (0, 0, 9));
        if (!clear)
            continue;
        crowded = 0;
        foreach (other in level.players)
            if (isalive(other) && distance(other.origin, point) < 256)
                crowded = 1;
        foreach (other in level.agentarray)
            if (isdefined(other.isactive) && other.isactive && distance(other.origin, point) < 48)
                crowded = 1;
        if (!crowded)
            return point + (0, 0, 8);
    }
    return undefined;
}

zombie_damage(inflictor, attacker, damage, flags, mod, weapon, point, direction, hitloc,
    time_offset, stun, model_index, part_name)
{
    if (!isalive(self))
        return;
    if (isdefined(attacker) && isplayer(attacker))
    {
        attacker add_points(10);
        if (isdefined(weapon) && issubstr(weapon, "iw7_atomizer_mp") && damage >= self.health)
            self.nocorpse = 1;
    }
    self.iwz_noir_hits++;
    if (self.iwz_noir_hits <= 20)
        log_event("damage agent=" + self getentitynumber() + " amount=" + damage +
            " healthBefore=" + self.health + " weapon=" + weapon + " hitloc=" + hitloc);
    scripts\mp\mp_agent::default_on_damage_finished(inflictor, attacker, damage, flags, mod,
        weapon, point, direction, hitloc, time_offset, stun, model_index, part_name);
}

zombie_killed(inflictor, attacker, damage, mod, weapon, direction, hitloc, time_offset, death_anim)
{
    if (isdefined(self.iwz_noir_counted_dead) && self.iwz_noir_counted_dead)
        return;
    self.iwz_noir_counted_dead = 1;
    // Native min/max return floats. Keep this counter integral for the next
    // spawn's ++; otherwise OP_inc fails and scenes finish with living zombies.
    level.iwz_noir_alive = int(max(0, level.iwz_noir_alive - 1));
    if (isdefined(attacker) && isplayer(attacker))
    {
        reward = 50;
        if (hitloc == "head")
            reward = 100;
        attacker add_points(reward);
        attacker iprintln("+" + reward + " | Points: " + attacker.iwz_noir_points);
    }
    log_event("killed agent=" + self getentitynumber() + " weapon=" + weapon +
        " remaining=" + level.iwz_noir_alive);
    self thread scripts\mp\agents\agent_utility::deactivateagent();
}

add_points(amount)
{
    if (!isdefined(self.iwz_noir_points))
        self.iwz_noir_points = 500;
    self.iwz_noir_points += amount;
    log_event("points player=" + self getentitynumber() + " added=" + amount + " total=" + self.iwz_noir_points);
}

player_death(victim, attacker, weapon, mod, extra)
{
    // MP scoring expects the killer to have player stats. Zombies have no rank,
    // scoreboard or killstreak; the normal player death/respawn pipeline still runs.
    if (isdefined(attacker) && isagent(attacker) &&
        isdefined(attacker.agent_type) && attacker.agent_type == "generic_zombie")
    {
        log_event("player killed=" + victim getentitynumber() + " byAgent=" + attacker getentitynumber());
        return;
    }
    if (isdefined(level.iwz_noir_normal_death))
        [[level.iwz_noir_normal_death]](victim, attacker, weapon, mod, extra);
}

observe_zombie()
{
    self endon("death");
    self endon("agent_in_use");
    level endon("game_ended");
    start = self.origin;
    for (i = 0; i < 30; i++)
    {
        wait 2;
        target = -1;
        if (isdefined(self.curmeleetarget))
            target = self.curmeleetarget getentitynumber();
        log_event("agent=" + self getentitynumber() + " moved=" + distance(start, self.origin) +
            " origin=" + self.origin + " state=" + self.aistate + " target=" + target + " health=" + self.health);
    }
}

watch_players()
{
    level endon("game_ended");
    foreach (player in level.players)
        player attach_player();
    for (;;)
    {
        level waittill("connected", player);
        player attach_player();
    }
}

attach_player()
{
    if (isdefined(self.iwz_noir_combat_attached))
        return;
    self.iwz_noir_combat_attached = 1;
    self.iwz_noir_points = 500;
    self thread observe_player_damage();
}

observe_player_damage()
{
    self endon("disconnect");
    level endon("game_ended");
    for (;;)
    {
        self waittill("damage", damage, attacker, direction, point, mod, model_name, part_name, tag_name, flags, weapon);
        if (isdefined(attacker) && isagent(attacker))
            log_event("player hit=" + self getentitynumber() + " byAgent=" + attacker getentitynumber() +
                " amount=" + damage + " health=" + self.health + " mod=" + mod);
    }
}
