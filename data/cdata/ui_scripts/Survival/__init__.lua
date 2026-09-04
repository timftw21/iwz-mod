local SURVIVAL_MODE_NAME = "SURVIVAL"
local SURVIVAL_DVAR = "iwz_survival_mode"
local SURVIVAL_BROWSE_DVAR = "iwz_survival_browse"
local ARCADE_DVAR = "iwz_gns_arcade"
local ARCADE_GAME_DVAR = "iwz_gns_arcade_game"
local ARCADE_RESULT_DVAR = "iwz_gns_arcade_result"

local survivalMaps = {
	cp_zmb = "ARCADE ATTACK!",
	cp_rave = "RAVE RAMPAGE"
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
	print("[IWZ][Survival] " .. message)
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

if MenuBuilder.m_types["MapButton"] == nil then
	require("frontEnd.MapButton")
end

if MenuBuilder.m_types["CPMaps"] == nil then
	require("frontEnd.cp.CPMaps")
end

local originalCPPrivateMatchButtons = MenuBuilder.m_types["CPPrivateMatchButtons"]
local originalCPMatchDetails = MenuBuilder.m_types["CPMatchDetails"]
local originalMapButton = MenuBuilder.m_types["MapButton"]
local originalCPMaps = MenuBuilder.m_types["CPMaps"]
local loggedDisabledSurvivalFilms = {}

local function getControllerIndex(controller)
	if type(controller) == "number" then
		return controller
	end

	if controller ~= nil then
		if controller.controllerIndex ~= nil then
			return controller.controllerIndex
		end

		if controller.controller ~= nil then
			return controller.controller
		end
	end

	-- CPMaps asks ZombiesUtils for its list without forwarding a controller.
	-- Private Zombies lobbies are rooted on local client/controller zero.
	return 0
end

local function updatePartyState()
	Engine.ExecNow("xupdatepartystate")
end

local function resetBossMode()
	Engine.ExecNow("set scr_boss_battles_enabled 0")
	Engine.NotifyServer("boss_reset", 1)

	for _, dvar in ipairs(bossDvars) do
		Engine.ExecNow("set " .. dvar .. " 0")
	end
end

local function clearArcadeMode()
	Engine.ExecNow("set " .. ARCADE_DVAR .. " 0")
	Engine.ExecNow("set " .. ARCADE_GAME_DVAR .. " 0")
	Engine.ExecNow("set " .. ARCADE_RESULT_DVAR .. " 0")
end

local function clearSurvivalMode(reason, clearBrowse)
	local wasActive = Engine.GetDvarBool(SURVIVAL_DVAR)
	local wasBrowsing = Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR)

	Engine.ExecNow("set " .. SURVIVAL_DVAR .. " 0")
	if clearBrowse then
		Engine.ExecNow("set " .. SURVIVAL_BROWSE_DVAR .. " 0")
	end

	if wasActive or wasBrowsing then
		log("cleared reason=" .. reason .. " active=" .. tostring(wasActive) .. " browse=" .. tostring(wasBrowsing))
	end
end


local function beginSurvivalBrowse(controllerIndex)
	-- CPMaps previews posters; MapButton commits the map only on selection.
	-- Keep the current lobby mode and cast intact until that same commit point.
	Engine.ExecNow("set " .. SURVIVAL_BROWSE_DVAR .. " 1")
	log("film browser opened controller=" .. controllerIndex ..
		" selectedMap=" .. Engine.GetDvarString("ui_mapname") ..
		" survival=" .. tostring(Engine.GetDvarBool(SURVIVAL_DVAR)) ..
		" cast=" .. game:getzombiescharacter() ..
		" available=cp_zmb->" .. survivalMaps.cp_zmb .. ",cp_rave->" .. survivalMaps.cp_rave)
	LUI.FlowManager.RequestAddMenu("CPMaps", true, controllerIndex)
end

MenuBuilder.m_types["MapButton"] = function(menu, controller)
	local self = originalMapButton(menu, controller)
	local controllerIndex = getControllerIndex(controller)
	local stockAction = self.Button.m_eventHandlers["button_action"]
	local stockSetText = self.Button.Text.setText
	local loggedLabelOverride = false
	assert(type(stockAction) == "function")

	local function refreshSurvivalFilmEligibility()
		local map = self:GetDataSource()
		if map == nil or map.ref == nil then
			return
		end

		local disabled = Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR) and survivalMaps[map.ref] == nil
		self.Button:SetButtonDisabled(disabled)

		if disabled and not loggedDisabledSurvivalFilms[map.ref] then
			loggedDisabledSurvivalFilms[map.ref] = true
			log("film disabled controller=" .. controllerIndex .. " map=" .. map.ref ..
				" reason=unavailable for Survival")
		end
	end

	-- MapButton's stock model subscription can publish the localized map name
	-- after our own subscription. Intercept the final label write so every
	-- asynchronous refresh is transformed while browsing Survival, without
	-- mutating the shared frontEnd.maps data source used by Choose Film.
	self.Button.Text.setText = function(element, text, duration)
		local map = self:GetDataSource()
		local survivalMapName = map ~= nil and survivalMaps[map.ref] or nil
		if survivalMapName ~= nil and Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR) then
			text = survivalMapName
			if not loggedLabelOverride then
				log("film label write intercepted controller=" .. controllerIndex ..
					" ref=" .. map.ref .. " label=" .. survivalMapName)
				loggedLabelOverride = true
			end
		end

		return stockSetText(element, text, duration)
	end

	-- Refresh on row data-source changes as before. The setText interceptor
	-- above is what guarantees later stock writes cannot restore Spaceland.
	self.Button:SubscribeToModelThroughElement(self, "name", function()
		local map = self:GetDataSource()
		local survivalMapName = map ~= nil and survivalMaps[map.ref] or nil
		if survivalMapName ~= nil and Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR) then
			self.Button.Text:setText(survivalMapName, 0)
		end

		refreshSurvivalFilmEligibility()
	end)

	-- The stock handler leaves the menu, which invalidates the row data source.
	-- Commit the mode before invoking it rather than appending an after-handler.
	self.Button:registerEventHandler("button_action", function(element, event)
		local actionController = getControllerIndex(event or controllerIndex)
		local map = self:GetDataSource()
		if map == nil or map.ref == nil then
			log("film selection deferred to stock reason=missing row data source controller=" .. actionController)
			return stockAction(element, event)
		end
		-- Stock MapButton opens the store for unowned films without selecting one.
		if not map.isOwned:GetValue(actionController) then
			return stockAction(element, event)
		end

		local mapRef = map.ref
		if Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR) and survivalMaps[mapRef] == nil then
			log("film selection rejected controller=" .. actionController .. " map=" .. mapRef ..
				" reason=disabled for Survival")
			return
		elseif Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR) then
			clearArcadeMode()
			resetBossMode()
			Engine.ExecNow("set " .. SURVIVAL_DVAR .. " 1")
			Engine.ExecNow("set " .. SURVIVAL_BROWSE_DVAR .. " 0")
			updatePartyState()
			log("selection committed controller=" .. actionController .. " map=" .. mapRef .. " mode=" .. SURVIVAL_MODE_NAME)
		else
			clearSurvivalMode("selected film " .. tostring(mapRef), true)
			updatePartyState()
		end

		return stockAction(element, event)
	end)

	return self
end

MenuBuilder.m_types["CPMaps"] = function(menu, controller)
	local self = originalCPMaps(menu, controller)

	self:addEventHandler("menu_close", function()
		if Engine.GetDvarBool(SURVIVAL_BROWSE_DVAR) then
			Engine.ExecNow("set " .. SURVIVAL_BROWSE_DVAR .. " 0")
			log("film browser canceled; lobby selection preserved map=" .. Engine.GetDvarString("ui_mapname") ..
				" survival=" .. tostring(Engine.GetDvarBool(SURVIVAL_DVAR)) ..
				" cast=" .. game:getzombiescharacter())
		end
	end)

	return self
end


MenuBuilder.m_types["CPPrivateMatchButtons"] = function(menu, controller)
	local self = originalCPPrivateMatchButtons(menu, controller)
	local controllerIndex = getControllerIndex(controller)

	local Survival = MenuBuilder.BuildRegisteredType("MenuButton", {
		controllerIndex = controllerIndex
	})
	Survival.id = "Survival"
	Survival.buttonDescription = "Select a Survival map."
	Survival.Text:setText(SURVIVAL_MODE_NAME, 0)
	Survival:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 160, _1080p * 190)
	Survival:addEventHandler("button_action", function(_, event)
		beginSurvivalBrowse(event.controller or controllerIndex)
	end)

	if self.GhostsNSkullsArcade then
		Survival:addElementBefore(self.GhostsNSkullsArcade)
		self.GhostsNSkullsArcade:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 200, _1080p * 230)
	elseif self.BossBattle then
		Survival:addElementBefore(self.BossBattle)
	else
		Survival:addElementBefore(self.Tips)
	end
	self.Survival = Survival

	if self.BossBattle then
		self.BossBattle:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 240, _1080p * 270)
	end
	self.Tips:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 280, _1080p * 310)
	self.Armory:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 320, _1080p * 350)
	self.ForSpacing:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 5, _1080p * 360, _1080p * 365)
	self.ContractsButton:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * 360, _1080p * 420)
	self.ButtonDescription:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 504, _1080p * 430, _1080p * 495)
	self:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 500, 0, _1080p * 495)

	local areWeGameHost = LUI.DataSourceInGlobalModel.new("frontEnd.lobby.areWeGameHost")
	local isGameStartRequested = LUI.DataSourceInGlobalModel.new("frontEnd.lobby.isGameStartRequested")
	local function refreshDisabledState()
		Survival:SetButtonDisabled(not areWeGameHost:GetValue(controllerIndex) or isGameStartRequested:GetValue(controllerIndex))
	end
	self:SubscribeToModel(areWeGameHost:GetModel(controllerIndex), refreshDisabledState)
	self:SubscribeToModel(isGameStartRequested:GetModel(controllerIndex), refreshDisabledState)
	refreshDisabledState()

	self.ChooseMap:addEventHandler("button_action", function()
		clearSurvivalMode("opened regular film selection", true)
	end)
	if self.GhostsNSkullsArcade then
		self.GhostsNSkullsArcade:addEventHandler("button_action", function()
			clearSurvivalMode("opened Ghosts N Skulls Arcade", true)
		end)
	end
	if self.BossBattle then
		self.BossBattle:addEventHandler("button_action", function()
			clearSurvivalMode("opened Boss Battle selection", true)
		end)
	end
	self.StartMatch:addEventHandler("button_action", function()
		if Engine.GetDvarBool(SURVIVAL_DVAR) then
			log("start match dispatched controller=" .. controllerIndex .. " map=" .. Engine.GetDvarString("ui_mapname") .. " mode=" .. SURVIVAL_MODE_NAME)
		end
	end)

	log("private-match option inserted below Choose Film")
	return self
end

MenuBuilder.m_types["CPMatchDetails"] = function(menu, controller)
	local self = originalCPMatchDetails(menu, controller)
	local controllerIndex = getControllerIndex(controller)
	local stockMapNameSetText = self.MapName.setText
	local loggedMapNameOverride = false

	-- CPMatchDetails owns a stock map-name subscription which may run after
	-- ours. Transform every final write while Survival is selected so the
	-- MAP field cannot revert to Rave in the Redwoods asynchronously.
	self.MapName.setText = function(element, text, duration)
		if Engine.GetDvarBool(SURVIVAL_DVAR) then
			local mapRef = Engine.GetDvarString("ui_mapname")
			local mapName = survivalMaps[mapRef]
			if mapName ~= nil then
				text = mapName
				if not loggedMapNameOverride then
					log("match-details map label write intercepted controller=" .. controllerIndex ..
						" ref=" .. mapRef .. " label=" .. mapName)
					loggedMapNameOverride = true
				end
			end
		end

		return stockMapNameSetText(element, text, duration)
	end

	local function refreshModeName()
		if Engine.GetDvarBool(SURVIVAL_DVAR) then
			self.GameType:setText(SURVIVAL_MODE_NAME, 0)
			local mapRef = Engine.GetDvarString("ui_mapname")
			local mapName = survivalMaps[mapRef]
			if mapName ~= nil then
				self.MapName:setText(mapName, 0)
			end
		end
	end

	self:SubscribeToModel(DataSources.frontEnd.lobby.gameTypeName:GetModel(controllerIndex), refreshModeName)
	self:SubscribeToModel(DataSources.frontEnd.lobby.mapName:GetModel(controllerIndex), refreshModeName)
	refreshModeName()
	return self
end

log("frontend integration registered maps=cp_zmb,cp_rave labels=" ..
	survivalMaps.cp_zmb .. "," .. survivalMaps.cp_rave)
