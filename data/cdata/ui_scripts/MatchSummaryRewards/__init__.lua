-- The stock AAR renderer already knows how to build calling-card item cards,
-- but CP merit completion does not add calling cards to its native AAR ledger.
-- Merge the match-scoped refs recorded by challenge_rewards.gsc into the stock
-- reward array so they use the same models, carousel, and completion animation.
if not Engine.InFrontend() then
	return
end

local stockGetAARRewards = Rewards.GetAARRewards
local MATCH_CALLING_CARD_DVAR = "iwz_match_calling_card_rewards"
local MATCH_WEAPON_LEVEL_DVAR = "iwz_match_weapon_level_rewards"
local WEAPON_LEVEL_IDENTIFIER_PREFIX = "iwz_weapon_level|"
local AAR_CALLING_CARD_WIDTH = 256
local AAR_CALLING_CARD_HEIGHT = 100
local matchCallingCardXP = {}

if stockGetAARRewards == nil then
	print("[IWZ][MatchSummaryRewards] install skipped reason=Rewards.GetAARRewards unavailable")
	return
end

if Rewards.iwzCallingCardAARProjectionInstalled then
	print("[IWZ][MatchSummaryRewards] install skipped reason=already installed")
	return
end

Rewards.iwzCallingCardAARProjectionInstalled = true

local function decodeWeaponLevelIdentifier(identifier)
	if type(identifier) ~= "string" or
		string.sub(identifier, 1, #WEAPON_LEVEL_IDENTIFIER_PREFIX) ~=
		WEAPON_LEVEL_IDENTIFIER_PREFIX then
		return nil, nil
	end

	local weaponRef, weaponLevel = string.match(identifier,
		"^iwz_weapon_level|([^|]+)|(%d+)$")
	weaponLevel = tonumber(weaponLevel)

	if weaponRef == nil or weaponRef == "" or weaponLevel == nil or
		weaponLevel < 1 then
		return nil, nil
	end

	return weaponRef, weaponLevel
end

local function installAARCallingCardBounds()
	if LUI.ItemCard == nil or LUI.ItemCard.BuildItemCard == nil then
		print("[IWZ][MatchSummaryRewards] calling-card bounds install skipped reason=LUI.ItemCard unavailable")
		return
	end

	if LUI.ItemCard.iwzAARCallingCardBoundsInstalled then
		return
	end

	local stockBuildItemCard = LUI.ItemCard.BuildItemCard
	LUI.ItemCard.iwzAARCallingCardBoundsInstalled = true

	LUI.ItemCard.BuildItemCard = function(self, context, itemType, identifier,
		controllerIndex, forceRebuild)
		local weaponRef, weaponLevel = decodeWeaponLevelIdentifier(identifier)
		local buildIdentifier = weaponRef or identifier
		local result = stockBuildItemCard(self, context, itemType, buildIdentifier,
			controllerIndex, forceRebuild)

		if weaponRef and context == LUI.ItemCard.contexts.AAR_PROGRESSION and
			itemType == LUI.ItemCard.types.WEAPON then
			local cardData = self and self._itemCardData
			if cardData and cardData.rank and cardData.rankIcon and cardData.rankName then
				cardData.rank:SetValue(controllerIndex, weaponLevel)
				cardData.rankName:SetValue(controllerIndex, "")

				local rank = self:getFirstDescendentById("ItemCardRank")
				if rank and rank.RankIcon and rank.RankNumber then
					rank.RankIcon:SetAlpha(0, 0)
					rank.RankNumber:SetAlignment(LUI.Alignment.Center)
					rank.RankNumber:SetAnchorsAndPosition(0.5, 0.5, 0.5, 0.5,
						_1080p * -22, _1080p * 22, _1080p * -13,
						_1080p * 13, 0)
				else
					print("[IWZ][MatchSummaryRewards] weapon level icon removal failed weapon=" ..
						tostring(weaponRef) .. " reason=rank widget unavailable")
				end

				local footer = LUI.DataSourceInGlobalModel.new(self._modelPath .. ".text")
				footer:SetValue(controllerIndex,
					Engine.Localize("MPUI_WEAPON_LVL") .. " " .. tostring(weaponLevel))
				print("[IWZ][MatchSummaryRewards] weapon level card rendered weapon=" ..
					tostring(weaponRef) .. " level=" .. tostring(weaponLevel) ..
					" rankIcon=hidden")
			else
				print("[IWZ][MatchSummaryRewards] weapon level card render failed weapon=" ..
					tostring(weaponRef) .. " level=" .. tostring(weaponLevel) ..
					" reason=rank data unavailable")
			end
		end

		if context == LUI.ItemCard.contexts.AAR_CHALLENGE and
			itemType == LUI.ItemCard.types.CALLING_CARD then
			local component = self and self.ItemCardImageComponent
			local image = component and component.Image
			local xpAmount = matchCallingCardXP[identifier]

			if image then
				image:SetAnchorsAndPosition(0.5, 0.5, 0.5, 0.5,
					_1080p * (-AAR_CALLING_CARD_WIDTH / 2),
					_1080p * (AAR_CALLING_CARD_WIDTH / 2),
					_1080p * (-AAR_CALLING_CARD_HEIGHT / 2),
					_1080p * (AAR_CALLING_CARD_HEIGHT / 2), 0)
				print("[IWZ][MatchSummaryRewards] calling-card image normalized merit=" ..
					tostring(identifier) .. " stock=350x138 final=" ..
					tostring(AAR_CALLING_CARD_WIDTH) .. "x" ..
					tostring(AAR_CALLING_CARD_HEIGHT) .. " slot=350x100")
			else
				print("[IWZ][MatchSummaryRewards] calling-card image normalization failed merit=" ..
					tostring(identifier) .. " reason=image component unavailable")
			end

			if xpAmount then
				local content = self:getChildById("itemCardButton") or self
				local footer = content:getChildById("ItemCardFooter")
				if not footer then
					local footerText = LUI.DataSourceInGlobalModel.new(
						self._modelPath .. ".iwzCallingCardXP")
					footerText:SetValue(controllerIndex,
						"+" .. tostring(xpAmount) .. " XP")

					footer = MenuBuilder.BuildRegisteredType("ItemCardFooter", {
						controllerIndex = controllerIndex
					})
					footer.id = "ItemCardFooter"
					footer:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0,
						_1080p * 395, _1080p * 420, 0)
					footer:SetDataSource({
						text = footerText
					}, controllerIndex)
					content:addElement(footer)
				end

				print("[IWZ][MatchSummaryRewards] calling-card XP footer rendered merit=" ..
					tostring(identifier) .. " xp=" .. tostring(xpAmount) ..
					" style=stock-zombies-footer formatter=literal-xp")
			else
				print("[IWZ][MatchSummaryRewards] calling-card XP footer skipped merit=" ..
					tostring(identifier) .. " reason=XP unavailable")
			end
		end

		return result
	end

	print("[IWZ][MatchSummaryRewards] installed AAR calling-card image bounds " ..
		tostring(AAR_CALLING_CARD_WIDTH) .. "x" .. tostring(AAR_CALLING_CARD_HEIGHT))
end

installAARCallingCardBounds()

local function isZombiesMatchSummaryQuery(unlockTypes, unlockTypeCount)
	if not Engine.IsAliensMode() or type(unlockTypes) ~= "table" or
		unlockTypeCount ~= 2 then
		return false
	end

	local hasCPWeapon = false
	local hasFateCard = false

	for index = 1, unlockTypeCount do
		if unlockTypes[index] == "CPWeapon" then
			hasCPWeapon = true
		elseif unlockTypes[index] == "fateCard" then
			hasFateCard = true
		else
			return false
		end
	end

	return hasCPWeapon and hasFateCard
end

local function getMatchCallingCardRefs()
	local refs = {}
	local serializedRefs = Engine.GetDvarString(MATCH_CALLING_CARD_DVAR)
	matchCallingCardXP = {}

	if serializedRefs == nil or serializedRefs == "" then
		return refs, ""
	end

	for entry in string.gmatch(serializedRefs, "[^,]+") do
		local meritRef, xpAmount = string.match(entry, "^([^:]+):(%d+)$")
		if not meritRef then
			meritRef = entry
		end

		if meritRef ~= "" then
			xpAmount = tonumber(xpAmount)
			table.insert(refs, meritRef)
			if xpAmount and xpAmount >= 0 then
				matchCallingCardXP[meritRef] = xpAmount
			end
		end
	end

	return refs, serializedRefs
end

local function getMatchWeaponLevels()
	local weaponLevels = {}
	local serializedRewards = Engine.GetDvarString(MATCH_WEAPON_LEVEL_DVAR)

	if serializedRewards == nil or serializedRewards == "" then
		return weaponLevels, ""
	end

	for entry in string.gmatch(serializedRewards, "[^,]+") do
		local weaponRef, weaponLevel = string.match(entry, "^([^:]+):(%d+)$")
		weaponLevel = tonumber(weaponLevel)
		if weaponRef and weaponRef ~= "" and weaponLevel and weaponLevel >= 1 then
			table.insert(weaponLevels, {
				ref = weaponRef,
				level = weaponLevel
			})
		else
			print("[IWZ][MatchSummaryRewards] malformed weapon-level reward ignored entry=" ..
				tostring(entry))
		end
	end

	return weaponLevels, serializedRewards
end

Rewards.GetAARRewards = function(controllerIndex, unlockTypes, unlockTypeCount)
	if not isZombiesMatchSummaryQuery(unlockTypes, unlockTypeCount) then
		return stockGetAARRewards(controllerIndex, unlockTypes, unlockTypeCount)
	end

	local rewards = stockGetAARRewards(controllerIndex, unlockTypes, unlockTypeCount)
	if type(rewards) ~= "table" then
		rewards = {}
	end

	local matchCallingCards, serializedRefs = getMatchCallingCardRefs()
	local matchWeaponLevels, serializedWeaponLevels = getMatchWeaponLevels()
	local queuedCallingCards = {}
	local callingCardCount = 0
	local weaponLevelCount = 0

	for index = 1, #rewards do
		local reward = rewards[index]
		if reward and reward.type == "callingCard" and reward.item then
			queuedCallingCards[reward.item] = true
			callingCardCount = callingCardCount + 1
		end
	end

	for index = 1, #matchCallingCards do
		local meritRef = matchCallingCards[index]
		if not queuedCallingCards[meritRef] then
			table.insert(rewards, {
				type = "callingCard",
				item = meritRef
			})
			queuedCallingCards[meritRef] = true
			callingCardCount = callingCardCount + 1
			print("[IWZ][MatchSummaryRewards] calling card merged index=" ..
				tostring(#rewards) .. " merit=" .. tostring(meritRef))
		end
	end

	for index = 1, #matchWeaponLevels do
		local weaponLevel = matchWeaponLevels[index]
		local encodedIdentifier = WEAPON_LEVEL_IDENTIFIER_PREFIX ..
			weaponLevel.ref .. "|" .. tostring(weaponLevel.level)
		table.insert(rewards, {
			type = "CPWeapon",
			item = encodedIdentifier
		})
		weaponLevelCount = weaponLevelCount + 1
		print("[IWZ][MatchSummaryRewards] weapon level merged index=" ..
			tostring(#rewards) .. " weapon=" .. tostring(weaponLevel.ref) ..
			" level=" .. tostring(weaponLevel.level))
	end

	print("[IWZ][MatchSummaryRewards] AAR rewards projected controller=" ..
		tostring(controllerIndex) .. " rewards=" .. tostring(#rewards) ..
		" callingCards=" .. tostring(callingCardCount) ..
		" weaponLevels=" .. tostring(weaponLevelCount) ..
		" recordedRefs=" .. tostring(serializedRefs) ..
		" recordedWeaponLevels=" .. tostring(serializedWeaponLevels))

	return rewards
end

print("[IWZ][MatchSummaryRewards] installed match-scoped Zombies calling-card and weapon-level reward projection")
