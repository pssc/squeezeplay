
--[[
=head1 NAME

applets.AutoSkin.AutoSkinMeta - Select SqueezePlay skin

=head1 DESCRIPTION

See L<applets.AutoSkin.AutoSkinApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local jiveMain      = jiveMain
local appletManager = appletManager


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function registerApplet(meta)
	meta:registerService("getActiveSkinType")
end


function configureApplet(meta)
	-- resident applet
	appletManager:loadApplet("AutoSkin")

	-- Initial skin type could be neither of these... 
	-- Precache
	if (appletManager:hasService("getSelectedSkinNameForType")) then
		log:info("Preloading skins for autoskin...")
		jiveMain:loadSkin(appletManager:callService("getSelectedSkinNameForType", "touch"))
		jiveMain:loadSkin(appletManager:callService("getSelectedSkinNameForType", "remote"))
	else
		log:warn("getSelectedSkinNameForType missing")
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

