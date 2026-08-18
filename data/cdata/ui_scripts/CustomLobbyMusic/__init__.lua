local CUSTOM_MUSIC_MODEL = "frontEnd.IWZCustomMusic"
local LOBBY_MUSIC_SELECTION_MODEL = "frontEnd.IWZLobbyMusicSelection"

local function log(message)
	print("[IWZ][CustomMusic] " .. message)
end

log("script loading frontend=" .. tostring(Engine.InFrontend()) .. " aliens=" .. tostring(Engine.IsAliensMode()))

if not Engine.InFrontend() then
	return
end

if MenuBuilder.m_types["CPLobbyMusicMenu"] == nil then
	require("frontEnd.cp.CPLobbyMusicMenu")
end

if MenuBuilder.m_types["CPLobbySecretSongButtons"] == nil then
	require("frontEnd.cp.CPLobbySecretSongButtons")
end

if MenuBuilder.m_types["CPPrivateMatchMenu"] == nil then
	require("frontEnd.cp.CPPrivateMatchMenu")
end

local customSelectionSource = LUI.DataSourceInGlobalModel.new(
	LOBBY_MUSIC_SELECTION_MODEL .. ".customSelected",
	custommusic.selectedname() ~= "" and 1 or 0
)

local function publishCustomSelection(controllerIndex, selected, reason)
	DataModel.SetModelValue(customSelectionSource:GetModel(controllerIndex), selected and 1 or 0)
	log("lobby selection model updated customSelected=" .. tostring(selected) .. " reason=" .. reason)
end

local function addHeadquartersFooter(menu, controllerIndex)
	if menu.SocialFeed then
		return
	end

	-- Headquarters supplies the angled black cap above ButtonHelperBar through
	-- SocialFeed. CPLobbyMusicMenu omits that sibling even though it is opened
	-- from Headquarters, so reuse the stock widget and its exact placement.
	local SocialFeed = MenuBuilder.BuildRegisteredType("SocialFeed", {
		controllerIndex = controllerIndex
	})
	SocialFeed.id = "SocialFeed"
	SocialFeed:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 1920, _1080p * 965, _1080p * 995)
	menu:addElement(SocialFeed)
	menu.SocialFeed = SocialFeed
	log("stock Headquarters footer treatment attached menu=" .. menu.id)
end

local function restoreStockMusic(reason)
	custommusic.release(reason)
	Engine.NotifyServer("music_changed", 0)
	log("stock ownership restored reason=" .. reason .. " notification=music_changed value=0")
end

-- Some frontend menus start music through the LUI API instead of
-- SND_SetMusicState. Keep a single owner throughout the lobby session, including
-- its film, Barracks, and Loadout sections. Only zm_main ends that session.
local originalPlayMusic = Engine.PlayMusic
Engine.PlayMusic = function(...)
	if custommusic.isclaimed() then
		if custommusic.islobbysession() then
			log("suppressed stock Engine.PlayMusic request while custom player owns the Zombies lobby session")
			Engine.StopMusic()
			return
		end

		custommusic.release("stock Engine.PlayMusic requested after returning to Zombies main menu")
		log("custom ownership released before forwarding stock Engine.PlayMusic request")
	end

	return originalPlayMusic(...)
end

-- The stock frontend remains globally active across every Zombies menu. Feed
-- section changes to the native player synchronously; the GSC monitor provides
-- the authoritative fallback for transitions that do not originate in LUI.
local originalSetFrontEndSceneSection = Engine.SetFrontEndSceneSection
Engine.SetFrontEndSceneSection = function(sectionName, ...)
	custommusic.setscene(sectionName or "")
	return originalSetFrontEndSceneSection(sectionName, ...)
end

local function stopStockMusicThen(callback)
	-- cp_frontend.gsc's shuffle loop only ends when a non-shuffle music_changed
	-- notification raises shuffle_changed. Claim first so the patched frontend
	-- GSC consumes that notification without installing another stock state.
	custommusic.setscene("zm_lobby")
	if not custommusic.claim("LUI requested custom lobby music") then
		log("custom ownership claim failed; stock playback left unchanged")
		return false
	end

	log("custom ownership claimed notification=music_changed value=0")
	Engine.NotifyServer("music_changed", 0)
	Engine.StopMusic()
	scheduler.once(function()
		Engine.StopMusic()
		log("stock shuffle stopped; transferring ownership to custom player")
		callback()
	end, 100)
	return true
end

local function buildTrackButton(_, controller)
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()
	local button = MenuBuilder.BuildRegisteredType("GenericButton", {
		controllerIndex = controllerIndex
	})
	button.id = "IWZCustomMusicTrackButton"

	-- The label is a model inside the row's data source. Subscribing only to the
	-- data-source assignment updates recycled rows but does not observe changes
	-- to that model. Subscribe the text element to buttonLabel itself so a new
	-- selection repaints every affected row immediately.
	button.Text:SubscribeToModelThroughElement(button, "buttonLabel", function()
		local dataSource = button:GetDataSource()
		if dataSource and dataSource.buttonLabel then
			local label = dataSource.buttonLabel:GetValue(controllerIndex)
			if label ~= nil then
				button.Text:setText(ToUpperCase(label), 0)
			end
		end
	end)

	button:addEventHandler("button_action", function(element, event)
		local dataSource = element:GetDataSource()
		if dataSource and dataSource.buttonOnClickFunction then
			dataSource.buttonOnClickFunction(element, event.controller or controllerIndex)
		end
	end)

	button:addEventHandler("button_over", function(element, event)
		local dataSource = element:GetDataSource()
		if dataSource and dataSource.buttonOnHoverFunction then
			dataSource.buttonOnHoverFunction(element, event.controller or controllerIndex)
		end
	end)

	return button
end

MenuBuilder.registerType("IWZCustomMusicTrackButton", buildTrackButton)

local function setSelectedTrackLabels(tracks, selectedIndex, controllerIndex)
	for _, track in ipairs(tracks) do
		local label = track.name
		if track.index == selectedIndex then
			label = label .. "  ^2(SELECTED)"
		end

		DataModel.SetModelValue(track.labelSource:GetModel(controllerIndex), label)
	end

	log("selection labels updated selectedIndex=" .. selectedIndex .. " rowCount=" .. #tracks)
end

local function populateTracks(menu, controllerIndex, focusFirst)
	WipeGlobalModelsAtPath(CUSTOM_MUSIC_MODEL)
	local trackCount = custommusic.rescan()
	local selectedName = custommusic.selectedname()
	local selectedIndex = custommusic.selectedindex()
	local tracks = {}
	publishCustomSelection(controllerIndex, selectedName ~= "", "custom music scan")

	for index = 0, trackCount - 1 do
		local name = custommusic.name(index)
		local extension = custommusic.extension(index)
		local label = name
		if selectedIndex == index then
			label = label .. "  ^2(SELECTED)"
		end

		tracks[#tracks + 1] = {
			index = index,
			name = name,
			extension = extension,
			labelSource = LUI.DataSourceInGlobalModel.new(CUSTOM_MUSIC_MODEL .. ".tracks." .. index, label)
		}
	end

	local dataSource = LUI.DataSourceFromList.new(#tracks)
	dataSource.MakeDataSourceAtIndex = function(_, index)
		local track = tracks[index + 1]
		return {
			buttonLabel = track.labelSource,
			buttonOnClickFunction = function()
				menu.PlayRequestToken = menu.PlayRequestToken + 1
				local requestToken = menu.PlayRequestToken
				menu.StatusText:setText("LOADING " .. ToUpperCase(track.name) .. "...", 0)
				log("selection requested index=" .. track.index .. " name=" .. track.name .. " format=" .. track.extension)

				if not stopStockMusicThen(function()
					if requestToken ~= menu.PlayRequestToken then
						log("selection request superseded before playback index=" .. track.index)
						return
					end

					if custommusic.play(track.index) then
						publishCustomSelection(controllerIndex, true, "custom track selected")
						setSelectedTrackLabels(tracks, track.index, controllerIndex)
						menu.StatusText:setText("NOW PLAYING: " .. ToUpperCase(track.name), 0)
						log("selection playing index=" .. track.index .. " name=" .. track.name)
					else
						restoreStockMusic("custom track failed to start")
						menu.StatusText:setText("UNABLE TO PLAY " .. ToUpperCase(track.name) .. " - CHECK THE LOG", 0)
						log("selection failed index=" .. track.index .. " name=" .. track.name)
					end
				end) then
					menu.StatusText:setText("UNABLE TO CLAIM CUSTOM MUSIC PLAYBACK - CHECK THE LOG", 0)
				end
			end,
			buttonOnHoverFunction = function()
				menu.TrackName:setText(ToUpperCase(track.name), 0)
				menu.TrackFormat:setText(ToUpperCase(track.extension) .. " AUDIO", 0)
			end
		}
	end

	menu.TrackList:SetGridDataSource(dataSource, controllerIndex)
	menu.EmptyMessage:SetAlpha(trackCount == 0 and 1 or 0, 0)
	menu.ListCount:SetAlpha(trackCount == 0 and 0 or 1, 0)
	menu.StatusText:setText(trackCount == 0 and "DROP SUPPORTED AUDIO FILES INTO THE FOLDER, THEN REFRESH"
		or (trackCount .. (trackCount == 1 and " TRACK FOUND" or " TRACKS FOUND")), 0)

	if focusFirst and trackCount > 0 then
		local first = menu.TrackList:GetElementAtPosition(0, 0)
		if first then
			first:processEvent({
				name = "gain_focus",
				controllerIndex = controllerIndex
			})
		end
	end

	log("menu scan populated count=" .. trackCount .. " selected=" .. (selectedName ~= "" and selectedName or "none"))
end

local function buildCustomMusicMenu(_, controller)
	local self = LUI.UIElement.new()
	self.id = "IWZCustomLobbyMusicMenu"
	self.PlayRequestToken = 0

	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()
	assert(controllerIndex)
	Engine.MenuDvarsSetup(controllerIndex)
	log("audio settings synchronized controller=" .. controllerIndex .. " reason=menu open")
	self:playSound("menu_open")

	local ButtonHelperBar = MenuBuilder.BuildRegisteredType("ButtonHelperBar", {
		controllerIndex = controllerIndex
	})
	ButtonHelperBar.id = "ButtonHelperBar"
	ButtonHelperBar:SetAnchorsAndPosition(0, 0, 1, 0, 0, 0, _1080p * -85, 0)
	self:addElement(ButtonHelperBar)
	self.ButtonHelperBar = ButtonHelperBar
	addHeadquartersFooter(self, controllerIndex)

	local MenuTitle = MenuBuilder.BuildRegisteredType("CPMenuTitle", {
		controllerIndex = controllerIndex
	})
	MenuTitle.id = "MenuTitle"
	MenuTitle.MenuTitle:setText("CUSTOM MUSIC", 0)
	MenuTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 96, _1080p * 1056, _1080p * 54, _1080p * 134)
	self:addElement(MenuTitle)
	self.MenuTitle = MenuTitle

	local TrackList = LUI.UIDataSourceGrid.new(nil, {
		maxVisibleColumns = 1,
		maxVisibleRows = 16,
		controllerIndex = controllerIndex,
		buildChild = function()
			return MenuBuilder.BuildRegisteredType("IWZCustomMusicTrackButton", {
				controllerIndex = controllerIndex
			})
		end,
		wrapX = true,
		wrapY = true,
		spacingX = _1080p * 10,
		spacingY = _1080p * 10,
		columnWidth = _1080p * 600,
		rowHeight = _1080p * 30,
		scrollingThresholdX = 1,
		scrollingThresholdY = 1,
		adjustSizeToContent = false,
		horizontalAlignment = LUI.Alignment.Left,
		verticalAlignment = LUI.Alignment.Top,
		springCoefficient = 600,
		maxVelocity = 5000
	})
	TrackList.id = "TrackList"
	TrackList:setUseStencil(false)
	TrackList:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 730, _1080p * 216, _1080p * 856)
	self:addElement(TrackList)
	self.TrackList = TrackList

	local ArrowUp = MenuBuilder.BuildRegisteredType("ArrowUp", {
		controllerIndex = controllerIndex
	})
	ArrowUp.id = "ArrowUp"
	ArrowUp:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 487, _1080p * 507, _1080p * 870, _1080p * 910)
	self:addElement(ArrowUp)
	self.ArrowUp = ArrowUp

	local ArrowDown = MenuBuilder.BuildRegisteredType("ArrowDown", {
		controllerIndex = controllerIndex
	})
	ArrowDown.id = "ArrowDown"
	ArrowDown:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 322, _1080p * 342, _1080p * 870, _1080p * 910)
	self:addElement(ArrowDown)
	self.ArrowDown = ArrowDown

	local ListCount = LUI.UIText.new()
	ListCount.id = "ListCount"
	ListCount:SetFontSize(24 * _1080p)
	ListCount:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	ListCount:SetAlignment(LUI.Alignment.Center)
	ListCount:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 342, _1080p * 487, _1080p * 878, _1080p * 902)
	self:addElement(ListCount)
	self.ListCount = ListCount

	TrackList:AddArrow(ArrowUp)
	TrackList:AddArrow(ArrowDown)
	TrackList:AddItemNumbers(ListCount)

	local EmptyMessage = LUI.UIText.new()
	EmptyMessage.id = "EmptyMessage"
	EmptyMessage:setText("NO SUPPORTED AUDIO FILES FOUND", 0)
	EmptyMessage:SetFontSize(24 * _1080p)
	EmptyMessage:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	EmptyMessage:SetAlignment(LUI.Alignment.Left)
	EmptyMessage:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 730, _1080p * 216, _1080p * 246)
	self:addElement(EmptyMessage)
	self.EmptyMessage = EmptyMessage

	local InfoTitle = LUI.UIText.new()
	InfoTitle.id = "InfoTitle"
	InfoTitle:setText("CUSTOM LOBBY MUSIC", 0)
	InfoTitle:SetFontSize(30 * _1080p)
	InfoTitle:SetFont(FONTS.GetFont(FONTS.MainBold.File))
	InfoTitle:SetAlignment(LUI.Alignment.Left)
	InfoTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 216, _1080p * 250)
	self:addElement(InfoTitle)
	self.InfoTitle = InfoTitle

	-- IW's styled text scales glyphs from the element height. Keep every field
	-- single-line and make its bounds match its font size so long metadata can
	-- scroll horizontally without inflating the type.
	local TrackName = LUI.UIStyledText.new()
	TrackName.id = "TrackName"
	TrackName:setText("SELECT A TRACK TO PREVIEW IT", 0)
	TrackName:SetFontSize(24 * _1080p)
	TrackName:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	TrackName:SetAlignment(LUI.Alignment.Left)
	TrackName:SetStartupDelay(2000)
	TrackName:SetLineHoldTime(400)
	TrackName:SetAnimMoveTime(300)
	TrackName:SetEndDelay(1500)
	TrackName:SetCrossfadeTime(750)
	TrackName:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
	TrackName:SetMaxVisibleLines(1)
	TrackName:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 280, _1080p * 304)
	self:addElement(TrackName)
	self.TrackName = TrackName

	local TrackFormat = LUI.UIText.new()
	TrackFormat.id = "TrackFormat"
	TrackFormat:SetFontSize(20 * _1080p)
	TrackFormat:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	TrackFormat:SetAlignment(LUI.Alignment.Left)
	TrackFormat:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 316, _1080p * 336)
	self:addElement(TrackFormat)
	self.TrackFormat = TrackFormat

	local FolderTitle = LUI.UIText.new()
	FolderTitle.id = "FolderTitle"
	FolderTitle:setText("FOLDER", 0)
	FolderTitle:SetFontSize(20 * _1080p)
	FolderTitle:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	FolderTitle:SetAlignment(LUI.Alignment.Left)
	FolderTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 380, _1080p * 400)
	self:addElement(FolderTitle)
	self.FolderTitle = FolderTitle

	local FolderPath = LUI.UIStyledText.new()
	FolderPath.id = "FolderPath"
	FolderPath:setText(custommusic.folder(), 0)
	FolderPath:SetFontSize(20 * _1080p)
	FolderPath:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	FolderPath:SetAlignment(LUI.Alignment.Left)
	FolderPath:SetStartupDelay(2000)
	FolderPath:SetLineHoldTime(400)
	FolderPath:SetAnimMoveTime(300)
	FolderPath:SetEndDelay(1500)
	FolderPath:SetCrossfadeTime(750)
	FolderPath:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
	FolderPath:SetMaxVisibleLines(1)
	FolderPath:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 414, _1080p * 434)
	self:addElement(FolderPath)
	self.FolderPath = FolderPath

	local FormatsTitle = LUI.UIText.new()
	FormatsTitle.id = "FormatsTitle"
	FormatsTitle:setText("SUPPORTED FORMATS", 0)
	FormatsTitle:SetFontSize(20 * _1080p)
	FormatsTitle:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	FormatsTitle:SetAlignment(LUI.Alignment.Left)
	FormatsTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 476, _1080p * 496)
	self:addElement(FormatsTitle)
	self.FormatsTitle = FormatsTitle

	local Formats = LUI.UIText.new()
	Formats.id = "Formats"
	Formats:setText("MP3, WAV, FLAC, OGG VORBIS, OGG OPUS", 0)
	Formats:SetFontSize(20 * _1080p)
	Formats:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	Formats:SetAlignment(LUI.Alignment.Left)
	Formats:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 510, _1080p * 530)
	self:addElement(Formats)
	self.Formats = Formats

	local StatusText = LUI.UIStyledText.new()
	StatusText.id = "StatusText"
	StatusText:SetFontSize(22 * _1080p)
	StatusText:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	StatusText:SetAlignment(LUI.Alignment.Left)
	StatusText:SetStartupDelay(2000)
	StatusText:SetLineHoldTime(400)
	StatusText:SetAnimMoveTime(300)
	StatusText:SetEndDelay(1500)
	StatusText:SetCrossfadeTime(750)
	StatusText:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
	StatusText:SetMaxVisibleLines(1)
	StatusText:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 880, _1080p * 1760, _1080p * 610, _1080p * 632)
	self:addElement(StatusText)
	self.StatusText = StatusText

	self.addButtonHelperFunction = function(root)
		root:AddButtonHelperText({
			helper_text = Engine.Localize("MENU_BACK"),
			button_ref = "button_secondary",
			side = "left",
			clickable = true
		})
		root:AddButtonHelperText({
			helper_text = "OPEN MUSIC FOLDER",
			button_ref = "button_alt1",
			side = "left",
			clickable = true
		})
		root:AddButtonHelperText({
			helper_text = "REFRESH",
			button_ref = "button_alt2",
			side = "left",
			clickable = true
		})
	end
	self:addEventHandler("menu_create", self.addButtonHelperFunction)

	local BindButton = LUI.UIBindButton.new()
	BindButton.id = "BindButton"
	BindButton:addEventHandler("button_secondary", function()
		self.PlayRequestToken = self.PlayRequestToken + 1
		LUI.FlowManager.RequestLeaveMenu(self, true)
	end)
	BindButton:addEventHandler("button_alt1", function()
		if not custommusic.openfolder() then
			self.StatusText:setText("UNABLE TO OPEN MUSIC FOLDER - CHECK THE LOG", 0)
		end
	end)
	BindButton:addEventHandler("button_alt2", function()
		populateTracks(self, controllerIndex, true)
	end)
	self:addElement(BindButton)
	self.BindButton = BindButton
	self:addEventHandler("menu_close", function()
		self.PlayRequestToken = self.PlayRequestToken + 1
		log("menu closed customPlaying=" .. tostring(custommusic.isplaying()) ..
			" selected=" .. (custommusic.selectedname() ~= "" and custommusic.selectedname() or "none"))
	end)

	populateTracks(self, controllerIndex, false)
	log("menu opened controller=" .. controllerIndex .. " folder=" .. custommusic.folder())
	return self
end

MenuBuilder.registerType("IWZCustomLobbyMusicMenu", buildCustomMusicMenu)

local originalSongButtons = MenuBuilder.m_types["CPLobbySecretSongButtons"]

local stockSongLocalizationKeys = {
	[0] = "LUA_MENU_ZM_SECRET_SONG_0",
	[1] = "LUA_MENU_ZM_SECRET_SONG_1",
	[2] = "LUA_MENU_ZM_SECRET_SONG_2",
	[3] = "LUA_MENU_ZM_SECRET_SONG_3",
	[4] = "LUA_MENU_ZM_SECRET_SONG_4",
	[5] = "LUA_MENU_ZM_SECRET_SONG_5",
	[6] = "LUA_MENU_ZM_SECRET_SONG_6",
	[7] = "ZM_SPACELAND_MUSIC_UP_N_ATOMS",
	[8] = "ZM_SPACELAND_MUSIC_RACING_STRIPES",
	[9] = "ZM_SPACELAND_MUSIC_SLAPPY_TAFFY",
	[10] = "ZM_SPACELAND_MUSIC_BOMBSTOPPERS",
	[11] = "ZM_SPACELAND_MUSIC_TUFF_NUFF",
	[12] = "ZM_SPACELAND_MUSIC_BANG_BANGS",
	[13] = "LUA_MENU_ZM_DEADEYE",
	[14] = "ZM_SPACELAND_MUSIC_QUICKIES",
	[15] = "ZM_SPACELAND_MUSIC_MULE_MUNCHIES",
	[16] = "ZM_SPACELAND_MUSIC_TRAIL_BLAZERS",
	[17] = "ZM_SPACELAND_MUSIC_BLUE_BOLTS",
	[18] = "LUA_MENU_ZM_CHANGE_CHEWS",
	[19] = "LUA_MENU_ZM_MEPH_MUSIC",
	[20] = "LUA_MENU_ZM_AFTERLIFE_MUUSIC",
	[21] = "LUA_MENU_ZM_EXTINCTION_MUSIC"
}

local function getStockLobbyMusicIndex(controllerIndex)
	local selectedIndex = DataSources.frontEnd.CP.songs.lobbyMusicIndex:GetValue(controllerIndex)
	if selectedIndex == nil then
		selectedIndex = Engine.GetPlayerDataEx(
			controllerIndex,
			CoD.StatsGroup.Coop,
			"zombiePlayerLoadout",
			"lobbySong"
		)
	end

	return tonumber(selectedIndex)
end

local function updateLobbyMusicSelectionLabels(songButtons, controllerIndex)
	local customSelected = custommusic.selectedname() ~= ""
	local stockSelectedIndex = getStockLobbyMusicIndex(controllerIndex)

	for index = 0, 21 do
		local buttonName = index == 0 and "OriginalSong" or "Song" .. index
		local button = songButtons[buttonName]
		if button and button.Text then
			local label = Engine.Localize(stockSongLocalizationKeys[index])
			if not customSelected and stockSelectedIndex == index then
				label = label .. "  ^2(SELECTED)"
			end

			button.Text:setText(label, 0)
		end
	end

	if songButtons.CustomMusic and songButtons.CustomMusic.Text then
		local customLabel = "CUSTOM MUSIC"
		if customSelected then
			customLabel = customLabel .. "  ^2(SELECTED)"
		end
		songButtons.CustomMusic.Text:setText(customLabel, 0)
	end

	local selectionState = customSelected and "custom" or "stock:" .. tostring(stockSelectedIndex)
	if songButtons.IWZLastSelectionState ~= selectionState then
		songButtons.IWZLastSelectionState = selectionState
		log("lobby music row labels updated selection=" .. selectionState)
	end
end

MenuBuilder.m_types["CPLobbySecretSongButtons"] = function(menu, controller)
	local self = originalSongButtons(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()

	-- Use the same component and dimensions as the stock song entries. Insert it
	-- immediately before the stock description widget so every description stays
	-- beneath every selectable song, regardless of how many songs are unlocked.
	local CustomMusic = MenuBuilder.BuildRegisteredType("GenericButton", {
		controllerIndex = controllerIndex
	})
	CustomMusic.id = "CustomMusic"
	CustomMusic.buttonDescription = "Play audio files from the iw7-mod custom_music folder."
	CustomMusic.Text:setText("CUSTOM MUSIC", 0)
	CustomMusic:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 500, 0, _1080p * 30)
	CustomMusic:addEventHandler("button_action", function(_, event)
		LUI.FlowManager.RequestAddMenu("IWZCustomLobbyMusicMenu", true, event.controller or controllerIndex, false)
	end)
	if self.ButtonDescription then
		CustomMusic:addElementBefore(self.ButtonDescription)
	else
		self:addElement(CustomMusic)
	end
	self.CustomMusic = CustomMusic

	self:SubscribeToModel(DataSources.frontEnd.CP.songs.lobbyMusicIndex:GetModel(controllerIndex), function()
		updateLobbyMusicSelectionLabels(self, controllerIndex)
	end)
	self:SubscribeToModel(customSelectionSource:GetModel(controllerIndex), function()
		updateLobbyMusicSelectionLabels(self, controllerIndex)
	end)
	updateLobbyMusicSelectionLabels(self, controllerIndex)
	log("custom music button inserted after stock lobby music entries and before descriptions")
	return self
end

local originalLobbyMusicMenu = MenuBuilder.m_types["CPLobbyMusicMenu"]
MenuBuilder.m_types["CPLobbyMusicMenu"] = function(menu, controller)
	local self = originalLobbyMusicMenu(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()
	addHeadquartersFooter(self, controllerIndex)
	return self
end

local originalSetZombiesLobbyMusic = ACTIONS.SetZombiesLobbyMusic
ACTIONS.SetZombiesLobbyMusic = function(...)
	if custommusic.isplaying() or custommusic.selectedname() ~= "" then
		custommusic.clear()
		log("stock lobby music selected; custom playback stopped and selection cleared")
	end

	local result = originalSetZombiesLobbyMusic(...)
	publishCustomSelection(Engine.GetFirstActiveController(), false, "stock lobby music selected")
	return result
end

-- Persist the selection across frontend rebuilds, but only resume it when the
-- actual pre-game lobby exists. The previous script-load timer could start a
-- saved track on the Zombies main menu and had no matching lobby-exit boundary.
local lobbyResumeToken = 0
local originalPrivateMatchMenu = MenuBuilder.m_types["CPPrivateMatchMenu"]
MenuBuilder.m_types["CPPrivateMatchMenu"] = function(menu, controller)
	local self = originalPrivateMatchMenu(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()
	lobbyResumeToken = lobbyResumeToken + 1
	local resumeToken = lobbyResumeToken

	self:addEventHandler("menu_create", function()
		custommusic.setscene("zm_lobby")
		if custommusic.isplaying() then
			-- Rebuilding the lobby can recreate a stock voice without issuing a new
			-- music-state call. Enforce custom ownership on the restored surface.
			Engine.StopMusic()
			scheduler.once(function()
				if custommusic.isplaying() and custommusic.islobbysession() then
					Engine.StopMusic()
					log("pre-game lobby stock playback silenced after delayed surface restore")
				end
			end, 100)
			log("pre-game lobby entered; custom playback retained and stock playback silenced name=" ..
				custommusic.selectedname())
			return
		end

		if custommusic.selectedname() == "" then
			log("pre-game lobby entered; no persisted custom selection")
			return
		end

		scheduler.once(function()
			if resumeToken ~= lobbyResumeToken or custommusic.isplaying() or custommusic.selectedname() == "" then
				return
			end

			Engine.MenuDvarsSetup(controllerIndex)
			log("audio settings synchronized controller=" .. controllerIndex .. " reason=pre-game lobby resume")
			if not stopStockMusicThen(function()
				if resumeToken ~= lobbyResumeToken then
					log("persisted resume superseded before playback")
					return
				end

				if custommusic.resume() then
					log("persisted custom selection resumed in pre-game lobby name=" .. custommusic.selectedname())
				else
					restoreStockMusic("persisted custom track failed to resume")
					log("persisted custom selection could not be resumed in pre-game lobby")
				end
			end) then
				log("persisted custom selection could not claim lobby music ownership")
			end
		end, 500)
	end)

	self:addEventHandler("menu_close", function()
		lobbyResumeToken = lobbyResumeToken + 1
		log("pre-game lobby closed customPlaying=" .. tostring(custommusic.isplaying()) ..
			"; awaiting stock-state or frontend lifecycle transition")
	end)

	return self
end

log("script registered")
