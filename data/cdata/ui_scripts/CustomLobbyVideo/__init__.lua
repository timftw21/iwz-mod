if not Engine.InFrontend() then
	return
end

if MenuBuilder.m_types["HeadquartersCustomizationButtons"] == nil then
	require("frontEnd.HeadquartersCustomizationButtons")
end

local MODEL = "frontEnd.IWZCustomVideo"
local function log(message)
	print("[IWZ][CustomVideo] " .. message)
end

MenuBuilder.registerType("IWZCustomVideoButton", function(_, controller)
	local index = controller.controllerIndex
	local button = MenuBuilder.BuildRegisteredType("GenericButton", controller)
	button.Text:SubscribeToModelThroughElement(button, "label", function()
		local source = button:GetDataSource()
		local label = source and source.label and source.label:GetValue(index)
		if label ~= nil then button.Text:setText(ToUpperCase(label), 0) end
	end)
	button:addEventHandler("button_action", function(element)
		local source = element:GetDataSource()
		if source then source.select() end
	end)
	button:addEventHandler("button_over", function(element)
		local source = element:GetDataSource()
		if source then source.hover() end
	end)
	return button
end)

local function text(menu, id, value, x, y, width, size)
	local element = LUI.UIStyledText.new()
	element.id = id
	element:setText(value, 0)
	element:SetFontSize(size * _1080p)
	element:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	element:SetAlignment(LUI.Alignment.Left)
	element:SetStartupDelay(1800)
	element:SetLineHoldTime(400)
	element:SetAnimMoveTime(300)
	element:SetEndDelay(1500)
	element:SetCrossfadeTime(750)
	element:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
	element:SetMaxVisibleLines(1)
	element:SetAnchorsAndPosition(0, 1, 0, 1, x * _1080p, (x + width) * _1080p, y * _1080p, (y + size) * _1080p)
	menu:addElement(element)
	menu[id] = element
	return element
end

local function refreshStatus(menu, controllerIndex)
	local selected = customvideo.selected()
	if menu.LastSelected ~= selected then
		menu.LastSelected = selected
		for _, entry in ipairs(menu.VideoRows or {}) do
			local label = entry.name .. (entry.id == selected and "  ^2(SELECTED)" or "")
			DataModel.SetModelValue(entry.label:GetModel(controllerIndex), label)
		end
	end
	local status = customvideo.status()
	if menu.LastStatus ~= status then
		menu.LastStatus = status
		local notice = ""
		if status:find("Unable to play:", 1, true) == 1 then
			notice = "VIDEO UNAVAILABLE. ORIGINAL MOVIE RESTORED."
		elseif status:find("Loading ", 1, true) == 1 then
			notice = "LOADING..."
		end
		menu.Status:setText(notice, 0)
	end
end

local function populate(menu, controllerIndex)
	customvideo.rescan()
	WipeGlobalModelsAtPath(MODEL)
	local entries = {{ id = "", name = "ORIGINAL MOVIE", extension = "" }}
	for _, entry in ipairs(customvideo.list()) do entries[#entries + 1] = entry end
	menu.VideoRows = entries
	menu.LastSelected = nil
	for index, entry in ipairs(entries) do
		entry.label = LUI.DataSourceInGlobalModel.new(MODEL .. ".rows." .. index, entry.name)
	end
	local source = LUI.DataSourceFromList.new(#entries)
	source.MakeDataSourceAtIndex = function(_, index)
		local entry = entries[index + 1]
		return {
			label = entry.label,
			select = function()
				if entry.id == "" then
					customvideo.clear()
				elseif not customvideo.play(entry.id) then
					menu.Status:setText("FILE UNAVAILABLE. REFRESH TO TRY AGAIN.", 0)
					return
				end
				refreshStatus(menu, controllerIndex)
				log("selection=" .. (entry.id == "" and "original" or entry.id))
			end,
			hover = function()
				menu.VideoName:setText(ToUpperCase(entry.name), 0)
				menu.Format:setText(entry.id == "" and "" or ToUpperCase(entry.extension) .. " VIDEO", 0)
			end
		}
	end
	menu.VideoList:SetGridDataSource(source, controllerIndex)
	menu.Empty:SetAlpha(#entries == 1 and 1 or 0, 0)
	refreshStatus(menu, controllerIndex)
end

MenuBuilder.registerType("IWZCustomLobbyVideoMenu", function(_, controller)
	local self = LUI.UIElement.new()
	self.id = "IWZCustomLobbyVideoMenu"
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()
	local options = {controllerIndex = controllerIndex}
	self:playSound("menu_open")

	local title = MenuBuilder.BuildRegisteredType("CPMenuTitle", options)
	title.MenuTitle:setText("MOVIE SCREEN", 0)
	title:SetAnchorsAndPosition(0, 1, 0, 1, 96 * _1080p, 1056 * _1080p, 54 * _1080p, 134 * _1080p)
	self:addElement(title)
	local footer = MenuBuilder.BuildRegisteredType("ButtonHelperBar", options)
	footer:SetAnchorsAndPosition(0, 0, 1, 0, 0, 0, -85 * _1080p, 0)
	self:addElement(footer)
	self.ButtonHelperBar = footer
	local social = MenuBuilder.BuildRegisteredType("SocialFeed", options)
	social:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920 * _1080p, 965 * _1080p, 995 * _1080p)
	self:addElement(social)

	local grid = LUI.UIDataSourceGrid.new(nil, {
		maxVisibleColumns = 1, maxVisibleRows = 15, controllerIndex = controllerIndex,
		buildChild = function() return MenuBuilder.BuildRegisteredType("IWZCustomVideoButton", options) end,
		wrapX = true, wrapY = true, spacingX = 10 * _1080p, spacingY = 10 * _1080p,
		columnWidth = 600 * _1080p, rowHeight = 30 * _1080p,
		scrollingThresholdX = 1, scrollingThresholdY = 1, adjustSizeToContent = false,
		horizontalAlignment = LUI.Alignment.Left, verticalAlignment = LUI.Alignment.Top,
		springCoefficient = 600, maxVelocity = 5000
	})
	grid.id = "VideoList"
	grid:SetAnchorsAndPosition(0, 1, 0, 1, 130 * _1080p, 730 * _1080p, 216 * _1080p, 816 * _1080p)
	self:addElement(grid)
	self.VideoList = grid
	local up = MenuBuilder.BuildRegisteredType("ArrowUp", options)
	up:SetAnchorsAndPosition(0, 1, 0, 1, 487 * _1080p, 507 * _1080p, 870 * _1080p, 910 * _1080p)
	self:addElement(up)
	local down = MenuBuilder.BuildRegisteredType("ArrowDown", options)
	down:SetAnchorsAndPosition(0, 1, 0, 1, 322 * _1080p, 342 * _1080p, 870 * _1080p, 910 * _1080p)
	self:addElement(down)
	local numbers = text(self, "Numbers", "", 342, 878, 145, 24)
	numbers:SetAlignment(LUI.Alignment.Center)
	grid:AddArrow(up)
	grid:AddArrow(down)
	grid:AddItemNumbers(numbers)

	text(self, "InfoTitle", "CUSTOM LOBBY VIDEO", 880, 216, 880, 30):SetFont(FONTS.GetFont(FONTS.MainBold.File))
	text(self, "VideoName", "SELECT A VIDEO", 880, 280, 880, 24)
	text(self, "Format", "", 880, 316, 880, 20):SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	text(self, "FolderTitle", "FOLDER", 880, 380, 880, 20)
	text(self, "Folder", customvideo.folder(), 880, 414, 880, 20):SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	text(self, "FormatsTitle", "SUPPORTED FORMATS", 880, 476, 880, 20)
	text(self, "Formats", "MP4, M4V, MKV, WEBM, MOV, AVI, WMV, MPG, MPEG, TS, M2TS", 880, 510, 880, 20):SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	text(self, "Playback", "LOOPS SILENTLY IN THE LOBBY. MUSIC CONTINUES.", 880, 554, 880, 20)
	text(self, "Status", "", 880, 610, 880, 22)
	text(self, "Empty", "ADD VIDEOS TO THE FOLDER, THEN REFRESH.", 880, 654, 880, 20)

	self:addEventHandler("menu_create", function(root)
		for _, helper in ipairs({{"BACK", "button_secondary"}, {"OPEN FOLDER", "button_alt1"}, {"REFRESH", "button_alt2"}}) do
			root:AddButtonHelperText({helper_text = helper[1], button_ref = helper[2], side = "left", clickable = true})
		end
	end)
	local bind = LUI.UIBindButton.new()
	bind:addEventHandler("button_secondary", function() LUI.FlowManager.RequestLeaveMenu(self, true) end)
	bind:addEventHandler("button_alt1", function()
		if not customvideo.openfolder() then self.Status:setText("UNABLE TO OPEN FOLDER.", 0) end
	end)
	bind:addEventHandler("button_alt2", function() populate(self, controllerIndex) end)
	self:addElement(bind)
	self:registerEventHandler("iwz_video_status", function() refreshStatus(self, controllerIndex) end)
	self:addElement(LUI.UITimer.new(nil, {
		interval = 250, event = "iwz_video_status", eventTarget = self, disposable = false, broadcastToRoot = false
	}))
	populate(self, controllerIndex)
	log("menu opened; music-style help panel; status shown only for loading or errors")
	return self
end)

local originalBarracks = MenuBuilder.m_types["HeadquartersCustomizationButtons"]
MenuBuilder.m_types["HeadquartersCustomizationButtons"] = function(menu, controller)
	local self = originalBarracks(menu, controller)
	if not Engine.IsAliensMode() then return self end
	local index = controller and controller.controllerIndex or Engine.GetFirstActiveController()
	local movie = MenuBuilder.BuildRegisteredType("GenericButton", {controllerIndex = index})
	movie.id = "MovieScreen"
	movie.Text:setText("MOVIE SCREEN", 0)
	movie.buttonDescription = "Choose your lobby movie."
	movie:SetAnchorsAndPosition(0, 1, 0, 1, 0, 500 * _1080p, 179 * _1080p, 209 * _1080p)
	movie:addElementAfter(self.LobbyMusicButton)
	self.MovieScreen = movie
	movie:addEventHandler("button_action", function(_, event)
		ACTIONS.OpenMenu("IWZCustomLobbyVideoMenu", true, event.controller or index)
	end)
	log("movie screen option added beneath Lobby Music in Barracks")
	return self
end

log("Barracks movie screen menu registered")
