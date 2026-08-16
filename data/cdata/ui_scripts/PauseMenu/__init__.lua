if Engine.InFrontend() then
	return
end

print("[IWZ][PauseMenu] script loading")

if MenuBuilder.m_types["CPPauseMenuButtons"] == nil then
	require("inGame.cp.CPPauseMenuButtons")
end

if MenuBuilder.m_types["CPPauseMenu"] == nil then
	require("inGame.cp.CPPauseMenu")
end

local originalCPPauseMenuButtons = MenuBuilder.m_types["CPPauseMenuButtons"]
local originalCPPauseMenu = MenuBuilder.m_types["CPPauseMenu"]

MenuBuilder.m_types["CPPauseMenuButtons"] = function(menu, controller)
	local self = originalCPPauseMenuButtons(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or self:getRootController()
	local restartTop = self.Tips and 80 or 40

	local RestartMatch = MenuBuilder.BuildRegisteredType("MenuButton", {
		controllerIndex = controllerIndex
	})
	RestartMatch.id = "RestartMatch"
	RestartMatch.Text:setText(ToUpperCase("Restart Match"), 0)
	RestartMatch:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * restartTop, _1080p * (restartTop + 30))
	RestartMatch:addEventHandler("button_action", function(_, event)
		local actionController = event and event.controller or controllerIndex
		print("[IWZ][PauseMenu] issuing map_restart controller=" .. tostring(actionController) .. " map=" .. tostring(Engine.GetDvarString("mapname")))
		Engine.Unpause()
		LUI.FlowManager.RequestCloseAllMenus()
		Engine.Exec("map_restart")
	end)

	RestartMatch:addElementBefore(self.LeaveGame)
	self.RestartMatch = RestartMatch

	self.LeaveGame:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 340, _1080p * (restartTop + 40), _1080p * (restartTop + 70))

	return self
end

local function applyPauseMenuLayout(self)
	if self.CPPauseMenuButtons then
		self.CPPauseMenuButtons:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 285, _1080p * 785, _1080p * 423, _1080p * 580)
	end

	if self.RankProgression then
		self.RankProgression:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 1666, _1080p * 1816, _1080p * 8, _1080p * 158)
	end
end

MenuBuilder.m_types["CPPauseMenu"] = function(menu, controller)
	local self = originalCPPauseMenu(menu, controller)

	applyPauseMenuLayout(self)
	self:addEventHandler("menu_create", function(root)
		applyPauseMenuLayout(root)
	end)

	if self.RankProgression then
		print("[IWZ][PauseMenu] controls attached and rank progression relocated")
	else
		print("[IWZ][PauseMenu] controls attached but RankProgression was unavailable")
	end

	return self
end

print("[IWZ][PauseMenu] script registered")
