post_load()
{
    if (getdvar("ui_mapname") != "cp_disco")
        return;

    level thread install_shaolin_pap_entrance_prompts();
}

install_shaolin_pap_entrance_prompts()
{
    level endon("game_ended");

    scripts\engine\utility::flag_wait("interactions_initialized");

	// Keep Shaolin's stock key capitalized for the two PaP entrances. Standard
	// doors use a dedicated resident key so sethintstringparams receives the
	// localized-string type it requires without depending on another map's asset.
	level.enter_area_hint = &"IWZ_CP_DISCO_STANDARD_ENTER_THIS_AREA";
    level.interaction_hintstrings["enter_stall_allowed"] = &"CP_DISCO_INTERACTIONS_ENTER_THIS_AREA";
    level.interaction_hintstrings["enter_peepshow_allowed"] = &"CP_DISCO_INTERACTIONS_ENTER_THIS_AREA";

	custom_scripts\cp\gsc_diagnostics::emit(
		"ShaolinPrompts",
		"installed resident prompt routing PaPEntries=2 PaPKey=CP_DISCO_INTERACTIONS_ENTER_THIS_AREA standardDoorKey=IWZ_CP_DISCO_STANDARD_ENTER_THIS_AREA");
}
