local ARCADE_MODE_NAME = "GHOSTS N SKULLS ARCADE"
local ARCADE_DVAR = "iwz_gns_arcade"
local ARCADE_GAME_DVAR = "iwz_gns_arcade_game"
local ARCADE_RESULT_DVAR = "iwz_gns_arcade_result"

local arcadeGames = {
	{
		name = "GHOSTS N SKULLS",
		map = "cp_zmb",
		icon = "iwz_gns_arcade_spaceland"
	},
	{
		name = "GHOSTS N SKULLS 2",
		map = "cp_rave",
		icon = "iwz_gns_arcade_rave"
	},
	{
		name = "SKULLBUSTER",
		map = "cp_disco",
		icon = "iwz_gns_arcade_shaolin"
	},
	{
		name = "SKULLHOP",
		map = "cp_town",
		icon = "iwz_gns_arcade_attack"
	},
	{
		name = "SKULLBREAKER",
		map = "cp_final",
		icon = "iwz_gns_arcade_beast"
	}
}

local bossDvars = {
	"scr_direct_to_grey",
	"scr_direct_to_super_slasher",
	"scr_direct_to_rat_king",
	"scr_direct_to_crab_boss",
	"scr_direct_to_rhino_fight",
	"scr_direct_to_meph_fight"
}

local function log(message)
	print("[IWZ][GhostsNSkullsArcade] " .. message)
end

if not Engine.InFrontend() then
	return
end

if MenuBuilder.m_types["CPPrivateMatchButtons"] == nil then
	require("frontEnd.cp.CPPrivateMatchButtons")
end

if MenuBuilder.m_types["CPMatchDetails"] == nil then
	require("frontEnd.cp.CPMatchDetails")
end

local originalCPPrivateMatchButtons = MenuBuilder.m_types["CPPrivateMatchButtons"]
local originalCPMatchDetails = MenuBuilder.m_types["CPMatchDetails"]

local function resetBossDvars()
	Engine.NotifyServer("boss_reset", 1)

	for _, dvar in ipairs(bossDvars) do
		Engine.ExecNow("set " .. dvar .. " 0")
	end
end

local function clearArcadeMode(reason, clearBossMode)
	if Engine.GetDvarBool(ARCADE_DVAR) then
		log("clearing mode reason=" .. reason)
	end

	Engine.ExecNow("set " .. ARCADE_DVAR .. " 0")
	Engine.ExecNow("set " .. ARCADE_GAME_DVAR .. " 0")
	Engine.ExecNow("set " .. ARCADE_RESULT_DVAR .. " 0")

	if clearBossMode then
		Engine.ExecNow("set scr_boss_battles_enabled 0")
		resetBossDvars()
	end

	Engine.ExecNow("xupdatepartystate")
end

local function isMapOwned(mapRef)
	local count = Lobby.GetMapFeederCount()
	for index = 0, count - 1 do
		if Lobby.GetMapLoadNameByIndex(index) == mapRef then
			local mapPack = Lobby.GetMapPackForMapIndex(index)
			return Engine.IsMapPackOwned(mapPack)
		end
	end

	return false
end

local function selectArcadeGame(menu, controllerIndex, gameIndex)
	local game = arcadeGames[gameIndex]
	assert(game)

	if not isMapOwned(game.map) then
		log("selection rejected controller=" .. controllerIndex .. " game=" .. game.name .. " map=" .. game.map .. " reason=map not owned")
		return
	end

	-- Boss Battle uses these same map-launch plumbing and intro-skip semantics.
	-- Clear its per-boss selectors so direct_boss_fight.gsc cannot claim the map,
	-- then mark this as the distinct arcade mode consumed by our GSC launcher.
	menu.ArcadeSelectionCommitted = true
	resetBossDvars()
	Engine.SetDvarString("ui_mapname", game.map)
	Engine.ExecNow("set scr_boss_battles_enabled 1")
	Engine.ExecNow("set " .. ARCADE_DVAR .. " 1")
	Engine.ExecNow("set " .. ARCADE_GAME_DVAR .. " " .. gameIndex)
	Engine.ExecNow("set " .. ARCADE_RESULT_DVAR .. " 0")
	Engine.SetPlayerDataEx(controllerIndex, CoD.StatsGroup.Coop, "dc", false)

	if not CONDITIONS.IsThirdGameMode(menu) then
		Engine.SetDvarString("ui_saved_mapname", game.map)
	end

	Engine.ExecNow("xupdatepartystate")
	log("selected controller=" .. controllerIndex .. " game=" .. game.name .. " map=" .. game.map .. " index=" .. gameIndex)
	LUI.FlowManager.RequestLeaveMenu(menu, true, true)
end

local function buildArcadeMenu(menu, controller)
	local self = LUI.UIHorizontalNavigator.new()
	self.id = "IWZGhostsNSkullsArcadeMenu"

	local controllerIndex = controller and controller.controllerIndex
	if controllerIndex == nil then
		controllerIndex = Engine.GetFirstActiveController()
	end
	assert(controllerIndex)

	self.ArcadeOriginalMap = Engine.GetDvarString("ui_mapname")
	self.ArcadeSelectionCommitted = false

	Engine.SetFrontEndSceneSection("zm_map_selection", 1)
	self:playSound("menu_open")
	log("menu opened controller=" .. controllerIndex)

	local ButtonHelperBar = MenuBuilder.BuildRegisteredType("ButtonHelperBar", {
		controllerIndex = controllerIndex
	})
	ButtonHelperBar.id = "ButtonHelperBar"
	ButtonHelperBar:SetAnchorsAndPosition(0, 0, 1, 0, 0, 0, _1080p * -85, 0)
	self:addElement(ButtonHelperBar)
	self.ButtonHelperBar = ButtonHelperBar

	local FriendsElement = MenuBuilder.BuildRegisteredType("online_friends_widget", {
		controllerIndex = controllerIndex
	})
	FriendsElement.id = "FriendsElement"
	FriendsElement:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
	FriendsElement:SetAlignment(LUI.Alignment.Left)
	FriendsElement:SetAnchorsAndPosition(0, 1, 1, 0, _1080p * 100, _1080p * 600, _1080p * -60, _1080p * -15)
	self:addElement(FriendsElement)
	self.FriendsElement = FriendsElement

	local MenuTitle = MenuBuilder.BuildRegisteredType("CPMenuTitle", {
		controllerIndex = controllerIndex
	})
	MenuTitle.id = "CPMenuTitle"
	MenuTitle.MenuTitle:setText(ARCADE_MODE_NAME, 0)
	MenuTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 96, _1080p * 1056, _1080p * 54, _1080p * 134)
	self:addElement(MenuTitle)
	self.CPMenuTitle = MenuTitle

	local GameButtons = LUI.UIVerticalNavigator.new()
	GameButtons.id = "GameButtons"
	GameButtons:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 630, _1080p * 200, _1080p * 390)
	self:addElement(GameButtons)
	self.GameButtons = GameButtons

	for gameIndex, game in ipairs(arcadeGames) do
		local buttonGameIndex = gameIndex
		local buttonGame = game
		local Button = MenuBuilder.BuildRegisteredType("GenericButton", {
			controllerIndex = controllerIndex
		})
		Button.id = "ArcadeGame" .. buttonGameIndex
		Button.buttonDescription = Engine.Localize("PRESENCE_" .. buttonGame.map)
		Button.Text:setText(buttonGame.name, 0)
		Button:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 500, _1080p * ((buttonGameIndex - 1) * 40), _1080p * (((buttonGameIndex - 1) * 40) + 30))
		Button:SetButtonDisabled(not isMapOwned(buttonGame.map))
		Button:addEventHandler("button_action", function(_, event)
			selectArcadeGame(self, event.controller or controllerIndex, buttonGameIndex)
		end)
		Button:addEventHandler("button_over", function()
			self.ArcadeIcon:setImage(RegisterMaterial(buttonGame.icon), 0)
			-- Match CPMapsBossButton: notify cp_frontend's zm_map_select_watcher so
			-- it swaps map_select_poster without streaming a different map zone.
			Engine.NotifyServer(buttonGame.map, 1)
			log("highlighted game=" .. buttonGame.name .. " map=" .. buttonGame.map .. " index=" .. buttonGameIndex .. " material=" .. buttonGame.icon .. " posterNotify=" .. buttonGame.map)
		end)
		GameButtons:addElement(Button)
		GameButtons["ArcadeGame" .. buttonGameIndex] = Button
	end

	local Spinner = LUI.UIImage.new()
	Spinner.id = "Spinner"
	Spinner:setImage(RegisterMaterial("zm_tix_arcane_spinner"), 0)
	Spinner:SetAlpha(0.8, 0)
	Spinner:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 100, _1080p * 612, _1080p * 456, _1080p * 968)
	self:addElement(Spinner)
	self.Spinner = Spinner

	local ArcadeIcon = LUI.UIImage.new()
	ArcadeIcon.id = "ArcadeIcon"
	ArcadeIcon:setImage(RegisterMaterial(arcadeGames[1].icon), 0)
	ArcadeIcon:SetUseAA(true)
	ArcadeIcon:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 185, _1080p * 527, _1080p * 548, _1080p * 860)
	self:addElement(ArcadeIcon)
	self.ArcadeIcon = ArcadeIcon

	self.addButtonHelperFunction = function(root)
		root:AddButtonHelperTextToElement(root.ButtonHelperBar, {
			helper_text = Engine.Localize("MENU_BACK"),
			button_ref = "button_secondary",
			side = "left",
			priority = 10,
			clickable = true
		})
		root:AddButtonHelperTextToElement(root.ButtonHelperBar, {
			helper_text = Engine.Localize("LUA_MENU_SELECT"),
			button_ref = "button_primary",
			side = "left",
			priority = -10,
			clickable = true
		})
	end
	self:addEventHandler("menu_create", self.addButtonHelperFunction)

	local BindButton = LUI.UIBindButton.new()
	BindButton.id = "BindButton"
	BindButton:addEventHandler("button_secondary", function()
		if not self.ArcadeSelectionCommitted then
			Engine.NotifyServer(self.ArcadeOriginalMap, 1)
			log("poster preview restored map=" .. self.ArcadeOriginalMap .. " reason=back notify=1")
		end

		LUI.FlowManager.RequestLeaveMenu(self, true)
	end)
	self:addElement(BindButton)
	self.BindButton = BindButton

	return self
end

MenuBuilder.registerType("IWZGhostsNSkullsArcadeMenu", buildArcadeMenu)

MenuBuilder.m_types["CPPrivateMatchButtons"] = function(menu, controller)
	local self = originalCPPrivateMatchButtons(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()

	local Arcade = MenuBuilder.BuildRegisteredType("MenuButton", {
		controllerIndex = controllerIndex
	})
	Arcade.id = "GhostsNSkullsArcade"
	Arcade.buttonDescription = "Select a Ghosts N Skulls arcade game."
	Arcade.Text:setText(ARCADE_MODE_NAME, 0)
	Arcade:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 160, _1080p * 190)
	Arcade:addEventHandler("button_action", function(_, event)
		LUI.FlowManager.RequestAddMenu("IWZGhostsNSkullsArcadeMenu", true, event.controller or controllerIndex)
	end)

	if self.BossBattle then
		Arcade:addElementBefore(self.BossBattle)
		self.BossBattle:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 200, _1080p * 230)
	else
		Arcade:addElementBefore(self.Tips)
	end
	self.GhostsNSkullsArcade = Arcade

	self.Tips:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 240, _1080p * 270)
	self.Armory:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 280, _1080p * 310)
	self.ForSpacing:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 5, _1080p * 320, _1080p * 325)
	self.ContractsButton:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 320, _1080p * 380)
	self.ButtonDescription:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 504, _1080p * 390, _1080p * 455)
	self:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 500, 0, _1080p * 455)

	local areWeGameHost = LUI.DataSourceInGlobalModel.new("frontEnd.lobby.areWeGameHost")
	local isGameStartRequested = LUI.DataSourceInGlobalModel.new("frontEnd.lobby.isGameStartRequested")
	local function refreshDisabledState()
		Arcade:SetButtonDisabled(not areWeGameHost:GetValue(controllerIndex) or isGameStartRequested:GetValue(controllerIndex))
	end
	self:SubscribeToModel(areWeGameHost:GetModel(controllerIndex), refreshDisabledState)
	self:SubscribeToModel(isGameStartRequested:GetModel(controllerIndex), refreshDisabledState)
	refreshDisabledState()

	self.ChooseMap:addEventHandler("button_action", function()
		clearArcadeMode("opened regular map selection", true)
	end)
	self.StartMatch:addEventHandler("button_action", function()
		if Engine.GetDvarBool(ARCADE_DVAR) then
			log("start match dispatched controller=" .. controllerIndex .. " selection=" .. Engine.GetDvarInt(ARCADE_GAME_DVAR) .. " map=" .. Engine.GetDvarString("ui_mapname"))
		end
	end)
	if self.BossBattle then
		self.BossBattle:addEventHandler("button_action", function()
			clearArcadeMode("opened boss battle selection", false)
		end)
	end

	log("private-match option inserted before Boss Battles")
	return self
end

MenuBuilder.m_types["CPMatchDetails"] = function(menu, controller)
	local self = originalCPMatchDetails(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or Engine.GetFirstActiveController()

	local function refreshModeName()
		if Engine.GetDvarBool(ARCADE_DVAR) then
			self.GameType:setText(ARCADE_MODE_NAME, 0)
		end
	end

	self:SubscribeToModel(DataSources.frontEnd.lobby.gameTypeName:GetModel(controllerIndex), refreshModeName)
	self:SubscribeToModel(DataSources.frontEnd.lobby.mapName:GetModel(controllerIndex), refreshModeName)
	refreshModeName()
	return self
end

log("frontend integration registered artworkCount=" .. #arcadeGames)
