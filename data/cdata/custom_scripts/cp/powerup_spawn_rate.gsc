post_load()
{
    level thread install_powerup_spawn_rate();
}

powerup_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Powerups", message);
}

install_powerup_spawn_rate()
{
    level endon("game_ended");

    while (!isdefined(level.powerup_drop_increment) ||
        !isdefined(level.score_to_drop) ||
        !isdefined(level.powerup_drop_count) ||
        !isdefined(level.powerup_drop_max_per_round))
    {
        scripts\engine\utility::waitframe();
    }

    configured_interval = getdvarint("iwz_powerup_drop_base_interval", 1750);
    stock_interval = level.powerup_drop_increment;
    stock_threshold = level.score_to_drop;

    tune_powerup_weights();

    if (configured_interval <= 0)
    {
        powerup_log("stock behavior preserved interval=" + int(stock_interval) +
            " threshold=" + int(stock_threshold) +
            " roundCap=" + level.powerup_drop_max_per_round);
        return;
    }

    // Preserve the starting-score offset that the stock script adds for each
    // connected player while replacing only the random 2000-3000 base interval.
    threshold_offset = stock_threshold - stock_interval;
    if (threshold_offset < 0)
        threshold_offset = 0;

    level.powerup_drop_increment = configured_interval;
    level.score_to_drop = threshold_offset + configured_interval;

    powerup_log("increased spawn rate stockInterval=" + int(stock_interval) +
        " baseInterval=" + configured_interval +
        " nextThreshold=" + int(level.score_to_drop) +
        " roundCap=" + level.powerup_drop_max_per_round);

    level thread monitor_powerup_drops();
}

tune_powerup_weights()
{
    loot_types = ["kill_generic_zombie", "kill_traversal_zombie"];

    foreach (loot_type in loot_types)
    {
        if (!isdefined(level.loot_info[loot_type]) ||
            !isdefined(level.loot_info[loot_type]["weights"]) ||
            !isdefined(level.loot_info[loot_type]["contents"]))
        {
            powerup_log("weight tuning skipped missing table=" + loot_type);
            continue;
        }

        tune_powerup_weight(loot_type, "grenade_30",
            getdvarint("iwz_powerup_weight_infinite_grenades", 2));
        tune_powerup_weight(loot_type, "board_windows",
            getdvarint("iwz_powerup_weight_carpenter", 3));
        tune_powerup_weight(loot_type, "ammo_max",
            getdvarint("iwz_powerup_weight_max_ammo", 12));
        tune_powerup_weight(loot_type, "cash_2",
            getdvarint("iwz_powerup_weight_double_money", 6));
        tune_powerup_weight(loot_type, "instakill_30",
            getdvarint("iwz_powerup_weight_insta_kill", 12));

        level.loot_info[loot_type]["weight_sum"] = get_powerup_weight_sum(loot_type);
        powerup_log("weight table=" + loot_type +
            " total=" + int(level.loot_info[loot_type]["weight_sum"]));
    }
}

tune_powerup_weight(loot_type, powerup, new_weight)
{
    contents = level.loot_info[loot_type]["contents"];

    for (index = 0; index < contents.size; index++)
    {
        if (contents[index]["value"] != powerup)
            continue;

        old_weight = level.loot_info[loot_type]["weights"][index];
        level.loot_info[loot_type]["weights"][index] = new_weight;
        powerup_log("weight table=" + loot_type +
            " powerup=" + powerup +
            " " + int(old_weight) + "->" + new_weight);
        return;
    }

    powerup_log("weight tuning skipped table=" + loot_type +
        " missing powerup=" + powerup);
}

get_powerup_weight_sum(loot_type)
{
    total = 0;

    foreach (weight in level.loot_info[loot_type]["weights"])
        total += weight;

    return total;
}

monitor_powerup_drops()
{
    level endon("game_ended");
    previous_drop_count = level.powerup_drop_count;

    for (;;)
    {
        scripts\engine\utility::waitframe();

        if (!isdefined(level.powerup_drop_count))
            continue;

        if (level.powerup_drop_count < previous_drop_count)
        {
            previous_drop_count = level.powerup_drop_count;
            continue;
        }

        if (level.powerup_drop_count == previous_drop_count)
            continue;

        previous_drop_count = level.powerup_drop_count;
        powerup_log("drop spawned roundCount=" + level.powerup_drop_count +
            "/" + level.powerup_drop_max_per_round +
            " teamScore=" + int(get_team_currency_earned()) +
            " nextThreshold=" + int(level.score_to_drop) +
            " nextInterval=" + int(level.powerup_drop_increment));
    }
}

get_team_currency_earned()
{
    total = 0;

    foreach (player in level.players)
    {
        if (isdefined(player.total_currency_earned))
            total += player.total_currency_earned;
    }

    return total;
}
