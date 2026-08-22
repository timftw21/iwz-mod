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
    level thread tune_challenge_rewards();
    level thread listen_for_barrier_tier_one_test_requests();
    level thread listen_for_barrier_tier_five_test_requests();
}

challenge_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Challenges", message);
}

is_master_challenge(merit_ref)
{
    // The calling-card table is the same source used by LUI to classify a
    // challenge as Master. This excludes unrelated one-tier 500 XP merits.
    return tablelookup("mp/callingCards.csv", 4, merit_ref, 5) == "TRUE";
}

get_challenge_final_requirements()
{
    requirements = [];
    requirements["mt_dlc1_all_ziplines"] = 25;
    requirements["mt_dlc1_sasquatch_kills"] = 100;
    requirements["mt_dlc1_charms_added"] = 15;
    requirements["mt_dlc1_challenge_badge"] = 25;
    requirements["mt_dlc2_roller_skaters"] = 100;
    requirements["mt_dlc2_chi_master"] = 15;
    requirements["mt_dlc4_entangler_kills"] = 100;
    requirements["mt_dlc4_special_wave_kills"] = 100;
    return requirements;
}

tune_challenge_rewards()
{
    level endon("game_ended");

    while (!isdefined(level.meritinfo))
        scripts\engine\utility::waitframe();

    tier_five_xp = getdvarint("iwz_challenge_tier5_xp", 2500);
    tuned_count = 0;
    unexpected_count = 0;
    career_count = 0;
    unexpected_career_count = 0;
    master_count = 0;
    unexpected_master_count = 0;

    challenge_requirements = get_challenge_final_requirements();
    requirement_count = 0;
    missing_requirement_count = 0;

    foreach (merit_ref, final_target in challenge_requirements)
    {
        if (!isdefined(level.meritinfo[merit_ref]) ||
            !isdefined(level.meritinfo[merit_ref]["targetval"]) ||
            !isdefined(level.meritinfo[merit_ref]["targetval"][4]))
        {
            missing_requirement_count++;
            challenge_log("Challenge requirements unavailable merit=" + merit_ref +
                " finalTarget=" + final_target);
            continue;
        }

        old_final_target = int(level.meritinfo[merit_ref]["targetval"][4]);
        tier_step = int(final_target / 5);
        for (tier_index = 0; tier_index < 5; tier_index++)
            level.meritinfo[merit_ref]["targetval"][tier_index] =
                tier_step * (tier_index + 1);

        requirement_count++;
        challenge_log("Challenge requirements tuned merit=" + merit_ref +
            " stockFinal=" + old_final_target + " targets=" + tier_step + "," +
            (tier_step * 2) + "," + (tier_step * 3) + "," +
            (tier_step * 4) + "," + (tier_step * 5));
    }

    foreach (merit_ref, merit in level.meritinfo)
    {
        if (!isdefined(merit["reward"]))
            continue;

        if (is_master_challenge(merit_ref))
        {
            foreach (tier_index, reward in merit["reward"])
            {
                if (int(reward) != 500 && int(reward) != 5000 && int(reward) != 10000)
                    unexpected_master_count++;

                level.meritinfo[merit_ref]["reward"][tier_index] = 10000;
                master_count++;
            }

            continue;
        }

        if (tablelookup("cp/allMeritsTable.csv", 0, merit_ref, 6) == "zmcareer")
        {
            foreach (tier_index, reward in merit["reward"])
            {
                if (int(reward) != 1000 && int(reward) != 5000)
                    unexpected_career_count++;

                level.meritinfo[merit_ref]["reward"][tier_index] = 5000;
                career_count++;
            }

            continue;
        }

        if (!isdefined(merit["reward"][4]))
            continue;

        old_reward = int(merit["reward"][4]);
        if (old_reward != 1000 && old_reward != tier_five_xp)
            unexpected_count++;

        level.meritinfo[merit_ref]["reward"][4] = tier_five_xp;
        tuned_count++;
    }

    challenge_log("Tier 5 rewards tuned count=" + tuned_count +
        " xp=" + tier_five_xp + " unexpectedStockValues=" + unexpected_count +
        " careerRewards=" + career_count + " careerXP=5000" +
        " unexpectedCareerValues=" + unexpected_career_count +
        " masterRewards=" + master_count + " masterXP=10000" +
        " unexpectedMasterValues=" + unexpected_master_count +
        " requirements=" + requirement_count +
        " tiersPerRequirement=5" +
        " missingRequirements=" + missing_requirement_count);
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
    if (is_master_challenge(merit_ref))
        reward = 10000;
    else if (tablelookup("cp/allMeritsTable.csv", 0, merit_ref, 6) == "zmcareer")
        reward = 5000;
    else if (tier_index == 4)
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
