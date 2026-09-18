main()
{
    // Capture the mode once: lobby selection can change after the match.
    if (!getdvarint("iwz_survival_mode", 0))
        return;

    replacefunc(scripts\cp\cp_persistence::updateleaderboardstats, ::update_leaderboard_stats);
    replacefunc(scripts\cp\cp_persistence::update_highest_wave_lb, ::update_highest_wave);
    println("[IWZ][SurvivalFilms] installed separate per-player Film records map=", getdvar("mapname"));
}

update_leaderboard_stats(player, stat, value, map, player_count, increment)
{
    if (scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight())
        return;

    // Retail uses the explicit increment (default 1), not the value argument.
    if (!isdefined(increment))
        increment = 1;

    player update_record(map, stat, increment, false);
}

update_highest_wave(player, value, stat, map, player_count)
{
    if (!scripts\cp\zombies\direct_boss_fight::should_directly_go_to_boss_fight())
        player update_record(map, stat, value, true);
}

update_record(map, stat, value, highest)
{
    fields = ["Highest_Wave", "Kills", "Rounds", "Headshots", "Downs", "Revives"];
    if (!scripts\engine\utility::array_contains(fields, stat))
        return;

    if (!isdefined(self.iwz_survival_film_stats))
    {
        self.iwz_survival_film_stats = [];
        foreach (field in fields)
            self.iwz_survival_film_stats[field] = 0;

        self.iwz_survival_film_session = iwzfilmrecordsession();
        println("[IWZ][SurvivalFilms] tracking player=", self getentitynumber(), " map=", map);
    }

    if (highest)
        self.iwz_survival_film_stats[stat] = max(self.iwz_survival_film_stats[stat], int(value));
    else
        self.iwz_survival_film_stats[stat] += max(0, int(value));

    // Send cumulative values so several awards in one client frame cannot lose
    // progress. Each client saves its own records, including connected guests.
    snapshot = self.iwz_survival_film_session + " " + map;
    foreach (field in fields)
        snapshot += " " + self.iwz_survival_film_stats[field];
    self setclientdvar("iwz_survival_film_snapshot", snapshot);
}
