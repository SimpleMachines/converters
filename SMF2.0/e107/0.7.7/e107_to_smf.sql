/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "e107 ver.0.7.7"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/e107_config.php"
---~ from_prefix: "`$mySQLdefaultdb`.$mySQLprefix"
---~ globals: "$IMAGES_DIRECTORY"
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting ranks...
/******************************************************************************/

DELETE FROM {$to_prefix}membergroups
WHERE group_name LIKE 'e107%';

---{
	$request = convert_query("
		SELECT e107_value
		FROM {$from_prefix}core
		WHERE e107_name = 'pref'
		LIMIT 1");
	list($prefs) = convert_fetch_row($request);
	convert_free_result($request);

	$prefs = @unserialize(strtr($prefs, array("\n" => ' ', "\r" => ' ')));

	if (isset($prefs['forum_levels']) && isset($prefs['forum_thresholds']))
	{
		$inserts = '';
		$post_count = explode(',', $prefs['forum_thresholds']);
		foreach (explode(',', $prefs['forum_levels']) as $k => $groupname)
			if ($groupname !== '')
				$inserts .= "
					(SUBSTRING('e107 " . addslashes($groupname) . "', 1, 255), $prefs[forum_thresholds], '', '')";

		if (!empty($inserts))
			convert_query("
				INSERT INTO {$to_prefix}membergroups
					(group_name, min_posts, online_color, stars)
				VALUES " . substr($inserts, 0, -1));
	}
---}

/******************************************************************************/
--- Converting groups...
/******************************************************************************/

---* {$to_prefix}membergroups
SELECT
	SUBSTRING(CONCAT('e107 ', userclass_name), 1, 255) AS group_name,
	-1 AS min_posts, '' AS online_color, '' AS stars
FROM {$from_prefix}userclass_classes;
---*

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$row['signature'] = preg_replace(
	array(
		'~\[size=([789]|[012]\d)\]~is',
		'~\[link=(.+?)\](.+?)\[/link\]~is',
		'~\[link\](.+?)\[/link\]~is',
		'~\[quote.+?=(.+?)\]~is',
		'~\[/quote.+?\]~is',
		'~\[blockquote\](.+?)\[/blockquote\]~is',
		'~\[img:(width|height)=(\d{1,})(?:&|&amp;)(width|height)=(\d{1,})\](.+?)\[/img\]~is',
	),
	array(
		'[size=$1px]',
		'[url=$1]$2[/url]',
		'[url]$1[/url]',
		'[quote author=$1]',
		'[/quote]',
		'[quote]$1[/quote]',
		'[img $1=$2 $3=$4]$5[/img]',
	), ltrim($row['signature']));
---}
SELECT
	u.user_id AS id_member, SUBSTRING(u.user_loginname, 1, 80) AS member_name,
	u.user_join AS date_registered, u.user_forums AS posts,
	(CASE WHEN u.user_admin = 1 THEN 1 ELSE 0 END) AS id_group, u.user_lastvisit AS last_login,
	SUBSTRING(u.user_name, 1, 255) AS real_name,
	SUBSTRING(u.user_password, 1, 64) AS passwd,
	SUBSTRING(u.user_email, 1, 255) AS email_address, 0 AS gender,
	ue.user_birthday AS birthdate,
	SUBSTRING(REPLACE(ue.user_homepage, 'http://', ''), 1, 255) AS website_title,
	SUBSTRING(ue.user_homepage, 1, 255) AS website_url,
	SUBSTRING(ue.user_location, 1, 255) AS location,
	SUBSTRING(ue.user_icq, 1, 255) AS icq,
	SUBSTRING(ue.user_aim, 1, 16) AS aim,
	SUBSTRING(ue.user_msn, 1, 255) AS msn, u.user_hideemail AS hide_email,
	SUBSTRING(u.user_signature, 1, 65534) AS signature,
	CASE
		WHEN SUBSTRING(u.user_timezone, 1, 1) = '+'
		THEN SUBSTRING(u.user_timezone, 2)
		ELSE u.user_timezone
	END AS time_offset,
	SUBSTRING(u.user_image, 1, 255) AS avatar,
	SUBSTRING(u.user_customtitle, 1, 255) AS usertitle,
	SUBSTRING(u.user_ip, 1, 255) AS member_ip,
	SUBSTRING(u.user_ip, 1, 255) AS member_ip2, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text, '' AS yim,
	'' AS time_format, '' AS secret_question, '' AS secret_answer, '' AS password_salt,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set
FROM {$from_prefix}user AS u
	LEFT JOIN {$from_prefix}user_extended AS ue ON (ue.user_extended_id = u.user_id)
WHERE u.user_id != 0;
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
		SELECT u.user_id AS id_member, mg.id_group
	FROM {$from_prefix}userclass_classes AS uc
		INNER JOIN {$from_prefix}user AS u
		INNER JOIN {$to_prefix}membergroups AS mg
		WHERE FIND_IN_SET(uc.userclass_id, REPLACE(u.user_class, '.', ','))
			AND CONCAT('e107 ', uc.userclass_name) = mg.group_name
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
				$additional_groups .= ',' . $row['id_group'];
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
	CASE
		WHEN forum_id > 500
		THEN forum_id - 499
		ELSE forum_id
	END AS id_cat, SUBSTRING(forum_name, 1, 255) AS name,
	forum_order AS cat_order
FROM {$from_prefix}forum
WHERE forum_parent = 0;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	DISTINCT f.forum_id AS id_board, SUBSTRING(f.forum_name, 1, 255) AS name,
	SUBSTRING(f.forum_description, 1, 65534) AS description,
	CASE
		WHEN f.forum_parent > 500
		THEN f.forum_parent - 499
		ELSE f.forum_parent
	END AS id_cat, f.forum_sub AS id_parent,
	CASE WHEN f.forum_sub = 0 THEN 0 ELSE 1 END AS child_level, f.forum_threads AS num_topics,
	f.forum_threads + f.forum_replies AS num_posts, f.forum_order AS board_order,
	CASE f.forum_class
		WHEN 252 THEN '-1'
		WHEN 255 THEN ''
		WHEN 253 THEN '0'
		WHEN 251 THEN '0'
		WHEN 254 THEN ''
		WHEN 0 THEN '-1,0'
		ELSE IFNULL(mg.id_group, '')
	END AS member_groups
FROM {$from_prefix}forum AS f
	INNER JOIN {$from_prefix}forum AS c
	LEFT JOIN {$from_prefix}userclass_classes AS uc ON (uc.userclass_id = f.forum_class)
	LEFT JOIN {$to_prefix}membergroups AS mg ON (mg.group_name = CONCAT('e107 ', uc.userclass_name))
WHERE f.forum_parent != 0;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics 200
---{
$ignore = true;
---}
SELECT
	t.thread_id AS id_topic, t.thread_s AS is_sticky,
	t.thread_forum_id AS id_board, t.thread_id AS id_first_msg,
	IFNULL(tl.thread_id, t.thread_id) AS id_last_msg,
	IFNULL(us.user_id, 0) AS id_member_started,
	IFNULL(ul.user_id, IFNULL(us.user_id, 0)) AS id_member_updated,
	IFNULL(p.poll_id, 0) AS id_poll, COUNT(*) AS num_replies, t.thread_views AS num_views,
	CASE WHEN t.thread_active = 1 THEN 0 ELSE 1 END AS locked
FROM {$from_prefix}forum_t AS t
	LEFT JOIN {$from_prefix}forum_t AS tl ON (tl.thread_parent = t.thread_id AND tl.thread_datestamp = t.thread_lastpost)
	LEFT JOIN {$from_prefix}user AS us ON (us.user_id = SUBSTRING_INDEX(t.thread_user, '.', 1))
	LEFT JOIN {$from_prefix}user AS ul ON (ul.user_id = SUBSTRING_INDEX(tl.thread_user, '.', 1))
	LEFT JOIN {$from_prefix}polls AS p ON (p.poll_datestamp = t.thread_id)
WHERE t.thread_parent = 0
GROUP BY t.thread_id;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$ignore = true;
$row['body'] = preg_replace(
	array(
		'~\[size=([789]|[012]\d)\]~is',
		'~\[link=(.+?)\](.+?)\[/link\]~is',
		'~\[link\](.+?)\[/link\]~is',
		'~\[quote.+?=(.+?)\]~is',
		'~\[/quote.+?\]~is',
		'~\[blockquote\](.+?)\[/blockquote\]~is',
		'~\[img:(width|height)=(\d{1,})(?:&|&amp;)(width|height)=(\d{1,})\](.+?)\[/img\]~is',
		'~<span class=\'smallblacktext\'>.+?</span>~is',
		'~\[file=(.+?)\](.+?)\[/file\]~is',
	),
	array(
		'[size=$1px]',
		'[url=$1]$2[/url]',
		'[url]$1[/url]',
		'[quote author=$1]',
		'[/quote]',
		'[quote]$1[/quote]',
		'[img $1=$2 $3=$4]$5[/img]',
		'',
		'[b]File:[/b] [url=$1]$2[/url]',
	), ltrim($row['body']));
---}
SELECT
	CASE WHEN m.thread_parent = 0 THEN m.thread_id ELSE m.thread_parent END AS id_topic,
	m.thread_forum_id AS id_board, m.thread_datestamp AS poster_time,
	m.thread_id AS id_msg, IFNULL(u.user_id, 0) AS id_member,
	SUBSTRING(IFNULL(m.thread_name, '(No Subject)'), 1, 255) AS subject,
	SUBSTRING(SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(m.thread_user, '.', 2), '.', -1), 0x1, 1), 1, 255) AS poster_name,
	SUBSTRING(IFNULL(u.user_email, 'e107.imported@example.com'), 1, 255) AS poster_email,
	'0.0.0.0' AS poster_ip, 1 AS smileys_enabled, m.thread_thread AS body,
	m.thread_edit_datestamp AS modified_time, 'xx' AS icon,
	SUBSTRING(SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(m.thread_lastuser, '.', 2), '.', -1), 0x1, 1), 1, 255) AS modified_name
FROM {$from_prefix}forum_t AS m
	LEFT JOIN {$from_prefix}user AS u ON (u.user_id = SUBSTRING_INDEX(m.thread_user, '.', 1));
---*

/******************************************************************************/
--- Converting posts (step 2)...
/******************************************************************************/

---* {$to_prefix}messages (update id_topic)
SELECT m.thread_id AS id_topic, SUBSTRING(m.thread_name, 1, 255) AS subject
FROM {$from_prefix}forum_t AS m
WHERE m.thread_parent = 0;
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.poll_id AS id_poll, SUBSTRING(p.poll_title, 1, 255) AS question,
	0 AS voting_locked, 1 AS max_votes, p.poll_end_datestamp AS expire_time,
	0 AS hide_results, 0 AS change_vote, p.poll_admin_id AS id_member,
	SUBSTRING(SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING_INDEX(t.thread_user, '.', 2), '.', -1), 0x1, 1), 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	INNER JOIN {$from_prefix}forum_t AS t
WHERE p.poll_datestamp = t.thread_id;
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---{
$request = convert_query("
	SELECT
		poll_id, poll_options, poll_votes
	FROM {$from_prefix}polls AS p
		INNER JOIN {$from_prefix}forum_t AS t
	WHERE p.poll_datestamp = t.thread_id");
$inserts = '';
while ($row = convert_fetch_assoc($request))
{
	$separateOptions = explode(chr(1), $row['poll_options']);
	$countOptions = count($separateOptions);
	$separateVotes = explode(chr(1), $row['poll_votes']);

	for ($i = 0; $i <= $countOptions-2; $i++)
	{
		if (!empty($separateOptions))
			$inserts .= "
				('$row[poll_id]', '$i', '$separateOptions[$i]', '$separateVotes[$i]'),";
	}
}
convert_free_result($request);

if ($inserts !== '')
	convert_query("
		INSERT INTO {$to_prefix}poll_choices
			(id_poll, id_choice, label, votes)
		VALUES " . substr($inserts, 0, -1));
---}

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace(
	array(
		'~\[size=([789]|[012]\d)\]~is',
		'~\[link=(.+?)\](.+?)\[/link\]~is',
		'~\[link\](.+?)\[/link\]~is',
		'~\[quote.+?=(.+?)\]~is',
		'~\[/quote.+?\]~is',
		'~\[blockquote\](.+?)\[/blockquote\]~is',
		'~\[img:(width|height)=(\d{1,})(?:&|&amp;)(width|height)=(\d{1,})\](.+?)\[/img\]~is',
	),
	array(
		'[size=$1px]',
		'[url=$1]$2[/url]',
		'[url]$1[/url]',
		'[quote author=$1]',
		'[/quote]',
		'[quote]$1[/quote]',
		'[img $1=$2 $3=$4]$5[/img]',
	), ltrim($row['body']));
---}
SELECT
	pm.pm_id AS id_pm, uf.user_id AS id_member_from, 0 AS deleted_by_sender,
	SUBSTRING(pm.pm_from, 1, 255) AS from_name,
	pm.pm_sent AS msgtime,
	SUBSTRING(pm.pm_subject, 1, 255) AS subject,
	SUBSTRING(pm.pm_text, 1, 65534) AS body
FROM {$from_prefix}private_msg AS pm
	INNER JOIN {$from_prefix}user AS uf
WHERE uf.user_id = pm.pm_from;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm.pm_id AS id_pm, ut.user_id AS id_member, 0 AS bcc,
	IF (pm.pm_read_del = 0, 0, 1) AS is_read, 0 AS deleted, '-1' AS labels
FROM {$from_prefix}private_msg AS pm
	INNER JOIN {$from_prefix}user AS ut
WHERE ut.user_id = pm.pm_to;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT
	u.user_id AS id_member, t.thread_id AS id_topic, 0 AS sent
FROM {$from_prefix}forum_t AS t
	INNER JOIN {$from_prefix}user AS u
WHERE u.user_id = SUBSTRING_INDEX(t.thread_user, '.', 1)
	AND t.thread_active = 99
	AND t.thread_parent = 0;
---*

/******************************************************************************/
--- Converting board access...
/******************************************************************************/

REPLACE INTO {$to_prefix}settings
	(variable, value)
VALUES ('permission_enable_by_board', '0');

---# Do all board permissions...
---{
$request = convert_query("
	SELECT forum_id
	FROM {$from_prefix}forum
	WHERE forum_class = 251");
$readonlyBoards = array();
while ($row = convert_fetch_assoc($request))
	$readonlyBoards[] = $row['forum_id'];
convert_free_result($request);

if (!empty($readonlyBoards))
	convert_query("
		UPDATE {$to_prefix}boards
		SET permission_mode = 4
		WHERE id_board IN (" . implode(', ', $readonlyBoards) . ")
		LIMIT " . count($readonlyBoards));
---}
---#

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT f.forum_id AS id_board, u.user_id AS id_member
FROM {$from_prefix}forum AS f
	INNER JOIN {$from_prefix}user AS u
WHERE FIND_IN_SET(u.user_name, REPLACE(f.forum_moderators, ', ', ','));
---*

/******************************************************************************/
--- Converting banned users...
/******************************************************************************/

TRUNCATE {$to_prefix}ban_items;
TRUNCATE {$to_prefix}ban_groups;

---# Moving banned entries...
---{
$_REQUEST['start'] = isset($_REQUEST['start']) ? (int) $_REQUEST['start'] : 0;
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT banlist_ip, banlist_reason
		FROM {$from_prefix}banlist
		LIMIT $_REQUEST[start], 250");
	$ban_time = time();
	$ban_num = 0;
	while ($row = convert_fetch_assoc($result))
	{
		$ban_num++;
		convert_query("
			INSERT INTO {$to_prefix}ban_groups
				(name, ban_time, expire_time, notes, reason, cannot_access)
			VALUES ('migrated_ban_$ban_num', $ban_time, NULL, '', '" . addslashes($row['banlist_reason']) . "', 1)");
		$id_ban_group = convert_insert_id();

		if (empty($id_ban_group))
			continue;

		if (strpos($row['banlist_ip'], '@') !== false)
		{
			convert_query("
				INSERT INTO {$to_prefix}ban_items
					(id_ban_group, email_address, hostname)
				VALUES ($id_ban_group, '" . addslashes($row['banlist_ip']) . "', '')");
			continue;
		}
		else
		{
			list ($octet1, $octet2, $octet3, $octet4) = explode('.', $row['banlist_ip']);

			$ip_high1 = $octet1;
			$ip_low1 = $octet1;

			$ip_high2 = $octet2;
			$ip_low2 = $octet2;

			$ip_high3 = $octet3;
			$ip_low3 = $octet3;

			$ip_high4 = $octet4;
			$ip_low4 = $octet4;

			convert_query("
				INSERT INTO {$to_prefix}ban_items
					(id_ban_group, ip_low1, ip_high1, ip_low2, ip_high2, ip_low3, ip_high3, ip_low4, ip_high4, email_address, hostname)
				VALUES ($id_ban_group, $ip_low1, $ip_high1, $ip_low2, $ip_high2, $ip_low3, $ip_high3, $ip_low4, $ip_high4, '', '')");
			continue;
		}
	}

	$_REQUEST['start'] += 250;
	if (convert_num_rows($result) < 250)
		break;

	convert_free_result($result);
}
$_REQUEST['start'] = 0;
---}
---#

---# Moving banned user...
---{
$request = convert_query("
	SELECT user_id
	FROM {$from_prefix}user
	WHERE user_ban = 1");
if (convert_num_rows($request) > 0)
{
	convert_query("
		INSERT INTO {to_prefix}ban_groups
			(name, ban_time, expire_time, reason, notes, cannot_access)
			VALUES ('migrated_ban_users', $ban_time, NULL, '', 'Imported from e107', 1)");
		$id_ban_group = convert_insert_id();

	if (empty($id_ban_group))
		continue;

	$inserts = '';
	while ($row = convert_fetch_assoc($request))
		$inserts .= "
			($id_ban_group, $row[user_id], '', ''),";
	convert_free_result($request);

	convert_query("
		INSERT INTO {$to_prefix}ban_items
			(id_ban_group, id_member, email_address, hostname)
		VALUES " . substr($inserts, 0, -1));
}
---}
---#

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

---# Copying over smilies directory...
---{
$e107_smileys_dir = $_POST['path_from'] . '/' . $IMAGES_DIRECTORY . 'emotes';

// Select the known smileys from db
$request = convert_query("
	SELECT e107_name AS smiley_dir
	FROM {$from_prefix}core
	WHERE e107_name LIKE 'emote_%'");

$smileys_dir = array();
while ($row = convert_fetch_assoc($request))
	$smileys_dir[] = $row['smiley_dir'];

// Find the path for SMF smileys.
$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'smileys_dir'
	LIMIT 1");
list ($smf_smileys_dir) = convert_fetch_row($request);
convert_free_result($request);

foreach ($smileys_dir as $dir)
{
	$smf_dir = str_replace('emote_', 'e107_', $dir);

	// Now copy it.
	copy_smileys($e107_smileys_dir . '/' . $dir, $smf_smileys_dir . '/' . $smf_dir);
}
---}
---#

---# Converting smileys codes...
---{
// Get the known values
$request = convert_query("
	SELECT variable, value
	FROM {$to_prefix}settings
	WHERE variable IN ('smiley_sets_known', 'smiley_sets_names')");
while ($row = convert_fetch_assoc($request))
{
	if ($row['variable'] == 'smiley_sets_known')
	{
		$smiley_sets_known = $row['value'];
		$smiley_sets_known_array = explode(',', $row['value']);
	}
	if ($row['variable'] == 'smiley_sets_names')
	{
		$smiley_sets_names = $row['value'];
		$smiley_sets_names_array = explode("\n", $row['value']);
	}
}
convert_free_result($request);

// Get the max smiley_order
$request = convert_query("
	SELECT MAX(smiley_order)
	FROM {$to_prefix}smileys");
list ($count) = convert_fetch_row($request);
convert_free_result($request);

// SMF known smileys
$request = convert_query("
	SELECT code
	FROM {$to_prefix}smileys");
$currentCodes = array();
while ($row = convert_fetch_assoc($request))
	$currentCodes[] = $row['code'];
convert_free_result($request);

// Get the smileys sets from e107
$request = convert_query("
	SELECT e107_name, e107_value AS smiley_codes
	FROM {$from_prefix}core
	WHERE e107_name LIKE 'emote_%'");

$insert = '';
while ($row = convert_fetch_assoc($request))
{
	$smileys_set = @unserialize($row['smiley_codes']);

	if (empty($smileys_set))
		continue;

	// Known sets
	if (!in_array('e107_' . trim($row['e107_name']), trim($smiley_sets_known_array)))
		$smiley_sets_known .= ',' . str_replace('emote_', 'e107_', trim($row['e107_name']));

	// Known sets names
	if (!in_array('e107_' . ucfirst($row['e107_name']), $smiley_sets_names_array))
		$smiley_sets_names .= '
' . str_replace('emote_', 'e107 ', ucfirst($row['e107_name']));

	foreach ($smileys_set as $filename => $codeArray)
	{
		// Fix it.
		$filename = str_replace('!', '.', $filename);

		$codeArray = explode(' ', $codeArray);
		foreach ($codeArray as $code)
		{
			// Do we already have this code?  If so skip it.
			if (in_array($code, $currentCodes))
				continue;

			if (trim($code) == '')
				continue;

			// Is this smiley in the db already?
			if (isset($dupSmiley[$filename]))
				$hidden = "1";
			else
				$hidden = "0";

			$count++;
			$name = substr($filename, 0, strrpos($filename, '.'));
			$insert .= "
			('$code', '$filename', '$name', $count, '$hidden'),";
		}
	}
}
convert_free_result($request);

// Insert the new smileys
if (!empty($insert))
{
	convert_query("
		INSERT INTO {$to_prefix}smileys
			(code, filename, description, smiley_order, hidden)
		VALUES " . substr($insert, 0, -1));
}

// Set the new known smileys
convert_query("
	REPLACE INTO {$to_prefix}settings
		(variable, value)
	VALUES
		('smiley_sets_known', '$smiley_sets_known'),
		('smiley_sets_names', '$smiley_sets_names')");

---}
---#