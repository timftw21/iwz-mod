if Engine.InFrontend() or Engine.GetDvarString("ui_mapname") ~= "cp_final" then
	return
end

print("[IWZ][BeastFixes] UI script loading")

if MenuBuilder.m_types["InventoryDLC4"] == nil then
	require("inGame.cp.InventoryDLC4")
end

local originalInventoryDLC4 = MenuBuilder.m_types["InventoryDLC4"]

if originalInventoryDLC4 == nil then
	print("[IWZ][BeastFixes] InventoryDLC4 unavailable; seam patch not installed")
	return
end

local loggedInventoryFix = false

MenuBuilder.m_types["InventoryDLC4"] = function(menu, controller)
	local self = originalInventoryDLC4(menu, controller)
	local questBar = self.QuestBarDLC4

	if questBar and questBar.inventoryBacking then
		-- Recovered stock geometry places InventoryDLC4 four pixels below the
		-- screen while its backing stops at local Y 1075.46. Extend only that
		-- backing to local Y 1084, yielding eight pixels of bottom overscan.
		questBar.inventoryBacking:SetAnchorsAndPosition(0, 1, 0, 1,
			0, _1080p * 1920, _1080p * 819.46, _1080p * 1084)

		if not loggedInventoryFix then
			print("[IWZ][BeastFixes] extended InventoryDLC4 backing over bottom seam (parentY=4 localBottom=1084)")
			loggedInventoryFix = true
		end
	end

	return self
end

print("[IWZ][BeastFixes] InventoryDLC4 seam patch registered")
