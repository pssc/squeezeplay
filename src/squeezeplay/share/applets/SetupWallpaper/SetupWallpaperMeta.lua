
--[[
=head1 NAME

applets.SetupWallpaper.SetupWallpaperMeta - SetupWallpaper meta-info

=head1 DESCRIPTION

See L<applets.SetupWallpaper.SetupWallpaperApplet>.

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


function jiveVersion(meta)
	return 1, 1
end


function settingsMeta(meta)
	return {
		bgPerSkin = { limit="toggle"},
		unfiltered = { limit="toggle"},
	}
end


function defaultSettings(meta)
	-- FIXME Should be in players SqueezeboxApplet, these are default bg for skins
	-- FIXME should be set by Skin if not set by SqueezeboxApplet
	return {
		-- FIXME resize
		bgPerSkin	= false,
		unfiltered	= false,
		WQVGAsmallSkin = "480x272_encore.png", --fab4
		WQVGAlargeSkin = "480x272_encore.png", --fab4
		FullscreenSkin = "240x320_midnight.png",
		QVGAportraitSkin  = "240x320_encore.png", --jive
		QVGAlandscapeSkin = "320x240_encore.png", --baby changes dependant on model
	}
end


function registerApplet(meta)
	meta:registerService("showBackground")
	meta:registerService("setBackground")
	--meta:registerService("addBackground")
	-- add a menu item for configuration
	jiveMain:addItem(meta:menuItem('appletSetupWallpaper', 'screenSettings', 'APPLET_NAME', function(applet, ...) applet:settingsShow(...) end))
	jiveMain:addItem(meta:menuItem('appletAdvSetupWallpaper', 'advancedSettings', "APPLET_NAME", function(applet, ...) applet:presentMeta(...) end))

end


function configureApplet(meta)
	-- load default wallpaper before connecting to a player (nil will load default)
	-- will also cause applet to load and subscribe
	appletManager:callService("showBackground")
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

