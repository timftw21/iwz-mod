if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

if MenuBuilder.m_types["SongSplash"] == nil then
	require("inGame.cp.SongSplash")
end

local originalSongSplash = MenuBuilder.m_types["SongSplash"]
MenuBuilder.m_types["SongSplash"] = function(menu, controller)
	local self = originalSongSplash(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or self:getRootController()
	local lastSequence = 0
	-- Stock omnvar updates can arrive after the custom notification. Keep
	-- these two labels on the custom metadata while its song is active.
	for _, field in ipairs({"Title", "Artist"}) do
		local label = self[field]
		local setText = label.setText
		label.setText = function(element, text, duration)
			local info = custommusic.djtrack()
			if info.sequence ~= 0 then
				text = field == "Title" and info.title or "Custom Playlist"
			end
			return setText(element, text, duration)
		end
	end
	self:registerEventHandler("iwz_custom_dj_song", function()
		local info = custommusic.djtrack()
		local sequence = info.sequence
		if sequence == 0 or sequence == lastSequence then
			return
		end
		lastSequence = sequence
		if not CONDITIONS.MusicPlaylistOnCheck(controllerIndex) then
			return
		end

		local title = info.title
		self.Title:setText(title, 0)
		self.Artist:setText("Custom Playlist", 0)
		ACTIONS.AnimateSequence(self, CONDITIONS.IsSplitscreen(self) and "slideInSplitScreen" or "slideIn")
		print("[IWZ][CustomMusicDJ] HUD song=" .. title .. " artist=Custom Playlist sequence=" .. sequence)
	end)
	local timer = LUI.UITimer.new(nil, {
		interval = 100,
		event = "iwz_custom_dj_song",
		eventTarget = self,
		disposable = false,
		broadcastToRoot = false
	})
	timer.id = "IWZCustomDJSongTimer"
	self:addElement(timer)
	return self
end

print("[IWZ][CustomMusicDJ] stock SongSplash custom-track notifications installed")
