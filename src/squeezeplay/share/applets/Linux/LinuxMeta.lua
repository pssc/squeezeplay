
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

-- RT script on post OnScreenInit
function rt(self,name)
        --if (string.match(os.getenv("JIVE_RT_PRI") or "", "([0-9]+)")) then
                local script = name or "squeezeplay-rt.sh"
                log:debug("RT script ",script," scheduled")
                jiveMain:registerPostOnScreenInit(function()
                        log:info("RT init ",script)
                        local s,err = io.popen(script, "r")

                        if err then
                                log:error("RT ",script," could not be run ",err,".")
                        else
                                s:close()
                        end
                end)
        --end
end

function registerApplet(meta)
end
