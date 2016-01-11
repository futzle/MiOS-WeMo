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
/*
 * Replaces prototype string.escapeHTML
 */
var WeMo = (function(api)
{
	// unique identifier for this plugin...
	var uuid = 'E451565B-B468-4E9E-8981-30DB4FD16F70';
	var myModule = {};
	var device = api.getCpanelDeviceId();

	function onBeforeCpanelClose(args)
	{
		// do some cleanup...
		console.log('handler for before cpanel close');
	}

	function init()
	{
		// register to events...
		api.registerEventHandler('on_ui_cpanel_before_close', myModule,
			'onBeforeCpanelClose');
	}

	function wemoEscapeHtml(string)
	{
		return string.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;');
	}

	function ShowStatus(text, error)
	{

		var html = ''
		html =
			'<input type="button" value="Reload Luup" onClick="WeMo.doReload()"/>';

		if (!error)
		{
			document.getElementById("wemo_saveChanges_text")
				.style.backgroundColor = "#00A652";
			document.getElementById("wemo_saveChanges_text")
				.innerHTML = text;
			document.getElementById("wemo_saveChanges_button")
				.style.backgroundColor = "#00A652";
			document.getElementById("wemo_saveChanges_button")
				.innerHTML = html;
		}
		else
		{
			document.getElementById("wemo_saveChanges_text")
				.style.backgroundColor = "#FF9090";
			document.getElementById("wemo_saveChanges_text")
				.innerHTML = text;
			document.getElementById("wemo_saveChanges_button")
				.style.backgroundColor = "#FF9090";
			document.getElementById("wemo_saveChanges_button")
				.innerHTML = html;
		}
	}

	function setDeviceStateVariable(DEVICE, SID, VARIABLE, VALUE, TRASH)
	{
		api.setDeviceStatePersistent(DEVICE, SID, VARIABLE, VALUE,
		{
			'onSuccess': function()
			{
				ShowStatus('Data updated, Reload LuuP Engine  to commit changes.  ',
					false);
			},
			'onFailure': function()
			{
				ShowStatus(
					'Failed to update data, Reload LuuP Engine and try again.  ',
					true);
			}
		});
	}
	// Remove an existing device.
	function configurationRemoveChildDevice(device, index, button)
	{
		var btn = jQuery(button);
		btn.attr('disabled', 'disabled');
		setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1", "Child" +
			index + "Type", "", 0);
		btn.val("Removed");
		jQuery('#wemo_saveChanges')
			.show();
	}

	function setEnableMulticast(device, button)
	{
		var btn = jQuery(button);
		var newState = btn.is(':checked');
		setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1",
			"EnableMulticast", newState ? "1" : "0", 0);
		if (!btn.is(':checked'))
		{
			jQuery('#wemo_scanResults')
				.hide();
		}
		jQuery('#wemo_saveChanges')
			.show();
	}

	function addManualRow(device, node)
	{
		var html = '<p>';
		html += 'Name&#xA0;<input type="text" class="wemo_name" size="16"/>&#xA0;';
		html +=
			'Type&#xA0;<select class="wemo_type"><option value="urn:Belkin:device:controllee:1">Appliance Switch</option><option value="urn:Belkin:device:sensor:1">Sensor</option><option value="urn:Belkin:device:lightswitch:1">Light Switch</option></select>&#xA0;';
		html +=
			'IP&#xA0;Address&#xA0;<input type="text" class="wemo_host" size="15"/>&#xA0;';
		html +=
			'<input type="button" value="Add Static" onClick="WeMo.configurationAddManualDevice(' +
			device + ',this)"/>';
		html += '</p>';
		jQuery('#' + node)
			.append(html);
	}
	// Add a found or manual device.
	function configurationAddDevice(device, name, type, usn, host)
	{
		var deviceCount = api.getDeviceState(device,
			"urn:futzle-com:serviceId:WeMo1", "ChildCount", 0) - 0;
		deviceCount++;
		setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1", "Child" +
			deviceCount + "Name", name || "");
		setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1", "Child" +
			deviceCount + "Type", type || "");
		setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1", "Child" +
			deviceCount + "USN", usn || "");
		if (host != undefined)
		{
			setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1", "Child" +
				deviceCount + "Host", host);
		}
		setDeviceStateVariable(device, "urn:futzle-com:serviceId:WeMo1",
			"ChildCount", deviceCount);
	}
	// Add a found device.
	function configurationAddFoundDevice(device, index, button, static)
	{
		var btn = jQuery(button);
		btn.parent('input')
			.attr('disabled', 'disabled');
		var unknownDeviceName = api.getDeviceState(device,
			"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "Name", 0);
		var unknownDeviceType = api.getDeviceState(device,
			"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "Type", 0);
		var unknownDeviceUSN = api.getDeviceState(device,
			"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "USN", 0);
		var unknownDeviceHost = api.getDeviceState(device,
			"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + index + "Host", 0);
		if (static)
		{
			configurationAddDevice(device, unknownDeviceName, unknownDeviceType,
				unknownDeviceUSN, unknownDeviceHost);
		}
		else
		{
			configurationAddDevice(device, unknownDeviceName, unknownDeviceType,
				unknownDeviceUSN, undefined);
		}
		btn.val("Added");
		jQuery('#wemo_saveChanges')
			.show();
	}
	// Add a manual device.
	function configurationAddManualDevice(device, button)
	{
		var btn = jQuery(button);
		var name = btn.parent()
			.find('.wemo_name')
			.val();
		var type = btn.parent()
			.find('.wemo_type')
			.val();
		var host = btn.parent()
			.find('.wemo_host')
			.val();
		if (name == "")
		{
			name = "Manual WeMo device";
		}
		if (host == "")
		{
			return;
		}
		btn.attr('disabled', 'disabled');
		configurationAddDevice(device, name, type, "", host);
		btn.val("Added");
		jQuery('#wemo_saveChanges')
			.show();
		addManualRow(device, 'wemo_addManual');
	}

	function doReload(device)
	{
		var requestURL = data_request_url + 'id=lu_action';
		requestURL +=
			'&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&timestamp=' +
			new Date()
			.getTime() + '&action=Reload';
		var xmlHttp = new XMLHttpRequest();
		xmlHttp.open("GET", requestURL, false);
		xmlHttp.send(null);
	}

	function configuration(device)
	{
		try
		{
			var html = '';
			html +=
				'<table width="100%" style="border-collapse: collapse"><tbody><tr><th  id="wemo_saveChanges_text"></th><th id="wemo_saveChanges_button"></th></tr></tbody>';
			html +=
				'</table>';

			// List known child devices, with option to delete them.
			var childDevices = api.getDeviceStateVariable(device,
				"urn:futzle-com:serviceId:WeMo1", "ChildCount",
				{
					'dynamic': false
				}) - 0;
			var actualChildDevices = 0;
			var childHtml = '';
			var dynamicCount = 0;
			childHtml +=
				'<div style="border: black 1px solid; padding: 5px; margin: 5px;">';
			childHtml +=
				'<div style="font-weight: bold; text-align: center;">Existing WeMo devices</div>';
			childHtml +=
				'<table width="100%"><thead><th>Name</th><th>Type</th><th>IP&#xA0;Address</th><th>Room</th><th>Action</th></thead>';
			var i;
			for (i = 1; i <= childDevices; i++)
			{
				// Find the child in the device list (requires exhaustive search).
				var childDeviceType = api.getDeviceStateVariable(device,
					"urn:futzle-com:serviceId:WeMo1", "Child" + i + "Type",
					{
						'dynamic': false
					}) || "";
				if (childDeviceType == "")
				{
					continue;
				}
				var childDeviceHost = api.getDeviceStateVariable(device,
					"urn:futzle-com:serviceId:WeMo1", "Child" + i + "Host",
					{
						'dynamic': false
					});
				var childDeviceUSN = api.getDeviceStateVariable(device,
					"urn:futzle-com:serviceId:WeMo1", "Child" + i + "USN",
					{
						'dynamic': false
					});
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
							childRoom = jsonp.get_room_by_id(childRoomId)
								.name;
						}
						childFound = true;
					}
				}
				if (!childFound)
				{
					continue;
				}
				childHtml += '<tr>';
				childHtml += '<td>' + wemoEscapeHtml(childName) + '</td>';
				childHtml += '<td>' + (childDeviceType == "urn:Belkin:device:sensor:1" ?
					"Sensor" :
					childDeviceType == "urn:Belkin:device:controllee:1" ?
					"Appliance Switch" :
					childDeviceType == "urn:Belkin:device:lightswitch:1" ? "Light Switch" :
					wemoEscapeHtml(childDeviceType)) + '</td>';
				if (childDeviceHost == undefined)
				{
					childDeviceHost = "Dynamic";
					dynamicCount++;
				}
				childHtml += '<td>' + wemoEscapeHtml(childDeviceHost) + '</td>';
				childHtml += '<td>' + wemoEscapeHtml(childRoom) + '</td>';
				childHtml +=
					'<td><input type="button" value="Remove" onClick="WeMo.configurationRemoveChildDevice(' +
					device + ',' + i + ',this)"/></td>';
				childHtml += '</tr>';
				actualChildDevices++;
			}
			childHtml += '</table>';
			childHtml += '</div>';
			if (actualChildDevices)
			{
				html += childHtml;
			}
			// Scan for WeMo devices on the network.  Requires Multicast to be enabled.
			var enableMulticast = api.getDeviceStateVariable(device,
				"urn:futzle-com:serviceId:WeMo1", "EnableMulticast",
				{
					'dynamic': false
				});
			if (enableMulticast == undefined)
			{
				enableMulticast = "1";
			}
			html +=
				'<div style="border: black 1px solid; padding: 5px; margin: 5px;">';
			html +=
				'<div style="font-weight: bold; text-align: center;">Scan for WeMo devices</div>';
			html += '<p><input type="checkbox"' +
				(enableMulticast == "1" ? ' checked="checked"' : '') +
				(dynamicCount ? ' disabled="disabled"' : '') +
				' onclick="WeMo.setEnableMulticast(' + device +
				', this)">&#xA0;Enable scan for WeMo devices on LAN</p>';
			// List unknown devices as candidates to add.
			if (enableMulticast == "1")
			{
				var unknownDevices = api.getDeviceStateVariable(device,
					"urn:futzle-com:serviceId:WeMo1", "UnknownDeviceCount",
					{
						'dynamic': false
					}) - 0;
				html +=
					'<table id="wemo_scanResults" width="100%"><thead><th>Name&#xA0;(Serial&#xA0;number)</th><th>Type</th><th>IP&#xA0;Address</th><th>Action</th></thead>';
				var i;
				for (i = 1; i <= unknownDevices; i++)
				{
					html += '<tr>';
					var unknownDeviceName = api.getDeviceStateVariable(device,
						"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + i + "Name",
						{
							'dynamic': false
						});
					html += '<td>' + wemoEscapeHtml(unknownDeviceName) + '</td>';
					var unknownDeviceType = api.getDeviceStateVariable(device,
						"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + i + "Type",
						{
							'dynamic': false
						});
					html += '<td>' + (unknownDeviceType == "urn:Belkin:device:sensor:1" ?
						"Sensor" :
						unknownDeviceType == "urn:Belkin:device:controllee:1" ?
						"Appliance Switch" :
						unknownDeviceType == "urn:Belkin:device:lightswitch:1" ?
						"Light Switch" :
						wemoEscapeHtml(unknownDeviceType)) + '</td>';
					var unknownDeviceAddress = api.getDeviceStateVariable(device,
						"urn:futzle-com:serviceId:WeMo1", "UnknownDevice" + i + "Host",
						{
							'dynamic': false
						});
					html += '<td>' + wemoEscapeHtml(unknownDeviceAddress) + '</td>';
					html +=
						'<td><input type="button" value="Add Dynamic" onClick="WeMo.configurationAddFoundDevice(' +
						device + ',' + i + ',this,false)"/>&#xA0;';
					html +=
						'<input type="button" value="Add Static" onClick="WeMo.configurationAddFoundDevice(' +
						device + ',' + i + ',this,true)"/></td>';
					html += '</tr>';
				}
				html += '</table>';
			}
			html += '</div>';
			// Allow manual adding of device at static address.
			html +=
				'<div id="wemo_addManual" style="border: black 1px solid; padding: 5px; margin: 5px;">';
			html +=
				'<div style="font-weight: bold; text-align: center;">Manually add WeMo device</div>';
			html += '</div>';
			// Notify user if the UPnP Proxy is not answering.
			var proxyApiVersion = api.getDeviceStateVariable(device,
				"urn:futzle-com:serviceId:WeMo1", "ProxyApiVersion",
				{
					'dynamic': false
				});
			if (proxyApiVersion == undefined || proxyApiVersion == "")
			{
				html +=
					'<div style="margin: 5px;"><p>UPnP Proxy is not running. Instant updates will not happen.  More information <a target="_new" href="http://code.mios.com/trac/mios_upnp-event-proxy/">here</a>.</p></div>';
			}
			else
			{
				html += '<div style=" margin: 5px;"><p>UPnP Proxy running (API version ' +
					wemoEscapeHtml(proxyApiVersion) + ')</p></div>';
			}
			api.setCpanelContent(html);
			addManualRow(device, 'wemo_addManual');
		}
		catch (e)
		{
			Utils.logError('Error in WeMo.configuration(): ' + e);
		}
	}
	myModule = {
		uuid: uuid,
		init: init,
		onBeforeCpanelClose: onBeforeCpanelClose,
		configurationAddManualDevice: configurationAddManualDevice,
		configurationRemoveChildDevice: configurationRemoveChildDevice,
		configurationAddFoundDevice: configurationAddFoundDevice,
		setEnableMulticast: setEnableMulticast,
		doReload: doReload,
		configuration: configuration
	};
	return myModule;
})(api);
