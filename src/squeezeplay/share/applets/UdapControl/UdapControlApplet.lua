--[[
Methods to respond to the following udap requests:
 - discover
 - get_ip
 - set_ip - not implmented
 - reset - not implmented
 - get_data - not implmented
 - set_data - limited
 - 	set server address
 - 	set slimserver address
 - advanced discover
 - no implmentation
 - get_uuid
 - set_volume
 - pause
 - get_pin
 - no implmentation
 - fwd
 - rev
 - preset
 - set_power
--]]

local pairs, tonumber, tostring = pairs, tonumber, tostring

-- stuff we use
local oo            = require("loop.simple")
local string        = require("string")
local table         = require("jive.utils.table")

local Applet        = require("jive.Applet")
local System        = require("jive.System")

local Framework     = require("jive.ui.Framework")
local Timer         = require("jive.ui.Timer")

local SocketUdp     = require("jive.net.SocketUdp")
local Udap          = require("jive.net.Udap")
local Player        = require("jive.slim.Player")
local hasNetworking, Networking = pcall(require, "jive.net.Networking")

local debug         = require("jive.utils.debug")

local jnt           = jnt
local jiveMain      = jiveMain
local appletManager = appletManager


module(..., Framework.constants)
oo.class(_M, Applet)


-- udap packet received
function _udapSink( self, chunk, err)

	if chunk == nil then
		log:error("Sink nil Chunk")
		return -- ignore errors
	end

	log:debug("udapSink chunk ip: ", chunk.ip ," port: ", chunk.port, " data len: ", #chunk.data)
	local pkt = Udap.parseUdap( chunk.data)
	log:debug("udapSink {", Udap.tostringUdap(pkt," / "),"}")

	if pkt.uapMethod == nil then
		log:error("udapMethod nil")
		return
	end

	-- We are not interested in udap responses here - only requests from other devices
	if pkt.udapFlag ~= 0x01 then
		log:debug("UDAP: not a request - discard packet")
		return
	end

	local ownMacAddress = System:getMacAddress() -- FIXME which one?
	ownMacAddress = string.gsub(ownMacAddress, "[^%x]", "")

	-- Discard packets from ourself
	if ownMacAddress == pkt.source then
		log:debug("UDAP: self origined packet - discard packet")
		self.ip = chunk.ip
		return
	end

	-- There are some requests we can and will handle without a current player
	-- but we do need a LocalPlayer
	local localPlayer = Player:getLocalPlayer()

	if localPlayer and pkt.uapMethod == "get_pin" and localPlayer:getSlimServer() then
		-- Provide a PIN to register this player with an account, if not already registered
		local sink = function(result, err)
			if result.error then
				log:debug(result.error)
			end

			-- Maybe SN will provide a nonce in the response that needs to be signed
			-- with the player's UUID as a verifier. In this case sign the nonce
			-- and append it to the value, separated with a colon.

			local packet = Udap.createGetPinResponse(ownMacAddress, pkt.source, pkt.seqno,
				(result.data and result.data.result and result.data.result ~= 0) and result.data.result or nil,
				localPlayer:getName())
			self.udap:send(function() return packet end, chunk.ip, chunk.port)
		end

		localPlayer:getSlimServer():request(sink, localPlayer:getId(), {'service', 'get_nonce'})

		return

	elseif localPlayer and pkt.dest == ownMacAddress then
		if pkt.uapMethod and log:isDebug() then
			log:debug("UDAP - ",pkt.uapMethod," request received - ",localPlayer)
		end

		if pkt.uapMethod == "get_ip" then
			local ip_address, ip_subnet
			local ifObj = hasNetworking and Networking:activeInterface()
		
			if ifObj then
				ip_address, ip_subnet = ifObj:getIPAddressAndSubnet()
				if not ip_address then                                    
					log:warn('Cannot get ip_address for active network interface ', ifObj)
				end                                                                                       
			else
				log:warn('Cannot find active network interface')
			end
			if not ip_address and self.ip then
				local a1, b1, c1, d1 = string.match(self.ip,"^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$")
				if ( d1 ~= nil ) then
					-- FIXME ip pack and upack in udap?
					ip_address = string.char(a1) .. string.char(b1) .. string.char(c1) .. string.char(d1)
				end
			end
			
			if not ip_address then return end                                
			
			local packet = Udap.createGetIpResponse(ownMacAddress, pkt.source, pkt.seqno, ip_address)
			self.udap:send(function()
						log:debug("UDAP - ",pkt.uapMethod," sending answer...",table.concat({string.byte(ip_address, 1, 4)},"."))
						return packet
						--end, "255.255.255.255", chunk.port)
						end, chunk.ip, chunk.port)
			return
			
		elseif pkt.uapMethod == "get_data" then
			return
		elseif pkt.uapMethod == "pause" then
			localPlayer:pause(false, true)
			return
			
		elseif pkt.uapMethod == "set_volume" then
			log:debug("UDAP - set_volume request received: seq=", pkt.data.seq, ", vol=", pkt.data.octet)
			-- Sets local volume only SC updated from controller?
			localPlayer:volumeFromController(pkt.data.octet, pkt.source, pkt.data.seq)
			return
			
		elseif pkt.uapMethod == "fwd" then
			localPlayer:fwd()
			return

		elseif pkt.uapMethod == "rev" then
			localPlayer:rew()
			return

		elseif pkt.uapMethod == "preset" then
			-- Seq not used
			localPlayer:presetPress(pkt.data.octet)
			return

		elseif pkt.uapMethod == "set_power" then
			-- Seq not used
			-- Actions?
			if System:hasSoftPower() then
				jiveMain:setSoftPowerState(pkt.data.octet == 0 and "off" or "on")
			end
			--localPlayer:setPower(pkt.data.octet, pkt.data.seq, false)
			return

		else
			log:debug("UDAP - ",pkt.uapMethod, "unknown method - ",localPlayer)
		end
	end

	local acceptPacket = false

	-- Only accept discover queries (length 27)
	if pkt.uapMethod == "discover" and #chunk.data == 27 then
		acceptPacket = true

	-- Only accept advanced discover queries (length 27)
	elseif pkt.uapMethod == "adv_discover" and #chunk.data == 27 then
		acceptPacket = true

	-- Only accept set data packets with our mac address as target
	elseif pkt.uapMethod == "set_data" and pkt.dest == ownMacAddress then
		if pkt.data["server_address"] then
			acceptPacket = true
		elseif pkt.data["slimserver_address"] then
			acceptPacket = true
		end

	-- Only accept get uuid packets with our mac address as target
	elseif pkt.uapMethod == "get_uuid" and pkt.dest == ownMacAddress then
		acceptPacket = true
	end

	-- Check for supported methods
	if not acceptPacket then
		log:debug("UDAP: not supported method - discard packet")
		return
	end

	local currentPlayer = appletManager:callService("getCurrentPlayer")

	-- Check if there is a current player
	if not currentPlayer then
		log:debug("UDAP: no current player - discard packet")
		return
	end

	log:debug("UDAP: curPlayer: ", currentPlayer, " local: ", currentPlayer:isLocal(), " connected: ", currentPlayer:isConnected())

	-- Check if current player is local
	if not currentPlayer:isLocal() then
		log:debug("UDAP: current player is not local - discard packet")
		return
	end

	-- Check if local player is connected
	if currentPlayer:isConnected() and pkt.uapMethod != "adv_discover" then
		log:debug("UDAP: current local player is connected - discard packet")
		return
	end

	local deviceName = currentPlayer:getName()
	local deviceModel = currentPlayer:getModel()

	log:debug("UDAP - ",pkt.uapMethod," request received")
	if pkt.uapMethod == "discover" then

		local packet = Udap.createDiscoverResponse(ownMacAddress, pkt.source, pkt.seqno, deviceName, deviceModel)
		self.udap:send(function() log:debug("UDAP - ",pkt.uapMethod," sending answer...") return packet end, "255.255.255.255", chunk.port)

	elseif pkt.uapMethod == "adv_discover" then

		local deviceId = currentPlayer:getDeviceType()
		deviceId = tostring(deviceId)

		local deviceStatus = "wait_slimserver"

		if currentPlayer:isConnected() then
			deviceStatus = "connected"
		end

		local packet = Udap.createAdvancedDiscoverResponse(ownMacAddress, pkt.source, pkt.seqno, deviceName,
								   deviceModel, deviceId, deviceStatus)
		self.udap:send(function() log:debug("UDAP - ",pkt.uapMethod," sending answer...") return packet end, "255.255.255.255", chunk.port)

	elseif pkt.uapMethod == "set_data" then
		if pkt.data["server_address"] and pkt.data["slimserver_address"] then
			local serverip = pkt.data["server_address"]
			local a1, b1, c1, d1 = string.byte(serverip, 1, 4)

			serverip = (a1 << 24) + (b1 << 16) + (c1 << 8) + d1

			local slimserverip = pkt.data["slimserver_address"]
			local a2, b2, c2, d2 = string.byte(slimserverip, 1, 4)

			slimserverip = (a2 << 24) + (b2 << 16) + (c2 << 8) + d2
			currentPlayer:connectIp(serverip, slimserverip)

		elseif pkt.data["server_address"] then
			local serverip = pkt.data["server_address"]
			local a1, b1, c1, d1 = string.byte(serverip, 1, 4)

			serverip = (a1 << 24) + (b1 << 16) + (c1 << 8) + d1
			currentPlayer:connectIp(serverip)

		elseif pkt.data["slimserver_address"] then
			local slimserverip = pkt.data["slimserver_address"]
			local a2, b2, c2, d2 = string.byte(slimserverip, 1, 4)

			slimserverip = (a2 << 24) + (b2 << 16) + (c2 << 8) + d2

			currentPlayer:connectIp(0, slimserverip)
		end

		local packet = Udap.createSetDataResponse(ownMacAddress, pkt.source, pkt.seqno)
		self.udap:send(function() log:debug("UDAP - ",pkt.uapMethod," sending answer...") return packet end, "255.255.255.255", chunk.port)

	elseif pkt.uapMethod == "get_uuid" then

		local packet = Udap.createGetUUIDResponse(ownMacAddress, pkt.source, pkt.seqno)
		self.udap:send(function() log:debug("UDAP - ",pkt.uapMethod," sending answer...") return packet end, "255.255.255.255", chunk.port)

	else
		log:debug("UDAP - ",pkt.uapMethod, "unknown method")
	end
end


-- init
-- Initializes the applet
function __init(self, ...)

	-- init superclass
	local obj = oo.rawnew(self, Applet(...))

	-- udap socket
	obj.udap = Udap(jnt, 
		function(chunk, err)
			obj:_udapSink(chunk, err)
		end)

	return obj
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

