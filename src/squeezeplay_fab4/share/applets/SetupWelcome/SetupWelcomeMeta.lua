
--[[
=head1 NAME

applets.SetupWelcome.SetupWelcomeMeta - SetupWelcome meta-info

=head1 DESCRIPTION

See L<applets.SetupWelcome.SetupWelcomeApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")
local locale	    = require("jive.utils.locale")

local AppletMeta    = require("jive.AppletMeta")

local log           = require("jive.utils.log").logger("applets.setup")

local appletManager = appletManager
local jiveMain      = jiveMain
local jnt           = jnt


-- HACK: this is bad, but we need to keep the meta in scope for the network
-- subscription to work
local hackMeta = true


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {
		[ "setupDone" ] = false,
		[ "registerDone" ] = false,
	}
end


function registerApplet(meta)
	meta:registerService("startSetup")
	meta:registerService("startRegister")
end


function configureApplet(meta)
	local settings = meta:getSettings()

	if not settings.setupDone then
		appletManager:callService("startSetup")
	end

	if not settings.registerDone then
		hackMeta = meta
		jnt:subscribe(meta)
	end
end


function notify_serverNew(meta, server)
	local settings = meta:getSettings()

	if settings.setupDone and server:isSqueezeNetwork() then
		appletManager:callService("startRegister")
	end
end


function notify_serverLinked(meta, server)
	log:info("server linked: ", server)

	local settings = meta:getSettings()
	settings.registerDone = server:getPin() and true or false
	meta:storeSettings()

	if settings.registerDone then
		jnt:unsubscribe(meta)
		hackMeta = nil
	end
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
