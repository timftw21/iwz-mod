main()
{
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    if (getdvar("ui_mapname") != "cp_rave")
    {
        survival_log("launch rejected reason=unsupported-map requested=" +
            getdvar("ui_mapname") + " supported=cp_rave");
        setdvar("iwz_survival_mode", 0);
        return;
    }

    // Reuse the complete Boss Battle perk board and its closed candy boxes.
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
    precachemodel("fullbody_zmb_skeleton");
    precachemodel("cp_rave_magic_wheel");
    precachemodel("cp_rave_magic_wheel_on");
    precachemodel("zmb_magic_wheel_spinner");

    replacefunc(scripts\cp\maps\cp_rave\cp_rave::init_magic_wheel,
        ::survival_select_island_wheel);
    replacefunc(scripts\cp\zombies\interaction_magicwheel::_id_BC3F,
        ::survival_hold_wheel_location);
    replacefunc(scripts\cp\maps\cp_rave\cp_rave::watch_zombie_health,
        ::survival_disable_skeleton_eye_monitor);
    replacefunc(scripts\cp\zombies\zombies_pillage::_id_6690,
        ::survival_disable_skeleton_pillage);
    replacefunc(scripts\cp\zombies\directors_cut::allow_directors_cut,
        ::survival_disallow_directors_cut);
    replacefunc(scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        wait_for_player_to_take_weapon,
        ::survival_wait_for_player_to_take_upgraded_weapon);

    survival_log("pre-load hooks installed map=cp_rave area=island " +
        "spawn=island_dropoff_player " +
        "wheel=scriptable-controller-plus-solid-visual-and-playerclip " +
        "perkSource=spaceland-boss-battle-board " +
        "zombieModel=fullbody_zmb_skeleton directorsCut=disabled " +
        "papPickupMetadata=guarded");
}

post_load()
{
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    if (!isdefined(level.script) || level.script != "cp_rave")
    {
        actual_script = "undefined";
        if (isdefined(level.script))
            actual_script = level.script;

        survival_log("post-load rejected expected=cp_rave actual=" +
            actual_script);
        return;
    }

    // Rave's island is already a complete authored combat volume. The stock
    // boat uses these same drop-off structs when it reaches the island.
    level.initial_active_volumes = ["island"];
    level.getspawnpoint =
        scripts\cp\maps\cp_rave\cp_rave::respawn_on_island;
    level.force_respawn_location =
        scripts\cp\maps\cp_rave\cp_rave::respawn_on_island;
    level.default_weapon = "iw7_m1c_zm";

    if (isdefined(level.char_intro_gesture))
    {
        level.iwz_survival_stock_char_intro_gesture =
            level.char_intro_gesture;
        level.char_intro_gesture = ::survival_char_intro_gesture;
    }

    if (isdefined(level.custom_onspawnplayer_func))
    {
        level.iwz_survival_stock_onspawn = level.custom_onspawnplayer_func;
        level.custom_onspawnplayer_func = ::survival_on_player_spawned;
    }

    if (isdefined(level.spawn_fx_func))
    {
        level.iwz_survival_stock_spawn_fx_func = level.spawn_fx_func;
        level.spawn_fx_func = ::survival_skeleton_spawn_fx;
    }

    // zmb_zombie_agent deliberately checks this override list before the
    // map's ordinary DLC1 outfit list. Rave already registers and precaches
    // the skeleton agent/model for its memory quests.
    level.generic_zombie_model_override_list = ["fullbody_zmb_skeleton"];

    install_survival_quick_revive_hooks();
    level thread enforce_survival_spawn_volumes();
    level thread configure_survival_weapon_wheel();
    level thread monitor_survival_zombie_models();
    level thread activate_survival_pap();
    level thread enable_survival_double_pap();
    level thread setup_survival_perk_purchase_wall();

    survival_log("Rave Rampage initialized initialVolume=island " +
        "spawn=island_dropoff_player " +
        "wheelSurface=(-4547.9,4878.54,-139.606) " +
        "perkSurface=(-6093.34,4569.24,179.093) " +
        "startingWeapon=iw7_m1c_zm " +
        "zombieModelOverride=fullbody_zmb_skeleton " +
        "pap=stock-auto-repair,double-pap-enabled");
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

survival_char_intro_gesture()
{
    if (isdefined(level.iwz_survival_stock_char_intro_gesture))
        self [[level.iwz_survival_stock_char_intro_gesture]]();

    previous_weapon = "undefined";
    if (isdefined(self.starting_weapon))
    {
        previous_weapon = self.starting_weapon;
        if (previous_weapon != "iw7_m1c_zm")
            self takeweapon(previous_weapon);
    }

    starting_weapon = self scripts\cp\utility::_giveweapon(
        "iw7_m1c_zm", undefined, undefined, 1);
    self switchtoweapon(starting_weapon);
    self setspawnweapon(starting_weapon, 1);
    self.starting_weapon = starting_weapon;
    self.default_starting_pistol = starting_weapon;

    // The stock loadout registered the Rave fists as the starting weapon
    // before this post-intro substitution. Register the M1 at PaP level one
    // so Rave's first upgrade has the same metadata as an ordinary loadout.
    starting_base = scripts\cp\utility::getrawbaseweaponname(starting_weapon);
    if (!isdefined(self.pap))
        self.pap = [];
    if (!isdefined(self.pap[starting_base]))
        self.pap[starting_base] = spawnstruct();
    self.pap[starting_base].lvl = 1;
    self notify("weapon_level_changed");

    character_index =
        scripts\cp\zombies\zombies_loadout::get_player_character_num();
    if (isdefined(level.player_character_info) &&
        isdefined(level.player_character_info[character_index]))
    {
        level.player_character_info[character_index].starting_weapon =
            starting_weapon;
    }

    survival_log("starting weapon applied player=" +
        (self getentitynumber()) + " previous=" + previous_weapon +
        " weapon=" + starting_weapon +
        " papBase=" + starting_base + " papLevel=" +
        self.pap[starting_base].lvl +
        " source=post-rave-intro-gesture");
}

survival_skeleton_spawn_fx()
{
    if (isdefined(self.agent_type) && self.agent_type == "generic_zombie")
    {
        if (!scripts\engine\utility::is_true(
            level.iwz_survival_logged_skeleton_spawn_fx_suppression))
        {
            level.iwz_survival_logged_skeleton_spawn_fx_suppression = 1;
            survival_log("skeleton-incompatible spawn FX suppressed " +
                "parts=spawn_fx_concrete,spawn_fx_dirt,spawn_fx_ceiling," +
                "dirt,dirt_concrete scope=generic_zombie");
        }
        return;
    }

    if (isdefined(level.iwz_survival_stock_spawn_fx_func))
        self [[level.iwz_survival_stock_spawn_fx_func]]();
}

survival_disable_skeleton_eye_monitor()
{
    if (!scripts\engine\utility::is_true(
        level.iwz_survival_logged_skeleton_eye_suppression))
    {
        level.iwz_survival_logged_skeleton_eye_suppression = 1;
        survival_log("skeleton-incompatible statue eye monitor suppressed " +
            "parts=eyes states=red_eyes,yellow_eyes");
    }
}

survival_disable_skeleton_pillage(agent)
{
    if (!scripts\engine\utility::is_true(
        level.iwz_survival_logged_skeleton_pillage_suppression))
    {
        level.iwz_survival_logged_skeleton_pillage_suppression = 1;
        survival_log("skeleton-incompatible pillage attachments suppressed " +
            "scope=Rave-Rampage agents=generic-zombie");
    }
}

get_survival_island_dropoff(player)
{
    dropoffs = scripts\engine\utility::getstructarray(
        "island_dropoff_player", "targetname");
    if (!isdefined(dropoffs) || !dropoffs.size)
        return undefined;

    player_number = player getentitynumber();
    foreach (dropoff in dropoffs)
    {
        if (isdefined(dropoff.script_count) &&
            dropoff.script_count == player_number)
        {
            return dropoff;
        }
    }

    return dropoffs[player_number % dropoffs.size];
}

survival_on_player_spawned()
{
    if (isdefined(level.iwz_survival_stock_onspawn))
        self [[level.iwz_survival_stock_onspawn]]();

    if (getdvarint("scr_gameended", 0))
    {
        survival_log("gameplay spawn relocation skipped ent=" +
            (self getentitynumber()) + " reason=stock-intermission-camera");
        return;
    }

    dropoff = get_survival_island_dropoff(self);
    if (!isdefined(dropoff))
    {
        survival_log("player spawn relocation failed ent=" +
            (self getentitynumber()) +
            " reason=island_dropoff_player-missing");
        return;
    }

    // The stock boat drop-off uses getgroundposition with only 32 units of
    // downward reach. Its authored origins can be farther above the island,
    // so trace through the full vertical gap instead of inheriting that hover.
    grounded_origin = scripts\engine\utility::drop_to_ground(
        dropoff.origin, 32, -512) + (0, 0, 1);
    spawn_angles = (0, 0, 0);
    if (isdefined(dropoff.angles))
        spawn_angles = dropoff.angles;

    dropoff_script_count = "undefined";
    if (isdefined(dropoff.script_count))
        dropoff_script_count = dropoff.script_count;

    self dontinterpolate();
    self setorigin(grounded_origin);
    self setplayerangles(spawn_angles);

    survival_log("player spawned ent=" + (self getentitynumber()) +
        " authoredOrigin=" + dropoff.origin +
        " groundedOrigin=" + grounded_origin +
        " groundDelta=" + (grounded_origin - dropoff.origin) +
        " angles=" + spawn_angles +
        " source=island_dropoff_player grounding=physics-trace scriptCount=" +
        dropoff_script_count);
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
        if (isdefined(volume.basename) && volume.basename != "island")
            volumes_to_disable[volumes_to_disable.size] = volume.basename;
    }

    foreach (volume_name in volumes_to_disable)
    {
        scripts\cp\zombies\zombies_spawning::deactivate_volume_by_name(
            volume_name);
    }

    scripts\cp\zombies\zombies_spawning::activate_volume_by_name("island");
    scripts\cp\zombies\zombie_entrances::enable_windows_in_area("island");

    survival_log("spawn volumes enforced active=island disabled=" +
        volumes_to_disable.size +
        " source=stock-island-combat-volume windows=island");
}

create_survival_weapon_wheel()
{
    target_origin = (-4547.9, 4878.54, -139.606);
    authored_wheels = level._id_B163;

    if (!isdefined(authored_wheels) || !authored_wheels.size)
    {
        survival_log("weapon wheel creation failed " +
            "reason=shared-wheel-list-unavailable");
        return;
    }

    // Rave's authored bases are map scriptables and reject setorigin. Keep one
    // as a hidden state controller, then create the visible base at the target.
    source_wheel = undefined;
    foreach (candidate in authored_wheels)
    {
        if (isdefined(candidate.area_name) &&
            candidate.area_name == "lake_shore")
        {
            source_wheel = candidate;
            break;
        }
    }

    if (!isdefined(source_wheel))
    {
        source_wheel = scripts\engine\utility::getclosest(
            target_origin, authored_wheels);
        survival_log("weapon wheel source fallback expected=lake_shore " +
            "selected=closest-authored-wheel");
    }

    stock_origin = source_wheel.origin;
    stock_angles = (0, 0, 0);
    if (isdefined(source_wheel.angles))
        stock_angles = source_wheel.angles;

    // The placement trace's horizontal heading is 268.274 degrees. Use the
    // clean cardinal heading so the cabinet faces straight down the path.
    target_angles = (0, 270, 0);

    source_spinner = source_wheel._id_10A03;
    spinner_origin = transform_survival_wheel_point(source_spinner.origin,
        stock_origin, stock_angles, target_origin, target_angles);
    spinner_angles = transform_survival_wheel_angles(source_spinner.angles,
        stock_angles, target_angles);

    visual_wheel = spawn("script_model", target_origin);
    visual_wheel.angles = target_angles;
    visual_wheel setmodel("cp_rave_magic_wheel");
    visual_wheel setnonstick(1);
    visual_wheel solid();

    // Dynamic xmodel physics stop shots and props but are excluded from the
    // player movement trace. Rave ships an authored player-only brush template
    // specifically for runtime cloning, so use its 64x64x128 volume as the
    // cabinet's movement collision instead of approximating physics contents.
    player_blocker = create_survival_wheel_player_blocker(
        target_origin, target_angles);

    new_spinner = spawn("script_model", spinner_origin);
    new_spinner.angles = spinner_angles;
    new_spinner setmodel("zmb_magic_wheel_spinner");

    wheel_fx = undefined;
    wheel_fx_spots = scripts\engine\utility::getstructarray(
        "wheel_fx_spot", "targetname");
    if (isdefined(wheel_fx_spots) && wheel_fx_spots.size)
    {
        wheel_fx = scripts\engine\utility::getclosest(
            stock_origin, wheel_fx_spots);
    }

    fx_origin = "undefined";
    if (isdefined(wheel_fx))
    {
        wheel_fx.origin = transform_survival_wheel_point(wheel_fx.origin,
            stock_origin, stock_angles, target_origin, target_angles);
        if (isdefined(wheel_fx.angles))
        {
            wheel_fx.angles = transform_survival_wheel_angles(wheel_fx.angles,
                stock_angles, target_angles);
        }
        fx_origin = wheel_fx.origin;
    }

    // Remove all authored wheel listeners before replacing the shared list.
    foreach (authored_wheel in authored_wheels)
    {
        authored_wheel notify("delete_wheel");
        authored_wheel makeunusable();
        authored_wheel setscriptablepartstate("base", "off");
        authored_wheel setscriptablepartstate("fx", "off");
        authored_wheel._id_10A03 setscriptablepartstate("spinner", "off");
    }

    // A plain spawned base model has no base/fx/spin_light scriptable parts.
    // Keep one hidden authored base as the stock logic controller and move its
    // server-side transform, while the new solid model supplies presentation
    // and collision at that same transform. The spawned spinner is scriptable.
    source_wheel.origin = target_origin;
    source_wheel.angles = target_angles;
    source_wheel.area_name = "island";
    source_wheel._id_E74A =
        scripts\cp\zombies\interaction_magicwheel::_id_7C20();
    source_wheel._id_13C25 =
        scripts\cp\zombies\interaction_magicwheel::_id_7ABF();
    source_wheel._id_10A03 = new_spinner;
    source_wheel.iwz_survival_visual = visual_wheel;

    level._id_B163 = [source_wheel];
    level._id_B160 = ["island"];
    level.current_active_wheel = source_wheel;
    level.iwz_rave_rampage_wheel = source_wheel;
    level.iwz_rave_rampage_wheel_visual = visual_wheel;
    if (isdefined(player_blocker))
        level.iwz_rave_rampage_wheel_player_blocker = player_blocker;
    source_wheel thread scripts\cp\zombies\interaction_magicwheel::_id_13643();

    survival_log("weapon wheel assembly created controllerEntity=" +
        (source_wheel getentitynumber()) + " visualEntity=" +
        (visual_wheel getentitynumber()) + " visualModel=" +
        visual_wheel.model +
        " sourceOrigin=" + stock_origin + " sourceAngles=" + stock_angles +
        " targetOrigin=" + target_origin + " targetAngles=" + target_angles +
        " spinnerEntity=" + (new_spinner getentitynumber()) +
        " spinnerOrigin=" + spinner_origin + " fxOrigin=" + fx_origin +
        " facingSource=fixed-path-forward targetArea=island " +
        "components=scriptable-controller,new-solid-base,new-spinner," +
        "fx-spot,authored-playerclip collision=projectile-and-player " +
        "authoredWheelsRetired=" + authored_wheels.size +
        " phase=shared-wheel-ready");
}

create_survival_wheel_player_blocker(target_origin, target_angles)
{
    player_clip_template = getent("player64x64x128", "targetname");
    if (!isdefined(player_clip_template))
    {
        survival_log("weapon wheel player collision creation failed " +
            "reason=player64x64x128-template-missing");
        return undefined;
    }

    blocker = spawn("script_model", (0, 0, 0));
    blocker clonebrushmodeltoscriptmodel(player_clip_template);
    blocker.origin = target_origin + (0, 0, 64);
    blocker.angles = target_angles;

    survival_log("weapon wheel player collision created entity=" +
        (blocker getentitynumber()) + " origin=" + blocker.origin +
        " angles=" + blocker.angles +
        " brush=player64x64x128 contents=authored-playerclip");
    return blocker;
}

transform_survival_wheel_point(point, source_origin, source_angles,
    target_origin, target_angles)
{
    delta = point - source_origin;
    yaw_delta = target_angles[1] - source_angles[1];
    cosine = cos(yaw_delta);
    sine = sin(yaw_delta);
    return target_origin + (
        delta[0] * cosine - delta[1] * sine,
        delta[0] * sine + delta[1] * cosine,
        delta[2]);
}

transform_survival_wheel_angles(angles, source_angles, target_angles)
{
    return (angles[0], angles[1] + target_angles[1] - source_angles[1],
        angles[2]);
}

survival_select_island_wheel()
{
    scripts\cp\zombies\interaction_magicwheel::
        set_magic_wheel_starting_location("lake_shore");
    survival_log("weapon wheel startup staged area=lake_shore " +
        "phase=cp_rave-init targetArea=island creation=after-shared-init");
}

survival_hold_wheel_location()
{
    survival_log("weapon wheel relocation intercepted " +
        "action=retain-new-island-wheel");
    activate_survival_weapon_wheel("relocation-intercept");
}

configure_survival_weapon_wheel()
{
    level endon("game_ended");

    while (!isdefined(level.magic_weapons) ||
        !isdefined(level.all_magic_weapons))
    {
        scripts\engine\utility::waitframe();
    }

    // Rave's Director's Cut implementation identifies these as the four map
    // wonder weapons. Survival exposes them without enabling Director's Cut.
    level.magic_weapons["acidrain"] = "iw7_harpoon1_zm";
    level.magic_weapons["benfranklin"] = "iw7_harpoon2_zm";
    level.magic_weapons["trapomatic"] = "iw7_harpoon3_zm+akimbo";
    level.magic_weapons["whirlwind"] = "iw7_harpoon4_zm";
    level.all_magic_weapons["acidrain"] = "iw7_harpoon1_zm";
    level.all_magic_weapons["benfranklin"] = "iw7_harpoon2_zm";
    level.all_magic_weapons["trapomatic"] = "iw7_harpoon3_zm+akimbo";
    level.all_magic_weapons["whirlwind"] = "iw7_harpoon4_zm";

    while (!isdefined(level._id_B163))
        scripts\engine\utility::waitframe();

    initialization_complete = 0;
    while (!initialization_complete)
    {
        initialization_complete = 1;
        foreach (wheel in level._id_B163)
        {
            if (!isdefined(wheel._id_10A03))
            {
                initialization_complete = 0;
                break;
            }
        }

        if (!initialization_complete)
            scripts\engine\utility::waitframe();
    }

    // This flag is initialized after the shared wheel system is fully ready.
    // Waiting on it prevents our activation from racing stock initialization.
    while (!scripts\engine\utility::flag_exist("fire_sale"))
        scripts\engine\utility::waitframe();

    // Once shared setup has loaded the wheel assets and helpers, create a new
    // visible Survival assembly backed by one authored state controller.
    create_survival_weapon_wheel();
    if (!isdefined(level.iwz_rave_rampage_wheel))
    {
        survival_log("weapon wheel configuration aborted " +
            "reason=new-wheel-creation-failed");
        return;
    }

    foreach (wheel in level._id_B163)
    {
        wheel._id_13C25 =
            scripts\cp\zombies\interaction_magicwheel::_id_7ABF();
    }

    log_survival_wheel_candidates();
    activate_survival_weapon_wheel("post-stock-initialization");
}

log_survival_wheel_candidates()
{
    foreach (wheel in level._id_B163)
    {
        area = "undefined";
        if (isdefined(wheel.area_name))
            area = wheel.area_name;

        selected = 0;
        if (isdefined(level.iwz_rave_rampage_wheel))
            selected = wheel == level.iwz_rave_rampage_wheel;

        survival_log("weapon wheel candidate entity=" +
            (wheel getentitynumber()) + " area=" + area +
            " origin=" + wheel.origin + " selected=" + selected);
    }
}

activate_survival_weapon_wheel(reason)
{
    wheel = level.iwz_rave_rampage_wheel;
    if (!isdefined(wheel) || !isdefined(wheel.area_name) ||
        !isdefined(wheel._id_10A03))
    {
        survival_log("weapon wheel activation failed reason=entity-not-ready " +
            "phase=" + reason);
        return;
    }

    scripts\cp\zombies\interaction_magicwheel::
        set_magic_wheel_starting_location(wheel.area_name);
    // The authored entity is retained only for its valid scriptable state
    // machine. Its client transform cannot move, so keep its visible parts off
    // while the new target-position model supplies the cabinet presentation.
    wheel setscriptablepartstate("base", "off");
    wheel setscriptablepartstate("fx", "off");
    wheel._id_10A03 setscriptablepartstate("spinner", "idle");
    wheel makeusable();
    wheel _meth_84A7("tag_use");
    wheel setusefov(60);
    wheel setuserange(72);
    if (isdefined(level.magic_wheel_spin_hint))
        wheel sethintstring(level.magic_wheel_spin_hint);
    else
        wheel sethintstring(&"CP_ZMB_INTERACTIONS_SPIN_WHEEL");
    level.current_active_wheel = wheel;

    if (!isdefined(wheel.iwz_survival_no_teddy_monitor))
    {
        wheel.iwz_survival_no_teddy_monitor = 1;
        wheel thread prevent_survival_wheel_teddy();
    }

    survival_log("weapon wheel activated phase=" + reason +
        " entity=" + (wheel getentitynumber()) +
        " area=" + wheel.area_name + " origin=" + wheel.origin +
        " angles=" + wheel.angles + " states=base=" +
        (wheel getscriptablepartstate("base")) + " fx=" +
        (wheel getscriptablepartstate("fx")) + " spinner=" +
        (wheel._id_10A03 getscriptablepartstate("spinner")) +
        " wonders=acidrain,benfranklin,trapomatic,whirlwind " +
        "instance=scriptable-controller-plus-solid-visual-and-playerclip " +
        "teddy=disabled");
}

prevent_survival_wheel_teddy()
{
    level endon("game_ended");

    for (;;)
    {
        self waittill("ready");
        completed_streak = level._id_13D01;
        level._id_13D01 = 0;
        level._id_B162 = 0;
        survival_log("weapon wheel movement streak reset entity=" +
            (self getentitynumber()) + " completedStreak=" +
            completed_streak + " behavior=fire-sale-no-teddy");
    }
}

monitor_survival_zombie_models()
{
    level endon("game_ended");
    level.iwz_survival_logged_skeletons = 0;

    for (;;)
    {
        level waittill("agent_spawned", agent);
        if (isdefined(agent.agent_type) &&
            agent.agent_type == "generic_zombie")
        {
            agent thread verify_survival_zombie_model();
        }
    }
}

verify_survival_zombie_model()
{
    level endon("game_ended");
    self endon("death");

    for (frame = 0; frame < 100 && !isdefined(self.model); frame++)
        scripts\engine\utility::waitframe();

    model_name = "undefined";
    if (isdefined(self.model))
        model_name = self.model;

    model_matches = model_name == "fullbody_zmb_skeleton";
    if (level.iwz_survival_logged_skeletons < 8 || !model_matches)
    {
        level.iwz_survival_logged_skeletons++;
        survival_log("zombie model verified ent=" +
            (self getentitynumber()) + " agentType=" + self.agent_type +
            " model=" + model_name + " expected=fullbody_zmb_skeleton " +
            "matched=" + model_matches);
    }
}

survival_wait_for_player_to_take_upgraded_weapon(upgraded_weapon,
    fists_weapon, target_level)
{
    self endon("death");
    self waittill("trigger", player);

    if (!isdefined(fists_weapon))
        fists_weapon = "iw7_fists_zm";

    if (player hasweapon(fists_weapon))
        player takeweapon(fists_weapon);

    if (player scripts\cp\cp_weapon::has_weapon_variation(upgraded_weapon))
    {
        upgraded_base = scripts\cp\utility::getrawbaseweaponname(
            upgraded_weapon);
        foreach (owned_weapon in player getweaponslistall())
        {
            owned_base = scripts\cp\utility::getrawbaseweaponname(
                owned_weapon);
            if (upgraded_base == owned_base)
                player takeweapon(owned_weapon);
        }
    }

    if (scripts\cp\zombies\interaction_weapon_upgrade::
        should_take_players_current_weapon(player))
    {
        current_weapon = player getcurrentweapon();
        player takeweapon(current_weapon);
    }

    self notify("weapon_taken");
    upgraded_weapon = player scripts\cp\utility::_giveweapon(
        upgraded_weapon, undefined, undefined, 0);
    player givemaxammo(upgraded_weapon);

    foreach (primary_weapon in player getweaponslistprimaries())
    {
        if (!issubstr(primary_weapon, upgraded_weapon))
            continue;

        if (scripts\cp\utility::isaltmodeweapon(primary_weapon))
        {
            primary_base = getweaponbasename(primary_weapon);
            if (isdefined(level.alt_mode_weapons_allowed) &&
                scripts\engine\utility::array_contains(
                    level.alt_mode_weapons_allowed, primary_base))
            {
                upgraded_weapon = "alt_" + upgraded_weapon;
                break;
            }
        }
    }

    player switchtoweapon(upgraded_weapon);
    upgraded_base = scripts\cp\utility::getrawbaseweaponname(
        upgraded_weapon);
    target_level = int(target_level);
    previous_level = "undefined";
    metadata_initialized = 0;

    if (!isdefined(player.pap))
        player.pap = [];

    if (isdefined(player.pap[upgraded_base]))
        previous_level = player.pap[upgraded_base].lvl;
    else
    {
        player.pap[upgraded_base] = spawnstruct();
        metadata_initialized = 1;
    }

    // The caller already calculated the desired level. Assign it exactly;
    // the stock blind increment crashes when a custom loadout lacks a record
    // and can drift from the weapon variant when earlier state was stale.
    player.pap[upgraded_base].lvl = target_level;
    player scripts\cp\cp_persistence::give_player_xp(500, 1);
    player notify("weapon_level_changed");

    survival_log("PaP weapon pickup completed player=" +
        (player getentitynumber()) + " weapon=" + upgraded_weapon +
        " base=" + upgraded_base + " level=" + previous_level + "->" +
        target_level + " metadataInitialized=" + metadata_initialized +
        " update=exact-target-level");
}

activate_survival_pap()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("pap_fixed") ||
        !scripts\engine\utility::flag_exist("init_interaction_done") ||
        !isdefined(level.pap_pieces_found) ||
        !isdefined(level.projector_struct) || !isdefined(level.players) ||
        !level.players.size)
    {
        scripts\engine\utility::waitframe();
    }

    if (scripts\engine\utility::flag("pap_fixed"))
    {
        survival_log("PaP auto-repair skipped reason=already-fixed");
        return;
    }

    repair_structs = scripts\engine\utility::getstructarray(
        "fix_pap", "script_noteworthy");
    if (!isdefined(repair_structs) || !repair_structs.size)
    {
        survival_log("PaP auto-repair failed reason=fix-pap-struct-missing");
        return;
    }

    pieces_before = level.pap_pieces_found;
    level.pap_pieces_found = 2;
    scripts\engine\utility::flag_set("pap_fixed");

    // Auto-completing the projector must retire the two silent pickup
    // interactions as well as the repair prompt. Otherwise an invisible
    // reel can consume use input at the perk board and publish quest icons
    // 11/12 (the PaP inventory photographs).
    pap_quest_pieces = scripts\engine\utility::getstructarray(
        "pap_quest_piece", "script_noteworthy");
    retired_pap_pickups = 0;
    foreach (pap_quest_piece in pap_quest_pieces)
    {
        scripts\cp\cp_interaction::remove_from_current_interaction_list(
            pap_quest_piece);
        if (isdefined(pap_quest_piece.model))
        {
            pap_quest_piece.model delete();
            pap_quest_piece.model = undefined;
        }
        retired_pap_pickups++;
    }
    level scripts\cp\utility::unset_zm_quest_icon(11);
    level scripts\cp\utility::unset_zm_quest_icon(12);
    setomnvarbit("zm_completed_quest_marks", 3, 0);

    linked_repair_structs = scripts\engine\utility::getstructarray(
        repair_structs[0].script_noteworthy, "script_noteworthy");
    foreach (repair_struct in linked_repair_structs)
    {
        scripts\cp\cp_interaction::remove_from_current_interaction_list(
            repair_struct);
    }

    // Quest mark 3 drives Rave's PaP inventory photo. Survival begins with
    // PaP repaired, so publishing that quest reward leaves a pending photo
    // which consumes the player's first unrelated interaction.
    level.projector_struct setmodel("cp_rave_projector_with_reels");
    level thread scripts\cp\maps\cp_rave\cp_rave_boat::play_pap_vo(
        level.players[0]);
    level thread scripts\cp\maps\cp_rave\cp_rave_boat::activate_pap(
        repair_structs[0]);

    wait(1.2);
    portal = scripts\engine\utility::getstruct(
        "porta_effect_location", "targetname");
    portal_origin = "undefined";
    if (isdefined(portal))
        portal_origin = portal.origin;

    survival_log("PaP auto-repaired pieces=" + pieces_before + "->" +
        level.pap_pieces_found + " fixed=" +
        scripts\engine\utility::flag("pap_fixed") +
        " portalOrigin=" + portal_origin +
        " activationPath=stock-cp_rave-activate-pap " +
        "questMarkPhoto=cleared papQuestPickupsRetired=" +
        retired_pap_pickups + " questIcons=11,12-cleared " +
        "unsafeInteractionRefresh=skipped");
}

enable_survival_double_pap()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("pap_fixed") ||
        !scripts\engine\utility::flag("pap_fixed") ||
        !scripts\engine\utility::flag_exist("fuses_inserted") ||
        !isdefined(level.pap_max) ||
        !isdefined(level.player_pap_machines) ||
        !level.player_pap_machines.size)
    {
        scripts\engine\utility::waitframe();
    }

    previous_pap_max = level.pap_max;
    placed_fuses_before = scripts\engine\utility::is_true(
        level.placed_alien_fuses);

    // Arcade Attack raises pap_max and installs the fuses immediately. Rave
    // renders a private PaP clone for each player, so also use Rave's stock
    // model-upgrade path and apply the same part-state sequence to every clone.
    scripts\engine\utility::flag_set("fuses_inserted");
    level.placed_alien_fuses = 1;
    level.pap_max = 3;
    scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        upgrade_machine_for_all_players();
    scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        update_level_pap_machines("door", "close");
    wait(0.5);
    scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        update_level_pap_machines("machine", "upgraded");
    wait(0.25);
    scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        update_level_pap_machines("reels", "neutral");
    wait(0.25);
    scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        update_level_pap_machines("reels", "on");
    wait(0.25);
    scripts\cp\maps\cp_rave\cp_rave_weapon_upgrade::
        update_level_pap_machines("door", "open_idle");

    pap_machine = level.player_pap_machines[0];
    survival_log("double PaP enabled papMax=" + previous_pap_max + "->" +
        level.pap_max + " fusesInserted=" +
        scripts\engine\utility::flag("fuses_inserted") +
        " placedAlienFuses=" + placed_fuses_before + "->" +
        level.placed_alien_fuses + " machineCount=" +
        level.player_pap_machines.size + " model=" + pap_machine.model +
        " states=machine=" +
        (pap_machine getscriptablepartstate("machine")) + " reels=" +
        (pap_machine getscriptablepartstate("reels")) + " door=" +
        (pap_machine getscriptablepartstate("door")) +
        " activationPath=arcade-pap-max-plus-rave-player-clones");
}

setup_survival_perk_purchase_wall()
{
    level endon("game_ended");

    while (!scripts\engine\utility::flag_exist("init_interaction_done"))
        scripts\engine\utility::waitframe();
    scripts\engine\utility::flag_wait("init_interaction_done");

    // crosshaircoords measured this wall and its outward normal. The Boss
    // Battle board treats -forward as its front, so yaw 102.004 faces the
    // measured 282.004-degree surface normal.
    wall_surface = (-6093.34, 4569.24, 179.093);
    wall_normal = (0.207983, -0.978132, 0);
    board_origin = wall_surface + wall_normal * 4;

    board = spawn("script_model", board_origin);
    board setmodel("p7_cafe_wall_menu_01");
    board.angles = (0, 102.004, 0);
    board setnonstick(1);
    level.perk_purchase_board = board;
    level.iwz_survival_perk_board = board;

    board thread scripts\cp\zombies\direct_boss_fight::player_use_monitor(
        board);
    scripts\cp\zombies\direct_boss_fight::
        create_perk_purchase_candy_boxes();
    level thread scripts\cp\zombies\direct_boss_fight::
        create_perk_purchase_interaction();
    level thread log_survival_perk_wall_ready();

    survival_log("perk wall created source=spaceland-boss-battle " +
        "measuredSurface=" + wall_surface + " wallNormal=" + wall_normal +
        " boardOrigin=" + board_origin + " boardAngles=" + board.angles +
        " candyBoxes=" + level.perk_purchase_structs.size +
        " wallClearance=4 interactionDelay=5");
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
    survival_log("perk wall interaction ready origin=" +
        interaction.origin + " enabled=" + interaction.enabled +
        " poweredOn=" + interaction.powered_on +
        " searchDistance=" + interaction.custom_search_dist +
        " boardOrigin=" + level.iwz_survival_perk_board.origin +
        " perks=10 purchasePath=survival-presentation " +
        "audio=stock-machine-jingle-vo-and-candy-foley " +
        "animation=stock-perk-candy-gesture");
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
