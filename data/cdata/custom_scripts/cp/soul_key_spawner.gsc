post_load()
{
    key_index = get_film_soul_key_index();
    if (!isdefined(key_index))
        return;

    level thread listen_for_soul_key_spawn_requests();
    soul_key_log("spawnSoulKey listener installed map=" + level.script +
        " film='" + get_film_name(key_index) + "' key=" + key_index);
}

soul_key_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("SoulKey", message);
}

listen_for_soul_key_spawn_requests()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("iwz_spawn_soul_key", player, requested_key_index,
            model_name, vertical_lift);
        spawn_film_soul_key(player, requested_key_index, model_name,
            vertical_lift);
    }
}

spawn_film_soul_key(player, requested_key_index, model_name, vertical_lift)
{
    if (!isdefined(player) || !isplayer(player))
    {
        soul_key_log("spawnSoulKey rejected reason=invalid player");
        return;
    }

    film_key_index = get_film_soul_key_index();
    if (!isdefined(film_key_index) || requested_key_index != film_key_index)
    {
        soul_key_log("spawnSoulKey rejected player=" +
            player getentitynumber() + " requestedKey=" +
            requested_key_index + " expectedKey=" + film_key_index +
            " reason=film mismatch");
        player iprintlnbold("Unable to identify this film's Soul Key");
        return;
    }

    if (!isdefined(model_name) || model_name == "")
    {
        soul_key_log("spawnSoulKey rejected player=" +
            player getentitynumber() + " key=" + film_key_index +
            " reason=model unavailable");
        player iprintlnbold("Soul Key model is unavailable");
        return;
    }

    if (!isdefined(vertical_lift) || vertical_lift < 0)
    {
        soul_key_log("spawnSoulKey rejected player=" +
            player getentitynumber() + " key=" + film_key_index +
            " model=" + model_name + " reason=invalid vertical lift");
        player iprintlnbold("Soul Key placement data is unavailable");
        return;
    }

    if (isdefined(level.iwz_spawned_soul_key))
    {
        soul_key_log("spawnSoulKey rejected player=" +
            player getentitynumber() + " key=" + film_key_index +
            " existingEnt=" +
            level.iwz_spawned_soul_key getentitynumber() +
            " reason=pickup already active");
        player iprintlnbold("A Soul Key pickup is already active");
        return;
    }

    player_angles = player getplayerangles();
    forward = anglestoforward((0, player_angles[1], 0));
    ground_origin = player.origin + forward * 64 + (0, 0, 24);
    ground_origin = scripts\engine\utility::drop_to_ground(
        ground_origin, 48, -160);
    spawn_origin = ground_origin + (0, 0, vertical_lift);

    soul_key = spawn("script_model", spawn_origin);
    soul_key.angles = (0, player_angles[1], 0);
    soul_key setmodel(model_name);
    soul_key.iwz_soul_key_index = film_key_index;
    soul_key.iwz_soul_key_model = model_name;
    level.iwz_spawned_soul_key = soul_key;

    glow = undefined;
    if (model_name != "tag_origin_soul_key" &&
        isdefined(level._effect) &&
        isdefined(level._effect["soul_key_glow"]))
    {
        glow = spawnfx(level._effect["soul_key_glow"], soul_key.origin);
        triggerfx(glow);
    }

    soul_key thread rotate_soul_key();
    soul_key thread monitor_soul_key_pickup(glow);
    soul_key_log("spawnSoulKey completed player=" +
        player getentitynumber() + " film='" +
        get_film_name(film_key_index) + "' key=" + film_key_index +
        " model=" + model_name + " ent=" +
        soul_key getentitynumber() + " groundOrigin=" + ground_origin +
        " spawnOrigin=" + spawn_origin + " verticalLift=" + vertical_lift +
        " glow=" + isdefined(glow));
    player iprintlnbold("Spawned " + get_film_name(film_key_index) +
        " Soul Key");
}

rotate_soul_key()
{
    self endon("death");
    base_angles = self.angles;

    for (;;)
    {
        self rotateto(base_angles + (randomintrange(-40, 40),
            randomintrange(-40, 90), randomintrange(-40, 90)), 3);
        wait(3);
    }
}

monitor_soul_key_pickup(glow)
{
    self endon("death");
    self makeusable();
    self sethintstring(get_soul_key_hint());

    for (;;)
    {
        self waittill("trigger", player);
        if (!isdefined(player) || !isplayer(player))
            continue;

        player playlocalsound("part_pickup");
        scripts\cp\zombies\directors_cut::give_dc_player_extra_xp_for_carrying_newb();
        award_film_soul_key(self.iwz_soul_key_index);
        break;
    }

    key_index = self.iwz_soul_key_index;
    model_name = self.iwz_soul_key_model;
    pickup_origin = self.origin;
    if (model_name == "tag_origin_soul_key")
        self setscriptablepartstate("actions", "pickup");

    level.iwz_spawned_soul_key = undefined;
    if (isdefined(glow))
        glow delete();

    self delete();
    soul_key_log("Soul Key picked up player=" +
        player getentitynumber() + " film='" + get_film_name(key_index) +
        "' key=" + key_index + " model=" + model_name +
        " origin=" + pickup_origin + " recipients=" + level.players.size);
    player iprintlnbold(get_film_name(key_index) + " Soul Key collected");
}

award_film_soul_key(key_index)
{
    soul_key_ref = "soul_key_" + key_index;
    foreach (player in level.players)
    {
        player setplayerdata("cp", "haveSoulKeys", "any_soul_key", 1);
        player setplayerdata("cp", "haveSoulKeys", soul_key_ref, 1);
        update_film_soul_key_achievement(player, key_index);
    }
}

update_film_soul_key_achievement(player, key_index)
{
    switch (key_index)
    {
        case 1:
            player scripts\cp\zombies\achievement::update_achievement(
                "SOUL_KEY", 1);
            break;

        case 2:
            player scripts\cp\zombies\achievement::update_achievement(
                "LOCKSMITH", 1);
            break;

        case 3:
            player scripts\cp\zombies\achievement::update_achievement(
                "PEST_CONTROL", 1);
            break;

        case 4:
            player scripts\cp\zombies\achievement::update_achievement(
                "SOUL_LESS", 1);
            break;

        default:
            break;
    }
}

get_film_soul_key_index()
{
    if (!isdefined(level.script))
        return undefined;

    switch (level.script)
    {
        case "cp_zmb":
            return 1;

        case "cp_rave":
            return 2;

        case "cp_disco":
            return 3;

        case "cp_town":
            return 4;

        case "cp_final":
            return 5;

        default:
            return undefined;
    }
}

get_film_name(key_index)
{
    switch (key_index)
    {
        case 1:
            return "Zombies in Spaceland";

        case 2:
            return "Rave in the Redwoods";

        case 3:
            return "Shaolin Shuffle";

        case 4:
            return "Attack of the Radioactive Thing";

        case 5:
            return "The Beast from Beyond";

        default:
            return "Unknown Film";
    }
}

get_soul_key_hint()
{
    switch (level.script)
    {
        case "cp_rave":
            return &"CP_RAVE_PICK_UP_SOUL_KEY";

        case "cp_disco":
            return &"CP_DISCO_INTERACTIONS_PICKUP_SOUL_KEY";

        default:
            return &"CP_ZMB_UFO_PICK_UP_SOUL_KEY";
    }
}
