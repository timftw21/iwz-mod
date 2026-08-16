if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

print("[IWZ][LowHealth] Zombies low-health overlay replacement loading")

if MenuBuilder.m_types["ZomPlayerDamageFlash"] == nil then
	require("inGame.cp.ZomPlayerDamageFlash")
end

if MenuBuilder.m_types["ZomPlayerDamageFlash"] == nil then
	print("[IWZ][LowHealth] ZomPlayerDamageFlash unavailable; replacement not installed")
	return
end

local STOCK_BLOOD_ALPHA = 0.85
local DEFAULT_BLOOD_ALPHA = 0.75
local STOCK_BLOOD_SCALE = 0.10
local DEFAULT_BLOOD_SCALE = 0.25

local function getBloodAlpha()
	local alpha = Engine.GetDvarFloat("iwz_low_health_blood_alpha")
	if alpha == nil then
		alpha = DEFAULT_BLOOD_ALPHA
	end

	return math.max(0, math.min(STOCK_BLOOD_ALPHA, alpha))
end

local function getBloodScale()
	local scale = Engine.GetDvarFloat("iwz_low_health_blood_scale")
	if scale == nil then
		scale = DEFAULT_BLOOD_SCALE
	end

	return math.max(STOCK_BLOOD_SCALE, math.min(1, scale))
end

local function buildZomPlayerDamageFlash(menu, controller)
	local self = LUI.UIElement.new()
	self:SetAnchorsAndPosition(0, 1, 0, 1, 0, 1920 * _1080p, 0, 1080 * _1080p)
	self.id = "ZomPlayerDamageFlash"
	self._animationSets = {}
	self._sequences = {}

	local controllerIndex = controller and controller.controllerIndex
	if controllerIndex == nil and not Engine.InFrontend() then
		controllerIndex = self:getRootController()
	end
	assert(controllerIndex)

	local Blood = LUI.UIImage.new()
	Blood.id = "Blood"
	Blood:SetAlpha(0, 0)
	Blood:SetScale(getBloodScale(), 0)
	Blood:setImage(RegisterMaterial("overlay_low_health"), 0)
	Blood:SetAnchorsAndPosition(0, 0, 0, 0,
		_1080p * 4.33, _1080p * -3.67, _1080p * 12.43, _1080p * -15.57)
	self:addElement(Blood)
	self.Blood = Blood

	local Flash = LUI.UIImage.new()
	Flash.id = "Flash"
	Flash:SetRGBFromInt(13718355, 0)
	Flash:SetAlpha(0, 0)
	Flash:SetScale(0.16, 0)
	Flash:SetAnchorsAndPosition(0, 0, 0, 0,
		_1080p * -10000, _1080p * 10000, _1080p * -10000, _1080p * 10000)
	self:addElement(Flash)
	self.Flash = Flash

	self._animationSets.DefaultAnimationSet = function()
		self._sequences.DefaultSequence = function()
		end

		Flash:RegisterAnimationSequence("Flash", {{
			function()
				return self.Flash:SetAlpha(0.4, 0)
			end,
			function()
				return self.Flash:SetAlpha(0.25, 110)
			end,
			function()
				return self.Flash:SetAlpha(0, 110, LUI.EASING.outSine)
			end
		}})
		self._sequences.Flash = function()
			Flash:AnimateSequence("Flash")
		end

		Blood:RegisterAnimationSequence("bloodOn", {{
			function()
				return self.Blood:SetAlpha(getBloodAlpha(), 0)
			end
		}})
		self._sequences.bloodOn = function()
			Blood:AnimateSequence("bloodOn")
		end

		Blood:RegisterAnimationSequence("bloodOff", {{
			function()
				return self.Blood:SetAlpha(getBloodAlpha(), 40)
			end,
			function()
				return self.Blood:SetAlpha(0, 460)
			end
		}})
		self._sequences.bloodOff = function()
			Blood:AnimateSequence("bloodOff")
		end
	end

	self._animationSets.DefaultAnimationSet()
	Blood:SubscribeToModel(DataSources.inGame.CP.zombies.playerHealthBlood:GetModel(controllerIndex), function()
		local bloodState = DataSources.inGame.CP.zombies.playerHealthBlood:GetValue(controllerIndex)
		if bloodState == 1 then
			Blood:SetScale(getBloodScale(), 0)
			print("[IWZ][LowHealth] transition=on controller=" .. tostring(controllerIndex) ..
				" targetAlpha=" .. tostring(getBloodAlpha()) ..
				" scale=" .. tostring(getBloodScale()) .. " fadeIn=0ms")
			ACTIONS.AnimateSequence(self, "bloodOn")
		elseif bloodState == 0 then
			print("[IWZ][LowHealth] transition=off controller=" .. tostring(controllerIndex))
			ACTIONS.AnimateSequence(self, "bloodOff")
		end
	end)
	Flash:SubscribeToModel(DataSources.inGame.CP.zombies.playerDamagedFlash:GetModel(controllerIndex), function()
		if DataSources.inGame.CP.zombies.playerDamagedFlash:GetValue(controllerIndex) == 1 then
			ACTIONS.AnimateSequence(self, "Flash")
		end
	end)

	-- CGLowHealthOverlay draws at its native fullscreen rectangle and ignores
	-- UIImage transforms. The health model above already controls visibility,
	-- so use the normal UIImage renderer to make alpha and scale effective.
	print("[IWZ][LowHealth] widget created controller=" .. tostring(controllerIndex) ..
		" bloodAlpha=" .. tostring(getBloodAlpha()) ..
		" bloodScale=" .. tostring(getBloodScale()) ..
		" renderer=UIImage; damage flash unchanged")
	return self
end

MenuBuilder.m_types["ZomPlayerDamageFlash"] = buildZomPlayerDamageFlash
print("[IWZ][LowHealth] full ZomPlayerDamageFlash replacement registered")
