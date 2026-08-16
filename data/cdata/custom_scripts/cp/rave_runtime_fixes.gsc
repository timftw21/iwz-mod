main()
{
    if (getdvar("ui_mapname") != "cp_rave")
        return;

    knife_animation_func = getfunction("scripts/cp/zombies/interaction_knife_throw", "load_animation");
    collect_bait_func = getfunction("scripts/cp/maps/cp_rave/cp_rave_harpoon_quest", "collect_bait");

    if (!isdefined(knife_animation_func) || !isdefined(collect_bait_func))
    {
        custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "installation failed: a stock Rave function was unavailable");
        return;
    }

    replacefunc(knife_animation_func, ::load_knife_throw_animation_stub);
    replacefunc(collect_bait_func, ::collect_bait_stub);
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "installed knife-precache suppression and bait-hint patch");
}

load_knife_throw_animation_stub()
{
    // These stock precache calls raise runtime errors on Rave. The animation
    // assets are already present in cp_dlc1_zombie and play correctly by name.
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "suppressed invalid knife-game animation precaches");
}

collect_bait_stub()
{
    bait_loc = scripts\engine\utility::getstruct("bait_loc", "targetname");
    bait_trigger = spawn("script_model", bait_loc.origin);
    bait_trigger setmodel("tag_origin");
    bait_trigger makeusable();
    bait_trigger sethintstring("Hold ^3[{+usereload,+activate}]^7 to pick up bait");
    level.bait_model = getent("bait_pickup", "targetname");
    custom_scripts\cp\gsc_diagnostics::emit("RaveFixes", "created bait trigger with bound and colorized use hint");

    for (;;)
    {
        bait_trigger waittill("trigger", player);
        player.has_bait = 1;
        player thread scripts\cp\utility::usegrenadegesture(player, "iw7_pickup_zm");
        player thread scripts\cp\powers\coop_powers::givepower("power_bait", "secondary", undefined, undefined, undefined, 1, 1);
        wait(0.1);
        level.bait_model hidefromplayer(player);
    }
}
