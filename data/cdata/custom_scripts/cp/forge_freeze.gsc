main()
{
    replacefunc(scripts\cp\zombies\zombies_weapons::weapon_watch_hint, ::weapon_watch_hint);
    custom_scripts\cp\gsc_diagnostics::emit("ForgeFreeze",
        "installed weapon hint once per player per match; hold=3s fade=0.5s");
}

weapon_watch_hint()
{
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");
    self.axe_hint_display = 0;
    self.nx1_hint_display = 0;
    weapon_base = getweaponbasename(self getcurrentprimaryweapon());
    weapon = self getcurrentweapon();
    previous_weapon = undefined;

    for (;;)
    {
        if (isdefined(weapon_base) && weapon_base == "iw7_axe_zm" && self.axe_hint_display < 3)
        {
            scripts\cp\utility::setlowermessage("msg_axe_hint", &"CP_ZOMBIE_AXE_HINT", 4);
            self.axe_hint_display++;
        }
        else if (isdefined(weapon_base) &&
            (weapon_base == "iw7_forgefreeze_zm" || weapon_base == "iw7_forgefreeze_zm_pap1" ||
                weapon_base == "iw7_forgefreeze_zm_pap2") && !isdefined(self.iwz_forge_hint_shown))
        {
            // Keep this flag across weapon changes and respawns. The stock watcher
            // resets its counter on spawn and queues the same fading hint five times.
            self.iwz_forge_hint_shown = true;
            self thread show_forge_hint();
        }

        scripts\cp\zombies\zombies_weapons::updatecamoscripts(weapon, previous_weapon);
        previous_weapon = weapon;
        self waittill("weapon_change");
        wait(0.5);
        weapon_base = getweaponbasename(self getcurrentprimaryweapon());
        weapon = self getcurrentweapon();
    }
}

show_forge_hint()
{
    level endon("game_ended");
    font = "default";
    if (isdefined(level.lowermessagefont))
        font = level.lowermessagefont;
    y = level.lowertexty;
    size = level.lowertextfontsize;
    if (level.splitscreen || self issplitscreenplayer() && !isai(self))
    {
        y -= 40;
        size *= 1.3;
    }

    // Use the stock lower-message layout with an independent lifetime so another
    // message cannot restart its fade or redisplay it when the queue changes.
    hint = scripts\cp\utility::createfontstring(font, size);
    hint.archived = 0;
    hint.sort = 10;
    hint.showinkillcam = 0;
    hint.hidewheninmenu = 1;
    hint scripts\cp\utility::setpoint("CENTER", level.lowertextyalign, 0, y);
    hint settext(&"CP_ZOMBIE_FORGEFREEZE_HINT");
    hint.alpha = 0.85;
    custom_scripts\cp\gsc_diagnostics::emit("ForgeFreeze",
        "hint shown player=" + self getentitynumber() + " hold=3s fade=0.5s");

    reason = self scripts\engine\utility::waittill_any_in_array_or_timeout_no_endon_death(
        ["death", "last_stand", "disconnect"], 3);
    if (reason == "timeout" && isdefined(hint))
    {
        hint fadeovertime(0.5);
        hint.alpha = 0;
        reason = self scripts\engine\utility::waittill_any_in_array_or_timeout_no_endon_death(
            ["death", "last_stand", "disconnect"], 0.5);
    }
    if (isdefined(hint))
        hint scripts\cp\utility::destroyelem();
    custom_scripts\cp\gsc_diagnostics::emit("ForgeFreeze", "hint removed reason=" + reason);
}
