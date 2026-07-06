property pollCount : 50
property pollDelay : 0.1

on shellQuote(valueText)
	return quoted form of valueText
end shellQuote

on terminalCommand(targetPath, promptCommand)
	set cdCommand to "cd " & my shellQuote(targetPath)
	if promptCommand is "" or promptCommand is "{prompt_cmd}" then return cdCommand
	return cdCommand & " && " & promptCommand
end terminalCommand

on activateApp(appName)
	using terms from application "Finder"
		tell application appName to activate
	end using terms from
end activateApp

on frontmostProcessName()
	tell application "System Events"
		repeat pollCount times
			try
				set frontProcesses to application processes whose frontmost is true
				if (count of frontProcesses) > 0 then return name of item 1 of frontProcesses
			end try
			delay pollDelay
		end repeat
	end tell
	return ""
end frontmostProcessName

on windowCount(processName)
	if processName is "" then return 0
	tell application "System Events"
		try
			if not (exists process processName) then return 0
			tell process processName to return count of windows
		on error
			return 0
		end try
	end tell
end windowCount

on processExists(processName)
	if processName is "" then return false
	tell application "System Events"
		try
			return exists process processName
		on error
			return false
		end try
	end tell
end processExists

on waitForWindowCount(processName, minimumCount)
	repeat pollCount times
		if my windowCount(processName) >= minimumCount then return true
		delay pollDelay
	end repeat
	return false
end waitForWindowCount

on clickFirstExistingFileMenuItem(processName, itemNames)
	tell application "System Events"
		try
			tell process processName
				tell menu bar 1
					if not (exists menu bar item "File") then return false
					tell menu bar item "File"
						tell menu "File"
							repeat with itemName in itemNames
								if exists menu item (itemName as text) then
									click menu item (itemName as text)
									return true
								end if
							end repeat
						end tell
					end tell
				end tell
			end tell
		end try
	end tell
	return false
end clickFirstExistingFileMenuItem

on ensureNewWindow(appName)
	set wasRunning to my processExists(appName)
	my activateApp(appName)
	delay 1.0

	set processName to my frontmostProcessName()
	if processName is "" then error "Could not find the frontmost process for " & appName & "."

	set initialWindows to my windowCount(processName)
	if not wasRunning and initialWindows > 0 then return processName

	if initialWindows is 0 then
		if my clickFirstExistingFileMenuItem(processName, {"New Window", "New Document", "New"}) then
			if my waitForWindowCount(processName, 1) then return processName
		end if

		tell application "System Events" to keystroke "n" using command down
		if my waitForWindowCount(processName, 1) then return processName
	else
		if my clickFirstExistingFileMenuItem(processName, {"New Window", "New Document", "New"}) then
			if my waitForWindowCount(processName, initialWindows + 1) then return processName
		end if

		tell application "System Events" to keystroke "n" using command down
		if my waitForWindowCount(processName, initialWindows + 1) then return processName
	end if

	error "Could not open a new window for " & appName & "."
end ensureNewWindow

on run argv
	if (count of argv) < 2 then error "Usage: osascript generic_terminal_launch.applescript <app_name> <path> [prompt_cmd]"

	set appName to item 1 of argv
	set targetPath to item 2 of argv
	set promptCommand to "{prompt_cmd}"
	if (count of argv) >= 3 then set promptCommand to item 3 of argv

	my ensureNewWindow(appName)
	delay 3.0
	tell application "System Events"
		keystroke my terminalCommand(targetPath, promptCommand)
		key code 36
	end tell
end run
