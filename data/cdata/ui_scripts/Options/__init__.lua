local commonFramerateCaps = {
	0,
	30,
	60,
	75,
	90,
	120,
	144,
	165,
	180,
	240,
	360
}

local toggleLabels = {
	"Disabled",
	"Enabled"
}

local xpRateLabels = {
	"REGULAR XP",
	"DOUBLE XP"
}

local hudModeLabels = {
	"NO HUD",
	"STANDARD"
}

local cameraPerspectiveLabels = {
	"FIRST-PERSON",
	"THIRD-PERSON"
}

local function isIwzDoubleXPEnabled()
	return Engine.IsAliensMode() and Engine.GetDvarBool("iwz_double_xp")
end

if Cac and Cac.IsDoubleXPActive and Cac.IsDoubleWeaponXPActive and not Cac.iwzDoubleXPConditionsInstalled then
	Cac.iwzDoubleXPConditionsInstalled = true
	local stockIsDoubleXPActive = Cac.IsDoubleXPActive
	local stockIsDoubleWeaponXPActive = Cac.IsDoubleWeaponXPActive

	Cac.IsDoubleXPActive = function(...)
		return isIwzDoubleXPEnabled() or stockIsDoubleXPActive(...)
	end

	Cac.IsDoubleWeaponXPActive = function(...)
		return isIwzDoubleXPEnabled() or stockIsDoubleWeaponXPActive(...)
	end

	print("[IWZ][DoubleXP] level and weapon XP notification conditions installed")
end

local nameColors = {
	{label = "DEFAULT", code = ""},
	{label = "RED", code = "^1"},
	{label = "GREEN", code = "^2"},
	{label = "YELLOW", code = "^3"},
	{label = "BLUE", code = "^4"},
	{label = "CYAN", code = "^5"},
	{label = "PINK", code = "^6"},
	{label = "WHITE", code = "^7"},
	{label = "TEAM COLOR", code = "^8"},
	{label = "GREY", code = "^9"},
	{label = "BLACK", code = "^0"},
	{label = "RAINBOW", code = "^:"}
}

local function findOption(options, id)
	for index, option in ipairs(options) do
		if option.id == id then
			return index, option
		end
	end
end

local function getFramerateCaps()
	local caps = {}
	local currentCap = Engine.GetDvarInt("com_maxfps")
	local hasCurrentCap = currentCap == 0

	for _, cap in ipairs(commonFramerateCaps) do
		table.insert(caps, cap)

		if cap == currentCap then
			hasCurrentCap = true
		end
	end

	if currentCap > 0 and not hasCurrentCap then
		local insertIndex = #caps + 1

		for index = 2, #caps do
			if currentCap < caps[index] then
				insertIndex = index
				break
			end
		end

		table.insert(caps, insertIndex, currentCap)
	end

	return caps, currentCap
end

local function buildDvarToggleButton(controllerIndex, id, title, description, dvar, labels)
	local currentValue = Engine.GetDvarBool(dvar) and 2 or 1
	local button = MenuBuilder.BuildRegisteredType("GenericArrowButton", {
		controllerIndex = controllerIndex
	})
	button.id = id
	button:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 50)
	button.buttonDescription = description
	button.Title:setText(title, 0)

	LUI.AddUIArrowTextButtonLogic(button, controllerIndex, {
		labels = labels or toggleLabels,
		action = function(index)
			local enabled = index == 2
			Engine.SetDvarBool(dvar, enabled)

			if dvar == "iwz_double_xp" then
				button:dispatchEventToRoot({
					name = "iwz_xp_rate_changed"
				})
				print("[IWZ][DoubleXP] option changed enabled=" .. tostring(enabled))
			elseif dvar == "iwz_zombies_hud" then
				button:dispatchEventToRoot({
					name = "iwz_hud_mode_changed",
					enabled = enabled
				})
				print("[IWZ][HUD] option changed enabled=" .. tostring(enabled) ..
					" mode=" .. (enabled and "standard" or "no_hud"))
			elseif dvar == "cg_thirdPerson" then
				print("[IWZ][Camera] option changed thirdPerson=" .. tostring(enabled) ..
					" perspective=" .. (enabled and "third-person" or "first-person"))
			end
		end,
		defaultValue = currentValue,
		wrapAround = true
	})

	button:addEventHandler("refresh_values", function()
		button.currentValue = Engine.GetDvarBool(dvar) and 2 or 1
		button:UpdateContent()
	end)

	return button
end

local function buildFramerateCapButton(controllerIndex)
	local caps, currentCap = getFramerateCaps()
	local labels = {}
	local currentIndex = 1

	for index, cap in ipairs(caps) do
		labels[index] = cap == 0 and "UNLIMITED" or tostring(cap) .. " FPS"

		if cap == currentCap then
			currentIndex = index
		end
	end

	local button = MenuBuilder.BuildRegisteredType("GenericArrowButton", {
		controllerIndex = controllerIndex
	})
	button.id = "FramerateCap"
	button:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 50)
	button.Title:setText("FRAMERATE CAP", 0)

	LUI.AddUIArrowTextButtonLogic(button, controllerIndex, {
		labels = labels,
		action = function(index)
			Engine.SetDvarInt("com_maxfps", caps[index])
		end,
		defaultValue = currentIndex,
		wrapAround = true
	})

	local function updateVsyncState()
		if Engine.GetDvarBool("r_vsync") then
			labels[1] = "DISPLAY REFRESH (V-SYNC)"
			button.buttonDescription = "Set a framerate limit. V-Sync remains active and uses the lower of this cap and the display refresh rate."
		else
			labels[1] = "UNLIMITED"
			button.buttonDescription = "Set the maximum number of frames rendered per second."
		end

		button:UpdateContent()
	end

	button:addEventHandler("refresh_values", updateVsyncState)
	button:addEventHandler("button_over", updateVsyncState)
	updateVsyncState()

	return button
end

local function buildFovScaleButton(controllerIndex)
	local minValue = 0.8
	local maxValue = 1.5
	local step = 0.01
	local currentValue = Engine.GetDvarFloat("com_fovUserScale")

	if currentValue < minValue then
		currentValue = minValue
	elseif currentValue > maxValue then
		currentValue = maxValue
	end

	local button = MenuBuilder.BuildRegisteredType("GenericFillBarArrowButton", {
		controllerIndex = controllerIndex
	})
	button.id = "FOV"
	button:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 50)
	button.buttonDescription = Engine.Localize("PLATFORM_UI_FOV_DESC")
	button.Title:setText(ToUpperCase(Engine.Localize("PLATFORM_UI_FOV_CAPS")), 0)

	local function updateContent(element)
		local fill = (element.currentValue - element.min) / (element.max - element.min)

		if element.direction == ArrowBarFillDirections.LEFT_TO_RIGHT then
			element.fillElement:SetAnchors(0, 1 - fill, 0, 0, element.updateDuration)
		else
			element.fillElement:SetAnchors(1 - fill, 0, 0, 0, element.updateDuration)
		end

		element.Text:setText(string.format("%.1f", element.currentValue * 80), element.updateDuration)
		ACTIONS.AnimateSequence(element, "ShowNumberLabel")
	end

	LUI.AddUIArrowFillBarButtonLogic(button, controllerIndex, {
		decimalPlacesToRound = 6,
		action = function(value)
			Engine.SetDvarFloat("com_fovUserScale", value)
		end,
		defaultValue = currentValue,
		wrapAround = false,
		max = maxValue,
		min = minValue,
		step = step,
		fillElement = button.GenericFillBar.Fill,
		UpdateContent = updateContent
	})

	button:addEventHandler("refresh_values", function()
		local value = Engine.GetDvarFloat("com_fovUserScale")
		button.currentValue = math.max(minValue, math.min(maxValue, value))
		button:UpdateContent()
	end)

	ACTIONS.AnimateSequence(button, "ShowTickMarker")
	local tickMarker = (1 - minValue) / (maxValue - minValue)
	button.GenericFillBar.TickMarker:SetAnchorsAndPosition(tickMarker, 1 - tickMarker - 0.01, 0, 0, 0, 0, -4, 4)

	return button
end

local function buildMuteOnFocusLostButton(controllerIndex)
	return buildDvarToggleButton(
		controllerIndex,
		"MuteOnFocusLost",
		"MUTE ON FOCUS LOST",
		"Mute all client audio while another application has focus.",
		"iwz_mute_on_focus_lost"
	)
end

local function buildSubtitlesButton(controllerIndex)
	local button = MenuBuilder.BuildRegisteredType("GenericArrowButton", {
		controllerIndex = controllerIndex
	})
	button.id = "Subtitles"
	button:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 50)
	button.buttonDescription = Engine.Localize("PLATFORM_OPTIONS_SUBTITLES_DESC")
	button.Title:setText(ToUpperCase(Engine.Localize("MENU_SUBTITLES_CAPS")), 0)
	OPTIONS.CreateSubtitleLogic(button, controllerIndex)

	return button
end

local function splitNameColor(name)
	local colorIndex = 1
	local nameStart = 1

	while true do
		local foundColor = false

		for index, color in ipairs(nameColors) do
			if color.code ~= "" and string.sub(name, nameStart, nameStart + 1) == color.code then
				if nameStart == 1 then
					colorIndex = index
				end

				nameStart = nameStart + 2
				foundColor = true
				break
			end
		end

		if not foundColor then
			break
		end
	end

	return colorIndex, string.sub(name, nameStart)
end

local function buildPlayerNameButton(controllerIndex)
	local button = MenuBuilder.BuildRegisteredType("GenericDualLabelButton", {
		controllerIndex = controllerIndex
	})
	button.id = "PlayerName"
	button:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 50)
	button.buttonDescription = "Change the name displayed to other players."
	button.Text:setText("PLAYER NAME", 0)
	button.Text:SetAlignment(LUI.Alignment.Left)

	local function refreshName()
		button.DynamicText:setText(Engine.GetDvarString("name"), 0)
	end

	button:addEventHandler("button_action", function(_, event)
		local _, currentName = splitNameColor(Engine.GetDvarString("name"))
		local controller = event.controller or controllerIndex

		OSK.OpenScreenKeyboard(controller, "PLAYER NAME", currentName, 29, false, false, false,
			function(_, newName, result)
				if result == CoD.KeyboardResult.UI_KEYBOARD_RESULT_CANCELLED or not newName or newName == "" then
					return
				end

				local colorIndex = splitNameColor(Engine.GetDvarString("name"))
				local _, plainName = splitNameColor(newName)
				Engine.SetDvarString("name", nameColors[colorIndex].code .. string.sub(plainName, 1, 29))
				refreshName()
			end, CoD.KeyboardInputTypes.Normal)
	end)

	button:addEventHandler("refresh_values", refreshName)
	refreshName()

	return button, refreshName
end

local function buildNameColorButton(controllerIndex, refreshName)
	local labels = {}
	for index, color in ipairs(nameColors) do
		labels[index] = color.label
	end

	local currentIndex = splitNameColor(Engine.GetDvarString("name"))
	local button = MenuBuilder.BuildRegisteredType("GenericArrowButton", {
		controllerIndex = controllerIndex
	})
	button.id = "NameColor"
	button:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 50)
	button.buttonDescription = "Choose the color used to display your player name."
	button.Title:setText("NAME COLOR", 0)

	LUI.AddUIArrowTextButtonLogic(button, controllerIndex, {
		labels = labels,
		action = function(index)
			local _, plainName = splitNameColor(Engine.GetDvarString("name"))
			Engine.SetDvarString("name", nameColors[index].code .. string.sub(plainName, 1, 29))
			refreshName()
		end,
		defaultValue = currentIndex,
		wrapAround = true
	})

	button:addEventHandler("refresh_values", function()
		button.currentValue = splitNameColor(Engine.GetDvarString("name"))
		button:UpdateContent()
	end)

	return button
end

local function buildClientOptions(_, controllerIndex)
	local playerName, refreshName = buildPlayerNameButton(controllerIndex)
	local nameColor = buildNameColorButton(controllerIndex, refreshName)

	return {
		playerName,
		nameColor,
		buildDvarToggleButton(
			controllerIndex,
			"SkipIntroCinematics",
			"SKIP INTRO CINEMATICS",
			"Skip the default and startup cinematics when the client launches.",
			"iwz_skip_intro_cinematics"
		),
		buildDvarToggleButton(
			controllerIndex,
			"PauseOnFocusLost",
			"PAUSE ON FOCUS LOST",
			"Automatically pause solo Zombies when another application has focus.",
			"iwz_pause_on_focus_lost"
		),
		buildDvarToggleButton(
			controllerIndex,
			"DoubleXP",
			"XP RATE",
			"Switch Zombies level and weapon progression between regular XP and double XP. Key progression is not affected.",
			"iwz_double_xp",
			xpRateLabels
		)
	}
end

local function buildZombiesOptions(_, controllerIndex)
	return {
		buildDvarToggleButton(
			controllerIndex,
			"CameraPerspective",
			"CAMERA PERSPECTIVE",
			"Switch gameplay between first-person and third-person camera perspectives.",
			"cg_thirdPerson",
			cameraPerspectiveLabels
		),
		buildDvarToggleButton(
			controllerIndex,
			"ZombiesHUD",
			"HUD",
			"Choose between the standard in-game Zombies HUD and no HUD.",
			"iwz_zombies_hud",
			hudModeLabels
		)
	}
end

local function customizeOptions(options, controllerIndex)
	local volumeIndex, volume = findOption(options, "Volume")

	if volumeIndex and volumeIndex > 1 then
		table.remove(options, volumeIndex)
		table.insert(options, 1, volume)
	end

	if volumeIndex and Engine.IsAliensMode() and not findOption(options, "Subtitles") then
		local mixPresetIndex = findOption(options, "MixPreset") or #options + 1
		table.insert(options, mixPresetIndex, buildSubtitlesButton(controllerIndex))
	end

	if volumeIndex and not findOption(options, "MuteOnFocusLost") then
		local mixPresetIndex = findOption(options, "MixPreset") or #options + 1
		table.insert(options, mixPresetIndex, buildMuteOnFocusLostButton(controllerIndex))
	end

	local brightnessIndex = findOption(options, "Brightness")
	local fpsCounterIndex = findOption(options, "FPSCounter")
	local isMainVideoOptions = brightnessIndex and fpsCounterIndex
	local fovIndex = findOption(options, "FOV")

	if fovIndex then
		table.remove(options, fovIndex)
	end

	if isMainVideoOptions then
		fpsCounterIndex = findOption(options, "FPSCounter")
		local framerateCapIndex = findOption(options, "FramerateCap")

		if not framerateCapIndex then
			framerateCapIndex = fpsCounterIndex + 1
			table.insert(options, framerateCapIndex, buildFramerateCapButton(controllerIndex))
		end

		table.insert(options, framerateCapIndex + 1, buildFovScaleButton(controllerIndex))
	end

	return options
end

if not LUI.SubtitlesLayer then
	require("inGame.sp.SubtitlesLayer")
end

local DoubleXPNotifications = MenuBuilder.m_types["DoubleXPNotifications"]

if DoubleXPNotifications and not LUI.iwzDoubleXPNotificationsPatched then
	LUI.iwzDoubleXPNotificationsPatched = true

	MenuBuilder.m_types["DoubleXPNotifications"] = function(menu, controller)
		local self = DoubleXPNotifications(menu, controller)

		local function refreshIwzDoubleXPIcons()
			if self.DoubleXP then
				self.DoubleXP:SetAlpha(Cac.IsDoubleXPActive() and 1 or 0, 0)
			end

			if self.DoubleWeaponXP then
				self.DoubleWeaponXP:SetAlpha(Cac.IsDoubleWeaponXPActive() and 1 or 0, 0)
			end
		end

		self:addEventHandler("iwz_xp_rate_changed", refreshIwzDoubleXPIcons)
		refreshIwzDoubleXPIcons()

		return self
	end

	print("[IWZ][DoubleXP] notification refresh hook installed")
end

local LUIRootInit = LUI.UIRoot.init

LUI.UIRoot.init = function(self, controllerIndex, name)
	LUIRootInit(self, controllerIndex, name)

	if Engine.IsAliensMode() and not Engine.InFrontend() and not self.subtitlesLayer then
		self.subtitlesLayer = self:AddLayer(LUI.SubtitlesLayer.new(self._controllerIndex), {
			exclusive = false
		})
	end
end

local function suppressFocusPause(event)
	if not event or event.name ~= "pause" or not Engine.IsAliensMode() or game:isclientfocused() then
		return false
	end

	if LUI.FlowManager.IsInStack("CPPauseMenu") then
		local function preserveGamePause()
			if not game:isclientfocused() and LUI.FlowManager.IsInStack("CPPauseMenu") and
				not Engine.IsLocalServerPaused() then
				Engine.Pause()
			end
		end

		preserveGamePause()
		scheduler.once(preserveGamePause)

		print("[IWZ][FocusPause] suppressed duplicate focus-loss pause event; preserved existing pause")
		return true
	end

	if not Engine.GetDvarBool("iwz_pause_on_focus_lost") then
		local function restoreGame()
			if not Engine.GetDvarBool("iwz_pause_on_focus_lost") and Engine.IsLocalServerPaused() then
				Engine.Unpause()
			end
		end

		restoreGame()
		scheduler.once(restoreGame)

		print("[IWZ][FocusPause] suppressed focus-loss pause event")
		return true
	end

	return false
end

if not LUI.UIRoot.iwzFocusPauseInterceptorsInstalled then
	LUI.UIRoot.iwzFocusPauseInterceptorsInstalled = true

	scheduler.once(function()
		local rootProcessEvent = LUI.UIRoot.ProcessEvent
		local rootProcessEventNow = LUI.UIRoot.ProcessEventNow

		LUI.UIRoot.ProcessEvent = function(self, event)
			if suppressFocusPause(event) then
				return false
			end

			return rootProcessEvent(self, event)
		end

		LUI.UIRoot.ProcessEventNow = function(self, event)
			if suppressFocusPause(event) then
				return false
			end

			return rootProcessEventNow(self, event)
		end

		print("[IWZ][FocusPause] event interceptors installed")
	end)
else
	print("[IWZ][FocusPause] event interceptors already installed")
end

local PCOptionWindow = MenuBuilder.m_types["PCOptionWindow"]

MenuBuilder.m_types["PCOptionWindow"] = function(menu, controller)
	local self = PCOptionWindow(menu, controller)
	local updateOptions = self.UpdateOptions

	self.UpdateOptions = function(element, controllerIndex, title, createOptions, category)
		local customizedCreateOptions = function(window, index)
			return customizeOptions(createOptions(window, index), index)
		end

		return updateOptions(element, controllerIndex, title, customizedCreateOptions, category)
	end

	return self
end

local PCOptionsButtons = MenuBuilder.m_types["PCOptionsButtons"]

MenuBuilder.m_types["PCOptionsButtons"] = function(menu, controller)
	local self = PCOptionsButtons(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or self:getRootController()
	local clientOptions = MenuBuilder.BuildRegisteredType("GenericButton", {
		controllerIndex = controllerIndex
	})
	clientOptions.id = "ClientOptions"
	clientOptions:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 30)
	clientOptions.buttonDescription = "Configure iwz-mod client and startup behavior."
	clientOptions.Text:setText("CLIENT OPTIONS", 0)
	clientOptions.Text:SetAlignment(LUI.Alignment.Left)

	clientOptions:addEventHandler("button_over", function()
		self:processEvent({
			name = "category_button_over"
		})
	end)

	clientOptions:addEventHandler("button_action", function(_, event)
		self:processEvent({
			name = "category_changed",
			title = "CLIENT OPTIONS",
			createOptions = buildClientOptions,
			noFocus = event.mouse
		})
	end)

	clientOptions:addElementBefore(self.VideoOptions)
	self.ClientOptions = clientOptions

	local zombiesOptions = MenuBuilder.BuildRegisteredType("GenericButton", {
		controllerIndex = controllerIndex
	})
	zombiesOptions.id = "ZombiesOptions"
	zombiesOptions:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * 30)
	zombiesOptions.buttonDescription = "Configure Infinite Warfare Zombies gameplay and presentation."
	zombiesOptions.Text:setText("ZOMBIES OPTIONS", 0)
	zombiesOptions.Text:SetAlignment(LUI.Alignment.Left)

	zombiesOptions:addEventHandler("button_over", function()
		self:processEvent({
			name = "category_button_over"
		})
	end)

	zombiesOptions:addEventHandler("button_action", function(_, event)
		self:processEvent({
			name = "category_changed",
			title = "ZOMBIES OPTIONS",
			createOptions = buildZombiesOptions,
			noFocus = event.mouse
		})
	end)

	zombiesOptions:addElementBefore(self.VideoOptions)
	self.ZombiesOptions = zombiesOptions

	self:addEventHandler("menu_create", function()
		self:processEvent({
			name = "category_changed",
			title = "CLIENT OPTIONS",
			createOptions = buildClientOptions,
			noFocus = true
		})
	end)

	print("[IWZ][Options] installed categories client=CLIENT OPTIONS zombies=ZOMBIES OPTIONS")

	return self
end
