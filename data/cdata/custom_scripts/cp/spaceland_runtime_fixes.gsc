main()
{
    // Physical games that temporarily remove the player's weapon use this path.
    replacefunc(scripts\cp\zombies\arcade_game_utility::saveplayerpregameweapon,
        ::save_player_pre_arcade_weapon_stub);

    // The eight Activision cabinets do not save the player's weapon. Both GSC
    // dumps show that their shared zombie_arcade_games::use_arcade_game entry
    // calls this award helper before linking the player to the cabinet.
    replacefunc(scripts\cp\zombies\arcade_game_utility::set_arcade_game_award_type,
        ::set_arcade_game_award_type_stub);

    // The stock Activision-cabinet timer awards 10 tickets every ten seconds.
    // Keep its gesture and afterlife soul-power behavior, but remove the live
    // player's passive ticket reward now that the cabinet is a safe activity.
    replacefunc(scripts\cp\zombies\zombie_arcade_games::_id_211A,
        ::activision_cabinet_reward_timer_stub);
    spaceland_log("installed arcade targeting hooks paths=weapon-save,award-type sourceHandoff=1 cabinetTickets=disabled");

    if (getdvar("ui_mapname") == "cp_zmb")
    {
        seticom_damage_monitor = getfunction(
            "scripts/cp/maps/cp_zmb/cp_zmb_dj", "damage_monitor");
        seticom_unlock_monitor = getfunction(
            "scripts/cp/maps/cp_zmb/cp_zmb_dj",
            "removelockedonflagonspeakerdeath");
        seticom_failure = getfunction(
            "scripts/cp/maps/cp_zmb/cp_zmb_dj", "defense_sequence_fail");
        if (isdefined(seticom_damage_monitor) &&
            isdefined(seticom_unlock_monitor) && isdefined(seticom_failure))
        {
            level.iwz_seticom_unlock_monitor = seticom_unlock_monitor;
            level.iwz_seticom_failure = seticom_failure;
            replacefunc(seticom_damage_monitor, ::seticom_damage_monitor_stub);
            spaceland_log("installed Seti-Com durability hook stockHits=10 hits=15 hudDenominator=15");
        }
        else
        {
            spaceland_log("Seti-Com durability hook unavailable: required cp_zmb_dj function lookup failed");
        }
    }
}

post_load()
{
    if (!isdefined(level.script) || level.script != "cp_zmb")
        return;

    level thread tune_alien_kill_xp();
    level thread listen_for_alien_kill_test_requests();
    level thread listen_for_alien_fuse_spawn_requests();
    level thread install_double_pap_persistence();
}

spaceland_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Spaceland", message);
}

seticom_damage_monitor_stub(seticom, damage_clip)
{
    level endon("speaker_defense_completed");
    level endon("destroy_speaker");
    seticom endon("death");

    // cp_zmb_dj::set_up_and_start_speaker starts the damage thread before it
    // assigns the stock 10-hit counter. Yield once so the parent setup finishes,
    // then replace that authoritative counter rather than entity engine health.
    scripts\engine\utility::waitframe();
    seticom.hit_point_left = 15;
    damage_clip setcandamage(1);
    damage_clip.health = 9999999;
    seticom.nextdamagetime = 0;
    spaceland_log("Seti-Com defense started ent=" +
        seticom getentitynumber() + " hits=15 stockHits=10");

    for (;;)
    {
        damage_clip waittill("damage", damage, attacker);
        if (isdefined(attacker) && isdefined(attacker.team) &&
            attacker.team == "allies")
        {
            continue;
        }

        if (!attacker scripts\cp\utility::is_zombie_agent())
            continue;

        if (!isdefined(attacker.agent_type) ||
            attacker.agent_type != "zombie_brute")
        {
            if (!isdefined(attacker.attackent))
            {
                attacker.attackent = damage_clip;
                attacker thread [[level.iwz_seticom_unlock_monitor]](
                    attacker, seticom);
            }
        }

        playfx(level._effect["vfx_zb_thu_sparks"],
            seticom.origin + (0, 0, 32));
        attacker notify("speaker_attacked");
        foreach (player in level.players)
        {
            player thread scripts\cp\cp_vo::try_to_play_vo(
                "quest_ufo_defend_speakers", "zmb_comment_vo");
        }

        current_time = gettime();
        if (current_time >= seticom.nextdamagetime)
        {
            seticom.nextdamagetime = current_time + 1000;
            seticom.hit_point_left--;
        }

        if (seticom.hit_point_left <= 0)
            break;

        update_seticom_health_hud(seticom);
    }

    spaceland_log("Seti-Com defense failed ent=" +
        seticom getentitynumber() + " hitsRemaining=0");
    [[level.iwz_seticom_failure]](seticom);
}

update_seticom_health_hud(seticom)
{
    health_fraction = seticom.hit_point_left / 15;
    setomnvar("zm_speaker_defense_health", health_fraction);
}

tune_alien_kill_xp()
{
    level endon("game_ended");

    // mp/default_agent_definition.csv defines zombie_grey with 1000 XP, and
    // gametype_zombie::give_attacker_kill_rewards reads this field per kill.
    while (!isdefined(level.agent_definition) ||
        !isdefined(level.agent_definition["zombie_grey"]) ||
        !isdefined(level.agent_definition["zombie_grey"]["xp"]))
    {
        scripts\engine\utility::waitframe();
    }

    stock_xp = int(level.agent_definition["zombie_grey"]["xp"]);
    level.agent_definition["zombie_grey"]["xp"] = 5000;
    level.iwz_alien_xp_ready = 1;
    spaceland_log("Alien kill XP tuned agent=zombie_grey stockXP=" + stock_xp +
        " xp=5000 source=agent_definition");
}

listen_for_alien_kill_test_requests()
{
    level endon("game_ended");
    spaceland_log("testAlienKill listener installed expectedXP=5000");

    for (;;)
    {
        level waittill("iwz_test_alien_kill", player);
        player simulate_alien_kill_reward();
    }
}

simulate_alien_kill_reward()
{
    if (!isdefined(self) || !isplayer(self))
    {
        spaceland_log("testAlienKill rejected reason=invalid player");
        return;
    }

    if (!scripts\engine\utility::is_true(level.iwz_alien_xp_ready) ||
        !isdefined(level.agent_definition) ||
        !isdefined(level.agent_definition["zombie_grey"]) ||
        !isdefined(level.agent_definition["zombie_grey"]["xp"]))
    {
        spaceland_log("testAlienKill rejected player=" + self getentitynumber() +
            " reason=agent definition unavailable");
        self iprintlnbold("Alien XP data is not ready");
        return;
    }

    if (!isdefined(level.zombie_xp))
    {
        spaceland_log("testAlienKill rejected player=" + self getentitynumber() +
            " reason=Zombies XP disabled");
        self iprintlnbold("Zombies XP is disabled in this match");
        return;
    }

    alien_xp = int(level.agent_definition["zombie_grey"]["xp"]);
    spaceland_log("testAlienKill awarding player=" + self getentitynumber() +
        " agent=zombie_grey xp=" + alien_xp +
        " path=cp_persistence::give_player_xp");
    scripts\cp\cp_persistence::give_player_xp(alien_xp);
    self iprintlnbold("Simulated Alien kill: +" + alien_xp + " XP");
}

listen_for_alien_fuse_spawn_requests()
{
    level endon("game_ended");
    spaceland_log("spawnAlienFuses listener installed source=local-stock-parity");

    for (;;)
    {
        level waittill("iwz_spawn_alien_fuses", player);

        if (!isdefined(player) || !isplayer(player))
        {
            spaceland_log("spawnAlienFuses rejected reason=invalid player");
            continue;
        }

        if (!isdefined(level.num_fuse_in_possession))
        {
            spaceland_log("spawnAlienFuses rejected player=" +
                player getentitynumber() + " reason=UFO quest unavailable");
            player iprintlnbold("Alien fuse quest is not ready");
            continue;
        }

        spawn_alien_fuses_at_stock_drop_point();
        spaceland_log("spawnAlienFuses spawned player=" +
            player getentitynumber() +
            " location=stock-drop-point origin=(657,765,105)");
        player iprintlnbold("Alien fuses spawned at the stock drop point");
    }
}

install_double_pap_persistence()
{
    level endon("game_ended");

    // init_ufo_quest initializes both the fuse counter and fuses_inserted flag.
    // Waiting for the counter prevents us from setting a flag that the stock
    // initializer would immediately clear.
    while (!isdefined(level.pap_max) ||
        !isdefined(level.num_fuse_in_possession))
    {
        scripts\engine\utility::waitframe();
    }

    if (getdvarint("iwz_survival_mode", 0))
    {
        pap_machine = getent("pap_machine", "targetname");
        while (!isdefined(pap_machine))
        {
            scripts\engine\utility::waitframe();
            pap_machine = getent("pap_machine", "targetname");
        }

        scripts\engine\utility::flag_set("fuses_inserted");
        previous_pap_max = level.pap_max;
        level.pap_max = 3;
        level thread show_inserted_alien_fuses();
        spaceland_log("double PaP forced survival=1 persistentWrite=0 papMax=" +
            int(previous_pap_max) + "->3 visual=alien-fuses-inserted");
        return;
    }

    if (getdvarint("iwz_spaceland_double_pap_unlocked", 0))
    {
        pap_machine = getent("pap_machine", "targetname");
        while (!isdefined(pap_machine))
        {
            scripts\engine\utility::waitframe();
            pap_machine = getent("pap_machine", "targetname");
        }

        scripts\engine\utility::flag_set("fuses_inserted");
        previous_pap_max = level.pap_max;
        level.pap_max = 3;
        level thread show_inserted_alien_fuses();
        spaceland_log("double PaP restored persistent=1 papMax=" +
            int(previous_pap_max) + "->3 visual=alien-fuses-inserted");
        return;
    }

    spaceland_log("double PaP persistence armed persistent=0 papMax=" +
        int(level.pap_max) + " waitingFor=fuses_inserted");
    scripts\engine\utility::flag_wait("fuses_inserted");

    // Stock upgrade_pap sets the flag immediately before raising pap_max.
    // Observe the completed state rather than persisting a partial interaction.
    while (level.pap_max < 3)
        scripts\engine\utility::waitframe();

    setdvar("iwz_spaceland_double_pap_unlocked", 1);
    spaceland_log("double PaP unlocked persistent=1 trigger=fuses_inserted papMax=" +
        int(level.pap_max));
}

// These are local copies of cp_zmb_ufo's stock fuse helpers. Referencing that
// map script directly makes the GSC linker require cp_zmb_ufo on every Zombies
// map, before post_load can reject non-Spaceland maps.
spawn_alien_fuses_at_stock_drop_point()
{
    first_fuse = spawn("script_model", (657, 765, 105));
    first_fuse setmodel("park_alien_gray_fuse");
    first_fuse.angles = (randomintrange(0, 360), randomintrange(0, 360),
        randomintrange(0, 360));

    second_fuse = spawn("script_model", (641, 765, 105));
    second_fuse setmodel("park_alien_gray_fuse");
    second_fuse.angles = (randomintrange(0, 360), randomintrange(0, 360),
        randomintrange(0, 360));

    second_fuse thread show_alien_fuse_glow(second_fuse, "souvenir_glow");
    second_fuse thread rotate_alien_fuse(second_fuse);
    first_fuse thread show_alien_fuse_glow(first_fuse, "souvenir_glow");
    first_fuse thread rotate_alien_fuse(first_fuse);
    first_fuse thread monitor_alien_fuse_pickup(first_fuse, second_fuse);
}

show_alien_fuse_glow(fuse, effect_name)
{
    fuse endon("death");
    wait(0.3);
    playfxontag(level._effect[effect_name], fuse, "tag_origin");
}

rotate_alien_fuse(fuse)
{
    fuse endon("death");
    base_angles = fuse.angles;

    for (;;)
    {
        fuse rotateto(base_angles + (randomintrange(-40, 40),
            randomintrange(-40, 90), randomintrange(-40, 90)), 3);
        wait(3);
    }
}

monitor_alien_fuse_pickup(first_fuse, second_fuse)
{
    first_fuse endon("death");
    first_fuse makeusable();
    first_fuse sethintstring(&"CP_ZMB_UFO_PICK_UP_FUSE");

    foreach (player in level.players)
    {
        player thread scripts\cp\cp_vo::add_to_nag_vo(
            "nag_ufo_fusefail", "zmb_comment_vo", 60, 15, 6, 1);
    }

    for (;;)
    {
        first_fuse waittill("trigger", player);
        if (!isplayer(player))
            continue;

        player playlocalsound("part_pickup");
        player thread scripts\cp\cp_vo::try_to_play_vo(
            "quest_ufo_collect_alienfuse_2", "zmb_comment_vo",
            "highest", 10, 0, 0, 1, 100);
        break;
    }

    level.num_fuse_in_possession++;
    scripts\cp\cp_interaction::add_to_current_interaction_list(
        scripts\engine\utility::getstruct("pap_upgrade", "script_noteworthy"));
    scripts\cp\cp_interaction::remove_from_current_interaction_list(
        scripts\engine\utility::getstruct("weapon_upgrade", "script_noteworthy"));
    level thread scripts\cp\cp_vo::remove_from_nag_vo("nag_ufo_fusefail");

    foreach (player in level.players)
        player setclientomnvar("zm_special_item", 1);

    second_fuse delete();
    first_fuse delete();
}

show_inserted_alien_fuses()
{
    pap_machine = getent("pap_machine", "targetname");
    pap_machine setscriptablepartstate("door", "close");
    wait(0.5);
    pap_machine setscriptablepartstate("machine", "upgraded");
    wait(0.25);
    pap_machine setscriptablepartstate("reels", "neutral");
    wait(0.25);
    pap_machine setscriptablepartstate("reels", "on");
    wait(0.25);
    pap_machine setscriptablepartstate("door", "open_idle");
}

set_arcade_game_award_type_stub(player)
{
    player enable_arcade_targeting_protection("award-type");

    if (scripts\engine\utility::is_true(player.in_afterlife_arcade))
    {
        player.arcade_game_award_type = "soul_power";
        return;
    }

    player.arcade_game_award_type = "tickets";
}

activision_cabinet_reward_timer_stub(player)
{
    player endon("stop_arcade_timer");
    player endon("disconnect");
    player endon("arcade_special_interrupt");

    // These hashed fields are local to the stock cabinet timer. Preserve their
    // initialization and 150-point cap so afterlife soul-power behavior remains
    // byte-for-byte equivalent apart from the normal ticket award call.
    if (!isdefined(player._id_2113))
        player._id_2113 = 0;

    elapsed_seconds = 0;
    player._id_210F = 0;
    spaceland_log("Activision cabinet reward timer player=" +
        player getentitynumber() + " awardType=" + player.arcade_game_award_type +
        " ticketsPerTick=0 soulPowerPerTick=10");

    for (;;)
    {
        player playanimscriptevent("power_active_cp", "gesture018");
        wait(1);
        elapsed_seconds++;

        if (elapsed_seconds % 10 != 0)
            continue;

        player._id_2113 = player._id_2113 + 10;
        if (player._id_2113 > 150)
        {
            player._id_2113 = 150;
            continue;
        }

        if (player.arcade_game_award_type == "soul_power")
        {
            scripts\cp\zombies\zombie_afterlife_arcade::give_soul_power(
                player, 10);
        }
    }
}

save_player_pre_arcade_weapon_stub(player)
{
    player enable_arcade_targeting_protection("weapon-save");

    if (scripts\engine\utility::is_true(player.in_afterlife_arcade))
        return;

    weapon = player getcurrentweapon();
    use_last_weapon = 0;
    if (weapon == "none")
        use_last_weapon = 1;
    else if (scripts\engine\utility::array_contains(
        level.additional_laststand_weapon_exclusion, weapon))
        use_last_weapon = 1;
    else if (scripts\engine\utility::array_contains(
        level.additional_laststand_weapon_exclusion, getweaponbasename(weapon)))
        use_last_weapon = 1;
    else if (scripts\cp\utility::is_melee_weapon(weapon, 1))
        use_last_weapon = 1;

    if (use_last_weapon)
    {
        player.copy_fullweaponlist = player getweaponslistall();
        weapon = player scripts\cp\cp_laststand::choose_last_weapon(
            level.additional_laststand_weapon_exclusion, 1, 1);
    }

    player.copy_fullweaponlist = undefined;
    if (isdefined(weapon))
        return weapon;

    return player getcurrentweapon();
}

enable_arcade_targeting_protection(source)
{
    if (!isdefined(level.script) || level.script != "cp_zmb" ||
        !isdefined(self) || !isplayer(self) ||
        scripts\engine\utility::is_true(self.in_afterlife_arcade))
    {
        return;
    }

    if (scripts\engine\utility::is_true(self.iwz_arcade_ignore_active))
    {
        previous_source = self.iwz_arcade_ignore_source;
        if (previous_source == source)
            return;

        // Basketball and Bowling for Planets issue a leading
        // arcade_game_over_for_player reset, then call the weapon-save helper in
        // the same frame. Transfer ownership to the physical-game watcher before
        // the award-type watcher can process that reset notification.
        self.iwz_arcade_ignore_source = source;
        self notify("iwz_arcade_targeting_monitor_replaced");
        self thread restore_targeting_after_arcade(source);
        spaceland_log("Arcade targeting handoff player=" + self getentitynumber() +
            " source=" + previous_source + "->" + source + " ignoreEnabled=" +
            self scripts\cp\utility::isignoremeenabled());
        return;
    }

    // allow_player_ignore_me is the stock reference-counted targeting API used
    // by the coaster and last-stand systems. The custom flag makes the two
    // patched entry paths share one owned reference while preserving independent
    // users of the stock API.
    self.iwz_arcade_ignore_active = 1;
    self.iwz_arcade_ignore_source = source;
    self scripts\cp\utility::allow_player_ignore_me(1);
    self thread restore_targeting_after_arcade(source);
    spaceland_log("Arcade targeting disabled player=" + self getentitynumber() +
        " source=" + source + " ignoreEnabled=" +
        self scripts\cp\utility::isignoremeenabled());
}

restore_targeting_after_arcade(expected_source)
{
    level endon("game_ended");
    self endon("iwz_arcade_targeting_monitor_replaced");

    // Activision cabinets end through exit_arcade_game. Physical games first
    // send arcade_game_over_for_player as a stale-thread reset and only later use
    // the same event for their real exit, so that event belongs exclusively to
    // the post-save watcher.
    if (expected_source == "weapon-save")
    {
        exit_events = ["arcade_game_over_for_player", "exit_arcade_game",
            "arcade_special_interrupt", "player_exit_afterlife", "last_stand",
            "revive", "spawned", "death", "disconnect"];
    }
    else
    {
        exit_events = ["exit_arcade_game", "arcade_special_interrupt",
            "player_exit_afterlife", "last_stand", "revive", "spawned",
            "death", "disconnect"];
    }

    exit_reason = self scripts\engine\utility::waittill_any_in_array_return_no_endon_death(
        exit_events);
    if (exit_reason == "disconnect" || !isdefined(self) || !isplayer(self))
        return;

    // A source handoff can occur after an exit notification wakes this thread
    // but before it is scheduled. Never let that stale watcher release the one
    // ignore reference now owned by its replacement.
    if (!scripts\engine\utility::is_true(self.iwz_arcade_ignore_active) ||
        !isdefined(self.iwz_arcade_ignore_source) ||
        self.iwz_arcade_ignore_source != expected_source)
    {
        return;
    }

    source = self.iwz_arcade_ignore_source;
    self.iwz_arcade_ignore_active = undefined;
    self.iwz_arcade_ignore_source = undefined;
    self scripts\cp\utility::allow_player_ignore_me(0);
    spaceland_log("Arcade targeting restored player=" + self getentitynumber() +
        " source=" + source + " reason=" + exit_reason + " ignoreEnabled=" +
        self scripts\cp\utility::isignoremeenabled());
}
