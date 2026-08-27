main()
{
    if (getdvar("ui_mapname") != "cp_disco")
        return;

    prepare_sky_steps = getfunction(
        "scripts/cp/maps/cp_disco/cp_disco_ghost_activation", "prepare_sky_steps");
    activate_sky_step = getfunction(
        "scripts/cp/maps/cp_disco/cp_disco_ghost_activation", "activate_sky_step");
    deactivate_sky_step = getfunction(
        "scripts/cp/maps/cp_disco/cp_disco_ghost_activation", "deactivate_sky_step");

    if (!isdefined(prepare_sky_steps) || !isdefined(activate_sky_step) ||
        !isdefined(deactivate_sky_step))
    {
        skullbuster_platform_log(
            "installation failed: a required stock Skullbuster function was unavailable");
        return;
    }

    // These references are used only by the test command. The retail platform
    // preparation, movement, activation, and timeout functions are not replaced.
    level.iwz_sky_step_prepare = prepare_sky_steps;
    level.iwz_sky_step_activate = activate_sky_step;
    level.iwz_sky_step_deactivate = deactivate_sky_step;
    skullbuster_platform_log(
        "retained stock platform relocation, activation, deactivation, and timeout behavior");
}

post_load()
{
    if (getdvar("ui_mapname") != "cp_disco")
        return;

    install_sky_step_edge_supports();
    level thread listen_for_skullbuster_platform_test_command();
    skullbuster_platform_log("started testSkullbusterPlatforms command listener");
}

skullbuster_platform_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("ShaolinSkullbuster", message);
}

install_sky_step_edge_supports()
{
    sky_steps = getentarray("sky_step_clip", "targetname");
    if (!isdefined(sky_steps) || sky_steps.size == 0)
    {
        skullbuster_platform_log("edge support installation failed: no sky_step_clip entities");
        return;
    }

    // Retail player_is_on_top_sky_step accepts a player within 20 units of the
    // brush origin (distance-squared <= 400). Extend the physical top one unit
    // beyond that scripted boundary so its edge cannot disagree with the quest
    // predicate while a landing is being resolved.
    desired_half_extent = 21;
    configured_platforms = 0;

    foreach (sky_step in sky_steps)
    {
        collision_half_size = sky_step iwzgetcollisionhalfsize();
        expansion_x = desired_half_extent - collision_half_size[0];
        expansion_y = desired_half_extent - collision_half_size[1];

        if (expansion_x < 0)
            expansion_x = 0;
        if (expansion_y < 0)
            expansion_y = 0;

        if (expansion_x == 0 && expansion_y == 0)
        {
            skullbuster_platform_log("edge support unnecessary ent=" +
                sky_step getentitynumber() + " model=" + sky_step.model +
                " halfSize=" + collision_half_size);
            continue;
        }

        // Linked brush children are not reliable predicted player collision after
        // their parent is warped from the storage grid to the challenge route.
        // Keep the authored brush movement untouched and create fresh, unlinked
        // collision at the final world-space position whenever a step activates.
        // Eight neighbors are required: diagonal-only helpers leave uncovered
        // strips along the middle of every edge.
        sky_step.iwz_edge_expansion_x = expansion_x;
        sky_step.iwz_edge_expansion_y = expansion_y;
        sky_step thread monitor_sky_step_edge_supports();
        configured_platforms++;

        skullbuster_platform_log("edge support configured ent=" +
            sky_step getentitynumber() + " model=" + sky_step.model +
            " stockHalfSize=" + collision_half_size +
            " expansion=(" + expansion_x + ", " + expansion_y + ", 0)" +
            " supportedHalfExtent=" + desired_half_extent);
    }

    skullbuster_platform_log("edge support configuration complete platforms=" +
        configured_platforms + " helperMode=fresh-unlinked-on-activation" +
        " supportedHalfExtent=" + desired_half_extent);
}

monitor_sky_step_edge_supports()
{
    level endon("game_ended");
    self endon("death");

    supports_active = 0;

    for (;;)
    {
        platform_active = isdefined(self.activated) && self.activated == 1;

        if (platform_active && !supports_active)
        {
            create_sky_step_edge_supports();
            supports_active = 1;
        }
        else if (!platform_active && supports_active)
        {
            delete_sky_step_edge_supports();
            supports_active = 0;
        }

        scripts\engine\utility::waitframe();
    }
}

create_sky_step_edge_supports()
{
    if (isdefined(self.iwz_edge_supports))
        return;

    expansion_x = self.iwz_edge_expansion_x;
    expansion_y = self.iwz_edge_expansion_y;
    offsets = [
        (expansion_x, 0, 0),
        (0 - expansion_x, 0, 0),
        (0, expansion_y, 0),
        (0, 0 - expansion_y, 0),
        (expansion_x, expansion_y, 0),
        (expansion_x, 0 - expansion_y, 0),
        (0 - expansion_x, expansion_y, 0),
        (0 - expansion_x, 0 - expansion_y, 0)
    ];
    self.iwz_edge_supports = [];

    foreach (offset in offsets)
    {
        support = spawn("script_model", self.origin + offset);
        support clonebrushmodeltoscriptmodel(self);
        support dontinterpolate();
        self.iwz_edge_supports[self.iwz_edge_supports.size] = support;
        support thread delete_edge_support_with_source(self);
    }

    skullbuster_platform_log("edge support activated sourceEnt=" +
        self getentitynumber() + " sourceOrigin=" + self.origin +
        " helperCount=" + self.iwz_edge_supports.size +
        " firstHelperEnt=" + self.iwz_edge_supports[0] getentitynumber() +
        " firstHelperOrigin=" + self.iwz_edge_supports[0].origin +
        " linked=0 coverage=continuous-3x3-grid");
}

delete_sky_step_edge_supports()
{
    if (!isdefined(self.iwz_edge_supports))
        return;

    helper_count = 0;
    foreach (support in self.iwz_edge_supports)
    {
        if (isdefined(support))
        {
            support delete();
            helper_count++;
        }
    }

    self.iwz_edge_supports = undefined;
    skullbuster_platform_log("edge support deactivated sourceEnt=" +
        self getentitynumber() + " sourceOrigin=" + self.origin +
        " deletedHelpers=" + helper_count);
}

delete_edge_support_with_source(source)
{
    level endon("game_ended");
    self endon("death");

    while (isdefined(source))
        scripts\engine\utility::waitframe();

    self delete();
}

listen_for_skullbuster_platform_test_command()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_test_skullbuster_platforms", player);

        if (!isdefined(player) || !isplayer(player))
        {
            skullbuster_platform_log(
                "testSkullbusterPlatforms rejected: player unavailable");
            continue;
        }

        if (scripts\engine\utility::is_true(level.iwz_sky_step_test_active))
        {
            disable_skullbuster_platform_test();
            player iprintlnbold("Skullbuster platform test disabled");
            continue;
        }

        if (isdefined(level.sky_steps))
        {
            skullbuster_platform_log(
                "testSkullbusterPlatforms rejected: stock platform challenge is active");
            player iprintlnbold("Skullbuster platform challenge is already active");
            continue;
        }

        enable_skullbuster_platform_test(player);
    }
}

enable_skullbuster_platform_test(player)
{
    [[level.iwz_sky_step_prepare]]();

    start_target = scripts\engine\utility::getstruct("sky_step_start", "targetname");
    if (!isdefined(start_target) || level.sky_steps.size == 0)
    {
        skullbuster_platform_log(
            "testSkullbusterPlatforms failed: platform entities or start target unavailable");
        disable_skullbuster_platform_test();
        player iprintlnbold("Skullbuster platforms are not ready");
        return;
    }

    level.iwz_sky_step_test_active = 1;
    active_step = [[level.iwz_sky_step_activate]](start_target, 0);
    active_count = 0;
    if (isdefined(active_step))
        active_count = 1;
    tier = 1;

    while (active_count < level.sky_steps.size)
    {
        targets = get_test_sky_step_targets_at_tier(tier, active_step);
        if (targets.size == 0)
            break;

        target = scripts\engine\utility::random(targets);
        active_step = [[level.iwz_sky_step_activate]](target, 0);
        if (!isdefined(active_step))
            break;

        active_count++;
        tier++;
    }

    skullbuster_platform_log("testSkullbusterPlatforms enabled player=" +
        player getentitynumber() + " activePlatforms=" + active_count +
        " finalTier=" + (tier - 1) + " stockTimeouts=disabled");
    player iprintlnbold("Skullbuster platform test enabled; run command again to disable");
}

get_test_sky_step_targets_at_tier(tier, previous_step)
{
    authored_targets = scripts\engine\utility::getstructarray(
        "sky_step_tier_" + tier, "targetname");
    valid_targets = [];

    foreach (target in authored_targets)
    {
        // Exact stock reachability constraint: 165 squared is 27,225.
        if (distancesquared(previous_step.origin, target.origin) <= 27225)
            valid_targets[valid_targets.size] = target;
    }

    return valid_targets;
}

disable_skullbuster_platform_test()
{
    active_count = 0;

    if (isdefined(level.sky_steps))
    {
        foreach (sky_step in level.sky_steps)
        {
            if (sky_step.activated == 1)
            {
                [[level.iwz_sky_step_deactivate]](sky_step);
                active_count++;
            }

            if (isdefined(sky_step.sky_step_vfx))
            {
                sky_step.sky_step_vfx delete();
                sky_step.sky_step_vfx = undefined;
            }
        }
    }

    level.sky_steps = undefined;
    level.iwz_sky_step_test_active = undefined;
    skullbuster_platform_log(
        "testSkullbusterPlatforms disabled activePlatforms=" + active_count +
        " relocation=stock");
}
