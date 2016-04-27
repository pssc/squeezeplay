
--[[
=head1 NAME

applets.ScreenSavers.ScreenSaversMeta - ScreenSavers meta-info

=head1 DESCRIPTION

See L<applets.ScreenSavers.ScreenSaversApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function defaultSettings(self)
	return {
		whenStopped = "Clock:openDetailedClock",
		whenPlaying = "NowPlaying:openScreensaver",
		whenOff = "false:false",
		timeout = 30000,
		poweron_window_time = 10000,
		poweroff = 14400000,
	}
end

function upgradeSettings(self, settings)
        if settings.poweron_window_time == nil then
              settings.poweron_window_time = 5000
        end
	if settings.poweroff == nil then
		settings.poweroff = 14400000
	end
        return settings
end

function registerApplet(meta)

	meta:registerService("addScreenSaver")
	meta:registerService("removeScreenSaver")
	meta:registerService("restartScreenSaverTimer")
	meta:registerService("isScreensaverActive")
	meta:registerService("deactivateScreensaver")
	meta:registerService("activateScreensaver")

	-- Menu for configuration
	jiveMain:addItem(meta:menuItem('appletScreenSavers', 'screenSettings', "SCREENSAVERS", function(applet, ...) applet:openSettings(...) end))

	jiveMain:addItem(meta:menuItem('appletScreenSavers', 'advancedSettings', "SCREENSAVERS",  function(applet, ...) applet:openAdvSettings(...) end))

end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

