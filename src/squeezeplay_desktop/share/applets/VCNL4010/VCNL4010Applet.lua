

-- stuff we use
local assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs = assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs

local oo                     = require("loop.simple")

local string                 = require("string")
local io                     = require("io")
local os                     = require("os")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local AppletUI               = require("jive.AppletUI")
local System                 = require("jive.System")
local Framework              = require("jive.ui.Framework")
local Label                  = require("jive.ui.Label")
local Textarea               = require("jive.ui.Textarea")
local Window                 = require("jive.ui.Window")
local Choice 		     = require("jive.ui.Choice")
local Popup                  = require("jive.ui.Popup")
local SimpleMenu	     = require("jive.ui.SimpleMenu")
local Task          	     = require("jive.ui.Task")

local log                    = require("jive.utils.log").logger("applet.VCNL4010")
local jnt                    = jnt

local appletManager = appletManager

module(..., Framework.constants)
oo.class(_M, AppletUI)

local TASK_TRY_LIMIT                    = 3 --config?


function init(self)
	 -- set up task ready to run
	
	local settings = self:getSettings()
	if settings["active"] then
        	self:_trigger()
	end

	return self
end


function _trigger(self)
        log:debug("_trigger")
        if not self.task then
                log:debug("New Task")
                self.task = Task("VCNL4010", self, _task, nil, Task.PRIORITY_LOW)
                self.task:addTask()
                self.count = 0
        else
                log:warn(self.task, " not yet terminated ",count)
                if self.count > TASK_TRY_LIMIT then
                        log:error (self.task, " forced terminaton ", count)
                        self:_debug()
                        self.task:removeTask()
                        self.task = nil
                end
        end
        log:debug("_triggered")
end


function _task(self)
	--  VCNL4010_IRLED MAX
	local settings = self:getSettings()
	System:smbusWriteData(self.ref,0x83, settings["irled"])
	if log:isDebug() then
		
		log:debug("IR Power 20==", System:smbusReadData(self.ref,0x83))
	end
	-- Light reading mode - 128 Con + 8 Auto comp + 5 Def Average
	System:smbusWriteData(self.ref,0x84, settings["lightmode"])
	-- Proximity Modulator Timing Adjustment (recommened in datasheet)
	System:smbusWriteData(self.ref,0x8F, settings["timing"])
	-- VCNL4010 READ light and Proxy
	System:smbusWriteData(self.ref,0x80, 0x08 | 0x10)

	self.po = 0
	while true do
		local res = System:smbusReadData(self.ref, 0x80)
		if (res & (0x20 | 0x40)) then -- light and Proxy ready
	        	local lh = System:smbusReadData(self.ref,0x85)
        		local ll = System:smbusReadData(self.ref,0x86)
                	local ph = System:smbusReadData(self.ref,0x87)
                	local pl = System:smbusReadData(self.ref,0x88)
                	local l = ll | (lh << 8 )
                	local p = pl | (ph << 8 )
			local settings = self:getSettings() -- Refreshed
			log:debug("Proximity ", p," Light ", l)
                	if self.po > 0 and p > self.po+settings["sensitivity"] then
				if System:hasSoftPower() then
					Framework:pushAction("power_on")
					log:info("Power on ",self.po,"-",p, " sensitivity ",settings["sensitivity"])
				end
			end
			-- FIXME light processing here for brighness ctrl
			self.po = p
		end
		System:smbusWriteData(self.ref,0x80, 0x08 | 0x10) -- Start another reading
		if settings["active"] then
			self.task:yield()
		else
			return
		end
	end
end

function setDevice(self,bus,ref)
	assert(bus)
	assert(ref)

	self.bus = bus
	self.ref = ref	
end

function free(self)
	local settings = self:getSettings()
	AppletUI.free(self)
	if settings["active"] then
		return false
	end
	return true
end

