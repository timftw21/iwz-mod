// Referenced by noir_section. A freestanding, repairable six-board obstacle.

setup(item)
{
    item.boards = [];
    item.next_repair = 0;
    item.reward_scene = 0;
    item.rewards = 0;
    // This model is the entire six-board assembly, not one plank. Its lowest
    // vertex is 22.516 units above its pivot; place that edge on the marker.
    item.prop = custom_scripts\mp\maps\mp_prime\noir_section::model_at(
        item.origin - (0, 0, 22.516113), item.yaw, "zmb_core_wood_board");
    for (i = 1; i <= 6; i++) item.prop hidepart("board_" + i + "_anim");
    for (i = 0; i < 6; i++) add_board(item);
    level thread watch_barricade(item);
}

add_board(item)
{
    tag = "board_" + (item.boards.size + 1) + "_anim";
    item.prop showpart(tag);
    item.prop solid();
    item.boards[item.boards.size] = tag;
    if (!isdefined(item.obstacle))
        item.obstacle = createnavobstaclebybounds(item.origin + (0, 0, 49), (8, 54, 49), (0, item.yaw, 0));
}

remove_board(item)
{
    count = item.boards.size;
    if (!count) return;
    item.prop hidepart(item.boards[count - 1]);
    remaining = [];
    for (i = 0; i < count - 1; i++) remaining[remaining.size] = item.boards[i];
    item.boards = remaining;
    if (!item.boards.size && isdefined(item.obstacle))
    {
        destroynavobstacle(item.obstacle);
        item.obstacle = undefined;
        item.prop notsolid();
    }
}

watch_barricade(item)
{
    level endon("game_ended");
    for (;;)
    {
        wait 1.5;
        if (!item.boards.size) continue;
        foreach (zombie in level.agentarray)
        {
            if (!isdefined(zombie.isactive) || !zombie.isactive || !isalive(zombie) ||
                !isdefined(zombie.agent_type) || zombie.agent_type != "generic_zombie") continue;
            if (distance(zombie.origin, item.origin) > 96) continue;
            trace = bullettrace(zombie.origin + (0, 0, 40), item.origin + (0, 0, 40), 0, zombie);
            if (trace["fraction"] < 1 && distance(trace["position"], item.origin + (0, 0, 40)) > 50) continue;
            remove_board(item);
            custom_scripts\mp\maps\mp_prime\noir_section::log_event("barricade hit=" + item.id + " agent=" + zombie getentitynumber() + " boards=" + item.boards.size);
            break;
        }
    }
}

repair(item)
{
    if (item.boards.size >= 6 || gettime() < item.next_repair) return 0;
    // Rebuilding must not trap a player or an enemy inside the obstacle.
    foreach (player in level.players)
        if (isalive(player) && distance(player.origin, item.origin) < 40) return 0;
    foreach (zombie in level.agentarray)
        if (isdefined(zombie.isactive) && zombie.isactive && distance(zombie.origin, item.origin) < 40) return 0;
    item.next_repair = gettime() + 1000;
    add_board(item);
    if (item.reward_scene != level.wave_num)
    {
        item.reward_scene = level.wave_num;
        item.rewards = 0;
    }
    if (item.rewards < 6)
    {
        item.rewards++;
        self custom_scripts\mp\maps\mp_prime\noir_zombies::add_points(10);
    }
    custom_scripts\mp\maps\mp_prime\noir_section::log_event("barricade repaired=" + item.id + " boards=" + item.boards.size + " rewardsThisScene=" + item.rewards);
    return 1;
}
