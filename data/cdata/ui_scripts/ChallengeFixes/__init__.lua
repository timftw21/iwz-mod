-- Frontend HKS starts before the selected mode is final. Register the shared
-- menu wrapper for the lifetime of the frontend VM and evaluate its mode when
-- each menu instance is built.
if not Engine.InFrontend() then
	return
end

print("[IWZ][ChallengeFixes] UI script loading frontend=true modeAtRegistration=" ..
	tostring(Engine.IsAliensMode()))

if MenuBuilder.m_types["MasterChallenge"] == nil then
	require("frontEnd.mp.MasterChallenge")
end

if MenuBuilder.m_types["ChallengeInfoBigProgress"] == nil then
	require("frontEnd.mp.ChallengeInfoBigProgress")
end

local originalMasterChallenge = MenuBuilder.m_types["MasterChallenge"]
local originalChallengeInfoBigProgress = MenuBuilder.m_types["ChallengeInfoBigProgress"]

local loggedPercentageFix = false
local loggedMissingPercentage = false
local loggedNonZombiesMenu = false
local loggedRewardLayoutFix = false
local loggedTierFiveReward = false

if originalMasterChallenge then
	MenuBuilder.m_types["MasterChallenge"] = function(menu, controller)
		local self = originalMasterChallenge(menu, controller)

		-- MasterChallenge is shared with multiplayer. The active frontend mode can
		-- change without restarting HKS, so make this decision at construction time.
		if not CONDITIONS.IsThirdGameMode(self) then
			if not loggedNonZombiesMenu then
				print("[IWZ][ChallengeFixes] leaving non-Zombies MasterChallenge unchanged")
				loggedNonZombiesMenu = true
			end
			return self
		end

		local percentage = self.PercentCompleteValue

		if percentage then
			-- Stock creates this text at 19 pixels, then the CP animation stretches
			-- its bounds to 36 pixels. Give it a true 24-pixel font and matching
			-- 24-pixel bounds so HKS does not upscale a low-resolution glyph raster.
			percentage:SetFontSize(24 * _1080p)
			percentage:RegisterAnimationSequence("DefaultSequence", {
				{
					function()
						return percentage:SetAnchorsAndPosition(0, 1, 0, 1,
							_1080p * 1090.26, _1080p * 1210.13,
							_1080p * 59, _1080p * 83, 0)
					end
				}
			})
			percentage:AnimateSequence("DefaultSequence")

			if not loggedPercentageFix then
				print("[IWZ][ChallengeFixes] set MasterChallenge percentage to native 24px rendering")
				loggedPercentageFix = true
			end
		elseif not loggedMissingPercentage then
			print("[IWZ][ChallengeFixes] MasterChallenge percentage unavailable during construction")
			loggedMissingPercentage = true
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] MasterChallenge unavailable; percentage patch not installed")
end

if originalChallengeInfoBigProgress then
	MenuBuilder.m_types["ChallengeInfoBigProgress"] = function(menu, controller)
		local self = originalChallengeInfoBigProgress(menu, controller)

		if not CONDITIONS.IsThirdGameMode(self) then
			return self
		end

		local rewardValue = self.RewardValue
		if rewardValue then
			-- The stock LTR value is right-aligned in a wide box, which creates an
			-- artificial gap after "XP Reward:". Arabic retains its stock RTL layout.
			if not CONDITIONS.IsArabic(self) then
				rewardValue:SetAlignment(LUI.Alignment.Left)
				rewardValue:SetAnchorsAndPosition(0, 1, 0, 1,
					_1080p * 144, _1080p * 231.69,
					_1080p * 470, _1080p * 490, 0)

				if not loggedRewardLayoutFix then
					print("[IWZ][ChallengeFixes] moved the LTR XP reward value next to its label")
					loggedRewardLayoutFix = true
				end
			end

			local controllerIndex = controller and controller.controllerIndex
			local function refreshRewardValue()
				local source = self:GetDataSource()
				if controllerIndex == nil or source == nil or
					source.currentTier == nil or source.tierCount == nil or
					source.currentTierXP == nil then
					return
				end

				local currentTier = source.currentTier:GetValue(controllerIndex)
				local tierCount = source.tierCount:GetValue(controllerIndex)
				local displayedXP = source.currentTierXP:GetValue(controllerIndex)
				if currentTier == 4 and tierCount ~= nil and tierCount >= 5 then
					displayedXP = Engine.GetDvarInt("iwz_challenge_tier5_xp")
					if not loggedTierFiveReward then
						print("[IWZ][ChallengeFixes] displaying Tier 5 XP reward=" .. tostring(displayedXP))
						loggedTierFiveReward = true
					end
				end

				if displayedXP ~= nil then
					rewardValue:setText(displayedXP, 0)
				end
			end

			-- Register after the stock currentTierXP subscription so this display
			-- projection wins without mutating the underlying challenge models.
			rewardValue:SubscribeToModelThroughElement(self, "currentTierXP", refreshRewardValue)
			rewardValue:SubscribeToModelThroughElement(self, "currentTier", refreshRewardValue)
			rewardValue:SubscribeToModelThroughElement(self, "tierCount", refreshRewardValue)
		end

		return self
	end
else
	print("[IWZ][ChallengeFixes] ChallengeInfoBigProgress unavailable; reward patches not installed")
end

print("[IWZ][ChallengeFixes] challenge UI patches registered percentage=" ..
	tostring(originalMasterChallenge ~= nil) .. " rewards=" ..
	tostring(originalChallengeInfoBigProgress ~= nil))
