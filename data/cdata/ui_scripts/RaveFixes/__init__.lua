if Engine.InFrontend() or Engine.GetDvarString("ui_mapname") ~= "cp_rave" then
	return
end

print("[IWZ][RaveFixes] UI script loading")

if MenuBuilder.m_types["InventoryDLC1"] == nil then
	require("inGame.cp.InventoryDLC1")
end

local originalInventoryDLC1 = MenuBuilder.m_types["InventoryDLC1"]

if originalInventoryDLC1 == nil then
	print("[IWZ][RaveFixes] InventoryDLC1 unavailable; seam patch not installed")
	return
end

local loggedInventoryFix = false

MenuBuilder.m_types["InventoryDLC1"] = function(menu, controller)
	local self = originalInventoryDLC1(menu, controller)
	local photoPack = self.PhotoPackDLC1

	if photoPack and photoPack.fractalBacking then
		-- Stock leaves the right and bottom screen edges slightly uncovered.
		-- Preserve the backing's vertical placement and add enough overscan for scaling.
		photoPack.fractalBacking:SetAnchorsAndPosition(0, 0, 1, 0,
			_1080p * -4, _1080p * 8, _1080p * -483.47, _1080p * 8)

		if not loggedInventoryFix then
			print("[IWZ][RaveFixes] extended InventoryDLC1 backing over right/bottom seams")
			loggedInventoryFix = true
		end
	end

	return self
end

print("[IWZ][RaveFixes] InventoryDLC1 seam patch registered")
