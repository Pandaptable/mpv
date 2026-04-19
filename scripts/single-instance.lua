local mp = require("mp")
local utils = require("mp.utils")

local function close_other_instances()
	local current_pid = utils.getpid()

	local process_list = utils.subprocess({
		args = { "tasklist", "/FI", "IMAGENAME eq mpv.exe" },
		cancellable = false,
	})

	if process_list.status == 0 then
		for line in process_list.stdout:gmatch("[^\r\n]+") do
			local pid = line:match("mpv%.exe%s+%d+")
			if pid then
				pid = tonumber(pid:match("%d+"))
				if pid and pid ~= current_pid then
					utils.subprocess({
						args = { "taskkill", "/PID", tostring(pid), "/F" },
						cancellable = false,
					})
				end
			end
		end
	end
end

mp.register_event("start-file", close_other_instances)

-- linux version
-- local mp = require 'mp'
-- local utils = require 'mp.utils'

-- function close_other_instances()
--     local current_pid = utils.getpid()

--     local process_list = utils.subprocess({
--         args = { "pgrep", "-x", "mpv" },
--         cancellable = false
--     })

--     if process_list.status == 0 then
--         for pid in process_list.stdout:gmatch("%d+") do
--             pid = tonumber(pid)
--             if pid and pid ~= current_pid then
--                 utils.subprocess({
--                     args = { "kill", tostring(pid) },
--                     cancellable = false
--                 })
--             end
--         end
--     end
-- end

-- mp.register_event("start-file", close_other_instances)