
--[[
=head1 NAME

applets.AutoSkin.AutoSkinApplet - An applet to select different SqueezePlay skins

=head1 DESCRIPTION

This applet allows the SqueezePlay skin to be selected.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
AutoSkinApplet overrides the following methods:

=cut
--]]

local ipairs, pairs = ipairs, pairs

local oo              = require("loop.simple")
local Applet          = require("jive.Applet")

local Framework       = require("jive.ui.Framework")
local Surface         = require("jive.ui.Surface")

local jiveMain        = jiveMain
local appletManager   = appletManager

local debug           = require("jive.utils.debug")

local SnapshotWindow  = require("jive.ui.SnapshotWindow")
local Window          = require("jive.ui.Window")

module(..., Framework.constants)
oo.class(_M, Applet)

--service method
function getActiveSkinType(self)
	return self.mode
end

function init(self, ...)
	-- skin types
	local touchSkin = "touch"
	local remoteSkin = "remote"

	if not self.irBlacklist then
		self.irBlacklist = {}

		-- see jive.irMap_default for defined buttons
		for x, button in ipairs({
			"arrow_up",
			"arrow_down",
		--	"arrow_left",
			"arrow_right",
			"play",
		--	"add",
		--	"now_playing",
		}) do
			local irCodes = Framework:getIRCodes(button)
			
			for name, irCode in pairs(irCodes) do
				self.irBlacklist[irCode] = button
			end
		end
		self.keyBlackList = {}
	end

	self.eatEvents = false
		
	Framework:addListener(EVENT_IR_ALL,
		function(event)
			-- ignore initial keypress after switching from touch to IR control
			if self.eatEvents then

				if event:getType() == EVENT_IR_UP then
					self.eatEvents = false
				end
				log:warn("eatme me - ir " .. event:getIRCode() .. " is context sensitive")
				return EVENT_CONSUME

			-- FIXME wake up if in screensaver mode by passing through events?
			elseif self:changeSkin(remoteSkin) and self.irBlacklist[event:getIRCode()] ~= nil then

				log:warn("eatme me - ir " .. self.irBlacklist[event:getIRCode()] .. " is context sensitive")
				self.eatEvents = true
				return EVENT_CONSUME

			end

			return EVENT_UNUSED
		end,
		-100)

	Framework:addListener(EVENT_MOUSE_ALL,
		function(event)
			local mapping = appletManager:callService("getInputDetectorMapping")
			local skin = mapping =='REMOTE' and remoteSkin or touchSkin

			if self.eatEvents then
				log:warn("eat me - I don't know what I'm touching! ",event:tostring())
				return EVENT_CONSUME
			end
			-- ignore event when switching from remote to touch: we don't know what we're touching
			-- wake up if in screensaver mode by passing through events
			if self:changeSkin(skin) and not appletManager:callService("isScreensaverActive") then
				log:warn("ignore me - I don't know what I'm touching! ",event:tostring())
				self.eatEvents = true
				return EVENT_CONSUME
			end

			return EVENT_UNUSED
		end,
		-100)

	Framework:addListener(EVENT_ALL_INPUT,
		function(event)
			local mapping = appletManager:callService("getInputDetectorMapping")
			local skin = mapping =='REMOTE' and remoteSkin or touchSkin 

			if event:getType() == EVENT_CHAR_PRESS then
				return EVENT_UNUSED
			end
			
			if self.eatEvents then
				if event:getType() == EVENT_KEY_UP then -- same as IR
                                        self.eatEvents = false
					log:warn("eaten key up - full ",event:tostring())
                                else
					log:warn("eat me - I don't know what I'm inputing! ",event:tostring())
				end
				return EVENT_CONSUME
			end

			log:debug(self,":AutoSkin INPUT listener ",event:tostring())
			-- FIXME key blacklist...? and or gnore initial keypress after switching from touch to remote
			-- Tranistion can take a while so can cause a KEY_HOLD event so deactivate SS and use an Empty Transition to eat events.
			local sa = appletManager:callService("isScreensaverActive")
			if self:changeSkin(skin, sa and Window.transitionEmpty) then
				appletManager:callService("deactivateScreensaver")
				log:warn("ignore me - I don't know what I'm inputing! ",event:tostring())
				self.eatEvents = true
				return EVENT_CONSUME
			end
			--deactivateScreensaver

			return EVENT_UNUSED
		end,
	-100)

	-- Catch all to release input on 'other' events
	Framework:addListener(EVENT_ALL,
		function(event)
			if self.eatEvents then
				log:warn("Catchall finished eating ", event:tostring())
				self.eatEvents = false
			end
			return EVENT_UNUSED
		end,
	-200)
	return self
end



function changeSkin(self, skinType, trans)
	log:debug(":changeSkin ",skinType,"==",self.mode)

	if  self.mode == skinType then
		return false
	end

	local skinName = appletManager:callService("getSelectedSkinNameForType", skinType)
	if jiveMain:getSelectedSkin() == skinName then
		self.mode = skinType -- needed for inital setting of mode at start.
		log:debug("skin already selected, not switching: ", skinName)
		return false
	end

        log:info(":changeSkin ",skinName,":",skinType)
        local old = SnapshotWindow("oldchsk")
	local ow, oh = Framework:getScreenSize()
	self.mode = skinType
	jiveMain:setSelectedSkin(skinName) -- FIXME Check we have vaild and changed
	local nw, nh = Framework:getScreenSize()
        log:info(":changeSkin new")
	local new = SnapshotWindow("newchsk")
        log:info(":changeSkin new done")

	if ow ~= nw or oh ~= nh then
		-- Resolution Change blank and fade in
		log:info(":changeSkin Resolution Change ",skinName,":",skinType)
		old = SnapshotWindow("BlankChSk",Surface:newRGB(nw, nh)) -- Blank and fade in
	end

	Framework:_startTransition(self:_trans(trans or Window.transitionFadeInFast ,old, new))

	return true
end


function _trans(self,trans, ...)
	local fn = trans(...)
	return function (...)
		if fn(...) then
			self.eatEvents = false
			log:debug(self,":changeSkin:trans Finished!")
		end
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

