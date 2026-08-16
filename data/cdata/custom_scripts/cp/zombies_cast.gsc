main()
{
    level thread monitor_zombies_cast_selection();
    println("[IWZ][ZombiesCast] GSC selection monitor installed");
}

monitor_zombies_cast_selection()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("connected", player);
        selection = iwz_get_zombies_character_selection();
        println("[IWZ][ZombiesCast] GSC connected ent=", player getentitynumber(), " requested=", selection);

        if (selection >= 1 && selection <= 4)
        {
            player._id_CFC4 = selection;

            if (scripts\engine\utility::array_contains(level.available_player_characters, selection))
                level.available_player_characters = scripts\engine\utility::array_remove(level.available_player_characters, selection);

            println("[IWZ][ZombiesCast] GSC field assigned ent=", player getentitynumber(), " value=", player._id_CFC4);
        }

        player thread verify_zombies_cast_selection(selection);
    }
}

verify_zombies_cast_selection(requested)
{
    self endon("disconnect");
    wait 1;

    assigned = -1;
    if (isdefined(self._id_CFC4))
        assigned = self._id_CFC4;

    character_index = -1;
    if (isdefined(self.player_character_index))
        character_index = self.player_character_index;

    println("[IWZ][ZombiesCast] GSC verification ent=", self getentitynumber(), " requested=", requested, " field=", assigned, " player_character_index=", character_index);
}
