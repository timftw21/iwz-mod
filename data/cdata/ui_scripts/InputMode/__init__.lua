local root = Engine.GetLuiRoot()
local lastMode
root:addEventHandler("iwz_check_input", function(element)
	local mode = Engine.IsGamepadEnabled()
	if mode == lastMode then
		return true
	end
	lastMode = mode
	element:TryAddMouseCursor()
	element:processEvent({ name = "refresh_button_helper", dispatchChildren = true })
	element:processEvent({ name = "refresh_button_background", dispatchChildren = true })
	element:processEvent({ name = "iwz_input_changed", dispatchChildren = true })
	print("[IWZ][Input] prompts refreshed gamepad=" .. tostring(mode))
	return true
end)

-- The root and its timer are recreated together on every frontend/match VM.
-- Native input switches immediately; LUI observes it on its own thread.
local timer = LUI.UITimer.new(nil, {
	interval = 50,
	event = "iwz_check_input",
	eventTarget = root,
	disposable = false,
	broadcastToRoot = false
})
timer.id = "IWZInputModeTimer"
root:addElement(timer)
