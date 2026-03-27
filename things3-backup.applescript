----------------------------------------------------------------------
-- things3-backup.applescript v5.5 (ULTRA FAST)
-- Exports Things3 -> single gtd.org (GTD / beorg / Emacs / Obsidian)
--
-- v5.5 Optimizations:
-- Zero shell calls inside loops. Pure AppleScript memory ops.
----------------------------------------------------------------------

property MAX_BACKUPS : 10
property REPEATER_STYLE : "++"
property INCLUDE_COMPLETED : true
property orgBuffer : ""
property orgFilePath : ""

----------------------------------------------------------------------
-- NATIVE STRING HANDLERS (0 milliseconds, no shell)
----------------------------------------------------------------------

on replaceText(searchStr, replaceStr, srcText)
	if srcText is "" then return ""
	set AppleScript's text item delimiters to searchStr
	set parts to text items of srcText
	set AppleScript's text item delimiters to replaceStr
	set res to parts as text
	set AppleScript's text item delimiters to ""
	return res
end replaceText

on splitText(src, delim)
	if src is "" then return {}
	set AppleScript's text item delimiters to delim
	set parts to text items of src
	set AppleScript's text item delimiters to ""
	return parts
end splitText

on cleanNotes(noteText)
	if noteText is "" then return ""
	-- U+2028 and U+2029 are Things3 internal line breaks
	set noteText to my replaceText((character id 8232), linefeed, noteText)
	set noteText to my replaceText((character id 8233), linefeed, noteText)
	return noteText
end cleanNotes

-- UPDATED: map emoji context tags to @context, keep area/other tags clean
on cleanTag(tg)
	-- Force to text
	try
		set tg to tg as text
	on error
		return ""
	end try
	if tg is "" then return ""
	
	-- Collapse double spaces
	set tg to my replaceText("  ", " ", tg)
	
	-- If the first character is an emoji and the second is a space,
	-- treat as "emoji + context text"
	if (count of tg) ≥ 3 then
		set firstChar to character 1 of tg
		set secondChar to character 2 of tg
		
		if secondChar is space then
			-- Strip emoji + space, keep the rest as the context name
			set ctxText to text 3 thru -1 of tg
			
			-- Lowercase + replace spaces with underscores
			set ctxText to my replaceText(" ", "_", ctxText)
			set ctxText to (do shell script "printf '%s' " & quoted form of ctxText & " | tr '[:upper:]' '[:lower:]'")
			
			if ctxText is not "" then
				return "@" & ctxText
			else
				return ""
			end if
		end if
	end if
	
	-- Non-emoji tags: generic cleanup, no @
	set tg to my replaceText(" ", "_", tg)
	return tg
end cleanTag

on areaToTag(areaClean)
	return my replaceText(" ", "_", areaClean)
end areaToTag

on escapeOrg(s)
	if s is "" then return ""
	set s to my replaceText("[", "(", s)
	set s to my replaceText("]", ")", s)
	return s
end escapeOrg

on rruleToRepeater(rrule, rStyle)
	if rrule is "" then return ""
	set freq to ""
	if rrule contains "FREQ=DAILY" then set freq to "DAILY"
	if rrule contains "FREQ=WEEKLY" then set freq to "WEEKLY"
	if rrule contains "FREQ=MONTHLY" then set freq to "MONTHLY"
	if rrule contains "FREQ=YEARLY" then set freq to "YEARLY"
	if freq is "" then return ""
	
	set intv to "1"
	if rrule contains "INTERVAL=" then
		set parts to my splitText(rrule, "INTERVAL=")
		if (count of parts) > 1 then
			set remainder to item 2 of parts
			set intv to item 1 of my splitText(remainder, ";")
		end if
	end if
	
	if freq is "DAILY" then return rStyle & intv & "d"
	if freq is "WEEKLY" then return rStyle & intv & "w"
	if freq is "MONTHLY" then return rStyle & intv & "m"
	if freq is "YEARLY" then return rStyle & intv & "y"
	return ""
end rruleToRepeater

on isoDate(theDate)
	if theDate is missing value then return ""
	try
		set isoRaw to (theDate as «class isot» as string)
		set datePart to text 1 thru 10 of isoRaw
		
		set theWeekday to weekday of theDate
		set dowStr to ""
		if theWeekday is Sunday then set dowStr to "Sun"
		if theWeekday is Monday then set dowStr to "Mon"
		if theWeekday is Tuesday then set dowStr to "Tue"
		if theWeekday is Wednesday then set dowStr to "Wed"
		if theWeekday is Thursday then set dowStr to "Thu"
		if theWeekday is Friday then set dowStr to "Fri"
		if theWeekday is Saturday then set dowStr to "Sat"
		
		return datePart & " " & dowStr
	on error
		return ""
	end try
end isoDate

----------------------------------------------------------------------
-- LOGIC HANDLERS
----------------------------------------------------------------------

on getTaskStatus(s)
	if s is "completed" then return "DONE"
	if s is "cancelled" then return "CANCELLED"
	return "TODO"
end getTaskStatus

on hasWaitingTag(tagList)
	repeat with tg in tagList
		set tgStr to tg as text
		if tgStr is "@waiting" or tgStr is "waiting" then return true
	end repeat
	return false
end hasWaitingTag

on orgTagString(tagList)
	if (count of tagList) is 0 then return ""
	set r to ":"
	repeat with tg in tagList
		set c to my cleanTag(tg)
		if c is not "" then set r to r & c & ":"
	end repeat
	if r is ":" then return ""
	return r
end orgTagString

on resolveTaskStat(rawStat, tagList, isSomeday)
	if rawStat is "DONE" then return "DONE"
	if rawStat is "CANCELLED" then return "CANCELLED"
	if isSomeday then return "MAYBE"
	if my hasWaitingTag(tagList) then return "WAIT"
	return "NEXT"
end resolveTaskStat

on orgDate(isoD, repeater)
	if isoD is "" then return ""
	if repeater is "" then return "<" & isoD & ">"
	return "<" & isoD & " " & repeater & ">"
end orgDate

----------------------------------------------------------------------
-- BULK DATA FETCH
----------------------------------------------------------------------
on collectAllCheckItems()
	set scpt to "tell application \"Things3\"
set allToDos to every to do
set r to {}
repeat with t in allToDos
set tID to id of t as text
set ciList to every check item of t
repeat with ci in ciList
set ciName to name of ci as text
set ciStat to status of ci as text
set ciMark to \"[ ]\"
if ciStat is \"completed\" then set ciMark to \"[X]\"
set r to r & {{tID, ciMark, ciName}}
end repeat
end repeat
return r
end tell"
	try
		return run script scpt
	on error
		return {}
	end try
end collectAllCheckItems

on getCheckItemsForTask(checkMap, taskID)
	set found to {}
	repeat with entry in checkMap
		if (item 1 of entry as text) is taskID then
			set found to found & {{item 2 of entry, item 3 of entry}}
		end if
	end repeat
	return found
end getCheckItemsForTask

----------------------------------------------------------------------
-- FILE WRITING
----------------------------------------------------------------------

on bufferLine(content)
	set orgBuffer to orgBuffer & content
	if (count of orgBuffer) > 50000 then
		my flushToFile()
	end if
end bufferLine

on flushToFile()
	if orgBuffer is "" then return
	set asFile to POSIX file orgFilePath
	try
		set fileRef to open for access asFile with write permission
		set eofPosition to get eof of fileRef
		write orgBuffer to fileRef as «class utf8» starting at (eofPosition + 1)
		close access fileRef
	on error
		try
			close access fileRef
		end try
	end try
	set orgBuffer to ""
end flushToFile

on writeMultilineNote(noteText)
	set noteText to my cleanNotes(noteText)
	set parts to my splitText(noteText, linefeed)
	repeat with noteLine in parts
		set lineStr to noteLine as text
		if lineStr is not "" then
			my bufferLine("   " & my escapeOrg(lineStr) & linefeed)
		else
			my bufferLine(linefeed)
		end if
	end repeat
end writeMultilineNote

on writeCheckItems(checkItems)
	if (count of checkItems) is 0 then return
	repeat with ci in checkItems
		my bufferLine("   - " & (item 1 of ci) & " " & my escapeOrg(item 2 of ci) & linefeed)
	end repeat
end writeCheckItems

on writeTaskNode(level, stat, rec, extraTags)
	set nodeTitle to item 1 of rec
	set nodeStart to item 3 of rec
	set nodeDue to item 4 of rec
	set nodeRecur to item 5 of rec
	set nodeTagList to item 6 of rec
	set nodeNoteText to item 7 of rec
	set nodeClosedDate to item 8 of rec
	set nodeCheckItems to item 9 of rec
	
	set nodeNoteText to my cleanNotes(nodeNoteText)
	
	set mergedTags to nodeTagList
	repeat with et in extraTags
		set mergedTags to mergedTags & {et}
	end repeat
	set tagStr to my orgTagString(mergedTags)
	
	set headline to level & " " & stat & " " & my escapeOrg(nodeTitle)
	if tagStr is not "" then set headline to headline & "  " & tagStr
	my bufferLine(headline & linefeed)
	
	if nodeClosedDate is not "" then
		my bufferLine("   CLOSED: [" & nodeClosedDate & "]" & linefeed)
	end if
	set repeater to my rruleToRepeater(nodeRecur, REPEATER_STYLE)
	set scheduledD to nodeStart
	if scheduledD is "" and nodeRecur is not "" and nodeDue is not "" then
		set scheduledD to nodeDue
	end if
	if scheduledD is not "" then
		my bufferLine("   SCHEDULED: " & my orgDate(scheduledD, repeater) & linefeed)
	end if
	if nodeDue is not "" then
		my bufferLine("   DEADLINE: " & my orgDate(nodeDue, "") & linefeed)
	end if
	if nodeNoteText is not "" then
		my writeMultilineNote(nodeNoteText)
	end if
	my writeCheckItems(nodeCheckItems)
end writeTaskNode

----------------------------------------------------------------------
-- MAIN
----------------------------------------------------------------------
set orgBuffer to ""
set USERNAME to do shell script "whoami"

set OBSIDIAN_DIR to "/Users/" & USERNAME & "/Library/Mobile Documents/iCloud~md~obsidian/Documents/Life/GTD"
set BACKUP_ROOT to "/Users/" & USERNAME & "/Things3_Backups"

do shell script "mkdir -p " & quoted form of OBSIDIAN_DIR
do shell script "mkdir -p " & quoted form of BACKUP_ROOT

set theDate to do shell script "date '+%Y-%m-%d_%H-%M-%S'"
set theNow to do shell script "date -u '+%Y-%m-%dT%H:%M:%SZ'"

set orgFile to OBSIDIAN_DIR & "/gtd.org"
set orgFilePath to orgFile

-- Clear the file natively
try
	set fileRef to open for access (POSIX file orgFilePath) with write permission
	set eof of fileRef to 0
	close access fileRef
on error
	do shell script "rm -f " & quoted form of orgFile & " && touch " & quoted form of orgFile
end try

try
	tell application "Things3" to get name
on error errMsg
	display alert "Things3 Backup Failed" message "Could not connect to Things3: " & errMsg
	error errMsg
end try

set checkMap to my collectAllCheckItems()

----------------------------------------------------------------------
-- DATA COLLECTION
----------------------------------------------------------------------
set projList to {}
set taskList to {}
set inboxList to {}
set looseList to {}

tell application "Things3"
	
	repeat with p in projects
		set pName to name of p as text
		set pID to id of p as text
		set pAreaClean to ""
		set pAreaTag to ""
		if area of p is not missing value then
			set pAreaClean to name of area of p as text
			set pAreaTag to my areaToTag(pAreaClean)
		end if
		set pRawStat to my getTaskStatus(status of p as text)
		set pNoteText to ""
		if notes of p is not "" and notes of p is not missing value then
			set pNoteText to notes of p as text
		end if
		set pDueDate to my isoDate(due date of p)
		set pClosedDate to my isoDate(completion date of p)
		set pTagList to {}
		repeat with eachTag in (tags of p)
			set pTagList to pTagList & {name of eachTag as text}
		end repeat
		set pSomeday to false
		try
			if (list of p) is not missing value then
				if name of list of p as text is "Someday" then set pSomeday to true
			end if
		end try
		set projList to projList & {{pID, pName, pAreaClean, pRawStat, pDueDate, pClosedDate, pNoteText, pTagList, pSomeday, pAreaTag}}
		
		repeat with t in (to dos of p)
			set tRawStat to my getTaskStatus(status of t as text)
			if INCLUDE_COMPLETED or tRawStat is "TODO" then
				set tID to id of t as text
				set tTitle to name of t as text
				set tDueDate to my isoDate(due date of t)
				set tStartDate to my isoDate(activation date of t)
				set tClosedDate to my isoDate(completion date of t)
				set tNoteText to ""
				if notes of t is not "" and notes of t is not missing value then
					set tNoteText to notes of t as text
				end if
				set tRecurRule to ""
				try
					if recurrence of t is not missing value then set tRecurRule to recurrence of t as text
				end try
				set tTagList to {}
				repeat with eachTag in (tags of t)
					set tTagList to tTagList & {name of eachTag as text}
				end repeat
				set tCheckItems to my getCheckItemsForTask(checkMap, tID)
				set taskList to taskList & {{pID, tTitle, tRawStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tCheckItems, pSomeday}}
			end if
		end repeat
	end repeat
	
	repeat with a in areas
		set aNameClean to name of a as text
		set aTag to my areaToTag(aNameClean)
		repeat with t in (to dos of a)
			set tRawStat to my getTaskStatus(status of t as text)
			if INCLUDE_COMPLETED or tRawStat is "TODO" then
				set tID to id of t as text
				set tTitle to name of t as text
				set tDueDate to my isoDate(due date of t)
				set tStartDate to my isoDate(activation date of t)
				set tClosedDate to my isoDate(completion date of t)
				set tNoteText to ""
				if notes of t is not "" and notes of t is not missing value then
					set tNoteText to notes of t as text
				end if
				set tRecurRule to ""
				try
					if recurrence of t is not missing value then set tRecurRule to recurrence of t as text
				end try
				set tTagList to {}
				repeat with eachTag in (tags of t)
					set tTagList to tTagList & {name of eachTag as text}
				end repeat
				set tCheckItems to my getCheckItemsForTask(checkMap, tID)
				set looseList to looseList & {{tTitle, tRawStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tCheckItems, aTag, false}}
			end if
		end repeat
	end repeat
	
	repeat with t in (to dos of list "Inbox")
		set tRawStat to my getTaskStatus(status of t as text)
		if INCLUDE_COMPLETED or tRawStat is "TODO" then
			set tID to id of t as text
			set tTitle to name of t as text
			set tDueDate to my isoDate(due date of t)
			set tStartDate to my isoDate(activation date of t)
			set tClosedDate to my isoDate(completion date of t)
			set tNoteText to ""
			if notes of t is not "" and notes of t is not missing value then
				set tNoteText to notes of t as text
			end if
			set tRecurRule to ""
			try
				if recurrence of t is not missing value then set tRecurRule to recurrence of t as text
			end try
			set tTagList to {}
			repeat with eachTag in (tags of t)
				set tTagList to tTagList & {name of eachTag as text}
			end repeat
			set tCheckItems to my getCheckItemsForTask(checkMap, tID)
			set inboxList to inboxList & {{tTitle, tRawStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tCheckItems}}
		end if
	end repeat
	
	repeat with t in (to dos of list "Someday")
		set tRawStat to my getTaskStatus(status of t as text)
		if INCLUDE_COMPLETED or tRawStat is "TODO" then
			set tID to id of t as text
			set tTitle to name of t as text
			set tDueDate to my isoDate(due date of t)
			set tStartDate to my isoDate(activation date of t)
			set tClosedDate to my isoDate(completion date of t)
			set tNoteText to ""
			if notes of t is not "" and notes of t is not missing value then
				set tNoteText to notes of t as text
			end if
			set tRecurRule to ""
			try
				if recurrence of t is not missing value then set tRecurRule to recurrence of t as text
			end try
			set tTagList to {}
			repeat with eachTag in (tags of t)
				set tTagList to tTagList & {name of eachTag as text}
			end repeat
			set tCheckItems to my getCheckItemsForTask(checkMap, tID)
			set looseList to looseList & {{tTitle, tRawStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tCheckItems, "", true}}
		end if
	end repeat
	
end tell

----------------------------------------------------------------------
-- BUILD ORG BUFFER
----------------------------------------------------------------------
my bufferLine("# -*- mode: org; coding: utf-8 -*-" & linefeed)
my bufferLine("#+TITLE: Life" & linefeed)
my bufferLine("#+DATE: " & theNow & linefeed)
my bufferLine("#+STARTUP: overview" & linefeed)
my bufferLine("#+TODO: IN NEXT WAIT MAYBE | DONE CANCELLED" & linefeed)
my bufferLine("#+PROPERTY: LOGGING nil" & linefeed)
my bufferLine("#+TAGS: { @home @office @phone @computer @errands @email } @waiting project" & linefeed)
my bufferLine(linefeed)

-- Inbox
my bufferLine("* Inbox" & linefeed)
repeat with td in inboxList
	set tStat to my resolveTaskStat(item 2 of td, item 6 of td, false)
	set rec to {item 1 of td, item 2 of td, item 3 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td}
	my writeTaskNode("**", tStat, rec, {})
end repeat
my bufferLine(linefeed)

-- Projects with nested tasks
repeat with pd in projList
	set pID to item 1 of pd
	set pName to item 2 of pd
	set pSomeday to item 9 of pd
	set pTagList to item 8 of pd
	set pNoteText to item 7 of pd
	set pDueDate to item 5 of pd
	set pClosedDate to item 6 of pd
	set pAreaTag to item 10 of pd
	
	set pMergedTags to pTagList
	if pAreaTag is not "" then set pMergedTags to pMergedTags & {pAreaTag}
	set pTagStr to my orgTagString(pMergedTags)
	
	-- FIXED: Plain heading "* ProjectName :tags:"
	set pHeading to "* " & my escapeOrg(pName)
	if pTagStr is not "" then set pHeading to pHeading & "  " & pTagStr
	my bufferLine(pHeading & linefeed)
	
	if pClosedDate is not "" then
		my bufferLine("   CLOSED: [" & pClosedDate & "]" & linefeed)
	end if
	if pDueDate is not "" then
		my bufferLine("   DEADLINE: <" & pDueDate & ">" & linefeed)
	end if
	if pNoteText is not "" then
		my writeMultilineNote(pNoteText)
	end if
	
	repeat with td in taskList
		if (item 1 of td as text) is pID then
			set tStat to my resolveTaskStat(item 3 of td, item 7 of td, pSomeday)
			set rec to {item 2 of td, item 3 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td, item 10 of td}
			my writeTaskNode("**", tStat, rec, {})
		end if
	end repeat
	my bufferLine(linefeed)
end repeat

-- Loose + Someday loose
repeat with td in looseList
	set tStat to my resolveTaskStat(item 2 of td, item 6 of td, item 11 of td)
	set extraTags to {}
	if (item 10 of td) is not "" then set extraTags to extraTags & {item 10 of td}
	set rec to {item 1 of td, item 2 of td, item 3 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td}
	my writeTaskNode("*", tStat, rec, extraTags)
end repeat

----------------------------------------------------------------------
-- FINAL FLUSH & BACKUP ROTATION
----------------------------------------------------------------------
my flushToFile()

set backupFile to BACKUP_ROOT & "/" & theDate & "_gtd.org"
do shell script "cp " & quoted form of orgFile & " " & quoted form of backupFile

set allBackups to do shell script "ls -1 " & quoted form of BACKUP_ROOT & "/*_gtd.org 2>/dev/null | sort || true"
if allBackups is not "" then
	set AppleScript's text item delimiters to linefeed
	set backupList to text items of allBackups
	set AppleScript's text item delimiters to ""
	
	set backupCount to count of backupList
	if backupCount > MAX_BACKUPS then
		set deleteCount to backupCount - MAX_BACKUPS
		repeat with i from 1 to deleteCount
			set oldBackup to item i of backupList
			if oldBackup is not "" then
				do shell script "rm -f " & quoted form of oldBackup
			end if
		end repeat
	end if
end if

display notification "Live: Obsidian/Life/GTD/gtd.org" with title "Things3 Sync Fast" subtitle "Backup: " & BACKUP_ROOT
