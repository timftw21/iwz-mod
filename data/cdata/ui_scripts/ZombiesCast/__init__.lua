if not Engine.InFrontend() then
	return
end

print("[IWZ][ZombiesCast] script loading")

local guestCharacterSelect = {
	[5] = 1,
	[6] = 2,
	[7] = 3,
	[8] = 4,
	[9] = 5
}

local defaultCast = {
	{
		id = 0,
		name = "Random"
	},
	{
		id = 1,
		name = "Sally"
	},
	{
		id = 2,
		name = "Poindexter"
	},
	{
		id = 3,
		name = "Andre"
	},
	{
		id = 4,
		name = "A.J."
	}
}

local filmGuests = {
	cp_zmb = {
		{
			id = 5,
			name = "David Hasselhoff",
			statGroup = "haveSoulKeys",
			statName = "soul_key_1"
		},
		{
			id = 9,
			name = "Willard Wyler",
			statGroup = "meritState",
			statName = "mt_dlc4_troll2"
		}
	},
	cp_rave = {
		{
			id = 6,
			name = "Kevin Smith",
			statGroup = "haveSoulKeys",
			statName = "soul_key_2"
		}
	},
	cp_disco = {
		{
			id = 7,
			name = "Pam Grier",
			statGroup = "haveSoulKeys",
			statName = "soul_key_3"
		}
	},
	cp_town = {
		{
			id = 8,
			name = "Elvira",
			statGroup = "haveSoulKeys",
			statName = "soul_key_4"
		}
	}
}

local function getCurrentFilm()
	return Engine.GetDvarString("ui_mapname")
end

local function hasStat(controllerIndex, statGroup, statName)
	local value = Engine.GetPlayerDataEx(controllerIndex, CoD.StatsGroup.Coop, statGroup, statName)
	return value == true or (tonumber(value) or 0) > 0
end

local function getCast(controllerIndex)
	local cast = {}
	for _, character in ipairs(defaultCast) do
		cast[#cast + 1] = character
	end

	for _, character in ipairs(filmGuests[getCurrentFilm()] or {}) do
		if hasStat(controllerIndex, character.statGroup, character.statName) then
			cast[#cast + 1] = character
		else
			cast[#cast + 1] = {
				id = character.id,
				name = "???",
				locked = true
			}
		end
	end

	return cast
end

local function applySelection(controllerIndex, selection)
	game:setzombiescharacter(selection)
	Engine.SetPlayerDataEx(
		controllerIndex,
		CoD.StatsGroup.Coop,
		"zombiePlayerLoadout",
		"characterSelect",
		guestCharacterSelect[selection] or 0
	)
end

local function getSelectedCharacter(controllerIndex)
	local selection = game:getzombiescharacter()
	for _, character in ipairs(getCast(controllerIndex)) do
		if character.id == selection and not character.locked then
			applySelection(controllerIndex, selection)
			return character
		end
	end

	applySelection(controllerIndex, 0)
	return defaultCast[1]
end

MenuBuilder.registerType("IWZCastMenu", function(menu, controller)
	local controllerIndex = controller and controller.controllerIndex
	if controllerIndex == nil then
		controllerIndex = 0
	end

	local selected = getSelectedCharacter(controllerIndex)
	local cast = getCast(controllerIndex)
	local buttons = {}
	local defaultFocusIndex = 1
	local lockedCount = 0

	for index, character in ipairs(cast) do
		local characterId = character.id
		local isLocked = character.locked
		if isLocked then
			lockedCount = lockedCount + 1
		end
		local label = ToUpperCase(character.name)
		if characterId == selected.id and not isLocked then
			label = label .. "  ^2(SELECTED)"
			defaultFocusIndex = index
		end

		buttons[#buttons + 1] = {
			label = label,
			disabled = isLocked,
			action = function()
				if not isLocked then
					applySelection(controllerIndex, characterId)
				end
			end
		}
	end

	local self = MenuBuilder.BuildRegisteredType("PopupMessageAndButtons", {
		title = "CAST",
		message = "Choose who you will play as.",
		defaultFocusIndex = defaultFocusIndex,
		cancelClosesPopup = true,
		buttonsClosePopup = true,
		buttons = buttons
	})
	self.id = "IWZCastMenu"
	print("[IWZ][ZombiesCast] cast menu built entries=" .. #cast .. " locked=" .. lockedCount)
	return self
end)

local function addCastInfo(menu, controllerIndex)
	local details = menu.MatchDetails
	details:SetAnchorsAndPosition(0, 1, 1, 0, _1080p * 131, _1080p * 618, _1080p * -329, _1080p * -135)

	local accent = LUI.UIImage.new()
	accent.id = "CastAccent"
	accent:SetAlpha(CONDITIONS.IsArabic(details) and 0 or 0.5, 0)
	accent:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 10, _1080p * 130, _1080p * 180)
	details:addElement(accent)
	details.CastAccent = accent

	local arabicAccent = LUI.UIImage.new()
	arabicAccent.id = "ArabicCastAccent"
	arabicAccent:SetAlpha(CONDITIONS.IsArabic(details) and 0.5 or 0, 0)
	arabicAccent:SetAnchorsAndPosition(1, 0, 0, 1, _1080p * 6, _1080p * 16, _1080p * 130, _1080p * 180)
	details:addElement(arabicAccent)
	details.ArabicCastAccent = arabicAccent

	local title = LUI.UIStyledText.new()
	title.id = "CastTitle"
	title:setText("CAST:", 0)
	title:SetFontSize(24 * _1080p)
	title:SetFont(FONTS.GetFont(FONTS.MainBold.File))
	title:SetAlignment(LUI.Alignment.Left)
	title:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 15, 0, _1080p * 130, _1080p * 154)
	details:addElement(title)
	details.CastTitle = title

	local value = LUI.UIStyledText.new()
	value.id = "CastValue"
	value:SetAlpha(0.5, 0)
	value:SetFontSize(32 * _1080p)
	value:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	value:SetAlignment(LUI.Alignment.Left)
	value:SetDecodeLetterLength(25)
	value:SetDecodeMaxRandChars(3)
	value:SetDecodeUpdatesPerLetter(4)
	value:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 15, 0, _1080p * 154, _1080p * 186)
	details:addElement(value)
	details.CastValue = value

	menu.updateCastInfo = function()
		value:setText(ToUpperCase(getSelectedCharacter(controllerIndex).name), 0)
	end
	menu.updateCastInfo()
end

if MenuBuilder.m_types["CPPrivateMatchMenu"] == nil then
	require("frontEnd.cp.CPPrivateMatchMenu")
end

local CPPrivateMatchMenu = MenuBuilder.m_types["CPPrivateMatchMenu"]

local function buildCPPrivateMatchMenu(menu, controller)
	local self = CPPrivateMatchMenu(menu, controller)
	local controllerIndex = controller and controller.controllerIndex
	if controllerIndex == nil then
		controllerIndex = 0
	end

	addCastInfo(self, controllerIndex)
	print("[IWZ][ZombiesCast] lobby controls attached map=" .. getCurrentFilm() ..
		" selection=" .. game:getzombiescharacter())

	self:addEventHandler("menu_create", function(root)
		root:AddButtonHelperText({
			helper_text = "CAST",
			button_ref = "button_alt2",
			side = "left",
			clickable = true
		})
	end)

	self:addEventHandler("gain_focus", function(root)
		root.updateCastInfo()
	end)

	local bindButton = LUI.UIBindButton.new()
	bindButton.id = "IWZCastBindButton"
	bindButton:addEventHandler("button_alt2", function(element, event)
		LUI.FlowManager.RequestPopupMenu(self, "IWZCastMenu", true, event.controller or controllerIndex, false)
	end)
	self:addElement(bindButton)
	self.IWZCastBindButton = bindButton

	return self
end

MenuBuilder.m_types["CPPrivateMatchMenu"] = buildCPPrivateMatchMenu

print("[IWZ][ZombiesCast] script registered")
