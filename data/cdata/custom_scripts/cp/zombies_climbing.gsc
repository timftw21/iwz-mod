main()
{
	level thread monitor_climbing_players();
	climbing_log("player monitor installed map=" + getdvar("ui_mapname"));
}

climbing_log(message)
{
	custom_scripts\cp\gsc_diagnostics::emit("Climbing", message);
}

monitor_climbing_players()
{
	level endon("game_ended");

	for (;;)
	{
		level waittill("connected", player);
		climbing_log("monitor attached player=" + player getentitynumber());
		player thread apply_climbing_changes();
	}
}

apply_climbing_changes()
{
	self endon("disconnect");
	level endon("game_ended");

	was_climbing = false;
	last_input_state = 0;

	for (;;)
	{
		is_climbing = self isonladder();

		if (is_climbing)
		{
			movement = self getnormalizedmovement();
			vertical_direction = 0;
			lateral_direction = 0;

			if (movement[0] > 0.05)
				vertical_direction = 1;
			else if (movement[0] < -0.05)
				vertical_direction = -1;

			if (movement[1] > 0.05)
				lateral_direction = 1;
			else if (movement[1] < -0.05)
				lateral_direction = -1;

			if (!was_climbing)
				climbing_log("ladder entered player=" + self getentitynumber() + " origin=" + self.origin);

			if (vertical_direction != 0 || lateral_direction != 0)
			{
				input_state = vertical_direction + lateral_direction * 10;

				if (input_state != last_input_state)
					climbing_log("input player=" + self getentitynumber() + " movement=" + movement + " velocity=" + self getvelocity());
			}
			else
				input_state = 0;

			last_input_state = input_state;
		}
		else
		{
			if (was_climbing)
				climbing_log("ladder exited player=" + self getentitynumber() + " origin=" + self.origin);

			last_input_state = 0;
		}

		was_climbing = is_climbing;
		scripts\engine\utility::waitframe();
	}
}
