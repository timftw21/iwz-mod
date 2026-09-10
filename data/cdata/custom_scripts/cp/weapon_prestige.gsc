main()
{
    // Both dumps identify FA1D as the per-player weapon-kit builder. It runs
    // before player_weapon_build_kit_initialized, which wall buys and the
    // mystery wheel consume. Extend that builder before any weapon is granted.
    replacefunc(scripts\cp\zombies\coop_wall_buys::_id_FA1D, ::build_prestige_weapon_kit);
    prestige_log("installed weapon-kit builder reward=optic_plus_six_attachments");
}

prestige_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("WeaponPrestige", message);
}

max_held_weapon_level()
{
    if (!isalive(self) || !isdefined(level.weaponranktable))
    {
        self iprintln("Spawn into the match before using maxweaponlevel");
        prestige_log("maxweaponlevel rejected player=" + self getentitynumber() + " reason=not_spawned");
        return;
    }
    held = self getcurrentweapon();
    if (!isdefined(held) || held == "" || held == "none")
    {
        self iprintln("Hold a weapon before using maxweaponlevel");
        prestige_log("maxweaponlevel rejected player=" + self getentitynumber() + " reason=no_weapon");
        return;
    }

    // Follow cp_weaponrank::try_give_player_weapon_xp's weapon normalization
    // and its cached per-weapon cap, rather than assuming every gun has 15 levels.
    weapon = scripts\cp\utility::getbaseweaponname(held);
    if (!scripts\cp\cp_weaponrank::weapon_has_ranks(weapon))
    {
        self iprintln("The held weapon has no weapon-level progression");
        prestige_log("maxweaponlevel rejected player=" + self getentitynumber() + " held=" + held + " root=" + weapon + " reason=no_ranks");
        return;
    }

    cp_xp = scripts\cp\cp_weaponrank::get_player_weapon_rank_cp_xp(self, weapon);
    mp_xp = scripts\cp\cp_weaponrank::get_player_weapon_rank_mp_xp(self, weapon);
    max_xp = scripts\cp\cp_weaponrank::get_weapon_max_rank_xp(weapon);
    max_level = scripts\cp\cp_weaponrank::get_max_weapon_rank_for_root_weapon(weapon) + 1;
    remaining = max_xp - cp_xp - mp_xp;
    if (remaining <= 0)
    {
        self iprintln("The held weapon is already at max level and XP");
        prestige_log("maxweaponlevel unchanged player=" + self getentitynumber() + " weapon=" + weapon + " xp=" + (cp_xp + mp_xp) + " cap=" + max_xp);
        return;
    }

    // Call the normal award routine, including the existing level-up/AAR hook.
    // Adding the exact deficit bypasses kill-event multipliers without resetting
    // prestige or either mode's accumulated XP.
    scripts\cp\cp_weaponrank::give_player_weapon_xp(self, weapon, remaining);
    new_cp_xp = scripts\cp\cp_weaponrank::get_player_weapon_rank_cp_xp(self, weapon);
    prestige = self getrankedplayerdata("common", "sharedProgression", "weaponLevel", weapon, "prestige");
    if (new_cp_xp + mp_xp < max_xp)
    {
        self iprintln("Weapon XP did not reach its cap; see console log");
        prestige_log("maxweaponlevel failed player=" + self getentitynumber() + " weapon=" + weapon + " xp=" + (new_cp_xp + mp_xp) + " cap=" + max_xp);
        return;
    }
    self iprintln("Held weapon is now level " + max_level + " with max XP");
    prestige_log("maxweaponlevel applied player=" + self getentitynumber() + " held=" + held + " weapon=" + weapon + " cpXP=" + cp_xp + "->" + new_cp_xp + " mpXP=" + mp_xp + " cap=" + max_xp + " level=" + max_level + " prestige=" + prestige);
}

read_prestige_attachments()
{
    self.iwz_prestige_attachments = [];
    entries = strtok(self iwzgetweaponattachments(), ",");
    foreach (entry in entries)
    {
        pair = strtok(entry, ":");
        if (pair.size != 2)
            continue;
        weapon = tablelookup("mp/statsTable.csv", 0, pair[0], 4);
        attachment = tablelookup("mp/attachmentTable.csv", 0, pair[1], 5);
        if (weapon == "" || attachment == "" || attachment == "none")
            continue;
        self.iwz_prestige_attachments[weapon] = attachment;
    }
}

get_prestige_attachment(weapon, equipped)
{
    if (!isdefined(self.iwz_prestige_attachments[weapon]))
        return undefined;

    attachment = self.iwz_prestige_attachments[weapon];
    prestige = self getrankedplayerdata("common", "sharedProgression", "weaponLevel", weapon, "prestige");
    if (!isdefined(prestige) || prestige < 1)
    {
        prestige_log("rejected player=" + self getentitynumber() + " weapon=" + weapon + " reason=prestige_required");
        return undefined;
    }

    // Stock CP AttachmentSelect unlocks individual attachments unconditionally:
    // weapon level gates SLOTS, unlike MP's individual attachment ranks. The
    // prestige field above is this slot's permanent unlock requirement.
    if (tablelookup("mp/attachmentTable.csv", 5, attachment, 2) == "rail")
        return undefined;

    allowed = scripts\cp\utility::getweaponattachmentarrayfromstats(weapon);
    supported = false;
    foreach (candidate in allowed)
    {
        if (scripts\cp\utility::attachmentmap_tobase(candidate) == attachment)
            supported = true;
    }
    if (!supported)
    {
        prestige_log("rejected player=" + self getentitynumber() + " weapon=" + weapon + " attachment=" + attachment + " reason=unsupported_attachment");
        return undefined;
    }
    foreach (other in equipped)
    {
        if (!scripts\cp\utility::attachmentscompatible(attachment, other))
        {
            prestige_log("rejected player=" + self getentitynumber() + " weapon=" + weapon + " attachment=" + attachment + " conflicts=" + other);
            return undefined;
        }
    }
    return attachment;
}

// Stock FA1D body, with the prestige attachment added before mpbuildweaponname.
build_prestige_weapon_kit( var_0 )
{
    level endon( "game_ended" );
    var_0 endon( "disconnect" );
    var_1 = 0;
    var_2 = 1;
    var_3 = 2;
    var_4 = 3;
    var_5 = 6;
    var_0.weapon_build_models = [];
    var_0.rofweaponslist = [];
    var_0._id_13C38 = [];
    var_0 read_prestige_attachments();

    if ( scripts\cp\utility::map_check( 2 ) )
        var_6 = "cp/cp_disco_wall_buy_models.csv";
    else if ( scripts\cp\utility::map_check( 3 ) )
        var_6 = "cp/cp_town_wall_buy_models.csv";
    else if ( scripts\cp\utility::map_check( 4 ) )
        var_6 = "cp/cp_final_wall_buy_models.csv";
    else
        var_6 = "cp/cp_wall_buy_models.csv";

    var_7 = 0;

    for (;;)
    {
        var_8 = tablelookupbyrow( var_6, var_7, var_2 );

        if ( var_8 == "" )
            break;

        var_9 = "none";
        var_10 = "none";
        var_11 = "none";
        var_12 = -1;
        extra_attachment = undefined;

        if ( isdefined( var_8 ) )
        {
            var_13 = tablelookup( var_6, var_1, var_7, var_3 );
            var_14 = tablelookup( var_6, var_1, var_7, var_4 );
            var_15 = [];

            if ( isdefined( var_13 ) && var_13 != "" )
            {
                var_16 = scripts\cp\cp_weaponpassives::_id_7D6C( var_0, var_13 );

                if ( var_16.size > 0 )
                    var_0._id_13C38[var_13] = var_16;

                for ( var_17 = 0; var_17 < var_5; var_17++ )
                {
                    var_18 = var_0 getrankedplayerdata( "cp", "zombiePlayerLoadout", "zombiePlayerWeaponModels", var_13, "attachment", var_17 );

                    if ( isdefined( var_18 ) && var_18 != "none" )
                        var_15[var_15.size] = var_18;
                }

                extra_attachment = var_0 get_prestige_attachment(var_13, var_15);
                if (isdefined(extra_attachment))
                    var_15[var_15.size] = extra_attachment;

                var_9 = scripts\cp\utility::getweaponcamo( var_13 );
                var_10 = scripts\cp\utility::getweaponcosmeticattachment( var_13 );
                var_11 = scripts\cp\utility::getweaponreticle( var_13 );
                var_12 = scripts\cp\utility::getweaponpaintjobid( var_13 );
            }

            var_0.weapon_build_models[var_8] = scripts\cp\utility::mpbuildweaponname( scripts\cp\utility::getweaponrootname( var_14 ), var_15, var_9, var_11, scripts\cp\utility::get_weapon_variant_id( var_0, var_14 ), self getentitynumber(), self.clientid, var_12, var_10 );

            if ( var_8 == "g18" )
                var_0 loadweaponsforplayer( [ var_0.weapon_build_models[var_8] ], 1 );

            var_19 = getweaponattachments( var_0.weapon_build_models[var_8] );

            if (isdefined(extra_attachment))
            {
                included = false;
                foreach (built_attachment in var_19)
                {
                    if (scripts\cp\utility::attachmentmap_tobase(built_attachment) == extra_attachment)
                        included = true;
                }
                prestige_log("built player=" + var_0 getentitynumber() + " weapon=" + var_13 + " sixthAttachment=" + extra_attachment + " included=" + included + " model=" + var_0.weapon_build_models[var_8]);
            }

            foreach ( var_18 in var_19 )
            {
                if ( issubstr( var_18, "rof" ) )
                    var_0.rofweaponslist[var_0.rofweaponslist.size] = getweaponbasename( var_0.weapon_build_models[var_8] );
            }
        }

        var_7++;
    }

    var_0.weaponkitinitialized = 1;
    var_0 notify( "player_weapon_build_kit_initialized" );
}
