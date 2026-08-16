emit(channel, message)
{
    if (!getdvarint("iwz_gsc_diagnostics", 1))
        return;

    level notify("iwz_gsc_log", "[IWZ][" + channel + "] " + gettime() + " " + message);
}
