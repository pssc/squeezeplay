
--[[
=head1 NAME

applets.SetupWallpaper.SetupWallpaperApplet - Wallpaper selection.

=head1 DESCRIPTION

This applet implements selection of the wallpaper for the jive background image.

The applet includes a selection of local wallpapers which are shipped with jive. It
also allows wallpapers to be downloaded and selected from the currently  attached server.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
SetupWallpaperApplet overrides the following methods:

=cut
--]]


-- stuff we use
local ipairs, pairs, type, print, tostring = ipairs, pairs, type, print, tostring

local oo                     = require("loop.simple")
local io                     = require("io")

local debug                  = require("jive.utils.debug")
local table                  = require("jive.utils.table")
local string                 = require("jive.utils.string")
local lfs                    = require("jive.utils.lfs")
local fun                    = require("jive.utils.fun")


local AppletUI               = require("jive.AppletUI")
local System                 = require("jive.System")

local Framework              = require("jive.ui.Framework")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Textarea               = require("jive.ui.Textarea")
local Tile                   = require("jive.ui.Tile")
local Window                 = require("jive.ui.Window")
local Framework              = require("jive.ui.Framework")

local RequestHttp            = require("jive.net.RequestHttp")
local SocketHttp             = require("jive.net.SocketHttp")


local jnt                    = jnt
local appletManager          = appletManager
local jiveMain               = jiveMain

module(..., Framework.constants)
oo.class(_M, AppletUI)

-- FIXME wallpers in skins call service for path... as its emeded but
-- should defualt wp be in skin... and additonal registered here with service...

local wallpaperMeta = { limit = "image", images = {}, download = {}, paths = { applet = "applets/SetupWallpaper/wallpapers/" , download = System.getUserDir().. "/wallpapers/" }, imageType = "wallpapers"  }
-- fixme action for set
local wallpapers = {}

function init(self)
	jnt:subscribe(self)

	lfs.mkdirRecursive(wallpaperMeta.paths.download)
	log:debug("downloaded ",wallpaperMeta.imageType," stored at: ",wallpaperMeta.paths.download)
	wallpaperMeta.unfiltered = self:getSettings()['unfiltered']
end

-- notify_playerCurrent
-- this is called when the current player changes (possibly from no player)
function notify_playerCurrent(self, player)
	log:debug("notify_playerCurrent(", player and player:getId(), ")")

	self:_wpEventKey()
	self:showBackground()
end

function _wpEventKey(self)
	local sm = self:getSettingsMeta()
	local skinName = jiveMain:getSelectedSkin()
	local wallpaper_key = skinName
	local player = appletManager:callService("getCurrentPlayer")
	local playerId 

	if player and player:getId() then
		local st = self:getSettings()
		playerId = player:getId()
		wallpaper_key = st.bgPerSkin and 'WP_'..playerId..'_'..skinName or 'WP_'..playerId
		log:debug("Create Meta Wall paper key ",wallpaper_key)
		-- FIXME use?
		sm[wallpaper_key] = fun.uses(wallpaperMeta,{ text = player:getName()..' '..skinName },true)
	else
		sm[wallpaper_key] = wallpaperMeta
	end
	sm[wallpaper_key]['action'] = function(k,v) self:setBackground(v, playerId, force) end
	return wallpaper_key
end


function notify_skinSelected(self, old, new)
	self:_wpEventKey()
	if self:getSettings()['bgPerSkin'] then
		self:showBackground()
	end
end


-- callback function
function settingsShow(self,mI)
	local skinName = jiveMain:getSelectedSkin()
	local wallpaper_key = skinName
	local st = self:getSettings()

	local player = appletManager:callService("getCurrentPlayer")

	if player then
		local playerId = player:getId()
		wallpaper_key = st.bgPerSkin and 'WP_'..playerId..'_'..skinName or 'WP_'..playerId

	end
	self:imageWindow(mI, wallpaper_key) 
end


function showBackground(self, wallpaper, playerId, force)
	-- default is different based on skin
	local st = self:getSettings()
	local sm = self:getSettingsMeta()
	local skinName = jiveMain:getSelectedSkin()
	local download = {}
	local downloadPrefix = wallpaperMeta.paths.download
	local firmwarePrefix = wallpaperMeta.paths.applet
	local wallpaper_key = skinName
	
	if not playerId then
		local player = appletManager:callService("getCurrentPlayer")
		playerId = player and player:getId() or nil
		log:debug("Curtent player ",playerId)
	end

	if playerId then 
		wallpaper_key = st.bgPerSkin and 'WP_'..playerId..'_'..skinName or 'WP_'..playerId
		log:debug("Wall paper key ",wallpaper_key)
	end
	if sm[wallpaper_key] then
		--on applet meta we may not have had the notify...
		download = sm[wallpaper_key].download
	end

	log:debug('Show wallpaper for ', playerId, ' skin ',skinName, " wallpaper ", wallpaper," perskin ",st['bgPerSkin'])
	if not wallpaper then
		wallpaper = st[wallpaper_key]
		if not wallpaper then
			-- Default for skin if available
			wallpaper = st[skinName]
		end
	end

	-- always refresh if forced
	if self.currentWallpaper == wallpaper and not force then
		-- no change
		return
	end
	log:info("change from ",self.currentWallpaper," to ", wallpaper)
	self.currentWallpaper = wallpaper

	local srf
       
	if wallpaper and download[wallpaper] then
		-- image in download cache
		if download[wallpaper] ~= "fetch" and download[url] ~= 
  "fetchset" then

			local data = download[wallpaper]
			srf = Tile:loadImageData(data, #data)
		end

	elseif wallpaper and string.match(wallpaper, "^https?://(.*)") then
		-- saved remote image for this player
		srf = Tile:loadImage(downloadPrefix .. wallpaper_key:gsub(":", "-"))
		-- FIXME not general?
	elseif wallpaper then
		-- we use dirs for list with imageType rather than findFile and firmware constant?
		if not string.match(wallpaper, "/") then
			-- try firmware wallpaper 
			-- Fixme paths search
			wallpaper = firmwarePrefix .. wallpaper
			log:debug("Search location ", wallpaper)
		end

		-- get the absolute file path for whatever we have
		wallpaper = System:findFile(wallpaper)

		-- or default? FIXME
        	if wallpaper then 
			log:debug("Wallpaper ",wallpaper)
			srf = Tile:loadImage(wallpaper)
		end
	end

	-- will go black... 
	if srf then
		Framework:setBackground(srf)
	else
		log:warn("Image not loaded ",wallpaper)
		if not wallpaper then
			local def = self:getDefaultSettings()
			log:debug(skinName, " Default skin ", def[skinName])
			log:debug("Defaults ",debug.view(def))

			if def[skinName] and st[skinName] ~= def[skinName] then
				log:debug("Updating to new default for ",skinName, " ",st[skinName]," -> ",def[skinName])
				st[skinName] = def[skinName]
				self:showBackground(wallpaper, playerId, force)
			end
		end
	end
end


--general image with key then bg set?
function setBackground(self, wallpaper, playerId, force)
	local st = self:getSettings()
	local download = {}
	local downloadPrefix = wallpaperMeta.paths.download
	local skinName = jiveMain:getSelectedSkin()
	local wallpaper_key = skinName


	if playerId then
		wallpaper_key = st.bgPerSkin and 'WP_'..playerId..'_'..skinName or 'WP_'..playerId
		download = self:getSettingsMeta()[wallpaper_key].download
	end
	log:debug('Set background for ', playerId, ' ', wallpaper)
	-- set the new wallpaper, or use the existing setting
	if wallpaper then
		if download[wallpaper] then
			if download[wallpaper] == "fetch" then
				download[wallpaper] = "fetchset"
				return
			end
			-- FIXME key based
			local path = downloadPrefix .. wallpaper_key:gsub(":", "-")
			local fh = io.open(path, "wb")
			if fh then
				log:info("saving image to ", path)
				fh:write(download[wallpaper])
				fh:close()
			else
				log:warn("unable to same image to ", path)
			end
		end

		self:getSettings()[wallpaper_key] = wallpaper
		--self:storeSettings()
	end
	self:showBackground(wallpaper, playerId, force)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

