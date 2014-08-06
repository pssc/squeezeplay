
--[[
=head1 NAME

jive.net.SocketTcp - A TCP socket to send/recieve data using a NetworkThread

=head1 DESCRIPTION

Implements a tcp socket that sends/receive data using a NetworkThread. 
jive.net.SocketTcp is a subclass of L<jive.net.Socket> and therefore inherits
its methods.
This class is mainly designed as a superclass for L<jive.net.SocketHttp> and
therefore is not fully useful as is.

=head1 SYNOPSIS

 -- create a jive.net.SocketTcp
 local mySocket = jive.net.SocketTcp(jnt, "192.168.1.1", 9090, "cli")

 -- print the connected state
 if mySocket:connected() then
   print(tostring(mySocket) .. " is connected")
 end

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------

-- stuff we use
local _assert, ipairs, pairs, setmetatable, tostring, tonumber, type = _assert, ipairs, pairs, setmetatable, tostring, tonumber, type

local debug    = require("debug")

local socket   = require("socket")
local oo       = require("loop.simple")

local Socket   = require("jive.net.Socket")
local ltn12       = require("ltn12")

local log      = require("jive.utils.log").logger("net.http")

local string      = require("string")
local table       = require("table")

local Proxy	= require("jive.net.Proxy")
local Task        = require("jive.ui.Task")



-- jive.net.SocketTcp is a subclass of jive.net.Socket
module(...)
oo.class(_M, Socket)


--[[

=head2 jive.net.SocketTcp(jnt, address, port, name)

Creates a TCP/IP socket named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "". I<address> and I<port> are the hostname/IP address and port to 
send/receive data from/to.
Must be called by subclasses.

=cut
--]]
function __init(self, jnt, address, port, name)
	log:debug("SocketTcp:__init(", name, ", ", address, ", ", port, ")") --FIXME

	_assert(address, "Cannot create SocketTcp without hostname/ip address - " .. debug.traceback())
	_assert(port, "Cannot create SocketTcp without port")

	local obj = oo.rawnew(self, Socket(jnt, name))

	obj.t_tcp = {
		address = address,
		port = port,
		connected = false,
		proxy = Proxy(jnt, address, port, name)
	}

	return obj
end


-- t_connect
-- connects our socket
function t_connect(self)
	log:debug(self, ":t_connect()") 
	
	-- create a tcp socket
	self.t_sock = socket.tcp()

	-- set no timeout ie non blocking...
	self.t_sock:settimeout(0)

	if self.t_tcp.proxy:isProxied() then
	   	self.t_tcp.address = self.t_tcp.proxy:getProxyIpOrServer()
	   	self.t_tcp.port = self.t_tcp.proxy:getProxyPort()
	end

	local err = socket.skip(1, self.t_sock:connect(self.t_tcp.address, self.t_tcp.port))
        
	if err and err ~= "timeout" then
		log:error(self,":t_connect: ", err)
		return nil, err
	end
	
	if self.t_tcp.proxy:isProxied() then
		-- Do proxy negotiation
		self.t_addWrite(self,function(...) log:debug(self," Proxy W pump") end,self.t_tcp.proxy:getTimeOut())
		self.t_addRead(self,function(...) log:debug(self," Proxy R pump") end,self.t_tcp.proxy:getTimeOut())
	end
	return 1
end


-- t_setConnected
-- changes the connected state. Mutexed because main thread clients might care about this status
function t_setConnected(self, state)
	log:debug(self, ":t_setConnected(", state, ")") --FIXME

	local stcp = self.t_tcp

	if state ~= stcp.connected then
		stcp.connected = state
	end
end


-- t_getConnected
-- returns the connected state, network thread side (i.e. safe, no mutex)
function t_getConnected(self)
	return self.t_tcp.connected
end


-- free
-- frees our socket
function free(self)
	--log:debug(self, ":free()")
	
	-- we store nothing, just call superclass
	Socket.free(self)
end


-- close
-- closes our socket
function close(self)
	--log:debug(self, ":close()")
	
	self:t_setConnected(false)
	
	Socket.close(self)
end


-- t_getIpPort
-- returns the Address and port
function t_getAddressPort(self)
	if self.proxyIsProxied() then
	   return self.t_tcp.proxy:getHostIp(), self.t_tcp.proxy:getHostPort()
	else
	   return self.t_tcp.address, self.t_tcp.port
	end
end


--[[

=head2 jive.net.SocketTcp:connected()

Returns the connected state of the socket. This is mutexed
to enable querying the state from the main thread while operations
on the socket occur network thread-side.

=cut
--]]
function connected(self)

	local connected = self.t_tcp.connected
	
	--log:debug(self, ":connected() = ", connected)
	return connected
end


--[[

=head2 tostring(aSocket)

if I<aSocket> is a L<jive.net.SocketTcp>, prints
 SocketTcp {name}

=cut
--]]
function __tostring(self)
	return "SocketTcp {" .. tostring(self.jsName) .. "}"
end


-- Overrides to manage connected state and proxy connection

-- t_add/read/write
function t_addRead(self, pump, timeout)
	local newpump = function(...)
		local ps = self.t_tcp.proxy:getState()
		if ps > 0 then
		  local source = function()
                                local line, err, partial = self.t_sock:receive('*l', partial)
                                while partial do
                                    line, err, partial = self.t_sock:receive('*l', partial)
                                    if err and err ~= 'timeout' then -- nonblocking...
                                        log:error(self, ":_addRead:proxy read status:", err)
                                        self:close(err)
                                        return nil, err
                                    else
                                        log:debug(self, ":_addRead:proxy read status:", err)
                                    end
                                    _, networkErr = Task:yield(false)

                                    if networkErr then
                                                log:warn(self, ":_addRead: yeild on read error: ", networkErr)
                                        	self:close(networkErr)
						return line, networkErr
                                    end
                                end

                                log:debug(self,":_addRead:source=",line," err=",err)
                                return line, err
                  end
		 
                  while ps > 0 do
			line, err = source()
			if err then
			   log:error(err)
			   self:close(err)
			   return
			end
			ps, data = self.t_tcp.proxy:step(line)
	  	  end
                  if ps == 0 then
		  -- Yeild to write real request
                                    _, networkErr = Task:yield(false)

                                    if networkErr then
                                                log:warn(self, ":_addRead: yeild for write on connect error: ", networkErr)
                                        	self:close(networkErr)
						return line,  networkErr
                                    end
                  end
		end

		if not self.t_tcp.connected then self:t_setConnected(true) end
		pump(...)
	end
	Socket.t_addRead(self, newpump, timeout)
end

function t_addWrite(self, pump, timeout)
	local newpump = function(...)
		local ps = self.t_tcp.proxy:getState()
		if ps > 0 then 
		   local sink = function(data)
			       local err = socket.skip(1, self.t_sock:send(data))

                		if err then
                      			log:error(self, ":t_connect: proxy send: ", data, err)
                       			self:close(err)
                      			return 
				end
                                log:debug(self,":_addWrite:source=",line," err=",err)
		   end

		   while ps > 0 do
			ps, data = self.t_tcp.proxy:step(nil)
			if data then
				sink(data)
				if err then
					log:error(err)
					self:close(err)
					return
				end
				
			elseif ps > 0 then -- >=? fix for tunnel atm
			  _, networkErr = Task:yield(false)
                          if networkErr then
                                      log:warn(self, ":_addWite: yeild on write error: ", networkErr)
                                      self:close()
                          end
			end
		   end
		end
		if not self.t_tcp.connected then self:t_setConnected(true) end
		pump(...)
	end
	Socket.t_addWrite(self, newpump, timeout)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

