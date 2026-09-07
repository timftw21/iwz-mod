main()
{
	map_ref = getdvar("mapname");
	setdvar("iwz_scoreboard_match_map", map_ref);
	// Capture the played mode too; frontend film selections can change it
	// before the player reopens the after-action scoreboard.
	survival = getdvarint("iwz_survival_mode", 0);
	setdvar("iwz_scoreboard_match_survival", survival);
	println("[IWZ][ScoreboardMatch] captured gameplay map ref=", map_ref,
		" survival=", survival);
}
