
--[[
=head1 NAME

jive.AppletUI - The applets with a meta settings based UI class.

=head1 DESCRIPTION

jive.Applet is the base class for all Jive applets. In Jive,
applets are very flexible in the methods they implement; this
class implements a very simple framework to manage localization,
settings and memory management.

=head1 FUNCTIONS

=cut
--]]

local coroutine, package, pairs, type = coroutine, package, pairs, type
local tostring, assert, ipairs = tostring, assert, ipairs

local jiveMain         = jiveMain
local appletManager    = appletManager
local jnt              = jnt

local oo               = require("loop.simple")
local os 	       = require("os")

local Applet           = require("jive.Applet")

local Framework        = require("jive.ui.Framework")
local Textinput        = require("jive.ui.Textinput")
local Textarea         = require("jive.ui.Textarea")
local Checkbox         = require("jive.ui.Checkbox")
local Keyboard         = require("jive.ui.Keyboard")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Window           = require("jive.ui.Window")
local Group            = require("jive.ui.Group")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")

local RequestHttp      = require("jive.net.RequestHttp")
local SocketHttp       = require("jive.net.SocketHttp")

local log              = require("jive.utils.log").logger("applet.ui")
local debug            = require("jive.utils.debug")
local fun	       = require("jive.utils.fun")
local string           = require("jive.utils.string")
local lfs              = require("jive.utils.lfs")

local SlimServer       = require("jive.slim.SlimServer")

module(..., Framework.constants)
oo.class(_M, Applet)

local map = fun.map

--[[

=head2 self:settingMenuCheckBox(self,menu,key,f)()

 self:settingMenuCheckBox(menu,"cec_toggle")

=cut
--]]
function metaMenuToggle(self,menu,key,f)
	local i = {
                 text = self:string(self:metaClassString(key).."_"..string.upper(key)),
                 style = 'item_choice',
                 check = Checkbox("checkbox",
                            function(object, isSelected)
                                  if isSelected ~= self:getMetaValue(key) then
				  	self:setMetaValue(key,isSelected)
                                  	if f and type(f) == "function" then f(isSelected) end
                                  end
                             end,
                             self:getMetaValue(key)
                         ),
        }
	
	if menu then
		menu:addItem(i)
	end
	return i
end


function metaMenuImage(self,menu,key)
	local text = self:getSettingsMeta()[key].text and self:getSettingsMeta()[key].text or self:string(self:metaClassString(key).."_"..string.upper(key))
	log:info(text)
	-- FIXME
        local i = {
               text = text,
               callback = function(event, mI)
                                self:imageWindow(mI,key)
                        end
        }

	if menu then
                menu:addItem(i)
        end
        return i
end

function imageWindow(self, menuItem, key)
        -- default is different based or skin 
        local sm = self:getSettingsMeta()[key]
        if not sm or sm['limit'] ~= 'image' then
                log:error('invalid meta key ',key)
        end
        local image = self:getSettings()[key]

	log:debug("imageWindow ", key, " = ", image, " ",#sm.images)

        local window = Window("text_list", menuItem.text, 'settingstitle')
        local menu = SimpleMenu('menu')

        menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)
        self:_imageMenu(menu, image, key)
        window:addWidget(menu)
        window:addListener(EVENT_WINDOW_POP,
                function(event)
			log:debug("Image window ",event:tostring())
                        -- Restore backgound
			appletManager:callService('showBackground')
			-- Clear downloads
                        sm.download = {}
			sm.focus = nil
                end
        )
        window:addListener(EVENT_WINDOW_INACTIVE,
		function(event)
			log:debug("Image window ",event:tostring())
                        -- Restore backgound
			appletManager:callService('showBackground')
		end
	)
	window:addListener(EVENT_WINDOW_ACTIVE,
		function(event)
			log:debug("Image window ",event:tostring())
			if sm.focus then
				appletManager:callService('showBackground',sm.focus)
			end
		end
	)
        self:tieAndShowWindow(window)
        return window
end


function _imageMenu(self, menu, image, key )
        local screenWidth, screenHeight = Framework:getScreenSize()
	local sm = self:getSettingsMeta()[key]
        local imageType = sm.imageType or 'images'
        local download_path = sm.paths.download
	local unfiltered = sm.unfiltered
        local group = RadioGroup()
        local images = {}

	-- FIXME dict from serivce... and data call on server connect...
	-- seperate out data and prsentation...

        -- read all files in the images / directory and into images
        -- this step is done first so images aren't read twice, 
        -- once from source area and once from build area
	log:debug("Searching ",imageType)
        for img in self:readdir(imageType) do -- FIXME type
		log:debug("trying ", img)
                _decodeImageFilename(img, images, screenWidth, screenHeight, unfiltered)
        end

        -- read files in the userpath too
	log:debug("Searching Paths ",download_path)
        for img in lfs.dir(download_path) do -- FIXME meta
		log:debug("Search trying ", img)
                _decodeImageFilename(download_path .. img, images, screenWidth, screenHeight, unfiltered)
        end

	-- FIXME search paths do we need?
	log:debug("Meta images ",#sm.images)
	for k,img in pairs(sm.images) do
		log:debug("Meta trying ", k, "=", img)
		_decodeImageFilename(img, images, screenWidth, screenHeight, unfiltered)
	end

	-- FIXME dont work with one item...
        for name, details in pairs(images) do
                log:debug(name, "|", details.token)

                local title = self:string(details.token)
                if title == details.token then
                        title = details.name 
		end
                if details.res then
                        title = tostring(title).." "..details.res
                end

                menu:addItem({
                        -- anything local goes to the top 
                        -- (i.e., higher precendence than SC-delivered custom wallpaper)
                        weight = 1,
                        text = title,
                        style = 'item_choice',
                        sound = "WINDOWSHOW",
                        check = RadioButton("radio",
                                group,
                                function()
					self:setMetaValue(key,details.fullpath)
                                end,
                                image == details.fullpath
                        ),
                        focusGained = function(event)
				appletManager:callService("showBackground",details.fullpath)
				sm.focus = details.fullpath
                        end
                })

        end

        -- get list of downloadable wallpapers from the server
	local server = SlimServer:getCurrentServer()
        if server then
        	local screen = screenWidth .. "x" .. screenHeight
                log:debug("found server - requesting ",imageType ," list ", screen)

                server:userRequest(
                        function(chunk, err)
                                if err then
                                        log:debug(err)
                                elseif chunk and chunk.data then
                                        self:_serverImageWindowSink(server,menu,image,key,group,chunk.data)
                                end
                        end,
                        false,
                        screen and { "jive"..imageType, "target:" .. screen } or { "jive"..imageType }
                )
        end

        -- jump to selected item
        for x, item in ipairs(menu:getItems()) do
                if item.check:isSelected() then
                        menu:setSelectedIndex(x)
                        break
                end
        end
	-- FIXME focused gained issue with one item... and not Selected on dl object?
end



function _decodeImageFilename(img, images, screenWidth, screenHeight, unflitered)
        -- split the fullpath into a table on /
        local fullpath = string.split('/', img)
        -- the filename is the last element in the fullpath table
        local leafname = fullpath[#fullpath]
        -- split on the period to get filename and filesuffix
        local parts = string.split("%.", leafname)

        -- if the suffix represents an image format (see _isImg() method), decode and add list
        if _isImg(parts[2]) then
                -- token is represented by uppercase of the filename
                local splitFurther = string.split("_", parts[1])
                local stringToken = string.upper(splitFurther[#splitFurther])
                local patternMatch = string.upper(parts[1])
                local pattern = nil
                local res = nil
		log:debug(name," ",stringToken," ",patternMatch)
		-- Note pattern string is uppered!
                if unflitered then 
                        local x,y = string.match(patternMatch,"(%d+)X(%d+)_")
                        if x and y then
                                res = x.."x"..y
                        end
			log:debug("Unfitered ",patternMatch," ",res)
			-- Token string global? FIXME
                else
			-- fallback non scaled option ie x_black.png...
			pattern = "^X_"
			if not string.match(patternMatch, pattern) then
                        	pattern = screenWidth..'X'..screenHeight..'_'
			else
				res = "∞"
			end
                end

                if not images[leafname] and
                        ( not pattern or ( pattern and string.match(patternMatch, pattern) ) ) then
			if not unflitered then
				for k,v in pairs(images) do
					if v.token == stringToken then
						if res then
							return images
						else
							images[k] = nil
						end
					end
				end
			end
                        images[leafname] = {
                                token    = stringToken,
                                name     = splitFurther[#splitFurther],
                                res      = res,
                                suffix   = parts[2],
                                fullpath = img,
                        }
			log:debug(debug.view(images[leafname]))
                end
        end
        return images
end


-- FIXME lfs?
-- returns true if suffix string is for an image format file extention
function _isImg(suffix)
        if suffix == 'png' or suffix == 'jpg' or suffix == 'gif' or suffix == 'bmp' then
                return true
        end

        return false
end


-- FIXME spearate presenation and data gathering
function _serverImageWindowSink(self, server, menu, image, key, group, data)
	log:debug("_serverImageWindowSink ",key)
	local ip, port = server:getIpPort()
	local sm = self:getSettingsMeta()[key]
	assert(sm.limit == "image")
        local download = sm.download
        local current = self:getSettings()[key]

	if data.item_loop then
		for _,entry in pairs(data.item_loop) do
			local url
			if entry.relurl then
				url = 'http://' .. ip .. ':' .. port .. entry.relurl
			else
				url = entry.url
			end
			log:debug("remote image: ", entry.title, " ", url)
			if string.match(url,"http") then
				menu:addItem({
					weight = 50,
					text = entry.title,
					style = 'item_choice',
					check = RadioButton("radio",
						group,
						function()
							if download[url] then
								self:showBackground(url, currentPlayerId)
								self:setMetaValue(key,url)
							end
						end,
						current == url
					),
					focusGained = function()
						if download[url] and download[url] ~= "fetch" and download[url] ~= "fetchset" then
							log:info("using cached: ", url, "=", type(download[url]))
							self:showBackground(url, currentPlayerId)
						else
							self:_fetchFile(url, key,
								function(set)
									if set then
										log:debug("set")
										self:showBackground(url, currentPlayerId)
										self:setMetaValue(key, url)
									else
										log:debug("fetch")
										self:showBackground(url, currentPlayerId)
									end
								end 
							)
						end
						sm.focus = url
					end
				})
                        end
                        if current == url then
				-- FIXME assumes last item and only one dl url ??
                                menu:setSelectedIndex(menu:numItems() - 1)
                        end
                end
        end
end


function _fetchFile(self, url, key, callback)
        local last = url
        local download = self:getSettingsMeta()[key].download

        if download[url] then
                log:warn("already fetching ", url, " not fetching again")
                return
        else
                log:info("fetching background: ", url)
        end
        download[url] = "fetch"

        -- FIXME
        -- need something here to constrain size of self.download

        local req = RequestHttp(
                function(chunk, err)
                        if err then
                                log:warn("error fetching background: ", url)
                                download[url] = nil
                        end
                        local state = download[url]
                        if chunk and (state == "fetch" or state == "fetchset") then
                                log:info("fetched background: ", url)
                                download[url] = chunk

                                if url == last then
                                        callback(state == "fetchset")
                                end
                        end
                end,
                'GET',
                url
        )

        local uri  = req:getURI()
        local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
        http:fetch(req)
end


-- Service getMeta
function getEnv(self,key,refresh)
	-- check class env?
	local mt = self:getSettingsMeta()
        if mt and mt[key] and mt[key].class and mt[key].class == "env" then
		return self:getMetaValue(key,refresh)
	end
	return nil
end


function getMetaClassEnv(self,key,refresh)
        local mt = self:getSettingsMeta()
        if mt[key] then
		if not mt[key].server then
			return appletManager:callService("getEnv",key,refresh)
		else
                	local st = self:getSettings()
                	if refresh then
                        	st.env[key] = os.getenv(key)
                	end
			log:debug("getMetaClassEnv ",key,"(",refresh,")=",st.env[key])
			return st.env[key]
		end
        end
        return nil
end


--FIXME if not persist what if settings are different to current env...
function readEnv(self)
        local st = self:getSettings()
        local mt = self:getSettingsMeta()
        for key,v in pairs(mt) do
                if v.class == "env" then
                        st.env[key] = os.getenv(key)
                end
        end
end


-- Service
function unregisterEnv(self,key)
        local st = self:getSettings()
	if st.env then
		st.env[key] = nil
	end
	-- loop
	local mt = self:getSettingsMeta()
	local meta = mt[key] and true or false
        self:unregisterSettingsMeta(key)
	if meta then
		appletManager:callService("unregisterEnv",key)
	end

end

--Service
function registerEnv(self,key,t,caller)
        assert(type(t)=="table")
        t.class = "env"
	if caller == self then
		t.client = true
		appletManager:callService("registerEnv",key,t,self)	
	elseif not t.server then
		t = fun.uses(t, { server = true, client = false } )
	end
	log:warn("registerEnv ",key," caller=",caller==self," server=",t['server'])

        self:registerSettingsMeta(key,t)
	return self:getMetaValue(key,true)
end


function setMetaClassEnv(self,key,value)
        local st = self:getSettings()
        local mt = self:getSettingsMeta()
        if mt[key] and mt[key].class == "env" then
		if not mt[key].server then
			value = appletManager:callService("setEnv",key,value)
		else
			log:warn("setMetaClassEnv ",key,"=",value)
                	st['env'][key] = value
                	st['env_unstable'] = true
		end
                Framework:putenv(key,value)
        end
        return value
end


-- Service rember env or global ns anyway
function setEnv(self,key,value)
	-- check? mt
	local mt = self:getSettingsMeta()
	if mt and mt[key] and mt[key].class and mt[key].class == "env" then
		return self:setMetaValue(key,value)
	end
end


function metaClassString(self,key)
	local mt = self:getSettingsMeta()
	local str = "SETTING"
	if mt and mt[key] and mt[key].class then
		str = string.upper(mt[key].class)
	else
		log:info("No metaClassString ",key)
	end
	return str
end


function presentMetaItem(self,key,menu)
        local meta = self:getSettingsMeta()[key]
        if not meta then return nil end
        log:warn(key,"=",debug.view(meta))
	local i

	-- FIXME generate fn from limmit auto with big if
        if meta.limit == 'dict' or meta.limit == 'func' then
        	-- construct menu on dict
                local dict = meta.limit == 'func' and meta.func() or meta.dict
                i = self:metaMenuDict(menu,key,dict)
        elseif meta.limit == 'string' or meta.limit == 'file' then
                i = self:metaMenuKeyboard(menu,key,'querty')
        elseif meta.limit == 'host' then
                -- FIXME setfn resove/ping etc...  in setMetaV..?
                i = self:metaMenuKeyboard(menu,key,'querty')
        elseif meta.limit == 'cardinal' then
                i = self:metaMenuKeyboard(menu,key,'numeric')
        elseif meta.limit == 'range' then
                -- FIXME setfn to implment range... in set..?
                i = self:metaMenuKeyboard(menu,key,'numeric')
        elseif meta.limit == 'toggle' then
                i = self:metaMenuToggle(menu,key)
        elseif meta.limit == 'image' then
		i = self:metaMenuImage(menu,key)
        else
                log:error("presentMetaItem: ",key," unkown limit ",meta.lmit)
        end
	return i
end

-- Open and create menu based on metainfo tied to applet
function presentMeta(self, menuItem)
        local meta = self:getSettingsMeta()
	local menu = SimpleMenu("menu")
        local window = Window("text_list", menuItem.text)
	local help_id = "HELP_MENU_META"
	local help = self:string(help_id)
	
	if help_id ~= help then
		menu:setHeaderWidget(Textarea("help_text", help))
	end
	-- FIXME weighted menu and sort from meta
	for k,v in pairs(meta) do
		if not v.server then -- FIXME exclude server once we have non local server
			self:presentMetaItem(k,menu)
		end
	end
	window:addWidget(menu)
        self:tieAndShowWindow(window)
end


function metaMenuDict(self,menu,key,dict,f)
	local fn = function (event, mI, menu, self)
		local group = RadioGroup()
		local meta = self:getSettingsMeta()[key]

		if meta.unset then
			menu:addItem({
				id= 'unset',
                		text = self:string((dict.name or "").."_UNSET"),
	                        style = 'item_choice',
        	                check = RadioButton("radio", group,
                	                	function(object, isSelected)
							 -- if f then ...
                                	         	self:setMetaValue(key,nil)
                		                end,
		                                self:getMetaValue(key) == nil
                		),
                	})
		end
		for k,v in pairs(dict.values) do
			menu:addItem({
				id = k,
				text = self:string((dict.name or "").."_"..string.upper(k)),
				style = 'item_choice',
                        	check = RadioButton("radio", group, 
					function(object, isSelected)
						-- if f then ...
	        				self:setMetaValue(key,v)
					end,
					self:getMetaValue(key) == v
				),
        		})
		end
		return menu
        end

	return self:addSubMenu(menu,key,fn)
end


function metaMenuKeyboard(self,menu,key,t,f)
	local meta = self:getSettingsMeta()[key]
        menu:addItem({
                 text = self:string(self:metaClassString(key).."_"..string.upper(key)),
                 callback = function(event, mI)
				-- numeric FIXME
				self:keyboardWindow(mI,t,tostring(self:getMetaValue(key) or ''),
					function(value)
						if value == '' and meta.unset then
							value = nil
						end
						if value ~= self:getMetaValue(key) then
                                    			if f and type(f) == "function" then f(value) end -- Is this required  if we check limits early
							self:setMetaValue(key,value)
							--numeric revolution
							--FIXME
							--nil? empty? empty string...
							--fresh? re fesh menu stack? how?
                                  		end
					end)
					
			    end
		
        })
end


function validateSettingsMeta(self,key,t)
        assert(type(t)=="table")
        assert(type(t.limit)=="string")
        assert(t.limit ~= "")
	if t["class"] then
        	assert(type(t.class)=="string")
	end
        if t.limit == "range" then
                assert(type(t.range)=="table")
        end
        if t.limit == "dict" then
                assert(type(t.dict)=="table")
                assert(type(t.dict.values)=="table")
        end
        if t.limit == "func" then
                assert(type(t.func)=="func")
        end
	if t.limit == "image" then
		assert(type(t.imageType)=="string")
	end
	return true
end


function registerSettingsMeta(self,key,t)
	if self:validateSettingsMeta(key,t) then
        	self:getSettingsMeta()[key] = t
		return true
	end
	return false
end


function unregisterSettingsMeta(self,key)
        -- FIXME applet manager...
        self:getMetaSettings()[key] = nil
end


function getSettingsMeta(self)
        return self._settingsMeta
end


function setMetaValue(self,key,value)
	local st = self:getSettings()
	local mt = self:getSettingsMeta()
	-- FIXME limit checks.... dynamic func check...

	if st[key] ~= value then
		log:warn("setMetaValue(",key,")  old ",st[key]," ~= new ",value)
		if mt and mt[key] and mt[key].action and type(mt[key].action) == "function" then
			mt[key].action(st[key],value)
		end

		local stfn
		if mt and mt[key] and mt[key].class then
			local fn = 'setMetaClass'..(mt[key].class:gsub("^%l", string.upper))
			log:warn("setMetaValue ",fn)
			if self[fn] then -- && type func
				log:warn("Found setMetaValue Class Function ",fn)
				stfn = self[fn]
			end
		end
		if stfn then
			log:warn("calling Class Set Fn")
			-- pcall?
			stfn(self,key,value)
		else
       			st['settings_unstable'] = true
			st[key] = value
		end
	end

	return st[key]
end


function getMetaValue(self,key, force)
	local st = self:getSettings()
	local mt = self:getSettingsMeta()

	local cfn
	if mt and mt[key] and mt[key].class then
                        local fn = 'getMetaClass'..(mt[key].class:gsub("^%l", string.upper))
                        if self[fn] then
                                log:warn("Found getMetaValue Class Function ",fn)
                                cfn = self[fn]
                        end
        end
	-- action?
	local value = cfn and cfn(self,key,force) or st[key]
        log:warn("getMetaValue ",key,"=",value, " force=", force)
	return value
end


function setSettingsMeta(self,set)
        self._settingsMeta = set
	for k,v in pairs(set) do
		self:validateSettingsMeta(k,v)
	end
        return self._settingsMeta
end


function keyboardWindow(self, menuItem, kbType, val, setfn)
        local window = Window("text_list", menuItem.text)
        local vaidinput = nil
        local min = 0 -- for nil?
        local max = 50

        -- FIXME switch like on
        if (  kbType == 'numeric' ) then
                vaidinput = "0123456789"
                max = 6
        end

        local v = Textinput.textValue(val, min, max)
        local textinput = Textinput("textinput", v,
                function(_, value)
                        log:debug("Input ", value,":",value:getValue())
                        window:playSound("WINDOWSHOW")
                        window:hide(Window.transitionPushLeft)
                        return setfn and setfn(value:getValue()) or false
                end, vaidinput)
        local backspace = Keyboard.backspace()
        local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

        window:addWidget(group)
        window:addWidget(Keyboard('keyboard',  kbType, textinput))
        window:focusWidget(group)

        self:tieAndShowWindow(window)
        return window
end


function addSubMenu(self,menu,name,f)
	local nm = SimpleMenu("menu") --style
	local id ="MENU_"..string.upper(name)
	local txt = self:string(id)
	local help_id = "HELP_"..string.upper(name)
	local help = self:string(help_id)
	
	if help_id ~= help then
		nm:setHeaderWidget(Textarea("help_text", help))
	end
	menu:addItem({
                                id = id,
                                text = txt ,
                                callback = function(event, mI)
                                                local window = Window("text_list", txt)
                                    		if f and type(f) == "function" then 
							f(event, mI, nm, self) 
						end
                                                window:addWidget(nm)
                                                self:tieAndShowWindow(window)
                                end
        })
	return nm
end


-- eliminate string needing to tostring...
function free(self)
        local st = self:getSettings()
        if st and st['settings_unstable'] then
                log:warn("free settings stored")
                st['settings_unstable'] = nil
		st['env'] = nil
                self:storeSettings()
        end

        return true
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.
Copyright 2014,2015 Phillip Camp. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
