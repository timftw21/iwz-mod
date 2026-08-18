main()
{
    setdvar("iwz_custom_music_frontend_monitor_ready", 0);
    setdvar("iwz_custom_music_lobby_session_active", 0);

    // cp_frontend::play_lobby_music owns the persistent stock music state. Keep
    // its normal behavior until the external player explicitly claims ownership.
    stock_play_lobby_music = getfunction("scripts/cp/maps/cp_frontend/cp_frontend", "play_lobby_music");
    level.iwz_custom_music_get_zombies_music = getfunction("scripts/cp/maps/cp_frontend/cp_frontend", "get_zombies_music");
    level.iwz_custom_music_run_shuffle = getfunction("scripts/cp/maps/cp_frontend/cp_frontend", "run_shuffle_music");
    if (!isdefined(stock_play_lobby_music) || !isdefined(level.iwz_custom_music_get_zombies_music) ||
        !isdefined(level.iwz_custom_music_run_shuffle))
    {
        println("[IWZ][CustomMusicGSC] failed to resolve stock lobby music functions");
        return;
    }

    replacefunc(stock_play_lobby_music, ::play_lobby_music_stub);
    println("[IWZ][CustomMusicGSC] installed stock lobby music ownership patch");
}

post_load()
{
    setdvar("iwz_custom_music_frontend_monitor_ready", 1);
    level thread monitor_frontend_section();
    println("[IWZ][CustomMusicGSC] frontend section monitor started");
}

play_lobby_music_stub()
{
    level endon("game_ended");
    self endon("disconnect");

    for (;;)
    {
        self waittill("luinotifyserver", channel, value);
        if (channel != "music_changed")
            continue;

        if (getdvarint("iwz_custom_music_active", 0))
        {
            level notify("shuffle_changed");
            level.shuffle_playing = 0;
            setmusicstate("");
            println("[IWZ][CustomMusicGSC] suppressed stock music state while custom player owns playback value=", value);
            continue;
        }

        song = [[level.iwz_custom_music_get_zombies_music]](value);
        if (song != "shuffle")
        {
            level notify("shuffle_changed");
            level.shuffle_playing = 0;
            setmusicstate(song);
            println("[IWZ][CustomMusicGSC] restored stock music state value=", value, " state=", song);
        }
        else
        {
            self thread [[level.iwz_custom_music_run_shuffle]]();
            println("[IWZ][CustomMusicGSC] started stock shuffle playback");
        }
    }
}

monitor_frontend_section()
{
    level endon("game_ended");
    previous_name = "";

    for (;;)
    {
        section = frontendscenegetactivesection();
        if (!isdefined(section) || !isdefined(section.name))
        {
            scripts\engine\utility::waitframe();
            continue;
        }

        // The frontend uses separate sections for film selection, Barracks,
        // Loadout, and other surfaces that still belong to the lobby session.
        // Latch on entry and clear only after returning to the Zombies main menu.
        lobby_session_active = getdvarint("iwz_custom_music_lobby_session_active", 0);
        if (section.name == "zm_lobby")
            lobby_session_active = 1;
        else if (section.name == "zm_main")
            lobby_session_active = 0;

        setdvar("iwz_custom_music_lobby_session_active", lobby_session_active);

        if (section.name != previous_name)
        {
            println("[IWZ][CustomMusicGSC] frontend section name=", section.name,
                " index=", section.index, " lobbySession=", lobby_session_active,
                " customActive=", getdvarint("iwz_custom_music_active", 0));
            previous_name = section.name;
        }

        scripts\engine\utility::waitframe();
    }
}
