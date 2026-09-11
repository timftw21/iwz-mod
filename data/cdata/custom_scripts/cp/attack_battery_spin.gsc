// IWZ-LOAD: map=cp_town
main()
{
    if (getdvar("ui_mapname") != "cp_town")
        return;

    create_drop = getfunction("scripts/cp/zombies/zombies_pillage", "_id_4934");
    if (!isdefined(create_drop))
    {
        battery_spin_log("installation failed: stock pillage drop function unavailable");
        return;
    }

    replacefunc(create_drop, ::create_pillage_drop);
    battery_spin_log("installed battery display rotation map=cp_town revolutionSeconds=2");
}

battery_spin_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("AttackBatterySpin", message);
}

// Preserve retail zombies_pillage::_id_4934, adding rotation only to its
// battery display model. The original interaction and cleanup own its lifetime.
create_pillage_drop(source)
{
    item = spawn("script_model", source.origin);
    item.origin = source.origin;
    item.angles = source.angles;
    item.script_noteworthy = "pillage_item";
    item._id_457D = scripts\cp\zombies\zombies_pillage::_id_7B82(item, source);
    item._id_CB47 = scripts\cp\zombies\zombies_pillage::_id_7A06(item.item);
    item._id_A038 = scripts\cp\zombies\zombies_pillage::_id_7A09(item.item);
    item.requires_power = 0;
    item.powered_on = 1;
    item.script_parameters = "default";
    item.custom_search_dist = 96;
    item setmodel(source.model);
    source delete();
    item thread scripts\cp\zombies\zombies_pillage::_id_13971();
    item thread scripts\cp\zombies\zombies_pillage::_id_5135(item);
    level._id_163C[level._id_163C.size] = item;
    scripts\cp\cp_interaction::add_to_current_interaction_list(item);

    if (item.type == "battery")
    {
        battery = spawn("script_model", item.origin + (0, 0, 20));
        effect = spawnfx(level._effect["pillage_box"], item.origin);
        scripts\engine\utility::waitframe();
        triggerfx(effect);
        scripts\engine\utility::waitframe();
        battery setmodel("crafting_battery_single_01");
        battery thread spin_battery();
        battery_spin_log("started display rotation origin=" + battery.origin);
        item scripts\engine\utility::waittill_any_timeout(60, "all_players_searched");

        if (isdefined(battery))
            battery delete();
        if (isdefined(effect))
            effect delete();
        battery_spin_log("battery display cleaned up");
    }
    else if (item.type != "quest" && item.type != "battery")
    {
        effect = spawnfx(level._effect["pillage_box"], item.origin);
        scripts\engine\utility::waitframe();
        triggerfx(effect);
        item scripts\engine\utility::waittill_any_timeout(60, "all_players_searched");
        if (isdefined(effect))
            effect delete();
    }
    else
        item scripts\engine\utility::waittill_any_timeout(60, "all_players_searched");

    scripts\cp\cp_interaction::remove_from_current_interaction_list(item);
}

spin_battery()
{
    self endon("death");
    for (;;)
    {
        self rotateyaw(360, 2);
        wait 2;
    }
}
