if not Engine.InFrontend() then
	return
end

if MenuBuilder.m_types["MapButton"] == nil then
	require("frontEnd.MapButton")
end
if MenuBuilder.m_types["CPMaps"] == nil then
	require("frontEnd.cp.CPMaps")
end

local mapsByName = {}
local stockGetMaps = ZombiesUtils.GetMapsDataSources
ZombiesUtils.GetMapsDataSources = function(path, controller, bossMode)
	local stock = stockGetMaps(path, controller, bossMode)
	if path == "frontEnd.maps" then mapsByName = {} end
	-- Barracks and boss battles only have records for the official films.
	if path ~= "frontEnd.maps" or bossMode ~= nil or not Engine.IsAliensMode() or
		Engine.GetDvarBool("iwz_survival_browse") then
		return stock
	end

	local maps = io.usermaps()
	for _, map in ipairs(maps) do
		mapsByName[map.name] = map
	end
	if #maps == 0 then return stock end
	local stockCount = stock:GetCountValue(controller)
	local source = LUI.DataSourceFromList.new(stockCount + #maps)
	source.MakeDataSourceAtIndex = function(_, index)
		if index < stockCount then
			return stock:GetDataSourceAtIndex(index, controller)
		end
		local map = maps[index - stockCount + 1]
		local modelPath = path .. ".custom." .. map.name
		local function model(field, value)
			return LUI.DataSourceInGlobalModel.new(modelPath .. "." .. field, value)
		end
		-- Do not ask the stock DDL for a custom map's stats: those fields do not exist.
		return {
			ref = map.name,
			name = model("name", map.title .. " [CUSTOM]"),
			desc = model("desc", map.description),
			image = model("image", "white"),
			isOwned = model("isOwned", true),
			listIndex = index,
			isCustom = true
		}
	end
	source.GetDefaultFocusIndex = function()
		local selected = Engine.GetDvarString("ui_mapname")
		for index, map in ipairs(maps) do
			if map.name == selected then return stockCount + index - 1 end
		end
		return stock:GetDefaultFocusIndex()
	end
	print("[IWZ][Usermaps] film picker stock=" .. stockCount .. " custom=" .. #maps)
	return source
end

local stockMapButton = MenuBuilder.m_types["MapButton"]
MenuBuilder.m_types["MapButton"] = function(menu, controller)
	local self = stockMapButton(menu, controller)
	self.Button:addEventHandler("button_over", function()
		local data = self:GetDataSource()
		local currentMenu = self:GetCurrentMenu()
		if currentMenu and currentMenu.id == "CPMaps" then
			currentMenu:processEvent({name = "iwz_custom_map_preview", map = data and mapsByName[data.ref]})
		end
	end)
	local stockAction = self.Button.m_eventHandlers["button_action"]
	self.Button:registerEventHandler("button_action", function(element, event)
		local data = self:GetDataSource()
		if data and data.isCustom then
			for _, dvar in ipairs({"iwz_survival_mode", "iwz_survival_browse", "iwz_gns_arcade",
				"iwz_gns_arcade_game", "iwz_gns_arcade_result"}) do
				Engine.ExecNow("set " .. dvar .. " 0")
			end
			print("[IWZ][Usermaps] selected map=" .. data.ref)
		end
		return stockAction(element, event)
	end)
	return self
end

local stockCPMaps = MenuBuilder.m_types["CPMaps"]
MenuBuilder.m_types["CPMaps"] = function(menu, controller)
	local self = stockCPMaps(menu, controller)
	local preview = LUI.UIElement.new()
	preview:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 830, _1080p * 1730, _1080p * 220, _1080p * 740)
	preview:SetAlpha(0, 0)
	local background = LUI.UIImage.new()
	background:setImage(RegisterMaterial("white"), 0)
	background:SetRGBFromInt(0, 0)
	background:SetAlpha(0.9, 0)
	preview:addElement(background)
	local title = LUI.UIText.new()
	title:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	title:SetFontSize(36 * _1080p)
	title:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 30, _1080p * -30, _1080p * 30, _1080p * 70)
	preview:addElement(title)
	local description = LUI.UIText.new()
	description:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	description:SetFontSize(24 * _1080p)
	description:SetAlignment(LUI.Alignment.Left)
	description:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 30, _1080p * -30, _1080p * 110, _1080p * 142)
	preview:addElement(description)
	self:addElement(preview)
	self:registerEventHandler("iwz_custom_map_preview", function(_, event)
		preview:SetAlpha(event.map and 1 or 0, 0)
		if event.map then
			title:setText(event.map.title, 0)
			local author = event.map.author ~= "" and ("\n\nBy " .. event.map.author) or ""
			description:setText(event.map.description .. author, 0)
		end
	end)
	self:processEvent({name = "iwz_custom_map_preview", map = mapsByName[Engine.GetDvarString("ui_mapname")]})
	return self
end

print("[IWZ][Usermaps] custom Zombies film picker registered")
