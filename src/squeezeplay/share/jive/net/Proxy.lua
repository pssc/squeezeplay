--[[
=head1 NAME

jive.net.Proxy - A Proxy for a TCP socket to send/recieve data using a NetworkThread
		 This implemts proxying for classes based on SockentTCP and Stream.
=head1 DESCRIPTION

Implements a list of global proxyies that are selected by untilzing classes
at runtime based on the connection details of ip, hostname and port.

=head1 SYNOPSIS


=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------

-- stuff we use
local _assert, ipairs, pairs, setmetatable, tostring, tonumber, type = _assert, ipairs, pairs, setmetatable, tostring, tonumber, type

local oo       = require("loop.simple")

local string   = require("string")
local table    = require("table")
local socket   = require("socket")

local DNS      = require("jive.net.DNS")
local Task     = require("jive.ui.Task")
local log      = require("jive.utils.log").logger("net.proxy")
local debug    = require("jive.utils.debug")


-- jive.net.proxy is a base class
module(..., oo.class)


-- state idx 1 global defaults
local proxies = { 
	{ port = 3128, server = "DEFAULTS" , no_proxy = { "127.0.0.1" } , active = true ,method = "HTTP_CONNECT" , timeout = 30 },
}

-- state - Big Switch
local proxy = false


-- Supported
local methods = { "HTTP_CONNECT" , "PF_SERVER" } 


-- *********************************************************************************************************

function __init(self, jnt, address, port, name)
	return oo.rawnew(self, {
                jnt = jnt,
		host = address,
		ip = DNS:isip(address) and address or nil,
		port = port,
                name = name or "",
		state = 0
        })
end

-- *********************************************************************************************************

function _getIdx(self,idx)
	if not idx then
           if self.idx then
		idx = self.idx
	   else
		idx = 1
	   end
	end

	if idx > table.getn(proxies) then
		log:error(self,":",debug.getinfo(1, "n").name,"(",idx,") > ",table.getn(proxies))
		idx = 1
	end

	return idx
end
	
-- *********************************************************************************************************

function addProxy(self,name)
	i = table.getn(proxies) + 1
	table.insert(proxies,i, { server = name } )

 	proxies[i].active = proxies[1].active
        proxies[i].port = nil
        proxies[i].timeout = nil
        proxies[i].no_proxy = {}
	proxies[i].method = nil

	return i
end

function removeProxy(self,i)
	if i != 1 then
		table.remove(proxies,i)
		setProxyState(proxy)
	end
end

-- *********************************************************************************************************


function setProxyState(tf)
        if tf and table.getn(proxies) > 1  then
            proxy = tf
        else
            proxy = false
        end
        return proxy
end

function getProxyState(class)
        return proxy
end

function getMethods(class) 
	return methods
end

function iterProxies(class)
  	local i = 0
	local n = table.getn(proxies)
	return function ()
		i = i + 1
		if i <= n then return i end
        end
end

-- *********************************************************************************************************

function setTimeOut(self,i,idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")
	idx = self:_getIdx(idx)
	--FIXME int check?
	proxies[idx].timeout = i
	return i
end

function setProxyIp(self,ip,idx)
	-- DNS:isip(address) FIXME?
	-- FIXME proxy.ip = ip
	idx = self:_getIdx(idx)
	proxies[idx].ip = ip
	self.proxy_ip = ip
	return ip
end

function setHostIp(self,ip)
	self.ip = ip
	return ip
end

--FIXME
function getProxyIp(self, idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")

        idx = self:_getIdx(idx)
	return self.proxy_ip and self.proxy_ip or proxies[idx].ip 
end

function getTimeOut(self,idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")
	idx = self:_getIdx(idx)
	return proxies[idx].timeout and proxies[idx].timeout or proxies[1].timeout
end

--WORKS
function setMethod(self,m,idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",m,",",idx,")")
	idx = self:_getIdx(idx)
	--FIXME CHECKS,
	proxies[idx].method = methods[m]
end

function getMethod(self,idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")
	idx = self:_getIdx(idx)
	m = proxies[idx].method and proxies[idx].method or proxies[1].method
	for k,v in ipairs(methods) do
		if v == m then
			return m , k
		end
	end
end

--FIXME nil
function getNoProxy(self, idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")
	idx = self:_getIdx(idx)
	return proxies[idx].no_proxy and proxies[idx].no_proxy or proxies[1].no_proxy
end

function setNoProxy(self,item,idx,j)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",item,",",idx,",",j,")")
        idx = self:_getIdx(idx)
	proxies[idx].no_proxy[j] = item
end

function addNoProxy(self,item,idx)
	i = table.getn(proxies[idx].no_proxy) + 1
	table.insert(proxies[idx].no_proxy,i,item )
	return i
end

function removeNoProxy(self,idx, j)
         table.remove(proxies[idx].no_proxy,j)
end

function getActive(self, idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")
	idx = self:_getIdx(idx)
	return proxies[idx].active 
end

function setActive(self,tf,idx)
	idx = self:_getIdx(idx)
	proxies[idx].active = tf
	return tf
end

function getProxyIpOrServer(self)
	return self.proxy_ip != nil and self.proxy_ip or self.proxy_server
end

--FIXME
function getProxyPort(self,idx)
	if idx then
		log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")")
		idx = self:_getIdx(idx)
		return proxies[idx].port and proxies[idx].port or proxies[1].port
	end
	return self.proxy_port
end

function setProxyPort(self,port,idx)
        idx = self:_getIdx(idx)
	log:debug(self,":",debug.getinfo(1, "n").name,"(",port,idx,")")
        proxies[idx].port = port
        return port
end

function getHostPort(self)
	return self.port
end

function getHostIp(self)
	return self.ip
end

function getProxyServer(self,idx)
	local server = self.proxy_server
	if type(idx) == "table" then 
		for k,v in pairs(idx) do
			log:debug(self,":",debug.getinfo(1, "n").name," [",k,"]=",v)
		end
	end
	if idx then
		server = proxies[idx].server 
	end
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")=",server)
	return server
end

function setProxyServer(self,server,idx)
        idx = self:_getIdx(idx)
	proxies[idx].server = server
	log:debug(self,":",debug.getinfo(1, "n").name,"(",idx,")=",server)
	return server
end

function getState(self)
	return self.state
end

-- *******************************************************************************************************

function isProxying(self)
	return self.proxied
end

function isConnected(self)
	return self.state == 0
end

function reset(self)
	if self.proxied then
		log:info(self,":reset()")
	else
		log:debug(self,":reset()")
	end
	self.proxy_ip = nil
	self.proxied = nil
end

function isProxied(self,test)
        if not proxy then
                return false
	end
	if self.proxied == true or self.proxied == false then
		return self.proxied
	end

        -- IDX 1 Gobal defults...
	local idx = 1
	local proxying = false
	while idx < table.getn(proxies) and proxying == false do
                idx = idx + 1
		if self:getActive(idx) then
                        proxying = true
                	for i,n in ipairs(self:getNoProxy(idx)) do
                        	if self.host and string.find(self.host,n) then	
                                        -- matched no proxy string
                   			if self:getMethod(idx) != 'PF_SERVER' then
                                           proxying = false
                                        end
                        	elseif self:getMethod(idx) == 'PF_SERVER' then
                                        proxying = false
                                elseif (n == self.ip) and (self:getMethod(idx) ~= 'PF_SERVER') then -- don't noporxy the proxy IP
					log:warn(self,":self denied own proxy[",n,":",self.host,"]=",self.ip)
                                	proxying = false
				else
					if n and not DNS:isip(n) then
						log:debug(self,":isProxied DNS:toip (",n,") ")
						local ip,err
						if Task:running() then
							ip,err = DNS:toip(tostring(n))
						else
							log:error(self,":isProxied DNS:toip no task for ",self.host," resolving ",n)
						end
						if not ip and err then
							log:warn(self,":isProxied DNS:toip (",n,") ",debug.view(err)," ",debug.traceback())
						elseif ip and string.find(self.host,ip) then
							proxying = false
						end
					end
				end
                	end
		end
        end 
        if not proxying then
	   log:info(self,":isProxied ",self.host," false")
	   if proxying == false then
		self.proxied = false
	   end
           return self.proxied
        end
        self.proxied = true
	self.state = 100


	-- Copy for this connection -- timeout ?
	self.proxy_method = self:getMethod(idx)
	self.proxy_server = self:getProxyServer(idx)
        if self.proxy_method == 'PF_SERVER' then
            self.state = -1
	    self.proxy_port = self:getProxyPort(idx) + self.port
        else
	    self.proxy_port = self:getProxyPort(idx) 
        end
	self.proxy_ip = self:getProxyIp(idx)
	self.idx = idx

	if log:isDebug() then
		for x,y in pairs(self) do
			log:debug(self,":isProxied proxy[",x,"]=",y)
		end
	end
	if not test or log:isDebug() then
		log:info(self,":isProxied proxied(", self.host, ":", self.port, ") via (",self.proxy_server,":",self.proxy_port,") method ",self.proxy_method )
	end

        return self.proxied
end



function step(self,data)
        log:debug(self,":step(",data,")")
	local send = nil
	local state = self.state
	local ip,err

            if not self:getProxyIp() and DNS:isip(self:getProxyServer()) then
               ip = self:getProxyServer()
            elseif not self:getProxyIp() then
               ip,err = DNS:toip(self:getProxyServer())
            end
	    if ip then
                self:setProxyIp(ip)
            end
        if self.proxy_method == 'PF_SERVER' then
            return nil,self.state
        end

	-- Write
	if data == nil then
           if self.proxy_method == 'HTTP_CONNECT' then
			if self.state == 100 then
			
				-- WRITE CONNECT
				send = string.format("CONNECT %s:%d HTTP/1.1\r\n\r\n", self.ip or self.ip and self.host , self.port)
                        	log:debug(self,":step: Proxy connect ",send)
				state = 200
			end
           end
	--read
	elseif self.proxied then
	   if self.proxy_method == 'HTTP_CONNECT' then 
		-- FIXME auth...
		if self.state == 200 and data then
			-- READ RESPONCE STATUS
                        local code = socket.skip(2, string.find(data, "HTTP/%d*%.%d* (%d%d%d)"))
                        log:debug(self,":step: Proxy status ",code)

                        if data then
                                self.statusCode = tonumber(code)
                                self.statusLine = data
				state = 201
                        else   
                                state = -1
                                log:warn(self,":step: Malformed Proxy status ",line)
                        end
		elseif self.state == 201 and data then
			-- READ RESPONCE HEADERS
                	if data ~= "" then
                                        local name, value = socket.skip(2, string.find(data, "^(.-):%s*(.*)"))
                                        if not (name and value) then
                                                send = ":step: Malformed Proxy reponse headers"
                                                log:warn(self,send)
                                        else
                                        	log:debug(self,":step: Proxy header ",line)
					end
					-- FIXME stash?
                        else   
                                        if self.statusCode ~= 200 then
                                                log:error(self," Proxy(",self.ip or self.ip and self.host,":",self.port,") Error status ",self.statusLine)
                                        	state = -2
					end	
					state = 0
                        		log:debug(self, ":step: proxy connect done")
                        end

		end
	   end
	end

	self.send = send
	self.state = state
        log:debug(self,":step() = ",state, ",",send)
	return state, send
end

function getSettings()
	return proxies
end

function setSettings(settings)
	proxies = settings
end

