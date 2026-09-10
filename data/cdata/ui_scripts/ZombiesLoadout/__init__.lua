if not Engine.InFrontend() then
	return
end

local function log(message)
	print("[IWZ][LoadoutUI] " .. message)
end

local patches = {}
local function wrapBuilder(stock, patch)
	return function(menu, controller)
		local self = stock(menu, controller)
		if Engine.IsAliensMode() then patch(self, controller.controllerIndex) end
		return self
	end
end
-- Follow the engine's menu registration order instead of importing menus at boot.
local registerType = MenuBuilder.registerType
MenuBuilder.registerType = function(name, builder)
	if patches[name] then builder = wrapBuilder(builder, patches[name]) end
	return registerType(name, builder)
end
local function patchBuilder(name, patch)
	patches[name] = patch
	local stock = MenuBuilder.m_types[name]
	if stock then MenuBuilder.m_types[name] = wrapBuilder(stock, patch) end
end

patchBuilder("LevelInfo", function(self)
	-- Match RankProgression (the pause-menu weapon widget): concentric squares
	-- of 130/120/144px. LevelInfo's stretched 115x114/107x106/125x124px
	-- layers do not share that geometry; cropping their edges cannot fix it.
	local function ring(element, radius)
		element:SetAnchorsAndPosition(0, 1, 0.5, 0.5,
			_1080p * (56 - radius), _1080p * (56 + radius),
			_1080p * -radius, _1080p * radius, 0)
	end
	ring(self.ProgressbarBack, 65)
	ring(self.ProgressbarBackCenter, 65)
	ring(self.ProgressbarBackRim, 60)
	ring(self.LevelBar, 72)
	self.ProgressNode:SetAnchorsAndPosition(0, 1, 0.5, 0.5,
		_1080p * 55, _1080p * 57, _1080p * -64, _1080p * -56, 0)
	log("weapon level dial uses RankProgression geometry rings=130/120/144; border crops removed")
end)

local function addTitleStrip(self)
	-- WeaponDetails owns the loadout's CPStrip; CACItemHeader has no CP strip.
	local header = self.CACItemHeader
	local stripe = LUI.UIImage.new()
	stripe.id = "CPStrip"
	stripe:SetRGBFromTable(SWATCHES.itemRarity.quality0, 0)
	stripe:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 11, 0, _1080p * 100)
	header:addElement(stripe)
	header.CPStrip = stripe
	log(self.id .. " title strip restored; matches WeaponDetails size")
	return stripe
end

patchBuilder("PersonalizeWeapon", function(self, controller)
	local stripe = addTitleStrip(self)
	stripe:SubscribeToModelThroughElement(self, "qualityColor", function()
		local color = self:GetDataSource().qualityColor:GetValue(controller)
		if color ~= nil then stripe:SetRGBFromInt(color, 0) end
	end)
end)

patchBuilder("ShowcaseLock", function(self)
	-- showcaselock.lua's CP animation set suppresses the entire frame and
	-- magnifies a 32px cp_wepbuild_lock. Use the stock full-size MP presentation.
	self._animationSets.DefaultAnimationSet()
	ACTIONS.AnimateSequence(self, "DefaultSequence")
	ACTIONS.AnimateSequence(self, "zombieResize")
	log("restored showcase lock frame material=icon_showcase_locked default=" ..
		tostring(game:isdefaultmaterial("icon_showcase_locked")))
end)

local tileLockLogged = false
patchBuilder("PersonalizeItem", function(self)
	self.LockImage:setImage(RegisterMaterial("icon_slot_locked"), 0)
	local stripe = LUI.UIImage.new()
	stripe.id = "IWZTitleStripe"
	stripe:SetAlpha(0.65, 0)
	stripe:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 6, 0, _1080p * 24)
	self:addElement(stripe)
	if not tileLockLogged then
		log("personalization tile lock uses icon_slot_locked")
		tileLockLogged = true
	end
end)

local function hideDescriptionNub(self)
	-- The MP divider crosses the taller Zombies font. Keep the undivided CP
	-- header, and stop its description animation from restoring the white nub.
	local nub = self.CACItemHeader.ItemDescriptionNub
	nub:SetAlpha(0, 0)
	nub:RegisterAnimationSequence("UpdateDescription", {{function()
		return nub:SetAlpha(0, 0)
	end}})
	log(self.id .. " description nub removed, including UpdateDescription animation")
end

for _, name in ipairs({"CamoSelect", "CosmeticAttachmentSelect", "ReticleSelect"}) do
	patchBuilder(name, function(self)
		addTitleStrip(self)
		hideDescriptionNub(self)
	end)
end
