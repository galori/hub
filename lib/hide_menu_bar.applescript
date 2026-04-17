on run argv
	set targetValue to item 1 of argv

	open location "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension?MenuBar"

	tell application "System Events"
		tell process "System Settings"
			repeat 20 times
				if exists window 1 then exit repeat
				delay 0.1
			end repeat

			if not (exists window 1) then error "System Settings window did not appear."

			-- Wait for the scroll area to load
			repeat 20 times
				try
					if exists scroll area 1 of group 1 of group 1 of UI element 1 of group 1 of window 1 then exit repeat
				end try
				delay 0.1
			end repeat

			tell window 1
				tell group 1
					tell UI element 1
						tell group 3
							tell group 1
								tell scroll area 1
									tell group 1
										set p to pop up button "Automatically hide and show the menu bar"
										perform action "AXPress" of p
										delay 0.2
										click menu item targetValue of menu 1 of p
									end tell
								end tell
							end tell
						end tell
					end tell
				end tell
			end tell
		end tell
	end tell
  delay 1
end run
