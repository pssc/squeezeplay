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

local JIVE_VERSION   = jive.JIVE_VERSION


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
		-- Linux Applet control
		backlight = true,
		blanking = true,
	}
end


function upgradeSettings(self, settings)
	settings['rt'] = nil
	settings['Revision'] = nil
	return settings
end


function settingsMeta(meta)
	return {
		fbcp_control = { limit="toggle"},
		fbcp_backlight = { limit="toggle"},
		fbcp_toggle = { limit="toggle"},
		cec_toggle = { limit="toggle"},
		time_sync_toggle = { limit="toggle"},
		display_power = { limit="toggle"},
		nosplash_sound = { limit="toggle"},

		backlight = { limit="toggle"},
		blanking = { limit="toggle"},
	}
end

function _piHW(self)
	local f = io.open(CPU_INFO)
	if not f then return end
	local pi = { model="unkown", memory=256, maker="",}

	-- possible Pi try identify HW then rev,
	-- unkown models will get a basic service
        for line in f:lines() do
        	if string.match(line, "Hardware%s+: BCM2708") then
			pi.hw = "BCM2708"
		elseif string.match(line, "Hardware%s+: BCM2709") then
			pi.hw = "BCM2709"
		elseif pi.hw and string.match(line, "Serial%s+: (%x+)") then
			pi.serial = string.match(line, "Serial%s+: (%x+)")
		elseif pi.hw and string.match(line, "Revision%s+: %x+") then
			local nrev = string.match(line, "Revision%s+: (%x+)")
			log:debug("Raw Revision: ", nrev)
			pi.revision = tonumber(nrev,16)
		end
	end
        f:close()
	return (pi.hw and pi.serial and pi.revision) and pi or nil
end


function _piResolv(self,pi)
	local nrev = pi.revision
	-- FIXME Detect new scheme
	log:debug("Detecting Pi with Revision: ", nrev)
	-- olde style overvolting - that will add in 1000000
	if ( nrev > 1000000 and pi.hw == "BCM2708" and nrev < 0x900091 ) then
		pi.ov = true
		nrev = nrev - 1000000
	end

	if pi.hw == "BCM2708" and
	   (rev == 0 or nrev == 1 or nrev == 0x13 or
	   (nrev > 0x14 and nrev < 0x900091)) then
		log:warn("Error Determining model of impossible Pi ")
		pi.model="error"
	elseif pi.hw == "BCM2709" then
		pi.model = "2 B"
		pi.memory = 1024
		pi.version = 1.1
		pi.maker = "Sony"
		if nrev == 0xa02082 then
			pi.model = "3 B"
			pi.version = 1.2
		end
	elseif nrev == 0x900092 then
		pi.model = "Zero"
		pi.version = 2
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
	elseif nrev == 0x14 then -- Unsure
		pi.model = "CM"
		pi.version = 1.1
		pi.memory = 512
		pi.maker = "Sony"
	else
		log:warn("Unkown pi ",pi.hw," r",pi.revsion)
	end
	return pi
end

function registerApplet(meta)
        -- Check pi...
	local pi = meta:_piHW()
        if not pi then
	   log:debug("No Pi hardware")
           return
        end
	local store
	local settings = meta:getSettings()

	if not settings.pi or
	   settings.pi.revision ~= pi.revision or
	   settings.pi.serial ~= pi.serial or
	   settings.pi.hw ~= pi.hw or
	   settings.model == "error" or
	   settings.model == "unkown" then
		settings['pi'] = meta:_piResolv(pi)
		--store = true
	end

        log:info("Version: ", JIVE_VERSION)
        log:info("Pi: ", debug.view(settings['pi']))
        log:debug("Settings: ", debug.view(settings))

        -- sound... for pass through...
	f = io.open("/usr/share/alsa/cards/bcm2835.conf")
	if not f then
		-- FIXME no ecode on copy fail
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
	-- System:getMacAddress()
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
                --["deviceRotation"] = 1,
                --["sshTunnel"] = 1,
                ["coreKeys"] = 1,
                ["presetKeys"] = 1,
                ["SMBus"] = 1,
                ["Capabilities"] = 1,
	})
	local store = false

	-- FIXME
	--if not settings.uuid and pi.serial then
	if pi.serial and pi.revision and not settings.uuid then
		--7.8.0-r8064979
		local mj,mr,po,co = string.match(JIVE_VERSION,"(%d+)\.(%d+)\.(%d+) r(%x+)")
		local uuid = string.format("%16s",pi.serial) ..
		string.format("%06x",pi.revision) ..
		string.format("%01x",mj) ..
		string.format("%01x",mr) ..
		string.format("%01x",po) ..
		string.format("%06x",tonumber(co,16))
		log:info("uuid: ",uuid)
		settings.uuid = uuid
		store = true
	end
	-- Linux base Applet? Fall back
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
	--Fallback
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
		log:info("Store Settings")
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

	-- audio playback defaults -- FIXME check decode open? option?
	appletManager:addDefaultSetting("Playback", "enableAudio", 1)

	-- Screen savers
	appletManager:addDefaultSetting("ScreenSavers", "whenPlaying", "NowPlaying:openScreensaver")
	appletManager:addDefaultSetting("ScreenSavers", "whenStopped", "Clock:openDetailedClockTransparent")
	appletManager:addDefaultSetting("ScreenSavers", "whenOff", "BlankScreen:openScreensaver")
	appletManager:addDefaultSetting("ScreenSavers", "poweron_window_time", 12000)
	-- settings = {whenPlaying="NowPlaying:openScreensaver",timeout=30000,poweron_window_time=10000,whenStopped="Clock:openDetailedClockTransparent",whenOff="Clock:openDetailedClockBlack",}

	appletManager:addDefaultSetting("SelectSkin","touch","800x480Skin")
	appletManager:addDefaultSetting("SelectSkin","remote","HDSkin-800x480")
	appletManager:addDefaultSetting("SelectSkin","skin","800x480Skin")

        --meta:registerService("getDefaultWallpaper") FIXME inconsistent for some skins...
	-- getDefaultWallpaper service is only for baby it should be fixed/removed in baby and SetUP wallpaper...
	-- setWallpaper?
	appletManager:addDefaultSetting("SetupWallpaper", "unfiltered", true)
	appletManager:addDefaultSetting("SetupWallpaper", "800x480Skin", "800x480_encore.png")
	appletManager:addDefaultSetting("SetupWallpaper", "HDSkin-800x480", "800x480_nocturne.png")

	appletManager:addDefaultSetting("ImageViewer", "imageLimit", 0)

	-- Detect Pi LCD and default to Local TS skin for input
	if os.getenv("RPI_LCD") then
		appletManager:addDefaultSetting("InputMapper", "default_mapping", 1)
	end

	if jiveMain:getDefaultSkin() == 'QVGAportraitSkin' then -- Lowest common denominator
		jiveMain:setDefaultSkin("800x480Skin") -- FIXME Resolution Detection Applet.... ... 800x600 as next vga based skin...
	end
	-- FIXME

	--  Work round differnces in models --FIXME pi3?
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

	-- AppletUI
	meta:registerService("registerEnv")
	meta:registerService("unregisterEnv")
	meta:registerService("getEnv")
	meta:registerService("setEnv")


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

