post_load()
{
    level thread install_bang_bangs_gesture_fix();
}

bang_bangs_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("BangBangs", message);
}

install_bang_bangs_gesture_fix()
{
    level endon("game_ended");

    while (!isdefined(level.interactions) ||
        !isdefined(level.interactions["perk_machine_rat_a_tat"]) ||
        !isdefined(level.interactions["perk_machine_rat_a_tat"].activation_func))
    {
        scripts\engine\utility::waitframe();
    }

    // Bang Bangs is the only stock perk registered to grant the perk before
    // playing its candy animation. Use the standard gesture-first handler
    // used by the other perk machines.
    level.interactions["perk_machine_rat_a_tat"].activation_func =
        scripts\cp\zombies\zombies_perk_machines::activate_perk_machine;

    level thread monitor_bang_bangs_purchases();
    bang_bangs_log("normalized purchase order to gesture-then-perk; removed one-second pre-gesture weapon display");
}

monitor_bang_bangs_purchases()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("bangbangs_purchased", player);

        if (isdefined(player))
        {
            bang_bangs_log("perk granted after gesture player=" + player getentitynumber());
        }
        else
        {
            bang_bangs_log("perk granted after gesture player=unknown");
        }
    }
}
