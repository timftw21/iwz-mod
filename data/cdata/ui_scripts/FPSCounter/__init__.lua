print("[IWZ][FPSCounter] script loading")

local function moveFPSCounter(root)
	if not root then
		return false
	end

	local counter = root.FPSCounter
	if not counter and root.getChildById then
		counter = root:getChildById("FPSCounter")
	end
	if not counter then
		return false
	end

	-- The native counter renders right-aligned within its 500-pixel element.
	-- Preserve that behavior while moving the rendered text to the upper-left.
	counter:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * -360, _1080p * 140, _1080p * 10, _1080p * 48)
	return true
end

local originalInit = LUI.UIRoot.init
if originalInit then
	LUI.UIRoot.init = function(root, ...)
		local result = originalInit(root, ...)
		print("[IWZ][FPSCounter] root init position applied=" .. tostring(moveFPSCounter(root)) .. " controller=" .. tostring(root._controllerIndex))
		return result
	end
end

local originalSetupRoot = LUI.UIRoot.setupRoot
if originalSetupRoot then
	LUI.UIRoot.setupRoot = function(root, ...)
		local result = originalSetupRoot(root, ...)
		if moveFPSCounter(root) then
			print("[IWZ][FPSCounter] moved to upper-left controller=" .. tostring(root._controllerIndex))
		end
		return result
	end
end

local existingRootsMoved = 0
if LUI.roots then
	for _, root in pairs(LUI.roots) do
		if moveFPSCounter(root) then
			existingRootsMoved = existingRootsMoved + 1
		end
	end
end

print("[IWZ][FPSCounter] script registered existingRootsMoved=" .. tostring(existingRootsMoved))
