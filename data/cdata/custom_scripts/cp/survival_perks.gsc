// IWZ-LOAD: referenced-only
// Shared Survival perk transactions and self-revive behavior. No automatic entry points.

precache_perk_wall(board_model)
{
    precachemodel(board_model);
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
    precachemodel("cp_disco_candybox_closed");
}

setup_perk_wall(surface, normal, yaw, board_model)
{
    level endon("game_ended");
    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        wait 0.05;
    scripts\engine\utility::flag_wait("init_interaction_done");

    board = spawn("script_model", surface + normal * 4);
    board setmodel(board_model);
    board.angles = (0, yaw, 0);
    board setnonstick(1);
    level.perk_purchase_board = board;
    level.iwz_survival_perk_board = board;
    board thread scripts\cp\zombies\direct_boss_fight::player_use_monitor(board);
    scripts\cp\zombies\direct_boss_fight::create_perk_purchase_candy_boxes();
    // This stock function returns after registering the one interaction.
    scripts\cp\zombies\direct_boss_fight::create_perk_purchase_interaction();
    interaction = level.perk_purchase_interactions[0];
    interaction.hint_func = ::survival_perk_purchase_hint;
    interaction.activation_func = ::survival_try_perk_purchase;
    survival_log("perk wall ready map=" + level.script + " surface=" + surface +
        " normal=" + normal + " boardOrigin=" + board.origin +
        " model=" + board_model + " angles=" + board.angles + " interactionOrigin=" + interaction.origin +
        " boxes=" + level.perk_purchase_structs.size +
        " searchDistance=" + interaction.custom_search_dist +
        " wallClearance=4 power=independent presentation=stock-candy-gesture");
}

survival_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Survival", message);
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
        survival_log("perk wall removal completed player=" +
            (player getentitynumber()) + " perk=" + perk +
            " presentation=stock-remove-sfx-and-refund");
        player.iwz_survival_perk_purchase_in_progress = undefined;
        return;
    }

    // Match Arcade Attack's candy purchase presentation against the captured
    // box. Do not signal direct-boss activation here: on Rave that event also
    // wakes unrelated island quest listeners (including the PaP photograph).
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

    perk_count_before = 0;
    if (isdefined(player.zombies_perks))
        perk_count_before = player.zombies_perks.size;

    player scripts\cp\cp_persistence::take_player_currency(cost, 1, "perk");
    if (!isdefined(player.current_perk_list))
        player.current_perk_list = [];
    player.current_perk_list[player.current_perk_list.size] = perk;

    sound_source = spawnstruct();
    sound_source.name = perk;
    sound_source.origin = candy_box.origin;

    survival_log("perk wall purchase presentation started player=" +
        (player getentitynumber()) + " perk=" + perk + " cost=" + cost +
        " perkCount=" + perk_count_before +
        " origin=" + candy_box.origin +
        " audio=stock-machine-jingle-vo-and-candy-foley " +
        "animation=stock-perk-candy-gesture " +
        "bossActivationNotification=skipped");

    level thread scripts\cp\zombies\zombies_perk_machines::
        play_perk_machine_purchase_sound(sound_source, player);
    scripts\cp\cp_vo::remove_from_nag_vo("dj_perkstation_use_nag");
    player scripts\cp\zombies\zombies_perk_machines::play_perk_gesture(perk);
    player scripts\cp\zombies\zombies_perk_machines::give_zombies_perk(
        perk, 0);

    survival_log("perk wall purchase presentation completed player=" +
        (player getentitynumber()) + " perk=" + perk + " perkCount=" +
        perk_count_before + "->" + player.zombies_perks.size);

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
