--[[
=head1 NAME

applets.NetProxy.NetProxyApplet - An applet to configure a squeezplay network proxy

=head1 DESCRIPTION

An applet to configure a squeezplay network proxy

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs, tostring ,select, tonumber, type = ipairs, pairs, tostring, select, tonumber, type

local table           = require("table")
local string          = require("string")
local os              = require("os")
local oo              = require("loop.simple")

local Framework       = require("jive.ui.Framework")
local SimpleMenu      = require("jive.ui.SimpleMenu")
local Window          = require("jive.ui.Window")
local Choice          = require("jive.ui.Choice")
local Textarea        = require("jive.ui.Textarea")
local Timer           = require("jive.ui.Timer")

local debug           = require("jive.utils.debug")

local Process	      = require("jive.net.Process")
local Proxy           = require("jive.net.Proxy")

local AppletUI        = require("jive.AppletUI")
local System          = require("jive.System")

local jnt             = jnt
local appletManager   = appletManager
local jiveMain	      = jiveMain

local CONNECT_TIMEOUT = 20
local RESTART_PERIOD  = 30000

module(..., Framework.constants)
oo.class(_M, AppletUI)

function menu(self, menuItem)

        log:info(":menu")

        local window = Window("text_list", self:string('APPLET_NAME'))

	local fresh = function(...)
        	log:debug(self,":menu.fresh()")
		local nw = self:menu(menuItem)
		-- nw:hide(Window.transtionNone)
		nw:replace(window,Window.transtionNone)
		window = nw
        	log:debug(self,":menu.fresh() end")
	end

        -- Menu for Settings...
        local menu = SimpleMenu("menu", { 
		{
			id = 'BigSwitch',
			text = self:string('PROXY'),
			style = 'item_choice',
			sound = "WINDOWSHOW",
			check = Choice("choice",{self:string('OFF'),self:string('ON')}, function(obj, selectedIndex)
                                               log:info(
                                                        "Choice updated: ",
                                                        tostring(selectedIndex),
                                                        " - ",
                                                        tostring(obj:getSelected())
                                               )
						Proxy.setProxyState(selectedIndex == 2 and true or false)
                         	end
			, Proxy.getProxyState() and 2 or 1 ) -- Index into choice
		},
		{
			id = 'Add',
			text = tostring(self:string('ADD')).." "..tostring(self:string('PROXY')),
			sound = "WINDOWSHOW",
			callback = function(event, mI)
					log:debug(self,":menu add(",event,",",mI,")")
					local nw = self:menuAddProxy(mI,fresh)
					nw:show()
					fresh()
					log:debug(self,":menu add(",event,") end")
			end
		}
	})
	menu:setHeaderWidget(Textarea("help_text", self:string('HELP')))

	if System:getMachine() == "squeezeplay" then
		local nm = self:addSubMenu(menu,"ssh_tunnel")
		self:metaMenuToggle(nm,"ssh_tunnel_script_toggle")
		self:metaMenuKeyboard(nm,"ssh_tunnel_server","querty")
		self:metaMenuKeyboard(nm,"ssh_tunnel_port","numeric")
		self:metaMenuKeyboard(nm,"ssh_tunnel_port_noproxy","numeric")
	end

	-- PROXIES GO GO GO
	for i in Proxy:iterProxies() do
		local name = Proxy:getProxyServer(i)
		
		menu:addItem({ 
				id = 'Proxy'..tostring(i),
				text = i == 1 and tostring(self:string(name)) or name,
				sound = "WINDOWSHOW",
				callback = function(event, mI)
						local nw = self:menuProxy(mI,i,fresh)
						nw:show()
				end
		})
	end
	
        window:addWidget(menu)
        self:tieWindow(window)
        return window
end


function menuProxy(self,menuItem,i,refresh) 
        log:info(":menuProxy")
	local window = Window("text_list", menuItem.text) 

	local fresh = function()
        	log:debug(self,":menuProxy.fresh(",window:getTitle(),")")
		local nw = self:menuProxy(menuItem,i,refresh)
		nw:replace(window,Window.transtionNone)
		window = nw
        	log:debug(self,":menuProxy.fresh(",window:getTitle(),") end")
	end

        local menu = SimpleMenu("menu", { 
						-- If defaults ie item 1 limit editing
						{
							id = 'Server',
							text = i != 1 and Proxy:getProxyServer(i) or tostring(self:string(Proxy:getProxyServer(i))),
							sound = "WINDOWSHOW",
							style = i !=1 and "item" or "item_no_arrow",
							callback = i !=1 and function(event, mI)
								log:debug(self,"Edit Proxy server Name")
								if i != 1 then
									self:keyboardWindow(mI, 'querty',Proxy:getProxyServer(i),function(value)
										Proxy:setProxyServer(value,i)
										fresh()
										refresh()
									end)
								end
							end or nil
						},
						{
							id = 'Port',
							text = tostring(self:string('PORT')).." "..Proxy:getProxyPort(i),
							sound = "WINDOWSHOW",
							callback = function(event, mI)
								self:keyboardWindow(mI, 'numeric',tostring(Proxy:getProxyPort(i)),function(value) 
									log:debug(self,"Portval ",value,",",type(value))
									Proxy:setProxyPort(tonumber(tostring(value)),i)
									fresh()
								end)

									
							end
						},
						{
							id = 'NoProxy',
							text = tostring(self:string('NOPROXY')),
							sound = "WINDOWSHOW",
							callback = function(event, mI)
								local w = self:menuNoProxy(mI,i)
								w:show()
							end
						},
						{
							id = 'Active',
							text = tostring(self:string('PROXY')),
							style = 'item_choice',
							sound = "WINDOWSHOW",
							check = Choice("choice",{self:string('NO'),self:string('YES')}, function(obj, selectedIndex)
                                               			log:info(
                                                        	"Choice updated: ",
                                                        	tostring(selectedIndex),
                                                        	" - ",
                                                        	tostring(obj:getSelected())
                                               			)
								Proxy:setActive(selectedIndex == 2 and true or false,i)
                         				end
							, Proxy:getActive(i) and 2 or 1 ) -- Index into choice
						},
						{
							id = 'method',
							text = self:string('METHOD'),
							style = 'item_choice',
							sound = "WINDOWSHOW",
							--FIXME iterate over
							check = Choice("choice",map(function(x) return self:string(x) end, Proxy:getMethods()), function(obj, selectedIndex)
                                               			log:info(
                                                        	"Choice updtated: ",
                                                        	tostring(selectedIndex),
                                                        	" - ",
                                                        	tostring(obj:getSelected())
                                               			)	
								Proxy:setMethod(selectedIndex,i)
                                                                fresh()
                         				end
							, select(2,Proxy:getMethod(i))) -- Index into choice... also
						},
						{
							id = 'method_help',
							style = 'item_text',
							text = self:string(Proxy:getMethod(i).."_HELP"),
						},
	})
	-- no delete idx 1 defaults
	if i != 1 then
		menu:addItem({ 
				id = 'Remove'..tostring(i),
				text = tostring(self:string('REMOVE')),
				sound = "WINDOWSHOW",
				callback = function(event, menuI)
						Proxy:removeProxy(i)
						refresh()
						window:hide(Window.transitionPushRight)
				end		
		})
	end
	
	window:addWidget(menu)
	self:tieWindow(window)
	return window
end

function menuAddProxy(self,menuItem, refresh)
	i = Proxy:addProxy("new")
	log:debug(self,":menuAddProxy = ",i)
	return self:menuProxy(menuItem, i, refresh)
end

function menuNoProxy(self,menuItem,i,refresh)
        log:info(":menuNoProxy")
	local window = Window("text_list", menuItem.text) 

	local fresh = function()
        	log:debug(self,":menuNoProxy.fresh(",window:getTitle(),")")
		local nw = self:menuNoProxy(menuItem,i,refresh)
		nw:replace(window,Window.transtionNone)
		window = nw
        	log:debug(self,":menuNoProxy.fresh(",window:getTitle(),") end")
	end
	
	-- Add
        local menu = SimpleMenu("menu", { 
						{
							id = 'Add',
							text = self:string('ADD'),
							sound = "WINDOWSHOW",
							callback = function(event, mI)
								self:keyboardWindow(mI, 'querty',tostring("new"),function(value)
									Proxy:addNoProxy(value,i)
									fresh()
								end)
							end
						},
	})

	-- list with delete and/or mod?
	for j, x in ipairs(Proxy:getNoProxy(i)) do
		menu:addItem({ 
				id = 'NoProxy'..tostring(j),
				text = x,
				sound = "WINDOWSHOW",
				callback = function(event, mI)
						local nw = self:menuNoProxyOptions(mI, i,j,fresh)
						nw:show()
				end
		})
	end

	window:addWidget(menu)
	self:tieWindow(window)
	return window
end

function menuNoProxyOptions(self,menuItem,i,j,refresh)
        log:info(":menuNoProxyOptions")

	local window = Window("text_list", menuItem.text) 
	
	-- Add
        local menu = SimpleMenu("menu", { 
						{
							id = 'Edit'..tostring(i).."/"..tostring(j),
							text = self:string('EDIT'),
							sound = "WINDOWSHOW",
							callback = function(event, mI)
								self:keyboardWindow(mI, 'querty',tostring(menuItem.text),function(value)
									Proxy:setNoProxy(value,i,j)
									log:debug(self,":",debug.getinfo(1, "n").name, ":menuNoProxyOptions (EDIT) window:",window:getTitle())
									refresh()
									window:hide(Window.transitionPushLeft)
								end)
							end
						},

		{ 
				id = 'Remove'..tostring(i).."/"..tostring(j),
				text = tostring(self:string('REMOVE')),
				sound = "WINDOWSHOW",
				callback = function(event, menuI)
						Proxy:removeNoProxy(i,j)
						refresh()
						window:hide(Window.transitionPushLeft)
				end
		}

	})
	
	window:addWidget(menu)
	return window
end

function init(self)
	if string.match(os.getenv("OS") or "", "Windows") then
		return
	end
	Process.init(jiveMain)

	self.state = {}
	-- FIXME only atcive
        local timer = Timer(RESTART_PERIOD,  function() self:_trigger(self.state) end)
	self:_trigger(self.state)
	timer:start()

	return self
end

function _trigger(self,state)
	local st = self:getSettings()
	local server = st['ssh_tunnel_server']
	local port = st['ssh_tunnel_port'] or 22
	local directport = st['ssh_tunnel_port_noproxy'] or "" -- nil
	local cmd = "./squeezeplay-ssh-tunnel.sh"

	if st['ssh_tunnel_server'] and st['ssh_tunnel_script_toggle'] and not state['tunnel'] or (state['tunnel'] and state['tunnel']:status() == "dead") then
		local cmdline = cmd .." ".. server .." ".. port .." ".. directport .." 2>&1"
		log:warn("Starting tunnel: ", cmdline)
		state['tunnel'] = Process(jnt, cmdline)
		state['tunnel']:readPid(state['tunnel']:logSink("tunnel",function (...)log:info(...)end),false) -- redirect may not work?
	end
end

function free(self)
	log:warn(self,":free()")
	local st = self:getSettings()
	st['proxies'] = Proxy.getSettings()
	st['proxy'] = Proxy.getProxyState()
        if log:isDebug() then
            debug.dump(st,4)
        end
	-- st['settings_unstable'] = true FIXME  no change?
	self:storeSettings() -- Applet Mananger should do this...
	log:debug(self,":free() end")
	return not st['ssh_tunnel_server_toggle']
end

