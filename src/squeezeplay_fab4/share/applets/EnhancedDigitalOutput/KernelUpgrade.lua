--[[

Subclass of SetupFirmareUpgrade.UpgradeUBI to only update the kernel volume

--]]

local assert, error, pairs, pcall, tonumber, type, string = assert, error, pairs, pcall, tonumber, type, string

local oo          = require("loop.simple")
local io          = require("io")
local Framework   = require("jive.ui.Framework")
local Task        = require("jive.ui.Task")
local UpgradeUBI  = require("applets.SetupFirmwareUpgrade.UpgradeUBI")
local debug       = require("jive.utils.debug")

local jnt = jnt
local appletManager = appletManager

module(..., oo.class)
oo.class(_M, UpgradeUBI)


function start(self, url, md5, callback)
	self._url = url
	self._md5 = md5
	self._callback = callback

	self:parseMtd()

	return Task:pcall(_upgrade, self)
end


function _upgrade(self)
	self._callback(false, "UPDATE_DOWNLOAD", "")

	-- parse the board revision
	local t, err = self:parseCpuInfo()
	if not t then
		log:warn("parseCpuInfo failed")
		return nil, err
	end

	-- remove any failed upgrades
	self:rmvol("kernel_upg")

	-- wait for udev
	self:udevtrigger()

	-- write new volume contents
	self:download()

	self._callback(false, "UPDATE_VERIFY")

	-- check the correct ubi volumes exist
	local oldvol = self:parseUbi()
	assert(oldvol.kernel_upg)

	-- verify new volumes
	self:parseMtd()
	self.verifyBytes = 0
	self.verifySize = self._size["kernel_upg"]

	-- verify md5 in zip with one passed by caller and validate volume
	local checksum = {}
	for md5, file in string.gmatch(self._checksum, "(%x+)%s+([^%s]+)") do	
		 checksum[file] = md5
	end
	assert(self._md5 == checksum[self._file["kernel_upg"]])
	self:checksum("kernel_upg")

	-- remove old image
	self:rmvol("kernel_bak")

	-- automically rename volumes
	self:renamevol({
		["kernel"] = "kernel_bak",
		["kernel_upg"] = "kernel",
	})

	-- check the volume rename worked
	local newvol = self:parseUbi()
	assert(newvol.kernel)
	assert(newvol.kernel ~= oldvol.kernel)

	-- reboot
	self._callback(true, "UPDATE_REBOOT")

	-- two second delay
	local t = Framework:getTicks()
	while (t + 2000) > Framework:getTicks() do
		Task:yield(true)
	end

	appletManager:callService("reboot")

	return true
end

