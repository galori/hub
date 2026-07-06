property pollCount : 50
property pollDelay : 0.1

on shellQuote(valueText)
	return quoted form of valueText
end shellQuote

on isMissing(valueText, placeholderText)
	return valueText is "" or valueText is placeholderText
end isMissing

on terminalCommand(targetPath, promptCommand)
	set cdCommand to "cd " & my shellQuote(targetPath)
	if my isMissing(promptCommand, "{prompt_cmd}") then
		return cdCommand
	end if
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
			tell process processName
				return count of windows
			end tell
		on error
			return 0
		end try
	end tell
end windowCount

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

on pressCommandN()
	tell application "System Events" to keystroke "n" using command down
end pressCommandN

on ensureNewWindow(appName)
	my activateApp(appName)
	delay 0.3

	set processName to my frontmostProcessName()
	if processName is "" then error "Could not find the frontmost process for " & appName & "."

	set initialWindows to my windowCount(processName)
	if initialWindows is 0 then
		my pressCommandN()
		if my waitForWindowCount(processName, 1) then return processName
	else
		if my clickFirstExistingFileMenuItem(processName, {"New Window", "New Document", "New"}) then
			if my waitForWindowCount(processName, initialWindows + 1) then return processName
		end if

		my pressCommandN()
		if my waitForWindowCount(processName, initialWindows + 1) then return processName
	end if

	error "Could not open a new window for " & appName & "."
end ensureNewWindow

on typeLineIntoFrontmost(textLine)
	tell application "System Events"
		keystroke textLine
		key code 36
	end tell
end typeLineIntoFrontmost

on openUrlInFrontmostWindow(targetUrl)
	tell application "System Events"
		keystroke "l" using command down
		delay 0.1
		keystroke targetUrl
		key code 36
	end tell
end openUrlInFrontmostWindow
