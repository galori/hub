property menuBarPopupName : "Automatically hide and show the menu bar"

on findMenuBarPopup(elementToSearch)
	tell application "System Events"
		try
			if (class of elementToSearch as text) is "pop up button" then
				try
					if (name of elementToSearch as text) is menuBarPopupName then return elementToSearch
				end try
			end if
		end try

		try
			repeat with childElement in UI elements of elementToSearch
				set foundElement to my findMenuBarPopup(childElement)
				if foundElement is not missing value then return foundElement
			end repeat
		end try
	end tell

	return missing value
end findMenuBarPopup

on run argv
	set targetValue to item 1 of argv

	tell application "System Events"
		tell process "System Settings"
			repeat 80 times
				if exists window 1 then exit repeat
				delay 0.25
			end repeat

			if not (exists window 1) then error "System Settings window did not appear."

			-- Wait for the menu bar popup to load. System Settings changes its
			-- internal group hierarchy across macOS releases, so find by label.
			set p to missing value
			repeat 80 times
				set p to my findMenuBarPopup(window 1)
				if p is not missing value then exit repeat
				delay 0.25
			end repeat

			if p is missing value then error "Menu bar auto-hide popup did not appear."

			if targetValue is "Get" or targetValue is "--get" then
				return (value of p as text)
			end if
			if (value of p as text) is targetValue then return

			perform action "AXPress" of p
			delay 0.2
			click menu item targetValue of menu 1 of p

			repeat 40 times
				if (value of p as text) is targetValue then return
				delay 0.25
			end repeat

			error "Menu bar auto-hide popup did not change to " & targetValue & "."
		end tell
	end tell
  delay 1
end run
