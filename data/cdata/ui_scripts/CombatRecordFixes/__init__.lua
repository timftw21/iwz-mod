-- Frontend HKS starts before the selected mode is final. Register CP menu
-- overrides for the lifetime of the frontend VM instead of making a one-time
-- decision from Engine.IsAliensMode() here.
if not Engine.InFrontend() then
	return
end

print("[IWZ][CombatRecordFixes] UI script loading frontend=true modeAtRegistration=" ..
	tostring(Engine.IsAliensMode()))

if MenuBuilder.m_types["CPCombatRecordMapListMenu"] == nil then
	require("frontEnd.cp.CPCombatRecordMapListMenu")
end

local originalMapListMenu = MenuBuilder.m_types["CPCombatRecordMapListMenu"]

if originalMapListMenu == nil then
	print("[IWZ][CombatRecordFixes] Films menu unavailable; helper bar patch not installed")
	return
end

local loggedHelperBarFix = false
local loggedMissingHelperBar = false

MenuBuilder.m_types["CPCombatRecordMapListMenu"] = function(menu, controller)
	local self = originalMapListMenu(menu, controller)

	if self.ButtonHelperBar then
		-- Stock applies +94.83 to both horizontal offsets, shifting the full-width
		-- helper bar right and leaving the bottom-left edge uncovered.
		self.ButtonHelperBar:SetAnchorsAndPosition(0, 0, 1, 0,
			0, 0, _1080p * -85, 0)

		if not loggedHelperBarFix then
			print("[IWZ][CombatRecordFixes] normalized Films helper bar to full screen width")
			loggedHelperBarFix = true
		end
	elseif not loggedMissingHelperBar then
		print("[IWZ][CombatRecordFixes] Films helper bar unavailable during menu construction")
		loggedMissingHelperBar = true
	end

	return self
end

print("[IWZ][CombatRecordFixes] Films helper bar patch registered")
