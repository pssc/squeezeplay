
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
			-- wake up if in screensaver mode - this is a non critical action
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
			if self:changeSkin(skin) then 
				log:warn("ignore me - I don't know what I'm inputing! ",event:tostring())
				self.eatEvents = true
				return EVENT_CONSUME
			end

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



function changeSkin(self, skinType)
	log:debug(self,":changeSkin ",skinType,"==",self.mode)

	if  self.mode == skinType then
		return false
	end

	local skinName = appletManager:callService("getSelectedSkinNameForType", skinType)
	if jiveMain:getSelectedSkin() == skinName then
		self.mode = skinType -- needed for inital setting of mode at start.
		log:debug("skin already selected, not switching: ", skinName)
		return false
	end

        log:info(self,":changeSkin ",skinName,":",skinType)
	local old = _capture("start")
	local sw, sh = Framework:getScreenSize()
	self.mode = skinType
	jiveMain:setSelectedSkin(skinName) -- FIXME Check we have vaild and changed
	local fw, fh = Framework:getScreenSize()
        log:info(self,":changeSkin new")
	local new = _capture("new")
        log:info(self,":changeSkin new done")

	if fw == sw and sh == fh then
		Framework:_startTransition(self:_transitionFadeIn(old, new))
	else
		-- Resolution Change
		log:info(self,":changeSkin Resolution Change ",skinName,":",skinType)
		old = Surface:newRGB(Framework:getScreenSize()) -- FIXME Blank and fade in ?
	end
	Framework:_startTransition(self:_transitionFadeIn(old, new)) -- FIXME event eating during transition so not afe to skip?

	return true
end


function _capture(name)
	local sw, sh = Framework:getScreenSize()
	local img = Surface:newRGB(sw, sh)

	Framework:draw(img)

	return img
end


function _transitionFadeIn(self, oldImage, newImage)
	local transitionDuration = self:getSettings()["transitionDuration"]
	local remaining = transitionDuration
	local startT

	return function(widget, surface)
			if not startT then
				-- getting start time on first loop avoids initial delay that can occur
				startT = Framework:getTicks()
			end

			newImage:blit(surface, 0, 0)
			oldImage:blitAlpha(surface, 0, 0, remaining * (255 / transitionDuration))
			-- Alpha channel is 8bit
			remaining = transitionDuration - (Framework:getTicks() - startT)
			if remaining <= 0 then
				Framework:_killTransition()
				log:info(":changeSkin Transtion Finished")
				self.eatEvents = false
			end
		end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

