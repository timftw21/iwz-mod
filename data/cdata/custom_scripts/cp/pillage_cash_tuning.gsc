main()
{
    replacefunc(scripts\cp\cp_persistence::give_player_currency, ::give_player_currency);
    pillage_cash_log("installed pickup-time Double Points multiplier source=level.cash_scalar type=pillage");

    configure_item = getfunction("scripts/cp/zombies/zombies_pillage", "_id_7B82");
    select_type = getfunction("scripts/cp/zombies/zombies_pillage", "_id_7BEF");
    select_explosive = getfunction("scripts/cp/zombies/zombies_pillage", "_id_3E8D");
    select_power = getfunction("scripts/cp/zombies/zombies_pillage", "_id_3E8E");

    if (!isdefined(configure_item) || !isdefined(select_type) ||
        !isdefined(select_explosive) || !isdefined(select_power))
    {
        pillage_cash_log("installation failed: one or more retail zombies_pillage function lookups were unavailable");
        return;
    }

    level.iwz_pillage_select_type = select_type;
    level.iwz_pillage_select_explosive = select_explosive;
    level.iwz_pillage_select_power = select_power;
    replacefunc(configure_item, ::configure_pillage_item_without_50_cash);
    pillage_cash_log("installed retail zombies_pillage::_id_7B82 replacement cashValues=100,200,250,500,1000 removed=50");
}

pillage_cash_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("PillageCash", message);
}

// Keep the stock currency award path, including its cap, card charge and HUD
// notifications. Only pillage cash bypasses Double Money in the retail game.
give_player_currency(amount, size, effect, skip_prestige, give_type)
{
    if (!isplayer(self))
        return;

    if (isdefined(give_type) && give_type == "pillage" && isdefined(level.cash_scalar))
    {
        base_amount = amount;
        amount = int(amount * level.cash_scalar);
        pillage_cash_log("pickup player=" + self getentitynumber() + " base=" +
            base_amount + " cashScalar=" + level.cash_scalar + " award=" + amount);
    }

    if (!scripts\engine\utility::is_true(skip_prestige))
    {
        amount = int(amount * scripts\cp\perks\prestige::prestige_getmoneyearnedscalar());
        amount = scripts\cp\cp_gamescore::round_up_to_nearest(amount, 5);
    }

    if (isdefined(level.currency_scale_func))
        amount = [[level.currency_scale_func]](self, amount);

    previous = scripts\cp\cp_persistence::get_player_currency();
    maximum = scripts\cp\cp_persistence::get_player_max_currency();
    balance = min(previous + amount, maximum);

    if (!isdefined(self.total_currency_earned))
        self.total_currency_earned = amount;

    if (scripts\cp\cp_persistence::is_valid_give_type(give_type))
    {
        self.total_currency_earned += balance - previous;
        self notify("consumable_charge", amount * 0.5);
    }

    level notify("currency_changed");
    scripts\cp\cp_persistence::eog_player_update_stat("currencytotal", int(self.total_currency_earned), 1);
    scripts\cp\cp_persistence::set_player_currency(balance);

    if (isdefined(level.update_money_performance))
        [[level.update_money_performance]](self, amount);

    now = gettime();
    if (balance >= maximum)
    {
        if (!isdefined(self.next_maxmoney_hint_time))
            self.next_maxmoney_hint_time = now + 30000;
        else if (now < self.next_maxmoney_hint_time)
            return;

        if (!level.gameended)
        {
            scripts\cp\utility::setlowermessage("maxmoney", &"COOP_GAME_PLAY_MONEY_MAX", 4);
            self.next_maxmoney_hint_time = now + 30000;
        }
    }

    if (scripts\cp\cp_persistence::is_valid_give_type(give_type))
        thread scripts\cp\utility::add_to_notify_queue("player_earned_money", amount);

    self notify("currency_earned", amount);
    if (!scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight())
        scripts\cp\utility::bufferednotify("currency_earned_buffered", amount);

    scripts\cp\cp_persistence::eog_player_update_stat("score", int(self.total_currency_earned), 1);
}

configure_pillage_item_without_50_cash(item, source)
{
    if (!scripts\engine\utility::flag("can_drop_coins"))
        excluded_types = ["quest"];
    else
        excluded_types = [];

    selected_type = [[level.iwz_pillage_select_type]](level._id_CB87, excluded_types);
    if (isdefined(item._id_4FFB))
        selected_type = item._id_4FFB;

    switch (selected_type)
    {
        case "explosive":
            item.item = [[level.iwz_pillage_select_explosive]]();
            item.type = "explosive";
            item.count = 0;
            break;

        case "powers":
            item.item = [[level.iwz_pillage_select_power]]();
            item.type = "powers";
            item.count = 0;
            break;

        case "clip":
            item.type = "clip";
            item.item = "clip";
            item.count = 1;
            break;

        case "maxammo":
            item.type = "maxammo";
            item.item = "maxammo";
            item.count = 1;
            break;

        case "money":
            item.type = "money";
            item.amount = int(scripts\engine\utility::random([1000, 500, 250, 200, 100]));
            item.item = "money";
            pillage_cash_log("generated cash item amount=" + item.amount + " minimum=100");
            break;

        case "tickets":
            item.type = "tickets";
            item.item = "tickets";
            item.amount = randomint(100);
            break;

        case "quest":
            if (isdefined(level.quest_create_pillage_interaction))
                [[level.quest_create_pillage_interaction]](item, source);
            break;

        case "battery":
            item.type = "battery";
            item.item = "battery";
            item.count = 1;
            break;
    }

    return item;
}
