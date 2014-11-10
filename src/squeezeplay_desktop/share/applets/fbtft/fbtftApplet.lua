

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
local log                    = require("jive.utils.log").logger("applet.fbtft")
local jnt                    = jnt

local appletManager = appletManager

module(..., Framework.constants)
oo.class(_M, LinuxApplet)



function init(self)
	sysOpen(self, "/sys/class/gpio/","export","w")
	sysWrite(self, "export", 252) 
	sysOpen(self, "/sys/class/gpio/gpio252/","direction","w")
	sysWrite(self, "direction", "out") 
	sysOpen(self, "/sys/class/gpio/gpio252/","value","w")

	local i = 0
	while appletManager:hasService("setBrightness"..i) do
		self["setBrightness"..i] = self.setBrightness
		i = i + 1
	end
	self:setBrightness('on')
end


function setBrightness(self, level)
        -- FIXME a quick hack to prevent the display from dimming
        if level == "off" then
                level = 0
        elseif level == "on" then
                level = 1
        elseif level == nil then
                return
        else
                level = 1
        end
        log:info("setBrightness: ", level)
	sysWrite(self, "value", level) -- this is backlight on off
end

