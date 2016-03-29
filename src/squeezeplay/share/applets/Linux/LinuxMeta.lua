
--[[
=head1 NAME

applets.SelectSkin.SelectSkinMeta - Select SqueezePlay skin

=head1 DESCRIPTION

See L<applets.SelectSkin.SelectSkinApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")
local os            = require("os")
local io            = require("io")
local string        = require("string")


local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain
local jnt           = jnt
local arg           = arg

module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta)
        return 1, 1
end

function registerApplet(meta)
end
