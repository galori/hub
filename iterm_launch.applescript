on shellQuote(valueText)
	return quoted form of valueText
end shellQuote

on commandFor(targetPath, promptCommand)
	set cdCommand to "cd " & shellQuote(targetPath)
	if promptCommand is "" or promptCommand is "{prompt_cmd}" then
		return cdCommand
	end if
	return cdCommand & " && " & promptCommand
end commandFor

on waitForItermWindow()
	tell application "iTerm"
		repeat 50 times
			try
				if (count of windows) > 0 then return true
			end try
			delay 0.1
		end repeat
	end tell
	return false
end waitForItermWindow

on openItermWindow()
	tell application "iTerm" to activate
	delay 0.5
	tell application "System Events" to keystroke "n" using command down
end openItermWindow

on run argv
	set targetPath to "{path}"
	set promptCommand to "{prompt_cmd}"

	if (count of argv) >= 1 then set targetPath to item 1 of argv
	if (count of argv) >= 2 then set promptCommand to item 2 of argv

	set commandText to my commandFor(targetPath, promptCommand)

	tell application "iTerm"
		activate
	end tell
	delay 0.3

	if not my waitForItermWindow() then
		my openItermWindow()
		if not my waitForItermWindow() then
			error "iTerm is running but no window could be opened."
		end if
	end if

	tell application "System Events"
		keystroke commandText
		key code 36
	end tell
end run
