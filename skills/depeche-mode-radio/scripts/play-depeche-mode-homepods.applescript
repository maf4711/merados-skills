on run
	return my playAll()
end run

on playAll()
	-- 80s80s Depeche Mode Radio
	-- NUR HomePods die kind=HomePod, available=true und wirklich selected werden
	set streamURL to "https://streams.80s80s.de/dm/mp3-192/streams.80s80s.de/"
	
	tell application "Music"
		if not running then launch
		set deviceList to every AirPlay device
		
		-- Do NOT deselect all first — that pauses every HomePod (audible stop).
		-- Only strip Computer / Apple TV / TV.
		repeat with oneDevice in deviceList
			try
				if ((kind of oneDevice) as text) is not "HomePod" then
					set selected of oneDevice to false
				end if
			end try
		end repeat
		
		set enabledNames to ""
		set skippedNames to ""
		
		repeat with oneDevice in deviceList
			set deviceName to (name of oneDevice) as text
			set deviceKind to ""
			set deviceAvailable to false
			try
				set deviceKind to (kind of oneDevice) as text
			end try
			try
				set deviceAvailable to (available of oneDevice) as boolean
			end try
			
			-- Filter: nur HomePod + available
			if deviceKind is not "HomePod" then
				-- Computer / Apple TV / etc. ignorieren
			else if deviceAvailable is false then
				if skippedNames is "" then
					set skippedNames to deviceName & " (aus/offline)"
				else
					set skippedNames to skippedNames & ", " & deviceName & " (aus/offline)"
				end if
			else
				-- available=true: versuchen zu adressieren, nur behalten wenn selected wirklich true
				set didSelect to false
				try
					set selected of oneDevice to true
					delay 0.15
					if (selected of oneDevice) is true then
						set didSelect to true
					end if
				end try
				
				if didSelect is true then
					if enabledNames is "" then
						set enabledNames to deviceName
					else
						set enabledNames to enabledNames & ", " & deviceName
					end if
				else
					-- available laut API, aber nicht multi-room adressierbar
					try
						set selected of oneDevice to false
					end try
					if skippedNames is "" then
						set skippedNames to deviceName & " (nicht adressierbar)"
					else
						set skippedNames to skippedNames & ", " & deviceName & " (nicht adressierbar)"
					end if
				end if
			end if
		end repeat
		
		-- Computer sicher aus
		repeat with oneDevice in deviceList
			try
				if ((kind of oneDevice) as text) is "computer" then
					set selected of oneDevice to false
				end if
			end try
		end repeat
		
		if enabledNames is "" then
			error "Kein adressierbarer HomePod online."
		end if
		
		open location streamURL
		delay 2
		try
			play
		end try
		delay 1
		set currentState to (player state as text)
		
		-- finale Verifikation: nur noch wirklich selected HomePods melden
		set finalNames to ""
		repeat with oneDevice in deviceList
			try
				if ((kind of oneDevice) as text) is "HomePod" and (selected of oneDevice) is true and (available of oneDevice) is true then
					set n to (name of oneDevice) as text
					if finalNames is "" then
						set finalNames to n
					else
						set finalNames to finalNames & ", " & n
					end if
				else if ((kind of oneDevice) as text) is "HomePod" and (selected of oneDevice) is true then
					-- selected aber nicht mehr available → abwählen
					set selected of oneDevice to false
				end if
			end try
		end repeat
	end tell
	
	if finalNames is "" then
		set finalNames to enabledNames
	end if
	
	set resultText to "Playing: " & finalNames & " | " & currentState
	if skippedNames is not "" then
		set resultText to resultText & " | skip: " & skippedNames
	end if
	try
		display notification finalNames with title "80s80s Depeche Mode Radio" subtitle "nur online & adressierbar"
	end try
	return resultText
end playAll
