
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
local Decode        = require("squeezeplay.decode")
local debug           = require("jive.utils.debug")
local ArtworkCache = require("jive.slim.ArtworkCache")

local appletManager = appletManager
local jiveMain      = jiveMain
local jive          = jive
local jnt           = jnt
local tonumber      = tonumber



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
		alsaSampleSize = 16,
                alsaPlaybackDevice = "default",
                alsaPlaybackBufferTime = 50,
                alsaPlaybackPeriodCount = 5,
	}
end


function registerApplet(meta)
        -- Check pi...
	local f = io.open(CPU_INFO)
        local pi = false
        if not f then
		-- warn?
        	return
        end

	local settings = meta:getSettings()

        for line in f:lines() do
        	if string.match(line, "Hardware%s+: BCM2708") then
        		pi = true
        	elseif string.match(line, "Revision%s+: %x+") then
			local pi = { model="error", version=0, memory=0, revision=0, maker="", ov=false }
			local nrev = string.match(line, "Revision%s+: (%x+)")
			log:debug("Raw Revision: ", nrev)
			nrev = tonumber(nrev,16)
			if (not settings['Revision'] and nrev ) or (nrev and settings['Revision'] and settings['Revision'] != nrev) then
				settings['Revision']=nrev
				-- olde style overvolting - that will add in  1000000
				if ( nrev > 1000000 ) then
					pi.ov = true
					nrev = nrev - 1000000
                  		end
                  		pi.revision=nrev

				if rev == 0 or nrev == 1 or nrev > 0x11 then
					log:error("Error Determining model of Pi")
					pi.model="error"
					pi = false
				elseif nrev == 0x02 then
					pi.model = "B"
					pi.version = 1
					pi.memory = 256
					pi.maker = "Egoman"
				elseif nrev == 0x03 then
					pi.model = "B"
					pi.version = 1.1
					pi.memory = 256
					pi.maker = "Egomanx"
				elseif nrev == 0x04 then
					pi.model = "B"
					pi.version = 2
					pi.memory = 256
					pi.maker = "Sony"
				elseif nrev == 0x05 then
					pi.model = "B"
					pi.version = 1.1
					pi.memory = 256
					pi.maker = "Qisda"
				elseif nrev == 0x06 then
					pi.model = "B"
					pi.version = 2
					pi.memory = 256
					pi.maker = "Egoman"
				elseif nrev == 0x07 then
					pi.model = "A"
					pi.version = 2
					pi.memory = 256
					pi.maker = "Egoman"
				elseif nrev == 0x08 then
					pi.model = "A"
					pi.version = 2
					pi.memory = 256
					pi.maker = "Sony"
				elseif nrev == 0x09 then
					pi.model = "A"
					pi.version = 2
					pi.memory = 256
					pi.maker = "Qisda"
				elseif nrev == 0x0d then
					pi.model = "B"
					pi.version = 2
					pi.memory = 512
					pi.maker = "Egoman"
				elseif nrev == 0x0e then
					pi.model = "B"
					pi.version = 2
					pi.memory = 512
					pi.maker = "Sony"
				elseif nrev == 0x0f then
					pi.model = "B"
					pi.version = 2
					pi.memory = 512
					pi.maker = "Qisda"
				elseif nrev == 0x10 then
					pi.model = "C"
					pi.version = 1.2
					pi.memory = 512
					pi.maker = "Sony"
				elseif nrev == 0x11 then
					pi.model = "B+"
					pi.version = 1.2
					pi.memory = 512
					pi.maker = "Sony"
				end
				settings['pi'] = pi
				-- save...
				-- reset? settings.
			end
		end
        end
        f:close()

        if not pi then
           return
        end
        log:info("Revision: ", string.format("%04x",settings['Revision']))
        log:info("Pi: ", debug.view(settings['pi']))

        -- sound... for pass through...
	f = io.open("/usr/share/alsa/cards/bcm2835.conf")
	if not f then
		local pcms,err = io.popen("cp ../share/jive/applets/SqueezePi/bcm2835.conf /usr/share/alsa/cards/bcm2835.conf", "r")
		if err then
			log:error("Copy of sound card config failed ",err,".")
		end
	else
		f:close()
	end

	-- FIXME fb.modes?

	-- appletManager:inhibitApplet("DesktopJive")

	-- Set player device type 
	LocalPlayer:setDeviceType("squeezeplay", "SqueezePi")

	-- Set the minimum support server version the version has to be greater than this ie 7.7+
	SlimServer:setMinimumVersion("7.6")

        -- is a resident Applet
        --appletManager:loadApplet("SqeezePi")

	-- audio playback defaults
	appletManager:addDefaultSetting("Playback", "enableAudio", 1)
	appletManager:addDefaultSetting("ScreenSavers", "whenStopped", "false:false")
	--appletManager:addDefaultSetting("ScreenSavers", "whenOff", "Clock:openDetailedClockBlack")

	if jiveMain:getDefaultSkin() == 'QVGAportraitSkin' then -- Lowest common denominator
		jiveMain:setDefaultSkin("800x600Skin") -- FIXME Resolution Detection Applet....
	end

	-- settings
	jiveMain:addItem(meta:menuItem('piaudio_selector', 'settingsAudio', "AUDIO_SELECT", function(applet, ...) applet:settingsAudioSelect(...) end))


        -- sp default 8MB -- FIXME make tunebale this is per slimserver... FIXME...
	if (settings['pi']['memory'] > 256) then
                -- FIXME alter default setting needs applet 
		ArtworkCache.setDefaultLimit(32*1024*1024)
		--appletManager:addDefaultSetting("ArtworkCache", "enableSetting", 1)
		--appletManager:addDefaultSetting("ArtworkCache", "defaultSize", 32*1024*1024)
	else
		ArtworkCache.setDefaultLimit(12*1024*1024)
		--appletManager:addDefaultSetting("ArtworkCache", "enableSetting", 1)
		--appletManager:addDefaultSetting("ArtworkCache", "defaultSize", 12*1024*1024)
	end

	-- services
	meta:registerService("setBrightness",true)
        --meta:registerService("getWakeupAlarm")
        --meta:registerService("setWakeupAlarm")
        --meta:registerService("getDefaultWallpaper")
        meta:registerService("poweroff")
        meta:registerService("reboot")

	-- open audio device
	Decode:open(settings)
end

--[[
function configureApplet(meta)
        local applet = appletManager:getAppletInstance("SqueezePI")

        applet:_configureInit()
end
--]]

