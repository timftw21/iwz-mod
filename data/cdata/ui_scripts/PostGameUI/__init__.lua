-- Game-over UI fix based on stock BroShotZomScreen Lua and the CP end-game
-- flow in the CODIW-Source dump.

if Engine.InFrontend() then
	return
end

if MenuBuilder.m_types["BroShotZomScreen"] == nil then
	require("inGame.cp.BroShotZomScreen")
end

local originalBroShotZomScreen = MenuBuilder.m_types["BroShotZomScreen"]
local GNS_ARCADE_DVAR = "iwz_gns_arcade"
local GNS_ARCADE_RESULT_DVAR = "iwz_gns_arcade_result"

if not originalBroShotZomScreen then
	print("[IWZ][PostGameUI] scene label fix skipped: BroShotZomScreen type is unavailable")
	return
end

local function addSceneLabelColon(text, scene)
	if type(text) ~= "string" or text == "" then
		return nil
	end

	local sceneText = tostring(scene)
	local escapedScene = string.gsub(sceneText, "(%W)", "%%%1")
	-- LocalizeIntoString wraps the resolved value in 0x1F/0x1E markers. Keep
	-- those closing markers at the end and insert punctuation inside them.
	local formattingSuffix = string.match(text, "([\30\31]+)$") or ""
	local body = text
	if formattingSuffix ~= "" then
		body = string.sub(text, 1, string.len(text) - string.len(formattingSuffix))
	end

	local whitespace = string.match(body, "(%s*)$") or ""
	if whitespace ~= "" then
		body = string.sub(body, 1, string.len(body) - string.len(whitespace))
	end

	local prefix = string.match(body, "^(.-)%s+" .. escapedScene .. "$")

	if not prefix then
		prefix = string.match(body, "^(.-)" .. escapedScene .. "$")
	end

	if not prefix then
		return nil
	end

	prefix = string.gsub(prefix, "%s+$", "")

	if string.sub(prefix, -1) == ":" then
		return prefix .. " " .. sceneText .. whitespace .. formattingSuffix
	end

	return prefix .. ": " .. sceneText .. whitespace .. formattingSuffix
end

local function stripLocalizationMarkers(text)
	return string.gsub(tostring(text), "[\30\31]", "")
end

local function applyGhostsNSkullsArcadeResult(self, controllerIndex)
	if not Engine.GetDvarBool(GNS_ARCADE_DVAR) then
		return false
	end

	local result = Engine.GetDvarInt(GNS_ARCADE_RESULT_DVAR)
	if result ~= 1 and result ~= 2 then
		print(
			"[IWZ][PostGameUI] Ghosts N Skulls Arcade result unavailable controller="
				.. tostring(controllerIndex) .. " value=" .. tostring(result)
		)
		return false
	end

	local requiredElements = {
		"Title",
		"TimeSurvived",
		"MatchEnded",
		"YouWon",
		"YouFailed"
	}
	for _, elementName in ipairs(requiredElements) do
		if self[elementName] == nil then
			print(
				"[IWZ][PostGameUI] Ghosts N Skulls Arcade result skipped controller="
					.. tostring(controllerIndex) .. " missingElement=" .. elementName
			)
			return false
		end
	end

	self.Title:SetAlpha(0, 0)
	self.TimeSurvived:SetAlpha(0, 0)
	self.MatchEnded:SetAlpha(0, 0)
	self.YouWon:SetAlpha(0, 0)
	self.YouFailed:SetAlpha(0, 0)

	-- These are normally hidden when no Boss Battle result splash is active.
	-- Keep them hidden explicitly because Arcade mode has no boss description
	-- or boss timer to present beneath its outcome.
	if self.BossTimer then
		self.BossTimer:SetAlpha(0, 0)
	end
	if self.bossDescText then
		self.bossDescText:SetAlpha(0, 0)
	end

	local resultText
	if result == 1 then
		resultText = "YOU WIN!"
		self.YouWon:setText(resultText, 0)
		self.YouWon:SetAlpha(1, 0)
	else
		resultText = "THE SKULLS ESCAPED..."
		self.YouFailed:setText(resultText, 0)
		self.YouFailed:SetAlpha(1, 0)
	end

	print(
		"[IWZ][PostGameUI] Ghosts N Skulls Arcade result applied controller="
			.. tostring(controllerIndex) .. " value=" .. tostring(result)
			.. " text=\"" .. resultText .. "\""
			.. " hidden=MatchEnded,Title,TimeSurvived,BossTimer,BossDescription"
	)
	return true
end

MenuBuilder.m_types["BroShotZomScreen"] = function(menu, controller)
	local self = originalBroShotZomScreen(menu, controller)
	local controllerIndex = controller and controller.controllerIndex
	if not controllerIndex and not Engine.InFrontend() then
		controllerIndex = self:getRootController()
	end

	if applyGhostsNSkullsArcadeResult(self, controllerIndex) then
		return self
	end

	local waveNumber = DataSources.inGame.CP.zombies.waveNumber
	local lastLoggedScene = nil

	if not self.Title then
		print("[IWZ][PostGameUI] scene label fix skipped: game-over Title is unavailable")
		return self
	end

	local function updateSceneLabel()
		local scene = waveNumber:GetValue(controllerIndex)
		if scene == nil then
			return
		end

		local stockText = LocalizeIntoString(scene, "CP_ZOMBIE_ROUNDS_SURVIVED_CAPS")
		local punctuatedText = addSceneLabelColon(stockText, scene)

		if punctuatedText then
			self.Title:setText(punctuatedText, 0)

			if lastLoggedScene ~= scene then
				lastLoggedScene = scene
				print(
					"[IWZ][PostGameUI] punctuated game-over scene label controller="
						.. tostring(controllerIndex)
						.. " scene=" .. tostring(scene)
						.. " text=\"" .. stripLocalizationMarkers(punctuatedText) .. "\""
						.. " source=BroShotZomScreen.Title"
				)
			end
		elseif lastLoggedScene ~= scene then
			lastLoggedScene = scene
			print(
				"[IWZ][PostGameUI] scene label punctuation skipped: localized value does not end in scene number controller="
					.. tostring(controllerIndex)
					.. " scene=" .. tostring(scene)
					.. " text=\"" .. stripLocalizationMarkers(stockText) .. "\""
			)
		end
	end

	self.Title:SubscribeToModel(waveNumber:GetModel(controllerIndex), updateSceneLabel)
	updateSceneLabel()

	return self
end

print("[IWZ][PostGameUI] installed game-over scene label punctuation fix")
