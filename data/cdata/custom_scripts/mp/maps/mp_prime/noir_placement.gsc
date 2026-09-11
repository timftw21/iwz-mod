// IWZ-LOAD: dvar=iwz_noir_placement
// Surface anchors are exact game coordinates; the small white dot shows facing.

init()
{
    if (getdvarint("iwz_noir_foundation", 0))
        precacheshader("white");
}

post_load()
{
    if (getdvarint("iwz_noir_foundation", 0))
        level thread load_layout();
}

log_event(message)
{
    level notify("iwz_gsc_log", "[IWZ][MapLayout] " + gettime() + " " + message);
}

load_layout()
{
    level endon("game_ended");
    wait 1;
    expected = custom_scripts\mp\maps\mp_prime\noir_layout::checksum();
    if (getdvar("iwz_noir_world_checksum") != expected)
    {
        log_event("ERROR layout rejected: world checksum=" + getdvar("iwz_noir_world_checksum") + " expected=" + expected);
        return;
    }
    level.iwz_noir_markers = custom_scripts\mp\maps\mp_prime\noir_layout::markers();
    foreach (item in level.iwz_noir_markers)
    {
        item.anchor = spawn("script_origin", item.origin);
        item.anchor.angles = (0, item.yaw, 0);
        item.anchor.targetname = "iwz_layout_" + item.id;
        color = (1, 0.85, 0.42);
        if (item.preset == "quick_revive")
            color = (0.45, 0.85, 1);
        else if (item.preset == "wall_buy")
            color = (0.56, 0.94, 0.66);
        world_dot(item.origin, color, 8);
        facing = item.origin + anglestoforward((0, item.yaw, 0)) * 48 + (0, 0, 4);
        world_dot(facing, (1, 1, 1), 4);
        trace = bullettrace(item.origin + item.normal * 16, item.origin - item.normal * 16, 0, undefined);
        log_event("anchor id=" + item.id + " preset=" + item.preset + " origin=" + item.anchor.origin +
            " yaw=" + item.anchor.angles[1] + " coordinateError=" + distance(item.origin, item.anchor.origin) +
            " collisionFraction=" + trace["fraction"] + " collisionOffset=" + distance(trace["position"], item.origin));
    }
    custom_scripts\mp\maps\mp_prime\noir_section::setup();
    log_event("loaded markers=" + level.iwz_noir_markers.size + " checksum=" + expected + " south gameplay active");
    foreach (player in level.players)
        player attach_player();
    for (;;)
    {
        level waittill("connected", player);
        player attach_player();
    }
}

world_dot(origin, color, size)
{
    hud = newhudelem();
    hud.x = origin[0];
    hud.y = origin[1];
    hud.z = origin[2];
    hud.color = color;
    hud.alpha = 0.85;
    hud.archived = 0;
    hud.showinkillcam = 0;
    hud setshader("white", size, size);
    hud setwaypoint(0, 0, 0, 1);
}

attach_player()
{
    if (isdefined(self.iwz_noir_placement_attached))
        return;
    self.iwz_noir_placement_attached = 1;
    self custom_scripts\mp\maps\mp_prime\noir_section::attach_player();
    self thread interaction_loop();
}

interaction_loop()
{
    self endon("disconnect");
    level endon("game_ended");
    hint = newclienthudelem(self);
    hint.horzalign = "center";
    hint.vertalign = "middle";
    hint.alignx = "center";
    hint.x = 0;
    hint.y = 120;
    hint.fontscale = 1.3;
    hint.archived = 0;
    hint.hidewheninmenu = 1;
    hint.alpha = 0;
    was_pressed = 0;
    for (;;)
    {
        item = undefined;
        nearest = 160;
        if (isalive(self) && self.sessionstate == "playing" && !self.iwz_noir_down)
        {
            foreach (candidate in level.iwz_noir_markers)
            {
                separation = distance(self.origin, candidate.origin);
                if (separation < nearest && candidate.preset != "calibration" &&
                    candidate.preset != "player_spawn" && candidate.preset != "zombie_spawn")
                {
                    nearest = separation;
                    item = candidate;
                }
            }
        }
        pressed = self usebuttonpressed();
        hint.alpha = 0;
        if (isdefined(item))
        {
            hint.alpha = 1;
            label = self custom_scripts\mp\maps\mp_prime\noir_section::hint(item);
            if (pressed && (!was_pressed || item.preset == "barricade"))
                self custom_scripts\mp\maps\mp_prime\noir_section::use_item(item);
            hint settext(label);
        }
        was_pressed = pressed;
        wait 0.1;
    }
}

can_use(item)
{
    if (!isalive(self) || self.sessionstate != "playing" ||
        (isdefined(self.iwz_noir_down) && self.iwz_noir_down) ||
        distance(self.origin, item.origin) > 96 || !isdefined(self.iwz_noir_points))
        return 0;
    target = item.origin + (0, 0, 40);
    eye = self geteye();
    if (vectordot(anglestoforward(self getplayerangles()), vectornormalize(target - eye)) < 0.6)
        return 0;
    // Ignore the interactive prop itself; world walls still block use.
    trace = bullettrace(eye, target, 0, self);
    if (trace["fraction"] < 1 && distance(trace["position"], target) > 2)
    {
        hit_item = isdefined(trace["entity"]) && isdefined(item.prop) && trace["entity"] == item.prop;
        if (!hit_item) return 0;
    }
    return 1;
}

purchase(item)
{
    if (item.preset != "wall_buy" || !can_use(item))
        return 0;
    weapon = "iw7_emc_mp";
    owned = self hasweapon(weapon);
    price = 500;
    if (owned)
        price = 250;
    if (self.iwz_noir_points < price)
    {
        self iprintlnbold("Not enough points");
        return 0;
    }
    replacement = undefined;
    normal_weapons = [];
    foreach (primary in self getweaponslistprimaries())
        if (!scripts\mp\utility::iskillstreakweapon(primary) && !issubstr(primary, "iw7_atomizer_mp"))
            normal_weapons[normal_weapons.size] = primary;
    if (!owned && normal_weapons.size >= 2)
    {
        foreach (primary in normal_weapons)
            if (primary == self getcurrentweapon())
                replacement = primary;
        if (!isdefined(replacement))
        {
            self iprintlnbold("Switch to the gun you want to replace");
            return 0;
        }
    }
    if (owned)
    {
        before = self getweaponammoclip(weapon) + self getweaponammostock(weapon);
        self givemaxammo(weapon);
        if (self getweaponammoclip(weapon) + self getweaponammostock(weapon) <= before)
        {
            self iprintlnbold("Ammo is already full");
            return 0;
        }
    }
    else
    {
        self giveweapon(weapon);
        if (!self hasweapon(weapon))
        {
            log_event("ERROR weapon grant failed id=" + item.id + " player=" + self getentitynumber());
            return 0;
        }
        self givemaxammo(weapon);
        if (isdefined(replacement))
            self takeweapon(replacement);
        self switchtoweapon(weapon);
    }
    self.iwz_noir_points -= price;
    log_event("purchase id=" + item.id + " player=" + self getentitynumber() + " weapon=" + weapon +
        " price=" + price + " pointsAfter=" + self.iwz_noir_points + " ammoRefill=" + owned);
    self iprintlnbold("EMC purchased | Points " + self.iwz_noir_points);
    return 1;
}
