/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "PHP-Nuke 7.9"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php", "/includes/constants.php"
---~ defines: IN_PHPBB
---~ from_prefix: "`$dbname`.{$prefix}_"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
/* Developers Note:                                                           */
/*   phpNuke is EXACTLY the same as phpBB but with constants for table names. */
/*   The converter doesn't support constants, so this is hard coded.          */
/******************************************************************************/

/******************************************************************************/
--- Converting ranks...
/******************************************************************************/

DELETE FROM {$to_prefix}membergroups
WHERE group_name LIKE 'phpBB %';

---* {$to_prefix}membergroups
---{
if (!isset($_SESSION['convert_num_stars']))
{
	$_SESSION['convert_num_stars'] = 1;

	// Got some ranks to move, so go do it... first remove the post based membergroups from the table.
	// !!! We must keep group id 4 as a post group.  MUST!!
	convert_query("
		DELETE FROM {$to_prefix}membergroups
		WHERE min_posts != -1
			AND id_group > 4");
}

if ($row['min_posts'] > -1)
{
	$row['stars'] = sprintf("%d#star.gif", $_SESSION['convert_num_stars']);
	if ($_SESSION['convert_num_stars'] < 5)
		$_SESSION['convert_num_stars']++;
}
---}
SELECT
	SUBSTRING(CONCAT('phpBB ', rank_title), 1, 255) AS group_name,
	rank_image AS stars, IF(rank_special = 0, rank_min, -1) AS min_posts,
	'' AS online_color
FROM {$from_prefix}bbranks
ORDER BY rank_min;
---*

/******************************************************************************/
--- Converting groups...
/******************************************************************************/

---* {$to_prefix}membergroups
SELECT
	SUBSTRING(CONCAT('phpBB ', group_name), 1, 255) AS group_name,
	-1 AS min_posts, '' AS stars, '' AS online_color
FROM {$from_prefix}bbgroups
WHERE group_single_user = 0;
---*

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
// Got the board timezone?
if (!isset($board_timezone))
{
	$request2 = convert_query("
		SELECT config_value
		FROM {$from_prefix}bbconfig
		WHERE config_name = 'board_timezone'
		LIMIT 1");
	list ($board_timezone) = convert_fetch_row($request2);
	convert_free_result($request2);

	// Find out where uploaded avatars go (attachments dir.)
	$request2 = convert_query("
		SELECT value
		FROM {$to_prefix}settings
		WHERE variable = 'attachmentUploadDir'
		LIMIT 1");
	list ($smf_attachments_dir) = convert_fetch_row($request2);
	convert_free_result($request2);

	$request2 = convert_query("
		SELECT config_value
		FROM {$from_prefix}bbconfig
		WHERE config_name = 'avatar_path'
		LIMIT 1");
	$phpbb_avatar_upload_path = $_POST['path_from'] . '/' . convert_result($request2, 0, 'config_value');
	convert_free_result($request2);
}

// time_offset = phpBB user TZ - phpBB board TZ.
$row['time_offset'] = $row['time_offset'] - $board_timezone;

if ($row['user_avatar_type'] == 0)
	$row['avatar'] = '';
// If the avatar type is uploaded (type = 1) copy avatar as an attachment with the correct name.
elseif ($row['user_avatar_type'] == 1 && strlen($row['avatar']) > 0)
{
	$smf_avatar_filename = 'avatar_' . $row['id_member'] . strrchr($row['avatar'], '.');
	copy($phpbb_avatar_upload_path . '/' . $row['avatar'], $smf_attachments_dir . '/' . $smf_avatar_filename);

	convert_insert('attachments', array('id_msg', 'id_member', 'filename'),
		array(0, $row['id_member'], $smf_avatar_filename)
	);
	$row['avatar'] = '';
}
elseif ($row['user_avatar_type'] == 3)
	$row['avatar'] = substr('gallery/' . $row['avatar'], 0, 255);
unset($row['user_avatar_type']);

$row['signature'] = preg_replace('~\[size=([789]|[012]\d)\]~i', '[size=$1px]', $row['signature']);
if ($row['signature_uid'] != '')
	$row['signature'] = preg_replace('~(:u:|:1:|:)' . preg_quote($row['signature_uid'], '~') . '~i', '', $row['signature']);
$row['signature'] = substr($row['signature'], 0, 65534);
unset($row['signature_uid']);

$row['date_registered'] = @strtotime($row['date_registered']);
---}
SELECT
	u.user_id AS id_member, SUBSTRING(u.username, 1, 80) AS member_name,
	SUBSTRING(u.username, 1, 255) AS real_name,
	SUBSTRING(u.user_password, 1, 64) AS passwd, u.user_lastvisit AS last_login,
	u.user_regdate AS date_registered,
	SUBSTRING(u.user_from, 1, 255) AS location,
	u.user_posts AS posts,
	IF(u.user_level = 3, 1, (IF(ISNULL(mg.id_group), 0, mg.id_group))) AS id_group,
	u.user_new_privmsg AS instant_messages,
	SUBSTRING(u.user_email, 1, 255) AS email_address,
	u.user_unread_privmsg AS unread_messages,
	SUBSTRING(u.user_msnm, 1, 255) AS msn,
	SUBSTRING(u.user_aim, 1, 16) AS aim,
	SUBSTRING(u.user_icq, 1, 255) AS icq,
	SUBSTRING(u.user_yim, 1, 32) AS yim,
	SUBSTRING(u.user_website, 1, 255) AS website_title,
	SUBSTRING(u.user_website, 1, 255) AS website_url,
	u.user_allow_viewonline AS show_online, u.user_timezone AS time_offset,
	IF(u.user_viewemail = 1, 0, 1) AS hide_email, u.user_avatar AS avatar,
	REPLACE(u.user_sig, '\n', '<br />') AS signature,
	u.user_sig_bbcode_uid AS signature_uid, u.user_avatar_type,
	u.user_notify_pm AS pm_email_notify, u.user_active AS is_activated,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS usertitle, '' AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt,
	'' AS member_ip2
FROM {$from_prefix}users AS u
	LEFT JOIN {$from_prefix}bbranks AS r ON (r.rank_id = u.user_rank AND r.rank_special = 1)
	LEFT JOIN {$to_prefix}membergroups AS mg ON (mg.group_name = CONCAT('phpBB ', r.rank_title))
WHERE u.user_id != 1
GROUP BY u.user_id;
---*

/******************************************************************************/
--- Converting additional member groups...
/******************************************************************************/

---# Checking memberships...
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT mg.id_group, mem.id_member
		FROM {$from_prefix}bbgroups AS g
			LEFT JOIN {$from_prefix}bbuser_group AS ug ON (ug.group_id = g.group_id)
			LEFT JOIN {$to_prefix}membergroups AS mg ON (mg.group_name = CONCAT('phpBB ', g.group_name))
			LEFT JOIN {$to_prefix}members AS mem ON (mem.id_member = ug.user_id)
		WHERE g.group_single_user = 0
		ORDER BY id_member
		LIMIT $_REQUEST[start], 250");
	$additional_groups = '';
	$last_member = 0;
	while ($row = convert_fetch_assoc($result))
	{
		if (empty($last_member))
			$last_member = $row['id_member'];

		if ($last_member != $row['id_member'])
		{
			$additional_groups = addslashes($additional_groups);

			convert_query("
				UPDATE {$to_prefix}members
				SET additional_groups = '$additional_groups'
				WHERE id_member = $last_member
				LIMIT 1");
			$last_member = $row['id_member'];
			$additional_groups = $row['id_group'];
		}
		else
		{
			if ($additional_groups == '')
				$additional_groups = $row['id_group'];
			else
				$additional_groups = $additional_groups . ',' . $row['id_group'];
		}
	}

	$_REQUEST['start'] += 250;
	if (convert_num_rows($result) < 250)
		break;

	convert_free_result($result);
}
$_REQUEST['start'] = 0;

if ($last_member != 0)
{
	$additional_groups = addslashes($additional_groups);

	convert_query("
		UPDATE {$to_prefix}members
		SET additional_groups = '$additional_groups'
		WHERE id_member = $last_member
		LIMIT 1");
}
---}
---#

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	cat_id AS id_cat, SUBSTRING(cat_title, 1, 255) AS name,
	cat_order AS cat_order
FROM {$from_prefix}bbcategories;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	forum_id AS id_board, forum_order AS board_order, forum_posts AS num_posts,
	forum_last_post_id AS id_last_msg, SUBSTRING(forum_name, 1, 255) AS name,
	cat_id AS id_cat, SUBSTRING(forum_desc, 1, 65534) AS description,
	forum_topics AS num_topics,
	CASE auth_read
		WHEN 0 THEN '-1,0,2'
		WHEN 1 THEN '0,2'
		WHEN 3 THEN '2'
		ELSE ''
	END AS member_groups
FROM {$from_prefix}bbforums;
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
	t.topic_id AS id_topic, (t.topic_type = 1 OR t.topic_type = 2) AS is_sticky,
	t.topic_first_post_id AS id_first_msg, t.topic_last_post_id AS id_last_msg,
	t.topic_poster AS id_member_started, p.poster_id AS id_member_updated,
	t.forum_id AS id_board, IF(v.vote_id <> 0, v.vote_id, 0) AS id_poll, t.topic_status = 1 AS locked,
	t.topic_replies AS num_replies, t.topic_views AS num_views
FROM {$from_prefix}bbtopics AS t
	LEFT JOIN {$from_prefix}bbposts AS p ON (p.post_id = t.topic_last_post_id)
	LEFT JOIN {$from_prefix}bbvote_desc AS v ON (v.topic_id = t.topic_id)
GROUP BY t.topic_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace('~\[size=([789]|[012]\d)\]~is', '[size=$1px]', $row['body']);
---}
SELECT
	p.post_id AS id_msg, p.topic_id AS id_topic, p.post_time AS poster_time,
	p.poster_id AS id_member,
	SUBSTRING(IFNULL(u.user_email, ''), 1, 255) AS poster_email,
	SUBSTRING(IF(IFNULL(pt.post_subject, '') = '', t.topic_title, pt.post_subject), 1, 255) AS subject,
	SUBSTRING(IF(IFNULL(p.post_username, '') = '', u.username, p.post_username), 1, 255) AS poster_name,
	p.enable_smilies AS smileys_enabled, IF(p.post_edit_time <> 0, p.post_edit_time, 0) AS modified_time,
	CONCAT_WS('.', CONV(SUBSTRING(p.poster_ip, 1, 2), 16, 10), CONV(SUBSTRING(p.poster_ip, 3, 2), 16, 10), CONV(SUBSTRING(p.poster_ip, 5, 2), 16, 10), CONV(SUBSTRING(p.poster_ip, 7, 2), 16, 10)) AS poster_ip,
	SUBSTRING(REPLACE(REPLACE(IF(pt.bbcode_uid = '', pt.post_text, REPLACE(REPLACE(REPLACE(pt.post_text, CONCAT(':u:', pt.bbcode_uid), ''), CONCAT(':1:', pt.bbcode_uid), ''), CONCAT(':', pt.bbcode_uid), '')), '\n', '<br />'), '"', '"'), 1, 65534) AS body,
	p.forum_id AS id_board, '' AS modified_name, 'xx' AS icon
FROM {$from_prefix}bbposts AS p
	LEFT JOIN {$from_prefix}bbposts_text AS pt ON (pt.post_id = p.post_id)
	LEFT JOIN {$from_prefix}bbtopics AS t ON (t.topic_id = p.topic_id)
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = p.poster_id);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	vote_id AS id_poll, SUBSTRING(vote_text, 1, 255) AS question,
	t.topic_poster AS id_member, vote_start + vote_length AS expire_time,
	SUBSTRING(IFNULL(u.username, ''), 1, 255) AS poster_name
FROM {$from_prefix}bbvote_desc AS vd
	INNER JOIN {$from_prefix}bbtopics AS t ON (vd.topic_id = t.topic_id)
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = t.topic_poster);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
SELECT
	vote_id AS id_poll, vote_option_id AS id_choice,
	SUBSTRING(vote_option_text, 1, 255) AS label, vote_result AS votes
FROM {$from_prefix}bbvote_results
GROUP BY vote_id, vote_option_id;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT vote_id AS id_poll, vote_user_id AS id_member
FROM {$from_prefix}bbvote_voters
WHERE vote_user_id > 0
GROUP BY vote_id, vote_user_id;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.privmsgs_id AS id_pm, pm.privmsgs_from_userid AS id_member_from,
	pm.privmsgs_type IN (0, 1, 3) AS deleted_by_sender,
	pm.privmsgs_date AS msgtime,
	SUBSTRING(uf.username, 1, 255) AS from_name,
	SUBSTRING(pm.privmsgs_subject, 1, 255) AS subject,
	SUBSTRING(REPLACE(IF(pmt.privmsgs_bbcode_uid = '', pmt.privmsgs_text, REPLACE(REPLACE(pmt.privmsgs_text, CONCAT(':1:', pmt.privmsgs_bbcode_uid), ''), CONCAT(':', pmt.privmsgs_bbcode_uid), '')), '\n', '<br />'), 1, 65534) AS body
FROM {$from_prefix}bbprivmsgs AS pm
	LEFT JOIN {$from_prefix}bbprivmsgs_text AS pmt ON (pmt.privmsgs_text_id = pm.privmsgs_id)
	LEFT JOIN {$from_prefix}users AS uf ON (uf.user_id = pm.privmsgs_from_userid);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm.privmsgs_id AS id_pm, pm.privmsgs_to_userid AS id_member,
	pm.privmsgs_type = 5 AS is_read, pm.privmsgs_type IN (2, 4) AS deleted,
	'-1' AS labels
FROM {$from_prefix}bbprivmsgs AS pm
	LEFT JOIN {$from_prefix}bbprivmsgs_text AS pmt ON (pmt.privmsgs_text_id = pm.privmsgs_id)
	LEFT JOIN {$from_prefix}users AS uf ON (uf.user_id = pm.privmsgs_from_userid);
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT user_id AS id_member, topic_id AS id_topic
FROM {$from_prefix}bbtopics_watch;
---*

/******************************************************************************/
--- Converting board access...
/******************************************************************************/

---{
convert_insert('settings', array('variable', 'value'), array('permission_enable_by_board', '1'), 'replace');
---}

UPDATE {$to_prefix}boards
SET id_profile = id_board + 4;

---# Do all board permissions...
---{
// Select all boards/forums.
$request = convert_query("
	SELECT
		CASE auth_post WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_post,
		CASE auth_reply WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_reply,
		CASE auth_edit WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_edit,
		CASE auth_sticky WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_sticky,
		CASE auth_announce WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_announce,
		CASE auth_delete WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_delete,
		CASE auth_vote WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_vote,
		CASE auth_pollcreate WHEN 0 THEN '-1,0,2,3' WHEN 1 THEN '0,2,3' WHEN 3 THEN '2,3' ELSE '' END AS auth_pollcreate,
		forum_id AS id_board
	FROM {$from_prefix}bbforums");
while ($row = convert_fetch_assoc($request))
{
	// Accumulate permissions in here - the keys are id_groups.
	$this_board = array(
		'-1' => array(),
		'0' => array(),
		'2' => array(),
		'3' => array(),
	);

	$row['auth_post'] = $row['auth_post'] == '' ? array() : explode(',', $row['auth_post']);
	$row['auth_reply'] = $row['auth_reply'] == '' ? array() : explode(',', $row['auth_reply']);
	$row['auth_edit'] = $row['auth_edit'] == '' ? array() : explode(',', $row['auth_edit']);
	$row['auth_sticky'] = $row['auth_sticky'] == '' ? array() : explode(',', $row['auth_sticky']);
	$row['auth_announce'] = $row['auth_announce'] == '' ? array() : explode(',', $row['auth_announce']);
	$row['auth_delete'] = $row['auth_delete'] == '' ? array() : explode(',', $row['auth_delete']);
	$row['auth_vote'] = $row['auth_vote'] == '' ? array() : explode(',', $row['auth_vote']);
	$row['auth_pollcreate'] = $row['auth_pollcreate'] == '' ? array() : explode(',', $row['auth_pollcreate']);

	foreach ($row['auth_post'] as $g)
		$this_board[$g] = array('post_new', 'mark_notify', 'mark_any_notify');

	foreach ($row['auth_reply'] as $g)
		$this_board[$g][] = 'post_reply_any';

	foreach ($row['auth_edit'] as $g)
		$this_board[$g][] = 'modify_own';

	foreach ($row['auth_sticky'] as $g)
		$this_board[$g][] = 'make_sticky';

	foreach ($row['auth_announce'] as $g)
		$this_board[$g][] = 'announce_topic';

	foreach ($row['auth_delete'] as $g)
	{
		$this_board[$g][] = 'remove_own';
		$this_board[$g][] = 'delete_own';
	}

	foreach ($row['auth_vote'] as $g)
	{
		$this_board[$g][] = 'poll_vote';
		$this_board[$g][] = 'poll_view';
	}

	foreach ($row['auth_pollcreate'] as $g)
	{
		$this_board[$g][] = 'poll_post';
		$this_board[$g][] = 'poll_add_own';
	}

	$setString = '';
	foreach ($this_board as $id_group => $permissions)
	{
		foreach ($permissions as $perm)
			$setString[] = array($id_group, $row['id_board'] + 4, $perm);
	}

	if ($setString != '')
		convert_insert('board_permissions', array('id_group', 'id_profile', 'permission'), $setString, 'insert ignore');
}
convert_free_result($request);
---}
---#

/******************************************************************************/
--- Converting group access...
/******************************************************************************/

---# Now do the group ones...
---{
// Select all auth_access records.
$request = convert_query("
	SELECT
		aa.forum_id AS id_board, mg.id_group AS id_group, aa.auth_post,
		aa.auth_reply, aa.auth_edit, aa.auth_delete, aa.auth_sticky,
		aa.auth_announce, aa.auth_vote, aa.auth_pollcreate, aa.auth_mod
	FROM {$from_prefix}bbauth_access AS aa
		INNER JOIN {$from_prefix}bbgroups AS g
		INNER JOIN {$to_prefix}membergroups AS mg
	WHERE g.group_id = aa.group_id
		AND mg.group_name = CONCAT('phpBB ', g.group_name)");
while ($row = convert_fetch_assoc($request))
{
	$this_group = array();

	if ($row['auth_post'] || $row['auth_mod'])
	{
		$this_group[] = 'post_new';
		$this_group[] = 'mark_notify';
		$this_group[] = 'mark_any_notify';
	}
	if ($row['auth_reply'] || $row['auth_mod'])
		$this_group[] = 'post_reply_any';
	if ($row['auth_edit'] || $row['auth_mod'])
		$this_group[] = 'modify_own';
	if ($row['auth_delete'] || $row['auth_mod'])
	{
		$this_group[] = 'remove_own';
		$this_group[] = 'delete_own';
	}
	if ($row['auth_sticky'] || $row['auth_mod'])
		$this_group[] = 'make_sticky';
	if ($row['auth_announce'] || $row['auth_mod'])
		$this_group[] = 'announce_topic';
	if ($row['auth_pollcreate'] || $row['auth_mod'])
	{
		$this_group[] = 'poll_post';
		$this_group[] = 'poll_add_own';
	}
	if ($row['auth_vote'] || $row['auth_mod'])
	{
		$this_group[] = 'poll_vote';
		$this_group[] = 'poll_view';
	}
	if ($row['auth_mod'])
	{
		$this_group[] = 'moderate_board';
		$this_group[] = 'remove_any';
		$this_group[] = 'lock_any';
		$this_group[] = 'lock_own';
		$this_group[] = 'merge_any';
		$this_group[] = 'modify_any';
		$this_group[] = 'modify_own';
		$this_group[] = 'move_any';
		$this_group[] = 'poll_add_any';
		$this_group[] = 'poll_edit_any';
		$this_group[] = 'poll_remove_any';
		$this_group[] = 'post_reply_own';
		$this_group[] = 'delete_any';
		$this_group[] = 'report_any';
		$this_group[] = 'send_topic';
		$this_group[] = 'split_any';
	}

	$setString = '';
	foreach ($this_group as $perm)
	{
		$setString[] = array($row['id_group'], $row['id_board'] + 4, $perm);
	}

	if (!empty($setString))
		convert_insert('board_permissions', array('id_group', 'id_profile', 'permission'), $setString, 'insert ignore');

	// Give group access to board.
	$result = convert_query("
		SELECT member_groups
		FROM {$to_prefix}boards
		WHERE id_board = $row[id_board]
		LIMIT 1");
	list ($member_groups) = convert_fetch_row($result);
	convert_free_result($result);

	convert_query("
		UPDATE {$to_prefix}boards
		SET member_groups = '" . implode(',', array_unique(explode(',', $member_groups . ',' . $row['id_group']))) . "'
		WHERE id_board = $row[id_board]
		LIMIT 1");
}
convert_free_result($request);
---}
---#

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT u.user_id AS id_member, aa.forum_id AS id_board
FROM {$from_prefix}users AS u
	INNER JOIN {$from_prefix}bbuser_group AS ug ON (ug.user_id = u.user_id)
	INNER JOIN {$from_prefix}bbauth_access AS aa ON (ug.group_id = aa.group_id)
	INNER JOIN {$from_prefix}bbgroups AS g ON (g.group_id = aa.group_id)
WHERE aa.auth_mod = 1
	AND g.group_single_user = 1
GROUP BY aa.forum_id, u.user_id;
---*

/******************************************************************************/
--- Converting avatar gallery images...
/******************************************************************************/

---# Copying over avatar directory...
---{

if (!function_exists('copy_dir'))
{
	function copy_dir($source, $dest)
	{
		if (!is_dir($source) || !($dir = opendir($source)))
			return;

		while ($file = readdir($dir))
		{
			if ($file == '.' || $file == '..')
				continue;

			// If we have a directory create it on the destination and copy contents into it!
			if (is_dir($source . '/' . $file))
			{
				@mkdir($dest . '/' . $file, 0777);
				copy_dir($source . '/' . $file, $dest . '/' . $file);
			}
			else
				copy($source . '/' . $file, $dest . '/' . $file);
		}
		closedir($dir);
	}
}
// Find the path for phpBB gallery avatars.
$request = convert_query("
	SELECT config_value
	FROM {$from_prefix}bbconfig
	WHERE config_name = 'avatar_gallery_path'
	LIMIT 1");
list ($phpbb_avatar_gallery_path) = convert_fetch_row($request);
convert_free_result($request);

if (empty($phpbb_avatar_gallery_path) || $phpbb_avatar_gallery_path = '/' || $phpbb_avatar_gallery_path = '')
	return;

// Find the path for SMF avatars.
$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'avatar_directory'
	LIMIT 1");
list ($smf_avatar_directory) = convert_fetch_row($request);
convert_free_result($request);

$phpbb_avatar_gallery_path = $_POST['path_from'] . '/' . $phpbb_avatar_gallery_path;

// Copy gallery avatars...
@mkdir($smf_avatar_directory . '/gallery', 0777);
copy_dir($phpbb_avatar_gallery_path, $smf_avatar_directory . '/gallery');
---}
---#

/******************************************************************************/
--- Converting censored words...
/******************************************************************************/

DELETE FROM {$to_prefix}settings
WHERE variable IN ('censor_vulgar', 'censor_proper');

---# Moving censored words...
---{
$result = convert_query("
	SELECT word, replacement
	FROM {$from_prefix}bbwords");
$censor_vulgar = array();
$censor_proper = array();
while ($row = convert_fetch_assoc($result))
{
	$censor_vulgar[] = $row['word'];
	$censor_proper[] = $row['replacement'];
}
convert_free_result($result);

$censored_vulgar = addslashes(implode("\n", $censor_vulgar));
$censored_proper = addslashes(implode("\n", $censor_proper));

convert_insert('settings', array('variable', 'value'),
	array(
		array('censor_vulgar', $censored_vulgar),
		array('censor_proper', $censored_proper),
	), 'replace');

---}
---#

/******************************************************************************/
--- Converting reserved names...
/******************************************************************************/

DELETE FROM {$to_prefix}settings
WHERE variable = 'reserveNames';

---# Moving reserved names...
---{
$result = convert_query("
	SELECT disallow_username
	FROM {$from_prefix}bbdisallow");
$disallow = array();
while ($row = convert_fetch_assoc($result))
	$disallow[] = str_replace('*', '', $row['disallow_username']);
convert_free_result($result);

$disallowed = addslashes(implode("\n", $disallow));

convert_insert('settings', array('variable', 'value'), array('reserveNames', $disallowed), 'replace');
---}
---#

/******************************************************************************/
--- Converting banned users...
/******************************************************************************/

TRUNCATE {$to_prefix}ban_items;
TRUNCATE {$to_prefix}ban_groups;

---# Moving banned entries...
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT ban_id, ban_userid, ban_ip, ban_email
		FROM {$from_prefix}bbbanlist
		LIMIT $_REQUEST[start], 250");
	$ban_time = time();
	while ($row = convert_fetch_assoc($result))
	{
		convert_insert('ban_groups', array('name', 'ban_time', 'expire_time', 'reason', 'notes', 'cannot_access'),
			array("migrated_ban_" . $row['ban_id'], $ban_time, NULL, '', 'Migrated from php-nuke', 1)
		);
		$id_ban_group = convert_insert_id();

		if (empty($id_ban_group))
			continue;

		if ($row['ban_email'])
		{
			convert_insert('ban_items', array('id_ban_group', 'email_address', 'hostname'),
				array($id_ban_group, $row['ban_email'], '')
			);
			continue;
		}
		if ($row['ban_ip'])
		{
			list ($octet1, $octet2, $octet3, $octet4) = explode(':', chunk_split($row['ban_ip'], 2, ':'));

			$ip_high1 = hexdec($octet1);
			$ip_low1 = $ip_high1 == 255 ? 0 : $ip_high1;

			$ip_high2 = hexdec($octet2);
			$ip_low2 = $ip_high2 == 255 ? 0 : $ip_high2;

			$ip_high3 = hexdec($octet3);
			$ip_low3 = $ip_high3 == 255 ? 0 : $ip_high3;

			$ip_high4 = hexdec($octet4);
			$ip_low4 = $ip_high4 == 255 ? 0 : $ip_high4;

			convert_insert('ban_items', array('id_ban_group', 'ip_low1', 'ip_high1', 'ip_low2', 'ip_high2', 'ip_low3', 'ip_high3', 'ip_low4', 'ip_high4', 'email_address', 'hostname'),
				array($id_ban_group, $ip_low1, $ip_high1, $ip_low2, $ip_high2, $ip_low3, $ip_high3, $ip_low4, $ip_high4, '', '')
			);
			continue;
		}
		if ($row['ban_userid'])
			convert_insert('ban_items', array('id_ban_group', 'id_member', 'email_address', 'hostname'),
				array($id_ban_group, $row['ban_userid'], '', '')
			);
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
--- Converting settings...
/******************************************************************************/

---# Moving settings...
---{
$result = convert_query("
	SELECT config_name, config_value AS value, sitename
	FROM {$from_prefix}bbconfig
	INNER JOIN {$from_prefix}config");
$setString = array();
while ($row = convert_fetch_assoc($result))
{
	if ($row['config_name'] == 'sitename')
		$phpbb_forum_name = !empty($row['value']) ? $row['value'] : $row['sitename'];
	elseif ($row['config_name'] == 'board_email')
		$phpbb_admin_email = $row['value'];
	// No translation required... ;).
	elseif (in_array($row['config_name'], array('smtp_host', 'smtp_username', 'smtp_password')))
		$setString[] = array($row[config_name], addslashes($row['value']));
	elseif ($row['config_name'] == 'require_activation')
		$setString[] = array('registration_method', addslashes($row['value']));
	elseif ($row['config_name'] == 'flood_interval')
		$setString[] = array('spamWaitTime', addslashes($row['value']));
	elseif ($row['config_name'] == 'avatar_max_width')
	{
		$setString[] = array('avatar_max_width_external', addslashes($row['value']));
		$setString[] = array('avatar_max_width_upload', addslashes($row['value']));
	}
	elseif ($row['config_name'] == 'avatar_max_height')
	{
		$setString[] = array('avatar_max_height_external', addslashes($row['value']));
		$setString[] = array('avatar_max_height_upload', addslashes($row['value']));
	}
	elseif ($row['config_name'] == 'max_sig_chars')
		$setString[] = array('max_signatureLength', addslashes($row['value']));
	elseif ($row['config_name'] == 'session_length')
		$setString[] = array('databaseSession_lifteim', addslashes($row['value']));
	elseif ($row['config_name'] == 'gzip_compress')
		$setString[] = array('enableCompressedOutput', addslashes($row['value']));
	elseif ($row['config_name'] == 'record_users_online')
		$setString[] = array('mostOnline', addslashes($row['value']));
	elseif ($row['config_name'] == 'record_online_date')
		$setString[] = array('mostDate', addslashes($row['value']));
	elseif ($row['config_name'] == 'smtp_email')
		$setString[] = array('mail_type', $row['value'] == 1 ? '1' : '0');
}
convert_free_result($result);

convert_insert('settings', array('variable', 'value'), $setString, 'replace');

updateSettings(array(
	'mbname' => '\'' . addcslashes($phpbb_forum_name, '\'\\') . '\'',
	'webmaster_email' => '\'' . addcslashes($phpbb_admin_email, '\'\\') . '\''
));
---}
---#

/******************************************************************************/
--- Converting attachment mod (if installed)...
/******************************************************************************/

---# Checking for attachments table, and copying data.
---{
/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
$result = convert_query("
	SHOW TABLES FROM " . preg_replace('~`\..*$~', '', $from_prefix) . "`
	LIKE '" . preg_replace('~^`.+?`\.~', '', $from_prefix) . "bbattachments'");
list ($tableExists) = convert_fetch_row($result);
convert_free_result($result);

// Doesn't exist?
if (!$tableExists)
	return;

if (!isset($id_attach))
{
	$result = convert_query("
		SELECT MAX(id_attach) + 1
		FROM {$to_prefix}attachments");
	list ($id_attach) = convert_fetch_row($result);
	convert_free_result($result);

	$result = convert_query("
		SELECT value
		FROM {$to_prefix}settings
		WHERE variable = 'attachmentUploadDir'
		LIMIT 1");
	list ($attachmentUploadDir) = convert_fetch_row($result);
	convert_free_result($result);

	// Get the original path... we'll copy it over for them!
	$result = convert_query("
		SELECT config_value
		FROM {$from_prefix}bbattachments_config
		WHERE config_name = 'upload_dir'
		LIMIT 1");
	list ($oldAttachmentDir) = convert_fetch_row($result);
	convert_free_result($result);

	if (substr($oldAttachmentDir, 0, 2) == '..')
		$oldAttachmentDir = $_POST['path_from'] . '/' . $oldAttachmentDir;
	elseif (substr($oldAttachmentDir, 0, 1) != '/')
		$oldAttachmentDir = $_POST['path_from'] . '/' . $oldAttachmentDir;
	if (empty($oldAttachmentDir) || !file_exists($oldAttachmentDir))
		$oldAttachmentDir = $_POST['path_from'] . '/files';
}

if (empty($id_attach))
	$id_attach = 1;

while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT
			a.post_id AS id_msg, ad.real_filename AS filename, ad.physical_filename AS encrypted,
			ad.download_count AS downloads, ad.filesize AS size
		FROM {$from_prefix}bbattachments AS a
			INNER JOIN {$from_prefix}bbattachments_desc AS ad ON (ad.attach_id = a.attach_id)
		WHERE a.post_id != 0
		LIMIT $_REQUEST[start], 100");
	$attachments = array();
	while ($row = convert_fetch_assoc($result))
	{
		if (!file_exists($oldAttachmentDir . '/' . $row['encrypted']))
			$row['encrypted'] = strtr($row['encrypted'], '& ', '__');

		// Get the true filesize in case the old db lied!
		$fileSize = filesize($oldAttachmentDir . '/' . $row['encrypted']);
		if (!is_integer($fileSize))
			continue;

		// Frankly I don't care whether they want encrypted filenames - they're having it - too dangerous.
		$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
		$physical_filename = $id_attach . '_' . $file_hash;

		if (strlen($physical_filename) > 255)
			return;

		if (copy($oldAttachmentDir . '/' . $row['encrypted'], $attachmentUploadDir . '/' . $physical_filename))
		{
			$rows[] = array(
				'id_attach' => $id_attach,
				'size' => $fileSize,
				'filename' => $attachedfile['filename'],
				'file_hash' => $file_hash,
				'id_msg' => $row['post_id'],
				'downloads' => 0
			);

			$id_attach++;
		}
	}

	if (!empty($attachments))
		convert_insert('attachments', array('id_attach' => 'int', 'size' => 'int', 'filename' => 'string', 'file_hash' => 'string', 'id_msg' => 'int', 'downloads' => 'int'), $attachments);

	$_REQUEST['start'] += 100;
	if (convert_num_rows($result) < 100)
		break;

	convert_free_result($result);
}

$_REQUEST['start'] = 0;
---}
---#