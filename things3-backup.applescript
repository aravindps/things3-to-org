----------------------------------------------------------------------
-- things3-backup.applescript v3.5
-- Exports Things3 -> single things3.org (beorg / Emacs compatible)
----------------------------------------------------------------------

property MAX_BACKUPS : 10
property REPEATER_STYLE : "++"
property INCLUDE_COMPLETED : true

----------------------------------------------------------------------
-- HANDLERS
----------------------------------------------------------------------

on tmpPath()
	set pid to do shell script "echo $$"
	return "/tmp/things3bak_" & pid & ".txt"
end tmpPath

on slugify(s)
	set cmd to "printf '%s' " & quoted form of s & " | sed 's/[^[:alnum:][:space:]-]//g;s/ /-/g;s/-\\{2,\\}/-/g;s/^-//;s/-$//'"
	return do shell script cmd
end slugify

on stripSpecial(s)
	set cmd to "printf '%s' " & quoted form of s & " | sed 's/[^[:alnum:][:space:]-]//g;s/^[[:space:]]*//;s/[[:space:]]*$//'"
	return do shell script cmd
end stripSpecial

on areaToTag(areaClean)
	if areaClean is "" then return ""
	set cmd to "printf '%s' " & quoted form of areaClean & " | tr '[:upper:] ' '[:lower:]_' | sed 's/__*/_/g;s/^_//;s/_$//'"
	return do shell script cmd
end areaToTag

on escapeOrg(s)
	if s is "" then return ""
	set cmd to "printf '%s' " & quoted form of s & " | tr '[]' '()'"
	return do shell script cmd
end escapeOrg

on isoDate(theDate)
	if theDate is missing value then return ""
	try
		set isoRaw to (theDate as «class isot» as string)
		set datePart to text 1 thru 10 of isoRaw
		set dowCmd to "date -j -f '%Y-%m-%d' " & quoted form of datePart & " '+%a' 2>/dev/null || echo ''"
		set dow to do shell script dowCmd
		if dow is not "" then
			return datePart & " " & dow
		else
			return datePart
		end if
	on error
		return ""
	end try
end isoDate

on getTaskStatus(s)
	if s is "completed" then
		return "DONE"
	else if s is "cancelled" then
		return "CANCELLED"
	else
		return "TODO"
	end if
end getTaskStatus

on rruleToRepeater(rrule, rStyle)
	if rrule is "" then return ""
	set freqCmd to "printf '%s' " & quoted form of rrule & " | grep -oE 'FREQ=[A-Z]+' | cut -d= -f2 || echo ''"
	set freq to do shell script freqCmd
	set intvCmd to "printf '%s' " & quoted form of rrule & " | grep -oE 'INTERVAL=[0-9]+' | cut -d= -f2 || echo '1'"
	set intv to do shell script intvCmd
	if intv is "" then set intv to "1"
	if freq is "DAILY" then
		return rStyle & intv & "d"
	else if freq is "WEEKLY" then
		return rStyle & intv & "w"
	else if freq is "MONTHLY" then
		return rStyle & intv & "m"
	else if freq is "YEARLY" then
		return rStyle & intv & "y"
	else
		return ""
	end if
end rruleToRepeater

on orgDate(isoD, repeater)
	if isoD is "" then return ""
	if repeater is "" then
		return "<" & isoD & ">"
	else
		return "<" & isoD & " " & repeater & ">"
	end if
end orgDate

on cleanTag(tg)
	set cmd to "printf '%s' " & quoted form of tg & " | LC_ALL=en_US.UTF-8 perl -CS -pe 's/[\\x{1F000}-\\x{1FFFF}\\x{2600}-\\x{27BF}\\x{FE00}-\\x{FEFF}\\x{1F300}-\\x{1F9FF}]//g' | sed 's/[^[:alnum:]_]/_/g' | tr '[:upper:]' '[:lower:]' | sed 's/__*/_/g;s/^_//;s/_$//'"
	return do shell script cmd
end cleanTag

on orgTagString(tagList)
	if (count of tagList) is 0 then return ""
	set r to ":"
	repeat with tg in tagList
		set c to my cleanTag(tg as text)
		if c is not "" then set r to r & c & ":"
	end repeat
	if r is ":" then return ""
	return r
end orgTagString

on writeFile(filePath, tmp, content)
	set fileRef to open for access POSIX file tmp with write permission
	set eof fileRef to 0
	write content to fileRef as «class utf8»
	close access fileRef
	do shell script "cat " & quoted form of tmp & " >> " & quoted form of filePath
end writeFile

on initFile(filePath)
	do shell script "rm -f " & quoted form of filePath & " && touch " & quoted form of filePath
end initFile

on writeMultilineNote(orgFile, tmp, noteText)
	set AppleScript's text item delimiters to linefeed
	set noteLines to text items of noteText
	set AppleScript's text item delimiters to ""
	repeat with noteLine in noteLines
		set lineStr to noteLine as text
		if lineStr is not "" then
			my writeFile(orgFile, tmp, "   " & my escapeOrg(lineStr) & linefeed)
		else
			my writeFile(orgFile, tmp, linefeed)
		end if
	end repeat
end writeMultilineNote

on writeCheckItems(orgFile, tmp, checkItems)
	if (count of checkItems) is 0 then return
	repeat with ci in checkItems
		my writeFile(orgFile, tmp, "   - " & (item 1 of ci) & " " & my escapeOrg(item 2 of ci) & linefeed)
	end repeat
end writeCheckItems

----------------------------------------------------------------------
-- collectCheckItems
-- Uses run script to defer compilation so the outer AppleScript
-- parser never sees "check item" as a class name directly.
-- taskID: Things3 unique id string of the to do
----------------------------------------------------------------------
on collectCheckItems(taskID)
	set tCheckItems to {}
	set scpt to "tell application \"Things3\"
		set t to to do id " & quoted form of taskID & "
		set ciList to every check item of t
		set r to {}
		repeat with i from 1 to count of ciList
			set ci to item i of ciList
			set r to r & {{name of ci as text, status of ci as text}}
		end repeat
		return r
	end tell"
	try
		set rawList to run script scpt
		repeat with pair in rawList
			set ciName to item 1 of pair as text
			set ciStat to item 2 of pair as text
			set ciMark to "[ ]"
			if ciStat is "completed" then set ciMark to "[X]"
			set tCheckItems to tCheckItems & {{ciMark, ciName}}
		end repeat
	on error
		-- task has no check items or Things3 version doesn't support them
	end try
	return tCheckItems
end collectCheckItems

----------------------------------------------------------------------
-- writeOrgNode
----------------------------------------------------------------------
on writeOrgNode(orgFile, tmp, orgLevel, nodeStat, nodeTitle, nodeStart, nodeDue, nodeRecur, nodeTagList, nodeNoteText, nodeClosedDate, nodeID, nodeCheckItems, nodeAreaTag)
	set mergedTags to nodeTagList
	if nodeAreaTag is not "" then set mergedTags to mergedTags & {nodeAreaTag}
	set tagStr to my orgTagString(mergedTags)
	
	set headline to orgLevel & " " & nodeStat & " " & my escapeOrg(nodeTitle)
	if tagStr is not "" then set headline to headline & "  " & tagStr
	my writeFile(orgFile, tmp, headline & linefeed)
	
	if nodeClosedDate is not "" then
		my writeFile(orgFile, tmp, "   CLOSED: [" & nodeClosedDate & "]" & linefeed)
	end if
	set repeater to my rruleToRepeater(nodeRecur, REPEATER_STYLE)
	set scheduledD to nodeStart
	if scheduledD is "" and nodeRecur is not "" and nodeDue is not "" then
		set scheduledD to nodeDue
	end if
	if scheduledD is not "" then
		my writeFile(orgFile, tmp, "   SCHEDULED: " & my orgDate(scheduledD, repeater) & linefeed)
	end if
	if nodeDue is not "" then
		my writeFile(orgFile, tmp, "   DEADLINE: " & my orgDate(nodeDue, "") & linefeed)
	end if
	
	my writeFile(orgFile, tmp, "   :PROPERTIES:" & linefeed)
	if nodeID is not "" then
		my writeFile(orgFile, tmp, "   :ID:        " & nodeID & linefeed)
		my writeFile(orgFile, tmp, "   :THINGS_URL: things:///show?id=" & nodeID & linefeed)
	end if
	if nodeRecur is not "" then
		my writeFile(orgFile, tmp, "   :RECURRENCE: " & nodeRecur & linefeed)
	end if
	my writeFile(orgFile, tmp, "   :END:" & linefeed)
	
	if nodeNoteText is not "" then
		my writeMultilineNote(orgFile, tmp, nodeNoteText)
	end if
	my writeCheckItems(orgFile, tmp, nodeCheckItems)
end writeOrgNode

----------------------------------------------------------------------
-- MAIN
----------------------------------------------------------------------
set USERNAME to do shell script "whoami"
set BACKUP_ROOT to "/Users/" & USERNAME & "/Documents/Things3-Backups"
set theDate to do shell script "date '+%Y-%m-%d'"
set theNow to do shell script "date -u '+%Y-%m-%dT%H:%M:%SZ'"
set backupDir to BACKUP_ROOT & "/" & theDate
do shell script "mkdir -p " & quoted form of backupDir
set orgFile to backupDir & "/things3.org"
set tmp to my tmpPath()
my initFile(orgFile)

-- Guard: verify Things3 is reachable before proceeding
try
	tell application "Things3" to get name
on error errMsg
	display alert "Things3 Backup Failed" message "Could not connect to Things3: " & errMsg
	error errMsg
end try

----------------------------------------------------------------------
-- DATA COLLECTION
-- projList:         1=slug      2=title      3=areaClean  4=stat      5=created
--                   6=due       7=closed     8=noteText   9=tagList   10=inSomeday
--                   11=projID   12=areaTag
-- taskList:         1=projSlug  2=title      3=stat       4=startDate 5=dueDate
--                   6=recur     7=tagList    8=noteText   9=closedDate 10=taskID
--                   11=checkItems  12=areaTag
-- inboxList:        1=title     2=stat       3=startDate  4=dueDate   5=recur
--                   6=tagList   7=noteText   8=closedDate 9=taskID    10=checkItems
-- somedayLooseList: same as inboxList
----------------------------------------------------------------------
set projList to {}
set taskList to {}
set inboxList to {}
set somedayLooseList to {}

tell application "Things3"
	
	----------------------------------------------------------------------
	-- Projects + their tasks
	----------------------------------------------------------------------
	repeat with p in projects
		set pName to name of p as text
		set pSlug to my slugify(pName)
		set pid to id of p as text
		set pAreaClean to ""
		set pAreaTag to ""
		if area of p is not missing value then
			set pAreaClean to my stripSpecial(name of area of p as text)
			set pAreaTag to my areaToTag(pAreaClean)
		end if
		set pStat to my getTaskStatus(status of p as text)
		set pNoteText to ""
		if notes of p is not "" and notes of p is not missing value then
			set pNoteText to notes of p as text
		end if
		set pCreated to my isoDate(creation date of p)
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
		on error
			-- list property unavailable; treat as non-Someday
		end try
		set projList to projList & {{pSlug, pName, pAreaClean, pStat, pCreated, pDueDate, pClosedDate, pNoteText, pTagList, pSomeday, pid, pAreaTag}}
		
		repeat with t in (to dos of p)
			set tStat to my getTaskStatus(status of t as text)
			if INCLUDE_COMPLETED or tStat is "TODO" then
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
				set tCheckItems to my collectCheckItems(tID)
				set taskList to taskList & {{pSlug, tTitle, tStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tID, tCheckItems, pAreaTag}}
			end if
		end repeat
	end repeat
	
	----------------------------------------------------------------------
	-- Loose area tasks (in area, not in any project)
	----------------------------------------------------------------------
	repeat with a in areas
		set aNameClean to my stripSpecial(name of a as text)
		set aTag to my areaToTag(aNameClean)
		set aLooseSlug to "__loose__" & aNameClean
		repeat with t in (to dos of a)
			set tStat to my getTaskStatus(status of t as text)
			if INCLUDE_COMPLETED or tStat is "TODO" then
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
				set tCheckItems to my collectCheckItems(tID)
				set taskList to taskList & {{aLooseSlug, tTitle, tStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tID, tCheckItems, aTag}}
			end if
		end repeat
	end repeat
	
	----------------------------------------------------------------------
	-- Inbox tasks
	----------------------------------------------------------------------
	repeat with t in (to dos of list "Inbox")
		set tStat to my getTaskStatus(status of t as text)
		if INCLUDE_COMPLETED or tStat is "TODO" then
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
			set tCheckItems to my collectCheckItems(tID)
			set inboxList to inboxList & {{tTitle, tStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tID, tCheckItems}}
		end if
	end repeat
	
	----------------------------------------------------------------------
	-- Someday loose tasks
	----------------------------------------------------------------------
	repeat with t in (to dos of list "Someday")
		set tStat to my getTaskStatus(status of t as text)
		if INCLUDE_COMPLETED or tStat is "TODO" then
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
			set tCheckItems to my collectCheckItems(tID)
			set somedayLooseList to somedayLooseList & {{tTitle, tStat, tStartDate, tDueDate, tRecurRule, tTagList, tNoteText, tClosedDate, tID, tCheckItems}}
		end if
	end repeat
	
end tell

----------------------------------------------------------------------
-- WRITE things3.org
----------------------------------------------------------------------
my writeFile(orgFile, tmp, "# -*- mode: org; coding: utf-8 -*-" & linefeed)
my writeFile(orgFile, tmp, "#+TITLE: Things3 Backup" & linefeed)
my writeFile(orgFile, tmp, "#+DATE: " & theNow & linefeed)
my writeFile(orgFile, tmp, "#+STARTUP: overview" & linefeed)
my writeFile(orgFile, tmp, "#+TODO: TODO | DONE CANCELLED" & linefeed)
my writeFile(orgFile, tmp, linefeed)

----------------------------------------------------------------------
-- Inbox
----------------------------------------------------------------------
my writeFile(orgFile, tmp, "* Inbox" & linefeed)
repeat with td in inboxList
	my writeOrgNode(orgFile, tmp, "**", item 2 of td, item 1 of td, item 3 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td, item 10 of td, "")
end repeat
my writeFile(orgFile, tmp, linefeed)

----------------------------------------------------------------------
-- Projects (flat, area as tag, excludes Someday projects)
----------------------------------------------------------------------
my writeFile(orgFile, tmp, "* Projects" & linefeed)
repeat with pd in projList
	if (item 10 of pd) is false then
		set pSlug to item 1 of pd
		set pAreaTag to item 12 of pd
		set pMergedTags to item 9 of pd
		if pAreaTag is not "" then set pMergedTags to pMergedTags & {pAreaTag}
		set pTagStr to my orgTagString(pMergedTags)
		set pHeading to "** " & (item 4 of pd) & " " & my escapeOrg(item 2 of pd)
		if pTagStr is not "" then set pHeading to pHeading & "  " & pTagStr
		my writeFile(orgFile, tmp, pHeading & linefeed)
		if (item 7 of pd) is not "" then
			my writeFile(orgFile, tmp, "   CLOSED: [" & (item 7 of pd) & "]" & linefeed)
		end if
		if (item 6 of pd) is not "" then
			my writeFile(orgFile, tmp, "   DEADLINE: <" & (item 6 of pd) & ">" & linefeed)
		end if
		my writeFile(orgFile, tmp, "   :PROPERTIES:" & linefeed)
		my writeFile(orgFile, tmp, "   :ID:        " & (item 11 of pd) & linefeed)
		my writeFile(orgFile, tmp, "   :THINGS_URL: things:///show?id=" & (item 11 of pd) & linefeed)
		if (item 3 of pd) is not "" then
			my writeFile(orgFile, tmp, "   :AREA:      " & (item 3 of pd) & linefeed)
		end if
		my writeFile(orgFile, tmp, "   :CREATED:   " & (item 5 of pd) & linefeed)
		my writeFile(orgFile, tmp, "   :END:" & linefeed)
		if (item 8 of pd) is not "" then
			my writeMultilineNote(orgFile, tmp, item 8 of pd)
		end if
		repeat with td in taskList
			if item 1 of td is pSlug then
				my writeOrgNode(orgFile, tmp, "***", item 3 of td, item 2 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td, item 10 of td, item 11 of td, item 12 of td)
			end if
		end repeat
		my writeFile(orgFile, tmp, linefeed)
	end if
end repeat

-- Loose area tasks — "__loose__" prefix is exactly 9 characters
repeat with td in taskList
	set tSlug to item 1 of td as text
	if (length of tSlug > 9) and (text 1 thru 9 of tSlug is "__loose__") then
		my writeOrgNode(orgFile, tmp, "**", item 3 of td, item 2 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td, item 10 of td, item 11 of td, item 12 of td)
	end if
end repeat
my writeFile(orgFile, tmp, linefeed)

----------------------------------------------------------------------
-- Someday
----------------------------------------------------------------------
my writeFile(orgFile, tmp, "* Someday" & linefeed)
repeat with pd in projList
	if (item 10 of pd) is true then
		set pSlug to item 1 of pd
		set pAreaTag to item 12 of pd
		set pMergedTags to item 9 of pd
		if pAreaTag is not "" then set pMergedTags to pMergedTags & {pAreaTag}
		set pTagStr to my orgTagString(pMergedTags)
		set pHeading to "** " & (item 4 of pd) & " " & my escapeOrg(item 2 of pd)
		if pTagStr is not "" then set pHeading to pHeading & "  " & pTagStr
		my writeFile(orgFile, tmp, pHeading & linefeed)
		if (item 7 of pd) is not "" then
			my writeFile(orgFile, tmp, "   CLOSED: [" & (item 7 of pd) & "]" & linefeed)
		end if
		if (item 6 of pd) is not "" then
			my writeFile(orgFile, tmp, "   DEADLINE: <" & (item 6 of pd) & ">" & linefeed)
		end if
		my writeFile(orgFile, tmp, "   :PROPERTIES:" & linefeed)
		my writeFile(orgFile, tmp, "   :ID:        " & (item 11 of pd) & linefeed)
		my writeFile(orgFile, tmp, "   :THINGS_URL: things:///show?id=" & (item 11 of pd) & linefeed)
		my writeFile(orgFile, tmp, "   :CREATED:   " & (item 5 of pd) & linefeed)
		my writeFile(orgFile, tmp, "   :END:" & linefeed)
		if (item 8 of pd) is not "" then
			my writeMultilineNote(orgFile, tmp, item 8 of pd)
		end if
		repeat with td in taskList
			if item 1 of td is pSlug then
				my writeOrgNode(orgFile, tmp, "***", item 3 of td, item 2 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td, item 10 of td, item 11 of td, item 12 of td)
			end if
		end repeat
		my writeFile(orgFile, tmp, linefeed)
	end if
end repeat
repeat with td in somedayLooseList
	my writeOrgNode(orgFile, tmp, "**", item 2 of td, item 1 of td, item 3 of td, item 4 of td, item 5 of td, item 6 of td, item 7 of td, item 8 of td, item 9 of td, item 10 of td, "")
end repeat
my writeFile(orgFile, tmp, linefeed)

----------------------------------------------------------------------
-- CLEANUP TMP
----------------------------------------------------------------------
do shell script "rm -f " & quoted form of tmp

----------------------------------------------------------------------
-- ROTATION
----------------------------------------------------------------------
set allBackups to do shell script "ls -1d " & quoted form of BACKUP_ROOT & "/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] 2>/dev/null | sort"
set AppleScript's text item delimiters to linefeed
set backupList to text items of allBackups
set AppleScript's text item delimiters to ""
set backupCount to count of backupList
if backupCount > MAX_BACKUPS then
	set deleteCount to backupCount - MAX_BACKUPS
	repeat with i from 1 to deleteCount
		set oldBackup to item i of backupList
		if oldBackup is not "" then do shell script "rm -rf " & quoted form of oldBackup
	end repeat
end if

display notification "Saved: " & orgFile with title "Things3 Backup v3.5"
