local oo            = require("loop.simple")
local os            = require("os")
local io            = require("io")
local string        = require("string")

local table         = require("jive.utils.table")

local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")
local debug         = require("jive.utils.debug")

local appletManager = appletManager

local jiveMain, jnt, string, tonumber, tostring = jiveMain, jnt, string, tonumber, tostring

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
        return 1, 1
end


function defaultSettings(meta)
        return {
		-- User
		active = false,
		sensitivity = 8,
		bus = 1,
		-- HW defaults
		address = 0x13,
		irled = 20,
		lightmode =  128 | 8 | 5,
		timing = 1,
        }
end

-- FIXME meta settings...
function settingsMeta(meta)
        return {
                active = { limit="toggle"},
                bus = { limit="cardinal"},
                sensitivity = { limit="cardinal"},
                --address = { limit="hex?"}, this is fixed...?
	}
end

function registerApplet(meta)
	if System:hasSMBus() then
		local settings = meta:getSettings()

		--FIXME menu to activate
		 jiveMain:addItem(meta:menuItem('VCNL4010', 'advancedSettings', "APPLET_NAME",  function(applet, ...) applet:presentMeta(...) end))
		if not settings["active"] then
			return
		end

		log:warn("smbus ",debug.view(settings))

		local bus = System:smbus(settings["bus"])
		local ref = System:smbusDevice(bus,settings["address"])
		local p_r = System:smbusReadData(ref,0x81) --VCNL4010_PRODUCTIDREV

		if p_r > 0 then --FIXME spilt productid and rev and check...
			log:warn("Ref ",ref, " VCNL4010_PRODUCTIDREV = ",p_r)
			--Resident applet
			local a = appletManager:loadApplet("VCNL4010")
			if a then 
				a:setDevice(bus,ref)
			end
		end
	end
end

