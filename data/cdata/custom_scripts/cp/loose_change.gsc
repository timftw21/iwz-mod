post_load()
{
    level thread initialize_loose_change();
}

loose_change_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("LooseChange", message);
}

initialize_loose_change()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        scripts\engine\utility::waitframe();

    scripts\engine\utility::flag_wait("init_interaction_done");

    level.iwz_loose_change_machines = [];

    foreach (interaction in level.all_interaction_structs)
    {
        if (!isdefined(interaction.script_noteworthy) || !issubstr(interaction.script_noteworthy, "perk_machine_"))
            continue;

        interaction.iwz_loose_change_id = level.iwz_loose_change_machines.size;
        level.iwz_loose_change_machines[level.iwz_loose_change_machines.size] = interaction;

        loose_change_log("registered machine id=" + interaction.iwz_loose_change_id + " type=" + interaction.script_noteworthy + " origin=" + interaction.origin);
    }

    loose_change_log("initialized map=" + getdvar("ui_mapname") + " machines=" + level.iwz_loose_change_machines.size + " baseReward=100 doubleMoneySource=level.cash_scalar range=72 sound=purchase_generic");

    level thread monitor_loose_change_players();

    foreach (player in level.players)
        player thread monitor_loose_change();
}

monitor_loose_change_players()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("connected", player);
        player thread monitor_loose_change();
    }
}

monitor_loose_change()
{
    self endon("disconnect");
    level endon("game_ended");

    if (isdefined(self.iwz_loose_change_monitor))
        return;

    self.iwz_loose_change_monitor = true;
    self.iwz_loose_change_claimed = [];
    loose_change_log("player monitor attached player=" + self getentitynumber());

    for (;;)
    {
        if (isalive(self) && !scripts\engine\utility::is_true(self.inlaststand) && self getstance() == "prone")
        {
            foreach (machine in level.iwz_loose_change_machines)
            {
                machine_id = machine.iwz_loose_change_id;

                if (isdefined(self.iwz_loose_change_claimed[machine_id]))
                    continue;

                distance_squared = distancesquared(self.origin, machine.origin);

                if (distance_squared > 5184)
                    continue;

                if (!sighttracepassed(self geteye(), machine.origin + (0, 0, 24), 0, self))
                    continue;

                self.iwz_loose_change_claimed[machine_id] = true;
                cash_scalar = 1;
                if (isdefined(level.cash_scalar))
                    cash_scalar = level.cash_scalar;

                // Stock cp_reward applies Double Money's level.cash_scalar
                // before calling give_player_currency. Loose change owns its
                // own award, so it must cross the same scoring boundary.
                reward = int(100 * cash_scalar);
                currency_before = self scripts\cp\cp_persistence::get_player_currency();
                self scripts\cp\cp_persistence::give_player_currency(reward, undefined, undefined, 1, "loose_change");
                currency_after = self scripts\cp\cp_persistence::get_player_currency();

                if (soundexists("purchase_generic"))
                    playsoundatpos(machine.origin, "purchase_generic");
                else
                    loose_change_log("purchase sound missing alias=purchase_generic");

                loose_change_log("awarded player=" + self getentitynumber() + " machine=" + machine.script_noteworthy + " id=" + machine_id + " distance=" + int(sqrt(distance_squared)) + " reward=" + reward + " cashScalar=" + cash_scalar + " currency=" + currency_before + "->" + currency_after);
                break;
            }
        }

        wait(0.1);
    }
}
