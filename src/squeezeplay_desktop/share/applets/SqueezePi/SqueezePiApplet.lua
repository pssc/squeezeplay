

-- stuff we use
local assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs = assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs

local oo                     = require("loop.simple")

local string                 = require("string")
local table                  = require("jive.utils.table")
local io                     = require("io")

local Applet                 = require("jive.Applet")
local System                 = require("jive.System")
local Framework              = require("jive.ui.Framework")
local Label                  = require("jive.ui.Label")
local Textarea               = require("jive.ui.Textarea")
local Window                 = require("jive.ui.Window")
local Choice 		     = require("jive.ui.Choice")
local Popup                  = require("jive.ui.Popup")
local SimpleMenu	     = require("jive.ui.SimpleMenu")


local jnt                    = jnt

local debug                  = require("jive.utils.debug")

module(..., Framework.constants)
oo.class(_M, Applet)

local AUDIO_SELECT = { "AUTO", "SOCKET", "HDMI" }

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
        local f,err = io.popen("amixer -c ALSA cget numid=3", "r")
        if not f then
                log:error("amixer could not be run ",err,".")
                -- add error to widow fixme
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

        f,err = io.popen("tvservice -a", "r")
        if not f then
                log:warn("tvservice -a could not be run ",err,".")
                -- add error to widow fixme
                window:addWidget(Textarea("text", "tvservice -a"..err..".")) --FIXME string err
        end
        -- "    PCM supported: Max channels: 2, Max samplerate:  32kHz, Max samplesize 16 bits."
        local i = 0
        for v in f:lines() do
                -- c,r,b = string.match(i, "    PCM supported: Max channels: (%d), Max samplerate:  (%d)kHz, Max samplesize (%d) bits.") 
		menu:addItem({id='tvservice'..i,text=v,style = 'item_text'})
                i = i + 1
        end
        f:close()

        window:addWidget(menu)
	self:tieAndShowWindow(window)
	return window
end

function map(f, t)
  local t2 = {}
  for k,v in pairs(t) do t2[k] = f(v) end
  return t2
end

