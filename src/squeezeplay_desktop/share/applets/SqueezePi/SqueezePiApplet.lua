
-- stuff we use
local type, assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs = type, assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs

local oo                     = require("loop.simple")

local string                 = require("string")
local io                     = require("io")
local os                     = require("os")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local System                 = require("jive.System")
local Framework              = require("jive.ui.Framework")

local Label                  = require("jive.ui.Label")
local Textarea               = require("jive.ui.Textarea")
local Choice 		     = require("jive.ui.Choice")
local Checkbox		     = require("jive.ui.Checkbox")
local RadioGroup	     = require("jive.ui.RadioGroup")
local RadioButton	     = require("jive.ui.RadioButton")
local Timer  		     = require("jive.ui.Timer")
local Process  		     = require("jive.net.Process")

local Window                 = require("jive.ui.Window")
local Popup                  = require("jive.ui.Popup")
local SimpleMenu	     = require("jive.ui.SimpleMenu")

local LinuxApplet            = require("applets.Linux.LinuxApplet")
local log                    = require("jive.utils.log").logger("applet.SqueezePi")

local socket		     = require("socket")
local appletManager	     = appletManager
local jnt                    = jnt
local jiveMain		     = jiveMain


module(..., Framework.constants)
oo.class(_M, LinuxApplet)

local AUDIO_SELECT = { "AUTO", "SOCKET", "HDMI" }
local RESTART_PERIOD = 30000


function init(self)
	self:getSettings()['env'] = {}
	log:warn("Meta ",debug.view(self:getSettingsMeta()))
	-- FIXME range?
	self:registerEnv('JIVE_FR', { limit = "cardinal", })
	--if test...
	if not appletManager:callService('test') then
		self:registerEnv('PI_DUMMY', { limit = "cardinal", })
	end
	self:registerEnv('SDL_FBACCEL', { limit = "dict", dict = { name = "FBACCEL" , values = { NONE = "0", DISPMANX = "176" }}})
	local ddv = { HDMI = "5", OTHER="6", LCD ="4", DEFAULT="0" }
	local dd = { values = ddv, name = "DISPMANX_DISPLAYS" }
	self:registerEnv('SDL_DISPMANX_DISPLAY', { limit = "dict", dict = dd })
	self:registerEnv('SDL_DISPMANX_DISPLAY_ALT', { limit = "dict", dict = dd})
	--FIXME func
	self:registerEnv('SDL_DISPMANX_FBCP', { limit = "string",})
	-- FIXME audio action... via action function... or
	self:readEnv() --FIXME if not persist what if settings are different to current env...
	Process.init(jiveMain)
	self.state = {}
	self:_trigger(self.state)
	Timer(RESTART_PERIOD, function() self:_trigger(self.state) end):start()

	-- notifications
	jnt:subscribe(self)

	if not self:getSettings()['nosplash_sound'] then
		playSplashSound(self)
	end
end


function _trigger(self,state)
        if self:getSettings()['cec_toggle'] and (not state['cec'] or (state['cec'] and state['cec']:status() == "dead")) then
                local cmdline =  "./libcec-daemon -a -v 2>&1"
                log:warn("Starting cec: ", cmdline)
                state['cec'] = Process(jnt, cmdline) --2>/dev/null 1>/dev/null")
		state['cec']:setKillTerm()
		state['cec']:readPid(state['cec']:logSink("cec"),false)
        end
end


function settingsAudioSelect(self)
	local window = Window("information", self:string("AUDIO_SELECT"), 'settingstitle')

	local setting = nil
        -- read current state
-- numid=3,iface=MIXER,name='PCM Playback Route'
--  ; type=INTEGER,access=rw------,values=1,min=0,max=2,step=0
--  : values=2
        local f,err = io.popen("amixer -c ALSA cget numid=3 2>&1", "r")
        if not f then
                log:error("amixer could not be run ",err,".")
            	window:addWidget(Textarea("text", "amixer could not be run "..err..".")) --FIXME string err
	        self:tieAndShowWindow(window)
                return window
        end
        for line in f:lines() do
            log:debug(line)
            setting = string.match(line, "  : values=(%d)") 
            if setting != nil then
                setting=setting+1
                break
            end 
        end
        f:close()
        if not setting then
             -- add error to widow fixme
            log:error("failed to parse amxier output\n")
            window:addWidget(Textarea("text", "failed to parse amxier output\n")) --FIXME string err
	    self:tieAndShowWindow(window)
            return window
        end

        local menu = SimpleMenu("menu", {
             {
                        id = 'audioselector',
                        text = self:string('AUDIO_SELECTOR'),
                        style = 'item_choice',
                        sound = "WINDOWSHOW",
                        check = Choice("choice", map(function(x) return self:string(x) end , AUDIO_SELECT), function(obj, selectedIndex)
                                               log:info(
                                                        "Choice updated: ",
                                                        tostring(selectedIndex-1),
                                                        " - ",
                                                        tostring(obj:getSelected())
                                               )
						local amixer,err = io.popen("amixer -c ALSA cset numid=3 "..selectedIndex-1,"r")
                                                if err then
                                                   log:error("amixer could not be run ",err,".")
						else
                                                	amixer:close()
						end
                                end
                        ,  setting) -- Index into choice
                },
	})

	local command = "tvservice -a 2>&1"
        local f,err = io.popen(command, "r")
        if not f then
                log:warn(command,"-- could not be run ",err,".")
		menu:setHeaderWidget(Textarea("help_text", command.."\n"..err.."."))
        end
        -- "    PCM supported: Max channels: 2, Max samplerate:  32kHz, Max samplesize 16 bits."
        local i = 0
        for v in f:lines() do
		menu:addItem({id='tvservice'..i,text=v,style = 'item_text'})
                i = i + 1
        end
        f:close()

	local pi = self:getSettings()['pi']
        local i = 0
        if pi then
            for k,v in pairs(pi) do
		v = k == "revision" and string.format("%04x",v) or v
		menu:addItem({id='pi'..i,text=tostring(self:string(string.upper(k)))..": "..tostring(v),style = 'item_text'})
                i = i + 1
            end
        end
        window:addWidget(menu)
	self:tieAndShowWindow(window)
	return window
end


function setBrightnessSqueezePi(self, level)
	log:info("setBrightnessSqueezePi: ", level)
	-- we may have displays that honour the blanking...
	local mylevel
        if level == "off" then
                mylevel = 0
        elseif level == "on" then
                mylevel = 1
        elseif level == nil then
                return
        else
                log:debug("setBrightness: mylevel ",level," to 1")
                mylevel = 1
        end

	-- super class call for generic linux blanking code blanking and backlight.
	self:setBrightness(level)

	if (self:getSettings()['display_power']) then
		local off = nil
		local command = "vcgencmd display_power"
		local f,err = io.popen(command, "r")
		if f then
			for line in f:lines() do
				local sc = string.match(line, "^display_power=([-%d]+)")
				if sc then
					sc = tonumber(sc) or 0
					if sc == 0 then
						off=true
					elseif sc >= 1 then
						off=false
					end
					log:info("vcgencmd display_power=",sc," we are ",off)
				else
					log:warn("Parse error for ",command)
					log:warn("line '",line,"'")
				end
			end
			f:close()
		else
			log:warn(command,"-- failed ",err)
		end

		-- best efforts this is a heavy weight operation now using vcgencmd display_power we still have to wait for the screen/display to detect and catch up with us.
		command = (mylevel == 0) and "vcgencmd display_power 0 2>&1" or "vcgencmd display_power 1 2>&1"
		if (mylevel == 0 and off == true) then
			log:info("Allready off")
		elseif (mylevel == 1 and off == false) then
			log:info("Allready on")
		else
			log:info(command)
			f,err = io.popen(command, "r")
			if f then
				f:close()
				if mylevel == 0 then
					-- pause for effect ?
					-- blaking will allready possibly be active
					-- socket.select(nil, nil, 2) -- sleep
				else
					-- force redraw
					-- socket.select(nil, nil, 2) -- sleep
					Framework:reDraw(nil)
				end
			else
				log:warn(command,"-- failed ",err,".")
			end
		end
	end

end

--[[
function getBrightness(self)
        return sysReadNumber(self, "blank")
end
]]--

function openAdvSettings(self, menuItem)
        local menu = SimpleMenu("menu",
                {
                        {
                                text = self:string("REBOOT"),
                                style = 'item_choice',
                                callback = function(event, menu_item)
                                                   appletManager:callService("reboot")
                                           end
                        },
                        {
                                text = self:string("POWEROFF"),
				style = 'item_choice',
                                callback = function(event, menu_item)
                                                   appletManager:callService("poweroff")
                                           end
                        },
                })

	self:metaMenuToggle(menu,"fbcp_control")
	self:metaMenuToggle(menu,"fbcp_backlight")
	self:metaMenuToggle(menu,"fbcp_toggle")
	self:presentMetaItem('cec_toggle',menu)
	--self:metaMenuToggle(menu,"time_sync_toggle")
	self:presentMetaItem('time_sync_toggle',menu)
	self:presentMetaItem('JIVE_DUMMY',menu)
	self:presentMetaItem('JIVE_FR',menu)
	self:presentMetaItem('SDL_FBACCEL',menu)
	self:presentMetaItem('SDL_DISPMANX_DISPLAY_ALT',menu)
	self:presentMetaItem('SDL_DISPMANX_DISPLAY',menu)
	self:metaMenuToggle(menu,"backlight")
	self:metaMenuToggle(menu,"blanking")
	self:metaMenuToggle(menu,"display_power")

	-- SDL_DISPMANX_FBCP control -- function call back meta....
	--self:presentMetaItem('SDL_DISPMANX_FBCP',menu)
	menu:addItem({
		text = self:string("MENU_SDL_DISPMANX_FBCP"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
					local window = Window("text_list", menuItem.text)
					local menu = SimpleMenu("menu")
					local group = RadioGroup()

					menu:setHeaderWidget(Textarea("help_text", self:string("HELP_SDL_DISPMANX_FBCP"))) 
					-- fbdetection ... Linux?
					-- /proc/fb
					-- 0 BCM2708 FB
					-- 1 fb_ili9340
					-- Ratio?
					-- FB options
					local fh = io.open("/proc/fb","r")
					if fh then
						for line in fh:lines() do
							local fb,desc = string.match(line,"(%d+)%s+(.+)")
							if desc and fb ~= "0" then
								fb = "/dev/fb"..fb
								menu:addItem({
									text = desc.." ("..fb..")",
									style = 'item_choice',
									check = RadioButton("radio", group,
										function(object, isSelected)
											self:setMetaValue('SDL_DISPMANX_FBCP',fb)
										end,
										self:getMetaValue('SDL_DISPMANX_FBCP') == fb
									),
								})
							end
						end
						fh:close()
					end
					-- disable option
					menu:addItem({
							text = self:string("DISABLE"),
							style = 'item_choice',
							check = RadioButton("radio", group,
								  function(object, isSelected)
									  self:setMetaValue('SDL_DISPMANX_FBCP',nil)
								  end,
								  self:getMetaValue('SDL_DISPMANX_FBCP') == nil
							),
					})

					window:addWidget(menu)
					self:tieAndShowWindow(window)
				   end,
	})

        local window = Window("text_list", menuItem.text, 'advsettingstitle')
        window:addWidget(menu)

	self:tieAndShowWindow(window)
        return window
end

function notify_skinSelected(self)
	local mapping = appletManager:callService("getInputDetectorMapping")
	-- settings FBCP and toggle
	local st = self:getSettings()
	local fbcp = st["fbcp_control"]
	local toggle = st["fbcp_toggle"]
	local backlight = st["fbcp_backlight"]

	if (self:getEnv('SDL_DISPMANX_FBCP') and mapping and fbcp) then
		if mapping == "REMOTE" and not toggle then
			System:putenv("SDL_DISPMANX_FBCP")
			if backlight then self:setBrightness("off","backlight") end
		else
			System:putenv("SDL_DISPMANX_FBCP="..(st.env['SDL_DISPMANX_FBCP'] or "1"))
			if backlight then self:setBrightness("on","backlight") end
		end
		Framework:getModes()
	end
end

function free(self)
	local st = self:getSettings()

	if st and st['env_unstable'] then
		log:warn("free env stored")
		self:storeEnv()
	end

	if st and st['settings_unstable'] then
		local env = st.env

		-- we dont read from envs file we are resident we just read from env
		-- will need to store if not resident app.
		st.env = {}
		log:warn("free settings stored")
		st['settings_unstable'] = nil
		self:storeSettings()
		st.env = env
	end

	return false
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.
Copyright 2014-18 Phillip Camp. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
