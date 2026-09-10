if not Engine.InFrontend() then
	return
end

local function log(message)
	print("[IWZ][WeaponPrestige] " .. message)
end

local modules = {
	PersonalizeWeapon = "frontEnd.PersonalizeWeapon",
	Personalize_WeaponPrestigeBtn = "frontEnd.mp.Personalize_WeaponPrestigeBtn",
	EnterWeaponPrestigeWidget = "frontEnd.mp.EnterWeaponPrestigeWidget",
	ConfirmWeaponPrestigeWidget = "frontEnd.mp.ConfirmWeaponPrestigeWidget",
	AttachmentSelect = "frontEnd.mp.AttachmentSelect",
	WeaponAttachmentButton = "frontEnd.cp.WeaponAttachmentButton",
	CPWeaponSelect = "frontEnd.cp.CPWeaponSelect",
	CamoSelect = "frontEnd.mp.CamoSelect",
	CosmeticAttachmentSelect = "frontEnd.mp.CosmeticAttachmentSelect",
	ReticleSelect = "frontEnd.mp.ReticleSelect"
}
local builders = {}
local registerType = MenuBuilder.registerType
MenuBuilder.registerType = function(name, builder)
	if builders[name] then builder = builders[name](builder) end
	return registerType(name, builder)
end
local function wrapBuilder(name, wrap)
	builders[name] = wrap
	local stock = MenuBuilder.m_types[name]
	if stock then MenuBuilder.m_types[name] = wrap(stock) end
end
local function loadLoadoutMenus()
	local started = game:getmonotonicmilliseconds()
	local loaded = 0
	for name, moduleName in pairs(modules) do
		if not MenuBuilder.m_types[name] then
			require(moduleName)
			loaded = loaded + 1
		end
	end
	if loaded > 0 then log("loadout menu imports=" .. loaded .. " elapsedMs=" .. (game:getmonotonicmilliseconds() - started)) end
end

local SELECTIONS = "iwz_weapon_attachments"
local extraModels = {}
local function readSelections()
	local result = {}
	for weapon, attachment in string.gmatch(Engine.GetDvarString(SELECTIONS) or "", "(%d+):(%d+),") do
		result[weapon] = attachment
	end
	return result
end

local function weaponID(weapon)
	return Engine.TableLookup(CSV.MPWeapons.file, CSV.MPWeapons.cols.ref, weapon, CSV.MPWeapons.cols.index)
end

local function getExtra(weapon)
	local id = readSelections()[weaponID(weapon)]
	if not id then return "none" end
	local ref = Engine.TableLookup(CSV.MPAttachments.file, CSV.MPAttachments.cols.index, id, CSV.MPAttachments.cols.baseRef)
	return ref ~= "" and ref or "none"
end

local function saveExtra(weapon, ref)
	local id = weaponID(weapon)
	if not id or not string.match(id, "^%d+$") then error("Unknown prestige weapon " .. tostring(weapon)) end
	-- Update the wire-format entry directly. The former table serializer could
	-- produce an empty value and then mistakenly validate that empty round trip.
	local packed = string.gsub(Engine.GetDvarString(SELECTIONS) or "", "(%d+):(%d+),", function(key, value)
		return key == id and "" or key .. ":" .. value .. ","
	end)
	if ref ~= "none" then
		local attachmentID = Engine.TableLookup(CSV.MPAttachments.file, CSV.MPAttachments.cols.baseRef, ref, CSV.MPAttachments.cols.index)
		if not attachmentID or not string.match(attachmentID, "^%d+$") then error("Unknown prestige attachment " .. tostring(ref)) end
		packed = packed .. id .. ":" .. attachmentID .. ","
	end
	if #packed > 600 then error("Prestige attachment selections exceed userinfo capacity") end
	Engine.SetDvarString(SELECTIONS, packed)
	local decoded = getExtra(weapon)
	if Engine.GetDvarString(SELECTIONS) ~= packed or decoded ~= ref then
		error("Prestige attachment save failed weapon=" .. weapon .. " expected=" .. ref .. " decoded=" .. tostring(decoded))
	end
	log("saved weapon=" .. weapon .. " id=" .. id .. " sixthAttachment=" .. decoded .. " userinfo=" .. packed)
end

local stockMaxPrestige = Prestige.GetMaxPrestigeRank
Prestige.GetMaxPrestigeRank = function()
	return Engine.IsAliensMode() and 1 or stockMaxPrestige()
end

local stockPrestigeString = Prestige.GetPrestigeLevelString
Prestige.GetPrestigeLevelString = function(rank)
	return Engine.IsAliensMode() and tostring(rank) or stockPrestigeString(rank)
end

local stockCanPrestige = Prestige.CanActivateWeaponPrestige
Prestige.CanActivateWeaponPrestige = function(weapon, controller)
	if not Engine.IsAliensMode() then return stockCanPrestige(weapon, controller) end
	local maxRank = Cac.GetWeaponMaxRank(weapon)
	if not maxRank or maxRank <= 0 or Cac.GetWeaponPrestigeLevel(weapon, controller) >= 1 then return false end
	local progress = DataSources.alwaysLoaded.playerData.MP.common.sharedProgression.weaponLevel[weapon]
	return progress.mpXP:GetValue(controller) + progress.cpXP:GetValue(controller) >= Cac.GetWeaponRankMaxXP(maxRank)
end

local stockReset = Prestige.DoWeaponPrestigeReset
Prestige.DoWeaponPrestigeReset = function(weapon, controller)
	if not Engine.IsAliensMode() then return stockReset(weapon, controller) end
	if not Prestige.CanActivateWeaponPrestige(weapon, controller) then
		log("prestige rejected weapon=" .. weapon .. " eligibility changed")
		return
	end
	log("prestige requested weapon=" .. weapon .. " shared XP and attachments reset; reward=sixth attachment")
	-- Stock reset updates the native shared prestige field, clears BOTH XP
	-- buckets and unequips locked attachments/reticles in both modes.
	stockReset(weapon, controller)
	local extra = extraModels[tostring(controller) .. "." .. weapon]
	if extra then extra:SetValue(controller, "none") else saveExtra(weapon, "none") end
	local progress = DataSources.alwaysLoaded.playerData.MP.common.sharedProgression.weaponLevel[weapon]
	log("prestige result weapon=" .. weapon .. " prestige=" .. Cac.GetWeaponPrestigeLevel(weapon, controller) ..
		" mpXP=" .. progress.mpXP:GetValue(controller) .. " cpXP=" .. progress.cpXP:GetValue(controller))
end

local function cpBuilder(name, patch)
	wrapBuilder(name, function(stock)
		return function(menu, controller)
			local self = stock(menu, controller)
			if Engine.IsAliensMode() then patch(self, controller) end
			return self
		end
	end)
end

cpBuilder("PersonalizeWeapon", function(self, options)
	local controller = options.controllerIndex
	local weapon = self.weaponDataSource.weapon:GetValue(controller)
	local maxRank = Cac.GetWeaponMaxRank(weapon)
	if not maxRank or maxRank <= 0 then return end
	local list = self.PersonalizeButtonList
	local button = MenuBuilder.BuildRegisteredType("Personalize_WeaponPrestigeBtn", {controllerIndex = controller})
	button.id = "IWZWeaponPrestige"
	button.TitleText:setText("WEAPON PRESTIGE", 0)
	-- Match PersonalizeButtonList's MP post-construction override, rather than
	-- the reusable prestige widget's default skull (icon_weapon_prestige).
	button.BGImage:setImage(RegisterMaterial("icon_weapon_accessory"), 0)
	-- The other cards use Personalize_RigCustomizationAppearenceBtn's CP
	-- animation set: 30% artwork at rest, 70% when focused. Prestige has no CP set.
	button.BGImage:SetAlpha(0.3, 0)
	for _, sequence in ipairs({"ButtonUp", "ButtonUpDisabled"}) do
		button.BGImage:RegisterAnimationSequence(sequence, {{function()
			return button.BGImage:SetAlpha(0.3, 250)
		end}})
	end
	log("prestige artwork=icon_weapon_accessory source=PersonalizeButtonList idleAlpha=0.3 focusAlpha=0.7 default=" .. tostring(game:isdefaultmaterial("icon_weapon_accessory")))
	button.buttonDescription = "Prestige 1 permanently unlocks a sixth attachment slot. Weapon XP is shared with Multiplayer."
	button:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 622, _1080p * 358, _1080p * 516)
	list:addElement(button)
	list.PersonalizeWeaponPrestigeBtn = button
	list.AccessoryButton.navigation.down = button
	button.navigation = {up = list.AccessoryButton}
	button:InitFromWeaponDataSource(self.weaponDataSource, controller)
	local function updateReward()
		if Cac.GetWeaponPrestigeLevel(weapon, controller) >= 1 then
			button.UnlockConditionText:setText("SIXTH ATTACHMENT SLOT UNLOCKED", 0)
		end
	end
	button:addEventHandler("prestige_level_increased", updateReward)
	updateReward()
	log("personalize weapon=" .. weapon .. " prestige=" .. Cac.GetWeaponPrestigeLevel(weapon, controller) ..
		" eligible=" .. tostring(Prestige.CanActivateWeaponPrestige(weapon, controller)))
end)

cpBuilder("EnterWeaponPrestigeWidget", function(self)
	self.PrestigeMessage:setText("Unlock a sixth attachment slot in Zombies.\nWeapon level, XP and equipped attachments reset\nin both Zombies and Multiplayer.", 0)
	self:SetBottom(_1080p * 380, 0)
	self.PrestigeMessage:SetFontSize(_1080p * 20)
	-- UIText's anchor height is its glyph height, not its multiline block height.
	self.PrestigeMessage:SetAnchorsAndPosition(0.5, 0.5, 0, 1, _1080p * -285, _1080p * 285, 0, _1080p * 20)
	self.WeaponImage:SetTop(_1080p * 98, 0)
	self.WeaponImage:SetBottom(_1080p * 226, 0)
	self.RewardsLabel:SetTop(_1080p * 244, 0)
	self.RewardsLabel:SetBottom(_1080p * 264, 0)
	self.RewardsLabel:SetFontSize(_1080p * 20)
	self.RewardsLabel:setText("PRESTIGE 1 REWARD: SIXTH ATTACHMENT SLOT", 0)
	self.PopupButtonEnter:SetTop(_1080p * 290, 0)
	self.PopupButtonEnter:SetBottom(_1080p * 320, 0)
	self.PopupButtonCancel:SetTop(_1080p * 332, 0)
	self.PopupButtonCancel:SetBottom(_1080p * 362, 0)
	log("enter popup prestige=1 textHeight=20 lines=3")
end)

cpBuilder("ConfirmWeaponPrestigeWidget", function(self)
	self.Message:setText("Weapon prestige 1 reached.\nYour sixth attachment slot is unlocked in Zombies.", 0)
	self.Message:SetFontSize(_1080p * 20)
	self.Message:SetAnchorsAndPosition(0.5, 0.5, 0, 1, _1080p * -285, _1080p * 285, 0, _1080p * 20)
	self.WeaponImage:SetTop(_1080p * 80, 0)
	self.WeaponImage:SetBottom(_1080p * 208, 0)
	self.RewardsLabel:SetTop(_1080p * 218, 0)
	self.RewardsLabel:SetBottom(_1080p * 238, 0)
	self.RewardsLabel:SetFontSize(_1080p * 20)
	-- The stock popup receives the MP charm strings in its parameters. Replace
	-- its reward label as well as the confirmation text.
	if self.RewardsLabel then self.RewardsLabel:setText("SIXTH ATTACHMENT SLOT", 0) end
	log("confirm popup prestige=1 textHeight=20 lines=2")
end)

local stockSlotUnlocked = Cac.IsCPAttachmentSlotUnlocked
Cac.IsCPAttachmentSlotUnlocked = function(slot, weapon, controller)
	if Engine.IsAliensMode() and slot == 7 then return Cac.GetWeaponPrestigeLevel(weapon, controller) >= 1 end
	return stockSlotUnlocked(slot, weapon, controller)
end

local function candidates(data, controller)
	local categorized = Cac.GetCategorizedAttachmentList(data, controller)
	local category = categorized[Cac.AttachmentCategories.attachments]
	return category and category.attachments or {}
end

local function canUseExtra(weapon, ref, controller, data, equipped)
	if ref == "none" then return true end
	if Cac.GetWeaponPrestigeLevel(weapon, controller) < 1 then return false end
	data = data or WEAPON_BUILD.GetWeaponDataSourceForKey(weapon, controller)
	local found = false
	for _, item in ipairs(candidates(data, controller)) do
		if item.baseRef == ref then found = true; break end
	end
	-- AttachmentSelect explicitly unlocks individual attachments in CP. Weapon
	-- level gates the stock slots; prestige gates this extra slot.
	if not found then return false end
	if not equipped then
		equipped = {}
		for i = 0, 5 do table.insert(equipped, data.attachment[i]:GetValue(controller)) end
	end
	for _, other in ipairs(equipped) do
		if other ~= "none" and (Cac.GetAttachmentBaseRef(other) == ref or other == ref or
			not Cac.AreAttachmentsCompatible(ref, other) or not Cac.AreAttachmentsCompatible(other, ref)) then return false end
	end
	return true
end

local function extraModel(weapon, controller)
	local key = tostring(controller) .. "." .. weapon
	if extraModels[key] then return extraModels[key] end
	local model = LUI.DataSourceInGlobalModel.new("frontEnd.CP.iwzPrestige." .. key, getExtra(weapon))
	local setValue = model.SetValue
	model.SetValue = function(self, index, value)
		saveExtra(weapon, value)
		return setValue(self, index, value)
	end
	extraModels[key] = model
	return model
end

local stockDecorator = LOADOUT.GetLootWeaponDecorator
LOADOUT.GetLootWeaponDecorator = function(path, controller)
	local decorate = stockDecorator(path, controller)
	return function(key, raw)
		local data = decorate(key, raw)
		if not Engine.IsAliensMode() then return data end
		local weapon = raw.weapon:GetValue(controller)
		local ref = extraModel(weapon, controller)
		local root = "frontEnd.CP.iwzPrestigeSlot." .. controller .. "." .. weapon
		local unique = ref:Filter(root .. ".unique", function(value) return Cac.GetAttachmentRef(value, weapon) end)
		local extra = {
			ref = ref, index = 6, slot = 6,
			GetValue = function(_, c) return ref:GetValue(c) end,
			SetValue = function(_, c, value) return ref:SetValue(c, value) end,
			pointCost = LUI.DataSourceFromList.new(0),
			weaponRef = LUI.DataSourceInGlobalModel.new(root .. ".weapon", weapon),
			used = ref:Filter(root .. ".used", Cac.IsAttachmentSlotInUse),
			icon = unique:Filter(root .. ".icon", Cac.GetAttachmentImage),
			name = unique:Filter(root .. ".name", function(value)
				return value == "none" and "ATTACHMENT 6" or Cac.GetAttachmentName(value)
			end),
			desc = unique:Filter(root .. ".desc", Cac.GetAttachmentDesc),
			attachmentUniqueDataSource = unique,
			disabled = LUI.DataSourceInGlobalModel.new(root .. ".disabled", not Cac.DoesWeaponHaveAttachmentsByCategory(weapon, raw.lootItemID:GetValue(controller), controller, Cac.AttachmentCategories.attachments))
		}
		local original = data.attachmentsList
		local list = LUI.DataSourceFromList.new(7)
		list.MakeDataSourceAtIndex = function(_, index)
			if index == 6 then return extra end
			return original:GetDataSourceAtIndex(index, controller)
		end
		data.attachmentsList = list
		data.attachments.attachmentSlotSeven = extra
		data.iwzPrestigeAttachment = extra
		return data
	end
end

-- All stock focus events AND the used-model subscription call this routine.
-- Correct its slot-seven fallback here, after stock writes its level number.
local attachmentRefreshPatched = false
wrapBuilder("WeaponAttachmentButton", function(stock)
	return function(menu, options)
		if not attachmentRefreshPatched then
			local module = assert(package.loaded[modules.WeaponAttachmentButton])
			local animate = module.AnimateFramedAttachment
			module.AnimateFramedAttachment = function(self, focused, controller)
				animate(self, focused, controller)
				if not Engine.IsAliensMode() then return end
				local data = self:GetDataSource()
				if not data then return end
				local extra = data.index == 6
				self.LevelString:setText(extra and "PRESTIGE" or Engine.Localize("MENU_LEVEL_CAPS"), 0)
				if extra then self.unlockLevel:setText("1", 0) end
			end
			attachmentRefreshPatched = true
			log("attachment unlock label uses shared refresh routine; slot=7 requiredPrestige=1")
		end
		return stock(menu, options)
	end
end)

-- Stock AttachmentSelect keeps its slot models in a fixed six-entry table.
-- Extend that table after construction; no seventh DDL field is accessed.
local stockEquippedSlot = Cac.GetAttachmentSlotDataSourceByEquippedRef
Cac.GetAttachmentSlotDataSourceByEquippedRef = function(controller, data, ref)
	if Engine.IsAliensMode() and data.iwzPrestigeAttachment then
		local extra = data.iwzPrestigeAttachment
		if extra:GetValue(controller) == Cac.GetAttachmentBaseRef(ref) then return extra end
	end
	return stockEquippedSlot(controller, data, ref)
end

local function otherAttachments(data, controller, selected)
	local equipped = {}
	for i = 0, 5 do
		local ref = data.attachment[i]:GetValue(controller)
		-- Stock selection moves an already equipped attachment into the target slot.
		if ref ~= selected then equipped[#equipped + 1] = ref end
	end
	return equipped
end

local stockSelectAttachment = ACTIONS.OnSelectAttachment
ACTIONS.OnSelectAttachment = function(button, controller)
	local menu = button:GetCurrentMenu()
	local data = menu.playerDataWeaponDataSource
	if Engine.IsAliensMode() and data and data.iwzPrestigeAttachment then
		local ref = button:GetDataSource().baseRef
		local weapon = data.weapon:GetValue(controller)
		local slot = menu.attachmentSlot:GetValue(controller)
		if slot == 6 then
			if not canUseExtra(weapon, ref, controller, data, otherAttachments(data, controller, ref)) then
				log("attachment rejected weapon=" .. weapon .. " slot=6 ref=" .. ref)
				return
			end
		else
			local extra = getExtra(weapon)
			if extra ~= "none" and (extra == ref or not Cac.AreAttachmentsCompatible(extra, ref) or
				not Cac.AreAttachmentsCompatible(ref, extra)) then
				log("replaced sixth attachment weapon=" .. weapon .. " old=" .. extra .. " selected=" .. ref)
				data.iwzPrestigeAttachment:SetValue(controller, "none")
			end
		end
		log("stock attachment selection weapon=" .. weapon .. " slot=" .. slot .. " ref=" .. ref)
	end
	return stockSelectAttachment(button, controller)
end

wrapBuilder("AttachmentSelect", function(stockAttachmentSelect)
	return function(menu, options)
		if not Engine.IsAliensMode() then return stockAttachmentSelect(menu, options) end
		local data = options.currentWeaponDataSource
		if not data or not data.iwzPrestigeAttachment then return stockAttachmentSelect(menu, options) end
		local controller = options.controllerIndex
		local slot = options.attachmentSlot
		local settings = LUI.ShallowCopy(options)
		-- Initialize stock subscriptions with a native slot before enabling index 6.
		if slot == 6 then settings.attachmentSlot = 1 end
		local self = stockAttachmentSelect(menu, settings)
		self.attachmentDataSources[7] = data.iwzPrestigeAttachment
		local weapon = data.weapon:GetValue(controller)
		local dependencies = {self.attachmentSlot, data.iwzPrestigeAttachment.ref}
		for i = 0, 5 do dependencies[#dependencies + 1] = data.attachment[i] end
		for category, content in pairs(self.attachments.categories) do
			local list = content.attachmentList
			for i = 0, list:GetCountValue(controller) - 1 do
				local item = list:GetDataSourceAtIndex(i, controller)
				local ref = item.baseRef
				local path = "iwz." .. category .. "." .. ref
				-- Include the extra ref in subscriptions so stock equipped markers and
				-- conflict state update when either a native slot or the extra slot changes.
				item.equipped = LUI.AggregateDataSource.new(self.menuDataModel, dependencies, path .. ".equipped", function(c)
					return Cac.GetAttachmentSlotDataSourceByEquippedRef(c, data, ref) ~= nil
				end)
				item.equipIconAlpha = LUI.AggregateDataSource.new(self.menuDataModel, dependencies, path .. ".alpha", function(c)
					local equipped = Cac.GetAttachmentSlotDataSourceByEquippedRef(c, data, ref)
					if not equipped then return 0 end
					return equipped == self.attachmentDataSources[self.attachmentSlot:GetValue(c) + 1] and 1 or 0.5
				end)
				if slot == 6 then
					item.disabled = LUI.AggregateDataSource.new(self.menuDataModel, dependencies, path .. ".disabled", function(c)
						return not canUseExtra(weapon, ref, c, data, otherAttachments(data, c, ref))
					end)
				end
			end
		end
		if slot == 6 then self.attachmentSlot:SetValue(controller, slot) end
		-- Refresh stock tile bindings to the extended equipped/disabled models.
		self:SetDataSource(self:GetDataSource(), controller)
		log("stock AttachmentSelect weapon=" .. weapon .. " slot=" .. slot .. " availableSlots=7")
		return self
	end
end)

wrapBuilder("CPWeaponSelect", function(stockWeaponSelect)
	return function(menu, options)
		if not Engine.IsAliensMode() then return stockWeaponSelect(menu, options) end
		loadLoadoutMenus()
		local slotWidth, slotGap = 150, 16
		local rowWidth = 7 * slotWidth + 6 * slotGap
		local closedLeft, editLeft, dialLeft = 480, 130.5, 1708
		-- UIGrid defaults to a horizontal primary axis: a seventh item in the
		-- stock six-column grid becomes an invisible second row. Change the
		-- attachment grid's construction options and its matching layout together.
		local newGrid = LUI.UIDataSourceGrid.new
		local patched = false
		LUI.UIDataSourceGrid.new = function(state, settings)
			if settings.maxVisibleColumns == 6 and settings.maxVisibleRows == 1 and
				settings.columnWidth == _1080p * 160 and settings.rowHeight == _1080p * 120 then
				settings.maxVisibleColumns = 7
				settings.columnWidth = _1080p * slotWidth
				settings.spacingX = _1080p * slotGap
				local buildChild = settings.buildChild
				settings.buildChild = function()
					local child = buildChild()
					child:SetRight(_1080p * slotWidth, 0)
					return child
				end
				patched = true
			end
			return newGrid(state, settings)
		end
		local ok, self = pcall(stockWeaponSelect, menu, options)
		LUI.UIDataSourceGrid.new = newGrid
		if not ok then error(self) end
		assert(patched, "CP attachment grid layout changed")
		local grid = self.Attachments
		grid:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * closedLeft, _1080p * (closedLeft + rowWidth), _1080p * 810, _1080p * 930)
		local function gridSequence(name, left, alpha)
			grid:RegisterAnimationSequence(name, {
				{function() return grid:SetAlpha(alpha, 100) end},
				{function() return grid:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * left, _1080p * (left + rowWidth), _1080p * 810, _1080p * 930, 100) end}
			})
		end
		gridSequence("OpenedAttachmentSelection", editLeft, 1)
		gridSequence("ClosedAttachmentSelection", closedLeft, 0.8)
		-- LevelInfo has a 300px root; its Zombies dial occupies the first 115px.
		-- Keep that root width so the backing anchors retain their circular shape.
		local function positionDial()
			return self.WeaponLevel:SetAnchorsAndPosition(0, 1, 1, 0, _1080p * dialLeft, _1080p * (dialLeft + 300), _1080p * -253, _1080p * -167, 0)
		end
		positionDial()
		for _, name in ipairs({"OpenedAttachmentSelection", "ClosedAttachmentSelection"}) do
			self.WeaponLevel:RegisterAnimationSequence(name, {{positionDial}})
		end
		local function labelPosition(label, offset)
			label:SetLeft(_1080p * (closedLeft + offset), 0)
			label:SetRight(_1080p * (closedLeft + offset + slotWidth - 10), 0)
			local function sequence(name, left)
				label:RegisterAnimationSequence(name, {{function()
					return label:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * (left + offset), _1080p * (left + offset + slotWidth - 10), _1080p * 791, _1080p * 810, 100)
				end}})
			end
			sequence("ClosedAttachmentSelection", closedLeft)
			sequence("OpenedAttachmentSelection", editLeft)
		end
		labelPosition(self.OpticLabel, 5)
		labelPosition(self.AttachmentLabel, slotWidth + slotGap + 5)
		log("weapon selection grid slots=7 slotWidth=" .. slotWidth .. " gap=" .. slotGap .. " rowWidth=" .. rowWidth .. " left=" .. closedLeft .. " editLeft=" .. editLeft .. " dialLeft=" .. dialLeft)
		return self
	end
end)

local stockCompleteModel = Cac.GetCompleteWeaponModelName
Cac.GetCompleteWeaponModelName = function(base, weapon, quality, variant, camo, attachments, cosmetic)
	if Engine.IsAliensMode() then
		local controller = Engine.GetFirstActiveController()
		local ref = getExtra(base)
		if ref ~= "none" then
			local data = WEAPON_BUILD.GetWeaponDataSourceForKey(base, controller)
			-- Preview callbacks also run halfway through stock attachment moves.
			-- They must never erase saved equipment during that intermediate state.
			if canUseExtra(base, ref, controller, data, attachments) then
				attachments = LUI.ShallowCopy(attachments or {})
				table.insert(attachments, ref)
			end
		end
	end
	return stockCompleteModel(base, weapon, quality, variant, camo, attachments, cosmetic)
end

log("installed Zombies prestige cap=1; native shared reset; optic plus six attachments; menu imports deferred until loadout")
