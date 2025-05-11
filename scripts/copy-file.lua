--TODO: make platform-independent (windows only atm)
local mp = require("mp")

local function copy_to_clipboard(key, message)
	local file_path = mp.get_property(key)
	mp.osd_message(message .. ": " .. file_path)

	-- PowerShell command to copy file paths to the clipboard
	local powershell_command = [[
	Add-Type -AssemblyName System.Windows.Forms;
	$files = [System.Collections.Specialized.StringCollection]::new();
	$files.Add(']] .. file_path:gsub("'", "''") .. [[');
	[System.Windows.Forms.Clipboard]::SetFileDropList($files);
	]]

	mp.commandv("run", "powershell", "-nop", "-c", powershell_command)
end

mp.add_key_binding(";", "copy_file_to_clipboard", function()
	copy_to_clipboard("path", "File Copied")
end)
