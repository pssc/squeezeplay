local oo            = require("loop.simple")
local io            = require("io")
local math          = require("math")
local string        = require("string")
local table         = require("jive.utils.table")
local os            = require("os")

local Decode        = require("squeezeplay.decode")
local AppletMeta    = require("jive.AppletMeta")
local LinuxMeta     = require("applets.Linux.LinuxMeta")
local LocalPlayer   = require("jive.slim.LocalPlayer")
local Framework     = require("jive.ui.Framework")
local System        = require("jive.System")
local Player        = require("jive.slim.Player")
local SlimServer    = require("jive.slim.SlimServer")
local Decode        = require("squeezeplay.decode")
local debug         = require("jive.utils.debug")
local ArtworkCache  = require("jive.slim.ArtworkCache")

local appletManager = appletManager
local jiveMain      = jiveMain
local jive          = jive
local jnt           = jnt
local tonumber      = tonumber



module(...)
-- inherit from linux
oo.class(_M, LinuxMeta)

local CPU_INFO="/proc/cpuinfo"


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return { 
--		audio_select = "AUTO" we dont hold the state alsa does...
		alsaSampleSize = 16,
                alsaPlaybackDevice = "default",
                alsaPlaybackBufferTime = 113378,
                alsaPlaybackPeriodCount = 5,
		display_power = true,
		autoaudio = true, -- FIXME
				  -- as Alsa driver doesnt support anything other than 16bit
		rt = false,
		-- Linux Applet control
		backlight = true,
		blanking = true,
	}
end


function settingsMeta(meta)
	return {
		fbcp_control = { limit="toggle"},
		fbcp_backlight = { limit="toggle"},
		fbcp_toggle = { limit="toggle"},
		cec_toggle = { limit="toggle"},
		time_sync_toggle = { limit="toggle"},
		display_power = { limit="toggle"},
		backlight = { limit="toggle"},
		blanking = { limit="toggle"},
	}
end


function registerApplet(meta)
        -- Check pi...
	local f = io.open(CPU_INFO)
        local pi,hw
        if not f then
		-- warn?
        	return
        end

	local settings = meta:getSettings()

	-- Pi try our med for unkown models for pi is an hw type then refine when we have a revsion
        for line in f:lines() do
        	if string.match(line, "Hardware%s+: BCM2708") then
			hw = "BCM2708"
		elseif string.match(line, "Hardware%s+: BCM2709") then
			hw = "BCM2709"
		elseif hw and string.match(line, "Revision%s+: %x+") then
			local nrev = string.match(line, "Revision%s+: (%x+)")
			pi = { hw=hw, model="error", version=0, memory=256, revision=0, maker="", ov=false }
			log:debug("Raw Revision: ", nrev)
			nrev = tonumber(nrev,16)
			-- FIXME Detect new scheme
			if (not settings['Revision'] and nrev ) or (nrev and settings['Revision'] and settings['Revision'] != nrev) then
				settings['Revision']=nrev
				-- olde style overvolting - that will add in  1000000
				if ( nrev > 1000000 and pi.hw == "BCM2708"  and nrev < 9000000 ) then
					pi.ov = true
					nrev = nrev - 1000000
                  		end
                  		pi.revision=nrev

				if pi.hw == "BCM2708" and (rev == 0 or nrev == 1 or nrev == 13 or (nrev > 0x14 and nrev < 0x900091)) then
					log:error("Error Determining model of Pi")
					pi = false
				elseif pi.hw == "BCM2709" then
					pi.model = "2"
					pi.memory = 1024
					pi.version = 1.1
					pi.maker = "Sony"
				elseif nrev == 0x900092 then
					pi.model = "Zero"
					pi.version = 1
					pi.memory = 512
					pi.maker = "Sony"
				elseif nrev == 0x02 then
					pi.model = "B"
					pi.version = 1
					pi.memory = 256
					pi.maker = "Egoman"
				elseif nrev == 0x03 then
					pi.model = "B"
					pi.version = 1.1
					pi.memory = 256
					pi.maker = "Egomanx, Fuses/D14 removed."
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
					pi.model = "B+"
					pi.version = 1.2
					pi.memory = 512
					pi.maker = "Sony"
				elseif nrev == 0x11 then
					pi.model = "CM"
					pi.version = 1.2
					pi.memory = 512
					pi.maker = "Sony"
				elseif nrev == 0x12 then
					pi.model = "A+"
					pi.version = 1.2
					pi.memory = 256
					pi.maker = "Sony"
				elseif nrev == 0x13 then
					pi = nil
				elseif nrev == 0x14 then -- Unsure
					pi.model = "CM"
					pi.version = 1.1
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
	   log:info("No pi")
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
	-- FIXME no X?
	-- FIXME uuid / mac and system in generic?
	appletManager:inhibitApplet("DesktopJive")

	-- Set player device type 
	LocalPlayer:setDeviceType("squeezeplay", "SqueezePi"..pi.model)

	-- DesktopJive
	-- settings.mac
	-- settings.uuid
	--System:getMacAddress()
        -- set mac address and uuid
	-- to depricate use of DesktopJive...
	-- soft reset
	-- uuid
	-- setSNHostname

        --System:init({
        --        macAddress = settings.mac,  System:getMacAddress()
        --        uuid = settings.uuid,
	--	  machine
	--	  revision
        --})
	-- System:getMacAddress()
	-- System:getArch()

	-- FIXME add caps on fly after Hw detect... needed...
        System:setCapabilities({
	        ["touch"] = 1,
                ["ir"] = 1,
                ["powerKey"] = 1,
                ["muteKey"] = 1,
                ["alarmKey"] = 1,
                ["audioByDefault"] = 1,
                ["wiredNetworking"] = 1,
                ["deviceRotation"] = 1,
                ["coreKeys"] = 1,
                ["presetKeys"] = 1,
                ["SMBus"] = 1,
                ["Capabilities"] = 1,
	})

       local store = false

	-- Linux base Applet??
        if not settings.uuid then
                store = true

                local uuid = {}
                for i = 1,16 do
                        uuid[#uuid + 1] = string.format('%02x', math.random(255))
                end

                settings.uuid = table.concat(uuid)
        end

        if not settings.mac then
                settings.mac = System:getMacAddress()
                store = true
        end

        if not settings.mac then
                -- random fallback FIXME Really?
                mac = {}
                for i = 1,6 do
                        mac[#mac + 1] = string.format('%02x', math.random(255))
                end

                store = true
                settings.mac = table.concat(mac, ":")
        end

        if store then
                log:debug("Mac Address: ", settings.mac)
                meta:storeSettings()
        end

	-- set system mac address and uuid
	System:init({
		macAddress = settings.mac,
		uuid = settings.uuid,
        })

        -- SN hosthame
        if settings.snaddress then
                jnt:setSNHostname(settings.snaddress)
        else
                jnt:setSNHostname("jive.squeezenetwork.com")
        end

	-- Set the minimum support server version the version has to be greater than this ie 7.7+
	SlimServer:setMinimumVersion("7.6")

	-- audio playback defaults -- FIXME check decode open?
	appletManager:addDefaultSetting("Playback", "enableAudio", 1)

	-- Screen savers
	appletManager:addDefaultSetting("ScreenSavers", "whenPlaying", "NowPlaying:openScreensaver")
	appletManager:addDefaultSetting("ScreenSavers", "whenStopped", "Clock:openDetailedClockTransparent")
	appletManager:addDefaultSetting("ScreenSavers", "whenOff", "BlankScreen:openScreensaver")
	appletManager:addDefaultSetting("ScreenSavers", "poweron_window_time", 12000)
	-- settings = {whenPlaying="NowPlaying:openScreensaver",timeout=30000,poweron_window_time=10000,whenStopped="Clock:openDetailedClockTransparent",whenOff="Clock:openDetailedClockBlack",}

	if jiveMain:getDefaultSkin() == 'QVGAportraitSkin' then -- Lowest common denominator
		jiveMain:setDefaultSkin("800x480Skin") -- FIXME Resolution Detection Applet.... ... 800x600 as next vga based skin...
	end
	-- FIXME
	appletManager:addDefaultSetting("SelectSkin","touch","800x480Skin")
	appletManager:addDefaultSetting("SelectSkin","remote","HDSkin-800x480")
	appletManager:addDefaultSetting("SelectSkin","skin","800x480Skin")

	-- Set if default prefs FIXME wallpaper applet?
        --meta:registerService("getDefaultWallpaper") FIXME inconsistent for some skins...
	appletManager:addDefaultSetting("SetupWallpaper", "unfiltered", true)
	appletManager:addDefaultSetting("SetupWallpaper", "800x480Skin", "800x480_encore.png")

	--  Work round differnces in models
	if (pi.model == "B" and pi.version < 2) then
		appletManager:addDefaultSetting("VCNL4010","bus",0)
	end

        -- sp default 8MB -- FIXME make tunebale this is per slimserver... FIXME...
	if pi.memory and pi.memory > 256 then
                -- FIXME alter default setting needs applet 
		ArtworkCache.setDefaultLimit(32*1024*1024)
		--appletManager:addDefaultSetting("ArtworkCache", "enableSetting", 1)
		--appletManager:addDefaultSetting("ArtworkCache", "defaultSize", 32*1024*1024)
	else
		ArtworkCache.setDefaultLimit(12*1024*1024)
	end

	-- settings
	jiveMain:addItem(meta:menuItem('piaudio_selector', 'settingsAudio', "AUDIO_SELECT", function(applet, ...) applet:settingsAudioSelect(...) end))
	jiveMain:addItem(meta:menuItem('appletSqueezePi', 'advancedSettings', "APPLET_NAME",  function(applet, ...) applet:openAdvSettings(...) end))

	-- Services
	-- no RTC ?
        --meta:registerService("getWakeupAlarm")
        --meta:registerService("setWakeupAlarm")
        meta:registerService("restart")
        meta:registerService("poweroff")
        meta:registerService("reboot")
	meta:registerService("setBrightness",true)

	local command = "tvservice -a 2>&1"
        local f,err = io.popen(command, "r")
	if not f then
	      log:warn(command,"-- could not be run ",err,".")
	end
	-- "    PCM supported: Max channels: 2, Max samplerate:  32kHz, Max samplesize 16 bits."
	-- "    PCM supported: Max channels: 8, Max samplerate: 192kHz, Max samplesize 24 bits."
	-- FIXME we need to go multi instance as effects are 16
	settings.alsaSampleSize = 16
	for v in f:lines() do
		local c,r,b = string.match(v, "%s+PCM supported: Max channels: (%d+), Max samplerate:  (%d+)kHz, Max samplesize (%d+) bits.")
		--if settings.autoaudio and settings.alsaPlaybackDevice == "default" and b then
		log:debug(v)
		if settings.autoaudio and b then
			log:info("Auto Sample Size ",b)
			--settings.alsaSampleSize = b
			--ALSA layer only accepts 16bit atm.
		end
	end
        f:close()

	--Framework:addActionListener("soft_reset", self, _softResetAction, true)
	-- open audio device
	Decode:open(settings)
end


--disconnect from player and server and re-set "clean (no server)" LocalPlayer as current player
function _softResetAction(self, event)
        LocalPlayer:disconnectServerAndPreserveLocalPlayer()
        jiveMain:goHome()
        log:debug(self,"Jive Desktop Soft Reset")
end


function configureApplet(meta)
	local settings = meta:getSettings()
	log:debug("configure ",debug.view(settings)," ",applet," ",meta)

	if settings['pi'] then
		-- is a resident applet
		appletManager:loadApplet("SqueezePi")
	end
end

