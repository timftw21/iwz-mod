main()
{
    // Stock cp_merits awards the XP but omits give_player_xp's notification
    // flag. Door/barrier rewards pass 1 here, which drives zom_xp_reward and
    // zom_xp_notify and produces the native on-screen XP popup.
    replacefunc(scripts\cp\cp_merits::giverankxpafterwait, ::give_rank_xp_after_wait_stub);
    challenge_log("installed tier award hook popup=stock_zom_xp");
}

post_load()
{
    level thread tune_tier_five_rewards();
    level thread listen_for_barrier_tier_one_test_requests();
    level thread listen_for_barrier_tier_five_test_requests();
}

challenge_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Challenges", message);
}

tune_tier_five_rewards()
{
    level endon("game_ended");

    while (!isdefined(level.meritinfo))
        scripts\engine\utility::waitframe();

    tier_five_xp = getdvarint("iwz_challenge_tier5_xp", 2500);
    tuned_count = 0;
    unexpected_count = 0;

    foreach (merit_ref, merit in level.meritinfo)
    {
        if (!isdefined(merit["reward"]) || !isdefined(merit["reward"][4]))
            continue;

        old_reward = int(merit["reward"][4]);
        if (old_reward != 1000 && old_reward != tier_five_xp)
            unexpected_count++;

        level.meritinfo[merit_ref]["reward"][4] = tier_five_xp;
        tuned_count++;
    }

    challenge_log("Tier 5 rewards tuned count=" + tuned_count +
        " xp=" + tier_five_xp + " unexpectedStockValues=" + unexpected_count);
}

give_rank_xp_after_wait_stub(merit_ref, tier_index)
{
    self endon("disconnect");
    level endon("game_ended");
    wait(0.25);

    if (!isdefined(level.meritinfo) ||
        !isdefined(level.meritinfo[merit_ref]) ||
        !isdefined(level.meritinfo[merit_ref]["reward"]) ||
        !isdefined(level.meritinfo[merit_ref]["reward"][tier_index]))
    {
        challenge_log("XP award skipped missing reward player=" + self getentitynumber() +
            " merit=" + merit_ref + " tier=" + (tier_index + 1));
        return;
    }

    reward = int(level.meritinfo[merit_ref]["reward"][tier_index]);
    if (tier_index == 4)
        reward = getdvarint("iwz_challenge_tier5_xp", 2500);

    highest_tier = tier_index == level.meritinfo[merit_ref]["reward"].size - 1;
    calling_card = "";
    if (highest_tier)
        calling_card = tablelookup("cp/allMeritsTable.csv", 0, merit_ref, 3);

    challenge_log("awarding player=" + self getentitynumber() +
        " merit=" + merit_ref + " tier=" + (tier_index + 1) +
        " highest=" + highest_tier + " callingCard=" + calling_card +
        " baseXP=" + reward + " popup=stock_zom_xp");

    scripts\cp\cp_persistence::give_player_xp(reward, 1);
}

listen_for_barrier_tier_one_test_requests()
{
    level endon("game_ended");
    challenge_log("testBarrierTier1 listener installed merit=mt_purchase_doors tier=1");

    for (;;)
    {
        level waittill("iwz_test_barrier_tier1", player);
        player stage_barrier_tier_test(1, "testBarrierTier1");
    }
}

listen_for_barrier_tier_five_test_requests()
{
    level endon("game_ended");
    challenge_log("testBarrierTier5 listener installed merit=mt_purchase_doors tier=5");

    for (;;)
    {
        level waittill("iwz_test_barrier_tier5", player);
        player stage_barrier_tier_test(5, "testBarrierTier5");
    }
}

stage_barrier_tier_test(tier_number, command_name)
{
    merit_ref = "mt_purchase_doors";

    if (!isdefined(self) || !isplayer(self))
    {
        challenge_log(command_name + " rejected reason=invalid player");
        return;
    }

    if (!isdefined(level.meritinfo) ||
        !isdefined(level.meritinfo[merit_ref]) ||
        !isdefined(level.meritinfo[merit_ref]["targetval"]) ||
        !level.meritinfo[merit_ref]["targetval"].size ||
        !isdefined(self.meritdata))
    {
        challenge_log(command_name + " rejected player=" + self getentitynumber() +
            " reason=merit runtime not ready");
        self iprintlnbold("Barrier challenge data is not ready");
        return;
    }

    tier_count = level.meritinfo[merit_ref]["targetval"].size;
    tier_index = tier_number - 1;
    if (tier_index < 0 || tier_index >= tier_count)
    {
        challenge_log(command_name + " rejected player=" + self getentitynumber() +
            " reason=invalid tier tier=" + tier_number + " tierCount=" + tier_count);
        self iprintlnbold("Barrier challenge tier is unavailable");
        return;
    }

    target = int(level.meritinfo[merit_ref]["targetval"][tier_index]);
    staged_progress = target - 1;
    old_state = scripts\cp\cp_hud_util::mt_getstate(merit_ref);
    old_progress = scripts\cp\cp_hud_util::mt_getprogress(merit_ref);

    scripts\cp\cp_hud_util::mt_setstate(merit_ref, tier_index);
    scripts\cp\cp_hud_util::mt_setprogress(merit_ref, staged_progress);

    // cp_merits::processmerit reads this per-match cache before persistent
    // player data, so keep the stock runtime mirror synchronized immediately.
    self.meritdata[merit_ref] = tier_index;

    challenge_log(command_name + " staged player=" + self getentitynumber() +
        " merit=" + merit_ref + " tier=" + tier_number + "/" + tier_count +
        " state=" + old_state + "->" + tier_index +
        " progress=" + old_progress + "->" + staged_progress +
        " target=" + target + " nextBarrierCompletesTier=1");
    self iprintlnbold("Barrier Tier " + tier_number + " staged: " + staged_progress + " / " + target);
}
