--[[
=head1 NAME

jive.JiveMain - Main Jive application.

=head1 DESCRIPTION

TODO

=head1 SYNOPSIS

TODO

=head1 FUNCTIONS

JiveMainMenu notifies any change with mainMenuUpdate

=cut
--]]


-- stuff we use
local math          = require("math")
local os            = require("os")
local coroutine     = require("coroutine")
local oo            = require("loop.simple")
-- local bit	    = require("bit") FIXME we need to make use backward compat for old installs

local Process       = require("jive.net.Process")
local NetworkThread = require("jive.net.NetworkThread")
local Iconbar       = require("jive.Iconbar")
local AppletManager = require("jive.AppletManager")
local System        = require("jive.System")
local locale        = require("jive.utils.locale")
local SimpleMenu    = require("jive.ui.SimpleMenu")
local Window        = require("jive.ui.Window")
local HomeMenu      = require("jive.ui.HomeMenu")
local Framework     = require("jive.ui.Framework")
local Task          = require("jive.ui.Task")
local Timer         = require("jive.ui.Timer")
local Event         = require("jive.ui.Event")
local table         = require("jive.utils.table")

local Canvas        = require("jive.ui.Canvas")

local _inputToActionMap = require("jive.InputToActionMap")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("squeezeplay")
local logI          = require("jive.utils.log").logger("squeezeplay.ui.input")
local logHeap       = require("jive.utils.log").logger("squeezeplay.heap")
local logPerf       = require("jive.utils.log").logger("squeezeplay.perf")
local logPerfHook   = require("jive.utils.log").logger("squeezeplay.perf.hook")
--require("profiler")

local EVENT_IR_ALL         = jive.ui.EVENT_IR_ALL
local EVENT_IR_PRESS       = jive.ui.EVENT_IR_PRESS
local EVENT_IR_DOWN        = jive.ui.EVENT_IR_DOWN
local EVENT_IR_UP          = jive.ui.EVENT_IR_UP
local EVENT_IR_REPEAT      = jive.ui.EVENT_IR_REPEAT
local EVENT_IR_HOLD        = jive.ui.EVENT_IR_HOLD
local EVENT_KEY_ALL        = jive.ui.EVENT_KEY_ALL
local ACTION               = jive.ui.ACTION
local EVENT_ALL_INPUT      = jive.ui.EVENT_ALL_INPUT
local EVENT_MOUSE_ALL      = jive.ui.EVENT_MOUSE_ALL
local EVENT_KEY_PRESS      = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_UP         = jive.ui.EVENT_KEY_UP
local EVENT_KEY_DOWN       = jive.ui.EVENT_KEY_DOWN
local EVENT_CHAR_PRESS      = jive.ui.EVENT_CHAR_PRESS
local EVENT_KEY_HOLD       = jive.ui.EVENT_KEY_HOLD
local EVENT_SCROLL         = jive.ui.EVENT_SCROLL
local EVENT_WINDOW_RESIZE  = jive.ui.EVENT_WINDOW_RESIZE
local EVENT_UNUSED         = jive.ui.EVENT_UNUSED
local EVENT_CONSUME        = jive.ui.EVENT_CONSUME

local KEY_HOME             = jive.ui.KEY_HOME
local KEY_FWD           = jive.ui.KEY_FWD
local KEY_REW           = jive.ui.KEY_REW
local KEY_GO            = jive.ui.KEY_GO
local KEY_BACK          = jive.ui.KEY_BACK
local KEY_UP            = jive.ui.KEY_UP
local KEY_DOWN          = jive.ui.KEY_DOWN
local KEY_LEFT          = jive.ui.KEY_LEFT
local KEY_RIGHT         = jive.ui.KEY_RIGHT
local KEY_PLAY          = jive.ui.KEY_PLAY
local KEY_PAUSE         = jive.ui.KEY_PAUSE
local KEY_VOLUME_UP     = jive.ui.KEY_VOLUME_UP
local KEY_VOLUME_DOWN   = jive.ui.KEY_VOLUME_DOWN
local KEY_ADD           = jive.ui.KEY_ADD

local JIVE_VERSION      = jive.JIVE_VERSION

-- Classes
local JiveMain = oo.class({}, HomeMenu)

-- FIXME env setting? seconds
local SPLASH_DELAY = 25
local HEAP_DELAY = 60000


-- strings
local _globalStrings

-- several submenus created by applets (settings, controller settings, extras)
-- should not need to have an id passed when creating it
local _idTranslations = {}

_softPowerState = "on"

-- Squeezebox remote IR codes
local irCodes = {
	[ 0x7689c03f ] = KEY_REW,
	[ 0x7689a05f ] = KEY_FWD,
	[ 0x7689807f ] = KEY_VOLUME_UP,
	[ 0x768900ff ] = KEY_VOLUME_DOWN,
}

--require"remdebug.engine"
--  remdebug.engine.start()
  
local _defaultSkin
local _fullscreen
local _postOnScreenInits = {}
local _postOffScreenCleans = {}

function JiveMain:goHome()
		local windowStack = Framework.windowStack

		if #windowStack > 1 then
			Framework:playSound("JUMP")
			jiveMain:closeToHome(true)
		else
			Framework:playSound("BUMP")
			windowStack[1]:bumpLeft()
		end
end

function JiveMain:disconnectPlayer(event) --self, event not used in our case, could be left out
	appletManager:callService("setCurrentPlayer", nil)
	JiveMain:goHome()
end


--fallback IR->KEY handler after widgets have had a chance to listen for ir - probably will be removed - still using for rew/fwd and volume for now
local function _irHandler(event)
	local irCode = event:getIRCode()
	local buttonName = Framework:getIRButtonName(irCode)

	if log:isDebug() then
		log:debug("IR event in fallback _irHandler: ", event:tostring(), " button:", buttonName )
	end
	if not buttonName then
		--code may have come from a "foreign" remote that the user is using
		return EVENT_CONSUME
	end

	local keyCode = irCodes[irCode]
	if (keyCode) then
		if event:getType() == EVENT_IR_PRESS  then
			Framework:pushEvent(Event:new(EVENT_KEY_PRESS, keyCode))
			return EVENT_CONSUME
		elseif event:getType() == EVENT_IR_HOLD then
			Framework:pushEvent(Event:new(EVENT_KEY_HOLD, keyCode))
			return EVENT_CONSUME
		elseif event:getType() == EVENT_IR_DOWN  then
			Framework:pushEvent(Event:new(EVENT_KEY_DOWN, keyCode))
			return EVENT_CONSUME
		elseif event:getType() == EVENT_IR_UP  then
			Framework:pushEvent(Event:new(EVENT_KEY_UP, keyCode))
			return EVENT_CONSUME
		end
	end

	return EVENT_UNUSED
end

function _goHomeAction(self)
	JiveMain:goHome()

	return EVENT_CONSUME
end


function _goFactoryTestModeAction(self)
	local key = "factoryTest"

	if jiveMain:getMenuTable()[key] then
		Framework:playSound("JUMP")
		jiveMain:getMenuTable()[key].callback()
	end

	return EVENT_CONSUME
end


function JiveMain:getSoftPowerState()
	return _softPowerState
end


--Note: Jive does not use setSoftPowerState since it doesn't have a soft power concept
function JiveMain:setSoftPowerState(softPowerState, isServerRequest)
	if _softPowerState == softPowerState then
		--already in the desired state, leave (can happen for instance when notify_playerPower comes back after a local power change)
		 return
	end

	_softPowerState = softPowerState
	local currentPlayer = appletManager:callService("getCurrentPlayer")
	if _softPowerState == "off" then
		log:info("Turn soft power off")
		if currentPlayer and (currentPlayer:isConnected() or currentPlayer:isLocal()) then
			currentPlayer:setPower(false, nil, isServerRequest)
		end
		--todo: also pause/power off local player since local player might be playing and not be the current player
		appletManager:callService("activateScreensaver", isServerRequest)
	elseif _softPowerState == "on" then
		log:info("Turn soft power on")
		--todo: Define what should happen for a non-jive remote player. Currently if a server is down, locally a SS will engage, but when the server
		--       comes back up the server is considered the master power might soft power SP back on 
		if currentPlayer and (currentPlayer:isConnected() or currentPlayer:isLocal()) then
			if currentPlayer.slimServer then
				currentPlayer.slimServer:wakeOnLan()
			end
			currentPlayer:setPower(true, nil, isServerRequest)
		end

		appletManager:callService("deactivateScreensaver")
		appletManager:callService("restartScreenSaverTimer")

	else
		log:error("unknown desired soft power state: ", _softPowerState)
	end
end

function JiveMain:togglePower()
	local powerState = JiveMain:getSoftPowerState()
	if powerState == "off" then
		JiveMain:setSoftPowerState("on")
	elseif powerState == "on" then
		JiveMain:setSoftPowerState("off")
	else
		log:error("unknown current soft power state: ", powerState)
	end

end

local function _powerAction()
	Framework:playSound("SELECT")
	JiveMain:togglePower()
	return EVENT_CONSUME
end

local function _powerOffAction()
	JiveMain:setSoftPowerState("off")
	return EVENT_CONSUME
end

local function _powerOnAction()
	JiveMain:setSoftPowerState("on")
	return EVENT_CONSUME
end


function _defaultContextMenuAction(self)
	if not Framework:isMostRecentInput("mouse") then -- don't bump on touch press hold, is visually distracting...
		Framework:playSound("BUMP")
		Framework.windowStack[1]:bumpLeft()
	end
	return EVENT_CONSUME
end

-- __init
-- creates our JiveMain main object
function JiveMain:__init()
	log:info("SqueezePlay version ", JIVE_VERSION)

	-- Seed the rng
	local initTime = os.time()
	math.randomseed(initTime)

--	profiler.start()
	-- Initialise UI
	Framework:init()
	Framework:initIRCodeMappings()
	-- register the default actions
	Framework:registerActions(_inputToActionMap)

	-- Singleton instances (locals)
	_globalStrings = locale:readGlobalStringsFile()

	-- Singleton instances (globals)
	-- create the main menu
	jiveMain = oo.rawnew(self, HomeMenu(_globalStrings:str("HOME"), nil, "hometitle"))
	jnt = NetworkThread()
	appletManager = AppletManager(jnt)
	iconbar = Iconbar(jnt)

	-- menu nodes to add...these are menu items that are used by applets
	JiveMain:jiveMainNodes(_globalStrings)

	jiveMain.skins = {}
	-- other local inits
	Process.init(jiveMain)

	-- init our listeners

	Framework:addListener(EVENT_IR_ALL,
		function(event) return _irHandler(event) end,
		false
	)

	-- global listener: resize window (only desktop versions)
	Framework:addListener(EVENT_WINDOW_RESIZE,
		function(event)
			jiveMain:reloadSkin()
			return EVENT_UNUSED
		end,
		10)		

	Framework:addActionListener("go_home", self, _goHomeAction, 10)

	--before NP exists (from SlimBrowseApplet), have go_home_or_now_playing go home
	Framework:addActionListener("go_home_or_now_playing", self, _goHomeAction, 10)

	Framework:addActionListener("add", self, _defaultContextMenuAction, 10)

	Framework:addActionListener("go_factory_test_mode", self, _goFactoryTestModeAction, 9999)

	--Consume up and down actions
	Framework:addActionListener("up", self, function() return EVENT_CONSUME end, 9999)
	Framework:addActionListener("down", self, function() return EVENT_CONSUME end, 9999)

	Framework:addActionListener("power", self, _powerAction, 10)
	Framework:addActionListener("power_off", self, _powerOffAction, 10)
	Framework:addActionListener("power_on", self, _powerOnAction, 10)

	Framework:addActionListener("nothing", self, function() return EVENT_CONSUME end, 10)

	--Last input type tracker (used by, for instance, Menu, to determine wheter selected style should be displayed)
	Framework:addListener(EVENT_ALL_INPUT,
		function(event)
			local etype = event:getType()
			local idm = appletManager:callService("getInputDetectorMapping")
			if (etype & EVENT_IR_ALL ) > 0 then
				if (Framework:isValidIRCode(event)) then
					Framework.mostRecentInputType = "ir"
				end
			end
			if (etype & EVENT_KEY_ALL ) > 0 then
				if idm == 'REMOTE' then
					Framework.mostRecentInputType = "ir"
				else
					Framework.mostRecentInputType = "key"
				end
			end
			-- FIXME idm for remote mouse events?
			if (etype & EVENT_SCROLL ) > 0 then
				Framework.mostRecentInputType = "scroll"
			end
			if (etype & EVENT_MOUSE_ALL) > 0 then
				Framework.mostRecentInputType = "mouse"
			end
			--FIXME not sure what to do about char/mouse, since it is a bit of a hybrid input type. So far usages don't care.
			logI:debug("EVENT_ALL_INPUT ",event:tostring(),":",Framework.mostRecentInputType,":",idm)
			return EVENT_UNUSED
		end,
		true
	)

	--Ignore foreign remote codes
	Framework:addListener( EVENT_IR_ALL,
		function(event)
			if (not Framework:isValidIRCode(event)) then
				--is foreign remote code, consume so it doesn't appear as input to the app (future ir blaster code might still care)
				if logI:isDebug() then
					log:debugI("Consuming foreign IR event: ", event:tostring())
				end
				return EVENT_CONSUME
			end

			return EVENT_UNUSED
		end,
		true
	)


	-- debug: set event warning thresholds (0 = off)
	if (logPerf:isDebug()) then
		logPerf:warn("Performance Warnings enabled")
		--Framework:perfwarn({ screen = 50, layout = 1, draw = 0, event = 50, queue = 5, garbage = 10 })
		Framework:perfwarn({ screen = 50, layout = 0, draw = 0, event = 50, queue = 5, garbage = 10 })
		if logPerfHook:isDebug() then
			logPerfiHook:warn("Performance Hook Warnings enabled")
			jive.perfhook(50)
		end
	end

	-- Splash screen is displayied in init
	-- applet load variable so start timers before reload could this be moved further up?
	local splashHandler = Framework:addListener(ACTION | EVENT_CHAR_PRESS | EVENT_KEY_ALL | EVENT_SCROLL, function(event)
					JiveMain:performPostOnScreenInit()
					Framework:setUpdateScreen(true)
					log:debug("Fired Handler ",event:tostring())
					return EVENT_UNUSED
				end)
	-- os time in seconds timer in mills
	local splashTimer = Timer((SPLASH_DELAY - (os.time() - initTime))*1000,
		function()
			JiveMain:performPostOnScreenInit()
			Framework:removeListener(splashHandler)
			Framework:setUpdateScreen(true)
			log:debug("Fired Timer")
		end,
		true)
	log:debug("Start Timer")
	splashTimer:start()

	if logHeap:isDebug() then
		local heapTimer = Timer(HEAP_DELAY,
			function()
			local s = jive.heap()
			logHeap:debug("--- HEAP total/new/free ---")
			logHeap:debug("number=", s["number"]);
			logHeap:debug("integer=", s["integer"]);
			logHeap:debug("boolean=", s["boolean"]);
			logHeap:debug("string=", s["string"]);
			logHeap:debug("table=", s["table"], "/", s["new_table"], "/", s["free_table"]);
			logHeap:debug("function=", s["function"], "/", s["new_function"], "/", s["free_function"]);
			logHeap:debug("thread=", s["thread"], "/", s["new_thread"], "/", s["free_thread"]);
			logHeap:debug("userdata=", s["userdata"], "/", s["new_userdata"], "/", s["free_userdata"]);
			logHeap:debug("lightuserdata=", s["lightuserdata"], "/", s["new_lightuserdata"], "/", s["free_lightuserdata"]);
		end)
		heapTimer:start()
	end

	-- show our window! from HomeMenu
	jiveMain.window:show()

	-- detect mode change
	local sw, sh = Framework:getScreenSize()
	-- load style and applets
	jiveMain:reload()
	local fw, fh = Framework:getScreenSize()

	-- show splash screen for +SPLASH_DELAY seconds, or until key/scroll events (splash displayed by init)
	-- however on mode change... we have blank screen... FIXME redisplay splash?
        if fw == sw and sh == fh then
		Framework:setUpdateScreen(false)
	else
		-- Force Update
		Framework:updateScreen()
	end

	-- run event loop
	Framework:eventLoop(jnt:task())
	Framework:quit()

	JiveMain:performPostOffScreenClean()

--	profiler.stop()
	log:warn("JiveMain Exit")
end


function JiveMain:registerPostOnScreenInit(callback,name)
	_assert(type(callback) == "function")
	-- FIXME name via introspection
	local entry = { callback = callback, name = name or "no name",}
	table.insert(_postOnScreenInits, entry)
	return entry
end


-- perform activities that need to run once the skin is loaded and the screen is visible
function JiveMain:performPostOnScreenInit()
	for i, v in ipairs(_postOnScreenInits) do
		log:info("Calling postOnScreenInit callback ",v.name)
		v.callback()
	end
	_postOnScreenInits = {}
end


function JiveMain:registerPostOffScreenClean(callback,name)
	_assert(type(callback) == "function")
	_assert(type(name) == "string")
	-- FIXME name via introspection
	local entry =  { callback = callback, name = name or "no name",}
	-- LIFO
	table.insert(_postOffScreenCleans, 1, entry)
	return entry
end


function JiveMain:performPostOffScreenClean()
	for i, v in ipairs(_postOffScreenCleans) do
		log:warn("Calling postOffScreenClean callback ",v.name)
		v.callback()
	end
	_postOffScreenCleans = {}
end


function JiveMain:removePostOffScreenClean(handel)
	for i, v in ipairs(_postOffScreenCleans) do
		if v == handel then
			return table.remove(_postOffScreenCleans,i)
		end
	end
	return nil
end


function JiveMain:jiveMainNodes(globalStrings)
	-- this can be called after language change, 
	-- so we need to bring in _globalStrings again if it wasn't provided to the method
	if globalStrings then
		_globalStrings = globalStrings
	else
		_globalStrings = locale:readGlobalStringsFile()
	end

	jiveMain:addNode( { id = 'hidden', node = 'nowhere' } )
	jiveMain:addNode( { id = 'extras', node = 'home', text = _globalStrings:str("EXTRAS"), weight = 50, hiddenWeight = 91  } )
	jiveMain:addNode( { id = 'radios', iconStyle = 'hm_radio', node = 'home', text = _globalStrings:str("INTERNET_RADIO"), weight = 20  } )
	jiveMain:addNode( { id = '_myMusic', iconStyle = 'hm_myMusic', node = 'hidden', text = _globalStrings:str("MY_MUSIC"), synthetic = true , hiddenWeight = 2  } )
	jiveMain:addNode( { id = 'games', node = 'extras', text = _globalStrings:str("GAMES"), weight = 70  } )
	jiveMain:addNode( { id = 'settings', iconStyle = 'hm_settings', node = 'home', noCustom = 1, text = _globalStrings:str("SETTINGS"), weight = 1005, })
	jiveMain:addNode( { id = 'advancedSettings', iconStyle = 'hm_advancedSettings', node = 'settings', text = _globalStrings:str("ADVANCED_SETTINGS"), weight = 105, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'screenSettings', iconStyle = 'hm_settingsScreen', node = 'settings', text = _globalStrings:str("SCREEN_SETTINGS"), weight = 60, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'screenSettingsNowPlaying', node = 'screenSettings', text = _globalStrings:str("NOW_PLAYING"), windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'factoryTest', node = 'advancedSettings', noCustom = 1, text = _globalStrings:str("FACTORY_TEST"), weight = 120, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'advancedSettingsBetaFeatures', node = 'advancedSettings', noCustom = 1, text = _globalStrings:str("BETA_FEATURES"), weight = 100, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'networkSettings', node = 'advancedSettings', noCustom = 1, text = _globalStrings:str("NETWORK_NETWORKING"), weight = 100, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'settingsAudio', iconStyle = "hm_settingsAudio", node = 'settings', noCustom = 1, text = _globalStrings:str("AUDIO_SETTINGS"), weight = 40, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'settingsBrightness', iconStyle = "hm_settingsBrightness", node = 'settings', noCustom = 1, text = _globalStrings:str("BRIGHTNESS_SETTINGS"), weight = 45, windowStyle = 'text_only' })
end

--[[

=head2 jive.JiveMain:addHelpMenuItem()

Adds a 'Help' menu item to I<menu> if the most recent input was not touch or mouse (which generally would have a help button instead)

=cut
--]]
function JiveMain:addHelpMenuItem(menu, obj, callback, textToken, iconStyle)
	-- only deliver an icon if specified
	if not iconStyle then
		iconStyle = "_BOGUS_"
	end
	if not Framework:isMostRecentInput("mouse") then
		menu:addItem({
			iconStyle = iconStyle,
			text = textToken and _globalStrings:str(textToken) or _globalStrings:str("GLOBAL_HELP"),
			sound = "WINDOWSHOW",
			callback =      function ()
						callback(obj)
					end,
			weight = 100
		})
	end
end



-- reload
-- 
function JiveMain:reload()
	log:debug("reload()")

	-- reset the skin
	jive.ui.style = {}

	-- manage applets
	appletManager:discover()

	-- make sure a skin is selected
	if not self.selectedSkin then
		for askin in pairs(self.skins) do
			self:setSelectedSkin(askin)
			break
		end
	end
	assert(self.selectedSkin, "No skin")
end


function JiveMain:registerSkin(name, appletName, method, skinId)
       log:debug("registerSkin(", name, ",", appletName, ", ", skinId or "", ")")
       -- skinId allows multiple entry methods to single applet to give multiple skins
       if skinId == nil then
               skinId = appletName
       end
       self.skins[skinId] = { appletName, name, method }
end


function JiveMain:skinIterator()
	local _f,_s,_var = pairs(self.skins)
	return function(_s,_var)
               local skinId, entry = _f(_s,_var)
               if skinId then
                       return skinId, entry[2]
		else
			return nil
		end
	end,_s,_var
end


function JiveMain:getSelectedSkin()
	return self.selectedSkin
end


local function _loadSkin(self, skinId, reload, useDefaultSize)
	if not self.skins[skinId] then
		log:warn("_load skin: ", skinId, " Failed no skin")
		return false
	end

	local appletName, name, method = unpack(self.skins[skinId])
	local obj = appletManager:loadApplet(appletName)
	assert(obj, "Cannot load skin " .. appletName)

	-- reset the skin
	jive.ui.style = {}

	obj[method](obj, jive.ui.style, reload==nil and true or reload, useDefaultSize)
	self._skin = obj

	Framework:styleChanged()

	return true
end


function JiveMain:isFullscreen()
	return _fullscreen
end


function JiveMain:setFullscreen(fullscreen)
	_fullscreen = fullscreen
end


function JiveMain:setSelectedSkin(skinId)
        log:info("select skin: ", skinId)
        local oldSkinId = self.selectedSkin
        if _loadSkin(self, skinId, false, true) then
                self.selectedSkin = skinId
		jnt:notify("skinSelected",oldSkinId ,self.selectedSkin)
                if oldSkinId and self.skins[oldSkinId] and self.skins[oldSkinId][1] ~= self.skins[skinId][1] then
			if oldSkinId ~= appletManager:callService("getSelectedSkinNameForType", "touch") and 
			   oldSkinId ~= appletManager:callService("getSelectedSkinNameForType", "remote") then
				jiveMain:freeSkin(oldSkinId)
			end
                end

	end
end


function JiveMain:getSkinParam(key,warn)
	if self._skin then
		local param = self._skin:param()

		if key and param[key] ~= nil then
			return param[key]
		end
	end

	if warn then
		log:warn('no value for skinParam ', key, ' found')
	elseif warn == nil then
		log:error('no value for skinParam ', key, ' found')
	end

	return nil
end



function JiveMain:getSkinParamOrNil(key)
	return JiveMain:getSkinParam(key,false)
end

function JiveMain:reloadSkin(reload)
        log:info("reload(", skinId, ")")
	_loadSkin(self, self.selectedSkin, true)
end


function JiveMain:loadSkin(skinId)
        log:info("loadSkin(", skinId, ")")
	_loadSkin(self, skinId, false, false)
end


function JiveMain:freeSkin(skinId)
        if skinId == nil then
                skinId = self.selectedSkin
        end
        log:info("freeSkin: ", skinId)
	
	if not self.skins[skinId] then
		return false
	end
	appletManager:freeApplet(self.skins[skinId][1])
end


function JiveMain:setDefaultSkin(skinId)
        log:debug("setDefaultSkin(", skinId, ")")
        _defaultSkin = skinId
end


function JiveMain:getDefaultSkin()
	return _defaultSkin or "QVGAportraitSkin"
end


-----------------------------------------------------------------------------
-- main()
-----------------------------------------------------------------------------

-- we create an object
JiveMain()


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

