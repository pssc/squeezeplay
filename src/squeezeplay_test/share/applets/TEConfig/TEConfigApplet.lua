

-- stuff we use
local assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs = assert, getmetatable, ipairs, pcall, setmetatable, tonumber, tostring, pairs

local oo                     = require("loop.simple")

local string                 = require("string")
local io                     = require("io")
local os                     = require("os")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local AppletUI               = require("jive.AppletUI")
local System                 = require("jive.System")
local Framework              = require("jive.ui.Framework")
local Label                  = require("jive.ui.Label")
local Textarea               = require("jive.ui.Textarea")
local Window                 = require("jive.ui.Window")
local Choice 		     = require("jive.ui.Choice")
local Popup                  = require("jive.ui.Popup")
local SimpleMenu	     = require("jive.ui.SimpleMenu")
local Task          	     = require("jive.ui.Task")

local log                    = require("jive.utils.log").logger("applet.VCNL4010")
local jnt                    = jnt

local appletManager = appletManager

module(..., Framework.constants)
oo.class(_M, AppletUI)


function test(self)
	return self:getSettings()['test']
end

function experimental(self)
	return self:getSettings()['experimental']
end

