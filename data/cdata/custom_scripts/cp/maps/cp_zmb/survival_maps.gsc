main()
{
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    if (getdvar("ui_mapname") != "cp_zmb")
    {
        survival_log("launch rejected reason=unsupported-map requested=" +
            getdvar("ui_mapname") + " supported=cp_zmb");
        setdvar("iwz_survival_mode", 0);
        return;
    }

    // Reuse the complete Spaceland Boss Battle board and closed candy boxes.
    // direct_boss_fight owns their reticle, purchase and refund behavior.
    precachemodel("p7_cafe_wall_menu_01");
    precachemodel("zmb_candybox_bang_closed");
    precachemodel("zmb_candybox_blue_closed");
    precachemodel("zmb_candybox_bomb_closed");
    precachemodel("zmb_candybox_mule_closed");
    precachemodel("zmb_candybox_quickies_closed");
    precachemodel("zmb_candybox_racin_closed");
    precachemodel("zmb_candybox_slappy_closed");
    precachemodel("zmb_candybox_trail_closed");
    precachemodel("zmb_candybox_tuff_closed");
    precachemodel("zmb_candybox_up_closed");

    // The stock outer portal previews the central hub. Arcade Attack routes
    // to PaP, so load the active effect authored by zm_center_portal instead.
    level._effect["iwz_survival_pap_portal"] = loadfx(
        "vfx/iw7/core/zombie/vfx_zmb_centportal_active_rnr.vfx");

    replacefunc(scripts\cp\zombies\zombie_fast_travel::_id_126BF,
        ::survival_portal_to_pap);
    replacefunc(scripts\cp\zombies\zombie_fast_travel::hidden_room_exit_tube,
        ::survival_hidden_room_exit_tube);
    replacefunc(scripts\cp\zombies\zombie_fast_travel::_id_F28A,
        ::survival_portal_active_fx);
    replacefunc(scripts\cp\zombies\zombie_fast_travel::_id_F30B,
        ::survival_portal_close_fx);
    replacefunc(scripts\cp\zombies\interaction_magicwheel::_id_BC3F,
        ::survival_hold_wheel_location);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb::init_magic_wheel,
        ::survival_select_arcade_wheel);
    replacefunc(scripts\cp\maps\cp_zmb\cp_zmb::cp_zmb_introscreen_text,
        ::survival_introscreen_text);
    replacefunc(scripts\cp\zombies\directors_cut::allow_directors_cut,
        ::survival_disallow_directors_cut);

    survival_log("pre-load hooks installed map=cp_zmb portal=arcade-to-pap " +
        "portalVisual=pap-active-rnr papExit=arcade objective=survival " +
        "wheel=authored-main-arcade-entity " +
        "perkSource=spaceland-boss-battle-board directorsCut=disabled");
}

post_load()
{
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    if (!isdefined(level.script) || level.script != "cp_zmb")
    {
        survival_log("post-load rejected expected=cp_zmb actual=" + level.script);
        return;
    }

    // Arcade Attack begins in the main arcade. All three doors leading out of
    // that room remain sealed, including the rear arcade door pf7_auto237.
    level.initial_active_volumes = ["arcade"];

    if (isdefined(level.custom_onspawnplayer_func))
    {
        level.iwz_survival_stock_onspawn = level.custom_onspawnplayer_func;
        level.custom_onspawnplayer_func = ::survival_on_player_spawned;
    }

    install_survival_quick_revive_hooks();
    level thread enforce_survival_spawn_volumes();
    level thread disable_arcade_exit_barriers();
    level thread synchronize_survival_power_switches();
    level thread configure_survival_weapon_wheel();
    level thread enable_survival_pap_exit();
    level thread setup_survival_perk_purchase_wall();

    survival_log("Arcade Attack initialized initialVolume=arcade " +
        "exits=pf7_auto151,pf7_auto213,pf7_auto237 " +
        "exitSeal=none " +
        "powerSwitchSync=arcade-to-default-full-power " +
        "spawn=arcade-fast-travel-end-positions " +
        "danceFloor=(2816,-1344,131)");
}

survival_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Survival", message);
}

survival_disallow_directors_cut()
{
    return 0;
}

install_survival_quick_revive_hooks()
{
    if (scripts\engine\utility::is_true(
        level.iwz_survival_quick_revive_hooks_installed))
    {
        return;
    }

    level.iwz_survival_quick_revive_hooks_installed = 1;

    if (isdefined(level.additional_give_perk))
        level.iwz_survival_stock_additional_give_perk =
            level.additional_give_perk;

    if (isdefined(level.take_perks_func))
        level.iwz_survival_stock_take_perks_func = level.take_perks_func;

    if (isdefined(level.have_self_revive_override))
        level.iwz_survival_stock_have_self_revive_override =
            level.have_self_revive_override;

    if (isdefined(level.laststand_enter_gamemodespecificaction))
        level.iwz_survival_stock_laststand_enter =
            level.laststand_enter_gamemodespecificaction;

    if (isdefined(level.laststand_exit_gamemodespecificaction))
        level.iwz_survival_stock_laststand_exit =
            level.laststand_exit_gamemodespecificaction;

    level.additional_give_perk = ::survival_additional_give_perk;
    level.take_perks_func = ::survival_take_perk;
    level.have_self_revive_override =
        ::survival_have_self_revive_override;
    level.laststand_enter_gamemodespecificaction =
        ::survival_laststand_enter;
    level.laststand_exit_gamemodespecificaction =
        ::survival_laststand_exit;

    survival_log("quick revive hooks installed route=meph-self-revive " +
        "timeout=3 perkPolicy=stock weaponPolicy=stock-except-mule " +
        "directorsCutPolicy=stock-permanent-perk-restore");
}

survival_additional_give_perk(perk)
{
    if (isdefined(level.iwz_survival_stock_additional_give_perk))
        self [[level.iwz_survival_stock_additional_give_perk]](perk);

    if (perk != "perk_machine_revive")
        return;

    ensure_survival_quick_revive_token(self, "perk-granted");
}

ensure_survival_quick_revive_token(player, source)
{
    if (!(scripts\cp\utility::isplayingsolo() || level.only_one_player))
        return;

    if (!(player scripts\cp\utility::has_zombie_perk(
        "perk_machine_revive")))
    {
        return;
    }

    if (scripts\engine\utility::is_true(
        player.iwz_survival_quick_revive_token))
    {
        return;
    }

    scripts\cp\cp_laststand::enable_self_revive(player);
    player.iwz_survival_quick_revive_token = 1;

    survival_log("quick revive token enabled player=" +
        (player getentitynumber()) + " source=" + source +
        " tokenCount=" + get_survival_self_revive_count(player) +
        " directorsCut=" + scripts\engine\utility::is_true(
            player.have_permanent_perks));
}

survival_take_perk(perk)
{
    if (isdefined(level.iwz_survival_stock_take_perks_func))
        self [[level.iwz_survival_stock_take_perks_func]](perk);

    if (perk != "perk_machine_revive")
        return;

    // The regular machine returns one use to this counter when the player
    // voluntarily removes Quick Revive. The boss-fight wall refunds the perk
    // through a different function and omits that stock decrement.
    if (scripts\engine\utility::is_true(
        self.iwz_survival_quick_revive_wall_refund))
    {
        uses_before = self.self_revives_purchased;
        if (self.self_revives_purchased > 0)
            self.self_revives_purchased--;

        survival_log("quick revive wall refund player=" +
            (self getentitynumber()) + " uses=" + uses_before + "->" +
            self.self_revives_purchased + " limit=" +
            self.max_self_revive_machine_use);
    }

    if (!scripts\engine\utility::is_true(
        self.iwz_survival_quick_revive_token))
        return;

    // The normal down callback removes every perk before cp_laststand tests
    // its self-revive token. Preserve that token until the completed revive,
    // just as cp_final does during the Mephistopheles fight.
    if (scripts\engine\utility::is_true(
        self.iwz_survival_quick_revive_down))
    {
        survival_log("quick revive perk removed player=" +
            (self getentitynumber()) +
            " reason=last-stand tokenCleanup=deferred tokenCount=" +
            get_survival_self_revive_count(self));
        return;
    }

    token_count_before = get_survival_self_revive_count(self);
    if (token_count_before > 0)
        scripts\cp\cp_laststand::disable_self_revive(self);

    self.iwz_survival_quick_revive_token = undefined;
    survival_log("quick revive token disabled player=" +
        (self getentitynumber()) + " reason=perk-removed-outside-last-stand " +
        "tokenCount=" + token_count_before + "->" +
        get_survival_self_revive_count(self));
}

survival_have_self_revive_override(player)
{
    // Meph excludes Quick Revive here. Its separately enabled token then
    // reaches cp_laststand::self_revive instead of Spaceland's afterlife path.
    if (scripts\cp\utility::isplayingsolo() || level.only_one_player)
    {
        return player scripts\cp\utility::is_consumable_active(
            "self_revive") &&
            !scripts\engine\utility::is_true(player.disable_self_revive_fnf);
    }

    if (isdefined(level.iwz_survival_stock_have_self_revive_override))
    {
        return [[level.iwz_survival_stock_have_self_revive_override]](
            player);
    }

    return (player scripts\cp\utility::has_zombie_perk(
        "perk_machine_revive")) ||
        ((player scripts\cp\utility::is_consumable_active("self_revive")) &&
        !scripts\engine\utility::is_true(player.disable_self_revive_fnf));
}

survival_laststand_enter(player)
{
    ensure_survival_quick_revive_token(player, "last-stand-reconcile");

    quick_revive_owned = player scripts\cp\utility::has_zombie_perk(
        "perk_machine_revive");
    player.iwz_survival_quick_revive_down =
        quick_revive_owned && scripts\engine\utility::is_true(
            player.iwz_survival_quick_revive_token);

    if (scripts\engine\utility::is_true(
        player.iwz_survival_quick_revive_down))
    {
        primary_weapons = player getweaponslistprimaries();
        player.iwz_survival_primary_count_before_down =
            primary_weapons.size;
        player.iwz_survival_directors_cut_at_down =
            scripts\engine\utility::is_true(player.have_permanent_perks);

        if (isdefined(player.mule_weapon))
            player.iwz_survival_mule_weapon_at_down = player.mule_weapon;
        else
            player.iwz_survival_mule_weapon_at_down = undefined;
    }

    if (isdefined(level.iwz_survival_stock_laststand_enter))
        player [[level.iwz_survival_stock_laststand_enter]](player);

    if (!scripts\engine\utility::is_true(
        player.iwz_survival_quick_revive_down))
    {
        return;
    }

    mule_weapon = "none";
    if (isdefined(player.iwz_survival_mule_weapon_at_down))
        mule_weapon = player.iwz_survival_mule_weapon_at_down;

    survival_log("quick revive down routed player=" +
        (player getentitynumber()) +
        " route=cp_laststand-self-revive timeout=3 tokenCount=" +
        get_survival_self_revive_count(player) + " directorsCut=" +
        player.iwz_survival_directors_cut_at_down +
        " primariesBefore=" +
        player.iwz_survival_primary_count_before_down +
        " muleWeapon=" + mule_weapon +
        " perkPolicy=stock-remove weaponPolicy=stock-restore-except-mule");
}

survival_laststand_exit(player)
{
    if (isdefined(level.iwz_survival_stock_laststand_exit))
        player [[level.iwz_survival_stock_laststand_exit]](player);

    if (!scripts\engine\utility::is_true(
        player.iwz_survival_quick_revive_down))
    {
        return;
    }

    token_count_before = get_survival_self_revive_count(player);
    if (token_count_before > 0)
        scripts\cp\cp_laststand::disable_self_revive(player);

    mule_outcome = "not-owned";
    if (isdefined(player.iwz_survival_mule_weapon_at_down))
    {
        if (player hasweapon(player.iwz_survival_mule_weapon_at_down))
            mule_outcome = "retained-unexpected";
        else
            mule_outcome = "removed";
    }

    directors_cut = player.iwz_survival_directors_cut_at_down;
    perk_outcome = "removed";
    if (directors_cut)
        perk_outcome = "stock-permanent-restore-scheduled";

    primary_weapons = player getweaponslistprimaries();

    survival_log("quick revive completed player=" +
        (player getentitynumber()) + " tokenCount=" + token_count_before +
        "->" + get_survival_self_revive_count(player) +
        " directorsCut=" + directors_cut + " perkOutcome=" +
        perk_outcome + " primaries=" +
        player.iwz_survival_primary_count_before_down + "->" +
        primary_weapons.size + " muleWeapon=" +
        mule_outcome + " afterlife=skipped");

    player.iwz_survival_quick_revive_token = undefined;
    player.iwz_survival_quick_revive_down = undefined;
    player.iwz_survival_primary_count_before_down = undefined;
    player.iwz_survival_directors_cut_at_down = undefined;
    player.iwz_survival_mule_weapon_at_down = undefined;
}

get_survival_self_revive_count(player)
{
    if (!isdefined(player.self_revive))
        return 0;

    return player.self_revive;
}

survival_perk_purchase_hint(interaction, player)
{
    if (isdefined(player.candy_box_looking_at) &&
        !scripts\engine\utility::is_true(player.kung_fu_mode))
    {
        perk = player.candy_box_looking_at.perk;
        if (perk == "perk_machine_revive" &&
            !(player scripts\cp\utility::has_zombie_perk(perk)) &&
            survival_quick_revive_purchase_capped(player))
        {
            return &"COOP_INTERACTIONS_CANNOT_BUY_SELF_REVIVE";
        }
    }

    return scripts\cp\zombies\direct_boss_fight::perk_purchase_hint_func(
        interaction, player);
}

survival_try_perk_purchase(interaction, player)
{
    if (!isdefined(player.candy_box_looking_at))
        return;

    if (scripts\engine\utility::is_true(player.kung_fu_mode))
        return;

    player thread survival_perk_purchase_internal(interaction, player);
}

survival_perk_purchase_internal(interaction, player)
{
    player endon("disconnect");

    if (scripts\engine\utility::is_true(
        player.iwz_survival_perk_purchase_in_progress))
    {
        return;
    }

    player.iwz_survival_perk_purchase_in_progress = 1;
    candy_box = player.candy_box_looking_at;
    perk = candy_box.perk;
    perk_owned = player scripts\cp\utility::has_zombie_perk(perk);

    if (perk == "perk_machine_revive" && !perk_owned &&
        survival_quick_revive_purchase_capped(player))
    {
        survival_log("quick revive purchase denied player=" +
            (player getentitynumber()) + " uses=" +
            player.self_revives_purchased + " limit=" +
            player.max_self_revive_machine_use +
            " reason=stock-self-revive-cap currencySpent=0");
        player scripts\cp\cp_interaction::interaction_show_fail_reason(
            interaction, &"COOP_INTERACTIONS_CANNOT_BUY_SELF_REVIVE");
        player.iwz_survival_perk_purchase_in_progress = undefined;
        return;
    }

    uses_before = player.self_revives_purchased;
    if (perk == "perk_machine_revive" && perk_owned)
        player.iwz_survival_quick_revive_wall_refund = 1;

    if (perk_owned)
    {
        player scripts\cp\zombies\direct_boss_fight::perk_purchase_internal(
            player);
        player.iwz_survival_quick_revive_wall_refund = undefined;
        player.iwz_survival_perk_purchase_in_progress = undefined;
        return;
    }

    // The boss-fight wall grants perks directly and therefore skips the
    // regular machine's purchase presentation. Perform the same transaction
    // against the captured candy box so changing aim during the blocking
    // gesture cannot change which perk is eventually granted.
    if (isdefined(player.zombies_perks) &&
        player.zombies_perks.size > 20 &&
        !scripts\engine\utility::is_true(player.have_gns_perk))
    {
        player.iwz_survival_perk_purchase_in_progress = undefined;
        return;
    }

    cost = scripts\cp\zombies\direct_boss_fight::get_perk_cost(perk);
    if (player scripts\cp\cp_persistence::get_player_currency() < cost)
    {
        player.iwz_survival_perk_purchase_in_progress = undefined;
        return;
    }

    player scripts\cp\cp_persistence::take_player_currency(cost, 1, "perk");
    scripts\cp\zombies\direct_boss_fight::made_direct_boss_fight_purchase(
        player);

    if (!isdefined(player.current_perk_list))
        player.current_perk_list = [];

    player.current_perk_list[player.current_perk_list.size] = perk;

    sound_source = spawnstruct();
    sound_source.name = perk;
    sound_source.origin = candy_box.origin;

    survival_log("perk wall purchase presentation started player=" +
        (player getentitynumber()) + " perk=" + perk + " cost=" + cost +
        " origin=" + candy_box.origin +
        " audio=stock-machine-jingle-vo-and-candy-foley " +
        "animation=stock-perk-candy-gesture");

    level thread scripts\cp\zombies\zombies_perk_machines::
        play_perk_machine_purchase_sound(sound_source, player);
    player scripts\cp\zombies\zombies_perk_machines::play_perk_gesture(perk);
    player scripts\cp\zombies\zombies_perk_machines::give_zombies_perk(
        perk, 0);

    survival_log("perk wall purchase presentation completed player=" +
        (player getentitynumber()) + " perk=" + perk);

    if (perk == "perk_machine_revive" && !perk_owned)
    {
        survival_log("quick revive purchased player=" +
            (player getentitynumber()) + " uses=" + uses_before + "->" +
            player.self_revives_purchased + " limit=" +
            player.max_self_revive_machine_use);
    }

    player.iwz_survival_perk_purchase_in_progress = undefined;
}

survival_quick_revive_purchase_capped(player)
{
    if (!isdefined(player.self_revives_purchased) ||
        !isdefined(player.max_self_revive_machine_use))
    {
        return 0;
    }

    return player.self_revives_purchased >=
        player.max_self_revive_machine_use;
}

survival_introscreen_text()
{
    wait(2);
    line_1 = scripts\cp\cp_hud_util::introscreen_corner_line(
        &"CP_ZMB_INTRO_LINE_1", 1);
    wait(1);
    line_2 = scripts\cp\cp_hud_util::introscreen_corner_line(
        &"CP_ZMB_INTRO_LINE_2", 2);
    wait(1);
    line_3 = scripts\cp\cp_hud_util::introscreen_corner_line(
        &"CP_ZMB_INTRO_LINE_3", 3);
    wait(1);
    line_4 = scripts\cp\cp_hud_util::introscreen_corner_line(
        &"CP_ZMB_INTRO_LINE_4", 4);

    survival_log("intro objective presented text=Survive-until-you-die");
    level waittill("introscreen_over");
    line_1 fadeovertime(2);
    line_2 fadeovertime(2);
    line_3 fadeovertime(2);
    line_4 fadeovertime(2);
    line_1.alpha = 0;
    line_2.alpha = 0;
    line_3.alpha = 0;
    line_4.alpha = 0;
    line_1 destroy();
    line_2 destroy();
    line_3 destroy();
    line_4 destroy();
}

survival_hold_wheel_location()
{
    survival_log("weapon wheel relocation intercepted action=reactivate-physical-arcade-wheel");
    activate_survival_arcade_wheel("relocation-intercept");
}

survival_select_arcade_wheel()
{
    // Spaceland's stock choices omit the wheel physically inside the main
    // arcade. Select the authored arcade volume before the shared initializer
    // assigns active/inactive states to every physical wheel.
    scripts\cp\zombies\interaction_magicwheel::set_magic_wheel_starting_location(
        "arcade");
    survival_log("weapon wheel startup location forced area=arcade " +
        "phase=cp_zmb-init source=authored-main-arcade-wheel");
}

configure_survival_weapon_wheel()
{
    level endon("game_ended");

    while (!isdefined(level.magic_weapons) ||
        !isdefined(level.all_magic_weapons))
    {
        scripts\engine\utility::waitframe();
    }

    level.magic_weapons["dischord"] = "iw7_dischord_zm";
    level.magic_weapons["facemelter"] = "iw7_facemelter_zm";
    level.magic_weapons["headcutter"] = "iw7_headcutter_zm";
    level.magic_weapons["shredder"] = "iw7_shredder_zm";
    level.all_magic_weapons["dischord"] = "iw7_dischord_zm";
    level.all_magic_weapons["facemelter"] = "iw7_facemelter_zm";
    level.all_magic_weapons["headcutter"] = "iw7_headcutter_zm";
    level.all_magic_weapons["shredder"] = "iw7_shredder_zm";

    while (!isdefined(level._id_B163))
        scripts\engine\utility::waitframe();

    wheel_initialization_complete = 0;
    while (!wheel_initialization_complete)
    {
        wheel_initialization_complete = 1;
        foreach (wheel in level._id_B163)
        {
            if (!isdefined(wheel._id_10A03))
            {
                wheel_initialization_complete = 0;
                break;
            }
        }

        if (!wheel_initialization_complete)
            scripts\engine\utility::waitframe();
    }

    while (!scripts\engine\utility::flag_exist("fire_sale"))
        scripts\engine\utility::waitframe();

    // Refresh every wheel's private randomized list. Fire Sale wheels must use
    // the same Survival weapon pool as the permanently active arcade wheel.
    foreach (wheel in level._id_B163)
    {
        wheel._id_13C25 =
            scripts\cp\zombies\interaction_magicwheel::_id_7ABF();
    }

    log_survival_wheel_candidates();

    // Select the authored wheel beside the arcade's upper floor. This point is
    // the out_of_order brush from cp_zmb's map ents, not a guessed area name.
    activate_survival_arcade_wheel("post-stock-initialization");
}

get_survival_arcade_wheel()
{
    if (!isdefined(level._id_B163) || !level._id_B163.size)
        return undefined;

    // cp_zmb map ents: the main-arcade wheel's out_of_order brush is
    // (2573, -912, 277). The old (1010, -2260, 440) target is Polar Peek.
    return scripts\engine\utility::getclosest(
        (2573, -912, 277), level._id_B163);
}

log_survival_wheel_candidates()
{
    reference = (2573, -912, 277);
    selected = get_survival_arcade_wheel();

    foreach (wheel in level._id_B163)
    {
        area = "undefined";
        if (isdefined(wheel.area_name))
            area = wheel.area_name;

        survival_log("weapon wheel candidate entity=" +
            (wheel getentitynumber()) + " area=" + area +
            " origin=" + wheel.origin + " distanceSquared=" +
            distancesquared(reference, wheel.origin) + " selected=" +
            (wheel == selected));
    }
}

activate_survival_arcade_wheel(reason)
{
    arcade_wheel = get_survival_arcade_wheel();
    if (!isdefined(arcade_wheel) || !isdefined(arcade_wheel.area_name) ||
        !isdefined(arcade_wheel._id_10A03))
    {
        survival_log("weapon wheel activation failed reason=entity-not-ready " +
            "phase=" + reason);
        return;
    }

    scripts\cp\zombies\interaction_magicwheel::set_magic_wheel_starting_location(
        arcade_wheel.area_name);
    scripts\cp\zombies\interaction_magicwheel::init_magic_wheel(arcade_wheel);

    // init_magic_wheel owns all five pieces of stock activation. Keep the
    // pointer explicit as later wheel code reads it directly.
    level.current_active_wheel = arcade_wheel;

    if (!isdefined(arcade_wheel.iwz_survival_no_teddy_monitor))
    {
        arcade_wheel.iwz_survival_no_teddy_monitor = 1;
        arcade_wheel thread prevent_survival_wheel_teddy();
    }

    wheel_states = "base=" +
        (arcade_wheel getscriptablepartstate("base")) +
        " fx=" + (arcade_wheel getscriptablepartstate("fx")) +
        " spinner=" +
        (arcade_wheel._id_10A03 getscriptablepartstate("spinner"));

    survival_log("weapon wheel activated phase=" + reason +
        " entity=" + (arcade_wheel getentitynumber()) +
        " area=" + arcade_wheel.area_name +
        " origin=" + arcade_wheel.origin +
        " states=" + wheel_states +
        " wonders=dischord,facemelter,headcutter,shredder movable=0 teddy=disabled");
}

prevent_survival_wheel_teddy()
{
    level endon("game_ended");

    for (;;)
    {
        self waittill("ready");

        // Fire Sale spins never advance the relocation streak. Reset the same
        // stock streak after each completed Survival spin so this permanent,
        // non-relocating wheel has identical no-teddy behavior.
        completed_streak = level._id_13D01;
        level._id_13D01 = 0;
        level._id_B162 = 0;
        survival_log("weapon wheel relocation streak reset entity=" +
            (self getentitynumber()) + " completedStreak=" +
            completed_streak + " behavior=fire-sale-no-teddy");
    }
}

enforce_survival_spawn_volumes()
{
    level endon("game_ended");

    if (!scripts\engine\utility::flag_exist("init_spawn_volumes_done"))
        scripts\engine\utility::flag_init("init_spawn_volumes_done");

    scripts\engine\utility::flag_wait("init_spawn_volumes_done");

    volumes_to_disable = [];
    foreach (volume in level.active_spawn_volumes)
    {
        if (isdefined(volume.basename) && volume.basename != "arcade")
            volumes_to_disable[volumes_to_disable.size] = volume.basename;
    }

    foreach (volume_name in volumes_to_disable)
    {
        scripts\cp\zombies\zombies_spawning::deactivate_volume_by_name(
            volume_name);
    }

    scripts\cp\zombies\zombies_spawning::activate_volume_by_name("arcade");
    scripts\cp\zombies\zombie_entrances::enable_windows_in_area("arcade");

    survival_log("spawn volumes enforced active=arcade disabled=" +
        volumes_to_disable.size + " arcadeBackLocked=pf7_auto237");
}

disable_arcade_exit_barriers()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        scripts\engine\utility::waitframe();
    scripts\engine\utility::flag_wait("init_interaction_done");

    // zombie_doors builds each door's private interaction array after the
    // generic interaction flag. Removing records before this flag races that
    // build and leaves _id_95B5 indexing an empty array.
    while (!scripts\engine\utility::flag_exist("doors_initialized"))
        scripts\engine\utility::waitframe();
    scripts\engine\utility::flag_wait("doors_initialized");

    // cp_zmb map ents identify the arcade exits as follows:
    //   pf7_auto151: arcade <-> moon_outside_begin
    //   pf7_auto213: arcade <-> moon_bumpercars
    //   pf7_auto237: arcade <-> arcade_back
    // pf7_auto238 is arcade_back <-> europa_2 and was the incorrect former
    // target. The logged wall hit (1813.1,-1682.22,159.263) is pf7_auto237.
    exit_targets = ["pf7_auto151", "pf7_auto213", "pf7_auto237"];
    disabled_count = 0;

    foreach (interaction in level.all_interaction_structs)
    {
        if (!isdefined(interaction.target))
            continue;

        target_index = -1;
        for (index = 0; index < exit_targets.size; index++)
        {
            if (interaction.target == exit_targets[index])
            {
                target_index = index;
                break;
            }
        }

        if (target_index < 0)
            continue;

        interaction.enabled = 0;
        scripts\cp\cp_interaction::remove_from_current_interaction_list(
            interaction);
        disabled_count++;
    }

    trigger_count = 0;
    hidden_icon_count = 0;
    door_triggers = getentarray("door_buy", "targetname");
    foreach (door_trigger in door_triggers)
    {
        if (!isdefined(door_trigger.target))
            continue;

        target_index = -1;
        for (index = 0; index < exit_targets.size; index++)
        {
            if (door_trigger.target == exit_targets[index])
            {
                target_index = index;
                break;
            }
        }

        if (target_index < 0)
            continue;

        stock_origin = door_trigger.origin;
        relocated_origin = stock_origin + (0, 0, -10000);

        // A disabled trigger can retain its authored purchase cursor on this
        // engine path (notably pf7_auto237). Move the stock brush trigger out
        // of play while its stock door thread remains valid. No replacement
        // usable or hint entity is created, keeping the barriers free of the
        // deferred hint feature's runtime errors.
        door_trigger makeunusable();
        door_trigger setcursorhint("HINT_NOICON");
        door_trigger.origin = relocated_origin;

        trigger_count++;
        hidden_icon_count++;

        survival_log("arcade exit secured target=" +
            door_trigger.target + " stockOrigin=" + stock_origin +
            " stockRelocated=" + relocated_origin +
            " sealVfx=none " +
            " cursorHint=HINT_NOICON purchaseEnabled=0 replacementHint=none");
    }

    survival_log("arcade exits sealed targets=pf7_auto151,pf7_auto213," +
        "pf7_auto237 interactionsDisabled=" + disabled_count +
        " doorTriggersDisabled=" + trigger_count +
        " purchaseIconsHidden=" + hidden_icon_count +
        " vfxSeals=0 " +
        " expectedInteractions=6 loggedBarrier=pf7_auto237 " +
        "loggedBarrierCoords=(1813.1,-1682.22,159.263) " +
        "replacementHints=none " +
        "ordering=after-doors_initialized");
}

synchronize_survival_power_switches()
{
    level endon("game_ended");

    // zombie_power emits this before its 2.5 second power-on delay. Route the
    // default switch through the full stock generator path so its authored
    // areas receive the same notifications and flags as a direct purchase.
    for (;;)
    {
        level waittill("power_on_scriptable_and_light", power_areas,
            activating_player);
        if (power_areas == "arcade,arcade_back")
            break;
    }

    while (!isdefined(level.generators))
        scripts\engine\utility::waitframe();

    arcade_generator = undefined;
    default_generator = undefined;
    foreach (generator in level.generators)
    {
        if (isdefined(generator.target) &&
            generator.target == "pf134_auto690")
        {
            arcade_generator = generator;
        }
        else if (isdefined(generator.target) &&
            generator.target == "pf134_auto654")
        {
            default_generator = generator;
        }
    }

    if (!isdefined(arcade_generator) || !isdefined(default_generator) ||
        !isdefined(arcade_generator.handle) ||
        !isdefined(default_generator.handle))
    {
        survival_log("power switch synchronization failed " +
            "reason=authored-generator-or-handle-missing arcadeFound=" +
            isdefined(arcade_generator) + " defaultFound=" +
            isdefined(default_generator));
        return;
    }

    if (scripts\engine\utility::is_true(default_generator.powered_on))
    {
        survival_log("power switch synchronization skipped " +
            "reason=default-switch-already-on arcadeOrigin=" +
            arcade_generator.handle.origin + " defaultOrigin=" +
            default_generator.handle.origin);
        return;
    }

    default_angles_before = default_generator.handle.angles;
    level thread scripts\cp\zombies\zombie_power::generic_generator(
        default_generator);

    // generic_generator activates its parsed script_parameters after the
    // stock 2.5-second power-on delay.
    wait(2.7);
    survival_log("power switches synchronized source=arcade target=default " +
        "arcadeTarget=" + arcade_generator.target + " arcadeOrigin=" +
        arcade_generator.handle.origin + " defaultTarget=" +
        default_generator.target + " defaultOrigin=" +
        default_generator.handle.origin + " defaultAngles=" +
        default_angles_before + "->" + default_generator.handle.angles +
        " defaultPoweredOn=" +
        scripts\engine\utility::is_true(default_generator.powered_on) +
        " powerAreasActivated=" + default_generator.script_parameters +
        " activationPath=stock-generic-generator remoteGesture=none");
}

survival_on_player_spawned()
{
    if (isdefined(level.iwz_survival_stock_onspawn))
        self [[level.iwz_survival_stock_onspawn]]();

    // spawnintermission deliberately respawns each player at the map-authored
    // mp_global_intermission point. Do not apply the gameplay relocation to
    // that spawn or the post-game camera is pushed down onto the arcade floor.
    if (getdvarint("scr_gameended", 0))
    {
        survival_log("gameplay spawn relocation skipped ent=" +
            (self getentitynumber()) + " reason=stock-intermission-camera");
        return;
    }

    // These are the map-authored destinations used by the arcade portal.
    // They sit inside the arcade; the previous guessed Y coordinate was on
    // the exterior side of the wall.
    spawn_locations = [];
    spawn_angles = [];
    spawn_source = "map-fallback";

    if (isdefined(level.fast_travel_spots) &&
        isdefined(level.fast_travel_spots["arcade"]) &&
        isdefined(level.fast_travel_spots["arcade"].end_positions) &&
        level.fast_travel_spots["arcade"].end_positions.size)
    {
        arcade_portal = level.fast_travel_spots["arcade"];
        foreach (end_position in arcade_portal.end_positions)
        {
            spawn_locations[spawn_locations.size] = end_position.origin;
            spawn_angles[spawn_angles.size] = end_position.angles;
        }
        spawn_source = "fast-travel-structs";
    }
    else
    {
        spawn_locations = [
            (2217.7, -1612.9, 140.5),
            (2186.6, -1610.1, 140.5),
            (2149.8, -1612.9, 140.5),
            (2121.6, -1612.9, 140.5)
        ];
        spawn_angles = [
            (0, 90, 0),
            (0, 90, 0),
            (0, 90, 0),
            (0, 90, 0)
        ];
    }

    start_index = (self getentitynumber()) % spawn_locations.size;
    selected_authored_origin = spawn_locations[start_index];
    selected_origin = scripts\engine\utility::drop_to_ground(
        selected_authored_origin, 32, -256) + (0, 0, 1);
    selected_angles = spawn_angles[start_index];

    for (offset = 0; offset < spawn_locations.size; offset++)
    {
        candidate_index = (start_index + offset) % spawn_locations.size;
        candidate_authored = spawn_locations[candidate_index];
        candidate = scripts\engine\utility::drop_to_ground(
            candidate_authored, 32, -256) + (0, 0, 1);
        if (!positionwouldtelefrag(candidate))
        {
            selected_authored_origin = candidate_authored;
            selected_origin = candidate;
            selected_angles = spawn_angles[candidate_index];
            break;
        }
    }

    self dontinterpolate();
    self setorigin(selected_origin);
    self setplayerangles(selected_angles);
    survival_log("player spawned ent=" + (self getentitynumber()) +
        " authoredOrigin=" + selected_authored_origin +
        " groundedOrigin=" + selected_origin +
        " groundDelta=" + (selected_origin - selected_authored_origin) +
        " angles=" + selected_angles + " source=" + spawn_source +
        " insideArcade=1");
}

survival_portal_to_pap(player, travel_time)
{
    if (!isdefined(player) || !isplayer(player))
    {
        survival_log("arcade portal rejected reason=invalid-player");
        return;
    }

    survival_log("arcade portal entered player=" +
        (player getentitynumber()) + " destination=pack-a-punch");
    scripts\cp\zombies\zombie_fast_travel::travel_through_hidden_tube(player);
    // Stock _id_126BF owns this notification. Its caller uses it to release the
    // player's teleport lock, while travel_through_hidden_tube does not emit it.
    player notify("fast_travel_complete");
    survival_log("arcade portal completed player=" +
        (player getentitynumber()) + " destination=pack-a-punch");
}

survival_portal_active_fx()
{
    if (isdefined(self.script_area) && self.script_area == "arcade")
    {
        // Keep the entrance scriptable's central-hub effect out of its active
        // state, then spawn the exact active effect used by zm_center_portal.
        self._id_D682 setscriptablepartstate("portal", "powered_on");

        if (!scripts\engine\utility::is_true(self.iwz_pap_visual_active))
        {
            wall_face_center = (2174.3, -1688.01, 164.349);
            // The trace point is the wall face, while the map-authored arcade
            // portal model sits at Y=-1666. Push the visual 22.01 units along
            // the measured (0,1,0) normal so the effect is in the portal plane
            // rather than intersecting the wall.
            desired_visual_center =
                wall_face_center + (0, 22.01, 0);
            visual_forward = (0, 1, 0);

            // The dumped vfx_zmb_centportal_active_rnr runner contains a
            // fixed local-space placement of (15,0,108). playfxontag placed
            // that offset above/behind the requested wall point. Spawn the FX
            // through the stock fast-travel path and subtract the transformed
            // authored offset so its visible center lands on the portal plane.
            visual_spawn_origin =
                desired_visual_center - (0, 15, 108);
            self.iwz_pap_visual_fx = spawnfx(
                level._effect["iwz_survival_pap_portal"],
                visual_spawn_origin, visual_forward);
            triggerfx(self.iwz_pap_visual_fx);
            self.iwz_pap_visual_active = 1;
            survival_log("arcade portal visual activated source=" +
                "zm_center_portal effect=vfx_zmb_centportal_active_rnr " +
                "wallFaceCenter=" + wall_face_center +
                " desiredCenter=" + desired_visual_center +
                " authoredPortalOrigin=" + self._id_D682.origin +
                " outwardWallNormalOffset=(0,22.01,0) " +
                " bakedLocalOffset=(15,0,108) " +
                "spawnOrigin=" + visual_spawn_origin +
                " forward=" + visual_forward +
                " path=stock-spawnfx-triggerfx " +
                "defaultEffect=vfx_zmb_portal_centhub suppressed=1");
        }
        return;
    }

    self._id_D682 setscriptablepartstate("portal", "active");
}

survival_portal_close_fx()
{
    if (isdefined(self.script_area) && self.script_area == "arcade" &&
        scripts\engine\utility::is_true(self.iwz_pap_visual_active))
    {
        if (isdefined(self.iwz_pap_visual_fx))
        {
            self.iwz_pap_visual_fx delete();
            self.iwz_pap_visual_fx = undefined;
        }
        self.iwz_pap_visual_active = undefined;
        survival_log("arcade portal visual closed effect=" +
            "vfx_zmb_centportal_active_rnr path=spawnfx-entity-delete");
    }

    self._id_D682 setscriptablepartstate("portal", "off");
}

enable_survival_pap_exit()
{
    level endon("game_ended");

    if (!scripts\engine\utility::flag_exist("fast_travel_init_done"))
        scripts\engine\utility::flag_init("fast_travel_init_done");

    scripts\engine\utility::flag_wait("fast_travel_init_done");

    hidden_exit = getent("hidden_room_portal", "targetname");
    if (!isdefined(hidden_exit))
    {
        survival_log("PaP exit unavailable reason=hidden_room_portal-missing");
        return;
    }

    survival_log("PaP exit enabled destination=arcade");
    level thread scripts\cp\zombies\zombie_fast_travel::turn_on_room_exit_portal();
}

survival_hidden_room_exit_tube(player)
{
    player forceusehintoff();
    player notify("delete_equipment");
    player scripts\cp\zombies\zombie_afterlife_arcade::add_white_screen();
    travel_anchor =
        scripts\cp\zombies\zombie_fast_travel::move_through_tube(
            player, "hidden_travel_tube_end", "hidden_travel_tube_start", 1);

    arcade_portal = level.fast_travel_spots["arcade"];
    if (isdefined(arcade_portal))
    {
        arcade_portal scripts\cp\zombies\zombie_fast_travel::teleport_to_safe_spot(player);
    }
    else
    {
        player playershow();
        player unlink();
        player dontinterpolate();
        player setorigin((2217.7, -1612.9, 140.5));
        player setplayerangles((0, 90, 0));
        player.disable_consumables = undefined;
        player scripts\cp\powers\coop_powers::power_enablepower();
        survival_log("PaP exit fallback used player=" +
            (player getentitynumber()) + " reason=arcade-fast-travel-missing");
    }

    player thread scripts\cp\zombies\zombie_afterlife_arcade::remove_white_screen(0.1);
    wait(0.1);
    travel_anchor delete();

    if (scripts\engine\utility::is_true(player.wor_phase_shift))
    {
        player scripts\cp\powers\coop_phaseshift::exitphaseshift(1);
        player.wor_phase_shift = 0;
    }

    player scripts\cp\utility::removedamagemodifier("papRoom", 0);
    player.is_off_grid = undefined;
    player.kicked_out = undefined;
    player scripts\cp\zombies\zombie_fast_travel::set_in_pap_room(
        player, 0);
    player notify("fast_travel_complete");
    scripts\cp\cp_vo::remove_from_nag_vo("ww_pap_nag");
    scripts\cp\cp_vo::remove_from_nag_vo("nag_find_pap");

    survival_log("PaP exit completed player=" +
        (player getentitynumber()) + " destination=arcade");
}

setup_survival_perk_purchase_wall()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        scripts\engine\utility::waitframe();
    scripts\engine\utility::flag_wait("init_interaction_done");

    // The stock golden-teeth ticket interaction is only 68 units from the
    // board and wins the interaction search when the board is viewed head-on.
    // Stock CODXP already removes this same interaction through this API.
    gold_teeth = scripts\engine\utility::getstruct(
        "gold_teeth", "script_noteworthy");
    if (isdefined(gold_teeth))
    {
        gold_teeth.enabled = 0;
        scripts\cp\cp_interaction::remove_from_current_interaction_list(
            gold_teeth);
        survival_log("nearby interaction disabled noteworthy=gold_teeth " +
            "origin=" + gold_teeth.origin +
            " reason=perk-wall-search-conflict");
    }
    else
    {
        survival_log("nearby interaction unavailable noteworthy=gold_teeth " +
            "perkWallConflictRemoval=skipped");
    }

    // Measured with crosshaircoords against the intended arcade wall. Move the
    // model half a unit along the surface normal to prevent coplanar flicker.
    wall_surface = (3784, -1239.65, 175.553);
    wall_normal = (-1, 0, 0);
    board_origin = wall_surface + wall_normal * 0.5;

    board = spawn("script_model", board_origin);
    board setmodel("p7_cafe_wall_menu_01");
    // Stock Boss Battle code treats -forward as the front of the board.
    board.angles = (0, 0, 0);
    board setnonstick(1);
    level.perk_purchase_board = board;
    level.iwz_survival_perk_board = board;

    board thread scripts\cp\zombies\direct_boss_fight::player_use_monitor(board);
    scripts\cp\zombies\direct_boss_fight::create_perk_purchase_candy_boxes();
    level thread scripts\cp\zombies\direct_boss_fight::create_perk_purchase_interaction();
    level thread log_survival_perk_wall_ready();

    survival_log("perk wall created source=spaceland-boss-battle " +
        "measuredSurface=" + wall_surface + " wallNormal=" + wall_normal +
        " boardOrigin=" + board_origin + " boardAngles=" + board.angles +
        " candyBoxes=" + level.perk_purchase_structs.size +
        " expectedBoardOrigin=(3783.5,-1239.65,175.553) interactionDelay=5");
}

log_survival_perk_wall_ready()
{
    level endon("game_ended");

    while (!isdefined(level.perk_purchase_interactions) ||
        !level.perk_purchase_interactions.size)
    {
        scripts\engine\utility::waitframe();
    }

    interaction = level.perk_purchase_interactions[0];
    interaction.hint_func = ::survival_perk_purchase_hint;
    interaction.activation_func = ::survival_try_perk_purchase;
    survival_log("perk wall interaction ready origin=" + interaction.origin +
        " enabled=" + interaction.enabled +
        " poweredOn=" + interaction.powered_on +
        " searchDistance=" + interaction.custom_search_dist +
        " boardOrigin=" + level.iwz_survival_perk_board.origin +
        " quickReviveLimit=3 counter=self_revives_purchased " +
        "refundPolicy=stock-decrement");
}
