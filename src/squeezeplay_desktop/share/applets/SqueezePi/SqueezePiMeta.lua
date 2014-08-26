
local oo            = require("loop.simple")
local io            = require("io")
local math          = require("math")
local string        = require("string")
local table         = require("jive.utils.table")
local os            = require("os")

local Decode        = require("squeezeplay.decode")
local AppletMeta    = require("jive.AppletMeta")
local LocalPlayer   = require("jive.slim.LocalPlayer")
local Framework     = require("jive.ui.Framework")
local System        = require("jive.System")
local Player        = require("jive.slim.Player")
local SlimServer        = require("jive.slim.SlimServer")

local appletManager = appletManager
local jiveMain      = jiveMain
local jive          = jive
local jnt           = jnt


module(...)
-- inherit from linux?
oo.class(_M, AppletMeta)

local CPU_INFO="/proc/cpuinfo"

function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return { 
--		audio_select = "AUTO" we dont hold the state alsa does...
	}
end


function registerApplet(meta)
        -- Check pi...
	local f = io.open(CPU_INFO)
        local pi = false
        if not f then
           -- Warn
           return
        end
        for line in f:lines() do
            if string.match(line, "Hardware%s+: BCM2708") then
               pi = true
            end
        end
        f:close()
        if not pi then
           return
        end

	-- Set player device type 
        LocalPlayer:setDeviceType("squeezeplay", "SqueezePi")

        -- Set the minimum support server version the version has to be greater than this ie 7.7+
        SlimServer:setMinimumVersion("7.6")

        jiveMain:addItem(meta:menuItem('piaudio_selector', 'settingsAudio', "AUDIO_SELECT", function(applet, ...) applet:settingsAudioSelect(...) end))

end


