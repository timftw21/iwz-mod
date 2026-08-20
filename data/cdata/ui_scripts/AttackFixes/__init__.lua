if Engine.InFrontend() or Engine.GetDvarString("ui_mapname") ~= "cp_town" then
	return
end

print("[IWZ][AttackFixes] UI script loading")

if MenuBuilder.m_types["InventoryDLC3"] == nil then
	require("inGame.cp.InventoryDLC3")
end

if MenuBuilder.m_types["MainPlayerInfoDLC3"] == nil then
	require("inGame.cp.MainPlayerInfoDLC3")
end

if MenuBuilder.m_types["inventoryNagWidget"] == nil then
	require("inGame.cp.inventoryNagWidget")
end

local originalInventoryDLC3 = MenuBuilder.m_types["InventoryDLC3"]
local originalMainPlayerInfoDLC3 = MenuBuilder.m_types["MainPlayerInfoDLC3"]
local loggedInventoryFix = false
local loggedChemicalFix = false
local loggedBatteryFix = false

if originalInventoryDLC3 ~= nil then
	MenuBuilder.m_types["InventoryDLC3"] = function(menu, controller)
		local self = originalInventoryDLC3(menu, controller)
		local questBar = self.questBarDLC3

		if questBar and questBar.InventoryBar then
			-- The material's transparent right padding leaves a narrow seam even
			-- though stock nominally overscans the display. Extend only the backing.
			questBar.InventoryBar:SetAnchorsAndPosition(0, 1, 0, 1,
				_1080p * -64, _1080p * 1992, _1080p * 568, _1080p * 1080)

			if not loggedInventoryFix then
				print("[IWZ][AttackFixes] extended InventoryDLC3 backing past right edge")
				loggedInventoryFix = true
			end
		end

		return self
	end
else
	print("[IWZ][AttackFixes] InventoryDLC3 unavailable; seam patch not installed")
end

if originalMainPlayerInfoDLC3 ~= nil then
	MenuBuilder.m_types["MainPlayerInfoDLC3"] = function(menu, controller)
		local self = originalMainPlayerInfoDLC3(menu, controller)

		if self.elementName then
			-- Stock provides only 257 pixels and permits word wrapping. The carried
			-- chemical label has room up to the perk rail, so use it without wrapping.
			self.elementName:SetWordWrap(false)
			self.elementName:SetAnchorsAndPosition(0, 1, 0, 1,
				_1080p * 200.5, _1080p * 640, _1080p * 152.94, _1080p * 174.94)

			if not loggedChemicalFix then
				print("[IWZ][AttackFixes] widened carried-chemical label and disabled wrapping")
				loggedChemicalFix = true
			end
		end

		return self
	end
else
	print("[IWZ][AttackFixes] MainPlayerInfoDLC3 unavailable; chemical label patch not installed")
end

if MenuBuilder.m_types["inventoryNagWidget"] ~= nil then
	local function buildSuppressedInventoryNagWidget(menu, controller)
		-- Recovered stock geometry from inventorynagwidget.lua. The original has
		-- no gameplay role: it only subscribes to zm_nag_text and animates one text
		-- child. Install an inert constructor instead of wrapping the generated
		-- registry trampoline, which can recursively rebuild the entire Zombies HUD.
		local self = LUI.UIElement.new()
		self:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 538, 0, _1080p * 52)
		self.id = "inventoryNagWidget"
		self._animationSets = {}
		self._sequences = {}

		if not loggedBatteryFix then
			print("[IWZ][AttackFixes] installed inert battery inventory-nag widget; stock battery icon binding preserved")
			loggedBatteryFix = true
		end

		return self
	end

	MenuBuilder.m_types["inventoryNagWidget"] = buildSuppressedInventoryNagWidget
else
	print("[IWZ][AttackFixes] inventoryNagWidget unavailable; battery nag patch not installed")
end

print("[IWZ][AttackFixes] Attack UI fixes registered")
