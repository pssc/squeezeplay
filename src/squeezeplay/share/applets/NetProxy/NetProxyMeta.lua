
--[[
=head1 NAME

applets.NetProxy.NetProxyMeta - NetProxy meta-info

=head1 DESCRIPTION

See L<applets.NetProxy.NetProxyMeta>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local pairs = pairs

local oo            = require("loop.simple")
local os	    = require("os")

local AppletMeta    = require("jive.AppletMeta")
local Framework     = require("jive.ui.Framework")
local Proxy         = require("jive.net.Proxy")
local string	    = require("jive.utils.string")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	-- FIXME default settings in Proxy.lua code overwrtten on load
        return {
	}
end


function settingsMeta(meta)
	return {
	}
end


function registerApplet(meta)
	-- in configure?
	-- load settings from Applet into net Proxy Instance
	local settings = meta:getSettings()

	if settings['proxies'] then
		--FXIME check defaults? exist?
		Proxy.setSettings(settings['proxies'])
	end
	if settings['proxy'] then
		Proxy.setProxyState(settings['proxy'])
	end

	-- HTTP_PROXY if not set in applet
	local proxy = os.getenv("HTTP_PROXY")
	if proxy and not settings['proxy'] then
		log:warn("HTTP_PROXY=", proxy)
		proxy, _=  string.gsub(proxy,"^https?://","")
		proxy, _= string.gsub(proxy,"$/","")
		local server, port = string.split(":")
		port, _ = string.gsub(port,"(%d+)","%1")
		port = port == '' and nil or port
		--FIXME NO_PROXY....
		local p = Proxy.addProxy(server)
		Proxy.setPort(port,p)
		Peoxy.setActive(true,p)
		Proxy.setProxyState(true)
	end

	jiveMain:addItem(meta:menuItem('appletNetProxySettings', 'networkSettings', meta:string("APPLET_NAME"), function(applet, ...) local w = applet:menu(...) w:show() end))
end


function configureApplet(meta)
	local st = meta:getSettings()
	if st['ssh_tunnel_server_toggle'] then
		appletManager:loadApplet("NetProxy")
	end
end

--[[
=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
