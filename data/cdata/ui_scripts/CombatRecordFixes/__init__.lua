-- Frontend HKS starts before the selected mode is final. Register CP menu
-- overrides for the lifetime of the frontend VM instead of making a one-time
-- decision from Engine.IsAliensMode() here.
if not Engine.InFrontend() then
	return
end

print("[IWZ][CombatRecordFixes] UI script loading frontend=true modeAtRegistration=" ..
	tostring(Engine.IsAliensMode()))

if MenuBuilder.m_types["CPCombatRecordMapListMenu"] == nil then
	require("frontEnd.cp.CPCombatRecordMapListMenu")
end

if MenuBuilder.m_types["CPCombatRecordMapValueButton"] == nil then
	require("frontEnd.cp.CPCombatRecordMapValueButton")
end

if MenuBuilder.m_types["CPCombatRecordWeaponListMenu"] == nil then
	require("frontEnd.cp.CPCombatRecordWeaponListMenu")
end

if MenuBuilder.m_types["CPCombatRecordCardsListMenu"] == nil then
	require("frontEnd.cp.CPCombatRecordCardsListMenu")
end

local originalMapListMenu = MenuBuilder.m_types["CPCombatRecordMapListMenu"]
local originalMapValueButton = MenuBuilder.m_types["CPCombatRecordMapValueButton"]
local originalWeaponListMenu = MenuBuilder.m_types["CPCombatRecordWeaponListMenu"]
local originalCardsListMenu = MenuBuilder.m_types["CPCombatRecordCardsListMenu"]

local loggedHelperBarFix = false
local loggedMissingHelperBar = false
local loggedFilmStatsFix = false
local loggedFilmRowFix = false
local loggedMissingFilmRow = false
local loggedMissingBossTime = false
local loggedFilmStencilFix = false
local loggedWeaponStencilFix = false
local loggedCardsStencilFix = false
local loggedWeaponDescriptionSpacing = false

local function normalizeWeaponDescription(description, source, weaponRef)
	if type(description) ~= "string" or description == "" then
		return description
	end

	-- Stock weapon prose uses double ASCII spaces between sentences. Limit the
	-- normalization to those spaces so newlines and localization control codes
	-- remain untouched.
	local normalized, replacementCount = string.gsub(description, "  +", " ")
	if replacementCount > 0 and not loggedWeaponDescriptionSpacing then
		print("[IWZ][CombatRecordFixes] normalized Zombies weapon description spacing" ..
			" source=" .. tostring(source) .. " weapon=" .. tostring(weaponRef) ..
			" replacements=" .. tostring(replacementCount))
		loggedWeaponDescriptionSpacing = true
	end

	return normalized
end

if Cac and Cac.GetWeaponDesc and Cac.GetWeaponLootDesc and
	not Cac.iwzWeaponDescriptionSpacingInstalled then
	local stockGetWeaponDesc = Cac.GetWeaponDesc
	local stockGetWeaponLootDesc = Cac.GetWeaponLootDesc
	Cac.iwzWeaponDescriptionSpacingInstalled = true

	Cac.GetWeaponDesc = function(weaponRef, ...)
		local description = stockGetWeaponDesc(weaponRef, ...)
		if not Engine.IsAliensMode() then
			return description
		end

		return normalizeWeaponDescription(description, "base", weaponRef)
	end

	Cac.GetWeaponLootDesc = function(weaponRef, lootItemID, ...)
		local description = stockGetWeaponLootDesc(weaponRef, lootItemID, ...)
		if not Engine.IsAliensMode() then
			return description
		end

		return normalizeWeaponDescription(description, "loot", weaponRef)
	end

	print("[IWZ][CombatRecordFixes] installed shared Zombies weapon description spacing normalization")
else
	print("[IWZ][CombatRecordFixes] shared weapon description spacing install skipped" ..
		" reason=Cac-functions-unavailable-or-installed")
end

if LOADOUT and LOADOUT.MakeBaseWeaponsListDataSource and
	not LOADOUT.iwzWeaponDescriptionSpacingInstalled then
	local stockMakeBaseWeaponsListDataSource = LOADOUT.MakeBaseWeaponsListDataSource
	LOADOUT.iwzWeaponDescriptionSpacingInstalled = true

	LOADOUT.MakeBaseWeaponsListDataSource = function(...)
		local weaponClasses = stockMakeBaseWeaponsListDataSource(...)
		if not Engine.IsAliensMode() then
			return weaponClasses
		end

		return weaponClasses:Decorate(function(_, weaponClass)
			return {
				weapons = weaponClass.weapons:Decorate(function(_, weapon, controllerIndex)
					local weaponRef = weapon.ref:GetValue(controllerIndex)
					return {
						desc = weapon.desc:Filter(
							"iwz_zombies_weapon_description_spacing",
							function(description)
								return normalizeWeaponDescription(
									description, "base-list", weaponRef)
							end)
					}
				end)
			}
		end)
	end

	print("[IWZ][CombatRecordFixes] installed Zombies base weapon list description" ..
		" spacing normalization surfaces=WeaponKits,CombatRecord")
else
	print("[IWZ][CombatRecordFixes] base weapon list spacing install skipped" ..
		" reason=LOADOUT.MakeBaseWeaponsListDataSource-unavailable-or-installed")
end

local COMBAT_RECORD_MODEL_PATH = ZombiesUtils.CombatRecordMenuModelPath

local function buildDescendingDataSource(source, controllerIndex, valueField)
	local entries = {}
	local count = source:GetCountValue(controllerIndex)

	for index = 0, count - 1 do
		local data = source:GetDataSourceAtIndex(index, controllerIndex)
		local valueSource = data and data[valueField]
		local value = valueSource and tonumber(valueSource:GetValue(controllerIndex)) or 0
		table.insert(entries, {
			data = data,
			value = value or 0,
			originalIndex = index
		})
	end

	table.sort(entries, function(a, b)
		if a.value == b.value then
			return a.originalIndex < b.originalIndex
		end

		return a.value > b.value
	end)

	local orderedSource = LUI.DataSourceFromList.new(#entries)
	orderedSource.MakeDataSourceAtIndex = function(_, index)
		return entries[index + 1].data
	end
	orderedSource.GetDefaultFocusIndex = function()
		return 0
	end

	local highestValue = 0
	if entries[1] then
		highestValue = entries[1].value
	end

	return orderedSource, count, highestValue
end

local function installDescendingGridSort(grid, controllerIndex, valueField, recordType)
	local setGridDataSource = grid.SetGridDataSource
	grid.SetGridDataSource = function(element, source, requestedControllerIndex)
		if source == nil then
			return setGridDataSource(element, source, requestedControllerIndex)
		end

		local sortControllerIndex = requestedControllerIndex or controllerIndex
		local orderedSource, count, highestValue = buildDescendingDataSource(
			source, sortControllerIndex, valueField)
		print("[IWZ][CombatRecordFixes] sorted " .. recordType ..
			" descending field=" .. valueField .. " count=" .. tostring(count) ..
			" highest=" .. tostring(highestValue))
		return setGridDataSource(element, orderedSource, requestedControllerIndex)
	end
end

local function decorateWeaponStats(_, weapon, controllerIndex)
	local weaponRef = weapon.ref:GetValue(controllerIndex)
	local modelPath = COMBAT_RECORD_MODEL_PATH .. ".weapons." .. weaponRef
	return {
		headshots = LUI.DataSourceInControllerModel.new(modelPath .. ".headshots",
			Engine.GetPlayerDataEx(controllerIndex, CoD.StatsGroup.Coop,
				"headShots", weaponRef)),
		kills = LUI.DataSourceInControllerModel.new(modelPath .. ".kills",
			Engine.GetPlayerDataEx(controllerIndex, CoD.StatsGroup.Coop,
				"killsPerWeapon", weaponRef))
	}
end

local function decorateWeaponClass(_, weaponClass)
	return {
		name = weaponClass.pluralName:Filter("localized", Engine.Localize),
		key = weaponClass.pluralName,
		weapons = weaponClass.weapons:Decorate(decorateWeaponStats)
	}
end

local function buildAllWeaponsDataSource(controllerIndex)
	local baseWeapons = LOADOUT.MakeBaseWeaponsListDataSource(
		COMBAT_RECORD_MODEL_PATH .. ".weapons.baseWeapons",
		Cac.GetAllWeaponClasses(), Cac.GetWeaponRowList())
	local weaponClasses = baseWeapons:Decorate(decorateWeaponClass)
	local weapons = {}

	for classIndex = 0, weaponClasses:GetCountValue(controllerIndex) - 1 do
		local weaponClass = weaponClasses:GetDataSourceAtIndex(classIndex)
		for weaponIndex = 0, weaponClass.weapons:GetCountValue(controllerIndex) - 1 do
			table.insert(weapons,
				weaponClass.weapons:GetDataSourceAtIndex(weaponIndex, controllerIndex))
		end
	end

	local source = LUI.DataSourceFromList.new(#weapons)
	source.MakeDataSourceAtIndex = function(_, index)
		return weapons[index + 1]
	end
	return source
end

local function buildAllCardsDataSource(controllerIndex)
	local cardSlots = DataSources.frontEnd.CP.fortuneCards:Decorate(
		function(cardSlot, cards)
			return {
				cardSlot = cardSlot,
				content = cards:Decorate(ZMB_CONSUMABLES.DecorateCardFunc(
					COMBAT_RECORD_MODEL_PATH .. ".cards"))
			}
		end)
	local cards = {}

	for slotIndex = 0, cardSlots:GetCountValue(controllerIndex) - 1 do
		local slot = cardSlots:GetDataSourceAtIndex(slotIndex)
		for cardIndex = 0, slot.content:GetCountValue(controllerIndex) - 1 do
			table.insert(cards, slot.content:GetDataSourceAtIndex(cardIndex, controllerIndex))
		end
	end

	local source = LUI.DataSourceFromList.new(#cards)
	source.MakeDataSourceAtIndex = function(_, index)
		return cards[index + 1]
	end
	return source
end

if originalMapValueButton then
	MenuBuilder.m_types["CPCombatRecordMapValueButton"] = function(menu, controller)
		local self = originalMapValueButton(menu, controller)
		local valueLabel = self.GenericDualLabelButton and self.GenericDualLabelButton.DynamicText

		if valueLabel then
			-- The stock rounds subscription refreshes after construction as each grid
			-- row receives its data source. Suppress that binding at the value label
			-- itself so an asynchronous refresh cannot restore the scene count.
			local setText = valueLabel.setText
			valueLabel.setText = function(element, value, duration)
				return setText(element, "", duration)
			end
			valueLabel:setText("", 0)
			valueLabel:SetAlpha(0, 0)

			if not loggedFilmRowFix then
				print("[IWZ][CombatRecordFixes] suppressed model-bound per-film Total Scenes values")
				loggedFilmRowFix = true
			end
		elseif not loggedMissingFilmRow then
			print("[IWZ][CombatRecordFixes] Films row value label unavailable during construction")
			loggedMissingFilmRow = true
		end

		return self
	end
else
	print("[IWZ][CombatRecordFixes] Films row unavailable; Total Scenes values remain visible")
end

if originalMapListMenu then
	MenuBuilder.m_types["CPCombatRecordMapListMenu"] = function(menu, controller)
		local self = originalMapListMenu(menu, controller)

		if self.MapGrid then
			-- The CP blood graphic animates from a 175x175 box around a 30px row.
			-- Stock stencils the grid exactly at x=132/y=200, cutting the graphic at
			-- the left and top edges. Films only contains five rows, so it needs no
			-- scrolling stencil.
			self.MapGrid:setUseStencil(false)

			if not loggedFilmStencilFix then
				print("[IWZ][CombatRecordFixes] disabled Films grid stencil so 175px blood hover art is not clipped")
				loggedFilmStencilFix = true
			end
		end

		if self.ButtonHelperBar then
			-- Stock applies +94.83 to both horizontal offsets, shifting the full-width
			-- helper bar right and leaving the bottom-left edge uncovered.
			self.ButtonHelperBar:SetAnchorsAndPosition(0, 0, 1, 0,
				0, 0, _1080p * -85, 0)

			if not loggedHelperBarFix then
				print("[IWZ][CombatRecordFixes] normalized Films helper bar to full screen width")
				loggedHelperBarFix = true
			end
		elseif not loggedMissingHelperBar then
			print("[IWZ][CombatRecordFixes] Films helper bar unavailable during menu construction")
			loggedMissingHelperBar = true
		end

		if self.RoundsStat then
			self.RoundsStat.Label:setText(ToUpperCase(
				Engine.Localize("MENU_SP_STAT_TOTAL") .. " " .. Engine.Localize("LUA_MENU_ZM_ROUNDS")), 0)
		end

		local function installMissingTimePlaceholder(stat, statName)
			if stat == nil or stat.AmountLabel == nil then
				return false
			end

			local amountLabel = stat.AmountLabel
			local setText = amountLabel.setText
			amountLabel.setText = function(element, value, duration)
				if value == nil or value == "" then
					value = "--:--"

					if not loggedMissingBossTime then
						print("[IWZ][CombatRecordFixes] normalized empty " .. statName ..
							" time during initial Films data binding")
						loggedMissingBossTime = true
					end
				end

				return setText(element, value, duration)
			end
			amountLabel:setText("--:--", 0)
			return true
		end

		if self.MapGrid and self.BossBattleStat and self.MephBattleStat then
			local bossPlaceholderInstalled = installMissingTimePlaceholder(self.BossBattleStat, "Boss Battle")
			local mephPlaceholderInstalled = installMissingTimePlaceholder(self.MephBattleStat, "Mephistopheles")

			if bossPlaceholderInstalled and mephPlaceholderInstalled and not loggedFilmStatsFix then
				print("[IWZ][CombatRecordFixes] labeled Total Scenes and bound missing boss-time placeholders")
				loggedFilmStatsFix = true
			end
		end

		return self
	end
else
	print("[IWZ][CombatRecordFixes] Films menu unavailable; Films patches not installed")
end

if originalWeaponListMenu then
	MenuBuilder.m_types["CPCombatRecordWeaponListMenu"] = function(menu, controller)
		local self = originalWeaponListMenu(menu, controller)
		local controllerIndex = controller and controller.controllerIndex or self:getRootController()

		if self.WeaponGrid then
			-- GenericDualLabelButton expands CPBlood from a 16px seed to 175x175,
			-- centered on a 30px row. The stock grid stencil clips that authored
			-- hover animation at its left, top and bottom bounds.
			self.WeaponGrid:setUseStencil(false)
			if not loggedWeaponStencilFix then
				print("[IWZ][CombatRecordFixes] disabled Weapons grid stencil so 175px blood hover art is not clipped")
				loggedWeaponStencilFix = true
			end

			installDescendingGridSort(self.WeaponGrid, controllerIndex, "kills", "Weapons")
			self.WeaponGrid:SetGridDataSource(buildAllWeaponsDataSource(controllerIndex),
				controllerIndex)
		else
			print("[IWZ][CombatRecordFixes] Weapons grid unavailable; kill sorting not installed")
		end

		return self
	end
else
	print("[IWZ][CombatRecordFixes] Weapons menu unavailable; kill sorting not installed")
end

if originalCardsListMenu then
	MenuBuilder.m_types["CPCombatRecordCardsListMenu"] = function(menu, controller)
		local self = originalCardsListMenu(menu, controller)
		local controllerIndex = controller and controller.controllerIndex or self:getRootController()

		if self.cardGrid then
			self.cardGrid:setUseStencil(false)
			if not loggedCardsStencilFix then
				print("[IWZ][CombatRecordFixes] disabled Fate & Fortune grid stencil so 175px blood hover art is not clipped")
				loggedCardsStencilFix = true
			end

			installDescendingGridSort(self.cardGrid, controllerIndex, "timesUsed", "Fate & Fortune cards")
			self.cardGrid:SetGridDataSource(buildAllCardsDataSource(controllerIndex),
				controllerIndex)
		else
			print("[IWZ][CombatRecordFixes] Fate & Fortune grid unavailable; usage sorting not installed")
		end

		return self
	end
else
	print("[IWZ][CombatRecordFixes] Fate & Fortune menu unavailable; usage sorting not installed")
end

print("[IWZ][CombatRecordFixes] patches registered films=" ..
	tostring(originalMapListMenu ~= nil) .. " weapons=" ..
	tostring(originalWeaponListMenu ~= nil) .. " cards=" ..
	tostring(originalCardsListMenu ~= nil))
