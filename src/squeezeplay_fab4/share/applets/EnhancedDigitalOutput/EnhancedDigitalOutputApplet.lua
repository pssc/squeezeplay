--[[

Enhanced Digital Output Applet - support of usb audio and extended digital output capabilties via addon kernel

(c) 2012, Adrian Smith, triode1@btinternet.com

--]]

local oo               = require("loop.simple")
local io               = require("io")
local os               = require("os")
local Applet           = require("jive.Applet")
local System           = require("jive.System")
local Framework        = require("jive.ui.Framework")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Textarea         = require("jive.ui.Textarea")
local Label            = require("jive.ui.Label")
local Popup            = require("jive.ui.Popup")
local Checkbox         = require("jive.ui.Checkbox")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Slider           = require("jive.ui.Slider")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Timer            = require("jive.ui.Timer")
local Icon             = require("jive.ui.Icon")
local Window           = require("jive.ui.Window")
local debug            = require("jive.utils.debug")

local JIVE_VERSION     = jive.JIVE_VERSION
local appletManager    = appletManager

local STOP_SERVER_TIMEOUT = 10

local string, ipairs, tonumber, tostring, require, type = string, ipairs, tonumber, tostring, require, type

module(..., Framework.constants)
oo.class(_M, Applet)


function deviceMenu(self, menuItem, firstUse)
	local window = Window("text_list", self:string("SELECT_OUTPUT"))
	local menu = SimpleMenu("menu")
	local system = System:getMachine()
	window:addWidget(menu)

	-- refreshing menu to detect hotplugging of usb dacs
	local timer

	local updateMenu = function()
		local info = self:_parseCards()
		local curr = self:getSettings()["playbackDevice"]
		
		local items = {}

		if curr == "default" then
			if not firstUse then
				items[#items+1] = {
					text = tostring(system == "fab4" and self:string("ANALOG_DIGITAL") or self:string("DEFAULT")) .. tostring(self:string("CURRENT")) ,
				}
			end
		else
	items[#items+1] = {
				-- FIXME pssc right for non fab4?
				text = system == "fab4" and self:string("ANALOG_DIGITAL") or self:string("DEFAULT"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
							   timer:stop()
							   self:_setCardAndReboot({ id = "default" }, false)
						   end,
			}
		end
		
		for num, card in ipairs(info) do
			if curr != card.id then
				items[#items+1] = {
					text = card.desc,
					sound = "WINDOWSHOW",
					callback = function(event, menuItem)
								   timer:stop()
								   -- FIXME plughw support...
								   if card.needshub then
									   -- this is a usb1 async dac without a hub - ask whether to use embeddedTTHack
									   local window = Window("text_list", menuItem.text)
									   local menu = SimpleMenu("menu")
									   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_USB1_DAC")))
									   menu:addItem({
											text = self:string("USB1_DAC_NO_HUB"),
											style = 'item_choice',
											callback = function(event, menuItem)
														   self:_setCardAndReboot(card, true)
													   end,
									   })
									   menu:addItem({
											text = self:string("USB1_DAC_HUB"),
											style = 'item_choice',
											callback = function(event, menuItem)
														   self:_setCardAndReboot(card, false)
													   end,
									   })
									   window:addWidget(menu)
									   window:show()
								   else
									   self:_setCardAndReboot(card, false)
								   end
							   end,
				}
			elseif (card.id == "TXRX") or (card.type == "asound-virtual") then
				items[#items+1] = {
					text = card.desc .. tostring(self:string("CURRENT")),
				}
			else
				items[#items+1] = {
					text = card.desc .. tostring(self:string("INFO")),
					sound = "WINDOWSHOW",
					callback = function(event, menuItem)
								   timer:stop()
								   self:_showStats(card.hw, card.desc)
							   end,
				}
			end
		end

		if firstUse then
			menu:setHeaderWidget(Textarea("help_text", self:string("HELP_FIRST_USE")))
		end

		menu:setItems(items, #items)
	end

	-- update on a timer
	timer = Timer(1000, function() updateMenu() end, false)
	timer:start()

	-- initial display
	updateMenu()

	-- cancel timer when window is hidden (e.g. screensaver)
	window:addListener(EVENT_WINDOW_ACTIVE | EVENT_HIDE,
		function(event)
			local type = event:getType()
			if type == EVENT_WINDOW_ACTIVE then
				timer:restart()
			else
				timer:stop()
			end
			return EVENT_UNUSED
		end,
		true
	)

	self:tieAndShowWindow(window)
	return window
end


function optionsMenu(self, menuItem)
	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	menu:addItem({
		text = self:string("SELECT_OUTPUT"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
					   self:deviceMenu(menuItem, false)
				   end
	})

	if (System:getMachine() == "fab4") then
		menu:addItem({
			text = self:string("KERNEL_UPDATE"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
					   local window = Window("text_list", menuItem.text)
					   local menu = SimpleMenu("menu")
					   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_KERNEL_UPDATE")))
					   menu:addItem({
							text = self:string("KERNEL_UPDATE_AUTO"),
							style = 'item_choice',
							check = Checkbox("checkbox",
								  function(object, isSelected)
									  self:getSettings()["autoKernelUpdate"] = isSelected
									  self:storeSettings()
								  end,
								  self:getSettings()["autoKernelUpdate"]
							),
					   })
					   menu:addItem({
							text = self:string("KERNEL_UPDATE_NOW"),
							style = 'item_choice',
							callback = function(event, menuItem)
										   self:_kernelUpdate()
									   end,
					   })
					   window:addWidget(menu)
					   window:show()
				   end,
		})

		menu:addItem({
			text = self:string("NO_HUB_OPTION"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
					   local window = Window("text_list", menuItem.text)
					   local menu = SimpleMenu("menu")
					   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_NO_HUB_OPTION"))) 
					   menu:addItem({
							text = self:string("NO_HUB_SETTING"),
							style = 'item_choice',
							check = Checkbox("checkbox",
								  function(object, isSelected)
									  self:getSettings()["embeddedTTHack"] = isSelected
									  self:storeSettings()
									  self:_restart()
								  end,
								  self:getSettings()["embeddedTTHack"]
							),
					   })
					   window:addWidget(menu)
					   window:show()
				   end,
		})

		menu:addItem({
			text = self:string("KERNEL_IDLE_OPTION"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
					   local window = Window("text_list", menuItem.text)
					   local menu = SimpleMenu("menu")
					   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_KERNEL_IDLE_OPTION")))
					   menu:addItem({
							text = self:string("KERNEL_IDLE_SETTING"),
							style = 'item_choice',
							check = Checkbox("checkbox",
								  function(object, isSelected)
									  self:getSettings()["cpuIdleFullspeed"] = isSelected
									  self:storeSettings()
									  self.cpuIdle() -- cb in meta to potentially update state
								  end,
								  self:getSettings()["cpuIdleFullspeed"]
							),
					   })
					   window:addWidget(menu)
					   window:show()
				   end,
		})
	end

	menu:addItem({
		text = self:string("BUFFER_TUNING"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
					   local options = {
						   { desc = "BUFFER_DEFAULT", time =  20000, count =   2 },
						   { desc = "BUFFER_LARGE",   time = 100000, count =   4 },
						   { desc = "BUFFER_SMALL",   time =   4000, count =   2 },
						   { desc = "BUFFER_RAND",    time = 100000, count = 104 },
						   { desc = "BUFFER_VLARGE",  time =4000000, count =   4 },
						   { desc = "BUFFER_VLRAND",  time =4000000, count = 104 },
						   { desc = "BUFFER_SPDF",    time =  30000, count =   3 },
						   { desc = "BUFFER_SLDF",    time =     40, count =   4 },
						   { desc = "BUFFER_SPPI",    time =     50, count =   5 },
					   }
					   local window = Window("text_list", menuItem.text)
					   local menu = SimpleMenu("menu")
					   local group = RadioGroup()
					   local settings = self:getSettings()
					   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_BUFFER_TUNING")))
					   for _, opt in ipairs(options) do
						   menu:addItem({
								text = self:string(opt.desc),
								style = 'item_choice',
								check = RadioButton("radio", group,
													function(event, menuItem)
														settings.bufferTime = opt.time
														settings.periodCount = opt.count
														self:storeSettings()
														self:_restart()
													end,
													settings.bufferTime == opt.time and settings.periodCount == opt.count)
						   })
					   end
					   window:addWidget(menu)
					   window:show()
				   end,
	})
        
	menu:addItem({
		text = self:string("SAMPLE_TUNING"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
					   local options = {
						   { desc = "SAMPLE_A",    size =      0 },
						   { desc = "SAMPLE_32",   size =     32 },
						   { desc = "SAMPLE_24",   size =     24 },
						   { desc = "SAMPLE_24_3", size = "24_3" },
						   { desc = "SAMPLE_16",   size =     16 },
					   }
					   local window = Window("text_list", menuItem.text)
					   local menu = SimpleMenu("menu")
					   local group = RadioGroup()
					   local settings = self:getSettings()
					   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_SAMPLE_TUNING")))
					   for _, opt in ipairs(options) do
						   menu:addItem({
								text = self:string(opt.desc),
								style = 'item_choice',
								check = RadioButton("radio", group,
													function(event, menuItem)
														settings.sampleSize = opt.size
														self:storeSettings()
														self:_restart()
													end,
													settings.sampleSize == opt.size)
						   })
					   end
					   window:addWidget(menu)
					   window:show()
				   end,
	})
        
	menu:addItem({
		text = self:string("NO_MMAP_OPTION"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
					   local window = Window("text_list", menuItem.text)
					   local menu = SimpleMenu("menu")
					   menu:setHeaderWidget(Textarea("help_text", self:string("HELP_NO_MMAP_OPTION"))) 
					   menu:addItem({
							text = self:string("NO_MMAP_SETTING"),
							style = 'item_choice',
							check = Checkbox("checkbox",
								  function(object, isSelected)
									  self:getSettings()["nommap"] = isSelected
									  self:storeSettings()
									  self:_restart()
								  end,
								  self:getSettings()["nommap"]
							),
					   })
					   window:addWidget(menu)
					   window:show()
				   end,
	})

	self:tieAndShowWindow(window)
	return window
end


function _parseCards(self)
	local t = {}
	local system = System:getMachine()

	local cards,err = io.open("/proc/asound/cards", "r")

	if err then
		log:error("/proc/asound/cards could not be opened",err)
		return
	end

	-- internal cards, put first in list
	if (system == "fab4") then
		t[1] = { id = "TXRX", desc = tostring(self:string("DIGITAL_ONLY")) }
	end

	-- read and parse entries
	for line in cards:lines() do
		local num, id, desc = string.match(line, "(%d+)%s+%[(.-)%s*%]:%s+(.*)")
		if id and id != "TXRX" and id != "fab4" and id != "fab4_1" then
			-- usb card - get bitdepth info
			local info = self:_parseStreamInfo(id)
			t[#t+1] = { id = id, desc = (system != "fab4" and desc) and tostring(self:string("DIRECT_HW")).." "..desc or desc , needshub = info.needshub , type="asound-card",  }
		end
	end
	cards:close()

	if (system == "fab4") then
		return t
	end

	local pcms,err = io.popen("aplay -L", "r")

	if err then
		log:error("aplay could not be run ",err,".")
	end

	local id, card, desc
	for line in pcms:lines()  do
		local pcm,hw  = string.match(line, "^([%w]+):CARD=([%w]+)")
		if not pcm then
			pcm = string.match(line, "^([%w]+)$")
			if pcm then
				-- card = nil
				log:debug(self,":_parseCards() vitrual pcm=",pcm," desc='", desc ,"' type=", (hw) and "asound-pcm" or "asound-virtual" ," hw=",hw )
			end
		end
		if pcm then
			if id then
				local info = (card) and self:_parseStreamInfo(card) or { needshub = false } 
				t[#t+1] = { id = id, desc = desc, type = (card) and "asound-pcm" or "asound-virtual" , hw = card, needshub = info.needshub }
				log:debug(self,":_parseCards() pcms id=",id," desc='", desc ,"' type=", (card) and "asound-pcm" or "asound-virtual" ," hw=",card , " hub=",info.needshub)
			end

			if hw then
				id = pcm..":"..hw
			else
				id = pcm
			end
			card = hw
		end
		desc = string.match(line, "^[%s]+(.+)$")
		if id and desc then
			desc = id ..", " .. desc
		end
	end
	local info = card and self:_parseStreamInfo(card) or { needshub = false }
	t[#t+1] = { id = id, desc = desc, type = (card) and "asound-pcm" or "asound-virtual", hw = card, needshub = info.needshub }

	pcms:close()

	return t
end


function _parseStreamInfo(self, card)
	local bits, needhub, async
	local t = {}
	
	local cards = io.open("/proc/asound/" .. card .. "/stream0", "r")
	
	if cards == nil then
		log:info("/proc/asound/" .. card .. "/stream0 could not be opened")
		return t
	end
	
	-- parsing helper functions
	local last
	local parse = function(regexp, opt)
		local tmp = last or cards:read()
		if tmp == nil then
			return
		end
		local r1, r2, r3 = string.match(tmp, regexp)
		if opt and r1 == nil and r2 == nil and r3 == nil then
			last = tmp
		else
			last = nil
		end
		return r1, r2, r3
	end

	local skip = function(number) 
		if last and number > 0 then
			last = nil
			number = number - 1
		end
		while number > 0 do
			cards:read()
			number = number - 2 -- FIXME  1 in orig code
		end
	end

	local eof = function()
		if last then return false end
		last = cards:read()
		return last == nil
	end

	-- detect full speed async devices without external hub
	t.id, t.speed = parse("usb%-fsl%-ehci%.(.-),%s(%w+)%sspeed%s:")
	t.hub = (t.id != "0-1")
	skip(2)

	-- detect status
	t.status = parse("  Status: (%w+)")

	if t.status == "Running" then
		t.interface = parse("    Interface = (%d+)")
		t.altset    = parse("    Altset = (%d+)")
		skip(2)
		t.momfreq   = parse("    Momentary freq = (%d+) Hz")
		t.feedbkfmt = parse("    Feedback Format = (.*)", true)
	end
	
	local fmts = {}

	while not eof() do

		local intf = parse("  Interface (%d+)")
		local alt  = parse("    Altset (%d+)")
		local fmt  = parse("    Format: (.*)")
		local chan = parse("    Channels: (%w+)")
		local type = parse("    Endpoint: %d+ %w+ %((%w+)%)")
		local rate = parse("    Rates: (.*)")
		local int  = parse("    Data packet interval: (.*)")
		skip(2)

		fmts[#fmts+1] = { intf = intf, alt = alt, fmt = fmt, chan = chan, type = type, rate = rate, int = int }

		if t.interface == intf and t.altset == alt then
			t.fmt = fmts[#fmts]
		end

		-- touch needs a hub in this case only due to imx35 embedded TT limitations
		-- FIXME pssc hub touch only or other platforms? 
		if type == "ASYNC" and t.speed == "full" and not t.hub then
			t.needshub = true
		end

	end
	
	t.fmts = fmts

	cards:close()

	return t
end


function _setCardAndReboot(self, card, embeddedTTHack)
	local s = self:getSettings()

	s.playbackDevice = card.id
	s.playbackType = card.type
	s.playbackHW = card.hw
	s.embeddedTTHack = embeddedTTHack

	self:storeSettings()

	self:_restart()
end


function _showStats(self, card, desc)
	-- check we can open the /proc file
	local info = io.open("/proc/asound/" .. card .. "/stream0", "r")

	if info == nil then
		log:info("/proc/asound/" .. card .. "/stream0" .. " could not be opened")
		return
	end

	info:close()

	local window = Window("text_list", desc)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)
	self:tieAndShowWindow(window)

	-- refreshing menu to detect hotplugging of usb dacs
	local timer

	local display = function()
						log:debug("fetching info...")
						local info = self:_parseStreamInfo(card)
						local items = {}
						local entry = function(text)
										  items[#items+1] = {
											  text = text,
											  style = "item_no_arrow",
										  }
									  end
						entry("Status: " .. info.status)
						entry("Speed: " .. (info.speed == "full" and "Full" or "High"))
						entry("Connection: " .. (info.hub and "via Hub" or "Direct"))
						if info.status == "Running" then
							local first, rest = string.match(info.fmt.type, "(%w)(%w+)")
							entry("Type: " .. string.upper(first) .. string.lower(rest))
							entry("Frequency: " .. info.momfreq .. " Hz")
							entry("Format: " .. info.fmt.fmt)
							entry("Rates: " .. info.fmt.rate)
							entry("Feedback Format: " .. ((info.feedbkfmt == "10.14" and "Full (10.14)") or 
														  (info.feedbkfmt == "16.16" and "High (16.16)") or "None"))
							entry("Interval: " .. info.fmt.int)
						else
							local i = 1
							while info.fmts[i] do
								local fmt = info.fmts[i]
								local cnt = #info.fmts > 1 and (" [" .. i .. "]: ") or ": "
								local first, rest = string.match(fmt.type, "(%w)(%w+)")
								entry("Type" .. cnt .. string.upper(first) .. string.lower(rest))
								entry("Format" .. cnt .. fmt.fmt)
								entry("Rates" .. cnt .. fmt.rate)
								i = i + 1
							end
						end
						menu:setItems(items, #items)
					end
	
	-- initial display
	display()

	-- update on a timer
	local timer = Timer(1000, function() display() end, false)
	timer:start()

	-- cancel timer when window is hidden (e.g. screensaver)
	window:addListener(EVENT_WINDOW_ACTIVE | EVENT_HIDE,
		function(event)
			local type = event:getType()
			if type == EVENT_WINDOW_ACTIVE then
				timer:restart()
			else
				timer:stop()
			end
			return EVENT_UNUSED
		end,
		true
	)
end


function _restart(self)
	self.popup = Popup("update_popup")
	self.popup:addWidget(Icon("icon_restart"))
	self.popup:addWidget(Label("text", self:string("REBOOTING")))
	self:tieAndShowWindow(self.popup)

	self.timer = Timer(3000,
					   function()
						   log:info("rebooting...")
						   appletManager:callService("reboot")
					   end,
					   true)
	self.timer:start()
end


--------------------------------------------------------------------------------------------------------------------------------
-- following is a modified form of SetupFirmwareUpgrade

function _kernelUpdate(self, kernel)
	if kernel then
		self.kernel = kernel
	end

	self.popup = Popup("update_popup")
	self.icon = Icon("icon_software_update")
	self.popup:addWidget(self.icon)

	self.text = Label("text", self:string("DOWNLOADING"), "")
	self.counter = Label("subtext", "")
	self.progress = Slider("progress", 1, 100, 1)

	self.popup:addWidget(self.text)
	self.popup:addWidget(self.counter)
	self.popup:addWidget(self.progress)
	self.popup:focusWidget(self.text)

	-- make sure this popup remains on screen
	self.popup:setAllowScreensaver(false)
	self.popup:setAlwaysOnTop(true)
	self.popup:setAutoHide(false)
	self.popup:setTransparent(false)

	-- no way to exit this popup
	self.upgradeListener =
		Framework:addListener(EVENT_ALL_INPUT,
				      function()
					      Framework.wakeup()
					      return EVENT_CONSUME
				      end,
				      true)

	-- disconnect from SqueezeCenter, we don't want to up
	-- interrupted during the firmware upgrade.
	appletManager:callService("disconnectPlayer")

	-- stop memory hungry services before upgrading
	if (System:getMachine() == "fab4") then

		appletManager:callService("stopSqueezeCenter")
		appletManager:callService("stopFileSharing")

		-- start the upgrade once SBS is shut down or timed out
		local timeout = 0
		self.serverStopTimer = self.popup:addTimer(1000, function()

			timeout = timeout + 1
			
			if timeout <= STOP_SERVER_TIMEOUT and appletManager:callService("isBuiltInSCRunning") then
				return
			end

			Task("upgrade", self, _doUpgrade, _upgradeFailed):addTask()
			
			self.popup:removeTimer(self.serverStopTimer)
		end)
	else
		Task("upgrade", self, _doUpgrade, _upgradeFailed):addTask()
	end

	self:tieAndShowWindow(self.popup)
	return window
end


function _doUpgrade(self)
	Task:yield(true)

	-- EN only messages
	local str = { UPDATE_DOWNLOAD = self:string("KERNEL_DOWNLOAD"), UPDATE_VERIFY = self:string("KERNEL_VERIFY"), 
				  UPDATE_REBOOT = self:string("REBOOTING") }

	local KernelUpgrade = require("applets.EnhancedDigitalOutput.KernelUpgrade")

	local t, err = KernelUpgrade():start(self.kernel.url, self.kernel.md5, 
		function (done, msg, count)
			if type(count) == "number" then
				if count >= 100 then
					count = 100
				end
				self.counter:setValue(count .. "%")
				self.progress:setRange(1, 100, count)
			else
				self.counter:setValue("")
			end
			
			self.text:setValue(str[msg] or msg)
			
			if done then
				self.icon:setStyle("icon_restart")
			end
		end
	)
	if not t then
		log:error("Upgrade failed: ", err)
		self:_upgradeFailed()

		if self.popup then
			self.popup:hide()
			self.popup = nil
		end
	end
end


function _upgradeFailed(self)
	-- unblock keys
	Framework:removeListener(self.upgradeListener)
	self.upgradeListener = nil

	-- reconnect to server
	appletManager:callService("connectPlayer")

	local window = Window("help_list", self:string("KERNEL_UPDATE_FAILED"))
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	menu:addItem({
		text = self:string("CANCEL"),
		sound = "WINDOWHIDE",
		callback = function()
					   window:hide()
				   end,
	})

	-- turn off auto update
	self:getSettings()["autoKernelUpdate"] = false
	self:storeSettings()

	self:tieAndShowWindow(window)
end
