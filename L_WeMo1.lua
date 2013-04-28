--
-- WeMo plugin
-- Copyright (C) 2013 Deborah Pickett
-- 
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
--
-- Version 0.0 2013-01-05 by Deborah Pickett
--

module ("L_WeMo1", package.seeall)

local socket = require("socket")
local http = require("socket.http")
local url = require("socket.url")
local ltn12 = require("ltn12")
local lxp = require("lxp")

Debug = 1
Device = nil
ServiceId = "urn:futzle-com:serviceId:WeMo1"
TypeDeviceFileMap = {
	[ "urn:Belkin:device:controllee:1" ] = "D_WeMo1_Controllee1.xml",
	[ "urn:Belkin:device:sensor:1" ] = "D_WeMo1_Sensor1.xml",
}
UsnChildMap = {}
ChildDevices = {}
ProxyApiVersion = nil
FutureActionQueue = {}

-- Debug levels:
-- 0: None except startup message.
-- 1: Errors that prevent the plugin from functioning.
-- 2: UPnP status information.
-- 3: UPnP request and response bodies.
-- 4: XML parsing.
function debug(s, level)
	if (level == nil) then level = 1 end
	if (level <= Debug) then
		luup.log(s)
	end
end

-- ssdpSearchParse(resp)
-- Parameters:
--   resp: Full UDP response text.
-- Return value on success:
--   [1] location (URL to send UPnP commands to)
--   [2] table containing parsed response.  Keys:
--     expiry: timestamp when the service will expire.
--     host: HTTP IP address from location.
--     port: HTTP port from location.
--     usn: Host's unique id
--     uuid: UUID portion of USN, before "::".
--     namespace: namespace portion of USN, after "::".
-- Return value on failure:
--   [1] nil
--   [2] reason for failure, or status code from first line of response.
function ssdpSearchParse(resp)
	local responseStatus = resp:match("^HTTP/1\.1 (%d%d%d)")
	if (responseStatus == "200") then
		-- Got a good response.
		local info = {}
		-- CACHE-CONTROL says when this information expires
		info.expiry = resp:match("\r\nCACHE-CONTROL: *max-age=(%d+)\r\n")
		if (info.expiry) then info.expiry = os.time() + tonumber(info.expiry) end
		-- LOCATION is a URL which says where this service can be reached.
		local location = resp:match("\r\nLOCATION: *(.-)\r\n")
		if (location) then
			-- Extract host and port for convenience.
			local host = location:match("://(.-)/")
			if (host:match(":")) then
				info.host, info.port = host:match("^(.+):(.+)$")
				info.port = tonumber(info.port)
			else
				info.host = host
				info.port = 80
			end
		else
			debug("Missing header LOCATION", 2)
			return nil, "Missing header LOCATION"
		end
		-- USN is the service name.
		info.usn = resp:match("\r\nUSN: *(.-)\r\n")
		if (info.usn) then
			info.uuid, info.namespace = info.usn:match("^(.-)::(.+)$")
			if (not info.uuid or not info.namespace) then
				debug("Bad USN format from " .. location .. ": " .. info.usn, 2)
				return nil, "Bad USN format: " .. info.usn
			end
		else
			debug("Missing header USN", 2)
			return nil, "Missing header USN"
		end
		return location, info
	else
		debug("Bad SSDP response " .. responseStatus, 2)
		return nil, responseStatus
	end
end

-- ssdpSearch(target, delay, ipaddr)
-- Parameters:
--   target: UPnP search scope (nil means "upnp:rootdevice")
--   delay: Seconds to wait for all responses.
--   ipaddr: Unicast/Multicast address to send search packet (nil means 239.255.255.250)
-- Return value on success:
--   table of responses received (possibly length 0),
--     key: location,
--     value: table
function ssdpSearch(target, delay, ipaddr)
	local returnImmediately = (ipaddr ~= nil)
	if (ipaddr == nil) then ipaddr = "239.255.255.250" end
	if (target == nil) then target = "upnp:rootdevice" end
	local result = {}
	local udp = socket.udp()
	local req = "M-SEARCH * HTTP/1.1\r\n"..
		"HOST: 239.255.255.250:1900\r\n" ..
		"MAN: \"ssdp:discover\"\r\n" ..
		"MX: " .. delay .. "\r\n" ..
		"ST: " .. target .. "\r\n" ..
		"\r\n"
	debug("M-SEARCH sent to " .. ipaddr .. ":1900", 2)
	debug("M-SEARCH body: " .. req, 3)
	udp:sendto(req, ipaddr, 1900)
	udp:settimeout(delay)

	repeat
		local resp, peer, port = udp:receivefrom()
		
		if (resp ~= nil) then
			debug("M-SEARCH response received from " .. peer .. " UDP port " .. port, 2)
			debug("M-SEARCH response body: " .. resp, 3)
			local location, info = ssdpSearchParse(resp)
			if (location) then
				debug("Response identifies itself as " .. info.host .. ":" .. info.port .. " from UUID " .. info.uuid, 2)
				result[location] = info
			end
		end
	until resp == nil or returnImmediately

	udp:close()

	return result
end

-- createXpathParser(targets)
-- Returns a parser object that collects strings in an XML document based on their root-to-element "xpath".
-- Parameters:
--   targets: array of strings, the paths to look for.  In form "/root/element1/element2".
-- Returns:
--   table, keys:
--     sink: ltn12 sink, to be passed to the http.request() function.
--     result: function which takes an XPath that was sought (string).
--       returns an array, each element one occurrence of the xpath, contains the strings in that element.
function createXpathParser(targets)
	local currentXpathTable = {}

	local currentXpath = function()
		return "/" .. table.concat(currentXpathTable, "/")
	end

	local result = {}

	local targetTable = {}
	for _, xpath in pairs(targets) do
		targetTable[xpath] = true
		result[xpath] = {}
	end

	local xmlParser = lxp.new({
		CharacterData = function(parser, string)
			debug("XML: string " .. string, 4)
			if (targetTable[currentXpath()]) then
				debug("XPath matched, add to result", 4)
				result[currentXpath()][#(result[currentXpath()])] = result[currentXpath()][#(result[currentXpath()])] .. string
			end
		end,
		StartElement = function(parser, elementName, attributes)
			debug("XML: start element " .. elementName, 4)
			table.insert(currentXpathTable, elementName)
			if (targetTable[currentXpath()]) then
				table.insert(result[currentXpath()], "")
			end
		end,
		EndElement = function(parser, elementName)
			debug("XML: end element " .. elementName, 4)
			table.remove(currentXpathTable)
		end,
	}, "|")

	local sink = function(chunk, err)
		if (chunk == nil) then
			debug("sink: end of file", 4)
			xmlParser:close()
			return nil
		end
		debug("sink: " .. chunk, 4)
		if (xmlParser:parse(chunk) == nil) then
			debug("sink: error", 4)
			xmlParser:close()
		end
		return 1
	end

	return {
		sink = sink,
		result = function(s) return result[s] end
	}
end

-- upnpGetDevice(location, timeout)
-- Gets information about a UPnP device.
-- Parameters:
--   location: string, HTTP URI of the device from the SSDP discovery.
--   timeout: number of seconds to wait for a response.
-- Return value on success:
--   table, with keys:
--     deviceType
--     friendlyName
--     serialNumber
--     serviceList, keys are serviceIds, values are tables:
--       serviceType,
--       controlURL,
--       eventSubURL
-- Return value on failure:
--   [1] nil
--   [2] Reason for failure (from http.request()).
function upnpGetDevice(location, timeout)
	-- UPnP nonconformance alert!
	-- Namespace should be urn:schemas-upnp-org:device-1-0, but is urn:Belkin:device-1-0 on WeMo devices.
	local deviceXPath = "/urn:Belkin:device-1-0|root/urn:Belkin:device-1-0|device"
	local deviceTypeXPath = deviceXPath .. "/urn:Belkin:device-1-0|deviceType"
	local friendlyNameXPath = deviceXPath .. "/urn:Belkin:device-1-0|friendlyName"
	local serialNumberXPath = deviceXPath .. "/urn:Belkin:device-1-0|serialNumber"
	local serviceListXPath = deviceXPath .. "/urn:Belkin:device-1-0|serviceList"
	local serviceXPath = serviceListXPath .. "/urn:Belkin:device-1-0|service"
	local serviceTypeXPath = serviceXPath .. "/urn:Belkin:device-1-0|serviceType"
	local serviceIdXPath = serviceXPath .. "/urn:Belkin:device-1-0|serviceId"
	local controlURLXPath = serviceXPath .. "/urn:Belkin:device-1-0|controlURL"
	local eventSubURLXPath = serviceXPath .. "/urn:Belkin:device-1-0|eventSubURL"

	-- Look for these paths in the XML.
	local xpathParser = createXpathParser({
		deviceTypeXPath,
		friendlyNameXPath,
		serialNumberXPath,
		serviceTypeXPath,
		serviceIdXPath,
		controlURLXPath,
		eventSubURLXPath,
	})

	-- Create a socket with a timeout.
	local sock = function()
		local s = socket.tcp()
		s:settimeout(timeout)
		return s
	end

	-- Get the device's top-level device XML, and pull out the interesting bits.
	local request, code = http.request({
		url = location,
		sink = xpathParser.sink,
		create = sock,
	})

	-- Seems to return (nil, "closed") even when successful.
	if (request == nil and code ~= "closed" ) then
		debug("HTTP response " .. code, 3)
		return nil, code
	else
		
		local deviceType = xpathParser.result(deviceTypeXPath)
		debug("Device type instances in this XML: " .. #deviceType, 3)
		if (#deviceType == 1) then
			debug("Device type is " .. deviceType[1], 2)

			if(TypeDeviceFileMap[deviceType[1]]) then
				debug("Device " .. location .. " is a " .. TypeDeviceFileMap[deviceType[1]], 1)

				local friendlyName = xpathParser.result(friendlyNameXPath)[1]
				local serialNumber = xpathParser.result(serialNumberXPath)[1]

				debug("Device " .. location .. " is called " .. friendlyName .. " and has serial Number " .. serialNumber, 1)

				local result = {
					deviceType = deviceType[1],
					friendlyName = xpathParser.result(friendlyNameXPath)[1],
					serialNumber = xpathParser.result(serialNumberXPath)[1],
				}

				-- Service information is spread across several tables.
				result.serviceList = {}
				for s = 1, #(xpathParser.result(serviceIdXPath)) do
					local serviceId = xpathParser.result(serviceIdXPath)[s]
					local serviceType = xpathParser.result(serviceTypeXPath)[s]
					local controlURL = xpathParser.result(controlURLXPath)[s]
					local eventSubURL = xpathParser.result(eventSubURLXPath)[s]
					result.serviceList[serviceId] = {
						serviceType = serviceType,
						controlURL = controlURL,
						eventSubURL = eventSubURL,
					}
				end

				return result
			else
				-- A device we don't care about.
				return nil, deviceType[1]
			end
		else
			-- Device is reporting too many, or too few, types.
			return nil, table.concat(deviceType, ", ")
		end
	end
end

-- subscribeToDevice(eventSubURL, renewalSID, timeout)
-- Send a UPnP SUBSCRIBE to the WeMo device,
-- and have it send events back to the UPnP proxy process.
-- Parameters:
--   eventSubURL: Absolute URL, the event subscription URL
--     of the UPnP device.
--   renewalSID: nil, if this is a new subscription.
--     Otherwise, the SID to be renewed.
--   timeout: wait this many seconds before giving up.
-- Return value on success:
--   SID (subscription ID) provided by the device.
--   Duration (in seconds) before the subscription must
--     be renewed.
-- Return value on failure:
--   nil
--   Reason for failure (string)
function subscribeToDevice(eventSubURL, renewalSID, timeout)
	-- Learn Vera's IP address.
	local s = socket.udp()
	local remoteHost = eventSubURL:match("://(.-)[/:]")
	debug("Remote host is " .. remoteHost, 3)
	s:setpeername(remoteHost, 80) -- Any port will do, not actually connecting.
	local myAddress = s:getsockname()
	debug("Local host is " .. myAddress, 3)
	s:close()

	-- Create a socket with a timeout.
	local sock = function()
		local s = socket.tcp()
		s:settimeout(timeout)
		return s
	end

	local headers = {
		["TIMEOUT"] = "Second-3600",
	}

	if (renewalSID) then
		-- Renewing, include SID header.
		headers["SID"] = renewalSID
	else
		-- New subscription, include CALLBACK and NT headers
		headers["CALLBACK"] = "<http://" .. myAddress .. ":2529/upnp/event>"
		headers["NT"] = "upnp:event"
	end
	
	-- Ask the device to inform the proxy about status changes.
	local request, code, headers = http.request({
		url = eventSubURL,
		method = "SUBSCRIBE",
		headers = headers,
		create = sock,
	})

	if (request == nil and code ~= "closed") then
		debug("Failed to subscribe to " .. eventSubURL .. ": " .. code, 1)
		return nil, code
	elseif (code ~= 200) then
		debug("Failed to subscribe to " .. eventSubURL .. ": " .. code, 1)
		return nil, code
	else
		local duration = headers["timeout"]:match("Second%-(%d+)")
		debug("Subscription confirmed, SID = " .. headers["sid"] .. " with timeout " .. duration, 2)
		return headers["sid"], tonumber(duration)
	end
end

-- getProxyApiVersion()
-- Calls the proxy with GET /version.
-- Sets the ProxyApiVersion Luup variable to the value received
-- (or the empty string).
-- Return value:
--   nil if the proxy is not running.
--   The proxy API version (as a string) otherwise.
function getProxyApiVersion()
	local sock = function()
		local s = socket.tcp()
		s:settimeout(2)
		return s
	end

	local t = {}
	local request, code = http.request({
		url = "http://localhost:2529/version",
		create = sock,
		sink = ltn12.sink.table(t)
	})

	if (request == nil and code == "timeout") then
		-- Proxy may be busy.
		debug("Temporarily cannot communicate with proxy", 1)
		return nil
	elseif (request == nil and code ~= "closed") then
		-- Proxy not running.
		debug("Cannot contact UPnP event proxy: " .. code, 1)
		luup.variable_set(ServiceId, "ProxyApiVersion", "", Device)
		return ""
	else
		-- Proxy is running, note its version number.
		ProxyApiVersion = table.concat(t)
		luup.variable_set(ServiceId, "ProxyApiVersion", ProxyApiVersion, Device)
		return ProxyApiVersion
	end
end

-- proxyVersionAtLeast(n)
-- Returns true if the proxy is running and is at least version n.
function proxyVersionAtLeast(n)
	if (ProxyApiVersion and tonumber(ProxyApiVersion:match("^(%d+)")) >= n) then
		return true
	end
	return false
end

-- informProxyOfSubscription(deviceId)
-- Sends a PUT /upnp/event/[sid] message to the proxy,
-- asking it to inform this plugin if the BinaryState
-- UPnP variable changes.
-- Return value:
--   nil if the proxy timed out (should try again).
--   false if the proxy refused our request (permanently).
--   true if the proxy agreed to our request.
function informProxyOfSubscription(deviceId)
	debug("Informing proxy of subscription for device " .. deviceId, 2)
	local sock = function()
		local s = socket.tcp()
		s:settimeout(2)
		return s
	end
	local d = ChildDevices[deviceId]

	-- Tell proxy about this subscription.
	-- BinaryState is the variable we care about.
	local proxyRequestBody = "<subscription expiry='" .. d.expiry .. "'>"
	proxyRequestBody = proxyRequestBody ..
		"<variable name='BinaryState' host='localhost' deviceId='" ..
		deviceId .. "' serviceId='" .. ServiceId ..
		"' action='notifyBinaryState' parameter='binaryState' sidParameter='sid'/>"
	proxyRequestBody = proxyRequestBody .. "</subscription>"
	local request, code = http.request({
		url = "http://localhost:2529/upnp/event/" .. url.escape(d.sid),
		create = sock,
		method = "PUT",
		headers = {
			["Content-Type"] = "text/xml",
			["Content-Length"] = proxyRequestBody:len(),
		},
		source = ltn12.source.string(proxyRequestBody),
		sink = ltn12.sink.null(),
	})
	if (request == nil and code ~= "closed") then
		debug("Failed to notify proxy of subscription: " .. code, 1)
		return nil
	elseif (code ~= 200) then
		debug("Failed to notify proxy of subscription: " .. code, 1)
		return false
	else
		debug("Successfully notified proxy of subscription", 2)
		return true
	end
end

-- cancelProxySubscription(sid)
-- Sends a DELETE /upnp/event/[sid] message to the proxy,
-- Return value:
--   nil if the proxy timed out (should try again).
--   false if the proxy refused our request (permanently).
--   true if the proxy agreed to our request.
function cancelProxySubscription(sid)
	debug("Cancelling unwelcome subscription for sid " .. sid, 2)
	local sock = function()
		local s = socket.tcp()
		s:settimeout(2)
		return s
	end

	local request, code = http.request({
		url = "http://localhost:2529/upnp/event/" .. url.escape(sid),
		create = sock,
		method = "DELETE",
		source = ltn12.source.empty(),
		sink = ltn12.sink.null(),
	})
	if (request == nil and code ~= "closed") then
		debug("Failed to cancel subscription: " .. code, 1)
		return nil
	elseif (code ~= 200) then
		debug("Failed to cancel subscription: " .. code, 1)
		return false
	else
		debug("Successfully cancelled subscription", 2)
		return true
	end
end

-- queueAction(delay, retries, action)
-- Remember to run the function in action (with no parameters)
-- in delay seconds.  Allow only the specified number of retries.
function queueAction(delay, retries, action)
	table.insert(FutureActionQueue, {
		time = os.time() + delay,
		retries = retries,
		action = action
	})
end

-- renewSubscription(deviceId)
-- Try to renew the UPnP subscription for the child device deviceId.
-- Return value:
--   nil if the renewal request timed out (and we should retry).
--   false if the renewal was refused (permanently).
--   true if the renewal was accepted (a later renewal will be
--     queued and the proxy will be informed).
function renewSubscription(deviceId)
	debug("Renewing subscription for device " .. deviceId, 2)
	local d = ChildDevices[deviceId]
	local eventSubURL = url.absolute(d.location, d.eventSubURL)
	debug("Renewing subscription at " .. eventSubURL, 2)
	-- Ask the device to inform the proxy about status changes.
	local sid, duration = subscribeToDevice(eventSubURL, d.sid, 5)
	if (sid) then
		d.expiry = os.time() + duration
		d.sid = sid
		-- Tell the proxy of this subscription soon.
		queueAction(0, 3, function() return informProxyOfSubscription(deviceId) end)
		queueAction(duration / 2, 3, function() return renewSubscription(deviceId) end)
		return true
	else
		return nil
	end
end

-- subscribeToAllDevices()
-- Attempt to make a UPnP event subscription to
-- all devices.
function subscribeToAllDevices()
	-- Check that the proxy is running.
	for retries = 1, 3 do
		if (getProxyApiVersion()) then
			break
		end
	end

	-- Since Proxy API version 1: accepts NOTIFY from device.
	if (proxyVersionAtLeast(1)) then
		for childId, d in pairs(ChildDevices) do
			local eventSubURL = url.absolute(d.location, d.eventSubURL)
			debug("Subscribing to events at " .. eventSubURL, 2)
			-- Ask the device to inform the proxy about status changes.
			local sid, duration = subscribeToDevice(eventSubURL, nil, 5)
			if (sid) then
				d.sid = sid
				d.expiry = os.time() + duration
				-- Tell the proxy of this subscription soon.
				queueAction(0, 3, function() return informProxyOfSubscription(childId) end)
				queueAction(duration / 2, 3, function() return renewSubscription(childId) end)
			end
		end
	end
end

-- schedule()
-- Ask the plugin to sleep for as many seconds as
-- the next event (or five minutes, if there are no events).
function schedule()
	-- How long to sleep?
	local delay = 300
	for i = 1, #FutureActionQueue do
		if (FutureActionQueue[i].time <= os.time()) then
			delay = 1
			break
		end
		delay = math.min(delay, FutureActionQueue[i].time - os.time())
	end
	debug("Sleeping for " .. delay .. " seconds", 2)
	luup.call_delay("reentry", delay, "")
end

-- reentry()
-- This function will be called when a sleep from
-- schedule() completes.  In theory, one of the queued actions
-- is now ready to perform.
function reentry()
	local action = nil
	for i = 1, #FutureActionQueue do
		if (FutureActionQueue[i].time <= os.time()) then
			action = table.remove(FutureActionQueue, i)
			break
		end
	end

	-- Clock skew might mean there is no action.
	if (action) then
		local result = action.action()
		if (result == nil) then
			if (action.retries > 0) then
				queueAction(math.random(1, 5), action.retries - 1, action.action)
			end
		end
	end

	-- Go back to sleep.
	schedule()
end

-- initialize(lul_device)
-- Entry point for the plugin.
-- Parameters:
--   lul_device: The top-level device Id.
function initialize(lul_device)
	debug("Starting WeMo plugin (device " .. lul_device .. ")", 0)

	Device = lul_device

	-- Go quiet with debug messages unless debugging enabled.
	Debug = luup.variable_get(ServiceId, "Debug", Device)
	if (Debug == nil) then
		Debug = 0
		luup.variable_set(ServiceId, "Debug", "0", Device)
	else
		Debug = tonumber(Debug)
	end

	-- Create child devices.
	-- Use information collected from previous runs.
	local childCount = luup.variable_get(ServiceId, "ChildCount", Device)
	if (childCount == nil) then
		luup.variable_set(ServiceId, "ChildCount", "0", Device)
		childCount = 0
	else
		childCount = tonumber(childCount)
	end
	debug("Creating up to " .. childCount .. " children", 2)
	local children = luup.chdev.start(Device)
	for child = 1, childCount do
		-- UPnP device type.
		local childType = luup.variable_get(ServiceId, "Child" .. child .. "Type", Device)
		if (childType and childType ~= "") then
			-- This was the device's Friendly Name at creation time.
			local childName = luup.variable_get(ServiceId, "Child" .. child .. "Name", Device)
			local childParameters = ""
			-- Child may be at a fixed IP address.
			local childAddress = luup.variable_get(ServiceId, "Child" .. child .. "Host", Device)
			-- Use the device's IP address (if it's static) or
			-- (otherwise) its UPnP device's USN (UDN) for the unique Id.
			local childUSN
			if (childAddress and childAddress ~= "") then
				childParameters = childParameters .. ServiceId .. ",Host=" .. childAddress
				childUSN = childAddress
			else
				childUSN = luup.variable_get(ServiceId, "Child" .. child .. "USN", Device)
			end
			-- Keep local munged copies of the device's UPnP files,
			-- because we need additional elements (<staticJson>) and
			-- want to filter out services we can't use.
			local childDeviceFile = TypeDeviceFileMap[childType]
			debug("Creating child " .. childUSN .. " (" .. childName .. ") as " .. childType, 2)
			luup.chdev.append(Device, children, childUSN, childName, childType,
				childDeviceFile, "I_WeMo1.xml", childParameters, false)
		end
	end
	luup.chdev.sync(Device, children)

	-- If list of child devices changed, Luup engine will restart here.

	-- Build child list.
	debug("Roll call of child devices", 2)
	for i, d in pairs(luup.devices) do
		if (d.device_num_parent == Device) then
			local usn = d.id
			UsnChildMap[usn] = i
			ChildDevices[i] = {}
			debug("MiOS child device " .. i .. " has unique id " .. usn, 2)
		end
	end

	-- Sync up with UPnP devices and match them to children.
	-- First probe devices that are at fixed IP addresses.
	-- These are probed explicitly so that they are found even
	-- if they don't respond to multicast discovery (or if
	-- multicast discovery is off).
	for d, childDevice in pairs(ChildDevices) do
		local host = luup.variable_get(ServiceId, "Host", d)
		if (host and host ~= "") then
			debug("Reconnecting to device at fixed address " .. host, 2)
			local ssdpResponse = ssdpSearch(nil, 5, host)
			for location, info in pairs(ssdpResponse) do
				debug("Reconnected at " .. location, 2)
				childDevice.host = host
				childDevice.port = info.port
				childDevice.location = location
				childDevice.found = true
				local upnpDevice = upnpGetDevice(location, 5)
				if (upnpDevice) then
					childDevice.serviceType = upnpDevice.serviceList["urn:Belkin:serviceId:basicevent1"].serviceType
					childDevice.controlURL = upnpDevice.serviceList["urn:Belkin:serviceId:basicevent1"].controlURL
					childDevice.eventSubURL = upnpDevice.serviceList["urn:Belkin:serviceId:basicevent1"].eventSubURL
				end
			end
			if (not childDevice.found) then
				debug("No response from " .. host, 1)
			end
		end
	end
	
	-- Now do a multicast search for any other devices.
	local enableMulticast = luup.variable_get(ServiceId, "EnableMulticast", Device)
	if (not enableMulticast) then
		enableMulticast = "1"
		luup.variable_set(ServiceId, "EnableMulticast", enableMulticast, Device)
	end
	if (enableMulticast == "1") then
		local unknownDevices = {}
		debug("Searching for UPnP devices...", 2)
		-- Search at any address.
		local allUpnp = ssdpSearch(nil, 5)
		debug("Searching complete", 2)
		for location, info in pairs(allUpnp) do
			debug("UPnP location " .. location, 2)
			debug("UPnP udn " .. info.uuid, 2)
			local knownChild = UsnChildMap[info.host]
			if (knownChild == nil) then
				-- Dynamic device, perhaps.
				knownChild = UsnChildMap[info.uuid]
			end
			if (knownChild ~= nil) then
				if (ChildDevices[knownChild].found) then
					-- Already created with a static address.
					debug("Skipping " .. info.uuid .. " because it has already been found at " .. location, 2)
				else
					-- Known device, may be at a different IP address now because of DHCP.
					debug("Uuid " .. info.uuid .. " is child device " .. knownChild .. " at " .. location, 2)
					ChildDevices[knownChild].host = info.host
					ChildDevices[knownChild].port = info.port
					ChildDevices[knownChild].location = location
					ChildDevices[knownChild].found = true
					local upnpDevice = upnpGetDevice(location, 5)
					if (upnpDevice) then
						ChildDevices[knownChild].serviceType = upnpDevice.serviceList["urn:Belkin:serviceId:basicevent1"].serviceType
						ChildDevices[knownChild].controlURL = upnpDevice.serviceList["urn:Belkin:serviceId:basicevent1"].controlURL
						ChildDevices[knownChild].eventSubURL = upnpDevice.serviceList["urn:Belkin:serviceId:basicevent1"].eventSubURL
					end
				end
			else
				-- Unrecognized UUID, perhaps a new device?
				debug("Unknown uuid " .. info.uuid .. ", identifying ...", 2)
				local upnpDevice = upnpGetDevice(location, 5)
				if (upnpDevice) then
					-- Discovered new WeMo device.
					upnpDevice.location = location
					upnpDevice.uuid = info.uuid
					upnpDevice.host = info.host
					debug("Noting details of unknown device " .. info.uuid, 2)
					table.insert(unknownDevices, upnpDevice)
				end
			end
		end

		-- Any new UPnP devices found?
		local unknownDeviceCount = 0
		for _, d in pairs(unknownDevices) do
			unknownDeviceCount = unknownDeviceCount + 1
			luup.variable_set(ServiceId, "UnknownDevice" .. unknownDeviceCount .. "Type", d.deviceType, Device)
			luup.variable_set(ServiceId, "UnknownDevice" .. unknownDeviceCount .. "USN", d.uuid, Device)
			luup.variable_set(ServiceId, "UnknownDevice" .. unknownDeviceCount .. "Host", d.host, Device)
			luup.variable_set(ServiceId, "UnknownDevice" .. unknownDeviceCount .. "Name", d.friendlyName .. " (" .. d.serialNumber .. ")", Device)
		end
		luup.variable_set(ServiceId, "UnknownDeviceCount", unknownDeviceCount, Device)
	end

	-- Any existing children not accounted for?
	local unaccountedDevices = 0
	for i, d in pairs(ChildDevices) do
		if (not d.found) then
			unaccountedDevices = unaccountedDevices + 1
			luup.set_failure(true, i)
		end
	end
	if (unaccountedDevices > 0) then
		-- return false, "Previously found WeMo devices not found.", string.format("%s[%d]", luup.devices[Device].description, Device)
	end

	-- Ask all devices to tell the UPnP proxy process when their state changes.
	subscribeToAllDevices()

	-- Start scheduler for future actions.
	schedule()

	return true
end

-- handleNotifyBinaryState(lul_device, binaryState, sid)
-- Invoked by the UPnP proxy when it learns that a state (switch, sensor) has changed.
function handleNotifyBinaryState(lul_device, binaryState, sid)
	debug("Setting BinaryState = " .. binaryState .. " for device " .. lul_device, 2)
	if (ChildDevices[lul_device] and sid == ChildDevices[lul_device].sid) then
		local childDeviceType = luup.devices[lul_device].device_type
		if (childDeviceType == "urn:schemas-futzle-com:device:WeMoControllee:1") then
			-- Switch.
			luup.variable_set("urn:upnp-org:serviceId:SwitchPower1", "Status", binaryState, lul_device)
		elseif (childDeviceType == "urn:schemas-futzle-com:device:WeMoSensor:1") then
			-- Sensor.
			luup.variable_set("urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", binaryState, lul_device)
		end
		return true
	end
	debug("SID does not match: expected " .. ChildDevices[lul_device].sid .. ", got " .. sid, 2)
  -- Try to shut the proxy up, we don't care about this SID.
	luup.call_delay("cancelProxySubscription", 1, sid)
	return false
end

-- handleSetArmed(lul_device, newArmedValue)
-- Invoked by the user when they request to Arm/Bypass a sensor.
function handleSetArmed(lul_device, newArmedValue)
	debug("Setting Armed = " .. newArmedValue .. " for device " .. lul_device, 2)
	if (ChildDevices[lul_device]) then
		local childDeviceType = luup.devices[lul_device].device_type
		if (childDeviceType == "urn:schemas-futzle-com:device:WeMoSensor:1") then
			luup.variable_set("urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", newArmedValue, lul_device)
			return true
		end
	end
	return false
end

-- upnpCallAction(location, serviceType, action, parameters, values)
-- Perform a UPnP POST to the given control URL, and parse the response.
-- Parameters:
--   location: Control URL (absolute URL in string)
--   serviceType: Service type for this action, string
--   action: Name of action to invoke, string
--   parameters: array of parameters expected by the action (in the order given in the service file)
--   values: array of parameter values expected by the action (in the same order)
function upnpCallAction(location, serviceType, action, parameters, values)
	local envelopeXPath = "/http://schemas.xmlsoap.org/soap/envelope/|Envelope"
	local bodyXPath = envelopeXPath .. "/http://schemas.xmlsoap.org/soap/envelope/|Body"
	local responseXPath = bodyXPath .. "/" .. serviceType .. "|" .. action .. "Response"
	local valueXPath = responseXPath .. "/BinaryState"

	-- Look for these paths in the response XML.
	local xPathTargets = {}
	for i = 1, #parameters do
		table.insert(xPathTargets, responseXPath .. "/" .. parameters[i])
	end
	local xpathParser = createXpathParser(xPathTargets)

	-- Create a socket with a timeout.
	local sock = function()
		local s = socket.tcp()
		s:settimeout(5)
		return s
	end

	-- Form the request to set the switch.
	local parameterList = {}
	for i = 1, #parameters do
		table.insert(parameterList, 
			"<" .. parameters[i] .. ">" .. values[i] .. "</" .. parameters[i] .. ">\n")
	end
	local requestBody = "<?xml version=\"1.0\"?>\n" ..
		"<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>\n" ..
		"<u:" .. action .. " xmlns:u=\"" .. serviceType .. "\">" ..
		table.concat(parameterList) ..
		"</u:" .. action .. ">" ..
		"</s:Body></s:Envelope>\n"

	-- Ask the device to inform the proxy about status changes.
	local request, code, headers = http.request({
		url = location,
		method = "POST",
		headers = {
			["SOAPACTION"] = "\"" .. serviceType .. "#" .. action .. "\"",
			["Content-Length"] = requestBody:len(),
			["Content-Type"] = "text/xml; charset=\"utf-8\"",
		},
		create = sock,
		source = ltn12.source.string(requestBody),
		sink = xpathParser.sink,
	})

	if (request == nil and code ~= "closed") then
		debug("Failed to set target: " .. code, 2)
		return nil, code
	elseif (code ~= 200) then
		debug("Failed to set target: " .. code, 2)
		return nil, code
	else
		local responseTable = {}
		for i = 1, #parameters do
			responseTable[parameters[i]] = xpathParser.result(responseXPath .. "/" .. parameters[i])[1]
		end
		return responseTable, code
	end
end

-- handleSetTarget(lul_device, newTargetValue)
-- Called when the user asks to turn on or off a switch.
function handleSetTarget(lul_device, newTargetValue)
	debug("Setting Target = " .. newTargetValue .. " for device " .. lul_device, 2)
	if (ChildDevices[lul_device]) then
		local childDeviceType = luup.devices[lul_device].device_type
		if (childDeviceType == "urn:schemas-futzle-com:device:WeMoControllee:1") then
			local controlURL = url.absolute(ChildDevices[lul_device].location, ChildDevices[lul_device].controlURL)
			local serviceType = ChildDevices[lul_device].serviceType

			local response, code = upnpCallAction(controlURL, serviceType, "SetBinaryState", { "BinaryState" }, { newTargetValue }) 
			if (response == nil) then
				debug("Failed to set target: " .. code, 2)
				return false
			else
				debug("SetBinaryState confirmed", 2)
				if (response.BinaryState == newTargetValue) then
					debug("New BinaryState is " .. response.BinaryState, 2)
					-- Update the switch device to match the requested new state.
					-- (It'll send a confirmation event shortly anyway, but users are impatient.)
					luup.variable_set("urn:upnp-org:serviceId:SwitchPower1", "Status", response.BinaryState, lul_device)
				else
					debug("Unexpected BinaryState: " .. response.BinaryState, 1)
				end
				return true
			end
		end
	end
	return false
end
