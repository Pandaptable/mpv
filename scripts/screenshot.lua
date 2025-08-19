mp.register_script_message("screenshot_subs", function()
	mp.command("script-binding clipshot-subs")
	mp.command("screenshot")
end)

mp.register_script_message("screenshot_video", function()
	mp.command("script-binding clipshot-video")
	mp.command("screenshot video")
end)

mp.register_script_message("screenshot_window", function()
	mp.command("script-binding clipshot-window")
	mp.command("screenshot window")
end)
