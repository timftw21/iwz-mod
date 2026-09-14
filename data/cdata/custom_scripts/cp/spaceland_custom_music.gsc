main()
{
    if (getdvar("ui_mapname") != "cp_zmb")
        return;

    select_song = getfunction("scripts/cp/zombies/zombie_jukebox", "get_song_struct");
    if (!isdefined(select_song))
    {
        println("[IWZ][CustomMusicDJ] stock song selector unavailable");
        return;
    }

    replacefunc(select_song, ::get_song_struct_with_custom);
    println("[IWZ][CustomMusicDJ] installed Spaceland song selection hook");
}

post_load()
{
    if (!isdefined(level.script) || level.script != "cp_zmb")
        return;

    count = iwz_dj_rescan();
    println("[IWZ][CustomMusicDJ] local playlist tracks=", count,
        " customOnly=", getdvarint("iwz_dj_custom_only", 0));
    level thread monitor_playlist_requests();
}

stop_on_event(event_name, generation)
{
    level endon("iwz_dj_song_finished");
    level waittill(event_name);
    if (level.iwz_dj_generation == generation)
    {
        iwz_dj_stop();
        println("[IWZ][CustomMusicDJ] playback boundary event=", event_name);
    }
}

monitor_playlist_requests()
{
    level endon("game_ended");
    previous_request = getdvarint("iwz_dj_request", 0);
    for (;;)
    {
        wait(0.1);
        request = getdvarint("iwz_dj_request", 0);
        if (request == previous_request)
            continue;

        previous_request = request;
        // Before the first DJ cue, keep the stock intro/jingle timing intact.
        if (isdefined(level.iwz_dj_started))
            level notify("skip_song");
        println("[IWZ][CustomMusicDJ] playlist request applied customOnly=",
            getdvarint("iwz_dj_custom_only", 0));
    }
}

get_song_struct_with_custom(songs, first_song, jukebox)
{
    // The stock jukebox_start thread owns hidden-song/forced-song endons.
    // Stay inside its selection boundary so those quests retain priority.
    level.iwz_dj_started = 1;
    if (!isdefined(first_song))
        first_song = 0;

    for (;;)
    {
        scripts\engine\utility::flag_waitopen("jukebox_paused");
        count = iwz_dj_count();
        custom_only = getdvarint("iwz_dj_custom_only", 0);
        if (count > 0 && (custom_only || randomint(songs.size + count) >= songs.size))
        {
            // Cancel any listeners left by an interrupted stock jukebox thread.
            level notify("iwz_dj_song_finished");
            if (!isdefined(level.iwz_dj_generation))
                level.iwz_dj_generation = 0;
            level.iwz_dj_generation++;
            name = iwz_dj_play();
            if (name != "")
            {
                // The stock loop installs its emitter cleanup only after this
                // selector returns. A custom first song can stay here longer.
                if (!isdefined(jukebox.iwz_dj_cleanup_installed))
                {
                    jukebox.iwz_dj_cleanup_installed = 1;
                    jukebox thread scripts\cp\zombies\zombie_jukebox::earlyendon(jukebox);
                }
                generation = level.iwz_dj_generation;
                level thread stop_on_event("skip_song", generation);
                level thread stop_on_event("add_hidden_song_to_playlist", generation);
                level thread stop_on_event("add_hidden_song_2_to_playlist", generation);
                level thread stop_on_event("force_new_song", generation);
                level thread stop_on_event("game_ended", generation);
                level.current_dj_song = "iwz_custom:" + name;
                level.song_last_played = -1;
                level.songs_played++;
                // The local SongSplash extension supplies the custom title
                // and artist when native PA playback starts; there is no CSV row.
                setomnvar("song_playing", -1);
                println("[IWZ][CustomMusicDJ] playing custom track=", name);
                while (iwz_dj_playing())
                    wait(0.05);
                iwz_dj_stop();
                level notify("iwz_dj_song_finished");
                first_song = 0;
                wait(1);
                continue;
            }
        }

        request = getdvarint("iwz_dj_request", 0);
        song = get_stock_song_struct(songs, first_song);
        // A test request during the DJ's spoken introduction must not commit
        // a stock song for several minutes before checking the new mode.
        if (request == getdvarint("iwz_dj_request", 0))
            return song;
    }
}

get_stock_song_struct(songs, first_song)
{
    // Stock Spaceland get_song_struct behavior, including perk cooldowns and
    // its DJ dialogue. Other maps keep their original selector unchanged.
    foreach (index, song in songs)
    {
        intro = song.djintro;
        if (song.genre == "perk")
        {
            if (first_song)
                continue;
            if (gettime() < level.next_perk_jingle_time && index + 1 < songs.size)
                continue;

            if (isdefined(intro) && intro != "")
            {
                level thread scripts\cp\cp_vo::try_to_play_vo(intro, "zmb_dj_vo");
                wait(lookupsoundlength(intro) / 1000);
            }
            level.next_perk_jingle_time = gettime() + 180000;
            return song;
        }

        if (isdefined(intro) && intro != "")
        {
            level thread scripts\cp\cp_vo::try_to_play_vo(intro, "zmb_dj_vo", "high", 20, 1, 0, 1);
            wait(lookupsoundlength(intro) / 1000);
        }
        return song;
    }
}
