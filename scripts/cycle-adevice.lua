local api = "wasapi"
local deviceList = mp.get_property_native("audio-device-list")
local aid = 1
local function cycle_adevice(s, e, d)
	mp.enable_messages("error")
	while s ~= e + d do -- until the loop would cycle back to the number we started on
		if string.find(mp.get_property("audio-device"), deviceList[s].name, 1, true) then
			while true do
				if s + d == 0 then --the device list starts at 1; 0 means we iterated to far
					s = #deviceList + 1 --so lets restart at the last device
				elseif s + d == #deviceList + 1 then --we iterated past the last device
					s = 0 --then start from the beginning
				end
				s = s + d --next device
				if string.find(deviceList[s].name, api, 1, true) then
					mp.set_property("audio-device", deviceList[s].name)
					deviceList[s].description = "•" .. string.match(deviceList[s].description, "[^%(]+")
					local list = "AUDIO DEVICE:\n"
					for i = 1, #deviceList do
						if string.find(deviceList[i].name, api, 1, true) then
							if deviceList[i].name ~= deviceList[s].name then
								list = list .. "◦"
							end
							list = list .. string.match(deviceList[i].description, "[^%(]+") .. "\n"
						end
					end
					if mp.get_property("vid") == "no" then
						print("audio=" .. deviceList[s].description)
					else
						mp.osd_message(list, 3)
					end
					mp.set_property("aid", aid)
					mp.command("seek 0 exact")
					return
				end
			end
		end
		s = s + d
	end
end

mp.observe_property("aid", function(id)
	if id ~= "no" then
		aid = id
	end
end)

mp.register_event("log-message", function(event)
	if event.text:find("Try unsetting it") then
		mp.set_property("audio-device", "auto")
		mp.set_property("aid", aid)
	end
end)

local allowed_devices = {
	"auto",
	"wasapi/{00d938c6-46d9-4140-83aa-b4f97847de55}", -- CABLE-A
	"wasapi/{d7d2d23c-83c5-4d40-a743-6e33d5be7cc4}", -- Voicemeeter Input
	"wasapi/{f5594dc2-d225-4c4c-9873-a530eec2c5a0}", -- Voicemeeter VAIO3 Input
	"wasapi/{f617877f-0da2-424d-a07d-788945f1d210}", -- Monitor
}

local device_index = 1

local function is_allowed(device_name)
	for _, allowed in ipairs(allowed_devices) do
		if device_name == allowed then
			return true
		end
	end
	return false
end

local function get_filtered_devices()
	local full_list = mp.get_property_native("audio-device-list")
	local filtered = {}
	for _, dev in ipairs(full_list) do
		if is_allowed(dev.name) then
			table.insert(filtered, dev)
		end
	end
	return filtered
end

local function set_device(index)
	local filtered = get_filtered_devices()
	if #filtered == 0 then
		mp.osd_message("No matching devices", 1)
		return
	end

	device_index = ((index - 1) % #filtered) + 1
	local selected = filtered[device_index]
	mp.set_property("audio-device", selected.name)
	mp.osd_message("Device: " .. selected.description, 1)
end

mp.add_key_binding("Ctrl+o", "cycle_filtered_adevice", function()
	set_device(device_index + 1)
end)

mp.add_key_binding("Ctrl+Shift+o", "cycleBack_filtered_adevice", function()
	set_device(device_index - 1)
end)

-- debugging
mp.add_key_binding("Ctrl+Shift+d", "copy_audio_devices", function()
	local list = mp.get_property_native("audio-device-list")
	local text = "=== Available Audio Devices ===\n"
	for i, dev in ipairs(list) do
		text = text .. string.format("[%d] name: %s | desc: %s\n", i, dev.name, dev.description)
	end

	-- Write to a temp file and pipe to clip
	local tmpfile = os.getenv("TEMP") .. "\\mpv_audio_devices.txt"
	local file = io.open(tmpfile, "w")
	file:write(text)
	file:close()
	os.execute('type "' .. tmpfile .. '" | clip')
	mp.osd_message("Audio devices copied to clipboard!", 2)
end)
