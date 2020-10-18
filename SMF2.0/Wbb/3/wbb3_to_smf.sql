/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Burning Board 3.0"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/wbb3_migration.php"
---~ globals: wcf_prefix, wbb_prefix
---~ from_prefix: "`$wbb3_database`."
---~ table_test: "{$from_prefix}{$wbb_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;
ALTER TABLE {$to_prefix}members
CHANGE COLUMN password_salt password_salt varchar(255) NOT NULL default '';

---* {$to_prefix}members
---{
$request = convert_query("
	SELECT groupID
	FROM {$from_prefix}{$wcf_prefix}user_to_groups
	WHERE userID = $row[id_member]");

while ($groups = convert_fetch_assoc($request))
{
	if (in_array('4', $groups))
		$row['id_group'] = '1';
	elseif (in_array('5', $groups))
		$row['id_group'] = '2';
	elseif (in_array('6', $groups))
		$row['id_group'] = '2';
}
convert_free_result($request);

$row['signature'] = preg_replace(
	array(
		'~\[size=(.+?)\]~is',
		'~\[align=left\](.+?)\[\/align\]~is',
		'~\[align=right\](.+?)\[\/align\]~is',
		'~\[align=center\](.+?)\[\/align\]~is',
		'~\[align=justify\](.+?)\[\/align\]~is',
		'~.Geneva, Arial, Helvetica, sans-serif.~is',
		'~.Tahoma, Arial, Helvetica, sans-serif.~is',
		'~.Arial, Helvetica, sans-serif.~is',
		'~.Chicago, Impact, Compacta, sans-serif.~is',
		'~.Comic Sans MS, sans-serif.~is',
		'~.Courier New, Courier, mono.~is',
		'~.Georgia, Times New Roman, Times, serif.~is',
		'~.Helvetica, Verdana, sans-serif.~is',
		'~.Impact, Compacta, Chicago, sans-serif.~is',
		'~.Lucida Sans, Monaco, Geneva, sans-serif.~is',
		'~.Times New Roman, Times, Georgia, serif.~is',
		'~.Trebuchet MS, Arial, sans-serif.~is',
		'~.Verdana, Helvetica, sans-serif.~is',
		'~\[list=1\]\[\*\]~is',
		'~\[list\]\[\*\]~is',
		'~\[\*\]~is',
		'~\[\/list\]~is',
		),

	array(
		'[size=$1pt]',
		'[left]$1[/left]',
		'[right]$1[/right]',
		'[center]$1[/center]',
		'$1',
		'Geneva',
		'Tahoma',
		'Arial',
		'Chicago',
		'Comic Sans MS',
		'Courier New',
		'Georgia',
		'Helvetica',
		'Impact',
		'Lucida Sans',
		'Times New Roman',
		'Trebuchet MS',
		'Verdana',
		'[list type=decimal][li]',
		'[list][li]',
		'[/li][li]',
		'[/li][/list]',
	),
	trim($row['signature'])
);

---}

SELECT
	u.userID AS id_member, SUBSTRING(u.username, 1, 80) AS member_name,
	IF (p.Posts IS NULL, 0, p.Posts) AS posts, u.registrationDate AS date_registered,
	u.lastActivityTime AS last_login,SUBSTRING(u.username, 1, 255) AS real_name,
	u.password AS passwd, SUBSTRING(u.email, 1, 64) AS email_address,
	v.userOption17 AS website_title,	v.userOption17 AS website_url, '' AS icq, '' AS aim,
	'' AS yim, '' AS msn,
	IF(IFNULL(v.userOption12, '') = '', 0, v.userOption12) AS gender,
	v.userOption11 AS birthdate,
	'' AS show_online, '' AS personal_text, '0' AS id_group, '' AS hide_email,
	'' AS time_offset, SUBSTRING(u.signature, 1, 65534) AS signature, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	v.userOption13 AS location, '' AS time_format, '' AS avatar, '' AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, salt AS password_salt,
	'' AS member_ip2
FROM {$from_prefix}wcf1_user AS u
	LEFT JOIN {$from_prefix}{$wcf_prefix}user_option_value AS v ON (u.userID = v.userID)
	LEFT JOIN {$from_prefix}{$wbb_prefix}user AS p ON (u.userID = p.UserID);
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	c.boardID AS id_cat, SUBSTRING(c.title, 1, 255) AS name,
	o.position AS cat_order
FROM {$from_prefix}{$wbb_prefix}board AS c
	LEFT JOIN {$from_prefix}{$wbb_prefix}board_structure AS o ON (o.boardID = c.boardID)
WHERE boardType = 1;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

/* The converter will set id_cat for us based on id_parent being wrong. */
---* {$to_prefix}boards
SELECT
	b.boardID AS id_board, o.parentID AS id_parent, o.position AS board_order,
	SUBSTRING(b.title, 1, 255) AS name, SUBSTRING(b.description, 1, 65534) AS description,
	b.threads AS num_topics,	b.countUserPosts AS num_posts, '1' AS member_groups
FROM {$from_prefix}{$wbb_prefix}board AS b
	LEFT JOIN {$from_prefix}{$wbb_prefix}board_structure AS o ON (o.boardID = b.boardID)
WHERE boardType = 0;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics
---{
// Find out assigned polls
$request = convert_query("
	SELECT
		pollID
	FROM {$from_prefix}{$wbb_prefix}post
	WHERE threadID = $row[id_topic] AND pollID > 0
	GROUP BY threadID");

list ($pollID) = convert_fetch_row($request);
convert_free_result($request);
if ($pollID > 0)
	$row['id_poll'] = $pollID;
---}

SELECT
	t.threadID AS id_topic, t.is_sticky AS is_sticky, t.boardID AS id_board,
	t.replies AS num_replies, t.views AS num_views, t.isClosed AS locked,
	t.userID AS id_member_started, t.lastPosterID AS id_member_updated,
	t.firstPostID AS id_first_msg, MAX(p.postid) AS id_last_msg,
	p.pollID AS id_poll
FROM {$from_prefix}{$wbb_prefix}thread AS t
	LEFT JOIN {$from_prefix}{$wbb_prefix}post AS p ON (p.threadID = t.threadID)
GROUP BY t.threadID
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~\[size=(.+?)\]~is',
		'~\[align=left\](.+?)\[\/align\]~is',
		'~\[align=right\](.+?)\[\/align\]~is',
		'~\[align=center\](.+?)\[\/align\]~is',
		'~\[align=justify\](.+?)\[\/align\]~is',
		'~.Geneva, Arial, Helvetica, sans-serif.~is',
		'~.Tahoma, Arial, Helvetica, sans-serif.~is',
		'~.Arial, Helvetica, sans-serif.~is',
		'~.Chicago, Impact, Compacta, sans-serif.~is',
		'~.Comic Sans MS, sans-serif.~is',
		'~.Courier New, Courier, mono.~is',
		'~.Georgia, Times New Roman, Times, serif.~is',
		'~.Helvetica, Verdana, sans-serif.~is',
		'~.Impact, Compacta, Chicago, sans-serif.~is',
		'~.Lucida Sans, Monaco, Geneva, sans-serif.~is',
		'~.Times New Roman, Times, Georgia, serif.~is',
		'~.Trebuchet MS, Arial, sans-serif.~is',
		'~.Verdana, Helvetica, sans-serif.~is',
		'~\[list=1\]\[\*\]~is',
		'~\[list\]\[\*\]~is',
		'~\[\*\]~is',
		'~\[\/list\]~is',
		),

	array(
		'[size=$1pt]',
		'[left]$1[/left]',
		'[right]$1[/right]',
		'[center]$1[/center]',
		'$1',
		'Geneva',
		'Tahoma',
		'Arial',
		'Chicago',
		'Comic Sans MS',
		'Courier New',
		'Georgia',
		'Helvetica',
		'Impact',
		'Lucida Sans',
		'Times New Roman',
		'Trebuchet MS',
		'Verdana',
		'[list type=decimal][li]',
		'[list][li]',
		'[/li][li]',
		'[/li][/list]',
	),
	trim($row['body'])
);
---}
SELECT
	p.postID AS id_msg, p.threadID AS id_topic, t.boardID AS id_board,
	p.time AS poster_time, p.userID AS id_member,
	SUBSTRING(IF(p.subject = '',t.topic , p.subject), 1, 255) AS subject,
	SUBSTRING(IFNULL(u.username, p.username), 1, 255) AS poster_name,
	SUBSTRING(p.ipAddress, 1, 255) AS poster_ip,
	SUBSTRING(IFNULL(u.email, ''), 1, 255) AS poster_email,
	p.enableSmilies AS smileys_enabled,
	SUBSTRING(REPLACE(p.message, '<br>', '<br />'), 1, 65534) AS body,
	p.lastEditTime AS modified_name, 'xx' AS icon
FROM {$from_prefix}wbb1_1_post AS p
	INNER JOIN {$from_prefix}{$wbb_prefix}thread AS t ON (t.threadID = p.threadID)
	LEFT JOIN {$from_prefix}{$wcf_prefix}user AS u ON (u.userID = p.userID);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/
ALTER TABLE {$to_prefix}poll_choices
	ADD old_choice INT( 12 ) unsigned NOT NULL;
TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pollID AS id_poll, SUBSTRING(p.question , 1, 255) AS question,
	t.userID AS id_member, p.endTime AS expire_time,
	SUBSTRING(IFNULL(t.username, ''), 1, 255) AS poster_name,
	choiceCount AS max_votes
FROM {$from_prefix}{$wcf_prefix}poll AS p
	LEFT JOIN {$from_prefix}{$wbb_prefix}post AS m ON (p.pollID = m.pollID)
	LEFT JOIN {$from_prefix}{$wbb_prefix}thread AS t ON (m.threadID = t.threadID);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
if (!isset($_SESSION['convert_last_poll']) || $_SESSION['convert_last_poll'] != $row['id_poll'])
{
	$_SESSION['convert_last_poll'] = $row['id_poll'];
	$_SESSION['convert_last_choice'] = 0;
}
$row['id_choice'] = ++$_SESSION['convert_last_choice'];
---}
SELECT
	pollID AS id_poll, 1 AS id_choice, SUBSTRING(pollOption, 1, 255) AS label,
	votes AS votes, pollOptionID AS old_choice
FROM {$from_prefix}{$wcf_prefix}poll_option
ORDER BY pollID;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT
	v.pollID AS id_poll, v.userID AS id_member, c.id_choice AS id_choice
FROM {$from_prefix}{$wcf_prefix}poll_option_vote AS v
	LEFT JOIN {$to_prefix}poll_choices AS c ON (v.pollOptionID = c.old_choice)
GROUP BY id_poll, id_member;
---*

/******************************************************************************/
--- Converting poll votes (part 2 - Fallback for migrated WBB2 boards)...
/******************************************************************************/

---* {$to_prefix}log_polls
---{
$ignore = true;
---}
SELECT
	pollID AS id_poll, userID AS id_member, 1 AS id_choice
FROM {$from_prefix}{$wcf_prefix}poll_vote
GROUP BY id_poll, id_member;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/
ALTER TABLE {$to_prefix}poll_choices
	DROP old_choice;

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($_POST['path_from'] . '/wcf/attachments/attachment-' . $row['attachmentID'] , $attachmentUploadDir . '/' . $physical_filename))
{
		$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
	);
	$id_attach++;
}
---}
SELECT
	attachmentID, messageID AS id_msg, downloads AS downloads, attachmentName AS filename
FROM {$from_prefix}{$wcf_prefix}attachment;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/
TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace(
	array(
		'~\[size=(.+?)\]~is',
		'~\[align=left\](.+?)\[\/align\]~is',
		'~\[align=right\](.+?)\[\/align\]~is',
		'~\[align=center\](.+?)\[\/align\]~is',
		'~\[align=justify\](.+?)\[\/align\]~is',
		'~.Geneva, Arial, Helvetica, sans-serif.~is',
		'~.Tahoma, Arial, Helvetica, sans-serif.~is',
		'~.Arial, Helvetica, sans-serif.~is',
		'~.Chicago, Impact, Compacta, sans-serif.~is',
		'~.Comic Sans MS, sans-serif.~is',
		'~.Courier New, Courier, mono.~is',
		'~.Georgia, Times New Roman, Times, serif.~is',
		'~.Helvetica, Verdana, sans-serif.~is',
		'~.Impact, Compacta, Chicago, sans-serif.~is',
		'~.Lucida Sans, Monaco, Geneva, sans-serif.~is',
		'~.Times New Roman, Times, Georgia, serif.~is',
		'~.Trebuchet MS, Arial, sans-serif.~is',
		'~.Verdana, Helvetica, sans-serif.~is',
		'~\[list=1\]\[\*\]~is',
		'~\[list\]\[\*\]~is',
		'~\[\*\]~is',
		'~\[\/list\]~is',
		),

	array(
		'[size=$1pt]',
		'[left]$1[/left]',
		'[right]$1[/right]',
		'[center]$1[/center]',
		'$1',
		'Geneva',
		'Tahoma',
		'Arial',
		'Chicago',
		'Comic Sans MS',
		'Courier New',
		'Georgia',
		'Helvetica',
		'Impact',
		'Lucida Sans',
		'Times New Roman',
		'Trebuchet MS',
		'Verdana',
		'[list type=decimal][li]',
		'[list][li]',
		'[/li][li]',
		'[/li][/list]',
	),
	trim($row['body'])
);
---}

SELECT
	pmID AS id_pm, userID AS id_member_from, '0' AS deleted_by_sender,
	time AS msgtime, username from_name, SUBSTRING(subject, 1, 255) AS subject,
	SUBSTRING(message, 1, 65534) AS body
FROM {$from_prefix}{$wcf_prefix}pm;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/
TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pmID AS id_pm, recipientID AS id_member,
	IF(isViewed > 0, 1, 0) AS is_read, IF(isDeleted = 1, 1, 0) AS deleted,
	'-1' AS labels, isBlindCopy AS bcc
FROM {$from_prefix}{$wcf_prefix}pm_to_user;
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($_POST['path_from'] . '/wcf/images/avatars/avatar-' . $row['avatarID'] . '.' . $row['avatarExtension'], $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_member' => $row['id_member'],
	);
	$id_attach++;
}
---}
SELECT
	avatarID, avatarName AS filename, userid AS id_member, avatarExtension
FROM {$from_prefix}{$wcf_prefix}avatar;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/
TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT
	userID AS id_member, threadID AS id_topic
FROM {$from_prefix}{$wbb_prefix}thread_subscription;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/
TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT
	userID AS id_member, boardID AS id_board
FROM {$from_prefix}{$wbb_prefix}board_subscription;
---*

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/
---* {$to_prefix}smileys
---{
$no_add = true;
$keys = array('code', 'filename', 'description', 'smpath', 'hidden');

$row['filename'] = preg_replace('~images\/smilies\/~is', '', $row['filename']);

if (!isset($smf_smileys_directory))
{
	// Find the path for SMF avatars.
	$request = convert_query("
		SELECT value
		FROM {$to_prefix}settings
		WHERE variable = 'smileys_dir'
		LIMIT 1");

	list ($smf_smileys_directory) = convert_fetch_row($request);
	convert_free_result($request);
}

$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'smiley_enable'
	LIMIT 1");

list ($smiley_enable) = convert_fetch_row($request);
convert_free_result($request);

if (isset($smiley_enable))
	convert_query("
		UPDATE {$to_prefix}settings
		SET value = '1'
		WHERE variable='smiley_enable'");

else
	convert_insert('settings', array('variable' => 'string', 'value' => 'string'),
		array('smiley_enable', '1'), 'ignore'
	);

if (is_file($_POST['path_from'] . '/wcf/images/smilies/'. $row['filename']))
{
	copy($_POST['path_from'] . '/wcf/images/smilies/'. $row['filename'] , $smf_smileys_directory . '/default/'.$row['filename']);

	convert_insert('smileys', array('code' => 'string', 'filename' => 'string', 'description' => 'string', 'hidden' => 'int'),
		array($row['code'], $row['newfilename'], $row['description'], 1), 'ignore'
	);
}
---}
SELECT
	smileyPath AS filename, smileyCode AS code, smileyTitle AS description
FROM {$from_prefix}{$wcf_prefix}smiley;
---*

/******************************************************************************/
--- Converting buddys..
/******************************************************************************/
---{
$no_add = true;
$keys = array('id_member', 'buddy_list');

$request = convert_query("
	SELECT userID AS tmp_member
	FROM {$from_prefix}{$wcf_prefix}user_whitelist
	GROUP BY userID");

while ($row = convert_fetch_assoc($request))
{
	$buddies = array();
	$request2 = convert_query("
		SELECT
			userID id_member, whiteUserID AS buddy_list
		FROM {$from_prefix}{$wcf_prefix}user_whitelist
		WHERE userID = $row[tmp_member]");

	while ($row2 = convert_fetch_assoc($request2))
	{
		array_push($buddies, $row2['buddy_list']);
		$buddylist = implode(',',$buddies);
	}

	convert_query("
		UPDATE {$to_prefix}members
		SET buddy_list = '$buddylist'
		WHERE id_member = $row[tmp_member]");
}
convert_free_result($request);
---}