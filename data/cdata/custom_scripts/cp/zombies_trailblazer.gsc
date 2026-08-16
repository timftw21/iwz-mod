main()
{
    if (iwz_patch_trailblazer_fx())
        trailblazer_log("installed finite first-person flame timeline with authored fade-out");
    else
        trailblazer_log("first-person particle definition unavailable; stock effect preserved");
}

trailblazer_log(message)
{
    custom_scripts\cp\gsc_diagnostics::emit("Trailblazer", message);
}
