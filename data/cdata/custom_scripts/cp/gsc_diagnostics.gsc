emit(channel, message)
{
    if (!getdvarint("iwz_gsc_diagnostics", 1))
        return;

    level notify("iwz_gsc_log", "[IWZ][" + channel + "] " + gettime() + " " + message);
}

print_crosshair_coordinates()
{
    trace_start = self geteye();
    view_angles = self getplayerangles();
    trace_end = trace_start + anglestoforward(view_angles) * 100000;
    trace = bullettrace(trace_start, trace_end, 0, self);

    if (!isdefined(trace) || !isdefined(trace["fraction"]) || trace["fraction"] >= 1)
    {
        level notify("iwz_gsc_log",
            "[IWZ][CrosshairCoords] " + gettime() +
            " hit=0 viewOrigin=" + trace_start + " viewAngles=" + view_angles);
        return;
    }

    hit_position = trace["position"];
    hit_normal = trace["normal"];
    surface_type = "unknown";
    if (isdefined(trace["surfacetype"]))
        surface_type = trace["surfacetype"];

    level notify("iwz_gsc_log",
        "[IWZ][CrosshairCoords] " + gettime() +
        " hit=1 position=" + hit_position +
        " normal=" + hit_normal +
        " normalAngles=" + vectortoangles(hit_normal) +
        " distance=" + distance(trace_start, hit_position) +
        " surface=" + surface_type +
        " viewOrigin=" + trace_start + " viewAngles=" + view_angles);
}
