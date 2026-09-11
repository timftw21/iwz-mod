// IWZ-LOAD: dvar=iwz_noir_placement
// Small solo survival section, using the authored layout and MP lifecycle.

init()
{
    if (!getdvarint("iwz_noir_foundation", 0))
        return;
    foreach (model in ["zmb_perk_up_n_atoms", "zmb_perk_up_n_atoms_on", "zmb_magic_wheel",
        "zmb_magic_wheel_on", "zmb_magic_wheel_spinner", "icbm_electricpanel_switch_02", "zmb_core_wood_board"])
        precachemodel(model);
    foreach (weapon in wheel_weapons())
    {
        precacheitem(weapon);
        precachemodel(getweaponmodel(weapon));
    }
}

log_event(message)
{
    level notify("iwz_gsc_log", "[IWZ][NoirSection] " + gettime() + " " + message);
}

setup()
{
    level.iwz_noir_power = 0;
    level.iwz_noir_zombie_spawns = [];
    level.iwz_noir_barricades = [];
    foreach (item in level.iwz_noir_markers)
    {
        switch (item.preset)
        {
            case "player_spawn":
                if (!isdefined(level.iwz_noir_player_start))
                    level.iwz_noir_player_start = item;
                break;
            case "zombie_spawn":
                point = getclosestpointonnavmesh(item.origin);
                if (isdefined(point) && distance(point, item.origin) <= 48)
                {
                    item.spawn_origin = point + (0, 0, 8);
                    level.iwz_noir_zombie_spawns[level.iwz_noir_zombie_spawns.size] = item;
                    log_event("zombie marker=" + item.id + " navigation=" + point + " snap=" + distance(point, item.origin));
                }
                else
                    log_event("ERROR zombie marker=" + item.id + " has no ground navigation within 48 units");
                break;
            case "quick_revive":
                // Solo Quick Revive is available before power, as on the stock maps.
                item.prop = model_at(item.origin, item.yaw, "zmb_perk_up_n_atoms_on");
                break;
            case "power":
                item.prop = model_at(item.origin + (0, 0, 40), item.yaw, "icbm_electricpanel_switch_02");
                break;
            case "magic_wheel":
                item.prop = model_at(item.origin, item.yaw, "zmb_magic_wheel");
                item.spinner = model_at(item.origin + anglestoforward((0, item.yaw, 0)) * 14 + (0, 0, 68),
                    item.yaw + 90, "zmb_magic_wheel_spinner");
                item.spinner setscriptablepartstate("spinner", "off");
                item.state = "idle";
                break;
            case "barricade":
                custom_scripts\mp\maps\mp_prime\noir_barricades::setup(item);
                level.iwz_noir_barricades[level.iwz_noir_barricades.size] = item;
                break;
        }
    }
    level.iwz_noir_stock_spawnpoint = level.getspawnpoint;
    level.getspawnpoint = ::player_spawnpoint;
    level.iwz_noir_stock_laststand = level.callbackplayerlaststand;
    level.callbackplayerlaststand = ::player_laststand;
    level.iwz_noir_stock_damage = level.callbackplayerdamage;
    level.callbackplayerdamage = ::player_damage;
    level.iwz_noir_layout_ready = 1;
    log_event("ready zombieSpawns=" + level.iwz_noir_zombie_spawns.size + " power=off revive=500 wheel=950");
}

model_at(origin, yaw, model)
{
    prop = spawn("script_model", origin);
    prop.angles = (0, yaw, 0);
    prop setmodel(model);
    prop notsolid();
    return prop;
}

player_spawnpoint()
{
    if (isdefined(level.iwz_noir_player_start))
    {
        item = level.iwz_noir_player_start;
        // Trace the placed floor, then check the actual player capsule. Stock
        // getspawnorigin/finalizespawnpointchoice still handle the chosen entity.
        ground = bullettrace(item.origin + (0, 0, 32), item.origin - (0, 0, 32), 0, undefined);
        point = ground["position"] + (0, 0, 8);
        if (ground["fraction"] < 1 && capsuletracepassed(point, 16, 64, self, 1, 0, 0, point + (0, 0, 1)) &&
            !positionwouldtelefrag(point))
        {
            item.anchor.origin = point;
            log_event("player spawn=" + self getentitynumber() + " marker=" + item.id + " origin=" + point + " yaw=" + item.yaw);
            return item.anchor;
        }
        log_event("player start obstructed marker=" + item.id + "; using stock safe spawn selection");
    }
    return self [[level.iwz_noir_stock_spawnpoint]]();
}

attach_player()
{
    if (!isdefined(self.iwz_noir_points)) self.iwz_noir_points = 500;
    self.iwz_noir_down = 0;
    self.iwz_noir_revive = 0;
    self.iwz_noir_revive_buys = 0;
    self.iwz_noir_life = 0;
    self thread player_lives();
    self thread status_hud();
}

player_lives()
{
    self endon("disconnect");
    level endon("game_ended");
    for (;;)
    {
        self waittill("spawned_player");
        self.iwz_noir_life++;
        self.iwz_noir_down = 0;
        self.iwz_noir_revive = 0;
        self unsetperk("specialty_pistoldeath", 1);
        self.iwz_noir_safe_until = 0;
        log_event("player life=" + self.iwz_noir_life + " origin=" + self.origin);
    }
}

status_hud()
{
    self endon("disconnect");
    level endon("game_ended");
    hud = newclienthudelem(self);
    hud.horzalign = "left";
    hud.vertalign = "top";
    hud.x = 16;
    hud.y = 170;
    hud.fontscale = 1.2;
    hud.archived = 0;
    hud.hidewheninmenu = 1;
    for (;;)
    {
        text = "Scene " + level.wave_num + " | Points " + self.iwz_noir_points;
        if (level.iwz_noir_power)
            text += " | Power ON";
        else
            text += " | Power OFF";
        if (self.iwz_noir_down)
            text += " | Reviving...";
        else if (self.iwz_noir_revive)
            text += " | Quick Revive";
        hud settext(text);
        wait 0.25;
    }
}

hint(item)
{
    switch (item.preset)
    {
        case "wall_buy": return "EMC 500 / ammo 250 | Press Use";
        case "power":
            if (level.iwz_noir_power) return "Power is ON";
            return "Turn on power | Press Use";
        case "quick_revive":
            if (self.iwz_noir_revive) return "Quick Revive ready";
            if (self.iwz_noir_revive_buys >= 3) return "Quick Revive sold out (3 purchases)";
            return "Quick Revive 500 | Press Use";
        case "magic_wheel":
            if (!level.iwz_noir_power) return "Magic Wheel | Turn on power";
            if (item.state == "spinning") return "Magic Wheel spinning...";
            if (item.state == "ready") return "Magic Wheel: " + weapon_label(item.weapon) + " | Buyer: press Use to take";
            return "Magic Wheel 950 | Press Use";
        case "barricade": return "Barricade " + item.boards.size + "/6 | Hold Use to repair";
    }
    return item.id;
}

use_item(item)
{
    if (!self custom_scripts\mp\maps\mp_prime\noir_placement::can_use(item))
        return 0;
    switch (item.preset)
    {
        case "wall_buy": return self custom_scripts\mp\maps\mp_prime\noir_placement::purchase(item);
        case "barricade": return self custom_scripts\mp\maps\mp_prime\noir_barricades::repair(item);
        case "power":
            if (level.iwz_noir_power) return 0;
            level.iwz_noir_power = 1;
            item.prop rotatepitch(-60, 0.5);
            foreach (marker in level.iwz_noir_markers)
            {
                if (marker.preset != "magic_wheel") continue;
                marker.prop setmodel("zmb_magic_wheel_on");
                marker.spinner setscriptablepartstate("spinner", "idle");
            }
            log_event("power on marker=" + item.id + " player=" + self getentitynumber());
            iprintlnbold("Power is ON");
            return 1;
        case "quick_revive": return buy_revive(item);
        case "magic_wheel": return use_wheel(item);
    }
    return 0;
}

can_afford(price)
{
    if (self.iwz_noir_points >= price) return 1;
    self iprintlnbold("Not enough points");
    return 0;
}

buy_revive(item)
{
    if (self.iwz_noir_revive || self.iwz_noir_revive_buys >= 3 || !can_afford(500)) return 0;
    self setperk("specialty_pistoldeath", 1);
    self.iwz_noir_revive = 1;
    self.iwz_noir_revive_buys++;
    self.iwz_noir_points -= 500;
    log_event("revive bought marker=" + item.id + " purchases=" + self.iwz_noir_revive_buys + " points=" + self.iwz_noir_points);
    self iprintlnbold("Quick Revive ready");
    return 1;
}

player_damage(inflictor, attacker, damage, flags, mod, weapon, point, direction, hitloc, time_offset, model, part)
{
    if (self.iwz_noir_down || (isdefined(self.iwz_noir_safe_until) && gettime() < self.iwz_noir_safe_until))
        return;
    self [[level.iwz_noir_stock_damage]](inflictor, attacker, damage, flags, mod, weapon, point, direction, hitloc, time_offset, model, part);
}

player_laststand(inflictor, attacker, damage, mod, weapon, direction, hitloc, time_offset, death_anim)
{
    if (!self.iwz_noir_revive || mod == "MOD_SUICIDE" || mod == "MOD_TRIGGER_HURT")
    {
        self [[level.iwz_noir_stock_laststand]](inflictor, attacker, damage, mod, weapon, direction, hitloc, time_offset, death_anim);
        return;
    }
    self endon("disconnect");
    self endon("death");
    self endon("spawned_player");
    level endon("game_ended");
    self.iwz_noir_revive = 0;
    self.iwz_noir_down = 1;
    self.inlaststand = 1;
    self.laststand = 1;
    self.health = 1;
    self unsetperk("specialty_pistoldeath", 1);
    self disableweapons();
    log_event("native last stand player=" + self getentitynumber() + " origin=" + self.origin + " mod=" + mod);
    wait 3;
    self scripts\mp\playerlogic::laststandrespawnplayer();
    self.inlaststand = 0;
    self.laststand = undefined;
    self enableweapons();
    self.iwz_noir_down = 0;
    self.iwz_noir_safe_until = gettime() + 3000;
    self allowdoublejump(0);
    self allowwallrun(0);
    self allowdodge(0);
    log_event("revived in place player=" + self getentitynumber() + " health=" + self.health + " origin=" + self.origin);
    self iprintlnbold("Revived | 3 seconds protection");
}

wheel_weapons()
{
    // Exact weapon assets from mp/statstable.csv (Rack-9's base is *_mpr).
    return ["iw7_m4_mp", "iw7_erad_mp", "iw7_spas_mpr", "iw7_mauler_mp"];
}

weapon_label(weapon)
{
    switch (weapon)
    {
        case "iw7_m4_mp": return "NV4";
        case "iw7_erad_mp": return "ERAD";
        case "iw7_spas_mpr": return "Rack-9";
        case "iw7_mauler_mp": return "Mauler";
    }
    return weapon;
}

use_wheel(item)
{
    if (!level.iwz_noir_power) return 0;
    if (item.state == "ready")
    {
        if (!isdefined(item.owner) || item.owner != self || item.life != self.iwz_noir_life) return 0;
        if (!give_wheel_weapon(item.weapon)) return 0;
        item.state = "claimed";
        log_event("wheel claimed marker=" + item.id + " weapon=" + item.weapon + " points=" + self.iwz_noir_points);
        return 1;
    }
    if (item.state != "idle" || !can_afford(950)) return 0;
    item.owner = self;
    item.life = self.iwz_noir_life;
    item.state = "spinning";
    self.iwz_noir_points -= 950;
    log_event("wheel purchased marker=" + item.id + " points=" + self.iwz_noir_points);
    level thread spin_wheel(item);
    return 1;
}

spin_wheel(item)
{
    level endon("game_ended");
    choices = [];
    foreach (weapon in wheel_weapons())
        if (!item.owner hasweapon(weapon)) choices[choices.size] = weapon;
    if (!choices.size) choices = wheel_weapons();
    item.weapon = choices[randomint(choices.size)];
    item.spinner setscriptablepartstate("spinner", "spinning");
    wait 3;
    item.spinner setscriptablepartstate("spinner", "idle");
    item.state = "ready";
    log_event("wheel ready marker=" + item.id + " weapon=" + item.weapon);
    // The owner's hint shows the result, and the world gun marks the pickup.
    item.prize = model_at(item.origin + (0, 0, 80), item.yaw, getweaponmodel(item.weapon));
    deadline = gettime() + 15000;
    while (item.state == "ready" && gettime() < deadline && isdefined(item.owner) &&
        isalive(item.owner) && item.owner.iwz_noir_life == item.life)
        wait 0.1;
    item.prize delete();
    item.prize = undefined;
    if (item.state != "claimed") log_event("wheel expired marker=" + item.id);
    item.owner = undefined;
    item.weapon = undefined;
    item.state = "idle";
}

give_wheel_weapon(weapon)
{
    replacement = undefined;
    count = 0;
    foreach (primary in self getweaponslistprimaries())
    {
        if (scripts\mp\utility::iskillstreakweapon(primary) || issubstr(primary, "iw7_atomizer_mp")) continue;
        count++;
        if (primary == self getcurrentweapon()) replacement = primary;
    }
    if (!self hasweapon(weapon) && count >= 2 && !isdefined(replacement))
    {
        self iprintlnbold("Switch to the gun you want to replace");
        return 0;
    }
    if (!self hasweapon(weapon))
    {
        self giveweapon(weapon);
        if (!self hasweapon(weapon))
        {
            log_event("ERROR wheel weapon grant=" + weapon);
            return 0;
        }
        if (count >= 2 && isdefined(replacement)) self takeweapon(replacement);
    }
    self givemaxammo(weapon);
    self switchtoweapon(weapon);
    return 1;
}
