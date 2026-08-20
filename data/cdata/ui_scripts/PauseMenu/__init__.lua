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

local weaponSplashTable = "cp/zombies/zombie_splashtable.csv"
local weaponRankTable = "mp/weaponRankTable.csv"
local weaponUnlockTable = "mp/unlocks/CPWeaponUnlocks.csv"

local function logWeaponWidget(message)
	print("[IWZ][WeaponLevelWidget] " .. message)
end

local function getCurrentWeaponRef(controllerIndex)
	local currentWeapon = DataSources.inGame
		and DataSources.inGame.player
		and DataSources.inGame.player.currentWeapon
	local baseWeapon = currentWeapon and currentWeapon.baseWeapon

	if not baseWeapon then
		return nil, nil
	end

	local weaponAsset = baseWeapon:GetValue(controllerIndex)
	if not weaponAsset or weaponAsset == "" or weaponAsset == "none" then
		return nil, weaponAsset
	end

	-- cp_weaponrank.gsc resolves the weapon used for shared progression through
	-- cp/utility::getbaseweaponname. Mirror that routine exactly: Zombies assets
	-- retain their _zm/_zmr/_pap suffixes in the HUD model, while progression is
	-- keyed by the first two tokens (for example iw7_g18_zmr -> iw7_g18).
	local prefix, weaponName = string.match(weaponAsset, "^([^_]+)_([^_]+)")
	local weaponRef
	if prefix == "iw5" or prefix == "iw6" or prefix == "iw7" then
		weaponRef = prefix .. "_" .. weaponName
	elseif prefix == "alt" then
		local altPrefix, altWeaponName = string.match(weaponAsset, "^alt_([^_]+)_([^_]+)")
		if altPrefix and altWeaponName then
			weaponRef = altPrefix .. "_" .. altWeaponName
		end
	else
		weaponRef = weaponAsset
	end

	if not weaponRef or weaponRef == "" then
		return nil, weaponAsset
	end

	return weaponRef, weaponAsset
end

local function getWeaponLevelIcon(weaponRef)
	local icon = Engine.TableLookup(weaponSplashTable, 0, "ranked_up_weapon_" .. weaponRef, 3)
	if icon and icon ~= "" then
		return icon, "level-up splash"
	end

	local ok, fallbackIcon = pcall(Cac.GetWeaponImage, weaponRef)
	if ok and fallbackIcon and fallbackIcon ~= "" then
		return fallbackIcon, "weapon table fallback"
	end

	return nil, "unavailable"
end

local function getWeaponXP(controllerIndex, weaponRef, field)
	local ok, value = pcall(
		Engine.GetPlayerDataEx,
		controllerIndex,
		CoD.StatsGroup.Common,
		"sharedProgression",
		"weaponLevel",
		weaponRef,
		field
	)

	if not ok then
		return nil, tostring(value)
	end

	return tonumber(value), nil
end

local function getWeaponUnlockData(controllerIndex, weaponRef)
	-- cp_weaponrank.gsc gates weapon XP with this exact CP rank/table check.
	-- The stored rank and column 7 are zero-based; column 2 is the matching
	-- player-facing level printed by the stock unlock UI.
	local lookupOK, rawUnlockRank = pcall(Engine.TableLookup, weaponUnlockTable, 0, weaponRef, 7)
	if not lookupOK or rawUnlockRank == nil then
		return nil, "unlock rank lookup unavailable: " .. tostring(rawUnlockRank)
	end

	-- Standard rows store their rank gate in column 7. DLC/merit rows reuse that
	-- column for the first criterion's numeric threshold, but cp_weaponrank.gsc
	-- still interprets it as a rank. Mirror that runtime behavior exactly; an
	-- absent or blank numeric value has the same zero-gate result as GSC's int().
	local unlockRank = tonumber(rawUnlockRank) or 0
	local rankOK, playerRank = pcall(
		Engine.GetPlayerDataEx,
		controllerIndex,
		CoD.StatsGroup.Coop,
		"progression",
		"playerLevel",
		"rank"
	)
	playerRank = tonumber(playerRank)
	if not rankOK or not playerRank then
		return nil, "player Zombies rank unavailable: " .. tostring(playerRank)
	end

	local displayLevel = tonumber(Engine.TableLookup(weaponUnlockTable, 0, weaponRef, 2)) or unlockRank + 1
	return {
		isLocked = playerRank < unlockRank,
		playerRank = playerRank,
		unlockRank = unlockRank,
		displayLevel = displayLevel
	}, nil
end

local function hideWeaponLevelWidget(widget, weaponAsset, reason)
	widget:SetAlpha(0, 0)

	local state = "hidden:" .. tostring(weaponAsset) .. ":" .. reason
	if widget.iwzLoggedState ~= state then
		widget.iwzLoggedState = state
		logWeaponWidget("hidden asset=" .. tostring(weaponAsset) .. " reason=" .. reason)
	end
end

local function refreshWeaponLevelWidget(widget, controllerIndex)
	local weaponRef, weaponAsset = getCurrentWeaponRef(controllerIndex)
	if not weaponRef then
		hideWeaponLevelWidget(widget, weaponAsset, "no progression weapon ref")
		return
	end

	local resolvedState = tostring(weaponAsset) .. ":" .. weaponRef
	if widget.iwzResolvedWeaponState ~= resolvedState then
		widget.iwzResolvedWeaponState = resolvedState
		logWeaponWidget(
			"resolved asset=" .. tostring(weaponAsset)
				.. " ref=" .. weaponRef
				.. " source=cp/utility::getbaseweaponname"
		)
	end

	local maxRankOK, maxRank = pcall(Cac.GetWeaponMaxRank, weaponRef)
	maxRank = tonumber(maxRank)
	if not maxRankOK or not maxRank then
		hideWeaponLevelWidget(widget, weaponAsset, "weapon rank bound unavailable ref=" .. weaponRef)
		return
	end

	-- cp_weaponrank.gsc keys progression by each root weapon's maximum rank.
	-- A zero maximum (fists and other utility/melee assets) cannot gain a level.
	if maxRank <= 0 then
		hideWeaponLevelWidget(
			widget,
			weaponAsset,
			"weapon has no level progression ref=" .. weaponRef .. " maxRank=" .. maxRank
		)
		return
	end

	local icon, iconSource = getWeaponLevelIcon(weaponRef)
	if not icon then
		hideWeaponLevelWidget(widget, weaponAsset, "weapon icon unavailable")
		return
	end

	local unlockData, unlockError = getWeaponUnlockData(controllerIndex, weaponRef)
	if not unlockData then
		hideWeaponLevelWidget(widget, weaponAsset, unlockError)
		return
	end

	if unlockData.isLocked then
		widget.ProgressBar:SetProgress(0)
		widget.RankIcon:setImage(RegisterMaterial(icon), 0)
		widget.RankIcon:SetRGBFromInt(8421504, 0)
		widget.RankIcon:SetAlpha(0.35, 0)
		widget.RankNumber:SetAlpha(0, 0)
		widget.LockIcon:SetAlpha(1, 0)
		widget.RankXPLabel:setText(ToUpperCase(Engine.Localize("MENU_LOCKED")) .. ":", 0)
		widget.RankXPValue:setText(
			"LVL " .. tostring(unlockData.displayLevel),
			0
		)
		widget:SetAlpha(1, 0)

		local state = table.concat({ "locked", weaponRef, unlockData.playerRank, unlockData.unlockRank, icon }, ":")
		if widget.iwzLoggedState ~= state then
			widget.iwzLoggedState = state
			logWeaponWidget(
				"locked controller=" .. controllerIndex
					.. " asset=" .. weaponAsset
					.. " ref=" .. weaponRef
					.. " playerRank=" .. unlockData.playerRank
					.. " requiredRank=" .. unlockData.unlockRank
					.. " displayLevel=" .. unlockData.displayLevel
					.. " requirementFormat=LVL noWrap=1 lockedColon=1"
					.. " icon=" .. icon
					.. " iconSource=" .. iconSource
					.. " source=cp_weaponrank.gsc/CPWeaponUnlocks.csv"
			)
		end
		return
	end

	local ok, levelData = pcall(Cac.GetWeaponLevelData, weaponRef, controllerIndex)
	if not ok or not levelData then
		hideWeaponLevelWidget(widget, weaponAsset, "weapon level data unavailable: " .. tostring(levelData))
		return
	end

	-- Stock cp_weaponrank.gsc adds both shared MP and Zombies XP before resolving
	-- a weapon rank. Read those same fields so "XP needed" has identical meaning.
	local mpXP, mpXPError = getWeaponXP(controllerIndex, weaponRef, "mpXP")
	local cpXP, cpXPError = getWeaponXP(controllerIndex, weaponRef, "cpXP")
	if not mpXP or not cpXP then
		hideWeaponLevelWidget(
			widget,
			weaponAsset,
			"shared weapon XP unavailable: " .. tostring(mpXPError or cpXPError)
		)
		return
	end

	local currentXP = mpXP + cpXP
	local rankOK, rawCurrentRank = pcall(Cac.GetWeaponRankForXP, currentXP)
	rawCurrentRank = tonumber(rawCurrentRank)
	if not rankOK or not rawCurrentRank then
		hideWeaponLevelWidget(widget, weaponAsset, "current weapon rank unavailable")
		return
	end

	-- Stock cp_weaponrank.gsc explicitly caps the XP-derived rank at the root
	-- weapon's maximum. The LUI helper can return the uncapped shared MP+CP rank.
	local currentRank = math.min(rawCurrentRank, maxRank)
	local currentLevel = currentRank + 1
	local maxLevel = maxRank + 1
	if currentRank ~= rawCurrentRank then
		local clampState = table.concat({ weaponRef, rawCurrentRank, maxRank, currentXP }, ":")
		if widget.iwzRankClampState ~= clampState then
			widget.iwzRankClampState = clampState
			logWeaponWidget(
				"clamped rank ref=" .. weaponRef
					.. " rawRank=" .. rawCurrentRank
					.. " maxRank=" .. maxRank
					.. " xp=" .. currentXP
					.. " source=cp_weaponrank.gsc"
			)
		end
	else
		widget.iwzRankClampState = nil
	end

	local isMaxLevel = currentRank >= maxRank
	local rankMinXP = tonumber(Engine.TableLookupByRow(weaponRankTable, currentRank, 1)) or currentXP
	local nextLevelXP = tonumber(Engine.TableLookupByRow(weaponRankTable, currentRank, 3)) or currentXP
	local xpNeeded = 0
	if not isMaxLevel then
		xpNeeded = math.max(0, nextLevelXP - currentXP)
	end

	local progress = tonumber(levelData.percentToNext)
	if not progress then
		local rankSpan = nextLevelXP - rankMinXP
		progress = rankSpan > 0 and (currentXP - rankMinXP) / rankSpan or 0
	end
	if isMaxLevel then
		progress = 1
	end
	progress = math.max(0, math.min(1, progress))

	widget.ProgressBar:SetProgress(progress)
	widget.RankIcon:setImage(RegisterMaterial(icon), 0)
	widget.RankIcon:SetRGBFromInt(16777215, 0)
	widget.RankIcon:SetAlpha(1, 0)
	widget.RankNumber:SetAlpha(1, 0)
	widget.LockIcon:SetAlpha(0, 0)
	widget.RankNumber:setText(tostring(currentLevel), 0)

	if isMaxLevel then
		widget.RankXPLabel:setText(ToUpperCase(Engine.Localize("LUA_MENU_MAX")), 0)
		widget.RankXPValue:setText("", 0)
	else
		widget.RankXPLabel:setText(ToUpperCase(Engine.Localize("LUA_MENU_MP_AAR_XP_NEEDED")), 0)
		widget.RankXPValue:setText(tostring(xpNeeded), 0)
	end

	widget:SetAlpha(1, 0)

	local state = table.concat({ weaponRef, currentLevel, currentXP, xpNeeded, icon }, ":")
	if widget.iwzLoggedState ~= state then
		widget.iwzLoggedState = state
		logWeaponWidget(
			"updated controller=" .. controllerIndex
				.. " asset=" .. weaponAsset
				.. " ref=" .. weaponRef
				.. " level=" .. currentLevel .. "/" .. maxLevel
				.. " rawRank=" .. rawCurrentRank
				.. " xp=" .. currentXP .. " (mp=" .. mpXP .. " cp=" .. cpXP .. ")"
				.. " xpNeeded=" .. xpNeeded
				.. " playerRank=" .. unlockData.playerRank
				.. " requiredRank=" .. unlockData.unlockRank
				.. " icon=" .. icon
				.. " iconSource=" .. iconSource
		)
	end
end

local function buildWeaponLevelWidget(controllerIndex)
	local widget = MenuBuilder.BuildRegisteredType("RankProgression", {
		controllerIndex = controllerIndex
	})
	widget.id = "IWZWeaponLevelWidget"

	-- Weapon-level splash icons share a wide canvas but their silhouettes have
	-- very different heights. Give the icon and level number separate lanes so
	-- tall pistol art cannot obscure the white level text.
	widget.RankIcon:SetAnchorsAndPosition(
		0,
		1,
		0,
		1,
		_1080p * 27,
		_1080p * 123,
		_1080p * 28,
		_1080p * 76
	)
	widget.RankNumber:SetAnchorsAndPosition(
		0,
		1,
		0,
		1,
		_1080p * 50,
		_1080p * 100,
		_1080p * 72,
		_1080p * 100
	)

	-- Stock UnlockCriteria uses icon_slot_locked. Overlay that familiar glyph on
	-- the dimmed weapon silhouette while the XP lane explains the required level.
	local LockIcon = LUI.UIImage.new()
	LockIcon.id = "LockIcon"
	LockIcon:setImage(RegisterMaterial("icon_slot_locked"), 0)
	LockIcon:SetAlpha(0, 0)
	LockIcon:SetAnchorsAndPosition(
		0,
		1,
		0,
		1,
		_1080p * 57,
		_1080p * 93,
		_1080p * 50,
		_1080p * 86
	)
	widget:addElement(LockIcon)
	widget.LockIcon = LockIcon

	-- Stock RankProgression gives both XP fields a 200px lane. The weapon and
	-- player circles only need a 110px lane between them, so constrain the child
	-- bounds as well as relocating the parent widget.
	widget.RankXPLabel:SetAnchorsAndPosition(
		1,
		0,
		0.5,
		0.5,
		0,
		_1080p * 110,
		_1080p * -18,
		0
	)
	widget.RankXPValue:SetAnchorsAndPosition(
		1,
		0,
		0.5,
		0.5,
		0,
		_1080p * 110,
		0,
		_1080p * 36
	)
	-- The stock 36px XP value fits this lane for numbers, but the full localized
	-- word "Level" wraps before its value. Use the compact "LVL &&1" treatment
	-- for the locked state and keep the lane single-line so it cannot grow toward the
	-- adjacent player progression widget.
	widget.RankXPValue:SetWordWrap(false)

	local currentWeapon = DataSources.inGame
		and DataSources.inGame.player
		and DataSources.inGame.player.currentWeapon
	local baseWeapon = currentWeapon and currentWeapon.baseWeapon
	if baseWeapon then
		widget:SubscribeToModel(baseWeapon:GetModel(controllerIndex), function()
			refreshWeaponLevelWidget(widget, controllerIndex)
		end)
	else
		logWeaponWidget("held-weapon data source unavailable controller=" .. controllerIndex)
	end

	local cpPlayerData = DataSources.alwaysLoaded
		and DataSources.alwaysLoaded.playerData
		and DataSources.alwaysLoaded.playerData.CP
	local playerRank = cpPlayerData
		and cpPlayerData.progression
		and cpPlayerData.progression.playerLevel
		and cpPlayerData.progression.playerLevel.rank
	if playerRank then
		widget:SubscribeToModel(playerRank:GetModel(controllerIndex), function()
			refreshWeaponLevelWidget(widget, controllerIndex)
		end)
	else
		logWeaponWidget("player Zombies rank data source unavailable controller=" .. controllerIndex)
	end

	refreshWeaponLevelWidget(widget, controllerIndex)
	logWeaponWidget("created controller=" .. controllerIndex)
	return widget
end

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

	if self.WeaponLevelWidget then
		self.WeaponLevelWidget:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 1396, _1080p * 1546, _1080p * 8, _1080p * 158)
	end

	if self.DoubleXPNotifications then
		-- The stock 515px container is rendered at half scale. Shift the whole
		-- four-icon strip left so every possible XP indicator ends before the
		-- weapon progression widget, not just the two icons active most often.
		self.DoubleXPNotifications:SetAnchorsAndPosition(
			0,
			1,
			0,
			1,
			_1080p * 986,
			_1080p * 1501,
			_1080p * 37,
			_1080p * 165
		)

		if not self.iwzDoubleXPLayoutLogged then
			self.iwzDoubleXPLayoutLogged = true
			logWeaponWidget(
				"layout weaponX=1396..1546 xpTextX=1546..1656"
					.. " doubleXPContainerX=986..1501 iconLaneY=28..76 levelLaneY=72..100"
			)
		end
	end
end

MenuBuilder.m_types["CPPauseMenu"] = function(menu, controller)
	local self = originalCPPauseMenu(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or self:getRootController()

	if self.RankProgression then
		self.WeaponLevelWidget = buildWeaponLevelWidget(controllerIndex)
		self:addElement(self.WeaponLevelWidget)
	end

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
