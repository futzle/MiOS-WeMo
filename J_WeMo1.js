/*
 * Plugin for Belkin WeMo
 * Copyright (C) 2009-2011 Deborah Pickett

 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

/**********
 *
 * Configuration tab
 *
 **********/

function configuration(device)
{
	var html = '';
	html += '<p id="wemo_saveChanges" style="display:none; font-weight: bold; text-align: center;">Close dialog and press SAVE to commit changes.</p>';

	// List known child devices, with option to delete them.
	var childDevices = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "ChildCount", 0) - 0;

	var actualChildDevices = 0;
	var childHtml = '';
	var dynamicCount = 0;
	childHtml += '<div style="border: black 1px solid; padding: 5px; margin: 5px;">';
	childHtml += '<div style="font-weight: bold; text-align: center;">Existing WeMo devices</div>';
	childHtml += '<table width="100%"><thead><th>Name</th><th>Type</th><th>IP&#xA0;Address</th><th>Room</th><th>Action</th></thead>';
	var i;
	for (i = 1; i <= childDevices; i++)
	{
		// Find the child in the device list (requires exhaustive search).
		var childDeviceType = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + i + "Type", 0);
		if (childDeviceType == "") { continue; }
		var childDeviceHost = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + i + "Host", 0);
		var childDeviceUSN = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + i + "USN", 0);
		var childRoom;
		var childFound = false;
		for (checkDevice in jsonp.ud.devices)
		{
			if (jsonp.ud.devices[checkDevice].id_parent == device &&
				(jsonp.ud.devices[checkDevice].altid == childDeviceUSN ||
				jsonp.ud.devices[checkDevice].altid == childDeviceHost))
			{
				childName = jsonp.ud.devices[checkDevice].name;
				var childRoomId = jsonp.ud.devices[checkDevice].room;
				if (childRoomId == "0")
				{
					// Room 0 is unassigned, would break get_room_by_id().
					childRoom = "Unassigned";
				}
				else
				{
					childRoom = jsonp.get_room_by_id(childRoomId).name;
				}
				childFound = true;
			}
		}
		if (!childFound) { continue; }
		childHtml += '<tr>';
		childHtml += '<td>' + childName.escapeHTML() + '</td>';
		childHtml += '<td>' + (childDeviceType == "urn:Belkin:device:sensor:1" ? "Sensor" :
			childDeviceType == "urn:Belkin:device:controllee:1" ? "Switch" :
			childDeviceType.escapeHTML()) + '</td>';
		if (childDeviceHost == undefined)
		{
			childDeviceHost = "Dynamic";
			dynamicCount++;
		}
		childHtml += '<td>' + childDeviceHost.escapeHTML() + '</td>';
		childHtml += '<td>' + childRoom.escapeHTML() + '</td>';
		childHtml += '<td><input type="button" value="Remove" onClick="configurationRemoveChildDevice(' + device + ',' + i + ',this)"/></td>';
		childHtml += '</tr>';
		actualChildDevices++;
	}
	childHtml += '</table>';
	childHtml += '</div>';
	if (actualChildDevices) { html += childHtml; }

	// Scan for WeMo devices on the network.  Requires Multicast to be enabled.
	var enableMulticast = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "EnableMulticast", 0);
	if (enableMulticast == undefined) { enableMulticast = "1"; }
	html += '<div style="border: black 1px solid; padding: 5px; margin: 5px;">';
	html += '<div style="font-weight: bold; text-align: center;">Scan for WeMo devices</div>';
	html += '<p><input type="checkbox"' +
		(enableMulticast == "1" ? ' checked="checked"' : '') +
		(dynamicCount ? ' disabled="disabled"' : '') +
		' onclick="setEnableMulticast(' + device + ', this)">&#xA0;Enable scan for WeMo devices on LAN</p>';

	// List unknown devices as candidates to add.
	if (enableMulticast == "1")
	{
		var unknownDevices = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDeviceCount", 1) - 0;
		html += '<table id="wemo_scanResults" width="100%"><thead><th>Name&#xA0;(Serial&#xA0;number)</th><th>Type</th><th>IP&#xA0;Address</th><th>Action</th></thead>';
		var i;
		for (i = 1; i <= unknownDevices; i++)
		{
			html += '<tr>';
			var unknownDeviceName = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + i + "Name", 1);
			html += '<td>' + unknownDeviceName.escapeHTML() + '</td>';
			var unknownDeviceType = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + i + "Type", 1);
			html += '<td>' + (unknownDeviceType == "urn:Belkin:device:sensor:1" ? "Sensor" :
				unknownDeviceType == "urn:Belkin:device:controllee:1" ? "Switch" :
				unknownDeviceType.escapeHTML()) + '</td>';
			var unknownDeviceAddress = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + i + "Host", 1);
			html += '<td>' + unknownDeviceAddress.escapeHTML() + '</td>';
			html += '<td><input type="button" value="Add Dynamic" onClick="configurationAddFoundDevice('
			 + device + ',' + i + ',this,false)"/>&#xA0;';
			html += '<input type="button" value="Add Static" onClick="configurationAddFoundDevice('
			 + device + ',' + i + ',this,true)"/></td>';
			html += '</tr>';
		}
		html += '</table>';
	}
	html += '</div>';

	// Allow manual adding of device at static address.
	html += '<div id="wemo_addManual" style="border: black 1px solid; padding: 5px; margin: 5px;">';
	html += '<div style="font-weight: bold; text-align: center;">Manually add WeMo device</div>';
	
	html += '</div>';

	// Notify user if the UPnP Proxy is not answering.
	var proxyApiVersion = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "ProxyApiVersion", 1);
	if (proxyApiVersion == undefined || proxyApiVersion == "")
	{
		html += '<div style="margin: 5px;"><p>UPnP Proxy is not running. Instant updates will not happen.  More information <a target="_new" href="http://code.mios.com/trac/mios_upnp-event-proxy/">here</a>.</p></div>';
	}
	else
	{
		html += '<div style=" margin: 5px;"><p>UPnP Proxy running (API version ' + proxyApiVersion.escapeHTML() + ')</p></div>';
	}

	set_panel_html(html);
	addManualRow(device, $('wemo_addManual'))
}

// Remove an existing device.
function configurationRemoveChildDevice(device, index, button)
{
	button.disable();
	set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + index + "Type", "", 0);
	button.setValue("Removed");
	$('wemo_saveChanges').show();
}

function setEnableMulticast(device, button)
{
	var newState = $F(button);
	set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "EnableMulticast", newState ? "1" : "0", 0);
	if (newState == false) { $('wemo_scanResults').hide(); }
	$('wemo_saveChanges').show();
}

function addManualRow(device, node)
{
	var html = '';
	html += 'Name&#xA0;<input type="text" class="wemo_name" size="16"/>&#xA0;';
	html += 'Type&#xA0;<select class="wemo_type"><option value="urn:Belkin:device:controllee:1">Switch</option><option value="urn:Belkin:device:sensor:1">Sensor</option></select>&#xA0;';
	html += 'IP&#xA0;Address&#xA0;<input type="text" class="wemo_host" size="15"/>&#xA0;';
	html += '<input type="button" value="Add Static" onClick="configurationAddManualDevice(' + device + ',this)"/>';
	var p = document.createElement("p");
	p.innerHTML = html;
	node.appendChild(p);
}

// Add a found or manual device.
function configurationAddDevice(device, name, type, usn, host)
{
	var deviceCount = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "ChildCount", 0) - 0;
	deviceCount++;
	set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + deviceCount + "Name", name || "", 0);
	set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + deviceCount + "Type", type || "", 0);
	set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + deviceCount + "USN", usn || "", 0);
	if (host != undefined)
	{
		set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "Child" + deviceCount + "Host", host, 0);
	}
	set_device_state(device, "urn:futzle-com:serviceId:WeMo1", "ChildCount", deviceCount, 0);
}

// Add a found device.
function configurationAddFoundDevice(device, index, button, static)
{
	button.parentNode.select('input').invoke("disable");

	var unknownDeviceName = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "Name", 0);
	var unknownDeviceType = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "Type", 0);
	var unknownDeviceUSN = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "USN", 0);
	var unknownDeviceHost = get_device_state(device, "urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "Host", 0);
	if (static)
	{
		configurationAddDevice(device, unknownDeviceName, unknownDeviceType, unknownDeviceUSN, unknownDeviceHost);
	}
	else
	{
		configurationAddDevice(device, unknownDeviceName, unknownDeviceType, unknownDeviceUSN, undefined);
	}

	button.setValue("Added");
	$('wemo_saveChanges').show();
}

// Add a manual device.
function configurationAddManualDevice(device, button)
{
	var name = $F(button.parentNode.select('input.wemo_name')[0]);
	var type = $F(button.parentNode.select('select.wemo_type')[0]);
	var host = $F(button.parentNode.select('input.wemo_host')[0]);
	if (name == "") { name = "Manual WeMo device"; }
	if (host == "") { return; }
	button.disable();
	configurationAddDevice(device, name, type, "", host);
	button.setValue("Added");
	$('wemo_saveChanges').show();
	addManualRow(device, $('wemo_addManual'));
}
