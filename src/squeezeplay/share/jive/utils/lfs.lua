-----------------------------------------------------------------------------
-- strings.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.util.string - fs utilities

=head1 DESCRIPTION

Assorted fs functions for strings

Builds on lfs module

=head1 SYNOPSIS

 -- recusive mkdir
 mkdirRecursive("/p/a/t/h")

=head1 FUNCTIONS

=cut
--]]


local setmetatable = setmetatable
local pairs = pairs

local ltable           = require('lfs')
local lfs              = require("lfs")
local string           = require("jive.utils.string")

local log              = require("jive.utils.log").logger("squeezeplay.lfs")

module(...)

-- this is the bit that does the extension.
setmetatable(_M, { __index = ltable })

--[[

=head2 mkdirRecursive(s)

mkdir for a whole path s.

=cut
--]]


function mkdirRecursive(dir)
    --normalize to "/"
    local dir = dir:gsub("\\", "/")

    local newPath = ""
    for i, element in pairs(string.split('/', dir)) do
        newPath = newPath .. element
        if i ~= 1 then --first element is (for full path): blank for unix , "<drive-letter>:" for windows
            if lfs.attributes(newPath, "mode") == nil then
                log:debug("Making directory: " , newPath)

                local created, err = lfs.mkdir(newPath)
                if not created then
                    error (string.format ("error creating dir '%s' (%s)", newPath, err))
                end
            end
        end
        newPath = newPath .. "/"
    end

end

