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

on run argv
	set targetPath to "{path}"
	set promptCommand to "{prompt_cmd}"

	if (count of argv) >= 1 then set targetPath to item 1 of argv
	if (count of argv) >= 2 then set promptCommand to item 2 of argv

	set commandText to my commandFor(targetPath, promptCommand)

	tell application "iTerm2"
		activate

		repeat 50 times
			try
				if (count of windows) > 0 then exit repeat
			end try
			delay 0.1
		end repeat

		if (count of windows) = 0 then
			create window with default profile
		end if
		set targetWindow to current window

		tell current session of targetWindow
			write text commandText
		end tell
	end tell
end run
