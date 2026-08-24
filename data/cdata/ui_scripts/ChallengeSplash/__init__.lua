if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

local SPLASH_TABLE = "cp/zombies/zombie_splashtable.csv"
local MERIT_TABLE = "cp/allMeritsTable.csv"
local MERIT_SPLASH_TYPE = "merit_splash"
local STOCK_DURATION_MS = 2500

local function log(message)
	print("[IWZ][ChallengeSplash] " .. message)
end

local function getChallengeDuration()
	return math.max(STOCK_DURATION_MS, Engine.GetDvarInt("iwz_challenge_splash_duration_ms"))
end

local function isZombieSplashMessage(messageType)
	return messageType ~= nil and messageType.key ~= nil and
		string.find(messageType.key, "LocalPlayerZombieSplash", 1, true) == 1
end

local function getMeritMetadata(splashIndex, controllerIndex)
	if splashIndex == nil then
		return nil
	end

	local row = tonumber(splashIndex)
	if row == nil or row < 0 then
		return nil
	end

	local splashType = Engine.TableLookupByRow(SPLASH_TABLE, row, 5)
	if splashType ~= MERIT_SPLASH_TYPE then
		return nil
	end

	local meritRef = Engine.TableLookupByRow(SPLASH_TABLE, row, 0)
	if meritRef == nil or meritRef == "" then
		return nil
	end

	local tierCount = 0
	local maxTiers = CSV.allChallengesTable and CSV.allChallengesTable.maxTiers or 8
	for tierIndex = 0, maxTiers do
		local target = Engine.TableLookup(MERIT_TABLE, 0, meritRef, 10 + tierIndex * 3)
		if target == nil or target == "" or tonumber(target) == nil or tonumber(target) <= 0 then
			break
		end
		tierCount = tierCount + 1
	end

	local state
	local stateOk, stateValue = pcall(
		Engine.GetPlayerDataEx,
		controllerIndex,
		CoD.StatsGroup.Coop,
		"meritState",
		meritRef
	)
	if stateOk then
		state = tonumber(stateValue)
	end

	local callingCard = nil
	local highestTier = tierCount > 0 and state ~= nil and state >= tierCount
	if highestTier then
		if CSV.callingCards and CSV.callingCards.cols then
			callingCard = Engine.TableLookup(
				CSV.callingCards.file,
				CSV.callingCards.cols.challenge,
				meritRef,
				CSV.callingCards.cols.texture
			)
		end

		-- The merit table carries the same material reference and remains a safe
		-- fallback if callingCards.csv is not active in an unusual CP UI context.
		if callingCard == nil or callingCard == "" then
			callingCard = Engine.TableLookup(MERIT_TABLE, 0, meritRef, 3)
		end
	end

	return {
		ref = meritRef,
		state = state,
		tierCount = tierCount,
		highestTier = highestTier,
		callingCard = callingCard
	}
end

if LUI.UIMessageQueue == nil or LUI.UIMessageQueue.AddMessage == nil then
	log("LUI.UIMessageQueue unavailable; queue patch not installed")
	return
end

if not LUI.UIMessageQueue.iwzChallengeSplashPatched then
	local originalAddMessage = LUI.UIMessageQueue.AddMessage

	LUI.UIMessageQueue.AddMessage = function(queue, messageType, values, dataSourcesTo)
		if not isZombieSplashMessage(messageType) or values == nil then
			return originalAddMessage(queue, messageType, values, dataSourcesTo)
		end

		local metadata = getMeritMetadata(values.splashIndex, queue.controller)
		if metadata == nil then
			return originalAddMessage(queue, messageType, values, dataSourcesTo)
		end

		if metadata.highestTier and metadata.callingCard ~= nil and metadata.callingCard ~= "" then
			-- ZMHUD normally copies zombie_splashtable's generic merit icon into the
			-- native local-player queue. Replace only that copied value; rank and
			-- weapon progression continue through the exact same untouched pipeline.
			values.icon = metadata.callingCard
		end

		local duration = getChallengeDuration()
		local originalDuration = messageType.displayTime
		messageType.displayTime = duration
		local succeeded, result = pcall(originalAddMessage, queue, messageType, values, dataSourcesTo)
		messageType.displayTime = originalDuration

		log("queued ref=" .. tostring(metadata.ref) ..
			" state=" .. tostring(metadata.state) .. "/" .. tostring(metadata.tierCount) ..
			" highest=" .. tostring(metadata.highestTier) ..
			" icon=" .. tostring(values.icon) ..
			" duration=" .. tostring(duration) .. "ms messageType=" .. tostring(messageType.key))

		if not succeeded then
			error(result)
		end

		return result
	end

	LUI.UIMessageQueue.iwzChallengeSplashPatched = true
	log("native message queue patched meritDuration=" .. tostring(getChallengeDuration()) ..
		"ms stockDuration=" .. tostring(STOCK_DURATION_MS) .. "ms")
end

local widgetSpecs = {
	{
		typeName = "LocalPlayerZombieSplash",
		moduleName = "inGame.cp.LocalPlayerZombieSplash",
		stockDuration = 2500,
		holds = {
			{ element = "spinner", points = { { 1, 5 } } },
			{ element = "glowCopy", points = { { 1, 4 } } },
			{ element = "glow", points = { { 2, 4 } } },
			{ element = "background", points = { { 1, 4 }, { 2, 4 }, { 3, 3 } } },
			{ element = "gridCopy", points = { { 1, 5 } } },
			{ element = "grid", points = { { 1, 12 } } },
			{ element = "splashIconZom", points = { { 1, 5 }, { 2, 3 }, { 4, 3 } } },
			{ element = "popup", points = { { 1, 4 } } },
			{ element = "Body", points = { { 1, 4 } } },
			{ element = "Header", points = { { 1, 4 }, { 2, 3 }, { 3, 3 }, { 4, 3 } } }
		}
	},
	{
		typeName = "LocalPlayerZombieSplashDLC1",
		moduleName = "inGame.cp.LocalPlayerZombieSplashDLC1",
		stockDuration = 2500,
		holds = {
			{ element = "blobCopyLeft", points = { { 1, 5 } } },
			{ element = "blobCopyRight", points = { { 2, 5 } } },
			{ element = "blob", points = { { 1, 5 }, { 2, 4 } } },
			{ element = "flower", points = { { 3, 3 } } },
			{ element = "splashIconZom", points = { { 1, 5 }, { 2, 3 }, { 3, 6 } } },
			{ element = "Body", points = { { 1, 5 } } },
			{ element = "Header", points = { { 1, 5 } } }
		}
	},
	{
		typeName = "LocalPlayerZombieSplashDLC2",
		moduleName = "inGame.cp.LocalPlayerZombieSplashDLC2",
		stockDuration = 2500,
		holds = {
			{ element = "LightRays", points = { { 2, 4 } } },
			{ element = "explosion", points = { { 1, 3 }, { 2, 3 } } },
			{ element = "flame3R", points = { { 1, 5 } } },
			{ element = "flame3L", points = { { 1, 5 } } },
			{ element = "bigFlameR", points = { { 1, 5 } } },
			{ element = "bigFlameL", points = { { 1, 5 } } },
			{ element = "flame1R", points = { { 1, 5 } } },
			{ element = "flame1L", points = { { 1, 5 } } },
			{ element = "flame2R", points = { { 1, 4 } } },
			{ element = "flame2L", points = { { 1, 4 } } },
			{ element = "splashIconZom", points = { { 1, 4 }, { 2, 4 }, { 3, 3 } } },
			{ element = "Body", points = { { 1, 4 } } },
			{ element = "Header", points = { { 1, 4 } } }
		}
	},
	{
		typeName = "LocalPlayerZombieSplashDLC3",
		moduleName = "inGame.cp.LocalPlayerZombieSplashDLC3",
		stockDuration = 2700,
		holds = {
			{ element = "spikes", points = { { 2, 3 }, { 3, 2 } } },
			{ element = "spikesSoft", points = { { 2, 3 }, { 3, 2 } } },
			{ element = "bubbles1", points = { { 1, 10 }, { 3, 15 } } },
			{ element = "bubbles2", points = { { 1, 5 }, { 3, 2 } } },
			{ element = "splashIconZom", points = { { 1, 4 }, { 2, 3 } } },
			{ element = "Body", points = { { 1, 5 }, { 2, 4 } } },
			{ element = "Header", points = { { 1, 5 }, { 2, 4 } } }
		}
	},
	{
		typeName = "LocalPlayerZombieSplashDLC4",
		moduleName = "inGame.cp.LocalPlayerZombieSplashDLC4",
		stockDuration = 2500,
		holds = {
			{ element = "rings", points = { { 1, 5 }, { 2, 5 } } },
			{ element = "splashIconZom", points = { { 1, 5 }, { 2, 6 } } },
			{ element = "Body", points = { { 1, 5 }, { 2, 5 } } },
			{ element = "Header", points = { { 1, 5 }, { 2, 5 } } }
		}
	}
}

local function isCurrentMeritSplash(controllerIndex)
	local splashIndex = DataSources.inGame.MP.splashes.localPlayer.splashIndex:GetValue(controllerIndex)
	local row = tonumber(splashIndex)
	return row ~= nil and row >= 0 and
		Engine.TableLookupByRow(SPLASH_TABLE, row, 5) == MERIT_SPLASH_TYPE
end

local function insertMeritHold(element, trackIndex, callbackIndex, stockDuration, controllerIndex)
	local sequence = element.sequences and element.sequences.FullNewLonger2
	local track = sequence and sequence[trackIndex]
	if track == nil or callbackIndex < 1 or callbackIndex > #track then
		return false
	end

	-- Generated LUI sequences are arrays of property tracks. Insert time at the
	-- native hold-to-exit boundary so the film-specific art, icon, and text all
	-- retain their stock transforms and leave together. Rank/weapon rows return
	-- immediately and execute the original sequence without any added time.
	table.insert(track, callbackIndex, function()
		if not isCurrentMeritSplash(controllerIndex) then
			return nil
		end

		local extraDuration = math.max(0, getChallengeDuration() - stockDuration)
		if extraDuration <= 0 then
			return nil
		end

		return element:Wait(extraDuration)
	end)

	return true
end

local function installWidgetPatch(spec)
	if MenuBuilder.m_types[spec.typeName] == nil then
		require(spec.moduleName)
	end

	local originalWidget = MenuBuilder.m_types[spec.typeName]
	if originalWidget == nil then
		log("widget unavailable type=" .. spec.typeName)
		return false
	end

	MenuBuilder.m_types[spec.typeName] = function(menu, controller)
		local self = originalWidget(menu, controller)
		local controllerIndex = controller and controller.controllerIndex
		if controllerIndex == nil then
			controllerIndex = self:getRootController()
		end

		if self.splashIconZom == nil or self.splashIconZom.Icon == nil or
			self.Body == nil or self.Header == nil then
			log("widget missing stock elements type=" .. spec.typeName)
			return self
		end

		local splashIcon = self.splashIconZom
		local iconImage = splashIcon.Icon

		iconImage:RegisterAnimationSequence("IWZCallingCardScale", {
			{
				function()
					return iconImage:SetScale(0, 0)
				end
			},
			{
				function()
					-- Calling-card materials are approximately 2.5:1. The original
					-- override used a 194x76 image; keep its center at (43,43) while
					-- reducing both axes to 75% (145.5x57) for Tier 5 popups.
					return iconImage:SetAnchorsAndPosition(0, 1, 0, 1,
						_1080p * -29.75, _1080p * 115.75,
						_1080p * 14.5, _1080p * 71.5, 0)
				end
			}
		})
		splashIcon._sequences.IWZCallingCardScale = function()
			iconImage:AnimateSequence("IWZCallingCardScale")
		end

		local insertedHoldCount = 0
		for _, hold in ipairs(spec.holds) do
			local element = self[hold.element]
			if element ~= nil then
				for _, point in ipairs(hold.points) do
					if insertMeritHold(element, point[1], point[2], spec.stockDuration, controllerIndex) then
						insertedHoldCount = insertedHoldCount + 1
					end
				end
			end
		end

		self:addEventHandler("message_queue_show", function()
			local splashIndex = DataSources.inGame.MP.splashes.localPlayer.splashIndex:GetValue(controllerIndex)
			local metadata = getMeritMetadata(splashIndex, controllerIndex)
			if metadata == nil then
				return
			end

			if metadata.highestTier and metadata.callingCard ~= nil and metadata.callingCard ~= "" then
				ACTIONS.AnimateSequenceByElement(self, {
					elementName = "splashIconZom",
					sequenceName = "IWZCallingCardScale",
					elementPath = "splashIconZom"
				})
			end

			log("showing ref=" .. tostring(metadata.ref) ..
				" widget=" .. spec.typeName ..
				" highest=" .. tostring(metadata.highestTier) ..
				" callingCard=" .. tostring(metadata.callingCard) ..
				" duration=" .. tostring(getChallengeDuration()) ..
				"ms timelineExtra=" .. tostring(math.max(0,
					getChallengeDuration() - spec.stockDuration)) .. "ms")
		end)

		log("timeline patched widget=" .. spec.typeName ..
			" stockDuration=" .. tostring(spec.stockDuration) ..
			"ms holdPoints=" .. tostring(insertedHoldCount))

		return self
	end

	return true
end

local patchedWidgetCount = 0
for _, spec in ipairs(widgetSpecs) do
	if installWidgetPatch(spec) then
		patchedWidgetCount = patchedWidgetCount + 1
	end
end

log("installed calling-card and hold patches widgets=" .. tostring(patchedWidgetCount) ..
	" callingCardScale=75% map=" .. tostring(Engine.GetDvarString("ui_mapname")))
