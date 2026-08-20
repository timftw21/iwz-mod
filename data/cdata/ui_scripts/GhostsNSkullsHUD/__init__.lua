if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

local function log(message)
	print("[IWZ][GhostsNSkullsHUD] " .. message)
end

-- Recovered from the stock ghostHUDContainer/skullHUDContainer LUI. Every
-- child is authored in a 1744-wide safe-area coordinate system (center 872),
-- but the stock rectangles omit the safe area's 88-pixel screen origin.
-- LUI.HUD.AddWidgetInternal uses the constructed root rectangle only to size
-- its wrapper, then resets the widget itself to 0..0 on every edge. Therefore
-- a parent offset is discarded; the persistent fix belongs in the three child
-- rectangles. Splitscreen has separate authored coordinates and gets no shift.
local FULLSCREEN_WIDTH = 1920
local SAFE_AREA_WIDTH = 1744
local SINGLESCREEN_X_OFFSET = (FULLSCREEN_WIDTH - SAFE_AREA_WIDTH) / 2
local CENTER_GROUP_LEFT = 572
local CENTER_GROUP_RIGHT = 1172

local containerSpecs = {
	ghostHUDContainer = {
		destroyedType = "ghostArcadeGameSkullDestroyed",
		escapedType = "ghostArcadeGameWidget",
		escapedLeft = 1308,
		escapedRight = 1709,
		entanglerType = "entanglerWidget"
	},
	skullHUDContainer = {
		destroyedType = "skullDestroyedWidget",
		escapedType = "skullStrikesWidget",
		escapedLeft = 1359,
		escapedRight = 1760,
		entanglerType = "skullEntanglerWidget"
	}
}

local containerBuildCounts = {}

local function buildGhostHUDContainer(menu, controller, typeName)
	local spec = containerSpecs[typeName]
	local self = LUI.UIElement.new()
	self:SetAnchorsAndPosition(0, 1, 0, 1, 0, FULLSCREEN_WIDTH * _1080p, 0, 1080 * _1080p)
	self.id = typeName
	self._animationSets = {}
	self._sequences = {}

	local controllerIndex = controller and controller.controllerIndex
	if not controllerIndex and not Engine.InFrontend() then
		controllerIndex = self:getRootController()
	end
	assert(controllerIndex)

	local isSplitscreen = CONDITIONS.IsSplitscreen(self)
	local horizontalOffset = isSplitscreen and 0 or SINGLESCREEN_X_OFFSET

	local ghostArcadeGameSkullDestroyed = MenuBuilder.BuildRegisteredType(spec.destroyedType, {
		controllerIndex = controllerIndex
	})
	ghostArcadeGameSkullDestroyed.id = "ghostArcadeGameSkullDestroyed"
	ghostArcadeGameSkullDestroyed:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * (27 + horizontalOffset), _1080p * (302 + horizontalOffset),
		_1080p * 799, _1080p * 949)
	self:addElement(ghostArcadeGameSkullDestroyed)
	self.ghostArcadeGameSkullDestroyed = ghostArcadeGameSkullDestroyed

	local ghostArcadeGameWidget = MenuBuilder.BuildRegisteredType(spec.escapedType, {
		controllerIndex = controllerIndex
	})
	ghostArcadeGameWidget.id = "ghostArcadeGameWidget"
	ghostArcadeGameWidget:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * (spec.escapedLeft + horizontalOffset),
		_1080p * (spec.escapedRight + horizontalOffset),
		_1080p * 847, _1080p * 979)
	self:addElement(ghostArcadeGameWidget)
	self.ghostArcadeGameWidget = ghostArcadeGameWidget

	local entanglerWidget = MenuBuilder.BuildRegisteredType(spec.entanglerType, {
		controllerIndex = controllerIndex
	})
	entanglerWidget.id = "entanglerWidget"
	entanglerWidget:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * (CENTER_GROUP_LEFT + horizontalOffset),
		_1080p * (CENTER_GROUP_RIGHT + horizontalOffset),
		_1080p * 889, _1080p * 949)
	self:addElement(entanglerWidget)
	self.entanglerWidget = entanglerWidget

	self._animationSets.DefaultAnimationSet = function()
		self._sequences.DefaultSequence = function()
		end

		entanglerWidget:RegisterAnimationSequence("initial", {
			{
				function()
					return self.entanglerWidget:SetAlpha(0, 0)
				end
			}
		})
		self._sequences.initial = function()
			entanglerWidget:AnimateSequence("initial")
		end

		entanglerWidget:RegisterAnimationSequence("display", {
			{
				function()
					return self.entanglerWidget:SetAlpha(1, 0)
				end
			}
		})
		self._sequences.display = function()
			entanglerWidget:AnimateSequence("display")
		end

		ghostArcadeGameWidget:RegisterAnimationSequence("hideEscapeWidget", {
			{
				function()
					return self.ghostArcadeGameWidget:SetAlpha(0, 0)
				end
			}
		})
		self._sequences.hideEscapeWidget = function()
			ghostArcadeGameWidget:AnimateSequence("hideEscapeWidget")
		end

		ghostArcadeGameSkullDestroyed:RegisterAnimationSequence("splitscreen", {
			{
				function()
					return self.ghostArcadeGameSkullDestroyed:SetAnchorsAndPosition(0, 1, 0, 1,
						_1080p * 44, _1080p * 319, _1080p * 416, _1080p * 566, 0)
				end
			}
		})
		ghostArcadeGameWidget:RegisterAnimationSequence("splitscreen", {
			{
				function()
					return self.ghostArcadeGameWidget:SetAnchorsAndPosition(0, 1, 0, 1,
						_1080p * 1482, _1080p * 1883, _1080p * 464, _1080p * 596, 0)
				end
			}
		})
		entanglerWidget:RegisterAnimationSequence("splitscreen", {
			{
				function()
					return self.entanglerWidget:SetAlpha(1, 0)
				end
			},
			{
				function()
					return self.entanglerWidget:SetAnchorsAndPosition(0, 1, 0, 1,
						_1080p * 712, _1080p * 1312, _1080p * 506, _1080p * 566, 0)
				end
			}
		})
		self._sequences.splitscreen = function()
			ghostArcadeGameSkullDestroyed:AnimateSequence("splitscreen")
			ghostArcadeGameWidget:AnimateSequence("splitscreen")
			entanglerWidget:AnimateSequence("splitscreen")
		end
	end

	self._animationSets.DefaultAnimationSet()
	entanglerWidget:SubscribeToModel(DataSources.inGame.CP.zombies.ghostArcadeIsActive:GetModel(controllerIndex), function()
		local isActive = DataSources.inGame.CP.zombies.ghostArcadeIsActive:GetValue(controllerIndex)
		if isActive ~= nil and isActive == true and not CONDITIONS.IsSplitscreen(self) then
			ACTIONS.AnimateSequence(self, "display")
		end
		if isActive ~= nil and isActive == false and not CONDITIONS.IsSplitscreen(self) then
			ACTIONS.AnimateSequence(self, "initial")
		end
		if isActive ~= nil and isActive == true and CONDITIONS.IsSplitscreen(self) then
			ACTIONS.AnimateSequence(self, "splitscreen")
		end
		if isActive ~= nil and isActive == false and CONDITIONS.IsSplitscreen(self) then
			ACTIONS.AnimateSequence(self, "initial")
		end
	end)
	ACTIONS.AnimateSequence(self, "initial")

	containerBuildCounts[typeName] = (containerBuildCounts[typeName] or 0) + 1
	if containerBuildCounts[typeName] == 1 then
		log("built offset child layout type=" .. typeName ..
			" splitscreen=" .. tostring(isSplitscreen) ..
			" horizontalOffset=" .. tostring(horizontalOffset) ..
			" localCenter=872 screenCenter=" .. tostring(horizontalOffset + 872) ..
			" centerScreenBounds=" .. tostring(horizontalOffset + CENTER_GROUP_LEFT) .. ".." ..
				tostring(horizontalOffset + CENTER_GROUP_RIGHT) ..
			" destroyedScreenBounds=" .. tostring(horizontalOffset + 27) .. ".." ..
				tostring(horizontalOffset + 302) ..
			" escapedScreenBounds=" .. tostring(horizontalOffset + spec.escapedLeft) .. ".." ..
				tostring(horizontalOffset + spec.escapedRight))
	end

	return self
end

local entanglerBuildCount = 0

local function buildEntanglerWidget(menu, controller)
	local self = LUI.UIElement.new()
	self:SetAnchorsAndPosition(0, 1, 0, 1, 0, 600 * _1080p, 0, 60 * _1080p)
	self.id = "entanglerWidget"
	self._animationSets = {}
	self._sequences = {}

	local controllerIndex = controller and controller.controllerIndex
	if not controllerIndex and not Engine.InFrontend() then
		controllerIndex = self:getRootController()
	end
	assert(controllerIndex)

	local background = LUI.UIImage.new()
	background.id = "background"
	background:SetRGBFromInt(787717, 0)
	background:SetAlpha(0.2, 0)
	background:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * -30, _1080p * 630, 0, _1080p * 60)
	self:addElement(background)
	self.background = background

	local progressBarBorder = LUI.UIImage.new()
	progressBarBorder.id = "progressBarBorder"
	progressBarBorder:SetRGBFromInt(2236448, 0)
	progressBarBorder:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, _1080p * 32, _1080p * 53.11)
	progressBarBorder:BindAlphaToModel(DataSources.inGame.CP.zombies.ghost.entanglerWidgetAlpha:GetModel(controllerIndex))
	self:addElement(progressBarBorder)
	self.progressBarBorder = progressBarBorder

	local progressBar = LUI.UIImage.new()
	progressBar.id = "progressBar"
	progressBar:SetAnchors(0, 1, 0, 1, 0)
	progressBar:SetLeft(0, 0)
	progressBar:SetTop(_1080p * 27.11, 0)
	progressBar:SetBottom(_1080p * 59.11, 0)
	progressBar:setImage(RegisterMaterial("cp_zmb_ghost_skull_fill_bar"), 0)
	progressBar:SubscribeToModel(DataSources.inGame.CP.zombies.ghost.entanglerProgress:GetModel(controllerIndex), function()
		local progress = DataSources.inGame.CP.zombies.ghost.entanglerProgress:GetValue(controllerIndex)
		if progress ~= nil then
			progressBar:SetRight(_1080p * Multiply(progress, 600), 0)
		end
	end)
	progressBar:BindAlphaToModel(DataSources.inGame.CP.zombies.ghost.entanglerWidgetAlpha:GetModel(controllerIndex))
	self:addElement(progressBar)
	self.progressBar = progressBar

	local stockInstruction = Engine.Localize("CP_ZMB_GHOST_KILL_GHOST")
	local correctedInstruction, replacementCount = string.gsub(stockInstruction, "  ", " ")
	local deploySCU = LUI.UIText.new()
	deploySCU.id = "deploySCU"
	deploySCU:setText(correctedInstruction, 0)
	deploySCU:SetFontSize(18 * _1080p)
	deploySCU:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	deploySCU:SetAlignment(LUI.Alignment.Center)
	deploySCU:SetAnchorsAndPosition(0, 0, 0, 1,
		_1080p * -30, _1080p * 30, 0, _1080p * 18)
	deploySCU:BindAlphaToModel(DataSources.inGame.CP.zombies.ghostArcadeInstructionAlpha:GetModel(controllerIndex))
	self:addElement(deploySCU)
	self.deploySCU = deploySCU

	local tracking = LUI.UIText.new()
	tracking.id = "tracking"
	tracking:setText(Engine.Localize("CP_ZMB_GHOST_TRACKING"), 0)
	tracking:SetFontSize(18 * _1080p)
	tracking:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	tracking:SetAlignment(LUI.Alignment.Left)
	tracking:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * 274, _1080p * 351, _1080p * 32, _1080p * 49)
	self:addElement(tracking)
	self.tracking = tracking

	local Objective = LUI.UIText.new()
	Objective.id = "Objective"
	Objective:setText(Engine.Localize("CP_ZMB_GHOST_OBJECTIVE"), 0)
	Objective:SetFontSize(24 * _1080p)
	Objective:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	Objective:SetAlignment(LUI.Alignment.Left)
	Objective:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * 99, _1080p * 526, _1080p * -34, _1080p * -10)
	Objective:BindAlphaToModel(DataSources.inGame.CP.zombies.ghostArcadeObjectiveAlpha:GetModel(controllerIndex))
	self:addElement(Objective)
	self.Objective = Objective

	local oneSkullEscaped = LUI.UIText.new()
	oneSkullEscaped.id = "oneSkullEscaped"
	oneSkullEscaped:SetRGBFromInt(16451592, 0)
	oneSkullEscaped:setText(Engine.Localize("CP_ZMB_GHOST_ONE_SKULL_ESCAPED"), 0)
	oneSkullEscaped:SetFontSize(24 * _1080p)
	oneSkullEscaped:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	oneSkullEscaped:SetAlignment(LUI.Alignment.Left)
	oneSkullEscaped:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * 178.37, _1080p * 421.63, _1080p * -33, _1080p * -9)
	oneSkullEscaped:BindAlphaToModel(DataSources.inGame.CP.zombies.ghostArcadeOneSkullEscapedAlpha:GetModel(controllerIndex))
	self:addElement(oneSkullEscaped)
	self.oneSkullEscaped = oneSkullEscaped

	local twoSkullsEscaped = LUI.UIText.new()
	twoSkullsEscaped.id = "twoSkullsEscaped"
	twoSkullsEscaped:SetRGBFromInt(16516871, 0)
	twoSkullsEscaped:setText(Engine.Localize("CP_ZMB_GHOST_TWO_SKULLS_ESCAPED"), 0)
	twoSkullsEscaped:SetFontSize(24 * _1080p)
	twoSkullsEscaped:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	twoSkullsEscaped:SetAlignment(LUI.Alignment.Left)
	twoSkullsEscaped:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * 179.5, _1080p * 445.5, _1080p * -34, _1080p * -10)
	twoSkullsEscaped:BindAlphaToModel(DataSources.inGame.CP.zombies.ghostArcadeTwoSkullsEscapedAlpha:GetModel(controllerIndex))
	self:addElement(twoSkullsEscaped)
	self.twoSkullsEscaped = twoSkullsEscaped

	local threeSkullsEscaped = LUI.UIText.new()
	threeSkullsEscaped.id = "threeSkullsEscaped"
	threeSkullsEscaped:SetRGBFromInt(16318721, 0)
	threeSkullsEscaped:setText(Engine.Localize("CP_ZMB_GHOST_THREE_SKULLS_ESCAPED"), 0)
	threeSkullsEscaped:SetFontSize(24 * _1080p)
	threeSkullsEscaped:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
	threeSkullsEscaped:SetAlignment(LUI.Alignment.Left)
	threeSkullsEscaped:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * 179, _1080p * 445, _1080p * -34, _1080p * -10)
	threeSkullsEscaped:BindAlphaToModel(DataSources.inGame.CP.zombies.ghostArcadeThreeSkullsEscapedAlpha:GetModel(controllerIndex))
	self:addElement(threeSkullsEscaped)
	self.threeSkullsEscaped = threeSkullsEscaped

	self._animationSets.DefaultAnimationSet = function()
		self._sequences.DefaultSequence = function()
		end

		tracking:RegisterAnimationSequence("flashing", {
			{
				function()
					return self.tracking:SetAlpha(1, 200)
				end,
				function()
					return self.tracking:SetAlpha(0, 800)
				end
			}
		})
		self._sequences.flashing = function()
			tracking:AnimateLoop("flashing")
		end

		tracking:RegisterAnimationSequence("endFlashing", {
			{
				function()
					return self.tracking:SetAlpha(0, 0)
				end,
				function()
					return self.tracking:SetAlpha(0, 50)
				end
			}
		})
		self._sequences.endFlashing = function()
			tracking:AnimateSequence("endFlashing")
		end

		self._sequences.hideAll = function()
			threeSkullsEscaped:AnimateSequence("hideAll")
		end

		deploySCU:RegisterAnimationSequence("cpFinal", {
			{
				function()
					return self.deploySCU:setText(Engine.Localize("CP_FINAL_SKULL_DEPLOY"), 0)
				end
			}
		})
		self._sequences.cpFinal = function()
			deploySCU:AnimateSequence("cpFinal")
		end
	end

	self._animationSets.DefaultAnimationSet()
	self:SubscribeToModel(DataSources.inGame.CP.zombies.ghost.entanglerFlashingActive:GetModel(controllerIndex), function()
		local flashingActive = DataSources.inGame.CP.zombies.ghost.entanglerFlashingActive:GetValue(controllerIndex)
		if flashingActive ~= nil and flashingActive == 1 then
			ACTIONS.AnimateSequence(self, "flashing")
		end
		if flashingActive ~= nil and flashingActive == 0 then
			ACTIONS.AnimateSequence(self, "endFlashing")
		end
	end)

	if CONDITIONS.IsDLC4(self) then
		-- Skullbreaker has a separate, substantially longer instruction. Preserve
		-- its stock text geometry and backing instead of applying this base-game fix.
		background:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 600, 0, _1080p * 60)
		deploySCU:SetAnchorsAndPosition(0, 0, 0, 1,
			_1080p * -51.5, _1080p * 76.5, 0, _1080p * 18)
		ACTIONS.AnimateSequence(self, "cpFinal")
	end

	entanglerBuildCount = entanglerBuildCount + 1
	if entanglerBuildCount == 1 then
		log("built instruction widget backingWidth=660 textWidth=660 normalizedDoubleSpaces=" ..
			tostring(replacementCount))
	end

	return self
end

if MenuBuilder.m_types["entanglerWidget"] == nil then
	require("inGame.cp.entanglerWidget")
end
if MenuBuilder.m_types["ghostHUDContainer"] == nil then
	require("inGame.cp.ghostHUDContainer")
end
if MenuBuilder.m_types["skullHUDContainer"] == nil then
	require("inGame.cp.skullHUDContainer")
end

-- Generated registry entries for these stock widgets can be factory
-- trampolines, so install recovered constructors directly rather than wrapping
-- and re-entering MenuBuilder.BuildRegisteredType.
MenuBuilder.m_types["entanglerWidget"] = buildEntanglerWidget
MenuBuilder.m_types["ghostHUDContainer"] = function(menu, controller)
	return buildGhostHUDContainer(menu, controller, "ghostHUDContainer")
end
MenuBuilder.m_types["skullHUDContainer"] = function(menu, controller)
	return buildGhostHUDContainer(menu, controller, "skullHUDContainer")
end

log("registered safe-area child layout offset=88 localCenter=872 screenCenter=960 instructionBacking=660")
