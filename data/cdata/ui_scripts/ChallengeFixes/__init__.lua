-- Frontend HKS starts before the selected mode is final. Register the shared
-- menu wrapper for the lifetime of the frontend VM and evaluate its mode when
-- each menu instance is built.
if not Engine.InFrontend() then
	return
end

print("[IWZ][ChallengeFixes] UI script loading frontend=true modeAtRegistration=" ..
	tostring(Engine.IsAliensMode()))

if MenuBuilder.m_types["CallingCardSelectionMenu"] == nil then
	require("frontEnd.mp.CallingCardSelectionMenu")
end

if MenuBuilder.m_types["CallingCardCategoryMenu"] == nil then
	require("frontEnd.mp.CallingCardCategoryMenu")
end

if MenuBuilder.m_types["ChallengesMenu"] == nil then
	require("frontEnd.mp.ChallengesMenu")
end

local MERIT_TABLE = "cp/allMeritsTable.csv"
local MERIT_REF_COLUMN = 0
local MERIT_SUBCATEGORY_COLUMN = 6
local CAREER_SUBCATEGORY = "zmcareer"
local CAREER_REWARD_XP = 5000
local MASTER_REWARD_XP = 10000
local NAMED_CHALLENGE_REWARDS = {
	mt_dlc3_troll = 2500,
	mt_dlc3_troll2 = 2500,
	mt_dlc2_troll = 5000,
	mt_dlc4_troll = 10000,
	mt_dlc4_troll2 = 50000
}
local CHALLENGE_REQUIREMENTS = {
	mt_purchased_weapon = {20, 40, 60, 80, 100},
	mt_revives = {5, 10, 15, 20, 25},
	mt_purchase_perks = {20, 40, 60, 80, 100},
	mt_faf_uses = {20, 40, 60, 80, 100},
	mt_dlc1_all_ziplines = {5, 10, 15, 20, 25},
	mt_dlc1_sasquatch_kills = {20, 40, 60, 80, 100},
	mt_dlc1_charms_added = {3, 6, 9, 12, 15},
	mt_dlc1_challenge_badge = {5, 10, 15, 20, 25},
	mt_dlc2_roller_skaters = {20, 40, 60, 80, 100},
	mt_dlc2_chi_master = {3, 6, 9, 12, 15},
	mt_dlc2_trap_kills = {40, 80, 120, 160, 200},
	mt_dlc3_cleaver_kills = {40, 80, 120, 160, 200},
	mt_dlc3_crowbar_kills = {40, 80, 120, 160, 200},
	mt_dlc3_crab_mini = {20, 40, 60, 80, 100},
	mt_dlc3_elvira_summon = {2, 4, 6, 8, 10},
	mt_dlc4_entangler_kills = {20, 40, 60, 80, 100},
	mt_dlc4_special_wave_kills = {20, 40, 60, 80, 100}
}
local REWARD_PROJECTION_VERSION = 6

local loggedCareerReward = false
local loggedMasterReward = false
local loggedChallengeRequirement = {}
local loggedNamedChallengeReward = {}

if CallingCardUtils and CallingCardUtils.GetChallengeEntry and
	CallingCardUtils.iwzRewardProjectionVersion ~= REWARD_PROJECTION_VERSION then
	CallingCardUtils.iwzRewardProjectionVersion = REWARD_PROJECTION_VERSION
	local stockGetChallengeEntry = CallingCardUtils.GetChallengeEntry

	CallingCardUtils.GetChallengeEntry = function(meritRef, ...)
		local entry = stockGetChallengeEntry(meritRef, ...)

		if entry and Engine.IsAliensMode() then
			local tierIndex = tonumber(entry.currentTier)
			local requirements = CHALLENGE_REQUIREMENTS[meritRef]
			local currentRequirement = requirements and tierIndex and
				requirements[tierIndex + 1]
			if currentRequirement then
				entry.currentTierMax = currentRequirement
				entry.currentProgress = math.min(
					tonumber(entry.currentProgress) or 0, currentRequirement)
				entry.currentProgressPercent = entry.currentProgress / currentRequirement
				entry.desc = CallingCardUtils.GetCardChallengeDesc(
					meritRef, currentRequirement, MERIT_TABLE)

				if not loggedChallengeRequirement[meritRef] then
					print("[IWZ][ChallengeFixes] displaying tuned requirement merit=" ..
						meritRef .. " tier=" .. tostring(tierIndex + 1) ..
						" target=" .. tostring(currentRequirement))
					loggedChallengeRequirement[meritRef] = true
				end
			end

			local namedReward = NAMED_CHALLENGE_REWARDS[meritRef]
			if namedReward then
				entry.currentTierXP = namedReward

				if not loggedNamedChallengeReward[meritRef] then
					print("[IWZ][ChallengeFixes] displaying named challenge XP merit=" ..
						meritRef .. " xp=" .. tostring(namedReward))
					loggedNamedChallengeReward[meritRef] = true
				end
			elseif entry.isMasterChallenge then
				entry.currentTierXP = MASTER_REWARD_XP

				if not loggedMasterReward then
					print("[IWZ][ChallengeFixes] displaying Master Challenge XP reward=" ..
						tostring(MASTER_REWARD_XP))
					loggedMasterReward = true
				end
			elseif Engine.TableLookup(MERIT_TABLE, MERIT_REF_COLUMN, meritRef,
				MERIT_SUBCATEGORY_COLUMN) == CAREER_SUBCATEGORY then
				entry.currentTierXP = CAREER_REWARD_XP

				if not loggedCareerReward then
					print("[IWZ][ChallengeFixes] displaying Career Milestone XP reward=" ..
						tostring(CAREER_REWARD_XP))
					loggedCareerReward = true
				end
			end
		end

		return entry
	end

	print("[IWZ][ChallengeFixes] challenge reward projection installed careerXP=" ..
		tostring(CAREER_REWARD_XP) .. " masterXP=" .. tostring(MASTER_REWARD_XP) ..
		" namedChallengeRewards=5 tunedChallengeRequirements=17x5")
else
	print("[IWZ][ChallengeFixes] CallingCardUtils unavailable; challenge reward projection not installed")
end

if MenuBuilder.m_types["MasterChallenge"] == nil then
	require("frontEnd.mp.MasterChallenge")
end

if MenuBuilder.m_types["ChallengeInfoBigProgress"] == nil then
	require("frontEnd.mp.ChallengeInfoBigProgress")
end

local originalMasterChallenge = MenuBuilder.m_types["MasterChallenge"]
local originalChallengeInfo = MenuBuilder.m_types["ChallengeInfo"]
local originalChallengeInfoBigProgress = MenuBuilder.m_types["ChallengeInfoBigProgress"]
local originalChallengesMenu = MenuBuilder.m_types["ChallengesMenu"]

local loggedPercentageFix = false
local loggedMissingPercentage = false
local loggedNonZombiesMenu = false
local loggedRewardLayoutFix = false
local loggedTierFiveReward = false
local loggedMasterHoverInstall = false
local loggedMasterSelection = false
local loggedMasterDescription = false
local loggedDescriptionPunctuation = false
local loggedSourceDescriptionPunctuation = false

local function addDescriptionPeriod(description)
	if type(description) ~= "string" or description == "" then
		return description
	end

	-- Localized UI strings can be wrapped in 0x1F/0x1E formatting markers.
	-- Keep the closing markers at the end and put punctuation inside them.
	local suffix = string.match(description, "([\30\31]+)$") or ""
	local text = description
	if suffix ~= "" then
		text = string.sub(description, 1, string.len(description) - string.len(suffix))
	end

	local whitespace = string.match(text, "(%s*)$") or ""
	if whitespace ~= "" then
		text = string.sub(text, 1, string.len(text) - string.len(whitespace))
	end

	if text == "" then
		return description
	end

	local lastCharacter = string.sub(text, -1)
	if lastCharacter ~= "." and lastCharacter ~= "!" and lastCharacter ~= "?" then
		text = text .. "."
	end

	return text .. whitespace .. suffix
end

if CallingCardUtils and CallingCardUtils.GetCardChallengeDesc and
	not CallingCardUtils.iwzDescriptionPunctuationInstalled then
	local stockGetCardChallengeDesc = CallingCardUtils.GetCardChallengeDesc
	CallingCardUtils.iwzDescriptionPunctuationInstalled = true

	CallingCardUtils.GetCardChallengeDesc = function(meritRef, requirement, tableFile)
		local description = stockGetCardChallengeDesc(meritRef, requirement, tableFile)
		if not Engine.IsAliensMode() then
			return description
		end

		local formattedDescription = addDescriptionPeriod(description)
		if formattedDescription ~= description and not loggedSourceDescriptionPunctuation then
			print("[IWZ][ChallengeFixes] normalized source challenge description punctuation" ..
				" surfaces=AAR,InProgress merit=" .. tostring(meritRef))
			loggedSourceDescriptionPunctuation = true
		end

		return formattedDescription
	end

	print("[IWZ][ChallengeFixes] installed source challenge description punctuation" ..
		" surfaces=AAR,InProgress mode=Zombies")
else
	print("[IWZ][ChallengeFixes] source description punctuation install skipped" ..
		" reason=CallingCardUtils.GetCardChallengeDesc unavailable-or-installed")
end

if originalMasterChallenge then
	MenuBuilder.m_types["MasterChallenge"] = function(menu, controller)
		local self = originalMasterChallenge(menu, controller)
		local controllerIndex = controller and controller.controllerIndex or self:getRootController()

		-- MasterChallenge is shared with multiplayer. The active frontend mode can
		-- change without restarting HKS, so make this decision at construction time.
		if not CONDITIONS.IsThirdGameMode(self) then
			if not loggedNonZombiesMenu then
				print("[IWZ][ChallengeFixes] leaving non-Zombies MasterChallenge unchanged")
				loggedNonZombiesMenu = true
			end
			return self
		end

		local percentage = self.PercentCompleteValue

		if percentage then
			-- Stock creates this text at 19 pixels, then the CP animation stretches
			-- its bounds to 36 pixels. Give it a true 24-pixel font and matching
			-- 24-pixel bounds so HKS does not upscale a low-resolution glyph raster.
			percentage:SetFontSize(24 * _1080p)
			percentage:RegisterAnimationSequence("DefaultSequence", {
				{
					function()
						return percentage:SetAnchorsAndPosition(0, 1, 0, 1,
							_1080p * 1090.26, _1080p * 1210.13,
							_1080p * 59, _1080p * 83, 0)
					end
				}
			})
			percentage:AnimateSequence("DefaultSequence")

			if not loggedPercentageFix then
				print("[IWZ][ChallengeFixes] set MasterChallenge percentage to native 24px rendering")
				loggedPercentageFix = true
			end
		elseif not loggedMissingPercentage then
			print("[IWZ][ChallengeFixes] MasterChallenge percentage unavailable during construction")
			loggedMissingPercentage = true
		end

		-- Stock builds MasterChallenge as a passive UIElement even though its data
		-- source has every field consumed by ChallengeInfoBig. Add a mouse-only
		-- hit target and the same Zombies selection border used by normal tiles.
		local hoverBorder = LUI.UIBorder.new({
			borderThicknessLeft = _1080p * 1,
			borderThicknessRight = _1080p * 1,
			borderThicknessTop = _1080p * 1,
			borderThicknessBottom = _1080p * 1
		})
		hoverBorder.id = "MasterChallengeHoverBorder"
		hoverBorder:SetAlpha(0.2, 0)
		self:addElement(hoverBorder)
		self.MasterChallengeHoverBorder = hoverBorder

		local hoverButton = LUI.UIButton.new()
		hoverButton.id = "MasterChallengeHoverButton"
		hoverButton.m_requireFocusType = FocusType.MouseOver
		hoverButton:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, 0, 0)
		self:addElement(hoverButton)
		self.MasterChallengeHoverButton = hoverButton

		local function setHoverSelected(selected)
			hoverBorder:SetAlpha(selected and 1 or 0.2, 0)
			if selected then
				hoverBorder:SetRGBFromTable(SWATCHES.Zombies.menuHeader, 0)
			else
				hoverBorder:SetRGBFromInt(16777215, 0)
			end
			hoverBorder:SetBorderThicknessLeft(_1080p * (selected and 3 or 1), 0)
			hoverBorder:SetBorderThicknessRight(_1080p * (selected and 3 or 1), 0)
			-- The stock challenge tile uses a 23px top bar, but MasterChallenge is
			-- only 142px tall and already has content at its upper edge.
			hoverBorder:SetBorderThicknessTop(_1080p * (selected and 3 or 1), 0)
			hoverBorder:SetBorderThicknessBottom(_1080p * (selected and 3 or 1), 0)
		end

		hoverButton:SubscribeToModelThroughElement(self, "desc", function()
			local source = self:GetDataSource()
			local description = source and source.desc and source.desc:GetValue(controllerIndex)
			if description ~= nil and description ~= "" then
				description = addDescriptionPeriod(description)
				hoverButton.buttonDescription = description
				self.buttonDescription = description

				if not loggedMasterDescription then
					print("[IWZ][ChallengeFixes] bound Master Challenge hover description=" ..
						tostring(description))
					loggedMasterDescription = true
				end
			end
		end)

		hoverButton:addEventHandler("button_over", function()
			setHoverSelected(true)
			self:dispatchEventToCurrentMenu({
				name = "selection_changed",
				newSelection = self
			})
			if hoverButton.buttonDescription then
				self:dispatchEventToCurrentMenu({
					name = "update_button_description",
					text = hoverButton.buttonDescription
				})
			end

			if not loggedMasterSelection then
				print("[IWZ][ChallengeFixes] Master Challenge hover selected full detail data source")
				loggedMasterSelection = true
			end
		end)
		hoverButton:addEventHandler("button_up", function()
			setHoverSelected(false)
		end)

		if not loggedMasterHoverInstall then
			print("[IWZ][ChallengeFixes] Master Challenge hover target and Zombies border installed")
			loggedMasterHoverInstall = true
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] MasterChallenge unavailable; percentage patch not installed")
end

if originalChallengeInfoBigProgress then
	MenuBuilder.m_types["ChallengeInfoBigProgress"] = function(menu, controller)
		local self = originalChallengeInfoBigProgress(menu, controller)

		if not CONDITIONS.IsThirdGameMode(self) then
			return self
		end

		local rewardValue = self.RewardValue
		if rewardValue then
			-- The stock LTR value is right-aligned in a wide box, which creates an
			-- artificial gap after "XP Reward:". Arabic retains its stock RTL layout.
			if not CONDITIONS.IsArabic(self) then
				rewardValue:SetAlignment(LUI.Alignment.Left)
				rewardValue:SetAnchorsAndPosition(0, 1, 0, 1,
					_1080p * 144, _1080p * 231.69,
					_1080p * 470, _1080p * 490, 0)

				if not loggedRewardLayoutFix then
					print("[IWZ][ChallengeFixes] moved the LTR XP reward value next to its label")
					loggedRewardLayoutFix = true
				end
			end

			local controllerIndex = controller and controller.controllerIndex
			local function refreshRewardValue()
				local source = self:GetDataSource()
				if controllerIndex == nil or source == nil or
					source.currentTier == nil or source.tierCount == nil or
					source.currentTierXP == nil then
					return
				end

				local currentTier = source.currentTier:GetValue(controllerIndex)
				local tierCount = source.tierCount:GetValue(controllerIndex)
				local displayedXP = source.currentTierXP:GetValue(controllerIndex)
				if currentTier == 4 and tierCount ~= nil and tierCount >= 5 then
					displayedXP = Engine.GetDvarInt("iwz_challenge_tier5_xp")
					if not loggedTierFiveReward then
						print("[IWZ][ChallengeFixes] displaying Tier 5 XP reward=" .. tostring(displayedXP))
						loggedTierFiveReward = true
					end
				end

				if displayedXP ~= nil then
					rewardValue:setText(displayedXP, 0)
				end
			end

			-- Register after the stock currentTierXP subscription so this display
			-- projection wins without mutating the underlying challenge models.
			rewardValue:SubscribeToModelThroughElement(self, "currentTierXP", refreshRewardValue)
			rewardValue:SubscribeToModelThroughElement(self, "currentTier", refreshRewardValue)
			rewardValue:SubscribeToModelThroughElement(self, "tierCount", refreshRewardValue)
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] ChallengeInfoBigProgress unavailable; reward patches not installed")
end

if originalChallengeInfo then
	MenuBuilder.m_types["ChallengeInfo"] = function(menu, controller)
		local self = originalChallengeInfo(menu, controller)

		if CONDITIONS.IsThirdGameMode(self) then
			local controllerIndex = controller and controller.controllerIndex or self:getRootController()
			self:SubscribeToModelThroughElement(self, "desc", function()
				local source = self:GetDataSource()
				local description = source and source.desc and source.desc:GetValue(controllerIndex)
				if description ~= nil and description ~= "" then
					local formattedDescription = addDescriptionPeriod(description)
					self.buttonDescription = formattedDescription

					if formattedDescription ~= description and not loggedDescriptionPunctuation then
						print("[IWZ][ChallengeFixes] added terminal punctuation to challenge descriptions")
						loggedDescriptionPunctuation = true
					end
				end
			end)
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] ChallengeInfo unavailable; source description formatting not installed")
end

local loggedEmptyDescriptionGuard = false
local loggedDescriptionGuardInstall = false
local loggedEmptyDescriptionAnimation = false
local loggedPaginationInstall = false

if originalChallengesMenu then
	MenuBuilder.m_types["ChallengesMenu"] = function(menu, controller)
		local self = originalChallengesMenu(menu, controller)
		local detailPanel = self.ChallengeInfoBig
		local controllerIndex = controller and controller.controllerIndex or self:getRootController()

		if CONDITIONS.IsThirdGameMode(self) and self.ArrowUp and self.ArrowDown and
			self.ListCount and self.SetDataSource then
			local setDataSource = self.SetDataSource
			local lastPaginationCount = nil
			local lastPaginationVisible = nil

			local function updatePagination(dataSource, activeControllerIndex, reason)
				local entries = dataSource and dataSource.entries
				if entries == nil then
					return
				end

				local count = tonumber(entries:GetCountValue(activeControllerIndex)) or 0
				local visible = count > 12
				local alpha = visible and 1 or 0
				self.ArrowUp:SetAlpha(alpha, 0)
				self.ArrowDown:SetAlpha(alpha, 0)
				self.ListCount:SetAlpha(alpha, 0)

				if count ~= lastPaginationCount or visible ~= lastPaginationVisible then
					local categoryRef = "unknown"
					if dataSource.ref then
						categoryRef = tostring(dataSource.ref:GetValue(activeControllerIndex))
					end

					print("[IWZ][ChallengeFixes] challenge pagination category=" ..
						categoryRef .. " count=" .. tostring(count) ..
						" visible=" .. tostring(visible) .. " reason=" .. reason)
					lastPaginationCount = count
					lastPaginationVisible = visible
				end
			end

			self.SetDataSource = function(element, dataSource, requestedControllerIndex)
				local result = setDataSource(element, dataSource, requestedControllerIndex)
				updatePagination(dataSource, requestedControllerIndex or controllerIndex,
					"data-source")
				return result
			end

			updatePagination(self:GetDataSource(), controllerIndex, "construction")

			if not loggedPaginationInstall then
				print("[IWZ][ChallengeFixes] installed reversible challenge pagination visibility")
				loggedPaginationInstall = true
			end
		end

		if CONDITIONS.IsThirdGameMode(self) and detailPanel then
			local descriptionWidget = detailPanel.ButtonDescriptionText
			local descriptionLabel = descriptionWidget and descriptionWidget.Description
			if descriptionLabel then
				local suppressNextUpdateAnimation = false
				local setText = descriptionLabel.setText
				descriptionLabel.setText = function(element, text, duration)
					-- ButtonDescriptionText follows mouse focus independently of the
					-- challenge data source. BACK publishes an empty description; ignore
					-- that update and its paired fade so the last description never blinks.
					if text == nil or text == "" then
						suppressNextUpdateAnimation = descriptionWidget._sequences and
							descriptionWidget._sequences.Update ~= nil
						if not loggedEmptyDescriptionGuard then
							print("[IWZ][ChallengeFixes] ignored empty BACK hover description update")
							loggedEmptyDescriptionGuard = true
						end
						return
					end

					local formattedText = addDescriptionPeriod(text)
					if formattedText ~= text and not loggedDescriptionPunctuation then
						print("[IWZ][ChallengeFixes] added terminal punctuation to challenge descriptions")
						loggedDescriptionPunctuation = true
					end
					return setText(element, formattedText, duration)
				end

				local updateSequence = descriptionWidget._sequences and
					descriptionWidget._sequences.Update
				if updateSequence then
					descriptionWidget._sequences.Update = function()
						if suppressNextUpdateAnimation then
							suppressNextUpdateAnimation = false
							descriptionLabel:SetAlpha(1, 0)

							if not loggedEmptyDescriptionAnimation then
								print("[IWZ][ChallengeFixes] suppressed empty BACK hover description animation")
								loggedEmptyDescriptionAnimation = true
							end
							return
						end

						return updateSequence()
					end
				end

				if not loggedDescriptionGuardInstall then
					print("[IWZ][ChallengeFixes] installed flicker-free challenge hover description retention")
					loggedDescriptionGuardInstall = true
				end
			end
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] ChallengesMenu unavailable; description retention not installed")
end

local originalCallingCardCategoryMenu = MenuBuilder.m_types["CallingCardCategoryMenu"]
local loggedCallingCardCategoryOrder = false
local callingCardCategoryPriority = {
	standard = 1,
	general = 2,
	career = 3
}

local function getCallingCardCategoryRef(cardIndex, controllerIndex)
	return CallingCardUtils.GetCardChallengeCategoryFromID(
		CallingCardUtils.GetCardCategoryID(cardIndex),
		CallingCardUtils.GetCardChallenge(cardIndex),
		controllerIndex)
end

local function categoryHasVisibleCard(categoryRef, rowCount, controllerIndex)
	for row = 0, rowCount do
		local cardIndex = CallingCardUtils.GetCardIDByRow(row)
		if getCallingCardCategoryRef(cardIndex, controllerIndex) == categoryRef then
			local visible = not CallingCardUtils.GetCardHideIfLocked(cardIndex)
			if not visible then
				local unlockRef = Engine.TableLookup(CSV.callingCards.file,
					CSV.callingCards.cols.index, cardIndex, CSV.callingCards.cols.unlockID)
				if unlockRef and unlockRef ~= "" then
					visible = Engine.IsUnlocked(controllerIndex, "callingCard", unlockRef, true)
				else
					local lootID = Engine.TableLookup(CSV.callingCards.file,
						CSV.callingCards.cols.index, cardIndex, CSV.callingCards.cols.lootID)
					if lootID ~= "" then
						visible = Loot.IsOwned(controllerIndex, tonumber(lootID)) > 0
					end
				end
			end

			if visible then
				return true
			end
		end
	end

	return false
end

local function buildOrderedCallingCardCategories(controllerIndex)
	local categories = {}
	local rowCount = Engine.TableGetRowCount(CSV.callingCards.file) - 1

	for row = 0, rowCount do
		local cardIndex = CallingCardUtils.GetCardIDByRow(row)
		local categoryRef = getCallingCardCategoryRef(cardIndex, controllerIndex)
		if categories[categoryRef] == nil then
			categories[categoryRef] = {
				card = cardIndex,
				hasNew = false
			}
		end

		local unlockRef = Engine.TableLookupByRow(CSV.callingCards.file, row,
			CSV.callingCards.cols.unlockID)
		if unlockRef and unlockRef ~= "" then
			local unlockRow = Engine.TableLookupGetRowNum(CSV.callingCardUnlockTable.file,
				CSV.callingCardUnlockTable.cols.ref, unlockRef)
			if unlockRow ~= -1 and Rewards.IsNew(controllerIndex, "callingCard", unlockRow) then
				categories[categoryRef].hasNew = true
			end
		end
	end

	for categoryRef, category in pairs(categories) do
		if not category.hasNew then
			category.hasNew = CallingCardUtils.HasNewLootCardsByCategory(
				controllerIndex, categoryRef)
		end
	end

	local orderedCategories = {}
	for categoryRef, category in pairs(categories) do
		local cardIndex = category.card
		local hideIfLocked = CallingCardUtils.GetCardHideIfLocked(cardIndex)
		local challengeRef = CallingCardUtils.GetCardChallenge(cardIndex)
		local visible = true

		if hideIfLocked and (challengeRef == nil or #challengeRef == 0) then
			visible = categoryHasVisibleCard(categoryRef, rowCount, controllerIndex)
		end

		if visible then
			table.insert(orderedCategories, {
				card = cardIndex,
				categoryRef = categoryRef
			})
		end
	end

	table.sort(orderedCategories, function(a, b)
		local aOrder = callingCardCategoryPriority[a.categoryRef] or
			(1000 + tonumber(a.card))
		local bOrder = callingCardCategoryPriority[b.categoryRef] or
			(1000 + tonumber(b.card))
		if aOrder == bOrder then
			return tonumber(a.card) < tonumber(b.card)
		end

		return aOrder < bOrder
	end)

	local source = LUI.DataSourceFromList.new(#orderedCategories)
	source.MakeDataSourceAtIndex = function(_, index, dataControllerIndex)
		local category = orderedCategories[index + 1]
		local cardIndex = category.card
		-- Stock has already populated callingCard.cardN before this replacement
		-- source is installed. Reusing those paths leaves the old labels attached
		-- to newly ordered route data, so keep the reordered models isolated.
		local modelPath = "frontEnd.MP.conquest.Headquarters.callingCard.iwzOrdered.card" .. index + 1
		local categoryID = CallingCardUtils.GetCardCategoryID(cardIndex)
		local challengeRef = CallingCardUtils.GetCardChallenge(cardIndex)
		local categoryName = CallingCardUtils.GetCardChallengeCategoryStringFromID(
			cardIndex, categoryID, challengeRef, dataControllerIndex)

		if CONDITIONS.IsThirdGameMode() then
			categoryName = ToUpperCase(categoryName)
		end

		return {
			category = LUI.DataSourceInGlobalModel.new(modelPath .. ".category", categoryName),
			categoryID = LUI.DataSourceInGlobalModel.new(modelPath .. ".categoryID", categoryID),
			challenge = LUI.DataSourceInGlobalModel.new(modelPath .. ".challenge", challengeRef),
			texture = LUI.DataSourceInGlobalModel.new(modelPath .. ".texture",
				CallingCardUtils.GetCardTexture(cardIndex)),
			hasNew = LUI.DataSourceInGlobalModel.new(modelPath .. ".hasNew",
				categories[category.categoryRef].hasNew)
		}
	end
	source.GetDefaultFocusIndex = function()
		return 0
	end

	return source, #orderedCategories
end

if originalCallingCardCategoryMenu then
	MenuBuilder.m_types["CallingCardCategoryMenu"] = function(menu, controller)
		local self = originalCallingCardCategoryMenu(menu, controller)
		local controllerIndex = controller and controller.controllerIndex or self:getRootController()

		if CONDITIONS.IsThirdGameMode(self) and self.CardCategoriesList then
			local orderedSource, categoryCount = buildOrderedCallingCardCategories(controllerIndex)
			self.CardCategoriesList:SetGridDataSource(orderedSource, controllerIndex)

			if not loggedCallingCardCategoryOrder then
				print("[IWZ][ChallengeFixes] ordered Calling Card categories Standard, Soul, Career" ..
					" models=iwzOrdered count=" .. tostring(categoryCount))
				loggedCallingCardCategoryOrder = true
			end
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] CallingCardCategoryMenu unavailable; category order patch not installed")
end

local originalCallingCardSelectionMenu = MenuBuilder.m_types["CallingCardSelectionMenu"]
local loggedCallingCardOrderFix = false
local meritSubcategoryOrder = {
	soul = 1,
	dlc1 = 2,
	dlc2 = 3,
	dlc3 = 4,
	dlc4 = 5,
	dc = 6,
	zmcareer = 7,
	secret = 8
}

if originalCallingCardSelectionMenu then
	MenuBuilder.m_types["CallingCardSelectionMenu"] = function(menu, controller)
		local self = originalCallingCardSelectionMenu(menu, controller)
		local controllerIndex = controller and controller.controllerIndex or self:getRootController()
		local tabManager = self.SubCategoryTabs
		local source = tabManager and tabManager:GetTabManagerDataSource()

		if CONDITIONS.IsThirdGameMode(self) and source then
			local tabs = {}
			local changed = false

			for index = 0, source:GetCountValue(controllerIndex) - 1 do
				local tab = source:GetDataSourceAtIndex(index, controllerIndex)
				local subcategory = nil
				if tab and tab.cards and tab.cards[1] then
					subcategory = CallingCardUtils.GetCardChallengeSubCategoryRef(
						tab.cards[1], controllerIndex)
				end

				table.insert(tabs, {
					data = tab,
					originalIndex = index,
					order = meritSubcategoryOrder[subcategory] or 1000
				})
			end

			table.sort(tabs, function(a, b)
				if a.order == b.order then
					return a.originalIndex < b.originalIndex
				end

				return a.order < b.order
			end)

			for index, tab in ipairs(tabs) do
				if tab.originalIndex ~= index - 1 then
					changed = true
					break
				end
			end

			if changed then
				local orderedSource = LUI.DataSourceFromList.new(#tabs)
				orderedSource.MakeDataSourceAtIndex = function(_, index)
					return tabs[index + 1].data
				end
				orderedSource.GetDefaultFocusIndex = function()
					return 0
				end

				tabManager:SetTabManagerDataSource(orderedSource)

				if not loggedCallingCardOrderFix then
					print("[IWZ][ChallengeFixes] restored Calling Card merit tab order from meritsubcategories.csv")
					loggedCallingCardOrderFix = true
				end
			end
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] CallingCardSelectionMenu unavailable; merit tab order patch not installed")
end

print("[IWZ][ChallengeFixes] challenge UI patches registered percentage=" ..
	tostring(originalMasterChallenge ~= nil) .. " rewards=" ..
	tostring(originalChallengeInfoBigProgress ~= nil))
