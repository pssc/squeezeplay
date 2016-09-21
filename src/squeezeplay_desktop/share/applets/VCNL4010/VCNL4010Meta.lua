local oo            = require("loop.simple")

local table         = require("jive.utils.table")

local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")
local debug         = require("jive.utils.debug")

local appletManager = appletManager

local jiveMain, jnt, tonumber, tostring = jiveMain, jnt, tonumber, tostring

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

		log:info("smbus ",debug.view(settings))

		local bus = System:smbus(settings["bus"])
		local ref = System:smbusDevice(bus,settings["address"])
		local p_r = System:smbusReadData(ref,0x81) --VCNL4010_PRODUCTIDREV

		if p_r and p_r > 0 then --FIXME spilt productid and rev and check...
			log:warn("Ref ",ref, " VCNL4010_PRODUCTIDREV = ",p_r)
			--Resident applet in confgiure?
			local app = appletManager:loadApplet("VCNL4010")
			if app then
				app:setDevice(bus,ref)
			end
		end
	end
end

