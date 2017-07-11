/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "YaBB SE 1.5.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/Settings.php"
---~ from_prefix: "`$db_name`.$db_prefix"
---~ globals: language, timeout, timeoffset, MembersPerPage, Show_RecentBar, userpic_width, userpic_height
---~ globals: facesdir, facesurl, maxmessagedisplay, maxdisplay, Cookie_Length, RegAgree, emailpassword, emailnewpass, emailwelcome
---~ globals: allow_hide_email, timeformatstring, guestaccess, MaxMessLen, MaxSigLen, enable_ubbc, mbname
---~ globals: JrPostNum, FullPostNum, SrPostNum, GodPostNum
---~ table_test: "{$from_prefix}members"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	mem.id_member, SUBSTRING(mem.member_name, 1, 80) AS member_name,
	mem.date_registered, mem.posts, SUBSTRING(mem.passwd, 1, 64) AS passwd,
	SUBSTRING(mem.website_title, 1, 255) AS website_title,
	SUBSTRING(mem.website_url, 1, 255) AS website_url, mem.last_login,
	mem.birthdate, SUBSTRING(mem.icq, 1, 255) AS icq,
	SUBSTRING(IFNULL(mem.real_name, mem.member_name), 1, 255) AS real_name,
	mem.notify_once AS notify_once, REPLACE(mem.lngfile, '.lng', '') AS lngfile,
	SUBSTRING(mem.email_address, 1, 255) AS email_address,
	SUBSTRING(mem.aim, 1, 16) AS aim,
	SUBSTRING(mem.personal_text, 1, 255) AS personal_text,
	SUBSTRING(mem.time_format, 1, 80) AS time_format,
	mem.hide_email, SUBSTRING(mem.member_ip, 1, 255) AS member_ip,
	SUBSTRING(mem.member_ip, 1, 255) AS member_ip2,
	SUBSTRING(mem.yim, 1, 32) AS yim,
	IF(IFNULL(mem.gender, '') = '', 0, IF(mem.gender = 'Male', 1, 2)) AS gender,
	SUBSTRING(mem.msn, 1, 255) AS msn,
	SUBSTRING(REPLACE(mem.signature, '<br>', '<br />'), 1, 65534) AS signature,
	SUBSTRING(mem.location, 1, 255) AS location, mem.time_offset,
	SUBSTRING(mem.avatar, 1, 255) AS avatar,
	SUBSTRING(mem.usertitle, 1, 255) AS usertitle,
	mem.im_email_notify AS pm_email_notify, mem.karma_bad, mem.karma_good,
	mem.notify_announcements,
	SUBSTRING(mem.secret_question, 1, 255) AS secret_question,
	IF(mem.secret_answer = '', '', MD5(mem.secret_answer)) AS secret_answer,
	CASE
		WHEN mem.memberGroup = 'Administrator' THEN 1
		WHEN mem.memberGroup = 'Global Moderator' THEN 2
		WHEN mg.id_group = 8 THEN 2
		WHEN mg.id_group = 1 THEN 1
		WHEN mg.id_group > 8 THEN mg.id_group
		ELSE 0
	END AS id_group, '' AS buddy_list, '' AS pm_ignore_list,
	'' AS message_labels, '' AS validation_code, '' AS additional_groups,
	'' AS smiley_set, '' AS password_salt
FROM {$from_prefix}members AS mem
	LEFT JOIN {$from_prefix}membergroups AS mg ON (mg.membergroup = mem.memberGroup);
---*

UPDATE IGNORE {$to_prefix}members
SET pm_ignore_list = '*'
WHERE pm_ignore_list RLIKE '([\n,]|^)[*]([\n,]|$)';

---{
while (true)
{
	pastTime($substep);

	$request = convert_query("
		SELECT id_member, im_ignore_list
		FROM {$from_prefix}members
		WHERE im_ignore_list RLIKE '[a-z]'
		LIMIT 512");
	while ($row2 = convert_fetch_assoc($request))
	{
		$request2 = convert_query("
			SELECT id_member
			FROM {$to_prefix}members
			WHERE FIND_IN_SET(member_name, '" . addslashes($row2['im_ignore_list']) . "')");
		$im_ignore_list = '';
		while ($row3 = convert_fetch_assoc($request2))
			$im_ignore_list .= ',' . $row3['id_member'];
		convert_free_result($request2);

		convert_query("
			UPDATE {$to_prefix}members
			SET pm_ignore_list = '" . substr($im_ignore_list, 1) . "'
			WHERE id_member = $row2[id_member]
			LIMIT 1");
	}
	if (convert_num_rows($request) < 512)
		break;
	convert_free_result($request);
}
---}

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id_cat, SUBSTRING(name, 1, 255) AS name, cat_order
FROM {$from_prefix}categories;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	id_board, id_cat, SUBSTRING(name, 1, 255) AS name, board_order,
	SUBSTRING(description, 1, 65534) AS description, num_topics, num_posts,
	`count` AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}boards;
---*

---# Updating access permissions...
---{
$request = convert_query("
	SELECT membergroup, id_group
	FROM {$from_prefix}membergroups
	WHERE id_group = 1 OR id_group > 7");
$member_groups = array();
while ($row2 = convert_fetch_row($request))
	$member_groups[trim($row2[0])] = $row2[1];
convert_free_result($request);

$result = convert_query("
	SELECT TRIM(member_groups) AS member_groups, id_cat
	FROM {$from_prefix}categories");
while ($row2 = convert_fetch_assoc($result))
{
	if (trim($row2['member_groups']) == '')
		$groups = '-1,0,2';
	else
	{
		$membergroups = array_unique(explode(',', $row2['member_groups']));
		$groups = array(2);
		foreach ($membergroups as $k => $check)
		{
			$membergroups[$k] = trim($membergroups[$k]);
			if ($membergroups[$k] == '' || !isset($member_groups[$membergroups[$k]]) || $member_groups[$membergroups[$k]] == 8)
				continue;

			$groups[] = $member_groups[$membergroups[$k]];
		}
		$groups = implode(',', array_unique($groups));
	}

	convert_query("
		UPDATE {$to_prefix}boards
		SET member_groups = '$groups'
		WHERE id_cat = $row2[id_cat]");
}
---}

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics
SELECT
	id_topic, id_board, is_sticky, IF(id_poll = -1, 0, id_poll) AS id_poll,
	num_views, id_member_started, id_member_updated, num_replies, locked,
	id_first_msg, id_last_msg
FROM {$from_prefix}topics
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$ignore = true;
---}

SELECT
	m.id_msg, m.id_topic, t.id_board, m.id_member, m.poster_time,
	SUBSTRING(m.poster_name, 1, 255) AS poster_name,
	SUBSTRING(m.poster_email, 1, 255) AS poster_email,
	SUBSTRING(m.poster_ip, 1, 255) AS poster_ip,
	SUBSTRING(m.subject, 1, 255) AS subject,
	m.smiliesEnabled AS smileys_enabled,
	m.modified_time,
	SUBSTRING(m.modified_name, 1, 255) AS modified_name,
	SUBSTRING(REPLACE(m.body, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}messages AS m
	INNER JOIN {$from_prefix}topics AS t ON (t.id_topic = m.id_topic);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.id_poll, SUBSTRING(p.question, 1, 255) AS question, p.voting_locked,
	t.id_member_started AS id_member,
	SUBSTRING(IFNULL(mem.real_name, 'Guest'), 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	INNER JOIN {$from_prefix}topics AS t ON (t.id_poll = p.id_poll)
	LEFT JOIN {$from_prefix}members AS mem ON (mem.id_member = t.id_member_started);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

for ($i = 1; $i <= 8; $i++)
{
		$rows[] = array(
		'id_poll' => $row['id_poll'],
		'id_choice' => $i,
		'label' => substr('" . addslashes($row['option' . $i]) . "', 1, 255),
		'votes' => (is_numeric($row['votes' . $i]) ? $row['votes' . $i] : 0),
	);
}
---}
SELECT
	id_poll, option1, option2, option3, option4, option5, option6, option7,
	option8, votes1, votes2, votes3, votes4, votes5, votes6, votes7, votes8
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
---{
$no_add = true;

$members = explode(',', $row['id_member']);
foreach ($members as $member)
	if (is_numeric($member))
		$rows[] = "$row[id_poll], $member, 0";
---}
SELECT id_poll, votedMemberIDs AS id_member, 0 AS id_choice
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	ID_IM AS id_pm, id_member_from, msgtime,
	SUBSTRING(from_name, 1, 255) AS from_name,
	SUBSTRING(subject, 1, 255) AS subject,
	SUBSTRING(body, 1, 65534) AS body,
	IF(deletedBy = 0, 1, 0) AS deleted_by_sender
FROM {$from_prefix}instant_messages;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	ID_IM AS id_pm, id_member_TO AS id_member, IF(readBy = 1, 1, 0) AS is_read,
	IF(deletedBy = 1, 1, 0) AS deleted, '-1' AS labels
FROM {$from_prefix}instant_messages;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT m.id_member, lt.id_topic, lt.notificationSent AS sent
FROM {$from_prefix}log_topics AS lt
	INNER JOIN {$from_prefix}members AS m ON (lt.id_member = m.id_member)
WHERE notificationSent != 0;
---*

---{
$result = convert_query("
	SELECT COUNT(*)
	FROM {$from_prefix}topics
	WHERE notifies != ''");
list ($numNotifies) = convert_fetch_row($result);
convert_free_result($result);

$_GET['start'] = (int) @$_GET['start'];

while ($_GET['start'] < $numNotifies)
{
	pastTime($substep);

	/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
	convert_query("
		INSERT IGNORE INTO {$to_prefix}log_notify
			(id_member, id_topic)
		SELECT mem.id_member, t.id_topic
		FROM {$from_prefix}topics AS t
			INNER JOIN {$from_prefix}members AS mem
		WHERE FIND_IN_SET(mem.id_member, t.notifies)
			AND t.notifies != ''
		LIMIT $_GET[start], 512");

	$_GET['start'] += 512;
}

unset($_GET['start']);
---}

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

if (!isset($yAttachmentDir))
{
	$result = convert_query("
		SELECT value
		FROM {$from_prefix}settings
		WHERE variable = 'attachmentUploadDir'
		LIMIT 1");
	list ($yAttachmentDir) = convert_fetch_row($result);
	convert_free_result($result);
}

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

$fp2 = @fopen($yAttachmentDir . '/' . $row['filename']);
while (!feof($fp2))
	fwrite($fp, fread($fp2, 2048));

fclose($fp);

$rows[] = array(
	'id_attach' => $id_attach,
	'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
	'filename' => $row['filename'],
	'file_hash' => $file_hash,
	'id_msg' => $row['id_msg'],
	'downloads' => 0,
);
$id_attach++;
---}
SELECT id_msg, attachmentFilename AS filename
FROM {$from_prefix}messages
WHERE attachmentFilename IS NOT NULL
	AND attachmentFilename != '';
---*

/******************************************************************************/
--- Converting activity logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_activity;

---* {$to_prefix}log_activity
SELECT
	(year * 10000 + month * 100 + day) AS date, hits, topics, posts, registers,
	mostOn as most_on
FROM {$from_prefix}log_activity;
---*

/******************************************************************************/
--- Converting banning logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_banned;

---* {$to_prefix}log_banned
SELECT SUBSTRING(ip, 1, 16) AS ip, SUBSTRING(email, 1, 255) AS email
FROM {$from_prefix}log_banned;
---*

/******************************************************************************/
--- Converting mark as read history...
/******************************************************************************/

TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}log_boards
SELECT id_board, id_member
FROM {$from_prefix}log_boards;
---*

/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
REPLACE INTO {$to_prefix}log_boards
	(id_board, id_member)
SELECT lmr.id_board, lmr.id_member
FROM {$from_prefix}log_mark_read AS lmr
	LEFT JOIN {$from_prefix}log_boards AS lb ON (lb.id_board = lmr.id_board AND lb.id_member = lmr.id_member)
WHERE lb.log_time < lmr.log_time;

---* {$to_prefix}log_mark_read
SELECT id_board, id_member
FROM {$from_prefix}log_mark_read;
---*

/******************************************************************************/
--- Converting karma logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_karma;

---* {$to_prefix}log_karma
SELECT id_target, id_executor, log_time, action
FROM {$from_prefix}log_karma;
---*

/******************************************************************************/
--- Converting topic view logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_topics;

---* {$to_prefix}log_topics
SELECT id_topic, id_member
FROM {$from_prefix}log_topics;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
---{
$no_add = true;

$members = array_unique(explode(',', $row['id_member']));
foreach ($members as $k => $check)
{
	$members[$k] = trim($members[$k]);
	if ($members[$k] == '')
		unset($members[$k]);
}

$result_mods = convert_query("
	SELECT id_member
	FROM {$to_prefix}members
	WHERE member_name IN ('" . implode("', '", $members) . "')
	LIMIT " . count($members));
while ($row_mods = convert_fetch_assoc($result_mods))
	$rows[] = "$row[id_board], $row_mods[id_member]";
convert_free_result($result_mods);
---}
SELECT id_board, moderators AS id_member
FROM {$from_prefix}boards;
---*

/******************************************************************************/
--- Converting banned members...
/******************************************************************************/

TRUNCATE {$to_prefix}ban_items;
TRUNCATE {$to_prefix}ban_groups;

---{
if (!function_exists('ip2range'))
{
	function ip2range($fullip)
	{
		$ip_parts = explode('.', $fullip);
		if (count($ip_parts) != 4)
			return array();
		$ip_array = array();
		for ($i = 0; $i < 4; $i++)
		{
			if ($ip_parts[$i] == '*')
				$ip_array[$i] = array('low' => '0', 'high' => '255');
			elseif (preg_match('/^(\d{1,3})\-(\d{1,3})$/', $ip_parts[$i], $range))
				$ip_array[$i] = array('low' => $range[1], 'high' => $range[2]);
			elseif (is_numeric($ip_parts[$i]))
				$ip_array[$i] = array('low' => $ip_parts[$i], 'high' => $ip_parts[$i]);
		}
		if (count($ip_array) == 4)
			return $ip_array;
		else
			return array();
	}
}

$request = convert_query("
	SELECT ban.type, ban.value, mem.id_member
	FROM {$from_prefix}banned AS ban
		LEFT JOIN {$from_prefix}members AS mem ON (mem.member_name = ban.value)");
$rows = array();
while ($row2 = convert_fetch_assoc($request))
{
	if ($row2['type'] == 'ip' && preg_match('/^\d{1,3}\.(\d{1,3}|\*)\.(\d{1,3}|\*)\.(\d{1,3}|\*)$/', $row2['value']))
	{
		$ip_parts = ip2range($row2['value']);
		$rows[] = array($ip_parts[0]['low'], $ip_parts[0]['high'], $ip_parts[1]['low'], $ip_parts[1]['high'], $ip_parts[2]['low'], $ip_parts[2]['high'], $ip_parts[3]['low'], $ip_parts[3]['high'], '', '', 0);
	}
	elseif ($row2['type'] == 'email')
		$rows[] = array(0, 0, 0, 0, 0, 0, 0, 0, '', $row2['value'], 0);
	elseif ($row2['type'] == 'username' && !empty($row2['id_member']))
		$rows[] = array(0, 0, 0, 0, 0, 0, 0, 0, '', '', $row2['id_member']);
}
convert_free_result($request);

// If there were values in the old table, insert them.
if (!empty($rows))
{
	convert_insert('ban_groups', array('name', 'ban_time', 'expire_time', 'reason', 'notes', 'cannot_access'),
		array("migrated_ban", time(), NULL, '', 'Migrated from YaBB SE', 1)
	$id_ban_group = convert_insert_id();

	convert_insert('ban_items', array('id_ban_group', 'ip_low1', 'ip_high1', 'ip_low2', 'ip_high2', 'ip_low3', 'ip_high3', 'ip_low4', 'ip_high4', 'hostname', 'email_address', 'id_member'), $rows, 1)
}
---}

/******************************************************************************/
--- Converting calendar events...
/******************************************************************************/

TRUNCATE {$to_prefix}calendar;

---* {$to_prefix}calendar
SELECT
	id AS ID_EVENT, CONCAT(year, '-', month + 1, '-', day) AS start_date,
	CONCAT(year, '-', month + 1, '-', day) AS end_date, id_board AS id_board,
	id_topic AS id_topic, id_member AS id_member,
	SUBSTRING(title, 1, 60) AS title
FROM {$from_prefix}calendar;
---*

/******************************************************************************/
--- Converting membergroups...
/******************************************************************************/

DELETE FROM {$to_prefix}permissions
WHERE id_group > 8;

DELETE FROM {$to_prefix}membergroups
WHERE id_group > 8;

---{
$setString = array(
	array(1, $membergroups[1], '#FF0000', -1, '5#staradmin.gif'),
	array(2, $membergroups[8], '#0000FF', -1, '5#stargmod.gif'),
	array(3, $membergroups[2], '', -1, '5#starmod.gif'),
	array(4, $membergroups[3], '', 0, '1#star.gif'),
	array(5, $membergroups[4], '', $JrPostNum, '2#star.gif'),
	array(6, $membergroups[5], '', $FullPostNum, '3#star.gif'),
	array(7, $membergroups[6], '', $SrPostNum, '4#star.gif'),
	array(8, $membergroups[7], '', $GodPostNum, '5#star.gif'),
);

$request = convert_query("
	SELECT id_group, membergroup
	FROM {$from_prefix}membergroups");
$membergroups = array();
while ($row2 = convert_fetch_assoc($request))
{
	$membergroups[$row2['id_group']] = addslashes($row2['membergroup']);
	if ($row2['id_group'] > 8)
		$setString[] = array($row2['id_group'], $membergroups[$row2['id_group']], '', -1, '');
}
convert_free_result($request);

$grouptitles = array('Administrator', 'Global Moderator', 'Moderator', 'Newbie', 'Junior Member', 'Full Member', 'Senior Member', 'Hero');
for ($i = 1; $i < 9; $i ++)
	$membergroups[$i] = isset($membergroups[$i]) ? $membergroups[$i] : $grouptitles[$i - 1];

convert_insert('membergroups', array('id_group', 'group_name', 'online_color', 'min_posts', 'stars'), $setString, 'replace');
---}

---{
// In addition add permissions for all the "new" groups.
$permissions = array(
	'view_mlist', 'search_posts', 'profile_view_own', 'profile_view_any', 'pm_read', 'pm_send', 'calendar_view',
	'view_stats', 'who_view', 'profile_identity_own', 'profile_extra_own',
	'profile_server_avatar', 'profile_upload_avatar', 'profile_remote_avatar', 'profile_remove_own'
);
$board_permissions = array(
	'remove_own', 'lock_own', 'mark_any_notify', 'mark_notify', 'modify_own',
	'poll_add_own', 'poll_edit_own', 'poll_lock_own', 'poll_post', 'poll_view',
	'poll_vote', 'post_attachment', 'post_new', 'post_reply_any', 'post_reply_own',
	'delete_own', 'report_any', 'send_topic', 'view_attachments'
);

$result = convert_query("
	SELECT id_group
	FROM {$to_prefix}membergroups
	WHERE id_group > 8");
$groups = array();
while ($row2 = convert_fetch_assoc($result))
	$groups[] = $row2['id_group'];
convert_free_result($result);

$setString = array();
foreach ($groups as $group)
{
	foreach ($permissions as $permission)
		$setString[] = array($group, $permission);
}

if (!empty($setString))
	convert_insert('permissions', array('id_group', 'permission'), $setString, 'insert ignore');

$setString = array();
$board_profiles = array()
foreach ($groups as $group)
{
	foreach ($board_permissions as $permission)
	{
		$setString[] = array($group + 4, 0, $permission);
		$board_profiles[] = $group + 4;
	}
}

if (!empty($setString))
	convert_insert('board_permissions', array('id_profile', 'permission'), $setString, 'insert ignore');

// This will set all the boards using custom permissions to their new profiles
convert_query("
	UPDATE {$to_prefix}boards
	SET id_profile = id_board + 4
	WHERE id_board IN (" . implode(',', $board_profiles) . ")");
---}

/******************************************************************************/
--- Converting basic settings...
/******************************************************************************/

---{
updateSettingsFile(array('mbname' => "'$mbname'"));
---}