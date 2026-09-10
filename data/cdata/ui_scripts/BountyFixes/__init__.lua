if not Engine.InFrontend() then
	return
end

print("[IWZ][BountyFixes] UI script loading")

if MenuBuilder.m_types["ContractProgress"] == nil then
	require("frontEnd.ContractProgress")
end

local originalContractProgress = MenuBuilder.m_types["ContractProgress"]

if originalContractProgress == nil then
	print("[IWZ][BountyFixes] ContractProgress unavailable; completed-layout patch not installed")
	return
end

local loggedCompleteLayout = false
local loggedActiveLayout = false

MenuBuilder.m_types["ContractProgress"] = function(menu, controller)
	local self = originalContractProgress(menu, controller)
	local originalSetupProgress = self.SetupProgress

	if originalSetupProgress == nil then
		print("[IWZ][BountyFixes] ContractProgress.SetupProgress unavailable on constructed widget")
		return self
	end

	self.SetupProgress = function(progress, controllerIndex, contractData)
		originalSetupProgress(progress, controllerIndex, contractData)

		if not Engine.IsAliensMode() then
			return
		end

		local complete = Contracts.CheckCompletion(controllerIndex, contractData.index)

		if complete then
			-- Stock hides only ProgressBar, leaving its black ProgressBackground
			-- strip visible from Y 100 to 128. Hide that remnant and center the
			-- 48-pixel label in the content area below the header (Y 36 to 130).
			progress.ProgressBackground:SetAlpha(0, 0)
			progress.ProgressBar:SetAlpha(0, 0)
			progress.ProgressText:SetAnchorsAndPosition(0, 0, 0.5, 0.5,
				_1080p * 23, _1080p * -10, _1080p * -6, _1080p * 42)

			if not loggedCompleteLayout then
				print("[IWZ][BountyFixes] applied completed layout hidden=ProgressBackground,ProgressBar textBoundsY=59,107 contentCenterY=83")
				loggedCompleteLayout = true
			end
		else
			-- Contract widgets can be reused when the menu refreshes. Restore every
			-- stock active-state property so incomplete bounties remain unchanged.
			progress.ProgressBackground:SetAlpha(0.5, 0)
			progress.ProgressBar:SetAlpha(1, 0)
			progress.ProgressText:SetAnchorsAndPosition(0, 0, 0.5, 0.5,
				_1080p * 23, _1080p * -10, _1080p * -16.5, _1080p * 31.5)

			if not loggedActiveLayout then
				print("[IWZ][BountyFixes] preserved active layout progressStrip=visible textBoundsY=48.5,96.5")
				loggedActiveLayout = true
			end
		end
	end

	return self
end

print("[IWZ][BountyFixes] completed-bounty layout patch registered")

-- Apply to resident or subsequently registered menus without importing them
-- during title-screen startup.
local patches = {}
local function wrapBuilder(stock, patch)
	return function(menu, controller)
		local self = stock(menu, controller)
		if Engine.IsAliensMode() then patch(self) end
		return self
	end
end
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

patchBuilder("ContractsButtonCP", function(self)
	-- MenuButton's CP animation fixes its visible background at 322px even
	-- though ContractsButtonCP's root is 340px wide.
	local background, border = self.ContractInfoBackground, self.Border
	local function position(element)
		element:SetAnchorsAndPosition(0, 1, 1, 0, 0, _1080p * 322, _1080p * -30, 0, 0)
	end
	position(background)
	position(border)
	border:SetAlpha(1, 0)
	local function style(focused)
		position(border)
		background:SetRGBFromInt(0, 0)
		background:SetAlpha(focused and 0.8 or 0.75, 0)
		border:SetBorderThicknessLeft(_1080p * (focused and 6 or 2), 0)
		border:SetBorderThicknessTop(0, 0)
		border:SetAlpha(focused and 1 or 0.2, 0)
		if focused then
			border:SetRGBFromTable(SWATCHES.Zombies.menuHeader, 0)
		else
			-- Match GenericListArrowButtonBackground's idle BorderBox.
			border:SetRGBFromInt(16777215, 0)
		end
	end
	for _, name in ipairs({"ButtonUp", "ButtonOver"}) do
		local focused = name == "ButtonOver"
		-- Replace the stock blue background and ButtonUp's shortened border.
		background:RegisterAnimationSequence(name, {{function() style(focused) end}})
		border:RegisterAnimationSequence(name, {{function() position(border) end}})
	end
	style(self:isInFocus())
	-- Keep the stock localized count and its update_contracts refresh path.
	local count = self.CompletedCount
	local setText = count.setText
	count.setText = function(element, text, ...)
		text = string.gsub(text, "([Cc][Oo][Mm][Pp][Ll][Ee][Tt][Ee][Dd]):?", "%1:")
		return setText(element, text, ...)
	end
	self:processEvent({name = "update_contracts"})
	print("[IWZ][BountyFixes] bounty info box width=322 height=30 topBorder=0 completedColon=1 idle=stock CP black/gray outline hover=Zombies menuHeader")
end)

patchBuilder("ContractMenu", function(self)
	-- ContractMenu's -4 bottom offset leaves its black footer short of the
	-- screen. Anchor the existing bar to the edge instead of covering the seam.
	self.ButtonHelperBar:SetBottom(0, 0)
	print("[IWZ][BountyFixes] bounty footer anchored to screen bottom; removed 4px gap")
end)
