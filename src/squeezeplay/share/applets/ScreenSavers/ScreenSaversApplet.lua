
--[[
=head1 NAME

applets.ScreenSavers.ScreenSaversApplet - Screensaver manager.

=head1 DESCRIPTION

This applets hooks itself into Jive to provide a screensaver
service, complete with settings.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
ScreenSaversApplet overrides the following methods:

=cut
--]]


-- stuff we use
local ipairs, pairs, tostring, tonumber = ipairs, pairs, tostring, tonumber

local os               = require("os")
local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Timer            = require("jive.ui.Timer")
local Framework        = require("jive.ui.Framework")
local Window           = require("jive.ui.Window")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Label            = require("jive.ui.Label")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local System           = require("jive.System")
local Textarea         = require("jive.ui.Textarea")
local string           = require("string")
local table            = require("jive.utils.table")
local Player           = require("jive.slim.Player")

local appletManager    = appletManager

local jnt = jnt
local jiveMain = jiveMain


module(..., Framework.constants)
oo.class(_M, Applet)

local _globalSsAllowedActions = {
			["pause"] = 1,
			["shutdown"] = 1,
			["power_off"] = 1,
		}

function init(self, ...)
	self.screensavers = {}
	self.screensaverSettings = {}
	self:addScreenSaver(
		self:string("SCREENSAVER_NONE"),  -- display name
		false,	-- applet for this screensaver 
		false,	-- method from the applet to call
		_,	--settingsName
		_,	--settings
		100,	--weight for settings menu
		nil,	-- closeMethod
		nil,	-- methodParam
		nil,	-- additionalKey
		{"whenOff"} -- "none" is not an acceptable option for an off screensaver, so exclude it from the settings menu for that mode
	) 

	self.timeout = self:getSettings()["timeout"]
	self.poweroff = self:getSettings()["poweroff"]
	self.extension = 0

	self.active = {}
	self.demoScreensaver = nil
	self.isScreenSaverActive = false

	self.timer = Timer(self.timeout, function() self:_activate() end, true)
	self.timerPowerOff = Timer(self.poweroff, function() log:warn("power_off timer.") if self.poweroff > 0 then Framework:pushAction("power_off") end end, true)
	--as we need the time as of then... in case some other event restarted us.
	jiveMain:registerPostOnScreenInit(function() self:_restartScreenSaverTimer() end,'ScreenSaver')

	self.defaultSettings = self:getDefaultSettings()

	-- listener to restart screensaver timer
	Framework:addListener(ACTION | EVENT_SCROLL | EVENT_MOUSE_ALL | EVENT_MOTION | EVENT_IR_ALL | EVENT_KEY_ALL,
		function(event)
			if (event:getType() & EVENT_IR_ALL) > 0 then
				if (not Framework:isValidIRCode(event)) then
					return EVENT_UNUSED
				end
			end
			
			log:debug("restart timer event=",event:tostring()," to ", self.timeout)
			self:_restartScreenSaverTimer(self.timeout)
			return EVENT_UNUSED
		end,
		true
	)

	Framework:addListener(ACTION | EVENT_KEY_PRESS | EVENT_KEY_HOLD | EVENT_SCROLL | EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD | EVENT_MOUSE_DRAG,
		function(event)

			if #self.active == 0 then
				log:debug("screensaver is not active")
				return EVENT_UNUSED
			end

			if Framework:isAnActionTriggeringKeyEvent(event, EVENT_KEY_ALL ) then
				log:debug("will come back as an ACTION, let's respond to it then to give other action listeners a chance")
				return 	EVENT_UNUSED
			end

			if event:getType() == ACTION then
				local action = event:getAction()

				if _globalSsAllowedActions[action] then
					log:debug("Global action allowed to pass through: ", action)
					return EVENT_UNUSED
				end
					
				if self.ssAllowedActions and (table.contains(self.ssAllowedActions, action) or #self.ssAllowedActions == 0) then
					log:debug("'Per window' action allowed to pass through: ", action)
					return EVENT_UNUSED
				end
			end
			if event:getType() == EVENT_SCROLL then
				if self.scrollAllowed then
					log:debug("'Per window' scroll event allowed to pass through")
					return EVENT_UNUSED

				end
			end
			if event:getType() == EVENT_MOUSE_PRESS or
			   event:getType() == EVENT_MOUSE_HOLD or
			   event:getType() == EVENT_MOUSE_DRAG then
				if self.mouseAllowed then
					log:debug("'Per window' mouse event allowed to pass through")
					return EVENT_UNUSED

				end
			end

			log:debug("Closing screensaver event=", event:tostring())
			self:deactivateScreensaver()

			-- keys should close the screensaver, and not
			-- perform an action
			if event:getType() == ACTION then
				if event:getAction() == "back" or event:getAction() == "go" then
					return EVENT_CONSUME
				end

				-- make sure when exiting a screensaver we
				-- really go home.
				if event:getAction() == "home" then
					appletManager:callService("goHome")
					return EVENT_CONSUME
				end

				if event:getAction() == "power" or event:getAction() == "power_on" then
					Framework:playSound("SELECT")
					--first power press deactivates	SS (power on already handled in deactivateSS())
					-- this make consistent behavior for any type of SS that is up, power button will always deactivate SS
					-- so user doesn't have to worry if "when off" SS is up or "when stopped" SS is up
					-- and since when playing NP SS isn't really a SS, pwer off will work when NP "SS" engages.
					return EVENT_CONSUME
				end
			end
			return EVENT_UNUSED
		end,
		-100 -- process before other event handlers
	)

	--last resort listener to close SS on any unused action/scroll/mousing (for instance when user hits pause when no server connected)
	Framework:addListener(ACTION | EVENT_SCROLL | EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD | EVENT_MOUSE_DRAG,
		function(event)

			-- screensaver is not active
			if #self.active == 0 then
				return EVENT_UNUSED
			end

			log:debug("Closing screensaver last resort event=", event:tostring())
			self:deactivateScreensaver()

			if event:getType() == ACTION then
				-- make sure when exiting a screensaver with home we
				-- really go home.
				if event:getAction() == "home" then
					appletManager:callService("goHome")
					return EVENT_CONSUME
				end
			end
			return EVENT_CONSUME
		end,
		100 -- process after other event handlers
	)

	jnt:subscribe(self)

	return self
end


--[[

=head2 applets.ScreenSavers.ScreenSaversApplet:free()

Overridden to return always false, this ensure the applet is
permanently loaded.

=cut
--]]
function free(self)
	-- ScreenSavers cannot be freed
	return false
end


--_activate(the_screensaver)
--Activates the screensaver C<the_screensaver>. If <the_screensaver> is nil then the
--screensaver set for the current mode is activated.
-- the force arg is set to true for preview, allowing screensavers that might be not shown in certain circumstances to still be previewed
-- see ClockApplet for example
function _activate(self, the_screensaver, force, isServerRequest)
	log:debug("Screensaver activate ", self.timeout)

	-- what screensaver, check the playmode of the current player
	if the_screensaver == nil then
		-- get timer compare to current timeout and reset timer temoprarily for extended run
		local to, extension
		self.currentSS, to = self:_getDefaultScreensaver()
		extension = to-self.timeout
		if extension > 0 and  self.extension < extension then
			self.extension = extension - self.extension
			self.timer:restart(self.extension)
			log:debug("Extension for ",self.currentSS," for ",extension)
			return
		elseif self.extension > 0 then
			log:debug("Extension finished ",self.currentSS," for ",self.extension)
			self.extension = 0
		end
	else
		self.currentSS = the_screensaver
	end
	local screensaver = self.screensavers[self.currentSS]

	-- In some situations the timer restart below tries to activate a SS when one is already running.
	-- We don't want to do this for BlankScreen when BlankScreen is already active
	-- This causes the backlight to turn on again after 10 seconds. #14986
	if self:isScreensaverActive() and self.current == 'BlankScreen' then
		log:warn("BlankScreen SS is currently active and we're trying to reactivate it. Nothing to activate then, so return")
		return
	else
		log:debug('_activate isScreensaverActive()=', self:isScreensaverActive(), ' self.current: ', self.current)
	end

	-- check if the top window will allow screensavers, if not then
	-- set the screensaver to activate 10 seconds after the window
	-- is closed, assuming we still don't have any activity
	if not Framework.windowStack[1]:canActivateScreensaver() and self:isSoftPowerOn() then
		Framework.windowStack[1]:addListener(EVENT_WINDOW_INACTIVE,
			function()
				if not self.timer:isRunning() then
					log:warn('Screen Saver Retry')
					-- FIXME like a temp extension
					self.timer:restart(10000)
					self.extension = 0
				end
			end)
		return
	end

	local year = os.date("%Y")

	-- the "none" choice is false:false, for which the proper course is to do nothing
	if self.currentSS == 'false:false' then
		log:warn('"none" is the configured screensaver for ', self:_getMode(), ', so do nothing')
		if self.poweroff and self:_getMode() == 'whenStopped' then
			self.timerPowerOff:start()
		end
		return
	end

	-- bug 15654, don't allow false:false to be the default whenOff SS when the clock is wrong
	local useBlankSS = tonumber(year) < 2010 and not force and self:_getMode() == 'whenOff' and not isServerRequest

	if not screensaver or not screensaver.applet -- fallback to default if screensaver.applet doesn't exist
		or useBlankSS then -- fallback to blank screensaver on whenOff and no clock

		if useBlankSS then
			-- bug 16148: special case, fall back to blank SS for whenOff and the clock not set and not a server request
			log:warn('Clock is not set properly, so fallback to blank screen SS')
			self.currentSS = 'BlankScreen:openScreensaver'
			screensaver = self.screensavers[self.currentSS]
		else	
			-- no screensaver, fallback to default
			log:warn('The configured screensaver method ', self.currentSS, ' is not available. Falling back to default from Meta file')
			self.currentSS = self.defaultSettings[self:_getMode()]
			screensaver = self.screensavers[self.currentSS]
		end
	end

	if screensaver and screensaver.applet then
		-- activate the screensaver. it should register any windows with
		-- screensaverWindow, and open then itself
		local instance = appletManager:loadApplet(screensaver.applet)
		if instance[screensaver.method](instance, force, screensaver.methodParam) ~= false then
			log:info("activated " .. screensaver.applet .. " screensaver")
		end
		self.timer:stop()
		self.isScreenSaverActive = true
	else
		-- special case for screensaver of NONE
		log:info('There is no screensaver applet available for this mode')
	end

	if self.poweroff and self:_getMode() == 'whenStopped' then
		self.timerPowerOff:start()
	end
end



--service method
function activateScreensaver(self, isServerRequest)
	log:debug("activateScreensaver service")
	self:_activate(nil, _, isServerRequest)
end


function isSoftPowerOn(self)
	return jiveMain:getSoftPowerState() == "on"
end


function _closeAnyPowerOnWindow(self)
	if self.powerOnWindow then
		self.powerOnWindow:hide(Window.transitionNone)
		self.powerOnWindow = nil

		local ss = self:_getOffScreensaver()

		if ss then
			local screensaver = self.screensavers[ss]
			if not screensaver or not screensaver.applet then
				log:debug("no screensaver, do nothing")
				return
			end

			local instance = appletManager:loadApplet(screensaver.applet)
			if instance.onOverlayWindowHidden then
				instance:onOverlayWindowHidden()
			end
		end
	end

end


function _getOffScreensaver(self)
	return self:getSettings()["whenOff"] or "BlankScreen:openScreensaver" --hardcode for backward compatability
end


function _getMode(self)
	local player = appletManager:callService("getCurrentPlayer")
	if not self:isSoftPowerOn() and System:hasSoftPower() then
		return 'whenOff'
	else
		if player and player:getPlayMode() == "play" then
			return 'whenPlaying'
		end
	end
	return 'whenStopped'
end


function _getDefaultScreensaver(self)
	local ss
	local dd = 0
	local set = self:getSettings()

	local ssMode = self:_getMode()
	if ssMode == 'whenOff' then
		ss = self:_getOffScreensaver()
	elseif ssMode == 'whenPlaying' then
		ss = set["whenPlaying"]
		dd = set["whenPlayingDelay"] or 0
	else
		ss = set['whenStopped']
		dd = set['whenStoppedDelay'] or 0
	end
	log:debug("_getDefaultScreensaver ",ssMode,": ", ss," ",dd)

	return ss, dd
end


function _setSSAllowedActions(self, scrollAllowed, ssAllowedActions, mouseAllowed)
	self.scrollAllowed = scrollAllowed
	self.ssAllowedActions = ssAllowedActions
	self.mouseAllowed = mouseAllowed
end


function _clearSSAllowedActions(self)
	self:_setSSAllowedActions(nil, nil, nil)
end


-- screensavers can have methods that are executed on close
function _deactivate(self, window, the_screensaver)
	log:debug("Screensaver deactivate")

	self:_clearSSAllowedActions()

	self:_closeAnyPowerOnWindow()

	if not the_screensaver then
		the_screensaver = self:_getDefaultScreensaver()
	end
	local screensaver = self.screensavers[the_screensaver]

	if screensaver and screensaver.applet and screensaver.closeMethod then
		local instance = appletManager:loadApplet(screensaver.applet)
		instance[screensaver.closeMethod](instance, screensaver.methodParam)
	end
	window:hide(Window.transitionNone)
	self.isScreenSaverActive = false
	self.demoScreensaver = nil

end


-- switch screensavers on a player mode change
function notify_playerModeChange(self, player, mode)
	if not self:isSoftPowerOn() then
		return
	end

	local oldActive = self.active

	if #oldActive == 0 then
		log:debug("screensaver is not active")
		return
	end

	self.active = {}
	self:_activate()

	log:debug("close active screensaver")
	for i, window in ipairs(oldActive) do
		_deactivate(self, window, self.demoScreensaver)
	end
end


--FIXME poweron allow?
local _powerAllowedActions = {
			["play_preset_0"] = 1,
			["play_preset_1"] = 1,
			["play_preset_2"] = 1,
			["play_preset_3"] = 1,
			["play_preset_4"] = 1,
			["play_preset_5"] = 1,
			["play_preset_6"] = 1,
			["play_preset_7"] = 1,
			["play_preset_8"] = 1,
			["play_preset_9"] = 1,
			["play"]          = "pause",
			["shutdown"]      = 1,
		}

function _powerActionHandler(self, actionEvent)
	local action = actionEvent:getAction()

	if _powerAllowedActions[action] then
		--for special allowed actions, turn on power and forward the action
		--jiveMain:setSoftPowerState("on")
		Framework:pushAction("power_on")

		--certain actions like play during poweroff translate to other actions
		Framework:pushAction(_powerAllowedActions[action] ~= 1 and action or _powerAllowedActions[action])
		return
	end
	log:debug("show power on window (if the specific SS allows it)")
	self:_showPowerOnWindow()
end


function _showPowerOnWindow(self)
	if self.powerOnWindow then
		return EVENT_UNUSED
	end

	local ss = self.currentSS or self:_getOffScreensaver()

	if ss then
		local screensaver = self.screensavers[ss]
		if not screensaver or not screensaver.applet then
			log:debug("no screensaver, do nothing")
			return
		end

		if not System:hasTouch() then
			log:debug("ss: don't use power on window")
			return
		end
		local instance = appletManager:loadApplet(screensaver.applet)
		if instance.onOverlayWindowShown then
			instance:onOverlayWindowShown()
		end
	end

	self.powerOnWindow = Window("power_on_window")
	self.powerOnWindow:setButtonAction("lbutton", "power")
	self.powerOnWindow:setButtonAction("rbutton", nil)
	self.powerOnWindow:setTransparent(true)
	self.powerOnWindow:setAlwaysOnTop(true)
	self.powerOnWindow:setAllowScreensaver(false)
	self.powerOnWindow:ignoreAllInputExcept({ "power", "power_on", "power_off" },
						function(actionEvent)
							return self:_powerActionHandler(actionEvent)
						end)
	self.powerOnWindow:show(Window.transitionNone)

	self.powerOnWindow:addTimer(    self:getSettings()['poweron_window_time'],
					function ()
						self:_closeAnyPowerOnWindow()
					end,
					true)
end


--[[

=head2 screensaverWindow(window)

Register the I<window> as a screensaver window. This is used to maintain the
the screensaver activity, and adds some default listeners for screensaver
behaviour.

If the screensaver window wants to respond to mouse activity or scrolling or actions (without the screensaver exiting), use
the boolean I<scrollAllowed> and boolean I<mouseAllowed> and string table I<ssAllowedActions>

If I<ssAllowedActions> is nil, no actions will be passed on. If an empty table is sent, all actions will be passed on.

If I<ssName> is not nil, use the ssName to store a name for the screensaver in self.current. If nil, it gets a default name of 'unnamedScreenSaver'

=cut
--]]
function screensaverWindow(self, window, scrollAllowed, ssAllowedActions, mouseAllowed, ssName)

	if not ssName then
		ssName = 'unnamedScreenSaver'
	end
	window:setIsScreensaver(true)

	self:_setSSAllowedActions(scrollAllowed, ssAllowedActions, mouseAllowed)
	
	-- the screensaver is active when this window is pushed to the window stack
	window:addListener(EVENT_WINDOW_PUSH,
			   function(event)
				   log:debug("screensaver opened on Push ", #self.active," ",ssName)

				   table.insert(self.active, window)
				   self.current = ssName
				   self.timer:stop()
				   return EVENT_UNUSED
			   end)

	-- the screensaver is inactive when this window is poped from the window stack
	window:addListener(EVENT_WINDOW_POP,
			   function(event)
				   table.delete(self.active, window)
				   self.current = nil
				   if #self.active == 0 then
					   log:debug("screensaver inactive")
					   self:_restartScreenSaverTimer()
				   end

				   log:debug("screensaver closed on Pop ", #self.active, " ", ssName)
				   return EVENT_UNUSED
			   end)

	if not self:isSoftPowerOn() then
		-- allow input to pass through, so that the following listeners will be honored
	        self:_setSSAllowedActions(true, {}, true)

		window:ignoreAllInputExcept(    { "power", "power_on", "power_off" },
		                                function(actionEvent)
		                                        self:_powerActionHandler(actionEvent)
		                                end)
		window:addListener(     EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD | EVENT_MOUSE_DRAG,
		                        function (event)
			                        self:_showPowerOnWindow()
			                        return EVENT_CONSUME
		                        end)
		window:addListener(     EVENT_SCROLL,
					function ()
						self:_showPowerOnWindow()
					end)
	end

	log:debug("Overriding the default window action 'bump' handling to allow action to fall through to framework listeners")
	window:removeDefaultActionListeners()
	
end


--service method
function restartScreenSaverTimer(self)
	log:debug("restartScreenSaverTimer() Service")
	self:_restartScreenSaverTimer(self.timeout)
end


function _restartScreenSaverTimer(self,timeout)
	self.extension = 0
	self.timer:restart(timeout)
	self.timerPowerOff:stop()
end


--service method
function isScreensaverActive(self)
	log:debug("isScreensaverActive=",self.isScreenSaverActive)
	return self.isScreenSaverActive
end

--service method
function deactivateScreensaver(self)
	log:debug("deactivateScreensaver Service")

	-- close all screensaver windows -0 do oldActive swap to avoid deleting iterated values when there is more than one window
	local oldActive = self.active
	
	-- also set the state to false here, because this function could also be called externally through a service call
	-- It's not enough to set it to false only here, since the addListener() events test for #self.active == 0 and exit if true
	-- the now playing screen saver is not a screen saver, so the addListener() events exits there, and never call this function
	self.isScreenSaverActive = false
	if #oldActive == 0 then
		-- screensaver is not active
		return
	end

	self.active = {}

	for i, window in ipairs(oldActive) do
		_deactivate(self, window, self.demoScreensaver)
	end

	if not self:isSoftPowerOn() then
		--jiveMain:setSoftPowerState("on")
		Framework:pushAction("power_on")
	end
end


function getKey(self, appletName, method, additionalKey)
	local key = tostring(appletName) .. ":" .. tostring(method)
	if additionalKey then
		key = key .. ":" .. tostring(additionalKey)
	end
	return key
end


function removeScreenSaver(self, appletName, method, settingsName, additionalKey)
	local key = self:getKey(appletName, method, additionalKey)

	if settingsName then
		self.screensaverSettings[settingsName] = nil
	end
	
	self.screensavers[key] = nil
end


--service method
function addScreenSaver(self, displayName, applet, method, settingsName, settings, weight, closeMethod, methodParam, additionalKey, modeExclusions)
	local key = self:getKey(applet, method, additionalKey)
	self.screensavers[key] = {
		applet = applet,
		method = method,
		displayName = displayName,
		settings = settings,
		weight = weight,
		closeMethod = closeMethod,
		methodParam = methodParam,
		modeExclusions = modeExclusions
	}

	if settingsName then
		self.screensaverSettings[settingsName] = self.screensavers[key]
	end
end


function setScreenSaver(self, mode, key)
	self:getSettings()[mode] = key
end


function setTimeout(self, timeout, timer)
	local set = self:getSettings()

	if timer then
		set[timer]=timeout
		if timer ~= 'poweroff' then
			self.timerPowerOff:setInterval(self.poweroff)
			return
		elseif timer ~= 'poweron_window_time' then
			return
		end
		if timeout > self.timeout then
			-- timer runs on shortest timer, as it will be extended
			timeout = self.timeout
		end
	end
	-- setting a long master timer suppresses shorter specific timers
	-- setting short spec time pushes down master timer.
	set["timeout"] = timeout
	self.timeout = timeout
	self.timer:setInterval(self.timeout)
end


function screensaverSetting(self, menuItem, mode)
	local menu = SimpleMenu("menu")
        menu:setComparator(menu.itemComparatorWeightAlpha)

	local activeScreensaver = self:getSettings()[mode]

	local group = RadioGroup()
	for key, screensaver in pairs(self.screensavers) do
		if not screensaver.modeExclusions or not table.contains(screensaver.modeExclusions, mode) then -- not all SSs should appear in all modes
			local button = RadioButton(
				"radio",
				group,
				function()
					self:setScreenSaver(mode, key)
				end,
				key == activeScreensaver
			)
			local testScreensaverAction = function (self)
				self.demoScreensaver = key
				self:_activate(key, true)
				return EVENT_CONSUME
			end

			-- pressing play should play the screensaver, so we need a handler
			button:addActionListener("play", self, testScreensaverAction)
			button:addActionListener("add", self, testScreensaverAction)

			-- set default weight to 100
			if not screensaver.weight then screensaver.weight = 100 end
			menu:addItem({
					text = screensaver.displayName,
					style = 'item_choice',
					check = button,
					weight = screensaver.weight
				     })
		end
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')

	local token = 'SCREENSAVER_SELECT_PLAYING_HELP'
	if mode == 'whenStopped' then
		token = 'SCREENSAVER_SELECT_STOPPED_HELP'
	elseif mode == 'whenOff' then
		token = 'SCREENSAVER_SELECT_OFF_HELP'
	end
	menu:setHeaderWidget(Textarea("help_text", self:string(token)))
	window:addWidget(menu)

	window:addListener(EVENT_WINDOW_POP, function() 
			-- we may be moving off of false:false here, so when we leave this window, restart the SS timer
			self:_restartScreenSaverTimer()
			self:storeSettings() 
	end)

	self:tieAndShowWindow(window)
	return window
end

function timeoutSetting(self, menuItem, timer)
	local group = RadioGroup()

	local timeout = self:getSettings()[timer] or self:getSettings()['timeout']
	
	local window = Window("text_list", menuItem.text, 'settingstitle')

	local settings = false
	window:addWidget(SimpleMenu("menu",
		{
			{
				text = self:string('DELAY_5_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(10000, timer) settings=true end, timeout == 5000),
			},
			{
				text = self:string('DELAY_10_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(10000, timer) settings=true end, timeout == 10000),
			},
			{
				text = self:string('DELAY_20_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(20000, timer) settings=true end, timeout == 20000),
			},
			{
				text = self:string('DELAY_30_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(30000, timer) settings=true end, timeout == 30000),
			},
			{
				text = self:string('DELAY_1_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(60000, timer) settings=true end, timeout == 60000),
			},
			{ 
				text = self:string('DELAY_2_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(120000, timer) settings=true end, timeout == 120000),
			},
			{
				text = self:string('DELAY_5_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(300000, timer) settings=true end, timeout == 300000),
			},
			{ 
				text = self:string('DELAY_10_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(600000, timer) settings=true end, timeout == 600000),
			},
			{ 
				text = self:string('DELAY_30_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(1800000, timer) settings=true end, timeout == 1800000),
			},
			{
				text = self:string('DELAY_1_HR'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(3600000, timer) settings=true end, timeout == 3600000),
			},
			{
				text = self:string('DELAY_2_HR'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(7200000, timer) settings=true end, timeout == 7200000),
			},
			{
				text = self:string('DELAY_4_HR'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(14400000, timer) settings=true end, timeout == 14400000),
			},
		}))

	window:addListener(EVENT_WINDOW_POP, function() if settings then self:storeSettings() end end)

	self:tieAndShowWindow(window)
	return window
end

function openAdvSettings(self, menuItem)
	local menu = SimpleMenu("menu",
		{
			{
				text = self:string("SCREENSAVER_DELAY_PLAYING"),
				weight = 5,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:timeoutSetting(menu_item, 'whenPlayingDelay')
					   end
			},
			{
				text = self:string("SCREENSAVER_DELAY_STOPPED"),
				weight = 5,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:timeoutSetting(menu_item ,'whenStoppedDelay')
					   end
			},
			{
				text = self:string("SCREENSAVER_POWERON_WINDOW_TIME"),
				weight = 5,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:timeoutSetting(menu_item ,'poweron_window_time')
					   end
			},
			{
				text = self:string("SCREENSAVER_POWEROFF"),
				weight = 5,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:timeoutSetting(menu_item,'poweroff')
					   end
			},
		})

	local window = Window("text_list", menuItem.text, 'advsettingstitle')
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function openSettings(self, menuItem)

	local menu = SimpleMenu("menu",
		{
			{ 
				text = self:string('SCREENSAVER_WHEN_PLAYING'),
				weight = 1,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:screensaverSetting(menu_item, "whenPlaying")
					   end
			},
			{
				text = self:string("SCREENSAVER_WHEN_STOPPED"),
				weight = 1,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:screensaverSetting(menu_item, "whenStopped")
					   end
			},
			{
				text = self:string("SCREENSAVER_DELAY"),
				weight = 5,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:timeoutSetting(menu_item)
					   end
			},
		})

	-- only present a WHEN OFF option when there is a local player present FIXME why?
	if Player:getLocalPlayer() then
		menu:addItem(
			{
				text = self:string("SCREENSAVER_WHEN_OFF"),
				weight = 2,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:screensaverSetting(menu_item, "whenOff")
					   end
			}
		)
	end
	
	menu:setComparator(menu.itemComparatorWeightAlpha)
	for setting_name, screensaver in pairs(self.screensaverSettings) do
		menu:addItem({
				     text = setting_name,
				     weight = 3,
				     sound = "WINDOWSHOW",
				     callback =
					     function(event, menuItem)
							local instance = appletManager:loadApplet(screensaver.applet)
							instance[screensaver.settings](instance, menuItem)
					     end
			     })
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(menu)

	-- Store the applet settings when the window is closed
	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)

	self:tieAndShowWindow(window)
	return window
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

