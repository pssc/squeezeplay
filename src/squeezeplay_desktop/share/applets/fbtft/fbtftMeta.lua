local oo            = require("loop.simple")
local os            = require("os")
local io            = require("io")
local string        = require("string")

local table         = require("jive.utils.table")

local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")

local appletManager = appletManager

local jiveMain, jnt, string, tonumber, tostring = jiveMain, jnt, string, tonumber, tostring

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
        return 1, 1
end


function defaultSettings(meta)
        return {
		fb = nil,
		active = true,
		device = nil,
        }
end

function registerApplet(meta)

	-- Detect adafruitrt28
	f = io.open("/sys/class/spi_master/spi0/spi0.1/stmpe-gpio.0/gpio/gpiochip250/base") 
	if f then
        	f:close()
		local i = 0 
		local gap = 4
		f = io.open("/sys/class/graphics/fb"..i.."/name")
		while i < gap do
		    local l = f and f:lines() or function(...) return nil end
		    for line in l do 
			-- readline
			-- match
			-- Detect fbtft
			if(string.match(line,"fb_ili9340")) then
				local settings = meta:getSettings()
				local j = 0
        			while appletManager:hasService("setBrightness"..j) do
					j = j + 1 
				end
				if (settings['active']) then
					meta:registerService("setBrightness"..j)
					settings['fb'] = i
					settings['device'] = line
				end
				-- Add menu for enable.
				jiveMain:addItem(meta:menuItem('appletFBTFTOptions', 'advancedSettings', meta:string("APPLET_NAME"),
					function(self, menuItem)
                  	   			local window = Window("text_list", menuItem.text)
                     				local menu = SimpleMenu("menu")
                     				window:addWidget(menu)

						menu:addItem({
							text = self:string("ACTIVE"),
                 					style = 'item_choice',
                 					check = Checkbox("checkbox",
                         					function(object, isSelected)
                                  					self:getSettings()["active"] = isSelected
                                  					self:storeSettings()
                                  					--self:_restart()
                                  				end,
                                  				self:getSettings()["active"]
							),
						})
						self:tieAndShowWindow(window)
					end
				))
				log:info("Dectected adafruitrt28 setBrightness",j," fb=",i)
			end
		    end
		    i=i+1
		    if f then
			f:close()
			gap = gap + 1
		    end
		    f = io.open("/sys/class/graphics/fb"..i.."/name")
		end
        end

	-- Detect adafruitrt35
end

