/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Invision Power Board"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/conf_global.php"
---~ globals: INFO
---~ from_prefix: "`$INFO[sql_database]`.$INFO[sql_tbl_prefix]"
---~ table_test: "{$from_prefix}members"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
$row['signature'] = addslashes(preg_replace(
	array(
		'~<!--QuoteBegin.*?-->.+?<!--QuoteEBegin-->~is',
		'~<!--QuoteEnd-->.+?<!--QuoteEEnd-->~is',
		'~<!--c1-->.+?<!--ec1-->~is',
		'~<!--c2-->.+?<!--ec2-->~is',
		'~<a href=\'mailto:(.+?)\'>.+?</a>~is',
		'~<a href=\'(.+?)\' target=\'_blank\'>(.+?)</a>~is',
		'~<span style=\'color:([^;]+?)\'>(.+?)</span>~is',
		'~<span style=\'font-size:([^;]+?).+?\'>(.+?)</span>~is',
		'~<span style=\'font-family:([^;]+?)\'>(.+?)</span>~is',
		'~<([/]?)ul>~is',
		'~<img src=\'~i',
		'~\' border=\'0\' alt=\'user posted image\'( /)?' . '>~i',
		'~<!--emo&(.+?)-->.+?<!--endemo-->~i',
	),
	array(
		'[quote]',
		'[/quote]',
		'[code]',
		'[/code]',
		'[email]$1[/email]',
		'[url=$1]$2[/url]',
		'[color=$1]$2[/color]',
		'[size=$1]$2[/size]',
		'[font=$1]$2[/font]',
		'[$1list]',
		'[img]',
		'[/img]',
		'$1',
	), ltrim($row['signature'])));
$row['signature'] = substr(strtr(strtr($row['signature'], '<>', '[]'), array('[br /]' => '<br />')), 0, 65534);
---}
SELECT
	id AS id_member, SUBSTRING(name, 1, 80) AS member_name,
	joined AS date_registered, posts,
	IF(mgroup = {$INFO['admin_group']}, 1, IF(mgroup > 5, mgroup + 3, 0)) AS id_group,
	last_visit AS last_login, SUBSTRING(name, 1, 255) AS real_name,
	IFNULL(msg_total, 0) AS instant_messages,
	SUBSTRING(password, 1, 64) AS passwd,
	SUBSTRING(email, 1, 255) AS email_address,
	SUBSTRING(website, 1, 255) AS website_title,
	SUBSTRING(website, 1, 255) AS website_url,
	SUBSTRING(location, 1, 255) AS location,
	SUBSTRING(icq_number, 1, 255) AS icq, signature,
	IF (bday_year = 0 AND bday_month != 0 AND bday_day != 0, CONCAT('0004-', bday_month, '-', bday_day), CONCAT_WS('-', IF(bday_year <= 4, 1, bday_year), IF(bday_month = 0, 1, bday_month), IF(bday_day = 0, 1, bday_day))) AS birthdate,
	SUBSTRING(aim_name, 1, 16) AS aim, SUBSTRING(yahoo, 1, 32) AS yim,
	SUBSTRING(msnname, 1, 255) AS msn, hide_email AS hide_email,
	SUBSTRING(IF(avatar = 'noavatar' OR INSTR(avatar, 'upload') > 0, '', avatar), 1, 255) AS avatar,
	IFNULL(email_pm, 0) AS pm_email_notify, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	'' AS time_format, '' AS usertitle, '' AS member_ip, '' AS secret_question,
	'' AS secret_answer, '' AS validation_code, '' AS additional_groups,
	'' AS smiley_set, '' AS password_salt, '' AS member_ip
FROM {$from_prefix}members
WHERE id != 0;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id AS id_cat, SUBSTRING(name, 1, 255) AS name, position AS cat_order
FROM {$from_prefix}categories
WHERE id >= 0;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	id AS id_board, topics AS num_topics, posts AS num_posts,
	SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, position AS board_order,
	category AS id_cat, parent_id AS id_parent, '-1,0' AS member_groups
FROM {$from_prefix}forums;
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
	t.tid AS id_topic, t.pinned AS is_sticky, t.forum_id AS id_board,
	t.starter_id AS id_member_started, t.last_poster_id AS id_member_updated,
	IFNULL(pl.pid, 0) AS id_poll, t.posts AS num_replies, t.views AS num_views,
	MIN(p.pid) AS id_first_msg, MAX(p.pid) AS id_last_msg,
	t.state = 'closed' AS locked
FROM {$from_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.topic_id = t.tid)
	LEFT JOIN {$from_prefix}polls AS pl ON (pl.tid = t.tid)
GROUP BY t.tid
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['body'] = addslashes(preg_replace(
	array(
		'~<!--QuoteBegin.*?-->.+?<!--QuoteEBegin-->~is',
		'~<!--QuoteEnd-->.+?<!--QuoteEEnd-->~is',
		'~<!--c1-->.+?<!--ec1-->~is',
		'~<!--c2-->.+?<!--ec2-->~is',
		'~<a href=\'mailto:(.+?)\'>.+?</a>~is',
		'~<a href=\'(.+?)\' target=\'_blank\'>(.+?)</a>~is',
		'~<span style=\'color:([^;]+?)\'>(.+?)</span>~is',
		'~<span style=\'font-size:([^;]+?).+?\'>(.+?)</span>~is',
		'~<span style=\'font-family:([^;]+?)\'>(.+?)</span>~is',
		'~<([/]?)ul>~is',
		'~<img src=\'~i',
		'~\' border=\'0\' alt=\'user posted image\'( /)?' . '>~i',
		'~<!--emo&(.+?)-->.+?<!--endemo-->~i',
	),
	array(
		'[quote]',
		'[/quote]',
		'[code]',
		'[/code]',
		'[email]$1[/email]',
		'[url=$1]$2[/url]',
		'[color=$1]$2[/color]',
		'[size=$1]$2[/size]',
		'[font=$1]$2[/font]',
		'[$1list]',
		'[img]',
		'[/img]',
		'$1',
	), ltrim($row['body'])));
$row['body'] = strtr(strtr($row['body'], '<>', '[]'), array('[br /]' => '<br />'));
---}
SELECT
	p.pid AS id_msg, p.topic_id AS id_topic, p.post_date AS poster_time,
	p.author_id AS id_member, SUBSTRING(t.title, 1, 255) AS subject,
	SUBSTRING(p.author_name, 1, 255) AS poster_name,
	SUBSTRING(p.ip_address, 1, 255) AS poster_ip,
	p.use_emo AS smileys_enabled, IFNULL(p.edit_time, 0) AS modified_time,
	SUBSTRING(p.edit_name, 1, 255) AS modified_name, t.forum_id AS id_board,
	SUBSTRING(REPLACE(p.post, '<br>', '<br />'), 1, 65534) AS body,
	SUBSTRING(mem.email, 1, 255) AS poster_email, 'xx' AS icon
FROM {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}topics AS t ON (t.tid = p.topic_id)
	LEFT JOIN {$from_prefix}members AS mem ON (mem.id = p.author_id);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pid AS id_poll, SUBSTRING(p.poll_question, 1, 255) AS question,
	p.starter_id AS id_member, SUBSTRING(mem.name, 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	LEFT JOIN {$from_prefix}members AS mem ON (mem.id = p.starter_id);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$choices = @unserialize(stripslashes($row['choices']));

if (is_array($choices))
	foreach ($choices as $choice)
	{
		$choice = addslashes_recursive($choice);
		$rows[] = "$row[id_poll], SUBSTRING('" . implode("', 1, 255), SUBSTRING('", $choice) . "', 1, 255)";
	}
---}
SELECT pid AS id_poll, choices
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting poll logs...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pl.pid AS id_poll, v.member_id AS id_member
FROM {$from_prefix}voters AS v
	LEFT JOIN {$from_prefix}polls AS pl ON (pl.tid = v.tid);
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = addslashes(preg_replace(
	array(
		'~<!--QuoteBegin.*?-->.+?<!--QuoteEBegin-->~is',
		'~<!--QuoteEnd-->.+?<!--QuoteEEnd-->~is',
		'~<!--c1-->.+?<!--ec1-->~is',
		'~<!--c2-->.+?<!--ec2-->~is',
		'~<a href=\'mailto:(.+?)\'>.+?</a>~is',
		'~<a href=\'(.+?)\' target=\'_blank\'>(.+?)</a>~is',
		'~<span style=\'color:([^;]+?)\'>(.+?)</span>~is',
		'~<span style=\'font-size:([^;]+?).+?\'>(.+?)</span>~is',
		'~<span style=\'font-family:([^;]+?)\'>(.+?)</span>~is',
		'~<([/]?)ul>~is',
		'~<img src=\'~i',
		'~\' border=\'0\' alt=\'user posted image\'( /)?' . '>~i',
		'~<!--emo&(.+?)-->.+?<!--endemo-->~i',
	),
	array(
		'[quote]',
		'[/quote]',
		'[code]',
		'[/code]',
		'[email]$1[/email]',
		'[url=$1]$2[/url]',
		'[color=$1]$2[/color]',
		'[size=$1]$2[/size]',
		'[font=$1]$2[/font]',
		'[$1list]',
		'[img]',
		'[/img]',
		'$1',
	), ltrim($row['body'])));
$row['body'] = substr(strtr(strtr($row['body'], '<>', '[]'), array('[br /]' => '<br />')), 0, 65534);
---}
SELECT
	pm.msg_id AS id_pm, pm.from_id AS id_member_from, pm.msg_date AS msgtime,
	SUBSTRING(uf.name, 1, 255) AS from_name,
	SUBSTRING(pm.title, 1, 255) AS subject,
	SUBSTRING(pm.message, 1, 65534) AS body
FROM {$from_prefix}messages AS pm
	LEFT JOIN {$from_prefix}members AS uf ON (uf.id = pm.from_id)
WHERE vid != 'sent';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	msg_id AS id_pm, recipient_id AS id_member, read_state = 1 AS is_read,
	'-1' AS labels
FROM {$from_prefix}messages
WHERE vid != 'sent';
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT member_id AS id_member, topic_id AS id_topic
FROM {$from_prefix}tracker;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT member_id AS id_member, forum_id AS id_board
FROM {$from_prefix}forum_tracker;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT member_id AS id_member, forum_id AS id_board
FROM {$from_prefix}moderators
WHERE member_id != -1;
---*

/******************************************************************************/
--- Converting permissions...
/******************************************************************************/

DELETE FROM {$to_prefix}permissions
WHERE id_group > 8;

DELETE FROM {$to_prefix}membergroups
WHERE id_group > 8;

---# Transforming permissions...
---{
/* These didn't make it to perms:
g_avoid_q, g_avoid_flood, g_other_topics, g_delete_own_topic, g_invite_friend,
g_icon, g_attach_max, g_avatar_upload, g_email_limit, g_append_edit, g_access_offline,
g_max_mass_pm, g_search_flood, g_edit_cutoff, g_promotion, g_hide_from_list,
*/

// These SMF perms have no equivalent but should be set.
$manual_perms = array(
	'profile_view_own',
	'profile_view_any',
	'karma_edit',
	'calendar_view',
	'mark_any_notify',
	'mark_notify',
	'view_attachments',
	'report_any',
);

while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT
			g_id AS id_group, g_title AS group_name, g_max_messages AS max_messages,
			g_view_board AS view_stats, g_mem_info AS view_mlist,
			g_view_board AS who_view, g_use_search AS search_posts, g_email_friend AS send_topic,
			g_edit_profile AS profile_identity_own, g_post_new_topics AS post_new,
			g_reply_own_topics AS post_reply_own, g_reply_other_topics AS post_reply_any,
			g_edit_posts AS modify_own, g_delete_own_posts AS delete_own,
			g_post_polls AS poll_post, g_post_polls AS poll_add_own, g_vote_polls AS poll_vote,
			g_use_pm AS pm_read, g_use_pm AS pm_send, g_is_supmod AS moderate_forum,
			g_is_supmod AS manage_membergroups, g_is_supmod AS manage_bans,
			g_access_cp AS manage_smileys, g_access_cp AS manage_attachments,
			g_can_remove AS delete_any, g_calendar_post AS calendar_post,
			g_calendar_post AS calendar_edit_any, g_post_closed AS lock_own,
			g_edit_topic AS modify_any, g_open_close_posts AS lock_any
		FROM {$from_prefix}groups
		WHERE g_id NOT IN (1, 4, 5)
		LIMIT $_REQUEST[start], 100");
	$perms = array();
	while ($row = convert_fetch_assoc($result))
	{
		$row = addslashes_recursive($row);
		// If this is NOT an existing membergroup add it (1-5 = existing.)
		if ($row['id_group'] > 5)
		{
			convert_insert('membergroups', array('id_group', 'group_name', 'max_messages', 'online_color', 'stars'),
				array($row[id_group] + 3, substr($row['group_name'], 0, 255), $row['max_messages'], '', '')
			);
			$groupID = $row['id_group'] + 3;
		}
		else
		{
			if ($row['id_group'] == 2)
				$groupID = -1;
			elseif ($row['id_group'] == 3)
				$groupID = 0;
			else
				$groupID = $row['id_group'];
		}

		unset($row['id_group'], $row['group_name'], $row['max_messages']);

		foreach ($row as $key => $value)
			if ($value == 1)
				$perms[] = array($groupID, $key);
		foreach ($manual_perms as $key)
			if ($value == 1 && $groupID != -1)
				$perms[] = array($groupID, $key);
	}

	if (!empty($perms))
		convert_insert('permissions', array('id_group', 'permission'), $perms, 'replace');

	$_REQUEST['start'] += 100;
	if (convert_num_rows($result) < 100)
		break;

	convert_free_result($result);
}

$_REQUEST['start'] = 0;
---}
---#

/******************************************************************************/
--- Converting board permissions...
/******************************************************************************/

---# Transforming board permissions...
---{
// This is SMF equivalent permissions.
$perm_equiv = array(
	'start_perms' => array(
		'post_new' => 1,
		'poll_post' => 1,
		'poll_add_own' => 1,
		'modify_own' => 1,
		'delete_own' => 1,
	),
	'read_perms' => array(
		'mark_notify' => 1,
		'mark_any_notify' => 1,
		'poll_view' => 1,
		'poll_vote' => 1,
		'report_any' => 1,
		'send_topic' => 1,
		'view_attachments' => 1,
	),
	'reply_perms' => array(
		'post_reply_own' => 1,
		'post_reply_any' => 1,
	),
	'upload_perms' => array(
		'post_attachments' => 1,
	),
);

global $groupMask;

// We need to load the member groups that we care about at all.
$result = convert_query("
	SELECT g_id AS id_group, g_perm_id AS perms
	FROM {$from_prefix}groups
	WHERE g_id != 5 AND g_id != 1 AND g_id != 4");
$groups = array();
$groupMask = array();
while ($row = convert_fetch_assoc($result))
{
	$groups[] = $row['id_group'];
	$groupMask[$row['id_group']] = $row['perms'];
}
convert_free_result($result);

if (!function_exists('magicMask'))
{
	function magicMask(&$group)
	{
		/*
		Right... don't laugh... here we explode the string to an array. Then we replace each group
		with the groups that use this mask. Then we remove duplicates and then we implode it again
		*/

		global $groupMask;

		if ($group != '*')
		{
			$groupArray = explode(',', $group);

			$newGroups = array();
			foreach ($groupMask as $id => $perms)
			{
				$perm = explode(',', $perms);
				foreach ($perm as $realPerm)
					if (in_array($realPerm, $groupArray) && !in_array($id, $newGroups))
						$newGroups[] = $id;
			}

			$group = implode(',', $newGroups);
		}
	}
}

if (!function_exists('smfGroup'))
{
	function smfGroup(&$group)
	{
		foreach ($group as $key => $value)
		{
			// Admin doesn't need to have his permissions done.
			if ($value == 4)
				unset($group[$key]);
			elseif ($value == 2)
				$group[$key] = -1;
			elseif ($value == 3)
				$group[$key] = 0;
			elseif ($value > 5)
				$group[$key] = $value + 3;
			else
				unset($group[$key]);
		}
	}
}

while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT id AS id_board, start_perms, reply_perms, read_perms, upload_perms
		FROM {$from_prefix}forums
		LIMIT $_REQUEST[start], 100");
	$perms = array();
	while ($row = convert_fetch_assoc($result))
	{
		$row = addslashes_recursive($row);

		// Oh yea... this is the "mask -> group" conversion stuffs...
		magicMask($row['start_perms']);
		magicMask($row['reply_perms']);
		magicMask($row['read_perms']);
		magicMask($row['upload_perms']);

		// This is used for updating the groups allowed on this board.
		$affectedGroups = array();

		// This is not at all fun... or the MOST efficient code but it should work.
		// first the patented "if everything is open do didley squat" routine.
		if ($row['start_perms'] == $row['reply_perms'] && $row['start_perms'] == $row['read_perms'] && $row['start_perms'] == $row['upload_perms'])
		{
			if ($row['read_perms'] != '*')
			{
				$affectedGroups = explode(',', $row['read_perms']);
				smfGroup($affectedGroups);

				// Update the board with allowed groups - appears twice in case board is hidden... makes sense to me :)
				convert_query("
					UPDATE {$to_prefix}boards
					SET member_groups = '" . implode(', ', $affectedGroups) . "'
					WHERE id_board = $row[id_board]");
			}
		}
		else
		{
			$tempGroup = array();
			/* The complicated stuff :)
			First we work out which groups can access the board (ie ones who can READ it) - and set the board
			permission for this. Then for every group we work out what permissions they have and add them to the array */
			if ($row['read_perms'] != '*')
			{
				$affectedGroups = explode(',', $row['read_perms']);
				smfGroup($affectedGroups);
				// Update the board with allowed groups - appears twice in case board is hidden... makes sense to me :)
				convert_query("
					UPDATE {$to_prefix}boards
					SET member_groups = '" . implode(', ', $affectedGroups) . "'
					WHERE id_board = $row[id_board]");
			}
			else
			{
				$affectedGroups[] = -1;
				$affectedGroups[] = 0;
			}
			// Now we know WHO can access this board, lets work out what they can do!
			// Everyone who is in affectedGroups can read so...
			foreach ($affectedGroups as $group)
				$tempGroup[$group] = $perm_equiv['read_perms'];
			if ($row['start_perms'] == '*')
				$affectedGroups2 = $affectedGroups;
			else
			{
				$affectedGroups2 = explode(',', $row['start_perms']);
				smfGroup($affectedGroups2);
			}
			foreach ($affectedGroups2 as $group)
				$tempGroup[$group] = isset($tempGroup[$group]) ? array_merge($perm_equiv['start_perms'], $tempGroup[$group]) : $perm_equiv['start_perms'];
			if ($row['reply_perms'] == '*')
				$affectedGroups2 = $affectedGroups;
			else
			{
				$affectedGroups2 = explode(',', $row['reply_perms']);
				smfGroup($affectedGroups2);
			}
			foreach ($affectedGroups2 as $group)
				$tempGroup[$group] = isset($tempGroup[$group]) ? array_merge($perm_equiv['reply_perms'], $tempGroup[$group]) : $perm_equiv['reply_perms'];
			if ($row['upload_perms'] == '*')
				$affectedGroups2 = $affectedGroups;
			else
			{
				$affectedGroups2 = explode(',', $row['upload_perms']);
				smfGroup($affectedGroups2);
			}
			foreach ($affectedGroups2 as $group)
				$tempGroup[$group] = isset($tempGroup[$group]) ? array_merge($perm_equiv['upload_perms'], $tempGroup[$group]) : $perm_equiv['upload_perms'];

			// Now we have $tempGroup filled with all the permissions for each group - better do something with it!
			foreach ($tempGroup as $groupno => $group)
				foreach ($group as $permission => $dummy)
					$perms[] = array($row['id_board'], $groupno, $permission);
		}
	}

	if (!empty($perms))
		convert_insert('board_permissions', array('id_board', 'id_group', 'permission'), $perms, 'replace');

	$_REQUEST['start'] += 100;
	if (convert_num_rows($result) < 100)
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
	':mellow:' => 'cool',
	':huh:' => 'huh',
	'^_^' => 'cheesy',
	':o' => 'shocked',
	';)' => 'wink',
	':P' => 'tongue',
	':D' => 'grin',
	':lol:' => 'cheesy',
	'B)' => 'cool',
	':rolleyes:' => 'rolleyes',
	'-_-' => 'smiley',
	'&lt;_&lt;' => 'smiley',
	':)' => 'smiley',
	':wub:' => 'kiss',
	':angry:' => 'angry',
	':(' => 'sad',
	':unsure:' => 'huh',
	':wacko:' => 'evil',
	':blink:' => 'smiley',
	':ph34r:' => 'afro',
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
	$rows[] = array($code, $name . '.gif', $name, $count);
}

if (!empty($rows))
	convert_insert('smileys', array('code', 'filename', 'description', 'smiley_order'), $rows, 'replace');
---}

/******************************************************************************/
--- Converting settings...
/******************************************************************************/

---{
convert_insert('settings', array('variable', 'value'),
	array(
		array('hotTopicPosts', $INFO['hot_topic']),
		array('defaultMaxMessages', $INFO['display_max_posts']),
		array('defaultMaxTopics', $INFO['display_max_topics']),
		array('spamWaitTime', $INFO['flood_control']),
		array('onlineEnable', $INFO['allow_online_list']),
	), 'replace');

updateSettingsFile(array(
	'mbname' => '\'' . addcslashes($INFO['board_name'], '\'\\') . '\'',
	'mmessage' => '\'' . addcslashes($INFO['offline_msg'], '\'\\') . '\''
));
---}

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

if (empty($INFO['upload_dir']) || !file_exists($INFO['upload_dir']))
	$INFO['upload_dir'] = $_POST['path_from'] . '/uploads';

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return

if (copy($INFO['upload_dir'] . '/' . $row['old_encrypt'], $attachmentUploadDir . '/' . $physical_filename))
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
	pid AS id_msg, attach_id AS old_encrypt, attach_hits AS downloads,
	attach_file AS filename
FROM {$from_prefix}posts
WHERE IFNULL(attach_id, '') != '';
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

if (empty($INFO['upload_dir']) || !file_exists($INFO['upload_dir']))
	$INFO['upload_dir'] = $_POST['path_from'] . '/uploads';

$oldFileName = substr($row['avatar'], 7);
$file_hash = getAttachmentFilename($oldFileName, $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($INFO['upload_dir'] . '/' . $oldFileName, $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => $filesize,
		'filename' => $oldFileName,
		'file_hash' => $file_hash,
		'id_member' => $row['id_member'],
	);

	$id_attach++;
}
---}
SELECT avatar, id AS id_member
FROM {$from_prefix}members
WHERE INSTR(avatar, 'upload') != 0;
---*