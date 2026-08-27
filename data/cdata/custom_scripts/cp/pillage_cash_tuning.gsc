main()
{
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
