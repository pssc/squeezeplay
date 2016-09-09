
--[[
=head1 NAME

applets.InputDetector.InputDetectorMeta - InputDetector meta-info

=head1 DESCRIPTION

See L<applets.InputDetector.InputDetectorMeta>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local pairs = pairs

local oo            = require("loop.simple")
local string        = require("string")


local AppletMeta    = require("jive.AppletMeta")
local Framework     = require("jive.ui.Framework")

local SlimServer    = require("jive.slim.SlimServer")

local System        = require("jive.System")
local os            = require("os")

local appletManager = appletManager
local jiveMain      = jiveMain



module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta)
	return 1, 1
end

function defaultSettings(meta)
        return { 
		devicelist = {},
		default_mapping = 2, -- index into mappings lua indexs from 1
		hidraw = false,
		notsdevice = false,
	}
end

function registerApplet(meta)
	local settings = meta:getSettings()
        local system = System:getMachine()

	if string.match(os.getenv("OS") or "", "Windows") then
		return
        end

	jiveMain:addItem(meta:menuItem('appletInputDetectorSettings', 'advancedSettings', meta:string("APPLET_NAME"), function(applet, ...) local w = applet:menu(...) w:show() end))
	meta:registerService("getInputDetectorMapping")
end

function configureApplet(meta)
	--  is a resident Applet
        appletManager:loadApplet("InputDetector")
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
