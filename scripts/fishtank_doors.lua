---@diagnostic disable: undefined-global
--[[
Fishtank door navigation script v3  (updates are released here: https://kiwifarms.net/search/member?user_id=40045)
Check out the clipping script too - https://rentry.org/mpv-clip-lua-script

== INSTRUCTIONS ==

Put the lua file in mpv's scripts directory.

The default keybind is left mouse button, which may not work if another script binds it first.
If LMB doesn't work for you, add this line to input.conf to change it to right double click:
MBTN_RIGHT_DBL script-binding fishtank_doors/pick-door

== CHANGELOG ==
- v3 released (june 15 2025)
- grid mode removed because fishtank.live no longer provides a grid stream :(
- updated tables to use season 4 streams
- v2 released (Nov 8 2024)
- video margins are respected (doors don't stretch over the black bars when maximized on a non-16:9 monitor)
- overlay scale is now updated with window size
- added side buttons
- added grid mode
- added clickable zones on PTZ cams
]]
--
local mp = require("mp")

local options = {
	hide_timeout_seconds = 0.7,
	door_font_height = 56,
	sidebtn_font_height = 38,
}
require("mp.options").read_options(options)

-- to generate this table:
-- curl 'https://api.fishtank.live/v1/live-streams/zones' -H 'Referer: https://www.fishtank.live/' | jq -r '.clickableZones | map(select(.action.name == "Change Live Stream")) | map("{room=\"" + .room + "\", to=\"" + .action.metadata + "\", points={" + (.points | split(" ") | join(",")) + "}}") | join(",\n")'
local doors = {
	{
		room = "camera-7-4",
		to = "camera-6-4",
		points = {
			0.2333,
			0.5020,
			0.2278,
			0.4939,
			0.2203,
			0.3629,
			0.1583,
			0.4093,
			0.1548,
			0.4052,
			0.0750,
			0.4598,
			0.0778,
			0.4638,
			0.0559,
			0.4789,
			0.0771,
			0.6262,
		},
	},
	{ room = "camera-7-4", to = "camera-5-4", points = { 0.1562, 0.3943, 0.1426, 0.1050, 0.0477, 0.1569, 0.0744, 0.4434 } },
	{
		room = "camera-11-4",
		to = "camera-10-4",
		points = { 0.1739, 0.3220, 0.1405, 0.0027, 0.1057, 0.0000, 0.0655, 0.0355, 0.1085, 0.3847 },
	},
	{ room = "camera-2-4", to = "camera-6-4", points = { 0.8104, 0.4911, 0.9038, 0.5539, 0.9413, 0.1296, 0.8261, 0.0696 } },
	{
		room = "camera-2-4",
		to = "camera-5-4",
		points = { 0.8117, 0.4966, 0.8015, 0.5171, 0.7967, 0.5157, 0.7804, 0.6712, 0.8745, 0.7394, 0.9004, 0.5553 },
	},
	{
		room = "camera-3-4",
		to = "camera-4-4",
		points = { 0.8479, 0.5321, 0.9093, 0.1078, 0.8070, 0.0314, 0.7694, 0.3915, 0.8035, 0.4202 },
	},
	{
		room = "camera-3-4",
		to = "camera-5-4",
		points = { 0.7681, 0.3956, 0.8008, 0.4216, 0.8452, 0.5321, 0.8615, 0.5471, 0.8288, 0.6999, 0.7394, 0.6057 },
	},
	{ room = "camera-4-4", to = "camera-12-4", points = { 0.5566, 0.3179, 0.5041, 0.3547, 0.5075, -0.0014, 0.5621, -0.0014 } },
	{
		room = "camera-4-4",
		to = "camera-5-4",
		points = {
			0.1330,
			0.6644,
			0.1044,
			0.4829,
			0.0825,
			0.2797,
			0.0716,
			0.1037,
			0.1774,
			0.0327,
			0.1924,
			0.3274,
			0.2087,
			0.5116,
			0.2190,
			0.5839,
		},
	},
	{
		room = "camera-7-4",
		to = "camera-9-4",
		points = {
			0.4052,
			0.2701,
			0.4018,
			-0.0027,
			0.7749,
			0.0000,
			0.7647,
			0.2920,
			0.7497,
			0.3083,
			0.6637,
			0.3629,
			0.5184,
			0.2865,
			0.4120,
			0.3779,
		},
	},
	{ room = "camera-9-4", to = "camera-6-4", points = { 0.9413, 0.2046, 0.8356, 0.1214, 0.7824, 0.5853, 0.8902, 0.6644 } },
	{
		room = "camera-9-4",
		to = "camera-7-4",
		points = {
			0.6862,
			0.4993,
			0.3404,
			0.2210,
			0.3472,
			0.0000,
			0.7265,
			-0.0014,
			0.7183,
			0.1310,
			0.7108,
			0.2551,
			0.7012,
			0.3752,
			0.6924,
			0.4707,
			0.6889,
			0.4775,
		},
	},
	{
		room = "camera-6-4",
		to = "camera-5-4",
		points = {
			0.5225,
			0.7640,
			0.5130,
			0.7476,
			0.3499,
			0.9563,
			0.3561,
			0.9754,
			0.3397,
			0.9195,
			0.3349,
			0.9222,
			0.2940,
			0.7299,
			0.2503,
			0.4625,
			0.2135,
			0.1528,
			0.2026,
			-0.0014,
			0.4911,
			-0.0027,
			0.5027,
			0.2210,
			0.5136,
			0.4352,
			0.5218,
			0.6194,
			0.5259,
			0.6903,
			0.5218,
			0.6971,
		},
	},
	{
		room = "camera-6-4",
		to = "camera-7-4",
		points = {
			0.8431,
			1.0832,
			0.8799,
			0.9577,
			0.9018,
			0.8677,
			0.9250,
			0.7613,
			0.9502,
			0.6139,
			0.9741,
			0.4352,
			0.9870,
			0.2647,
			0.9918,
			0.1364,
			0.9898,
			0.1105,
			0.9939,
			0.1460,
			0.9932,
			1.1119,
			0.8615,
			1.1132,
			0.8397,
			1.1146,
			0.8342,
			1.1146,
		},
	},
	{
		room = "camera-5-4",
		to = "camera-1-4",
		points = { 0.9939, 1.1119, 0.9945, 0.3247, 0.9598, 0.5553, 0.9004, 0.8022, 0.8363, 1.0109, 0.7926, 1.1132 },
	},
	{
		room = "camera-5-4",
		to = "camera-4-4",
		points = { 0.2626, 0.4093, 0.2135, 0.3042, 0.1944, 0.1719, 0.1746, -0.0027, 0.2142, -0.0027 },
	},
	{
		room = "camera-5-4",
		to = "camera-3-4",
		points = {
			0.0641,
			0.0614,
			0.0675,
			0.0546,
			0.0614,
			-0.0027,
			0.1180,
			-0.0027,
			0.1385,
			0.1664,
			0.1528,
			0.2647,
			0.1698,
			0.3574,
			0.1330,
			0.4461,
			0.1392,
			0.4789,
			0.1562,
			0.5634,
			0.1119,
			0.3629,
			0.0825,
			0.2142,
		},
	},
	{ room = "camera-1-4", to = "camera-6-4", points = { 0.3165, 0.4420, 0.2981, 0.0314, 0.3568, 0.0109, 0.3779, 0.5362 } },
	{
		room = "camera-1-4",
		to = "camera-5-4",
		points = { 0.3799, 0.5457, 0.2804, 0.6398, 0.2538, 0.4106, 0.2312, 0.0546, 0.2920, 0.0341, 0.3138, 0.4393 },
	},
	{
		room = "camera-6-4",
		to = "camera-10-4",
		points = { 0.7988, 0.4106, 0.7824, 0.3997, 0.7333, 0.4843, 0.7394, 0.3111, 0.7415, 0.1323, 0.7408, 0.0014, 0.8097, -0.0027 },
	},
	{
		room = "camera-6-4",
		to = "camera-9-4",
		points = {
			0.7217,
			0.4966,
			0.8111,
			0.5621,
			0.8281,
			0.3479,
			0.8349,
			0.1883,
			0.8342,
			-0.0027,
			0.8076,
			0.0000,
			0.7988,
			0.4093,
			0.7810,
			0.3984,
		},
	},
	{
		room = "camera-10-4",
		to = "camera-9-4",
		points = {
			0.4509,
			1.0368,
			0.4297,
			0.6480,
			0.4038,
			0.3015,
			0.3820,
			0.0000,
			0.6050,
			0.0000,
			0.6296,
			-0.0027,
			0.6187,
			0.2128,
			0.6432,
			0.2251,
			0.6392,
			0.2647,
			0.6296,
			0.2783,
			0.6153,
			0.2865,
			0.6071,
			0.4188,
			0.5969,
			0.5675,
			0.5880,
			0.6944,
			0.5900,
			0.7326,
		},
	},
	{
		room = "camera-10-4",
		to = "camera-6-4",
		points = {
			0.7865,
			0.5989,
			0.7954,
			0.5634,
			0.8090,
			0.4611,
			0.8199,
			0.3602,
			0.8302,
			0.2524,
			0.8390,
			0.1364,
			0.8417,
			0.0477,
			0.8329,
			0.0150,
			0.8329,
			-0.0014,
			0.8984,
			-0.0014,
			0.9939,
			-0.0014,
			0.9939,
			1.1132,
			0.7401,
			1.1146,
			0.6958,
			1.1146,
			0.7231,
			0.9959,
			0.7428,
			0.8895,
			0.7729,
			0.6985,
		},
	},
	{
		room = "camera-10-4",
		to = "camera-7-4",
		points = {
			0.6289,
			-0.0014,
			0.8254,
			0.0000,
			0.8302,
			0.0205,
			0.8356,
			0.0477,
			0.8329,
			0.1296,
			0.8254,
			0.2251,
			0.8151,
			0.3370,
			0.8022,
			0.4529,
			0.7817,
			0.5812,
			0.6351,
			0.4734,
			0.6057,
			0.4475,
			0.6153,
			0.2892,
			0.6303,
			0.2769,
			0.6432,
			0.2551,
			0.6453,
			0.2251,
			0.6207,
			0.2046,
		},
	},
	{ room = "camera-12-4", to = "camera-4-4", points = { 0.9932, 1.1132, 0.7763, 1.1132, 0.7844, -0.0027, 0.9945, -0.0027 } },
	{ room = "camera-7-4", to = "camera-8-4", points = { 0.9945, 0.2906, 0.9659, 0.2906, 0.9638, 0.1460, 0.9945, 0.1446 } },
	{
		room = "camera-8-4",
		to = "camera-7-4",
		points = {
			0.9932,
			0.8731,
			0.9932,
			1.1091,
			-0.0014,
			1.1091,
			-0.0034,
			1.0177,
			-0.0034,
			0.9686,
			-0.0027,
			0.9427,
			-0.0020,
			0.9181,
			-0.0020,
			0.8936,
			-0.0041,
			0.8677,
		},
	},
	-- {room="camera-7-4", to="camera-7-4", points={0.3956,0.0341,0.2251,0.0928,0.2224,0.0437,0.3506,-0.0014,0.3943,-0.0027}},
	{
		room = "camera-5-4",
		to = "camera-6-4",
		points = {
			0.5744,
			0.9454,
			0.5730,
			0.5416,
			0.5709,
			0.2278,
			0.5668,
			0.0000,
			0.7858,
			-0.0014,
			0.9366,
			0.0000,
			0.9945,
			-0.0068,
			0.9939,
			0.3247,
			0.9584,
			0.5484,
			0.8977,
			0.7967,
			0.8342,
			1.0068,
			0.7885,
			1.1119,
			0.7094,
			1.1091,
			0.6937,
			1.1091,
		},
	},
	{
		room = "camera-10-4",
		to = "camera-11-4",
		points = { -0.0015, -0.0010, 0.3773, 0.0010, 0.4487, 1.0424, 0.1090, 1.1123, 0.0185, 0.7587 },
	},
	{
		room = "camera-5-4",
		to = "camera-2-4",
		points = {
			0.0907,
			1.1119,
			0.0518,
			0.7954,
			0.0437,
			0.6194,
			0.0430,
			0.4338,
			0.0457,
			0.3247,
			0.0498,
			0.2510,
			0.1296,
			0.6194,
			0.1889,
			0.8131,
			0.2442,
			0.9754,
			0.2824,
			1.0696,
			0.3042,
			1.1119,
		},
	},
}

-- calculate aabb and average for every door
for i = 1, #doors do
	local points = doors[i].points
	local x1, y1, x2, y2 = points[1], points[2], points[1], points[2]
	local sum_x, sum_y = 0, 0
	local n_points = #points / 2
	for i = 1, n_points do
		local x, y = points[i * 2 - 1], points[i * 2]
		sum_x = sum_x + x
		sum_y = sum_y + y
		x1, y1 = math.min(x1, x), math.min(y1, y)
		x2, y2 = math.max(x2, x), math.max(y2, y)
	end
	doors[i].avg_x = sum_x / n_points
	doors[i].avg_y = sum_y / n_points
	doors[i].aabb = { x1, y1, x2, y2 }
end

-- command to generate:
--curl 'https://api.fishtank.live/v1/live-streams' -H 'Referer: https://www.fishtank.live/' | jq -r '.liveStreams | map("[\"" + .id + "\"]=\"" + .name + "\"") | join(",\n")'
local room_titles = {
	["camera-1-4"] = "Bedroom 1",
	["camera-2-4"] = "Bedroom 2",
	["camera-3-4"] = "Bedroom 3",
	["camera-4-4"] = "Bedroom 4",
	["camera-5-4"] = "Hallway Upstairs",
	["camera-6-4"] = "Hallway Downstairs",
	["camera-7-4"] = "Living Room",
	["camera-8-4"] = "Living Room PTZ",
	["camera-9-4"] = "Kitchen",
	["camera-10-4"] = "Laundry Room",
	["camera-11-4"] = "Garage",
	["camera-12-4"] = "Confessional",
	["camera-13-4"] = "Director",
}
local DIRECTOR_BTN = "camera-13-4"

local BACK_BTN = "_BACK"

local PTZ_BTN = "_PTZ"
local side_buttons = { DIRECTOR_BTN, BACK_BTN } -- you can put room ids here like "director-mode-3"

local function points_to_ass_path(points, x_mult, y_mult, x_off, y_off)
	local path = "m " .. points[1] * x_mult + x_off .. " " .. points[2] * y_mult + y_off .. " l"
	for i = 3, #points, 2 do
		path = path .. " " .. points[i] * x_mult + x_off .. " " .. points[i + 1] * y_mult + y_off
	end
	return path
end

local function point_in_polygon(x, y, path)
	local inside = false
	local n = #path / 2

	for i = 0, n - 1 do
		local x1, y1 = path[i * 2 + 1], path[i * 2 + 2]
		local x2, y2 = path[((i + 1) % n) * 2 + 1], path[((i + 1) % n) * 2 + 2]

		-- check if the point is within the y range of the segment
		if (y1 > y) ~= (y2 > y) then
			-- calculate the x coordinate of the intersection
			local intersectX = (x2 - x1) * (y - y1) / (y2 - y1) + x1
			if x < intersectX then
				inside = not inside
			end
		end
	end

	return inside
end

local HOV_TYPE_DOOR = 2
local HOV_TYPE_SIDEBTN = 3

-- STATE
local ass = nil
local current_room = nil
local previous_room = nil
local hovered_type = HOV_TYPE_DOOR
local hovered_door_i = 0 -- 0 always means nothing is hovered
local mouse_x, mouse_y = 0, 0
local last_mousemove_t = 0

local is_visible = false

local dim = mp.get_property_native("osd-dimensions")
dim.vw, dim.vh = 1, 1

local function make_door_ass(points, aabb, is_hovered, label, white_label)
	local text = "{\\shad0\\an7\\pos(0, 0)\\1c&H2020ff&"
	if is_hovered then
		text = text .. "\\bord0\\1a&Hd0&"
	else
		text = text .. "\\bord4\\1a&Hff&\\3a&Hbb&\\3c&H2020ff&"
	end
	text = text .. "\\p1}" .. points_to_ass_path(points, dim.vw, dim.vh, dim.ml, dim.mt) .. "{\\p0}\n"

	if label then
		local mid_x = (aabb[1] + aabb[3]) / 2
		local mid_y = (aabb[2] + aabb[4]) / 2
		local x, y = dim.ml + mid_x * dim.vw, dim.mt + mid_y * dim.vh
		local fs = math.max(dim.vh, 480) / 1080 * options.door_font_height -- fs = door_font_height @ 1080p, shrinks with player size until 480p
		text = text
			.. "{\\shad0\\bord0\\fs"
			.. fs
			.. "\\an5\\pos("
			.. x
			.. ", "
			.. y
			.. ")\\1c&H"
			.. (white_label and "ffffff" or "000050")
			.. "&\\1a&H00&}"
			.. label
			.. "\n"
	end
	return text
end

local function redraw()
	if ass == nil then
		return
	end
	ass.res_x = dim.w
	ass.res_y = dim.h
	--print("redrawing")
	ass.data = ""
	if is_visible then
		for i = 1, #doors do
			if doors[i].room == current_room then
				local is_hovered = i == hovered_door_i and hovered_type == HOV_TYPE_DOOR
				ass.data = ass.data
					.. make_door_ass(
						doors[i].points,
						doors[i].aabb,
						is_hovered,
						is_hovered and room_titles[doors[i].to]
					)
			end
		end
		local top_offset = options.sidebtn_font_height / 2 + 30
		for i = 1, #side_buttons do
			local btn = side_buttons[i]
			local label
			if btn == BACK_BTN then
				label = "Prev"
			else
				label = room_titles[btn]
			end
			local is_hovered = i == hovered_door_i and hovered_type == HOV_TYPE_SIDEBTN
			if is_hovered then
				ass.data = ass.data
					.. "{\\shad0\\bord1\\fs"
					.. options.sidebtn_font_height
					.. "\\an6\\pos("
					.. dim.w - 15
					.. ", "
					.. top_offset
					.. ")\\1c&H2020ff&\\1a&H00&\\3c&H000005&\\3a&H80&}> "
					.. label
					.. "\n"
			else
				ass.data = ass.data
					.. "{\\shad0\\bord0\\fs"
					.. options.sidebtn_font_height
					.. "\\an6\\pos("
					.. dim.w - 10
					.. ", "
					.. top_offset
					.. ")\\1c&H000050&\\1a&H00&}"
					.. label
					.. "\n"
			end
			top_offset = top_offset + options.sidebtn_font_height
		end
	end
	ass:update()
end

local function update(force_redraw)
	if current_room == nil then
		return
	end
	local new_hov_type = 0
	local new_hovered = 0
	local top_offset = options.sidebtn_font_height / 2 + 30
	for i = 1, #side_buttons do
		if
			mouse_x > dim.w - options.sidebtn_font_height * 2
			and mouse_y > top_offset - options.sidebtn_font_height / 2
			and mouse_y < top_offset + options.sidebtn_font_height / 2
		then
			new_hovered = i
			new_hov_type = HOV_TYPE_SIDEBTN
			break
		end
		top_offset = top_offset + options.sidebtn_font_height
	end
	if new_hovered == 0 then
		for i = 1, #doors do
			if doors[i].room == current_room then
				local x, y = (mouse_x - dim.ml) / dim.vw, (mouse_y - dim.mt) / dim.vh
				local aabb = doors[i].aabb
				if
					x >= aabb[1]
					and x <= aabb[3]
					and y >= aabb[2]
					and y <= aabb[4]
					and point_in_polygon(x, y, doors[i].points)
				then
					new_hovered = i
					new_hov_type = HOV_TYPE_DOOR
					break
				end
			end
		end
	end

	local new_is_visible = last_mousemove_t + options.hide_timeout_seconds > mp.get_time()
	if
		new_hovered ~= hovered_door_i
		or new_is_visible ~= is_visible
		or new_hov_type ~= hovered_type
		or force_redraw
	then
		hovered_type = new_hov_type
		hovered_door_i = new_hovered
		is_visible = new_is_visible
		redraw()
	end
end
local timer = mp.add_periodic_timer(0.1, update)

local _previous_hover = false
-- there is a bug in mpv where hover will stay false even after the pointer has moved back in
-- so we only hide on the first unhover
local function on_mouse_move(_, pos)
	--print(pos.x, pos.y, pos.hover)
	mouse_x, mouse_y = pos.x, pos.y
	if not pos.hover and _previous_hover then
		last_mousemove_t = 0 -- hide
	else
		last_mousemove_t = mp.get_time()
	end
	update()
	_previous_hover = pos.hover
end
mp.observe_property("mouse-pos", "native", on_mouse_move)

local function on_resize(_, dimensions)
	dim = dimensions
	dim.vw, dim.vh = dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb
	update(true)
end
mp.observe_property("osd-dimensions", "native", on_resize)

local function switch_cam_by_title(title)
	local playlist = mp.get_property_native("playlist")
	for i = 1, #playlist do
		if playlist[i].title:find(title .. "$") then
			mp.set_property_number("playlist-pos-1", i)
			return true
		end
	end
	return false
end

local function on_click()
	last_mousemove_t = mp.get_time()
	if current_room == nil or hovered_door_i == 0 then
		return
	end
	local door_id
	if hovered_type == HOV_TYPE_SIDEBTN then
		door_id = side_buttons[hovered_door_i]
		if door_id == BACK_BTN then
			door_id = previous_room
		end
	elseif hovered_type == HOV_TYPE_DOOR then
		door_id = doors[hovered_door_i].to
	end
	if not door_id then
		return
	end
	switch_cam_by_title(room_titles[door_id])
end
mp.add_key_binding("mbtn_left", "pick-door", on_click)

local function file_loaded()
	local filename = mp.get_property("filename") -- hopefully filename doesn't include query strings
	if not filename:find("%.m3u8") then
		return
	end
	local title = mp.get_property("media-title")
	--if title:find("PTZ$") then return end

	-- match room id
	for r_id, r_title in pairs(room_titles) do
		if title:find(r_title .. "$") then
			current_room = r_id
			ass = mp.create_osd_overlay("ass-events")
			ass.res_x = w
			ass.res_y = h
			update()
			break
		end
	end
end

local function end_file()
	previous_room = current_room
	current_room = nil
	hovered_type = HOV_TYPE_DOOR
	hovered_door_i = 0
	is_visible = false
	if ass then
		ass:remove()
	end
end

mp.register_event("file-loaded", file_loaded)
mp.register_event("end-file", end_file)
