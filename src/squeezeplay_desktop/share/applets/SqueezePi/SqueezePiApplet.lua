

-- stuff we use
local assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs = assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs

local oo                     = require("loop.simple")

local string                 = require("string")
local io                     = require("io")
local os                     = require("os")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local Applet                 = require("jive.Applet")
local System                 = require("jive.System")
local Framework              = require("jive.ui.Framework")
local Label                  = require("jive.ui.Label")
local Textarea               = require("jive.ui.Textarea")
local Window                 = require("jive.ui.Window")
local Choice 		     = require("jive.ui.Choice")
local Popup                  = require("jive.ui.Popup")
local SimpleMenu	     = require("jive.ui.SimpleMenu")

local LinuxApplet            = require("applets.Linux.LinuxApplet")
local log                    = require("jive.utils.log").logger("applet.SqueezePi")

local socket		= require("socket")
local appletManager = appletManager
local jnt                    = jnt


module(..., Framework.constants)
oo.class(_M, LinuxApplet)

local AUDIO_SELECT = { "AUTO", "SOCKET", "HDMI" }


function init(self)
	--local fbdev = string.match(os.getenv("SDL_FBDEV") or "", "/dev/fb([0-9]+)")
	--sysOpen(self, "/sys/class/graphics/fb"..(fbdev and fbdev or "0").."/", "blank", "rw")
	-- FIXME on screen init? timered ? or just do on reg? app unloads?
        --self:setBrightnessSqueezePi('on')
        --log:debug("init end")
end

function settingsAudioSelect(self)
	local window = Window("information", self:string("AUDIO_SELECT"), 'settingstitle')

	local setting = nil
        local fresh = function()
                log:debug(self,":settingsAudioSelect.fresh(",window:getTitle(),")")
                local nw = self:menuProxy(menuItem,i,refresh)
                nw:replace(window,Window.transtionNone)
                window = nw
                log:debug(self,":settingsAudioSelect.fresh(",window:getTitle(),") end")
        end
      
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
                window:addWidget(Textarea("text", command.."\n"..err.."."))
        end
        -- "    PCM supported: Max channels: 2, Max samplerate:  32kHz, Max samplesize 16 bits."
        local i = 0
        for v in f:lines() do
                -- c,r,b = string.match(i, "    PCM supported: Max channels: (%d), Max samplerate:  (%d)kHz, Max samplesize (%d) bits.") 
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
	-- we may have displays than honour the blanking...
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
				-- display_power=1
				local sc = string.match(line, "^display_power=([%d]+)")
				if sc then
					sc = tonumber(sc) or 0
					if sc == 0 then
						off=true
					else
						off=false
					end
					log:debug("state ",sc," ",off)
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
					--blaking will allready possibly be active
					-- socket.select(nil, nil, 2) -- sleep
				else
					-- force redraw
					socket.select(nil, nil, 2) -- sleep
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

        local window = Window("text_list", menuItem.text, 'advsettingstitle')
        window:addWidget(menu)

        self:tieAndShowWindow(window)
        return window
end

function map(f, t)
  local t2 = {}
  for k,v in pairs(t) do t2[k] = f(v) end
  return t2
end
