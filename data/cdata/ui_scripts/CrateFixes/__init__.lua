if not Engine.InFrontend() then
	return
end

local function wrapCardPackButton(stock)
	return function(menu, controller)
		local self = stock(menu, controller)
		if not Engine.IsAliensMode() then return self end

		local button = self.MenuButton
		local background = button.GenericListButtonBackground
		local function fitBackground()
			return background:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, 0, 0, 0)
		end

		-- menu_create selects this animation set after the button is built.
		-- Replace its fixed 322px width without changing the Zombies styling.
		local thirdGameMode = button._animationSets.ThirdGameMode
		button._animationSets.ThirdGameMode = function()
			thirdGameMode()
			background:RegisterAnimationSequence("DefaultSequence", {{fitBackground}})
		end
		fitBackground()
		print("[IWZ][CrateFixes] card-pack background follows row width on creation and Zombies layout initialization")
		return self
	end
end

local typeName = "OpenFortuneCardPackButton"
local stock = MenuBuilder.m_types[typeName]
if stock then
	MenuBuilder.m_types[typeName] = wrapCardPackButton(stock)
end

-- Also handle menus first registered after the frontend scripts load.
local registerType = MenuBuilder.registerType
MenuBuilder.registerType = function(name, builder)
	if name == typeName then builder = wrapCardPackButton(builder) end
	return registerType(name, builder)
end
