property pollCount : 50
property pollDelay : 0.1

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

on ensureNewWindow(appName, expectedProcessName)
	set processHint to expectedProcessName
	if processHint is "" then set processHint to appName
	set wasRunning to my processExists(processHint)

	my activateApp(appName)
	delay 1.0

	set processName to my frontmostProcessName()
	if my processExists(processHint) then set processName to processHint
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
	if (count of argv) < 1 then error "Usage: osascript generic_app_launch.applescript <app_name>"
	set processName to ""
	if (count of argv) >= 2 then set processName to item 2 of argv
	set openedProcess to my ensureNewWindow(item 1 of argv, processName)
	return ""
end run
