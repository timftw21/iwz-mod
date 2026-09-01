local SPLASH_TABLE = "cp/zombies/zombie_splashtable.csv"
local CAMO_TABLE = "mp/camotable.csv"
local MENU_CAMOS_TABLE = "mp/menucamos.csv"
local CAMO_UNLOCK_TABLE = "mp/unlocks/camounlocks.csv"
local WEAPON_REF = "iw7_m1c"

local CAMOS = {
	{
		id = "NeonRot",
		index = "253",
		ref = "camo253",
		unlockRef = "iw7_m1c+camo253",
		-- Custom progression must not borrow a real weapon's analytics bucket.
		-- This saved IWZ dvar is readable by gameplay, native unlock rules, and UI.
		progressDvar = "iwz_neon_rot_headshots",
		requiredHeadshots = 5,
		resetRevisionDvar = "iwz_neon_rot_reset_revision",
		resetRevision = 2,
		splashRef = "iwz_camo_neon_rot_unlock"
	}
}

local CAMOS_BY_REF = {}
local CAMOS_BY_SPLASH_REF = {}
for _, camo in ipairs(CAMOS) do
	CAMOS_BY_REF[camo.ref] = camo
	CAMOS_BY_SPLASH_REF[camo.splashRef] = camo
end

local function log(message)
	print("[IWZ][ZombiesCamos] " .. message)
end

local function readProgress(controllerIndex, camo)
	return true, Engine.GetDvarInt(camo.progressDvar)
end

if Engine.InFrontend() then
	local controllerIndex = Engine.GetFirstActiveController()
	for _, camo in ipairs(CAMOS) do
		if controllerIndex ~= nil and controllerIndex >= 0 and
			Engine.GetDvarInt(camo.resetRevisionDvar) < camo.resetRevision then
			local beforeRead, before = readProgress(controllerIndex, camo)
			local writeSucceeded = pcall(
				Engine.SetDvarInt, camo.progressDvar, 0)
			local afterRead, after = readProgress(controllerIndex, camo)

			if writeSucceeded and afterRead and tonumber(after) == 0 then
				Engine.SetDvarInt(camo.resetRevisionDvar, camo.resetRevision)
				log("one-time progress reset completed camo=" .. camo.id ..
					" controller=" .. tostring(controllerIndex) ..
					" progressSource=saved-dvar progressRef=" .. camo.progressDvar ..
					" beforeRead=" .. tostring(beforeRead) ..
					" before=" .. tostring(before) .. " after=0 revision=" ..
					tostring(camo.resetRevision))
			else
				log("one-time progress reset deferred camo=" .. camo.id ..
					" controller=" .. tostring(controllerIndex) ..
					" progressSource=saved-dvar progressRef=" .. camo.progressDvar ..
					" beforeRead=" .. tostring(beforeRead) ..
					" before=" .. tostring(before) ..
					" writeSucceeded=" .. tostring(writeSucceeded) ..
					" afterRead=" .. tostring(afterRead) ..
					" after=" .. tostring(after))
			end
		end
	end

	-- Stock CamoSelect only evaluates Zombies unlock rules for Director's Cut
	-- (camo35); every other Zombies-category camo is treated as unlocked. Extend
	-- that decision point for custom camos and derive each result from the same
	-- independent persisted counter used by gameplay and its reset command.
	if LOADOUT ~= nil and LOADOUT.MakePersonalizationItemsListDataSource ~= nil and
		not LOADOUT.iwzZombiesCamoUnlockPatched then
		local stockMakePersonalizationItemsListDataSource =
			LOADOUT.MakePersonalizationItemsListDataSource

		LOADOUT.MakePersonalizationItemsListDataSource = function(
			modelPath, items, options, challengeData)
			if options ~= nil and options.equipmentRef == WEAPON_REF and
				options.isUnlockedFunc ~= nil then
				local stockIsUnlocked = options.isUnlockedFunc
				options.isUnlockedFunc = function(item)
					local camo = item ~= nil and CAMOS_BY_REF[item.ref] or nil
					if camo ~= nil then
						local progressRead, progress = readProgress(
							options.controllerIndex, camo)
						local unlocked = progressRead and
							progress >= camo.requiredHeadshots
						log("loadout unlock evaluation camo=" .. camo.id ..
							" controller=" ..
							tostring(options.controllerIndex) .. " weapon=" .. WEAPON_REF ..
							" ref=" .. camo.ref ..
							" progressSource=saved-dvar progressRef=" ..
							camo.progressDvar .. " progressRead=" ..
							tostring(progressRead) .. " progress=" .. tostring(progress) ..
							" threshold=" .. tostring(camo.requiredHeadshots) ..
							" unlocked=" .. tostring(unlocked))
						return unlocked
					end

					return stockIsUnlocked(item)
				end
			end

			return stockMakePersonalizationItemsListDataSource(
				modelPath, items, options, challengeData)
		end

		LOADOUT.iwzZombiesCamoUnlockPatched = true
		log("installed CamoSelect unlock evaluator weapon=" .. WEAPON_REF ..
			" customCamos=" .. tostring(#CAMOS))
	else
		log("CamoSelect unlock evaluator unavailable loadout=" ..
			tostring(LOADOUT ~= nil) .. " makeDataSource=" ..
			tostring(LOADOUT ~= nil and
				LOADOUT.MakePersonalizationItemsListDataSource ~= nil))
	end

	for _, camo in ipairs(CAMOS) do
		local camoRow = Engine.TableLookupGetRowNum(CAMO_TABLE, 1, camo.ref)
		local menuRow = Engine.TableLookupGetRowNum(
			MENU_CAMOS_TABLE, 0, camo.index)
		local unlockRow = Engine.TableLookupGetRowNum(
			CAMO_UNLOCK_TABLE, 0, camo.unlockRef)
		local progressRead, progress = readProgress(controllerIndex, camo)
		local nativeUnlocked = false
		local nativeUnlockRead = false
		if controllerIndex ~= nil and controllerIndex >= 0 then
			nativeUnlockRead, nativeUnlocked = pcall(
				Engine.IsUnlocked,
				controllerIndex,
				"unlock",
				camo.unlockRef,
				true
			)
		end
		log("frontend table audit camo=" .. camo.id ..
			" controller=" .. tostring(controllerIndex) ..
			" camoRow=" .. tostring(camoRow) ..
			" menuRow=" .. tostring(menuRow) ..
			" unlockRow=" .. tostring(unlockRow) ..
			" progressSource=saved-dvar progressRef=" .. camo.progressDvar ..
			" progressRead=" .. tostring(progressRead) ..
			" progress=" .. tostring(progress) ..
			" nativeUnlockRead=" .. tostring(nativeUnlockRead) ..
			" nativeUnlocked=" .. tostring(nativeUnlocked))
	end
	return
end

if not Engine.IsAliensMode() then
	return
end

if MenuBuilder.m_types["splashIconZom"] == nil then
	require("inGame.cp.splashIconZom")
end

local stockSplashIconZom = MenuBuilder.m_types["splashIconZom"]
if stockSplashIconZom == nil then
	log("Film splash icon widget unavailable type=splashIconZom")
	return
end

if not MenuBuilder.iwzZombiesCamoHexIconPatched then
	MenuBuilder.m_types["splashIconZom"] = function(menu, controller)
		local self = stockSplashIconZom(menu, controller)
		local controllerIndex = controller and controller.controllerIndex
		if controllerIndex == nil then
			controllerIndex = self:getRootController()
		end

		if self.Icon == nil then
			log("Film splash icon missing stock element type=splashIconZom")
			return self
		end

		local hexBackingMask = LUI.UIImage.new()
		hexBackingMask.id = "IWZHexBackingMask"
		hexBackingMask:SetUseAA(true)
		hexBackingMask:setImage(
			RegisterMaterial("splash_hex_backing_alpha_feather"), 0)
		hexBackingMask:SetAlpha(0, 0)
		hexBackingMask:SetScale(0.13, 0)
		hexBackingMask:SetAnchorsAndPosition(
			0, 1, 0, 1, 0, _1080p * 86, 0, _1080p * 86)
		self:addElement(hexBackingMask)
		self.IWZHexBackingMask = hexBackingMask

		local hexBacking = LUI.UIImage.new()
		hexBacking.id = "IWZHexBacking"
		hexBacking:SetUseAA(true)
		hexBacking:setImage(RegisterMaterial("splash_hex_backing"), 0)
		hexBacking:SetAlpha(0, 0)
		hexBacking:SetScale(0.13, 0)
		hexBacking:SetAnchorsAndPosition(
			0, 1, 0, 1, 0, _1080p * 86, 0, _1080p * 86)
		self:addElement(hexBacking)
		self.IWZHexBacking = hexBacking

		local hexContentIcon = LUI.UIImage.new()
		hexContentIcon.id = "IWZHexContentIcon"
		hexContentIcon:SetUseAA(true)
		hexContentIcon:SetAlpha(0, 0)
		hexContentIcon:SetScale(0.13, 0)
		hexContentIcon:SetAnchorsAndPosition(
			0, 1, 0, 1, _1080p * 7, _1080p * 79,
			_1080p * 7, _1080p * 79)
		hexContentIcon:SubscribeToModel(
			DataSources.inGame.MP.splashes.localPlayer.icon:GetModel(controllerIndex),
			function()
				local icon = DataSources.inGame.MP.splashes.localPlayer.icon:GetValue(
					controllerIndex)
				if icon ~= nil then
					hexContentIcon:setImage(RegisterMaterial(icon), 0)
				end
			end)
		self:addElement(hexContentIcon)
		self.IWZHexContentIcon = hexContentIcon
		hexContentIcon:SetMask(hexBackingMask)

		local showingSplashRef = nil
		local function updateIconShape()
			local splashIndex = tonumber(
				DataSources.inGame.MP.splashes.localPlayer.splashIndex:GetValue(
					controllerIndex))
			local splashRef = nil
			if splashIndex ~= nil and splashIndex >= 0 then
				splashRef = Engine.TableLookupByRow(
					SPLASH_TABLE, splashIndex, 0)
			end

			local customCamo = CAMOS_BY_SPLASH_REF[splashRef]
			local useHexIcon = customCamo ~= nil
			self.Icon:SetAlpha(useHexIcon and 0 or 1, 0)
			hexBackingMask:SetAlpha(useHexIcon and 1 or 0, 0)
			hexBacking:SetAlpha(useHexIcon and 1 or 0, 0)
			hexContentIcon:SetAlpha(useHexIcon and 1 or 0, 0)

			if useHexIcon and showingSplashRef ~= splashRef then
				log("Film camo icon activated camo=" .. customCamo.id ..
					" ref=" .. splashRef ..
					" row=" .. tostring(splashIndex) ..
					" widget=splashIconZom shape=hex backing=splash_hex_backing" ..
					" mask=splash_hex_backing_alpha_feather")
			end
			showingSplashRef = useHexIcon and splashRef or nil
		end

		hexContentIcon:SubscribeToModel(
			DataSources.inGame.MP.splashes.localPlayer.splashIndex:GetModel(
				controllerIndex),
			updateIconShape)
		updateIconShape()

		return self
	end

	MenuBuilder.iwzZombiesCamoHexIconPatched = true
	log("Film-specific camo icon port ready widget=splashIconZom films=5" ..
		" shape=hex customCamos=" .. tostring(#CAMOS) ..
		" stockMeritIcons=unchanged")
end
