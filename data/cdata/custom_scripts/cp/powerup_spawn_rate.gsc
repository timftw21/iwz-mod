main()
{
    apply_infinite_grenade_effects = getfunction(
        "scripts/cp/loot", "apply_infinite_grenade_effects");
    level.iwz_powerup_power_icon_active = getfunction(
        "scripts/cp/loot", "power_icon_active");
    level.iwz_powerup_drop_loot = getfunction(
        "scripts/cp/loot", "drop_loot");
    level.iwz_powerup_finish_power_cooldown = getfunction(
        "scripts/cp_mp/powershud", "powershud_finishpowercooldown");
    power_adjustcharges = getfunction(
        "scripts/cp/powers/coop_powers", "power_adjustcharges");

    if (isdefined(apply_infinite_grenade_effects) &&
        isdefined(level.iwz_powerup_power_icon_active))
    {
        replacefunc(apply_infinite_grenade_effects,
            ::apply_infinite_grenade_effects_preserving_charges);
        powerup_log("installed Infinite Grenades charge-preservation hook; stock duration and icon behavior retained");
    }
    else
    {
        powerup_log("Infinite Grenades charge-preservation hook unavailable apply=" +
            isdefined(apply_infinite_grenade_effects) + " icon=" +
            isdefined(level.iwz_powerup_power_icon_active));
    }

    if (isdefined(power_adjustcharges) &&
        isdefined(level.iwz_powerup_finish_power_cooldown))
    {
        replacefunc(power_adjustcharges,
            ::power_adjustcharges_with_infinite_recharge_sfx);
        powerup_log("installed Infinite Grenades recharge-sound hook alias=mp_ability_ready_L1");
    }
    else
    {
        powerup_log("Infinite Grenades recharge-sound hook unavailable adjust=" +
            isdefined(power_adjustcharges) + " finishHud=" +
            isdefined(level.iwz_powerup_finish_power_cooldown));
    }

    powerup_log("spawnInfiniteGrenades stock drop function available=" +
        isdefined(level.iwz_powerup_drop_loot));
}

post_load()
{
    level thread install_powerup_spawn_rate();

    if (isdefined(level.iwz_powerup_drop_loot))
        level thread listen_for_infinite_grenade_spawn_requests();
}

powerup_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Powerups", message);
}

apply_infinite_grenade_effects_preserving_charges(player)
{
    player.power_cooldowns = 1;
    player.has_infinite_grenade = 1;

    // Stock calls power_adjustcharges(1, "primary", 1) here. The final 1
    // selects absolute assignment, so every primary grenade is overwritten to
    // one charge. Infinite Grenades already owns recharge through
    // level.infinite_grenades; activating it does not need to touch inventory.
    log_preserved_primary_grenade_charges(player);

    duration = 30;
    if (isdefined(level.temporal_increase))
        duration *= level.temporal_increase;

    player thread [[level.iwz_powerup_power_icon_active]](
        duration, "grenade_30");
}

power_adjustcharges_with_infinite_recharge_sfx(adjustment, slot, set_absolute)
{
    if (!isdefined(slot))
        slot = "all";

    power_names = get_registered_player_power_names(self);
    charge_value = adjustment;

    foreach (power_name in power_names)
    {
        if (!isdefined(adjustment))
            charge_value = level.powers[power_name].maxcharges;

        if (self.powers[power_name].slot != slot && slot != "all")
            continue;

        previous_charges = self.powers[power_name].charges;
        if (isdefined(set_absolute))
            self.powers[power_name].charges = int(min(
                charge_value, level.powers[power_name].maxcharges));
        else if (self.powers[power_name].charges + charge_value >= 0)
            self.powers[power_name].charges += charge_value;
        else
            self.powers[power_name].charges = 0;

        self.powers[power_name].charges = int(clamp(
            self.powers[power_name].charges, 0,
            level.powers[power_name].maxcharges));
        self setweaponammoclip(
            self.powers[power_name].weaponuse,
            self.powers[power_name].charges);
        self notify("power_used " + power_name);
        scripts\cp_mp\powershud::powershud_updatepowercharges(
            self.powers[power_name].slot,
            self.powers[power_name].charges);

        if (!isdefined(set_absolute) && isdefined(adjustment) &&
            adjustment > 0 &&
            scripts\engine\utility::is_true(level.infinite_grenades) &&
            self.powers[power_name].slot == "primary" &&
            // Stock's cooldown-to-available HUD transition owns the 0->1 cue.
            // Add the same cue only where that transition no longer occurs.
            previous_charges > 0 &&
            self.powers[power_name].charges > previous_charges)
        {
            // Direct calls to this HUD-owned alias fail the server precache
            // check. Route it through the stock function that owns the alias;
            // the primary slot is already available, so this reasserts the
            // correct full-meter/available HUD state while emitting its cue.
            self [[level.iwz_powerup_finish_power_cooldown]]("primary", 0);
            powerup_log("Infinite Grenades recharge player=" +
                self getentitynumber() + " power=" + power_name +
                " charges=" + previous_charges + "->" +
                self.powers[power_name].charges + "/" +
                level.powers[power_name].maxcharges +
                " alias=mp_ability_ready_L1 source=stock-powershud");
        }
    }
}

get_registered_player_power_names(player)
{
    level_power_names = getarraykeys(level.powers);
    player_power_names = getarraykeys(player.powers);
    registered_power_names = [];
    registered_power_index = 0;

    foreach (player_power_name in player_power_names)
    {
        foreach (level_power_name in level_power_names)
        {
            if (player_power_name != level_power_name)
                continue;

            registered_power_names[registered_power_index] = player_power_name;
            registered_power_index++;
            break;
        }
    }

    return registered_power_names;
}

log_preserved_primary_grenade_charges(player)
{
    if (!isdefined(player.powers))
    {
        powerup_log("Infinite Grenades activated player=" +
            player getentitynumber() + " primary powers unavailable");
        return;
    }

    primary_count = 0;
    foreach (power_name in getarraykeys(player.powers))
    {
        power = player.powers[power_name];
        if (!isdefined(power.slot) || power.slot != "primary")
            continue;

        primary_count++;
        charges = "<undefined>";
        if (isdefined(power.charges))
            charges = power.charges;

        max_charges = "<undefined>";
        if (isdefined(level.powers) && isdefined(level.powers[power_name]) &&
            isdefined(level.powers[power_name].maxcharges))
        {
            max_charges = level.powers[power_name].maxcharges;
        }

        powerup_log("Infinite Grenades preserved player=" +
            player getentitynumber() + " power=" + power_name +
            " charges=" + charges + "/" + max_charges);
    }

    if (primary_count == 0)
    {
        powerup_log("Infinite Grenades activated player=" +
            player getentitynumber() + " primary powers=0");
    }
}

listen_for_infinite_grenade_spawn_requests()
{
    level endon("game_ended");
    powerup_log("spawnInfiniteGrenades listener installed map=" + level.script);

    for (;;)
    {
        level waittill("iwz_spawn_infinite_grenade_powerup", player);
        if (!isdefined(player) || !isplayer(player))
        {
            powerup_log("spawnInfiniteGrenades rejected invalid player");
            continue;
        }

        player_angles = player getplayerangles();
        forward = anglestoforward((0, player_angles[1], 0));
        spawn_origin = player.origin + forward * 64 + (0, 0, 24);
        spawn_origin = scripts\engine\utility::drop_to_ground(
            spawn_origin, 48, -160);

        spawned = [[level.iwz_powerup_drop_loot]](
            spawn_origin, undefined, "grenade_30", 0, undefined, 1);
        powerup_log("spawnInfiniteGrenades requested player=" +
            player getentitynumber() + " origin=" + spawn_origin +
            " spawned=" + spawned);

        if (spawned)
            player iprintlnbold("Spawned Infinite Grenades powerup");
        else
            player iprintlnbold("Unable to spawn Infinite Grenades powerup");
    }
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

    configured_interval = getdvarint("iwz_powerup_drop_base_interval", 2250);
    interval_revision = getdvarint("iwz_powerup_drop_interval_revision", 0);

    // The dvar is archived, so existing installations retain the old 1900
    // default in config_mp.cfg even after the executable's default changes.
    // Migrate that exact old default once while preserving deliberate custom
    // values.
    if (interval_revision < 1)
    {
        previous_interval = configured_interval;
        if (configured_interval == 1900)
        {
            configured_interval = 2250;
            setdvar("iwz_powerup_drop_base_interval", configured_interval);
        }

        setdvar("iwz_powerup_drop_interval_revision", 1);
        powerup_log("interval migration revision=1 previous=" + previous_interval +
            " current=" + configured_interval +
            " migrated=" + int(previous_interval == 1900));
    }
    stock_interval = level.powerup_drop_increment;
    stock_threshold = level.score_to_drop;

    migrate_powerup_weight_defaults();
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

migrate_powerup_weight_defaults()
{
    revision = getdvarint("iwz_powerup_weight_revision", 0);
    if (revision >= 1)
        return;

    migrated = 0;
    migrated += migrate_powerup_weight_default("iwz_powerup_weight_infinite_grenades", 2, 4);
    migrated += migrate_powerup_weight_default("iwz_powerup_weight_carpenter", 3, 4);
    migrated += migrate_powerup_weight_default("iwz_powerup_weight_max_ammo", 12, 11);
    migrated += migrate_powerup_weight_default("iwz_powerup_weight_double_money", 6, 5);
    migrated += migrate_powerup_weight_default("iwz_powerup_weight_insta_kill", 12, 11);
    setdvar("iwz_powerup_weight_revision", 1);

    powerup_log("weight migration revision=1 migrated=" + migrated +
        " preserved=" + (5 - migrated));
}

migrate_powerup_weight_default(dvar_name, old_default, new_default)
{
    current = getdvarint(dvar_name, new_default);
    if (current != old_default)
    {
        powerup_log("weight migration preserved dvar=" + dvar_name +
            " value=" + current);
        return 0;
    }

    setdvar(dvar_name, new_default);
    powerup_log("weight migration updated dvar=" + dvar_name +
        " " + old_default + "->" + new_default);
    return 1;
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
            getdvarint("iwz_powerup_weight_infinite_grenades", 4));
        tune_powerup_weight(loot_type, "board_windows",
            getdvarint("iwz_powerup_weight_carpenter", 4));
        tune_powerup_weight(loot_type, "ammo_max",
            getdvarint("iwz_powerup_weight_max_ammo", 11));
        tune_powerup_weight(loot_type, "cash_2",
            getdvarint("iwz_powerup_weight_double_money", 5));
        tune_powerup_weight(loot_type, "instakill_30",
            getdvarint("iwz_powerup_weight_insta_kill", 11));

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
        wait(0.25);

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
