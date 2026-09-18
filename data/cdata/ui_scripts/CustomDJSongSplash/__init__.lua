if Engine.InFrontend() or not Engine.IsAliensMode() then
	return
end

if MenuBuilder.m_types["SongSplash"] == nil then
	require("inGame.cp.SongSplash")
end

local originalSongSplash = MenuBuilder.m_types["SongSplash"]
local shownSequences = {}
MenuBuilder.m_types["SongSplash"] = function(menu, controller)
	local self = originalSongSplash(menu, controller)
	local controllerIndex = controller and controller.controllerIndex or self:getRootController()
	local lastSequence = 0
	local loggedDuplicate = 0
	-- Both the stock songPlayingIndex subscription and our timer enter these
	-- sequences. Deduplicate at that shared boundary, including HUD rebuilds.
	for _, name in ipairs({"slideIn", "slideInSplitScreen"}) do
		local animate = self._sequences[name]
		self._sequences[name] = function()
			local info = custommusic.djtrack()
			if info.sequence ~= 0 then
				if shownSequences[controllerIndex] == info.sequence then
					if loggedDuplicate ~= info.sequence then
						loggedDuplicate = info.sequence
						print("[IWZ][CustomMusicDJ] suppressed duplicate splash sequence=" .. info.sequence)
					end
					return
				end
				shownSequences[controllerIndex] = info.sequence
				if not CONDITIONS.MusicPlaylistOnCheck(controllerIndex) then
					return
				end
				self.Title:setText(info.title, 0)
				self.Artist:setText("Custom Playlist", 0)
				print("[IWZ][CustomMusicDJ] HUD song=" .. info.title ..
					" artist=Custom Playlist sequence=" .. info.sequence)
			else
				-- Clearing the stock index to -1 while a custom track decodes is
				-- not a new stock song and must not display an empty banner.
				local index = DataSources.inGame.CP.zombies.songs.songPlayingIndex:GetValue(controllerIndex)
				if index == nil or index < 0 then
					return
				end
			end
			return animate()
		end
	end
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
		ACTIONS.AnimateSequence(self, CONDITIONS.IsSplitscreen(self) and "slideInSplitScreen" or "slideIn")
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
