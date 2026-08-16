if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

print("[IWZ][ZombiesHUD] shared HUD fixes loading")

if MenuBuilder.m_types["ConsumableActivate"] == nil then
	require("inGame.cp.ConsumableActivate")
end

local originalConsumableActivate = MenuBuilder.m_types["ConsumableActivate"]

if originalConsumableActivate == nil then
	print("[IWZ][ZombiesHUD] ConsumableActivate unavailable; card-ready offset not installed")
	return
end

local CARD_READY_RAISE = 30
local loggedCardReadyFix = false

MenuBuilder.m_types["ConsumableActivate"] = function(menu, controller)
	local self = originalConsumableActivate(menu, controller)

	-- The stock widget is bottom-anchored and extends into the perk strip. Keep
	-- its parent placement intact and raise every visual inside it by 30 pixels.
	self.BackingBox:SetAnchorsAndPosition(0, 1, 0, 1,
		0, _1080p * 401, _1080p * (2 - CARD_READY_RAISE), _1080p * (30 - CARD_READY_RAISE))
	self.ConsumableUpName:SetAnchorsAndPosition(0, 1, 0, 1,
		0, _1080p * 386, _1080p * (2 - CARD_READY_RAISE), _1080p * (28 - CARD_READY_RAISE))
	self.Activated:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * 106, _1080p * 606, _1080p * (83 - CARD_READY_RAISE), _1080p * (113 - CARD_READY_RAISE))
	self.Ready:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * -50, _1080p * 451, _1080p * (35 - CARD_READY_RAISE), _1080p * (57 - CARD_READY_RAISE))
	self.ActivateText:SetAnchorsAndPosition(0, 1, 0, 1,
		_1080p * -50, _1080p * 451, _1080p * (60 - CARD_READY_RAISE), _1080p * (82 - CARD_READY_RAISE))

	if not loggedCardReadyFix then
		print("[IWZ][ZombiesHUD] raised ConsumableActivate visuals by 30 pixels")
		loggedCardReadyFix = true
	end

	return self
end

print("[IWZ][ZombiesHUD] card-ready offset registered")
