/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "UBB.threads 6.4/6.5"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.inc.php", "/includes/config.inc.php"
---~ globals: config
---~ from_prefix: "`$config[dbname]`.$config[tbprefix]"
---~ table_test: "{$from_prefix}Users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	U_Number AS id_member, SUBSTRING(U_LoginName, 1, 80) AS member_name,
	U_Totalposts AS posts, U_Registered AS date_registered,
	U_Laston AS last_login, SUBSTRING(U_Title, 1, 255) AS usertitle,
	IF(U_Status = 'Administrator', 1, 0) AS id_group,
	SUBSTRING(U_Password, 1, 64) AS passwd,
	SUBSTRING(U_Username, 1, 255) AS real_name,
	SUBSTRING(U_Email, 1, 255) AS email_address,
	SUBSTRING(U_Homepage, 1, 255) AS website_title,
	SUBSTRING(U_Homepage, 1, 255) AS website_url,
	SUBSTRING(U_Location, 1, 255) AS location,
	SUBSTRING(U_Signature, 1, 65534) AS signature,
	U_TimeOffset AS time_format,
	SUBSTRING(IFNULL(U_Picture, ''), 1, 255) AS avatar, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS icq, '' AS aim, '' AS yim, '' AS msn,
	'' AS time_format, '' AS member_ip, '' AS secret_question, '' AS secret_answer,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set,
	'' AS password_salt, '' AS member_ip2
FROM {$from_prefix}Users
WHERE U_Number != 0;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT Cat_Number AS id_cat, Cat_Title AS name
FROM {$from_prefix}Category
WHERE Cat_Number != 0
GROUP BY Cat_Number;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	Bo_Number AS id_board, Bo_Cat AS id_cat, Bo_Title AS name,
	Bo_Description AS description, Bo_Threads AS num_topics, Bo_Total AS num_posts
FROM {$from_prefix}Boards;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics
SELECT
	p.B_Number AS id_topic, p.B_Sticky AS is_sticky, p.B_Number AS id_first_msg,
	p.B_PosterId AS id_member_started, p.B_Replies AS num_replies,
	p.B_Counter AS num_views, IF(p.B_Status = 'C', 1, 0) AS locked,
	b.Bo_Number AS id_board, MAX(p2.B_Number) AS id_last_msg
FROM {$from_prefix}Posts AS p
	INNER JOIN {$from_prefix}Boards AS b ON (b.Bo_Keyword = p.B_Board)
	INNER JOIN {$from_prefix}Posts AS p2 ON (p2.B_Main = p.B_Number)
WHERE p.B_Topic = 1
GROUP BY p.B_Number
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, p.B_PosterId AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}Posts AS p ON (p.B_Number = t.id_last_msg);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
SELECT
	p.B_Number AS id_msg, IF(p.B_Main = 0, p.B_Number, p.B_Main) AS id_topic,
	p.B_Posted AS poster_time, p.B_PosterId AS id_member,
	SUBSTRING(p.B_Subject, 1, 255) AS subject,
	SUBSTRING(IFNULL(u.U_Username, 'Guest'), 1, 255) AS poster_name,
	SUBSTRING(p.B_IP, 1, 255) AS poster_ip,
	SUBSTRING(IFNULL(u.U_Email, ''), 1, 255) AS poster_email,
	b.Bo_Number AS id_board,
	SUBSTRING(REPLACE(p.B_Body, '<br>', '<br />'), 1, 65534) AS body,
	'' AS modified_name, 'xx' AS icon
FROM {$from_prefix}Posts AS p
	INNER JOIN {$from_prefix}Boards AS b ON (b.Bo_Keyword = p.B_Board)
	LEFT JOIN {$from_prefix}Users AS u ON (u.U_Number = p.B_PosterId);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
---{
convert_query("
	UPDATE {$to_prefix}topics
	SET id_poll = $row[id_poll]
	WHERE id_topic = $row[id_topic]
	LIMIT 1");
unset($row['id_topic']);
---}
SELECT
	pq.P_QuestionNum AS id_poll, SUBSTRING(pq.P_Question, 1, 255) AS question,
	IF(pq.P_ChoiceType = 'one', 1, 8) AS max_votes, pm.P_Stop AS expire_time,
	pt.B_PosterId AS id_member, pt.B_Number AS id_topic,
	SUBSTRING(IFNULL(u.U_Username, 'Guest'), 1, 255) AS poster_name,
	pm.P_NoResults AS hide_results
FROM {$from_prefix}PollQuestions AS pq
	INNER JOIN {$from_prefix}PollMain AS pm ON (pm.P_Id = pq.P_PollId)
	INNER JOIN {$from_prefix}Posts AS pt ON (pt.B_Poll = pq.P_PollId)
	LEFT JOIN {$from_prefix}Users AS u ON (u.U_Number = pt.B_PosterId)
WHERE pt.B_Main = 1
GROUP BY pq.P_PollId;
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
SELECT
	po.P_QuestionNum AS id_poll, po.P_OptionNum AS id_choice,
	SUBSTRING(po.P_Option, 1, 255) AS label, COUNT(pv.P_QuestionNum) AS votes
FROM {$from_prefix}PollOptions AS po
	LEFT JOIN {$from_prefix}PollVotes AS pv ON (po.P_QuestionNum = pv.P_QuestionNum AND po.P_OptionNum = pv.P_OptionNum)
GROUP BY po.P_QuestionNum, po.P_OptionNum;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	m.M_Number AS id_pm, m.M_Sender AS id_member_from, m.M_Sent AS msgtime,
	SUBSTRING(IFNULL(u.U_Username, 'Guest'), 1, 255) AS from_name,
	SUBSTRING(m.M_Subject, 1, 255) AS subject,
	SUBSTRING(m.M_Message, 1, 65534) AS body
FROM {$from_prefix}Messages AS m
	LEFT JOIN {$from_prefix}Users AS u ON (u.U_Number = m.M_Sender);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	M_Number AS id_pm, M_Uid AS id_member, M_Status != 'N' AS is_read,
	'-1' AS labels
FROM {$from_prefix}Messages;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT mods.Mod_Uid AS id_member, b.Bo_Number AS id_board
FROM {$from_prefix}Moderators AS mods
	INNER JOIN {$from_prefix}Boards AS b ON (b.Bo_Keyword = mods.Mod_Board);
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT F_Thread AS id_topic, F_Owner AS id_member
FROM {$from_prefix}Favorites;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT S_Board AS id_board, S_Uid AS id_member
FROM {$from_prefix}Subscribe;
---*

/******************************************************************************/
--- Converting buddies...
/******************************************************************************/

---# Clear out everyones buddy list just incase...
UPDATE {$to_prefix}members
SET buddy_list = '';
---#

---# Get all the buddies...
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT Add_Owner AS id_member, Add_Member AS ID_BUDDY
		FROM {$from_prefix}AddressBook
		LIMIT $_REQUEST[start], 250");
	while ($row = convert_fetch_assoc($result))
	{
		$row['ID_BUDDY'] = (int) $row['ID_BUDDY'];

		convert_query("
			UPDATE {$to_prefix}members
			SET buddy_list = IF(buddy_list = '', '$row[ID_BUDDY]', CONCAT(buddy_list, ',$row[ID_BUDDY]'))
			WHERE id_member = $row[id_member]
			LIMIT 1");
	}

	$_REQUEST['start'] += 250;
	if (convert_num_rows($result) < 250)
		break;

	convert_free_result($result);
}

$_REQUEST['start'] = 0;
---}
---#

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

// Try to get a better filename!
$oldFilename = $row['ID_MDG'] . '-' .$row['filename'];
$row['filename'] = strpos($oldFilename, '-') !== false ? substr($oldFilename, strpos($oldFilename, '-') + 1) : $oldFilename;
$row['size'] = filesize($GLOBALS['config']['files'] . '/' . $row['filename']);

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($GLOBALS['config']['files'] . '/' . $oldFilename, $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => $row['size'],
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
	);

	$id_attach++;
}
---}
SELECT B_File AS filename, B_Number AS id_msg, B_FileCounter AS downloads
FROM {$from_prefix}Posts
WHERE B_FILE != 'NULL';
---*