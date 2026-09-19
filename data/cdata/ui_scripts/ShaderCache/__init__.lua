if not Engine.InFrontend() or not ShaderUpload then
	return
end

-- Stock FenceShaderUpload requests the same progress popup on every fence tick.
-- Keep the stock driver checks and cancel/resume behavior, but open each popup once.
local module = package.loaded["utils.FenceShaderUpload"]
local fence = module and module.FenceShaderUpload

local restartCaching = ShaderUpload.RestartCaching
ShaderUpload.RestartCaching = function(...)
	local restarted = restartCaching(...)
	if not restarted then
		LUI.FlowManager.RequestPopupMenu(nil, "PopupOK", false, Engine.GetFirstActiveController(), false, {
			title = Engine.Localize("MENU_NOTICE"),
			message = "Unable to restart shader caching. Check the client log for details."
		})
	end
	return restarted
end

if fence then
	fence.UpdateState = function(self)
		if self._state == LUI.Fence.STATE.pass then
			return
		end
		assert(self._state ~= LUI.Fence.STATE.fail)
		if Engine.DisplayDriverMeetsMinVer and not Engine.DisplayDriverMeetsMinVer()
			and not Engine.GetDvarBool("r_ignoreBadDisplayDriver") then
			self._state = LUI.Fence.STATE.block
			if not LUI.FlowManager.IsInStack("BadDisplayDriverPopup") then
				LUI.FlowManager.RequestPopupMenu(nil, "BadDisplayDriverPopup", false, false, false, {}, nil, true, true)
			end
			return
		end
		if not Engine.GetDvarBool("r_preloadShadersFrontendSkip") and not self._didStart then
			self._didStart = true
			local started = ShaderUpload.Start()
			print("[IWZ][ShaderCache] preload start=" .. tostring(started))
			if not started then
				Engine.SetDvarBool("r_preloadShadersFrontendSkip", true)
			end
		end
		if not ShaderUpload.IsWorkAvailable() or Engine.GetDvarBool("r_preloadShadersFrontendSkip") then
			self._state = LUI.Fence.STATE.pass
			print("[IWZ][ShaderCache] fence passed skipped=" .. tostring(Engine.GetDvarBool("r_preloadShadersFrontendSkip")))
			return
		end
		self._state = LUI.Fence.STATE.block
		if not LUI.FlowManager.IsInStack("ShaderUploadDialog") then
			LUI.FlowManager.RequestPopupMenu(nil, "ShaderUploadDialog", false, false, false, {
				onCancelUpload = function()
					Engine.SetDvarBool("r_preloadShadersFrontendSkip", true)
					print("[IWZ][ShaderCache] preload cancelled; progress retained")
				end
			}, nil, true, true)
		end
	end
end
print("[IWZ][ShaderCache] UI installed popupGuard=" .. tostring(fence ~= nil))
