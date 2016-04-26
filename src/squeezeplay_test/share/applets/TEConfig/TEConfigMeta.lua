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
        }
end


function settingsMeta(meta)
        return {
                test = { limit="toggle"},
                experimental = { limit="toggle"},
	}
end


function registerApplet(meta)
	jiveMain:addItem(meta:menuItem('TECONFIG', 'advancedSettings', "APPLET_NAME",  function(applet, ...) applet:presentMeta(...) end))
	meta:registerService('test')
	meta:registerService('experimental')
	if meta:getSettings()['test'] then
		log:warn('Test Features Enabled')
	end
	if meta:getSettings()['experimental'] then
		log:warn('Experimental Features Enabled')
	end
end

