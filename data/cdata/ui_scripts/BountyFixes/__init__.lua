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
