if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

print("[IWZ][ZombiesHUD] shared HUD fixes loading")

if MenuBuilder.m_types["ConsumableActivate"] == nil then
	require("inGame.cp.ConsumableActivate")
end

local originalConsumableActivate = MenuBuilder.m_types["ConsumableActivate"]

if originalConsumableActivate == nil then
	print("[IWZ][ZombiesHUD] ConsumableActivate unavailable; card-ready offset not installed")
else
	local CARD_READY_RAISE = 30
	local loggedCardReadyFix = false

	MenuBuilder.m_types["ConsumableActivate"] = function(menu, controller)
		local self = originalConsumableActivate(menu, controller)

		-- The stock widget is bottom-anchored and extends into the perk strip. Keep
		-- its parent placement intact and raise every visual inside it by 30 pixels.
		self.BackingBox:SetAnchorsAndPosition(0, 1, 0, 1,
			0, _1080p * 401, _1080p * (2 - CARD_READY_RAISE), _1080p * (30 - CARD_READY_RAISE))
		self.ConsumableUpName:SetAnchorsAndPosition(0, 1, 0, 1,
			0, _1080p * 386, _1080p * (2 - CARD_READY_RAISE), _1080p * (28 - CARD_READY_RAISE))
		self.Activated:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * 106, _1080p * 606, _1080p * (83 - CARD_READY_RAISE), _1080p * (113 - CARD_READY_RAISE))
		self.Ready:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * -50, _1080p * 451, _1080p * (35 - CARD_READY_RAISE), _1080p * (57 - CARD_READY_RAISE))
		self.ActivateText:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * -50, _1080p * 451, _1080p * (60 - CARD_READY_RAISE), _1080p * (82 - CARD_READY_RAISE))

		if not loggedCardReadyFix then
			print("[IWZ][ZombiesHUD] raised ConsumableActivate visuals by 30 pixels")
			loggedCardReadyFix = true
		end

		return self
	end

	print("[IWZ][ZombiesHUD] card-ready offset registered")
end

if MenuBuilder.m_types["CPClapboardBase"] == nil then
	require("inGame.cp.CPClapboardBase")
end

if MenuBuilder.m_types["CPClapboardBase"] == nil then
	print("[IWZ][ZombiesHUD] CPClapboardBase unavailable; triple-digit scene fix not installed")
else
	local clapboardBuildCount = 0

	local function buildCPClapboardBase(menu, controller)
		local self = LUI.UIElement.new()
		self:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1 * _1080p, 0, 1 * _1080p)
		self.id = "CPClapboardBase"
		self._animationSets = {}
		self._sequences = {}

		local controllerIndex = controller and controller.controllerIndex
		if not controllerIndex and not Engine.InFrontend() then
			controllerIndex = self:getRootController()
		end
		assert(controllerIndex)

		local Base = LUI.UIImage.new()
		Base.id = "Base"
		Base:setImage(RegisterMaterial("clapboard_base"), 0)
		Base:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * -5, _1080p * 251, _1080p * -50, _1080p * 206)
		self:addElement(Base)
		self.Base = Base

		local function buildWavesText(id, fontSize, top, bottom)
			local element = LUI.UIText.new()
			element.id = id
			element:SetRGBFromInt(16777215, 0)
			element:SetFontSize(fontSize * _1080p)
			element:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
			element:SetAlignment(LUI.Alignment.Left)
			element:SetOptOutRightToLeftAlignmentFlip(true)
			element:SetWordWrap(false)
			element:SetAlpha(0, 0)
			element:SetAnchorsAndPosition(0, 1, 0, 1,
				_1080p * 128, _1080p * 242, _1080p * top, _1080p * bottom)
			self:addElement(element)
			return element
		end

		-- IW7's UIText glyph scale follows the element's vertical control height;
		-- SetFontSize alone does not resize this clapboard text. Keep a separate,
		-- vertically centered control height for each digit class.
		local Waves = buildWavesText("Waves", 64, 30.5, 108.5)
		local WavesTriple = buildWavesText("WavesTriple", 48, 39.5, 99.5)
		local WavesExtended = buildWavesText("WavesExtended", 36, 46.5, 92.5)
		local currentDigitClass = nil

		Waves:SubscribeToModel(DataSources.inGame.CP.zombies.waveNumberSplash:GetModel(controllerIndex), function()
			local sceneNumber = DataSources.inGame.CP.zombies.waveNumberSplash:GetValue(controllerIndex)
			if sceneNumber ~= nil then
				local numericSceneNumber = tonumber(sceneNumber) or 0
				local absoluteSceneNumber = math.abs(numericSceneNumber)
				local digitClass = "standard"
				local activeElement = Waves
				local fontSize = 64
				local controlTop = 30.5
				local controlBottom = 108.5

				if absoluteSceneNumber >= 1000 then
					digitClass = "extended"
					activeElement = WavesExtended
					fontSize = 36
					controlTop = 46.5
					controlBottom = 92.5
				elseif absoluteSceneNumber >= 100 then
					digitClass = "triple"
					activeElement = WavesTriple
					fontSize = 48
					controlTop = 39.5
					controlBottom = 99.5
				end

				Waves:SetAlpha(activeElement == Waves and 1 or 0, 0)
				WavesTriple:SetAlpha(activeElement == WavesTriple and 1 or 0, 0)
				WavesExtended:SetAlpha(activeElement == WavesExtended and 1 or 0, 0)
				activeElement:setText(sceneNumber, 0)

				if digitClass ~= currentDigitClass then
					currentDigitClass = digitClass
					print("[IWZ][ZombiesHUD] scene number layout scene=" .. tostring(sceneNumber) ..
						" class=" .. digitClass .. " element=" .. activeElement.id ..
						" constructedFont=" .. tostring(fontSize) ..
						" controlTop=" .. tostring(controlTop) ..
						" controlBottom=" .. tostring(controlBottom) ..
						" controlHeight=" .. tostring(controlBottom - controlTop) .. " boxWidth=114")
				end
			end
		end)
		self.Waves = Waves
		self.WavesTriple = WavesTriple
		self.WavesExtended = WavesExtended

		local Scene = LUI.UIText.new()
		Scene.id = "Scene"
		Scene:SetRGBFromInt(16777215, 0)
		Scene:setText(ToUpperCase(Engine.Localize("ZM_CONSUMABLES_SCENE")), 0)
		Scene:SetFontSize(32 * _1080p)
		Scene:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
		Scene:SetAlignment(LUI.Alignment.Center)
		Scene:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * 9, _1080p * 128, _1080p * 53.5, _1080p * 85.5)
		self:addElement(Scene)
		self.Scene = Scene

		self._animationSets.DefaultAnimationSet = function()
			self._sequences.DefaultSequence = function()
			end

			Base:RegisterAnimationSequence("cpRaveLogo", {
				{
					function()
						return self.Base:setImage(RegisterMaterial("clapboard_base_dlc1"), 0)
					end
				}
			})
			self._sequences.cpRaveLogo = function()
				Base:AnimateSequence("cpRaveLogo")
			end

			Base:RegisterAnimationSequence("cpDiscoLogo", {
				{
					function()
						return self.Base:setImage(RegisterMaterial("clapboard_base_dlc2"), 0)
					end
				}
			})
			self._sequences.cpDiscoLogo = function()
				Base:AnimateSequence("cpDiscoLogo")
			end

			Base:RegisterAnimationSequence("cpTownLogo", {
				{
					function()
						return self.Base:setImage(RegisterMaterial("cp_town_wave_clapper"), 0)
					end
				}
			})
			self._sequences.cpTownLogo = function()
				Base:AnimateSequence("cpTownLogo")
			end

			Base:RegisterAnimationSequence("cpFinalLogo", {
				{
					function()
						return self.Base:setImage(RegisterMaterial("cp_final_wave_clapper"), 0)
					end
				}
			})
			self._sequences.cpFinalLogo = function()
				Base:AnimateSequence("cpFinalLogo")
			end
		end

		self._animationSets.DefaultAnimationSet()
		if CONDITIONS.IsRave(self) then
			ACTIONS.AnimateSequence(self, "cpRaveLogo")
		end
		if CONDITIONS.IsDLC2(self) then
			ACTIONS.AnimateSequence(self, "cpDiscoLogo")
		end
		if CONDITIONS.IsDLC3(self) then
			ACTIONS.AnimateSequence(self, "cpTownLogo")
		end
		if CONDITIONS.IsDLC4(self) then
			ACTIONS.AnimateSequence(self, "cpFinalLogo")
		end

		clapboardBuildCount = clapboardBuildCount + 1
		if clapboardBuildCount <= 3 or clapboardBuildCount % 100 == 0 then
			print("[IWZ][ZombiesHUD] CPClapboardBase built count=" .. tostring(clapboardBuildCount))
		end

		return self
	end

	-- Generated MenuBuilder registry entries are factory trampolines. Calling a
	-- saved entry from a replacement re-enters BuildRegisteredType recursively,
	-- so install the recovered stock constructor directly instead of wrapping it.
	MenuBuilder.m_types["CPClapboardBase"] = buildCPClapboardBase
	print("[IWZ][ZombiesHUD] full CPClapboardBase replacement registered separateTextElements=1 stockFont=64 stockHeight=78 tripleFont=48 tripleHeight=60 extendedFont=36 extendedHeight=46 wordWrap=false boxWidth=114")
end
