

-- stuff we use
local ipairs, tostring, type = ipairs, tostring, type

local oo              = require("loop.simple")
local Framework       = require("jive.ui.Framework")
local Widget          = require("jive.ui.Widget")
local Window          = require("jive.ui.Window")
local Surface         = require("jive.ui.Surface")

local log             = require("jive.utils.log").logger("squeezeplay.ui")

local EVENT_ACTION    = jive.ui.EVENT_ACTION
local EVENT_KEY_PRESS = jive.ui.EVENT_KEY_PRESS
local ACTION          = jive.ui.ACTION
local EVENT_CONSUME   = jive.ui.EVENT_CONSUME


-- our class
module(...)
oo.class(_M, Window)

function captureScreen()
	local img = Surface:newRGB(Framework:getScreenSize())
	if not img then log:error("allocation for image failed ", Framework:getScreenSize()) end
	--take snapshot of screen
	Framework:draw(img)

	return img
end


function __init(self, windowId)
	local obj = oo.rawnew(self, Window("" , "", _, windowId))

	obj._DEFAULT_SHOW_TRANSITION = Window.transitionNone
	obj._DEFAULT_HIDE_TRANSITION = Window.transitionFadeInFast

	obj:setAllowScreensaver(true)
	obj:setShowFrameworkWidgets(false)

	obj:setButtonAction("lbutton", nil)
	obj:setButtonAction("rbutton", nil)

	obj._sc = captureScreen()

	return obj
end

--[[
function _cancelContextMenuAction()
	Window:hideContextMenus()
	return EVENT_CONSUME
end

function _getTopWindowContextMenu(self)
	local topWindow = Window:getTopNonTransientWindow()

	if topWindow:isContextMenu() then
		return topWindow
	end
end
--]]

function getSurface(self)
	return self._sc
end

function draw(self, surface)
	self._sc:blit(surface, 0, 0)
end

function refresh(self)
	self._sc = captureScreen()
end



function __tostring(self)
	return "SnapshotWindow("..tostring(self.windowId or "")..")"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
