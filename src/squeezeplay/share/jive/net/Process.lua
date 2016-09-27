--[[
--]]
local assert = assert

local oo              = require("loop.base")
local io              = require("io")
local os              = require("os")
local string          = require("string")

local Task            = require("jive.ui.Task")
local System          = require("jive.System")

local debug           = require("jive.utils.debug")
local log             = require("jive.utils.log").logger("net.socket")

local jiveMain        = jiveMain

module(..., oo.class)


function init(jm)
	jiveMain = jm
end

function __init(self, jnt, prog)
	local obj = oo.rawnew(self, {
		jnt = jnt,
		prog = prog,
		_status = "suspended",
	})
	if not jiveMain then log:error("jiveMain ",prog) end
	return obj
end


function read(self, sink)
	self.fh, err = io.popen(self.prog, 'r')
	local tf,rf

	if self.fh == nil then
		sink(nil, err)

		self._status = "dead"
		return
	end

	-- Cope with squeezeos builds without this.
	if System.fionread then
		rf = function(fd)
			return System:fionread(fd)
		end
	else
		-- FIXME may work on windows needs testing
		rf = function(fd) return '*l' end
	end

	if string.match(os.getenv("OS") or "", "Windows") then
			-- blocking on Windows!
			local chunk = self.fh:read("*a")
			self.fh:close()

			sink(chunk)
			sink(nil)
			self._status = "dead"
			return
	else
		local fd = self:getfd()
		tf = function(_, ...)
			while true do
				local chunk = self.fh:read(rf(fd))

				sink(chunk)
				if chunk == nil then
					self.jnt:t_removeRead(self)
					self.fh:close()

					self._status = "dead"
					if self.h then
						jiveMain:removePostOffScreenClean(self.h)
						self.h = nil
					end
					return false
				end

				Task:yield(false)
			end
		end
	end

        -- (self, name, obj, f, errf, priority)
	local task = Task("prog:" .. self.prog, nil,tf)

	self._status = "running"
	self.jnt:t_addRead(self, task, 0)
end

function setPid(self,pid)
	if not self.killOpt then self.killOpt="" end
	self.pid = pid
	self.h = jiveMain:registerPostOffScreenClean(function()
							self:kill()
							self.pid = nil
						end,"Kill "..pid)
end

function pidSink(self,sink)
	return function(chunk,err)
		if not chunk then
				sink(chunk,err)
                                return
                 end
		 -- Iterate over lines in a buffer, ignoring empty lines
                 -- (works for both DOS and Unix line ending conventions)
                 for line in string.gmatch(chunk,"[^\r\n]+") do
                                if not self.pid then
					local pid = line:match("PID=(%d+)")
					if pid then
						log:info("PID(",self.prog,")=",pid)
						self:setPid(pid)
					end
                                else
					if sink then sink(line,err) end
                                end
		end
	end
end

function readPid(self,sink,shell)
	local exec = shell and "" or "exec"
	self.prog = "echo PID=$$ && "..exec.." "..self.prog
	self:read(self:pidSink(sink))
end

function logSink(self,short,logf)
	local name = short or self.pid or self.prog
	local logger = logf or function(...) log:info(...) end
        return function(chunk,err)
		if chunk == nil then
			logger("exit ",name)
		else
			logger(name,": ",chunk)
		end
	end
end

function kill(self)
	if self.pid and  self._status ~= "dead" then
		local t = io.popen("kill "..self.killOpt..self.pid)
		log:warn("kill ",self.pid," ",self.prog)
		if t then t:close() end
	end
end

function setKillTerm(self)
	self.killOpt = "-9 "
end

function status(self)
	return self._status
end


function getfd(self)
	return self.fh:fileno()
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
