
local ipairs, pairs, tonumber, setmetatable, type, tostring = ipairs, pairs, tonumber, setmetatable, type, tostring

local math             = require("math")
local table            = require("table")
local os	       = require("os")	
local string	       = require("jive.utils.string")
local debug	       = require("jive.utils.debug")

local oo               = require("loop.simple")

local Framework        = require("jive.ui.Framework")
local log              = require("jive.utils.log").logger("squeezeplay.ui")


module(..., Framework.constants)
--oo.class(_M, Applet)

-- : https://css-tricks.com/viewport-sized-typography/
ViewPort = oo.class(_M)
function ViewPort:__init(w,h,x,y)
	local obj = oo.rawnew(self)
	if not x or not y then
		obj.x, obj.y = Framework:getScreenSize()
	else
		obj.x, obj.y = x, y
	end
	if not w or not h then
		w,h = obj.x, obj.y	
	end
	obj.ppi = 96
	obj.ptSize = 1/72
	obj.vw = w/100
	obj.vh = h/100
	obj.vx = obj.x/100
	obj.vy = obj.y/100
	return obj
end

function ViewPort:_sfont(o,n,pt)
        local i = self.ptSize * pt
        local px = i * self.ppi
	local vs = px / o
        local cpx = vs * n
        local ci = cpx / self.ppi
        local npt = math.floor(ci / self.ptSize)
	log:debug("_sfont (", o,",", n,"): ",pt,"/", vs,"/", npt)
        return npt
end

function ViewPort:swfont(pt)
	log:debug("swfont ",pt)
        return self:_sfont(self.vw,self.vx,pt)
end

function ViewPort:shfont(pt)
	log:debug("shfont ",pt)
        return debug:_sfont(self.vh,self.vy,pt)
end

function ViewPort:sw(px)
	local wxSize = px/self.vw
        local cpx = math.floor(wxSize*self.vx)
	log:debug("sw ",px,"/", wxSize,"/",cpx)
	return cpx
end

function ViewPort:sh(px)
	local wxSize = px/self.vh
        local cpx = math.floor(wxSize*self.vy)
	log:debug("sh ", px,"/",wxSize, "/", cpx)
	return cpx
end

function ViewPort:smin(px)
	return math.min(self:sw(px),self:sh(px))
end

function ViewPort:smax(px)
	return math.max(self:sw(px),self:sh(px))
end

function ViewPort:sminfont(pt)
	return self:sh(1) < self:sw(1) and self:shfont(pt) or self:swfont(pt)
end

function ViewPort:smaxfont(pt)
	return self:sh(1) > self:sw(1) and self:shfont(pt) or self:swfont(pt)
end

function ViewPort:w(n)
	return n * obj.vx
end

function ViewPort:h(n)
	return n * obj.vy
end

