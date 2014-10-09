--[[

Enhanced Digital Output Meta - support of usb audio and extended digital output capabilties via addon kernel

(c) 2012, Adrian Smith, triode1@btinternet.com

--]]

local oo            = require("loop.simple")
local os            = require("os")
local io            = require("io")
local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")
local Decode        = require("squeezeplay.decode")
local Timer         = require("jive.ui.Timer")
local Popup         = require("jive.ui.Popup")
local Label         = require("jive.ui.Label")
local Icon          = require("jive.ui.Icon")
local Window           = require("jive.ui.Window")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Checkbox         = require("jive.ui.Checkbox")


local appletManager = appletManager

local jiveMain, jnt, string, tonumber, tostring = jiveMain, jnt, string, tonumber, tostring

--local debug = require("jive.utils.debug")

module(...)
oo.class(_M, AppletMeta)

local FLAG_NOMMAP	 = 0x10


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(self)
        --FIXME get current defaults...
	return {
		playbackDevice = "default",
		effectsDevice = "default",
		bufferTime = 20000,
		periodCount = 2,
                sampleSize = 0,
		firstUse = true,
                nommap = false,
                active = false,
	}
end


function registerApplet(meta)
	local settings = meta:getSettings()
	local system = System:getMachine()
	
        local ja = io.open("jive_alsa","r") -- cwd should be bin dir for jive alsa to exec anyway... using as test for alsa support... --FIXME OS linux check..
        if not ja or system == 'baby' or system == 'jive' or system =='fab4' then
           return
        else
           ja:close()
        end


        if not settings.active then
            jiveMain:addItem(
               meta:menuItem('appletDigitalOutputOptions', 'advancedSettings', meta:string("APPLET_NAME"), 
                  function(self, menuItem)
                     local window = Window("text_list", menuItem.text)
                     local menu = SimpleMenu("menu")
                     window:addWidget(menu)

                     menu:addItem({
                        text = self:string("ACTIVE"),
                        style = 'item_choice',
                        check = Checkbox("checkbox",
                           function(object, isSelected)
                                  self:getSettings()["active"] = isSelected
                                  self:storeSettings()
                                  self:_restart()
                           end,
                           self:getSettings()["active"]
                        ),
                     })

                     self:tieAndShowWindow(window)
                  end
               )
            )
            return
        end

	-- check output device is available else bring up popup and restart if output attaches
	local playbackDeviceFound = true

	if settings.playbackDevice != "default" then
		local card = settings.playbackHW and settings.playbackHW or settings.playbackDevice
		log:debug("Find playback device card=",card," playbackDevice=",settings.playbackDevice," playbackHW=",settings.playbackHW)
		

		-- FIXME pssc card none or virtual
		local fh = io.open("/proc/asound/" .. card)

		if fh == nil then
			log:warn("playback device not found - waiting")
			playbackDeviceFound = false
			local timer, rebootTime

			-- stop animated wait for dac to be connected
			local popup = Popup("waiting_popup")
			local label = Label("text", tostring(meta:string("DAC_NOT_CONNECTED")) .. "\n" .. card)
			popup:addWidget(Icon("icon_connecting"))
			popup:addWidget(label)
			popup:show()

			-- restart if dac attached, clear timer if popup dismissed
			local check = function()
				if popup:isVisible() then
					fh = io.open("/proc/asound/" .. card)
					if fh ~= nil and not rebootTime then
						log:info("playback device attached - restarting")
						label:setValue(meta:string("REBOOTING"))
						fh:close()
						rebootTime = 3
					end
					if rebootTime then
						rebootTime = rebootTime - 1
						if rebootTime == 0 then
							log:info("rebooting")
							appletManager:callService("reboot")
						end
					end
					
				else
					timer:stop()
				end
			end

			timer = Timer(1000, function() check() end, false)
			timer:start()
		end

	end

	if playbackDeviceFound then

		-- init the decoder with our settings - we are loaded earlier than SqueezeboxFab4, decode:open ignores reopen
		local playbackDevice = "default"
		if settings.playbackDevice != "default" then
		
			if settings.playbackType == "asound-card" then
				playbackDevice = "hw:CARD=" .. settings.playbackHW
			elseif settings.playbackType == "asound-plughw" then
				playbackDevice = "plughw:CARD=" .. settings.playbackHW
			else
				playbackDevice = settings.playbackDevice ..":".. settings.playbackHW
			end
		end
		log:info("playbackDevice: ", playbackDevice, " bufferTime: ", settings.bufferTime, " periodCount: ", settings.periodCount)
		
		local effectsDevice = "default"
		if settings.effectsDevice and settings.effectsDevice != "default" then
			if settings.effectsType == "asound-card" then
				effectsDevice = "hw:CARD="  .. settings.effectsHW
			elseif settings.playbackType == "asound-plughw" then
				effectsDevice = "plughw:CARD=" .. settings.effectsHW
			else
				effectsDevice = settings.effectsDevice ..":CARD=".. settings.effectsHW
			end
		end
		log:info("effectsDevice: ", effectsDevice )

		--FIXME test for patched/updated version... jive_alsa updated so... sample size can be fiddled with
		Decode:open({
			alsaPlaybackDevice = playbackDevice,
			alsaSampleSize = settings.sampleSize and settings.sampleSize or 0, -- system == 'fab4' and 24 or 16, -- auto detected on patched versions, will honor setting now 0 for auto.
			alsaPlaybackBufferTime = settings.bufferTime,
			alsaPlaybackPeriodCount = settings.periodCount,
			alsaEffectsDevice = effectsDevice,
                        alsaFlags = settings.nommap and FLAG_NOMMAP or nil
		})
		
	end

	-- register menus
	jiveMain:addItem(
		meta:menuItem('appletDigitalOutputDevices', 'settingsAudio', meta:string("APPLET_NAME"), 
			function(applet, menuItem) applet:deviceMenu(menuItem,false,"playback" ) end
		)
	)
	jiveMain:addItem(
		meta:menuItem('appletDigitalOutputOptions', 'advancedSettings', meta:string("APPLET_NAME"), 
			function(applet, menuItem) applet:optionsMenu(menuItem) end
		)
	)

	-- first use dialog
	if not updating and settings.firstUse then
		settings.firstUse = false
		meta:storeSettings()
		local applet = appletManager:loadApplet('DigitalOutput')
		applet:deviceMenu(nil, true, "playback")
	end

end




