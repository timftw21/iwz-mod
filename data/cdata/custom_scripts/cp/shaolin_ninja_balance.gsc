post_load()
{
    if (getdvar("ui_mapname") != "cp_disco")
        return;

    level thread monitor_ninja_spawns();
    level thread configure_existing_ninjas();
    ninja_balance_log("installed stock bdisableteleport control and 1.15 locomotion scale");
}

ninja_balance_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("ShaolinNinjas", message);
}

monitor_ninja_spawns()
{
    level endon("game_ended");
    ninja_balance_log("agent_spawned monitor installed");

    for (;;)
    {
        level waittill("agent_spawned", agent);
        configure_ninja(agent, "agent-spawned");
    }
}

configure_existing_ninjas()
{
    level endon("game_ended");

    while (!isdefined(level.spawned_enemies))
        scripts\engine\utility::waitframe();

    configured = 0;
    foreach (enemy in level.spawned_enemies)
    {
        if (configure_ninja(enemy, "existing-scan"))
            configured++;
    }

    ninja_balance_log("existing enemy scan complete configured=" + configured);
}

configure_ninja(agent, source)
{
    if (!isdefined(agent) || !isdefined(agent.agent_type) ||
        agent.agent_type != "karatemaster" ||
        scripts\engine\utility::is_true(agent.iwz_ninja_balance_configured))
    {
        return 0;
    }

    stock_move_rate = agent.moveratescale;

    // karatemaster::shouldteleport checks this authored field before traversal,
    // sprint-response, damage-response, crowding, and distance teleport logic.
    agent.bdisableteleport = 1;

    // The karate-master ASM applies moveratescale only while entering or
    // playing locomotion states. Melee animations retain their stock playback.
    agent.moveratescale = 1.15;
    agent.iwz_ninja_balance_configured = 1;

    ninja_balance_log("configured ent=" + agent getentitynumber() +
        " source=" + source + " teleportDisabled=" + agent.bdisableteleport +
        " moveRate=" + stock_move_rate + "->" + agent.moveratescale);
    return 1;
}
