if Engine.InFrontend() or Engine.GetDvarString("ui_mapname") ~= "cp_zmb" then
	return
end

print("[IWZ][SpacelandFixes] UI script loading")

if MenuBuilder.m_types["Inventory"] == nil then
	require("inGame.cp.Inventory")
end

if MenuBuilder.m_types["inventoryNagWidget"] == nil then
	require("inGame.cp.inventoryNagWidget")
end

if MenuBuilder.m_types["questFullScreenSplash"] == nil then
	require("inGame.cp.questFullScreenSplash")
end

local originalInventory = MenuBuilder.m_types["Inventory"]
local originalQuestFullScreenSplash = MenuBuilder.m_types["questFullScreenSplash"]

local loggedInventoryFix = false
local loggedDoubleXPIconsRemoved = false
local loggedSetiComPartsPopupBacking = false
local loggedInventoryNagLayout = false

if originalQuestFullScreenSplash ~= nil then
	MenuBuilder.m_types["questFullScreenSplash"] = function(menu, controller)
		local self = originalQuestFullScreenSplash(menu, controller)
		local recorderWidget = self.questRecorderWidget
		local recorderBacking = recorderWidget and recorderWidget.Backing

		if recorderBacking then
			-- SETI-COM's calculator/radio/umbrella pickup uses questRecorderWidget.
			-- Match the solid #232323 backing used by the other Spaceland quest
			-- pickup widgets (robot, ark, and tooth), not the full inventory texture.
			recorderBacking:SetRGBFromInt(2302755, 0)

			if not loggedSetiComPartsPopupBacking then
				print("[IWZ][SpacelandFixes] matched SETI-COM parts popup backing to stock quest gray rgb=#232323")
				loggedSetiComPartsPopupBacking = true
			end
		end

		return self
	end
else
	print("[IWZ][SpacelandFixes] questFullScreenSplash unavailable; SETI-COM popup fix not installed")
end

if MenuBuilder.m_types["inventoryNagWidget"] ~= nil then
	MenuBuilder.m_types["inventoryNagWidget"] = function(menu, controller)
		-- This is the stock inventoryNagWidget recovered from the UI dump. Its
		-- subscription is rebuilt so the engine's later Scene 4/6 pulses cannot
		-- briefly run the stock Visible sequence before a wrapper can suppress it.
		local self = LUI.UIElement.new()
		self:SetAnchorsAndPosition(0, 1, 0, 1, 0, _1080p * 538, 0, _1080p * 52)
		self.id = "inventoryNagWidget"
		self._animationSets = {}
		self._sequences = {}
		local controllerIndex = controller and controller.controllerIndex

		if not controllerIndex and not Engine.InFrontend() then
			controllerIndex = self:getRootController()
		end
		assert(controllerIndex)

		local inventoryNag = LUI.UIText.new()
		inventoryNag.id = "InventoryNag"
		inventoryNag:setText(Engine.Localize("ZOMBIE_POWERUPS_INVENTORY_NAG"), 0)
		inventoryNag:SetFontSize(_1080p * 30)
		inventoryNag:SetFont(FONTS.GetFont(FONTS.MainBold.File))
		inventoryNag:SetAlignment(LUI.Alignment.Center)
		-- Preserve the stock centered horizontal layout and leave a readable gap
		-- below the clapboard.
		inventoryNag:SetAnchorsAndPosition(1, 0, 0, 1,
			_1080p * -535.5, _1080p * 5.5, _1080p * 20, _1080p * 52)
		self:addElement(inventoryNag)
		self.InventoryNag = inventoryNag

		if not loggedInventoryNagLayout then
			print("[IWZ][SpacelandFixes] installed post-Scene-1-only inventory nag centered top=20")
			loggedInventoryNagLayout = true
		end

		self._animationSets.DefaultAnimationSet = function()
			self._sequences.DefaultSequence = function()
			end

			inventoryNag:RegisterAnimationSequence("Hidden", {
				{
					function()
						return self.InventoryNag:SetAlpha(0, 0)
					end
				}
			})
			self._sequences.Hidden = function()
				inventoryNag:AnimateSequence("Hidden")
			end

			inventoryNag:RegisterAnimationSequence("Visible", {
				{
					function()
						return self.InventoryNag:SetAlpha(0, 0)
					end,
					function()
						return self.InventoryNag:SetAlpha(1, 260)
					end,
					function()
						return self.InventoryNag:SetAlpha(1, 2490)
					end,
					function()
						return self.InventoryNag:SetAlpha(0, 250)
					end
				},
				{
					function()
						return self.InventoryNag:SetScale(0, 0)
					end,
					function()
						return self.InventoryNag:SetScale(0, 260)
					end,
					function()
						return self.InventoryNag:SetScale(0.5, 340)
					end,
					function()
						return self.InventoryNag:SetScale(0, 410)
					end,
					function()
						return self.InventoryNag:SetScale(0.5, 420)
					end,
					function()
						return self.InventoryNag:SetScale(0, 410)
					end,
					function()
						return self.InventoryNag:SetScale(0.5, 430)
					end,
					function()
						return self.InventoryNag:SetScale(0, 480)
					end
				}
			})
			self._sequences.Visible = function()
				inventoryNag:AnimateSequence("Visible")
			end
		end

		self._animationSets.DefaultAnimationSet()
		local shownAfterSceneOne = false
		self:SubscribeToModel(
			DataSources.inGame.CP.zombies.quests.inventoryNagAlpha:GetModel(controllerIndex),
			function()
				local nagAlpha = DataSources.inGame.CP.zombies.quests.inventoryNagAlpha:GetValue(controllerIndex)

				if nagAlpha ~= nil and nagAlpha == 1 then
					local scene = tonumber(DataSources.inGame.CP.zombies.waveNumber:GetValue(controllerIndex))
					local shouldShow = scene == 2 and not shownAfterSceneOne

					print("[IWZ][SpacelandFixes] inventory nag trigger scene=" .. tostring(scene) ..
						" action=" .. (shouldShow and "show" or "suppress"))

					if shouldShow then
						shownAfterSceneOne = true
						ACTIONS.AnimateSequence(self, "Visible")
					end
				end
		end)
		ACTIONS.AnimateSequence(self, "Hidden")

		return self
	end
else
	print("[IWZ][SpacelandFixes] inventoryNagWidget unavailable; layout and Scene 1 gate not installed")
end

if originalInventory ~= nil then
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

		local doubleXPNotifications = self.DoubleXPNotifications

		if doubleXPNotifications then
			-- The stock Inventory always builds this global XP-status widget. It is not
			-- part of Spaceland's sticker inventory, so suppress its parent only here.
			doubleXPNotifications:SetAlpha(0, 0)

			if not loggedDoubleXPIconsRemoved then
				print("[IWZ][SpacelandFixes] hid Inventory DoubleXPNotifications widget")
				loggedDoubleXPIconsRemoved = true
			end
		end

		return self
	end
else
	print("[IWZ][SpacelandFixes] Inventory unavailable; inventory fixes not installed")
end

print("[IWZ][SpacelandFixes] Spaceland UI fixes registered")
