-- The stock Zombies AAR formatter reads frontEnd.lobby.mapName, which changes
-- whenever another film is selected. Rebuild the derived text from the map
-- captured by gameplay before returning to the frontend.

if not Engine.InFrontend() then
	return
end

local stockInitAARScoreboardDataSources = InitAARScoreboardDataSources
local MATCH_MAP_DVAR = "iwz_scoreboard_match_map"

if type(stockInitAARScoreboardDataSources) ~= "function" then
	print("[IWZ][Scoreboard] install skipped reason=InitAARScoreboardDataSources unavailable")
	return
end

if DataSources.frontEnd.AAR.iwzScoreboardFormatterInstalled then
	print("[IWZ][Scoreboard] install skipped reason=already installed")
	return
end

DataSources.frontEnd.AAR.iwzScoreboardFormatterInstalled = true

if MenuBuilder.m_types["CPAARScoreboard"] == nil then
	require("frontEnd.cp.CPAARScoreboard")
end

local originalCPAARScoreboard = MenuBuilder.m_types["CPAARScoreboard"]

if originalCPAARScoreboard then
	MenuBuilder.m_types["CPAARScoreboard"] = function(menu, controller)
		local self = originalCPAARScoreboard(menu, controller)
		local controllerIndex = controller and controller.controllerIndex or
			Engine.GetFirstActiveController()

		if self.DiagonalBackground then
			self.DiagonalBackground:SetAnchorsAndPosition(
				0.5, 0.5, 0, 1,
				_1080p * -1448, _1080p * 1464,
				_1080p * 205, _1080p * 681
			)
			print("[IWZ][Scoreboard] diagonal background moved controller=" ..
				tostring(controllerIndex) ..
				" stockY=155..631 correctedY=205..681 offsetY=50 tabBottomY=185")
		else
			print("[IWZ][Scoreboard] diagonal background move skipped controller=" ..
				tostring(controllerIndex) .. " reason=element unavailable")
		end

		return self
	end
else
	print("[IWZ][Scoreboard] diagonal background move install skipped " ..
		"reason=CPAARScoreboard unavailable")
end

local lastLoggedValues = {}
local cachedMapName = nil
local cachedMapRef = nil
local cachedMapSource = nil

local function printable(value)
	local text = tostring(value or "")
	local cleaned = string.gsub(text, "[\r\n\30\31]", "")
	return cleaned
end

local function nonEmptyValue(dataSource, controllerIndex)
	if dataSource == nil then
		return nil
	end

	local value = dataSource:GetValue(controllerIndex)
	if value == nil or tostring(value) == "" then
		return nil
	end

	return tostring(value)
end

local function mapDisplayName(mapRef)
	if mapRef == nil or mapRef == "" then
		return nil, "empty"
	end

	local mapCount = tonumber(Lobby.GetMapFeederCount()) or 0
	for index = 0, mapCount - 1 do
		local loadName = Lobby.GetMapLoadNameByIndex(index)
		if loadName ~= nil and string.lower(tostring(loadName)) ==
			string.lower(tostring(mapRef)) then
			return Lobby.GetMapNameByIndex(index), "lobby-index-" .. tostring(index)
		end
	end

	if CSV ~= nil and CSV.mpMapTable ~= nil then
		local localizationKey = Engine.TableLookup(CSV.mpMapTable.file,
			CSV.mpMapTable.cols.ref, mapRef, CSV.mpMapTable.cols.name)
		if localizationKey ~= nil and localizationKey ~= "" then
			return Engine.Localize(localizationKey), "mp-map-table"
		end
	end

	return tostring(mapRef), "raw-ref"
end

local function resolveMatchMap(controllerIndex)
	local capturedMapRef = Engine.GetDvarString(MATCH_MAP_DVAR)
	local aarMapName = nonEmptyValue(DataSources.frontEnd.AAR.mapName,
		controllerIndex)
	local lobbyMapName = nonEmptyValue(DataSources.frontEnd.lobby.mapName,
		controllerIndex)

	if capturedMapRef ~= nil and capturedMapRef ~= "" then
		local displayName, lookupSource = mapDisplayName(capturedMapRef)
		cachedMapName = displayName
		cachedMapRef = capturedMapRef
		cachedMapSource = "gameplay-capture/" .. lookupSource
	elseif aarMapName ~= nil then
		cachedMapName = aarMapName
		cachedMapRef = ""
		cachedMapSource = "frontEnd.AAR.mapName"
	elseif cachedMapName == nil and lobbyMapName ~= nil then
		-- On the first post-match initialization the selected film is still the
		-- film just played. Cache it once; never follow later lobby selections.
		cachedMapName = lobbyMapName
		cachedMapRef = ""
		cachedMapSource = "initial-lobby-cache"
	end

	return cachedMapName or "", cachedMapRef or "", cachedMapSource or "missing",
		capturedMapRef or "", aarMapName or "", lobbyMapName or ""
end

local function formatElapsedTime(seconds)
	local hours = math.floor(seconds / 3600)
	if hours > 0 then
		local minutes = math.floor(seconds / 60 - hours * 60)
		return string.format("%.2d:%.2d:%.2d", hours, minutes,
			math.floor(seconds - hours * 60 * 60 - minutes * 60))
	end

	local minutes = math.floor(seconds / 60)
	return string.format("%.2d:%.2d", minutes,
		math.floor(seconds - minutes * 60))
end

local function formatTimeSurvived(timeSurvived, controllerIndex)
	local seconds = tonumber(timeSurvived) or 0
	local mapName, mapRef, mapSource, capturedMapRef, aarMapName,
		lobbyMapName = resolveMatchMap(controllerIndex)
	local timePlayedLabel = Engine.Localize("LUA_MENU_TIME_PLAYED_CAPS")
	timePlayedLabel = string.gsub(timePlayedLabel or "TIME PLAYED", ":%s*$", "")
	local finalText = mapName .. " - " .. timePlayedLabel .. ": " ..
		formatElapsedTime(seconds)
	local logKey = tostring(controllerIndex)
	local signature = table.concat({
		printable(seconds),
		printable(mapRef),
		printable(mapSource),
		printable(capturedMapRef),
		printable(aarMapName),
		printable(lobbyMapName),
		printable(finalText)
	}, "|")

	if lastLoggedValues[logKey] ~= signature then
		lastLoggedValues[logKey] = signature
		print("[IWZ][Scoreboard] formatted controller=" ..
			tostring(controllerIndex) .. " seconds=" .. tostring(seconds) ..
			" map=\"" .. printable(mapName) .. "\" mapRef=\"" ..
			printable(mapRef) .. "\" mapSource=" .. printable(mapSource) ..
			" capturedRef=\"" .. printable(capturedMapRef) ..
			"\" aarMap=\"" .. printable(aarMapName) .. "\" lobbyMap=\"" ..
			printable(lobbyMapName) .. "\" punctuation=explicit" ..
			" text=\"" .. printable(finalText) .. "\"")
	end

	return finalText
end

InitAARScoreboardDataSources = function(controllerIndex)
	stockInitAARScoreboardDataSources(controllerIndex)

	if not Engine.IsAliensMode() then
		return
	end

	local timeSurvived = DataSources.frontEnd.AAR.timeSurvived
	if timeSurvived == nil then
		print("[IWZ][Scoreboard] formatter activation failed controller=" ..
			tostring(controllerIndex) .. " reason=time data source unavailable")
		return
	end

	-- Use a unique filter name so HKS cannot reuse the stock `text` filter and
	-- its callback, which closes over the mutable lobby map data source.
	DataSources.frontEnd.AAR.timeSurvivedText = timeSurvived:Filter(
		"iwzScoreboardText", formatTimeSurvived)

	local mapName, mapRef, mapSource, capturedMapRef, aarMapName,
		lobbyMapName = resolveMatchMap(controllerIndex)
	print("[IWZ][Scoreboard] formatter activated controller=" ..
		tostring(controllerIndex) .. " map=\"" .. printable(mapName) ..
		"\" mapRef=\"" .. printable(mapRef) .. "\" mapSource=" ..
		printable(mapSource) .. " capturedRef=\"" ..
		printable(capturedMapRef) .. "\" aarMap=\"" ..
		printable(aarMapName) .. "\" lobbyMap=\"" ..
		printable(lobbyMapName) .. "\"")
end

print("[IWZ][Scoreboard] installed Zombies AAR map ownership, TIME PLAYED punctuation, " ..
	"and diagonal background layout fixes")
