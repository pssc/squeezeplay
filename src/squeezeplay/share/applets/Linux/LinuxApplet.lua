-- Base Class for linux based devices...
local pcall, unpack, tonumber, tostring = pcall, unpack, tonumber, tostring

local oo                     = require("loop.simple")
local os                     = require("os")
local io                     = require("io")
local lfs                    = require("lfs")

local string                 = require("jive.utils.string")
local table                  = require("jive.utils.table")

local Applet                 = require("jive.Applet")
local System                 = require("jive.System")

local Player                 = require("jive.slim.Player")

local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Event                  = require("jive.ui.Event")
local Label                  = require("jive.ui.Label")
local Popup                  = require("jive.ui.Popup")
local Task                   = require("jive.ui.Task")
local Textarea               = require("jive.ui.Textarea")
local Tile                   = require("jive.ui.Tile")
local Timer                  = require("jive.ui.Timer")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Window                 = require("jive.ui.Window")

local debug                  = require("jive.utils.debug")
local log                    = require("jive.utils.log").logger("applet.Linux")

local jnt                    = jnt
local jiveMain               = jiveMain
local appletManager          = appletManager


module(..., Framework.constants)
oo.class(_M, Applet)

local skipbacklight = {}
local skipblanking = {}

function sysOpen(self, path, attr, mode)
	if not mode or string.match(mode, "r") then
		local fh = io.open(path .. attr, "r")
		if not fh then
			log:warn("Can't open (read) ", path, attr)
			return nil
		end

		self["sysr_" .. attr] = fh
	end

	if mode and string.match(mode, "w") then
		local fh = io.open(path .. attr, "w")
		if not fh then
			log:warn("Can't open (write) ", path, attr)
			return nil
		end

		self["sysw_" .. attr] = fh
	end
	return fh
end


function sysReadNumber(self, attr)
         return sysReadString(self, attr,true)
end

function sysReadString(self, attr, num)
	local fh = self["sysr_" .. attr]
	if not fh then
		return nil
	end

	fh:seek("set")

	local line, err = fh:read("*a")
	if err then
		return nil
	else
		return num and tonumber(line) or line
	end
end

function sysWrite(self, attr, val)
	local fh = self["sysw_" .. attr]
	if not fh then
		return -1
	end

	fh:write(val)
	fh:flush(val)
end

function parseCpuInfo(self,keytable)
	local f = io.open("/proc/cpuinfo")
	if f then
		for line in f:lines() do
			for k in pairs(keytable) do
			    if string.match(line, k) then
				key[k] = string.match(line, k.."%s+:%s+(.+)")
			    end
			end
		end
		f:close()
	end
	return keys
end

local function _errorWindow(self, title)
	local window = Window("help_info", title)
	window:setSkin({
		help_info = {
			bgImg = Tile:fillColor(0x000000ff),
		},
	})

	window:setAllowScreensaver(false)
	window:setAlwaysOnTop(true)
	window:setAutoHide(false)
	window:setShowFrameworkWidgets(false)

	return window
end


function verifyMacUUID(self)
	mac = System:getMacAddress()
	uuid = System:getUUID()

	if not uuid or string.match(mac, "^00:40:20")
		or uuid == "00000000-0000-0000-0000-000000000000"
		or mac == "00:04:20:ff:ff:01" then

		local window = _errorWindow(self, self:string("INVALID_MAC_TITLE"))

		local text = Textarea("help_text", self:string("INVALID_MAC_TEXT"))
		local menu = SimpleMenu("menu", {
			{
				text = self:string("INVALID_MAC_CONTINUE"),
				sound = "WINDOWHIDE",
				callback = function()
						   window:hide()
					   end
			},
		})

		menu:setHeaderWidget(text)
		window:addWidget(menu)

		window:show()
	end
end


-- linux spefic?
function betaHardware(self, euthanize)
	log:info("beta hardware")

	local window = _errorWindow(self, self:string("BETA_HARDWARE_TITLE"))
	window:ignoreAllInputExcept({})

	if euthanize then
		window:addWidget(Textarea("help_text", self:string("BETA_HARDWARE_EUTHANIZE", self._revision)))
	else
		window:addWidget(Textarea("help_text", self:string("BETA_HARDWARE_TEXT", self._revision)))
	end

	jiveMain:registerPostOnScreenInit(function()
		window:show(Window.transitionNone)

		if not euthanize then
			local timer = Timer(8000, function()
				window:hide(Window.transitionNone)
			end, true):start()
		end
	end)
end

-- really inlunx specfic?
-- genertic wrapper?
-- clean shutdown?
function playSplashSound(self)
	local settings = self:getSettings()

	self._wasLastShutdownUnclean = not settings.cleanReboot
	
	if settings.cleanReboot == false then
		-- unclean reboot, not splash sound
		log:info("unclean reboot")
		return
	end

	settings.cleanReboot = false --FIXME really init?
	self:storeSettings()

	-- The startup sound needs to be played with the minimum
	-- delay, load and play it first
	appletManager:callService("loadSounds", "STARTUP")
	Framework:playSound("STARTUP")
end


function _cleanReboot(self)
	local settings = self:getSettings()

	settings.cleanReboot = true
	self:storeSettings()
end


--service method
function wasLastShutdownUnclean(self)
	return self._wasLastShutdownUnclean
end


-- power off
-- genertic wrapper?
function poweroff(self, now)
	log:info("Shuting down now=", now)

	-- disconnect from SqueezeCenter
	appletManager:callService("disconnectPlayer")

	_cleanReboot(self)

	if now then
		log:warn("force poweroff (don't go through init)")
		local sysreq = io.open("/proc/sysrq-trigger","w")
		sysreq:write("s")
		sysreq:write("o")
		sysreq:write("r")
		-- Fall trough just in case
	end

	local popup = Popup("waiting_popup")

	popup:addWidget(Icon("icon_restart"))
	popup:addWidget(Label("text", self:string("GOODBYE")))

	-- make sure this popup remains on screen
	popup:setAllowScreensaver(false)
	popup:setAlwaysOnTop(true)
	popup:setAutoHide(false)
	popup:ignoreAllInputExcept({})

	popup:show()

	popup:playSound("SHUTDOWN")

	log:info("poweroff ...")
	self._poweroffTimer = Timer(4000, function()
		log:info("... now")
		self:powerOff()
	end)
	self._poweroffTimer:start()
end

function powerOff(self)
        local command = "poweroff 2>&1"
        local f,err = io.popen(command, "r")
        if not f then
                log:warn(command,"-- could not be run ",err,".")
	end
	-- Framework:quit()?
end

-- low battery
function lowBattery(self)
	if self.lowBatteryWindow then
		return
	end

	local player = Player:getLocalPlayer()
	if player then
		player:pause(true)
	end

	log:info("battery low")

	local popup = Popup("waiting_popup")

	popup:addWidget(Icon("icon_battery_low"))
	popup:addWidget(Label("text", self:string("BATTERY_LOW")))
	popup:addWidget(Label("subtext", self:string("BATTERY_LOW_2")))

	-- make sure this popup remains on screen
	popup:setAllowScreensaver(false)
	popup:setAlwaysOnTop(true)
	popup:setAutoHide(false)
	popup:ignoreAllInputExcept({})

	popup:show()

	-- FIXME jive made sure the brightness was on (do we really
	-- want this, I don't think so as it may wake people up)

	self.lowBatteryTimer = Timer(1200000, function()
		-- force poweroff (don't go through init)
		squeezeos.poweroff()
	end)
	self.lowBatteryTimer:start()

	self.lowBatteryWindow = popup
end


-- low battery cancel
-- battry in seperate applet?
function lowBatteryCancel(self)
	if not self.lowBatteryWindow then
		return
	end

	log:info("battery low cancelled")

	self.lowBatteryTimer:stop()
	self.lowBatteryWindow:hide()

	self.lowBatteryTimer = nil
	self.lowBatteryWindow = nil
end

-- action soft_reset?
function restart(self)
	log:info("restart")
	_cleanReboot(self) --FIXME hmmm

        self.popup = Popup("update_popup")
        self.popup:addWidget(Icon("icon_restart"))
        self.popup:addWidget(Label("text", self:string("RESTARTING")))
        self:tieAndShowWindow(self.popup)

        self.timer = Timer(3000,
                                           function()
						   Framework:quit()
                                                   log:info("quit...")
                                           end,
                                           true)
        self.timer:start()
	-- Reexec?
end

-- reboot
function reboot(self,now)
	log:info("reboot now=", now)
	_cleanReboot(self) --FIXME hmmm

        self.popup = Popup("update_popup")
        self.popup:addWidget(Icon("icon_restart"))
        self.popup:addWidget(Label("text", self:string("REBOOTING")))
        self:tieAndShowWindow(self.popup)

        self.timer = Timer(3000,
                                           function()
						   Framework:quit()
                                                   log:info("rebooting...")
                                           end,
                                           true)
        self.timer:start()

	if now then
		log:warn("force reboot (don't go through init)")
		local sysreq = io.open("/proc/sysrq-trigger","w")
		sysreq:write("s")
		sysreq:write("b")
		-- fall through
	end
        local command = "reboot 2>&1"
        local f,err = io.popen(command, "r")
        if not f then
                log:warn(command,"-- could not be run ",err,".")
	end
end

-- framebuffer blanking... and backlight
-- Screen on/off support for standard fbdevices or at lease as close as we can get
function setBrightness(self,level)
        if level == "off" then
                level = 0
        elseif level == "on" then
                level = 1
        elseif level == nil then
                return
        else
		log:debug("setBrightness: ",level," to ", 1)
                level = 1
        end

	-- Blanking is the inverse of level
	local val = level == 0 and 1 or 0
	if self:getSettings()["blanking"] then
		dirNodeSetValue("/sys/class/graphics","blank",val,skipblanking)
	end
	-- /sys/class/backlight/soc\:backlight/bl_power
	-- Control BACKLIGHT power, values are FB_BLANK_* from fb.h
	-- FB_BLANK_UNBLANK (0)   : power on
	-- FB_BLANK_POWERDOWN (4) : power off
	val = level == 0 and 4 or 0
	if self:getSettings()["backlight"] then
		dirNodeSetValue("/sys/class/backlight","bl_power",val,skipbacklight)
	end
end

function dirNodeSetValue(dir,node,val,skip)
	for entry in lfs.dir(dir) do repeat
		local entrydir = dir.."/"..entry

		if skip and skip[entry] then
			break
		end
                local entrymode = lfs.attributes(entrydir, "mode")
		log:debug("dirNodeSetValue: ",entrydir," is ", entrymode)
                if entry:match("^%.") or (entrymode ~= "directory") then
			break
                end

		local fblank = entrydir.."/"..node
                local mode = lfs.attributes(fblank,"mode")
		log:debug("dirNodeSetValue: ",fblank," mode is ", mode)
                if mode == "file" then
			local fh = io.open(fblank,"w")
			if fh then
				log:info("dirNodeSetValue: ",fblank," to ",val)
				fh:write(val)
				fh:flush()
				fh:close()
			end
                end
		break -- oddness as we are in a double loop
	until true end
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.
Copyright 2014,2015 Phillip Camp. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
