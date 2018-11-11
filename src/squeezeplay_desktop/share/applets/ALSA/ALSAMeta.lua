--[[

ALSA - Support of ALSA and extended output capabilties

Based on EDO by (c) 2012, Adrian Smith, triode1@btinternet.com
(c) 2014, Phillip Camp,

--]]

local oo            = require("loop.simple")
local os            = require("os")
local io            = require("io")
local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")
local Decode        = require("squeezeplay.decode")
local Timer         = require("jive.ui.Timer")
local Popup         = require("jive.ui.Popup")
local Textarea       = require("jive.ui.Textarea")
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
           ja:close()
           return
        end
        ja:close()


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
				  appletManager:callService("restart")
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

	if settings.playbackDevice and settings.playbackDevice != "default" then
		local card = settings.playbackDevice
		
		local pcm,hw  = string.match(card, "^([%w]+):([%w=]+)")
		if hw then
			local cd = string.match(hw,"CARD=([%w]+)")
			hw = cd and cd or hw
			card = hw
			log:debug("Munged card ",card)
		end
		log:debug("Find playback device card=",card," playbackDevice=",settings.playbackDevice)
		local fh = io.open("/proc/asound/" .. card)

		if not fh then
			log:warn("playback device not found")
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
				playbackDevice = "hw:CARD=" .. settings.playbackDevice
			elseif settings.playbackType == "asound-plughw" then
				playbackDevice = "plughw:CARD=" .. settings.playbackDevice
			else
				playbackDevice = settings.playbackDevice
			end
		end
		log:info("playbackDevice: ", playbackDevice, " bufferTime: ", settings.bufferTime, " periodCount: ", settings.periodCount)
		
		local effectsDevice = "default"
		if settings.effectsDevice and settings.effectsDevice != "default" then
			if settings.effectsType == "asound-card" then
				effectsDevice = "hw:CARD="  .. settings.effectsDevice
			elseif settings.playbackType == "asound-plughw" then
				effectsDevice = "plughw:CARD=" .. settings.effectsdevice
			else
				effectsDevice = settings.effectsDevice
			end
		end
		log:info("effectsDevice: ", effectsDevice )

		-- jive_alsa updated so... sample size can be fiddled with
		local ok , err = Decode:open({
			alsaPlaybackDevice = playbackDevice,
			alsaSampleSize = settings.sampleSize and settings.sampleSize or 0, -- system == 'fab4' and 24 or 16, -- auto detected on patched versions, will honor setting now 0 for auto.
			alsaPlaybackBufferTime = settings.bufferTime,
			alsaPlaybackPeriodCount = settings.periodCount,
			alsaEffectsDevice = effectsDevice,
                        alsaFlags = settings.nommap and FLAG_NOMMAP or nil,
		})
		--if not ok then JiveMain:registerPostOnScreenInit(function Popup(meta:string(err), meta:string("ERROR_DOPEN")):show() end) end
		if not ok then
			local p = Popup("toast_popup", meta:string("ERROR_TITLE"))
			local es = tostring(meta:string(err)).. " playbackDevice: " .. playbackDevice .. ( (" effectsDevice: ".. effectsDevice) or "")
			log:warn(es)
			p:addWidget(Textarea("toast_popup_textarea",  es))
			p:focusWidget(nil)
			p:show()
		end
	end

	-- register menus
	jiveMain:addItem(
		meta:menuItem('appletALSADevices', 'settingsAudio', meta:string("AUDIO_DEVICE"), 
			function(applet, menuItem) applet:deviceMenu(menuItem,false,"playback" ) end
		)
	)

	jiveMain:addItem(
		meta:menuItem('appletALSAOptions', 'advancedSettings', meta:string("APPLET_NAME"), 
			function(applet, menuItem) applet:optionsMenu(menuItem) end
		)
	)

	-- first use dialog
	if settings.firstUse then
		settings.firstUse = false
		meta:storeSettings()
		local applet = appletManager:loadApplet('ALSA')
		applet:deviceMenu(nil, true, "playback")
	end

end

