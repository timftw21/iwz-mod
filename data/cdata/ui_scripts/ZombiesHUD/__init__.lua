if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

print("[IWZ][ZombiesHUD] shared HUD fixes loading")

local inGameTimerState = {
	startedAt = nil,
	pausedAt = nil,
	pausedMilliseconds = 0
}

local function getElapsedMatchMilliseconds()
	if not game or not game.getmonotonicmilliseconds then
		return nil
	end

	local now = game:getmonotonicmilliseconds()
	if inGameTimerState.startedAt == nil then
		if Game.GetOmnvar("ui_session_state") ~= "playing" then
			return nil
		end

		inGameTimerState.startedAt = now
		print("[IWZ][InGameTimer] elapsed clock started sessionState=playing")
	end

	if Engine.IsLocalServerPaused() then
		if inGameTimerState.pausedAt == nil then
			inGameTimerState.pausedAt = now
		end
	elseif inGameTimerState.pausedAt ~= nil then
		inGameTimerState.pausedMilliseconds = inGameTimerState.pausedMilliseconds +
			(now - inGameTimerState.pausedAt)
		inGameTimerState.pausedAt = nil
	end

	local effectiveNow = inGameTimerState.pausedAt or now
	return math.max(0, effectiveNow - inGameTimerState.startedAt -
		inGameTimerState.pausedMilliseconds)
end

local function formatBossTimerMilliseconds(milliseconds)
	local hours = math.floor(milliseconds / 3600000 % 24)
	local minutes = math.floor(milliseconds / 60000 % 60)
	local seconds = math.floor(milliseconds / 1000 % 60)

	if hours > 0 then
		return Engine.Localize("DIRECT_BOSS_FIGHT_HOURS",
			string.format("%.2d", hours), string.format("%.2d", minutes),
			string.format("%.2d", seconds))
	end

	return Engine.Localize("DIRECT_BOSS_FIGHT_MINUTES",
		string.format("%.2d", minutes), string.format("%.2d", seconds))
end

local function getBossTimerContainer(hud)
	local wrapper = hud and hud.bossTimer
	return wrapper and wrapper._widget
end

local function refreshInGameTimer(hud, hudClassName)
	local elapsedMilliseconds = getElapsedMatchMilliseconds()
	local container = getBossTimerContainer(hud)
	local bossTimer = container and container.BossTimer
	local timerText = bossTimer and bossTimer.Timer

	if elapsedMilliseconds == nil or timerText == nil then
		return
	end

	local bossSplash = Game.GetOmnvar("zm_boss_splash") or 0
	if bossSplash == 2 or bossSplash == 3 then
		-- Boss Battle and its pre-fight countdown own this stock widget and the
		-- zm_boss_timer-backed text while their authored sequences are active.
		hud.iwzInGameTimerVisible = false
		return
	end

	local enabled = Engine.GetDvarBool("iwz_in_game_timer")
	if not enabled or bossSplash > 0 then
		if hud.iwzInGameTimerVisible then
			ACTIONS.AnimateSequence(container, "hide")
			hud.iwzInGameTimerVisible = false
			print("[IWZ][InGameTimer] hidden class=" .. hudClassName ..
				" enabled=" .. tostring(enabled) .. " bossSplash=" .. tostring(bossSplash))
		end
		return
	end

	if not hud.iwzInGameTimerVisible then
		ACTIONS.AnimateSequence(container, "bossBattle")
		hud.iwzInGameTimerVisible = true
		print("[IWZ][InGameTimer] shown class=" .. hudClassName ..
			" source=BossTimerContainer pauseAware=1")
	end

	local elapsedSecond = math.floor(elapsedMilliseconds / 1000)
	if hud.iwzInGameTimerLastSecond ~= elapsedSecond then
		hud.iwzInGameTimerLastSecond = elapsedSecond
		timerText:setText(formatBossTimerMilliseconds(elapsedMilliseconds), 0)
	end
end

local zombiesHudClasses = {
	{name = "ZMHUD", class = LUI.ZMHUD},
	{name = "ZMHUDDLC1", class = LUI.ZMHUDDLC1},
	{name = "ZMHUDDLC2", class = LUI.ZMHUDDLC2},
	{name = "ZMHUDDLC3", class = LUI.ZMHUDDLC3},
	{name = "ZMHUDDLC4", class = LUI.ZMHUDDLC4}
}

local patchedHudClassCount = 0

for _, hudEntry in ipairs(zombiesHudClasses) do
	local hudClass = hudEntry.class

	if hudClass and hudClass.GetToggleWidgets and not hudClass.iwzHudModePatched then
		hudClass.iwzHudModePatched = true
		local hudClassName = hudEntry.name
		local stockGetToggleWidgets = hudClass.GetToggleWidgets
		local stockInit = hudClass.init

		hudClass.GetToggleWidgets = function(self)
			if not Engine.GetDvarBool("iwz_zombies_hud") then
				return {}, true
			end

			local widgets, showListedWidgets, animations = stockGetToggleWidgets(self)
			local scoreboardLayer = LUI.ScoreboardLayer:GetInstance()
			local inventoryShowing = scoreboardLayer:IsShowingScoreboard()

			if inventoryShowing and self.papTimer ~= nil then
				-- Zombies inventories are owned by ScoreboardLayer, not FlowManager. The
				-- stock scoreboard branch hides every HUD widget except its damage widgets.
				-- Keep the in-world PaP display's wrapper in that branch's visible list.
				widgets[#widgets + 1] = self.papTimer

				if not self.iwzPapTimerInventoryExempted then
					self.iwzPapTimerInventoryExempted = true
					print("[IWZ][PaPTimer] preserving in-world display during inventory" ..
						" class=" .. hudClassName ..
						" timer=" .. tostring(Game.GetOmnvar("zombie_papTimer")))
				end
			elseif self.iwzPapTimerInventoryExempted then
				print("[IWZ][PaPTimer] inventory exemption cleared class=" .. hudClassName ..
					" timer=" .. tostring(Game.GetOmnvar("zombie_papTimer")))
				self.iwzPapTimerInventoryExempted = false
			end

			return widgets, showListedWidgets, animations
		end

		if stockInit then
			hudClass.init = function(self, controllerIndex)
				stockInit(self, controllerIndex)

				local clockAvailable = game and game.getmonotonicmilliseconds ~= nil
				local bossTimerContainer = getBossTimerContainer(self)
				local timerText = bossTimerContainer and bossTimerContainer.BossTimer and
					bossTimerContainer.BossTimer.Timer

				if clockAvailable and timerText then
					self.iwzInGameTimerVisible = false
					self.iwzInGameTimerLastSecond = -1
					self:addEventHandler("iwz_in_game_timer_tick", function(element)
						refreshInGameTimer(element, hudClassName)
					end)
					self:addEventHandler("iwz_in_game_timer_changed", function(element)
						refreshInGameTimer(element, hudClassName)
					end)

					local timer = LUI.UITimer.new(nil, {
						interval = 250,
						event = "iwz_in_game_timer_tick",
						disposable = false,
						broadcastToRoot = false,
						stopped = false,
						controllerIndex = controllerIndex
					})
					self:addElement(timer)
					self.iwzInGameTimerTicker = timer
					print("[IWZ][InGameTimer] installed class=" .. hudClassName ..
						" source=bossTimer._widget.BossTimer.Timer")
					refreshInGameTimer(self, hudClassName)
				else
					print("[IWZ][InGameTimer] install skipped class=" .. hudClassName ..
						" clockAvailable=" .. tostring(clockAvailable) ..
						" wrapperAvailable=" .. tostring(self.bossTimer ~= nil) ..
						" widgetAvailable=" .. tostring(bossTimerContainer ~= nil) ..
						" timerTextAvailable=" .. tostring(timerText ~= nil))
				end

				self:addEventHandler("iwz_hud_mode_changed", function(element)
					LUI.HUD.UpdateWidgetsVisibility(element)
					print("[IWZ][HUD] refreshed Zombies HUD widgets class=" .. hudClassName ..
						" enabled=" .. tostring(Engine.GetDvarBool("iwz_zombies_hud")))
				end)
			end
		end

		patchedHudClassCount = patchedHudClassCount + 1
		print("[IWZ][HUD] installed HUD-only visibility hook class=" .. hudClassName)
	end
end

print("[IWZ][HUD] HUD-only visibility hooks ready count=" .. tostring(patchedHudClassCount))

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
		local gamepadEnabled = Engine.IsGamepadEnabled() == 1
		local activationKey = gamepadEnabled and "ZM_CONSUMABLES_BUTTON_KEYS" or
			"ZM_CONSUMABLES_BUTTON_KEYS_PC"

		-- Stock constructs this text with the controller-only +smoke/+frag key
		-- before its later empty_menu_stack callback corrects the input device.
		-- Initialize from the active device now; retain the stock callback so a
		-- later device change still updates it normally.
		self.ActivateText:setText(Engine.Localize(activationKey), 0)

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
			print("[IWZ][ZombiesHUD] raised ConsumableActivate visuals by 30 pixels; " ..
				"initialized activation binding key=" .. activationKey ..
				" gamepad=" .. tostring(gamepadEnabled))
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
	local beastSceneOneTransitionPlayed = false

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

				-- Beast's custom spawner delays the internal-wave-one cue by ten
				-- seconds. Own Scene 1 at the authoritative presentation callback so
				-- it is aligned with the clapboard, then suppress that delayed replay;
				-- the same stock helper owns Scene 2 onward without a delay.
				if numericSceneNumber == 1 and CONDITIONS.IsDLC4(self) and
					not beastSceneOneTransitionPlayed then
					beastSceneOneTransitionPlayed = true
					Engine.PlaySound("mus_zombies_newwave")
					print("[IWZ][BeastFixes] Scene 1 transition started from presented " ..
						"waveNumberSplash scene=1 alias=mus_zombies_newwave")
				end

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
		if clapboardBuildCount <= 3 or clapboardBuildCount == 100 then
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

do
	local weaponInfoBuildCount = 0
	local lastLoggedReserveDigitClass = nil

	local function buildWeaponInfoZM(menu, controller)
		local self = LUI.UIElement.new()
		self:SetAnchorsAndPosition(0, 1, 0, 1, 0, 351 * _1080p, 0, 50 * _1080p)
		self.id = "weaponinfoZM"
		self._animationSets = {}
		self._sequences = {}

		local controllerIndex = controller and controller.controllerIndex
		if not controllerIndex and not Engine.InFrontend() then
			controllerIndex = self:getRootController()
		end
		assert(controllerIndex)

		local box = LUI.UIImage.new()
		box.id = "box"
		box:SetAlpha(0.5, 0)
		box:SetZRotation(180, 0)
		box:setImage(RegisterMaterial("zm_pc_score_bg"), 0)
		box:SetUseAA(true)
		box:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * 100, _1080p * 351, _1080p * 1, _1080p * 48.69)
		self:addElement(box)
		self.box = box

		local TextStockAmmo = LUI.UIStyledText.new()
		TextStockAmmo.id = "TextStockAmmo"
		TextStockAmmo:SetRGBFromInt(10066329, 0)
		TextStockAmmo:SetFontSize(20 * _1080p)
		TextStockAmmo:SetFont(FONTS.GetFont(FONTS.MainBold.File))
		TextStockAmmo:SetAlignment(LUI.Alignment.Right)
		TextStockAmmo:SetShadowMinDistance(-0.02, 0)
		TextStockAmmo:SetShadowMaxDistance(0.02, 0)
		TextStockAmmo:SetWordWrap(false)
		local stockReserveLeft = 264.5
		local stockReserveRight = 296.5
		local extendedReserveLeft = 270
		local extendedReserveRight = 300
		TextStockAmmo:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * stockReserveLeft, _1080p * stockReserveRight,
			_1080p * 28.69, _1080p * 48.69)
		TextStockAmmo:BindAlphaToModel(
			DataSources.inGame.player.currentWeapon.ammoReserveAlpha:GetModel(controllerIndex))
		local reserveDigitClass = nil
		TextStockAmmo:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.stockAmmoDisplay:GetModel(controllerIndex), function()
				local stockAmmoDisplay =
					DataSources.inGame.player.currentWeapon.stockAmmoDisplay:GetValue(controllerIndex)
				if stockAmmoDisplay ~= nil then
					local numericStockAmmo = math.abs(tonumber(stockAmmoDisplay) or 0)
					local digitClass = "standard"
					local fontSize = 20
					local controlTop = 28.69
					if numericStockAmmo >= 10000 then
						digitClass = "five-digit"
						fontSize = 11
						controlTop = 37.69
					elseif numericStockAmmo >= 1000 then
						digitClass = "four-digit"
						fontSize = 14
						controlTop = 34.69
					end

					if digitClass ~= "standard" then
						-- The parent HUD masks content shortly after the stock reserve boundary.
						-- Scale extended counts into that safe region and grow rightward from a
						-- fixed 6.5-pixel gap after the magazine field.
						TextStockAmmo:SetFontSize(fontSize * _1080p)
						TextStockAmmo:SetAlignment(LUI.Alignment.Left)
						TextStockAmmo:SetAnchorsAndPosition(0, 1, 0, 1,
							_1080p * extendedReserveLeft, _1080p * extendedReserveRight,
							_1080p * controlTop, _1080p * 48.69)
					else
						TextStockAmmo:SetFontSize(fontSize * _1080p)
						TextStockAmmo:SetAlignment(LUI.Alignment.Right)
						TextStockAmmo:SetAnchorsAndPosition(0, 1, 0, 1,
							_1080p * stockReserveLeft, _1080p * stockReserveRight,
							_1080p * 28.69, _1080p * 48.69)
					end
					TextStockAmmo:setText(stockAmmoDisplay, 0)

					if digitClass ~= reserveDigitClass then
						reserveDigitClass = digitClass
						if digitClass ~= lastLoggedReserveDigitClass then
							lastLoggedReserveDigitClass = digitClass
							print("[IWZ][ZombiesHUD] reserve ammo layout value=" ..
								tostring(stockAmmoDisplay) .. " class=" .. digitClass ..
								" font=" .. tostring(fontSize) .. " controlTop=" .. tostring(controlTop) ..
								" wordWrap=false bounds=" ..
								tostring(digitClass ~= "standard" and extendedReserveLeft or stockReserveLeft) ..
								".." .. tostring(digitClass ~= "standard" and extendedReserveRight or stockReserveRight) ..
								" alignment=" .. tostring(digitClass ~= "standard" and "left" or "right"))
						end
					end
				end
			end)
		self:addElement(TextStockAmmo)
		self.TextStockAmmo = TextStockAmmo

		local TextLeftClipAmmo = LUI.UIStyledText.new()
		TextLeftClipAmmo.id = "TextLeftClipAmmo"
		TextLeftClipAmmo:SetRGBFromTable(SWATCHES.HUD.normal, 0)
		TextLeftClipAmmo:SetAlpha(0.92, 0)
		TextLeftClipAmmo:SetDepth(15, 0)
		TextLeftClipAmmo:SetDotPitchEnabled(true)
		TextLeftClipAmmo:SetDotPitchX(0, 0)
		TextLeftClipAmmo:SetDotPitchY(0, 0)
		TextLeftClipAmmo:SetDotPitchContrast(0, 0)
		TextLeftClipAmmo:SetDotPitchMode(0)
		TextLeftClipAmmo:SetFontSize(48 * _1080p)
		TextLeftClipAmmo:SetFont(FONTS.GetFont(FONTS.MainBold.File))
		TextLeftClipAmmo:SetAlignment(LUI.Alignment.Right)
		TextLeftClipAmmo:SetShadowMinDistance(-0.02, 0)
		TextLeftClipAmmo:SetShadowMaxDistance(0.02, 0)
		TextLeftClipAmmo:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * 102, _1080p * 179, _1080p * 7, _1080p * 55)
		TextLeftClipAmmo:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.clipAmmoLeftDisplay:GetModel(controllerIndex), function()
				local clipAmmoLeftDisplay =
					DataSources.inGame.player.currentWeapon.clipAmmoLeftDisplay:GetValue(controllerIndex)
				if clipAmmoLeftDisplay ~= nil then
					TextLeftClipAmmo:setText(clipAmmoLeftDisplay, 0)
				end
			end)
		self:addElement(TextLeftClipAmmo)
		self.TextLeftClipAmmo = TextLeftClipAmmo

		local TextRightClipAmmo = LUI.UIStyledText.new()
		TextRightClipAmmo.id = "TextRightClipAmmo"
		TextRightClipAmmo:SetRGBFromTable(SWATCHES.HUD.normal, 0)
		TextRightClipAmmo:SetDotPitchEnabled(true)
		TextRightClipAmmo:SetDotPitchX(0, 0)
		TextRightClipAmmo:SetDotPitchY(0, 0)
		TextRightClipAmmo:SetDotPitchContrast(0, 0)
		TextRightClipAmmo:SetDotPitchMode(0)
		TextRightClipAmmo:SetFontSize(48 * _1080p)
		TextRightClipAmmo:SetFont(FONTS.GetFont(FONTS.MainBold.File))
		TextRightClipAmmo:SetAlignment(LUI.Alignment.Right)
		TextRightClipAmmo:SetShadowMinDistance(-0.2, 0)
		TextRightClipAmmo:SetShadowMaxDistance(0.8, 0)
		TextRightClipAmmo:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * 184, _1080p * 263.5, _1080p * 2, _1080p * 50)
		TextRightClipAmmo:BindAlphaToModel(
			DataSources.inGame.player.currentWeapon.ammoInfoAlpha:GetModel(controllerIndex))
		TextRightClipAmmo:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.clipAmmoRightDisplay:GetModel(controllerIndex), function()
				local clipAmmoRightDisplay =
					DataSources.inGame.player.currentWeapon.clipAmmoRightDisplay:GetValue(controllerIndex)
				if clipAmmoRightDisplay ~= nil then
					TextRightClipAmmo:setText(clipAmmoRightDisplay, 0)
				end
			end)
		self:addElement(TextRightClipAmmo)
		self.TextRightClipAmmo = TextRightClipAmmo

		local weaponDescriptionZM = MenuBuilder.BuildRegisteredType("weaponDescriptionZM", {
			controllerIndex = controllerIndex
		})
		weaponDescriptionZM.id = "weaponDescriptionZM"
		weaponDescriptionZM:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * -13.5, _1080p * 286.5, _1080p * -133.13, _1080p * -83.13)
		self:addElement(weaponDescriptionZM)
		self.weaponDescriptionZM = weaponDescriptionZM

		local bar = LUI.UIImage.new()
		bar.id = "bar"
		bar:SetAlpha(0.3, 0)
		bar:SetUseAA(true)
		bar:SetAnchorsAndPosition(0, 1, 0, 1,
			_1080p * 182, _1080p * 184, _1080p * 3, _1080p * 46.69)
		self:addElement(bar)
		self.bar = bar

		self._animationSets.DefaultAnimationSet = function()
			self._sequences.DefaultSequence = function()
			end

			TextStockAmmo:RegisterAnimationSequence("NoStockAmmo", {
				{
					function()
						return self.TextStockAmmo:SetRGBFromTable(SWATCHES.HUD.warning, 0)
					end
				}
			})
			self._sequences.NoStockAmmo = function()
				TextStockAmmo:AnimateSequence("NoStockAmmo")
			end

			TextStockAmmo:RegisterAnimationSequence("HasStockAmmo", {
				{
					function()
						return self.TextStockAmmo:SetRGBFromInt(12566463, 0)
					end
				}
			})
			self._sequences.HasStockAmmo = function()
				TextStockAmmo:AnimateSequence("HasStockAmmo")
			end

			box:RegisterAnimationSequence("ShowLeftClipAmmo", {
				{
					function()
						return self.box:SetAnchorsAndPosition(0, 1, 0, 1,
							_1080p * 156, _1080p * 351, _1080p * 1, _1080p * 48.69, 0)
					end
				}
			})
			TextLeftClipAmmo:RegisterAnimationSequence("ShowLeftClipAmmo", {
				{
					function()
						return self.TextLeftClipAmmo:SetAlpha(1, 0)
					end
				}
			})
			bar:RegisterAnimationSequence("ShowLeftClipAmmo", {
				{
					function()
						return self.bar:SetAlpha(0.5, 0)
					end
				}
			})
			self._sequences.ShowLeftClipAmmo = function()
				box:AnimateSequence("ShowLeftClipAmmo")
				TextLeftClipAmmo:AnimateSequence("ShowLeftClipAmmo")
				bar:AnimateSequence("ShowLeftClipAmmo")
			end

			box:RegisterAnimationSequence("HideLeftClipAmmo", {
				{
					function()
						return self.box:SetAnchorsAndPosition(0, 1, 0, 1,
							_1080p * 156, _1080p * 351, _1080p * 1, _1080p * 48.69, 0)
					end
				}
			})
			TextLeftClipAmmo:RegisterAnimationSequence("HideLeftClipAmmo", {
				{
					function()
						return self.TextLeftClipAmmo:SetAlpha(0, 0)
					end
				}
			})
			bar:RegisterAnimationSequence("HideLeftClipAmmo", {
				{
					function()
						return self.bar:SetAlpha(0, 0)
					end
				}
			})
			self._sequences.HideLeftClipAmmo = function()
				box:AnimateSequence("HideLeftClipAmmo")
				TextLeftClipAmmo:AnimateSequence("HideLeftClipAmmo")
				TextRightClipAmmo:AnimateSequence("HideLeftClipAmmo")
				bar:AnimateSequence("HideLeftClipAmmo")
			end
		end

		self._animationSets.DefaultAnimationSet()
		TextStockAmmo:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.stockAmmo:GetModel(controllerIndex), function()
				local stockAmmo = DataSources.inGame.player.currentWeapon.stockAmmo:GetValue(controllerIndex)
				if stockAmmo ~= nil and stockAmmo <= 0 then
					ACTIONS.AnimateSequence(self, "NoStockAmmo")
				end
				if stockAmmo ~= nil and stockAmmo > 0 then
					ACTIONS.AnimateSequence(self, "HasStockAmmo")
				end
			end)

		local updateDualWieldLayout = function()
			local isDualWielding =
				DataSources.inGame.player.currentWeapon.isDualWielding:GetValue(controllerIndex)
			local isMeleeWeapon =
				DataSources.inGame.player.currentWeapon.isMeleeWeapon:GetValue(controllerIndex)
			if isDualWielding ~= nil and isDualWielding == true and
				isMeleeWeapon ~= nil and isMeleeWeapon == false then
				ACTIONS.AnimateSequence(self, "ShowLeftClipAmmo")
			end
			if isDualWielding ~= nil and isDualWielding == false then
				ACTIONS.AnimateSequence(self, "HideLeftClipAmmo")
			end
		end

		self:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.isDualWielding:GetModel(controllerIndex),
			updateDualWieldLayout)
		self:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.isMeleeWeapon:GetModel(controllerIndex),
			updateDualWieldLayout)
		self:SubscribeToModel(
			DataSources.inGame.player.currentWeapon.isMeleeWeapon:GetModel(controllerIndex), function()
				local isMeleeWeapon =
					DataSources.inGame.player.currentWeapon.isMeleeWeapon:GetValue(controllerIndex)
				if isMeleeWeapon ~= nil and isMeleeWeapon == true then
					ACTIONS.AnimateSequence(self, "HideLeftClipAmmo")
				end
			end)

		weaponInfoBuildCount = weaponInfoBuildCount + 1
		if weaponInfoBuildCount <= 3 or weaponInfoBuildCount == 100 then
			print("[IWZ][ZombiesHUD] weaponinfoZM built count=" .. tostring(weaponInfoBuildCount))
		end

		return self
	end

	local function installWeaponInfoReplacement(source)
		-- As with CPClapboardBase above, generated registry entries are factory
		-- trampolines and cannot safely be wrapped. Install the recovered stock
		-- constructor with only the reserve-ammo text geometry changed.
		MenuBuilder.m_types["weaponinfoZM"] = buildWeaponInfoZM
		print("[IWZ][ZombiesHUD] full weaponinfoZM replacement registered source=" .. source ..
			" stockBoxWidth=32 extendedBoxWidth=30 extendedLeft=270 extendedRight=300 " ..
			"magazineGap=6.5 fourDigitFont=14 fiveDigitFont=11 wordWrap=false maxDigits=5")
	end

	if MenuBuilder.m_types["weaponinfoZM"] ~= nil then
		installWeaponInfoReplacement("existing-type")
	else
		-- weaponinfoZM is loaded lazily with the Zombies HUD. Requiring it while the
		-- custom-script loader is active re-enters HKS package loading, so replace its
		-- one future registration and restore the global registrar immediately.
		local originalRegisterType = MenuBuilder.registerType
		MenuBuilder.registerType = function(typeName, constructor)
			local result = originalRegisterType(typeName, constructor)
			if typeName == "weaponinfoZM" then
				MenuBuilder.registerType = originalRegisterType
				installWeaponInfoReplacement("deferred-registration")
			end
			return result
		end
		print("[IWZ][ZombiesHUD] deferred weaponinfoZM replacement armed")
	end
end
