-- Sends one text through the Messages app.
--   osascript send-message.applescript chat     <chat id>      <message>
--   osascript send-message.applescript imessage <phone number> <message>
--   osascript send-message.applescript sms      <phone number> <message>
--   osascript send-message.applescript ping     (asks for permission to control Messages)
on run argv
	set sendMode to item 1 of argv
	tell application "Messages"
		if sendMode is "ping" then
			return "Messages has " & (count of chats) & " chats."
		end if
		set target to item 2 of argv
		set messageText to item 3 of argv
		if sendMode is "chat" then
			send messageText to chat id target
		else if sendMode is "imessage" then
			set theAccount to first account whose service type = iMessage
			send messageText to participant target of theAccount
		else if sendMode is "sms" then
			set theAccount to first account whose service type = SMS
			send messageText to participant target of theAccount
		else
			error "Unknown send mode: " & sendMode
		end if
	end tell
	return "sent"
end run
