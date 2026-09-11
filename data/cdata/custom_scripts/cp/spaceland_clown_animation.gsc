// IWZ-LOAD: map=cp_zmb
main()
{
    if (getdvar("ui_mapname") != "cp_zmb")
        return;

    move_changed = getfunction("scripts/asm/zombie/zombie", "_id_BCCD");
    if (!isdefined(move_changed))
    {
        clown_animation_log("installation failed: stock movement-change check unavailable");
        return;
    }

    replacefunc(move_changed, ::movement_mode_changed);
    clown_animation_log("installed movement-change check matching stock forced clown sprint selection");
}

movement_mode_changed()
{
    // Preserve the stock brute exception and uninitialized-state behavior.
    if (isdefined(self.agent_type) && self.agent_type == "zombie_brute")
        return 0;
    if (!isdefined(self.asm.cur_move_mode))
        return 0;

    requested = self._blackboard.movetype;
    desired = requested;
    // zombie::_id_BE9A always selects sprint for suicide bombers, ahead of
    // the ordinary walk/run requests. _id_BCCD must compare against that same
    // effective mode. Otherwise a pending spawn request or the shared late-
    // round walker override repeatedly re-enters sprint_loop_clown, restarting
    // its clip every ASM tick while navigation continues to move the clown.
    if (scripts\engine\utility::is_true(self.is_suicide_bomber))
    {
        desired = "sprint";
        if (self.asm.cur_move_mode == desired && requested != desired)
            log_clown_request_mismatch(requested);
    }

    // A walking zombie transformed into a clown must still enter sprint once.
    return self.asm.cur_move_mode != desired;
}

log_clown_request_mismatch(requested)
{
    // Once per request per spawn; the prevented restart can recur every tick.
    if (isdefined(self.iwz_clown_log_spawn) && self.iwz_clown_log_spawn == self.connecttime &&
        isdefined(self.iwz_clown_log_request) && self.iwz_clown_log_request == requested)
        return;

    self.iwz_clown_log_spawn = self.connecttime;
    self.iwz_clown_log_request = requested;
    clown_animation_log("prevented sprint restart ent=" + (self getentitynumber()) +
        " model=" + self.model + " wave=" + level.wave_num + " requested=" + requested +
        " effective=sprint current=" + self.asm.cur_move_mode +
        " velocity=" + (self getvelocity()));
}

clown_animation_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("ClownAnimation", message);
}
