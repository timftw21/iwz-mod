if Engine.InFrontend() or Engine.GetDvarString("ui_mapname") ~= "cp_zmb" then
	return
end

print("[IWZ][SpacelandFixes] UI script loading")

if MenuBuilder.m_types["Inventory"] == nil then
	require("inGame.cp.Inventory")
end

local originalInventory = MenuBuilder.m_types["Inventory"]

if originalInventory == nil then
	print("[IWZ][SpacelandFixes] Inventory unavailable; seam patch not installed")
	return
end

local loggedInventoryFix = false

MenuBuilder.m_types["Inventory"] = function(menu, controller)
	local self = originalInventory(menu, controller)
	local stickerPack = self.StickerPack

	if stickerPack and stickerPack.pinkGradiant then
		-- Stock stops this full-width backing 2.47 pixels above the screen edge.
		stickerPack.pinkGradiant:SetAnchorsAndPosition(0, 0, 1, 0,
			0, 0, _1080p * -186.57, _1080p * 8)

		if not loggedInventoryFix then
			print("[IWZ][SpacelandFixes] extended Inventory backing over bottom seam")
			loggedInventoryFix = true
		end
	end

	return self
end

print("[IWZ][SpacelandFixes] Inventory seam patch registered")
