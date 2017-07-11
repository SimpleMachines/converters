/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Burning Board 2.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/acp/lib/config.inc.php"
---~ from_prefix: "`$sqldb`.bb{$n}_"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting ranks...
/******************************************************************************/

DELETE FROM {$to_prefix}membergroups
WHERE min_posts != -1
	AND id_group != 4;

---* {$to_prefix}membergroups
---{
// Do the stars!
if (trim($row['stars']) != '')
	$row['stars'] = sprintf("%d#star.gif", substr_count($row['stars'], ';') + 1);
---}
SELECT
	SUBSTRING(ranktitle, 1, 80) AS group_name, needposts AS min_posts,
	'' AS online_color, rankimages AS stars
FROM {$from_prefix}ranks
WHERE groupid NOT IN (1, 2, 3)
ORDER BY needposts;
---*

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---{
$test = convert_query("
	SELECT groupcombinationid
	FROM {$from_prefix}groupcombinations
	LIMIT 1");

// This is /not/ beautiful but we can support 2.0.x too with it.
if ($test)
{
	$_SESSION['group_id_clause'] = 'gc.groupids';
	$_SESSION['group_id_join'] = "LEFT JOIN {$from_prefix}groupcombinations AS gc ON (gc.groupcombinationid = u.groupcombinationid)";
	$_SESSION['password_clause'] = "IF(u.sha1_password != '', u.sha1_password, u.password)";
}
else
{
	$_SESSION['group_id_clause'] = 'u.groupid';
	$_SESSION['group_id_join'] = '';
	$_SESSION['password_clause'] = 'u.password';
}
---}

---* {$to_prefix}members
---{
// Do we need to load the groups first?
if (!isset($admin_groups))
{
	$admin_groups = array();
	$gmod_groups = array();

	$result = convert_query("
		SELECT groupid, securitylevel
		FROM {$from_prefix}groups
		WHERE securitylevel > 1");
	if ($result)
	{
		while ($row2 = convert_fetch_assoc($result))
		{
			if ($row2['securitylevel'] > 3)
				$admin_groups[] = $row2['groupid'];
			else
				$gmod_groups[] = $row2['groupid'];
		}
	}
	else
	{
		$result = convert_query("
			SELECT groupid, issupermod, canuseacp
			FROM {$from_prefix}groups
			WHERE issupermod OR canuseacp");
		while ($row2 = convert_fetch_assoc($result))
		{
			if ($row2['canuseacp'])
				$admin_groups[] = $row2['groupid'];
			else
				$gmod_groups[] = $row2['groupid'];
		}
	}
	convert_free_result($result);
}
$allGroups = explode(',', $row['id_group']);
// Default to nothing...
$row['id_group'] = 0;
foreach ($allGroups as $id_group)
{
	// Admin?
	if (in_array($id_group, $admin_groups))
		$row['id_group'] = 1;
	elseif (in_array($id_group, $gmod_groups))
		$row['id_group'] = 2;
}

$row['signature'] = substr(preg_replace('~\[size=([789]|[012]\d)\]~is', '[size=$1pt]', $row['signature']), 0, 65534);
---}
SELECT
	u.userid AS id_member, SUBSTRING(u.username, 1, 80) AS member_name,
	u.userposts AS posts, u.regdate AS date_registered,
	{$_SESSION['group_id_clause']} AS id_group,
	SUBSTRING(u.title, 1, 255) AS usertitle, u.lastvisit AS last_login,
	SUBSTRING(u.username, 1, 255) AS real_name,
	SUBSTRING(u.email, 1, 255) AS email_address,
	{$_SESSION['password_clause']} AS passwd,
	SUBSTRING(u.icq, 1, 255) AS icq, SUBSTRING(u.aim, 1, 16) AS aim,
	SUBSTRING(u.yim, 1, 32) AS yim, SUBSTRING(u.msn, 1, 255) AS msn,
	SUBSTRING(u.homepage, 1, 255) AS website_title,
	SUBSTRING(u.homepage, 1, 255) AS website_url, u.birthday AS birthdate,
	IF(u.invisible = 0, 1, 0) AS show_online, u.gender,
	SUBSTRING(u.usertext, 1, 255) AS personal_text,
	IF(u.showemail = 0, 1, 0) AS hide_email,
	u.signature AS signature, u.timezoneoffset AS time_offset, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS location, '' AS time_format, '' AS avatar, '' AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt,
	'' AS member_ip2
FROM {$from_prefix}users AS u
	{$_SESSION['group_id_join']};
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

if (copy($_POST['path_from'] . '/images/avatars/avatar-' . $row['avatarid'] . '.' . $row['avatarextension'], $attachmentUploadDir . '/' . $physical_filename))
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
	avatarid, SUBSTRING(CONCAT(avatarname, '.', avatarextension), 1, 255) AS filename,
	userid AS id_member, avatarextension
FROM {$from_prefix}avatars;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	boardid AS id_cat, SUBSTRING(title, 1, 255) AS name,
	boardorder AS cat_order
FROM {$from_prefix}boards
WHERE isboard = 0;
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
	boardid AS id_board, parentid AS id_parent, boardorder AS board_order,
	SUBSTRING(title, 1, 255) AS name, SUBSTRING(description, 1, 65534) AS description,
	threadcount AS num_topics, postcount AS num_posts, '-1, 0' AS member_groups
FROM {$from_prefix}boards
WHERE isboard = 1;
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
	t.threadid AS id_topic, t.important AS is_sticky, t.boardid AS id_board,
	t.replycount AS num_replies, t.views AS num_views, t.closed AS locked,
	t.starterid AS id_member_started, t.lastposterid AS id_member_updated,
	MIN(p.postid) AS id_first_msg, MAX(p.postid) AS id_last_msg,
	t.pollid AS id_poll
FROM {$from_prefix}threads AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.threadid = t.threadid)
GROUP BY t.threadid
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace('~\[size=([789]|[012]\d)\]~is', '[size=$1pt]', $row['body']);
---}
SELECT
	p.postid AS id_msg, p.threadid AS id_topic, t.boardid AS id_board,
	p.posttime AS poster_time, p.userid AS id_member,
	SUBSTRING(t.topic, 1, 255) AS subject, p.ipaddress AS poster_ip,
	SUBSTRING(IFNULL(u.username, p.username), 1, 255) AS poster_name,
	SUBSTRING(IFNULL(u.email, ''), 1, 255) AS poster_email,
	allowsmilies AS smileys_enabled,
	SUBSTRING(REPLACE(p.message, '<br>', '<br />'), 1, 65534) AS body,
	'' AS modified_name, 'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}threads AS t ON (t.threadid = p.threadid)
	LEFT JOIN {$from_prefix}users AS u ON (u.userid = p.userid);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pollid AS id_poll, SUBSTRING(p.question , 1, 255) AS question,
	t.starterid AS id_member,
	IF(p.timeout = 0, 0, (p.starttime + 86400 * p.timeout)) AS expire_time,
	SUBSTRING(IFNULL(u.username, ''), 1, 255) AS poster_name,
	choicecount AS max_votes
FROM {$from_prefix}polls AS p
	INNER JOIN {$from_prefix}threads AS t ON (p.threadid = t.threadid)
	LEFT JOIN {$from_prefix}users AS u ON (u.userid = t.starterid);
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
SELECT pollid AS id_poll, 1 AS id_choice,
SUBSTRING(polloption, 1, 255) AS label, votes
FROM {$from_prefix}polloptions
ORDER BY pollid;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT id AS id_poll, userid AS id_member
FROM {$from_prefix}votes
GROUP BY id_poll, id_member;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace('~\[size=([789]|[012]\d)\]~is', '[size=$1pt]', $row['body']);
---}
SELECT
	pm.privatemessageid AS id_pm, pm.senderid AS id_member_from,
	IF(pm.deletepm = 2, 1, 0) AS deleted_by_sender, pm.sendtime AS msgtime,
	SUBSTRING(IFNULL(u.username, 'Guest'), 1, 255) AS from_name,
	SUBSTRING(pm.subject, 1, 255) AS subject,
	SUBSTRING(pm.message, 1, 65534) AS body
FROM {$from_prefix}privatemessage AS pm
	LEFT JOIN {$from_prefix}users AS u ON (u.userid = pm.senderid);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm.privatemessageid AS id_pm, pm.recipientid AS id_member, 1 AS is_read,
	IF(pm.deletepm = 1, 1, 0) AS deleted, '-1' AS labels
FROM {$from_prefix}privatemessage AS pm;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT s.userid AS id_member, s.threadid AS id_topic
FROM {$from_prefix}subscribethreads AS s;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT s.userid AS id_member, s.boardid AS id_board
FROM {$from_prefix}subscribeboards AS s;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT m.userid AS id_member, m.boardid AS id_board
FROM {$from_prefix}moderators AS m;
---*

/******************************************************************************/
--- Converting banned users (by IP)...
/******************************************************************************/

TRUNCATE {$to_prefix}ban_items;
TRUNCATE {$to_prefix}ban_groups;

---# Moving banned entries...
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT value
		FROM {$from_prefix}options
		WHERE varname = 'ban_ip'
		LIMIT " . (int) $_REQUEST['start'] . ", 25");
	$ban_time = time();
	$ban_count = $_REQUEST['start'] + 1;
	while ($row = convert_fetch_assoc($result))
	{
		$ips = explode("\n", $row['value']);
		foreach ($ips as $ip)
		{
			$ip = trim($ip);
			$sections = explode('.', $ip);

			if (empty($sections[0]))
				continue;

			$ip_low1 = $sections[0];
			$ip_high1 = $sections[0];

			$ip_low2 = isset($sections[1]) && $sections[1] != '*' ? $sections[1] : 0;
			$ip_high2 = isset($sections[1]) && $sections[1] != '*' ? $sections[1] : 255;

			$ip_low3 = isset($sections[2]) && $sections[2] != '*' ? $sections[2] : 0;
			$ip_high3 = isset($sections[2]) && $sections[2] != '*' ? $sections[2] : 255;

			$ip_low4 = isset($sections[3]) && $sections[3] != '*' ? $sections[3] : 0;
			$ip_high4 = isset($sections[3]) && $sections[3] != '*' ? $sections[3] : 255;

			convert_insert('ban_groups', array('name' => 'string', 'ban_time' => 'int', 'expire_time' => 'int', 'reason' => 'string', 'notes' => 'string', 'cannot_access' => 'int'),
				array("migrated_ban_" . $ban_count++, $ban_time, 0, '', 'Migrated from Burning Board', 1)
			);
			$id_ban_group = convert_insert_id();

			if (empty($id_ban_group))
				continue;

			convert_insert('ban_items', array('id_ban_group' => 'int', 'ip_low1' => 'int', 'ip_high1' => 'int', 'ip_low2' => 'int', 'ip_high2' => 'int', 'ip_low3' => 'int', 'ip_high3' => 'int', 'ip_low4' => 'int', 'ip_high4' => 'int', 'email_address' => 'string', 'hostname' => 'string'),
				array($id_ban_group, $ip_low1, $ip_high1, $ip_low2, $ip_high2, $ip_low3, $ip_high3, $ip_low4, $ip_high4, '', '')
			);
		}
	}

	$_REQUEST['start'] += 25;
	if (convert_num_rows($result) < 25)
		break;

	convert_free_result($result);
}
$_REQUEST['start'] = 0;
---}
---#

/******************************************************************************/
--- Converting banned users (by email)...
/******************************************************************************/

---# Moving banned entries...
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT value
		FROM {$from_prefix}options
		WHERE varname = 'ban_email'
		LIMIT " . (int) $_REQUEST['start'] . ", 25");
	$ban_time = time();
	$ban_count = $_REQUEST['start'] + 1;
	while ($row = convert_fetch_assoc($result))
	{
		$emails = explode("\n", $row['value']);
		foreach ($emails as $email)
		{
			$email = trim($email);

			if (empty($email))
				continue;

			convert_insert('ban_groups', array('name' => 'string', 'ban_time' => 'int', 'expire_time' => 'int', 'reason' => 'string', 'notes' => 'string', 'cannot_access' => 'int'),
				array("migrated_ban_" . $ban_count++, $ban_time, 0, '', 'Migrated from Burning Board', 1)
			);

			$id_ban_group = convert_insert_id();

			if (empty($id_ban_group))
				continue;

			convert_insert('ban_items', array('id_ban_group' => 'int', 'email_address' => 'string', 'hostname' => 'string'),
				array($id_ban_group, $email, '')
			);
		}
	}

	$_REQUEST['start'] += 25;
	if (convert_num_rows($result) < 25)
		break;

	convert_free_result($result);
}
$_REQUEST['start'] = 0;
---}
---#

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

UPDATE {$to_prefix}smileys
SET hidden = 1;

---{
$specificSmileys = array(
	':)' => 'smiley',
	':))' => 'smiley',
	':]' => 'cheesy',
	'?(' => 'huh',
	'8)' => 'cool',
	':(' => 'sad',
	':D' => 'grin',
	';(' => 'cry',
	'8o' => 'shocked',
	':O' => 'embarrassed',
	';)' => 'wink',
	':P' => 'tongue',
	':tongue:' => 'tongue',
	':baby:' => 'angel',
	':rolleyes:' => 'rolleyes',
	':evil:' => 'evil',
	'X(' => 'angry',
);

$request = convert_query("
	SELECT MAX(smiley_order)
	FROM {$to_prefix}smileys");
list ($count) = convert_fetch_row($request);
convert_free_result($request);

$request = convert_query("
	SELECT code
	FROM {$to_prefix}smileys");
$currentCodes = array();
while ($row = convert_fetch_assoc($request))
	$currentCodes[] = $row['code'];
convert_free_result($request);

$rows = array();
foreach ($specificSmileys as $code => $name)
{
	if (in_array($code, $currentCodes))
		continue;

	$count++;
	$rows[] = array(substr($code, 0, 30), substr($name . '.gif', 0, 48), substr($name, 0, 80), $count);
}

if (!empty($rows))
	convert_insert('smileys', array('code' => 'string', 'filename' => 'string', 'description' => 'string', 'smiley_order' => 'int'), $rows, 'replace');
---}

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getAttachmentFilename($row['filename'], $id_attach);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;
if (copy($_POST['path_from'] . '/attachments/attachment-' . $row['attachmentid'] . '.' . $row['attachmentextension'], $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'id_msg' => $row['id_msg'],
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'fileext' => $row['attachmentextension'],
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'downloads' => $row['downloads'],
	);

	$id_attach++;
}
---}
SELECT
	attachmentid, postid AS id_msg, counter AS downloads, attachmentextension,
	SUBSTRING(CONCAT(attachmentname, '.', attachmentextension), 1, 255) AS filename
FROM {$from_prefix}attachments;
---*