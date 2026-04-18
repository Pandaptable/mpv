-- osd-clock-uosc.lua
local options = require("mp.options")
-- Configuration
local cfg = {
	interval = "15m",
	format = "%H:%M",
	duration = 2.5,
	key = "h",
	name = "show-clock",
	-- Styling
	font_size = 48,
	margin = 30,
}

options.read_options(cfg, "osd-clock")
local function htime2sec(hstr)
	local s = tonumber(hstr)
	if s then
		return s
	end
	local hu = { h = 3600, m = 60, s = 1 }
	s = 0
	for unit, mult in pairs(hu) do
		local _, _, num = string.find(hstr, "(%d+)" .. unit)
		if num then
			s = s + tonumber(num) * mult
		end
	end
	return s
end

-- Clear the OSD
local function clear_clock()
	mp.set_osd_ass(0, 0, "")
end
local timer = nil

local function show_clock(duration)
	local time_str = os.date(cfg.format)
	local dur = duration or cfg.duration
		-- Top-right drawing using ASS
		local w, h = mp.get_osd_size()
		if not w or not h then
			return
		end

		-- Style mimicking uosc: White text, thin dark border, no shadow
		local ass = string.format(
			"{\\an9\\bord1\\shad0\\fs%d\\pos(%d,%d)}%s",
			cfg.font_size,
			w - cfg.margin,
			cfg.margin,
			time_str
		)

		mp.set_osd_ass(w, h, ass)

		-- Custom timer to clear the ASS layer
		if timer then
			timer:kill()
		end
		timer = mp.add_timeout(dur, clear_clock)

end
-- Timer logic
if cfg.interval and cfg.interval ~= "" then
	local interval_sec = htime2sec(cfg.interval)
	local function align_and_start()
		local time = os.time()
		local delay = interval_sec * math.ceil(time / interval_sec) - time
		mp.add_timeout(delay, function()
			show_clock()
			mp.add_periodic_timer(interval_sec, show_clock)
		end)
	end
	align_and_start()
end

-- Keybind and Messages
if cfg.key then
	mp.add_key_binding(cfg.key, cfg.name, show_clock)
end
mp.register_script_message("flash-clock", function()
	show_clock(1)
end)
mp.register_script_message("show-clock", function()
	show_clock()
end)
