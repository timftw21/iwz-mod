post_load()
{
    if (getdvar("ui_mapname") != "cp_final")
        return;

    stock_starting_ammo = level.force_starting_ammo;
    level.force_starting_ammo = 350;

    custom_scripts\cp\gsc_diagnostics::emit("Ammo",
        "Beast starting OSA reserve=" + stock_starting_ammo + "->" + level.force_starting_ammo +
        " source=cp_final::setuphacks/force_starting_ammo");
}
