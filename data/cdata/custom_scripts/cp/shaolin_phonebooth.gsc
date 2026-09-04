main()
{
    if (getdvar("ui_mapname") != "cp_disco")
        return;

    intro = getfunction("scripts/cp/maps/cp_disco/phonebooth", "snd_phone_intro");
    play_sound = getfunction("scripts/cp/maps/cp_disco/phonebooth", "playlocalsound_phone");
    if (!isdefined(intro) || !isdefined(play_sound))
    {
        phonebooth_log("installation failed reason=stock-phone-functions-unavailable");
        return;
    }

    level.iwz_phone_play_sound = play_sound;
    replacefunc(intro, ::phone_intro_with_targeting_protection);
    phonebooth_log("installed targeting protection paths=dialpad,morse-call release=phonebooth-end,puzzle-reset,lifecycle");
}

phonebooth_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("ShaolinPhoneBooth", message);
}

phone_intro_with_targeting_protection(puzzle_call)
{
    self endon("exit_phonebooth");
    self endon("dialed");
    self enable_phone_targeting_protection(isdefined(puzzle_call));

    // Both dumps call this shared intro only after accepting the interaction,
    // immediately before playerlinktodelta. Retain its stock audio and timeout.
    if (!isdefined(puzzle_call))
        self [[level.iwz_phone_play_sound]]("receiver_pickup");
    else
    {
        self thread [[level.iwz_phone_play_sound]]("payphone_npc_start_pickup_receiver");
        wait 10.358;
    }

    self notify("timeout");
}

enable_phone_targeting_protection(puzzle_call)
{
    if (!isdefined(self) || !isplayer(self) ||
        scripts\engine\utility::is_true(self.iwz_phone_ignore_active))
        return;

    // Use the same reference-counted API as the Activision cabinet fix. Own one
    // reference per player so ending a call preserves other ignore-me users.
    self.iwz_phone_ignore_active = 1;
    self scripts\cp\utility::allow_player_ignore_me(1);
    self thread restore_targeting_after_phone();
    if (puzzle_call)
        self thread watch_phone_puzzle_reset();

    phonebooth_log("targeting disabled player=" + (self getentitynumber()) +
        " puzzleCall=" + puzzle_call + " ignoreReferences=" + self.enabledignoreme);
}

watch_phone_puzzle_reset()
{
    level endon("game_ended");
    self endon("disconnect");
    self endon("iwz_phone_protection_ended");
    // The quest reset aborts phone_puzzle_call before its phonebooth_end notify.
    level waittill("puzzle_phone_reset");
    self notify("iwz_phone_puzzle_reset");
}

restore_targeting_after_phone()
{
    level endon("game_ended");
    // Do not restore on dialed, timeout, or exit_phonebooth: stock can still be
    // playing the call/outro while the player is linked. Both normal exits emit
    // phonebooth_end after unlinking and restoring controls.
    reason = self scripts\engine\utility::waittill_any_in_array_return_no_endon_death(
        ["phonebooth_end", "iwz_phone_puzzle_reset", "last_stand", "death",
            "disconnect", "spawned", "revive"]);
    if (reason == "disconnect" || !isdefined(self) || !isplayer(self))
        return;

    if (!scripts\engine\utility::is_true(self.iwz_phone_ignore_active))
        return;

    self.iwz_phone_ignore_active = undefined;
    self notify("iwz_phone_protection_ended");
    // zombie::onspawnplayer resets enabledignoreme/ignoreme. A spawn cleanup
    // must discard the old ownership flag without decrementing the new life.
    if (reason != "spawned")
        self scripts\cp\utility::allow_player_ignore_me(0);

    phonebooth_log("targeting restored player=" + (self getentitynumber()) +
        " reason=" + reason + " ignoreReferences=" + self.enabledignoreme +
        " ignoreEnabled=" + self scripts\cp\utility::isignoremeenabled());
}
