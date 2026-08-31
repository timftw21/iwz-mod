main()
{
	map_ref = getdvar("mapname");
	setdvar("iwz_scoreboard_match_map", map_ref);
	println("[IWZ][ScoreboardMatch] captured gameplay map ref=", map_ref);
}
