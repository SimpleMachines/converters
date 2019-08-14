/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "phpBB3"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ defines: IN_PHPBB
---~ from_prefix: "`$dbname`.$table_prefix"
---~ table_test: "{$from_prefix}users"

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
	rank_image AS stars, '' AS description, IF(rank_special = 0, rank_min, -1) AS min_posts,
	'' AS online_color
FROM {$from_prefix}ranks
ORDER BY rank_min;
---*

/******************************************************************************/
--- Converting groups...
/******************************************************************************/

---* {$to_prefix}membergroups
SELECT
	SUBSTRING(CONCAT('phpBB ', group_name), 1, 255) AS group_name,
	-1 AS min_posts, '' AS stars, '' AS description, group_colour AS online_color
FROM {$from_prefix}groups
WHERE group_id NOT IN (1, 6);
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
		FROM {$from_prefix}config
		WHERE config_name = 'board_timezone'
		LIMIT 1");
	list ($board_timezone) = convert_fetch_row($request2);
	convert_free_result($request2);

	// Find out where uploaded avatars go
	$request2 = convert_query("
		SELECT value
		FROM {$to_prefix}settings
		WHERE variable = 'custom_avatar_enabled'
		LIMIT 1");

	if (convert_num_rows($request2))
		list ($custom_avatar_enabled) = convert_fetch_row($request2);
	else
		$custom_avatar_enabled = false;
	convert_free_result($request2);

	if ($custom_avatar_enabled)
	{
		// Custom avatar dir.
		$request2 = convert_query("
			SELECT value
			FROM {$to_prefix}settings
			WHERE variable = 'custom_avatar_dir'
			LIMIT 1");
		list ($avatar_dir) = convert_fetch_row($request2);
		$attachment_type = '1';
	}
	else
	{
		// Attachments dir.
		$request2 = convert_query("
			SELECT value
			FROM {$to_prefix}settings
			WHERE variable = 'attachmentUploadDir'
			LIMIT 1");
		list ($avatar_dir) = convert_fetch_row($request2);
		$attachment_type = '0';
	}
	convert_free_result($request2);

	$request2 = convert_query("
		SELECT config_value
		FROM {$from_prefix}config
		WHERE config_name = 'avatar_path'
		LIMIT 1");
	$phpbb_avatar_upload_path = $_POST['path_from'] . '/' . convert_result($request2, 0, 'config_value');
	convert_free_result($request2);

	$request2 = convert_query("
		SELECT config_value
		FROM {$from_prefix}config
		WHERE config_name = 'avatar_salt'
		LIMIT 1");
	$phpbb_avatar_salt = convert_result($request2, 0, 'config_value');
	convert_free_result($request2);
}

// time_offset = phpBB user TZ - phpBB board TZ.
$row['time_offset'] = $row['time_offset'] - $board_timezone;

if ($row['user_avatar_type'] == 0)
	$row['avatar'] = '';
// If the avatar type is uploaded (type = 1) copy avatar with the correct name.
elseif ($row['user_avatar_type'] == 1 && strlen($row['avatar']) > 0)
{
	$phpbb_avatar_ext = substr(strchr($row['avatar'], '.'), 1);
	$smf_avatar_filename = 'avatar_' . $row['id_member'] . strrchr($row['avatar'], '.');

	if (file_exists($phpbb_avatar_upload_path . '/' . $phpbb_avatar_salt . '_' . $row['id_member'] . '.' . $phpbb_avatar_ext))
		@copy($phpbb_avatar_upload_path . '/' . $phpbb_avatar_salt . '_' . $row['id_member'] . '.' . $phpbb_avatar_ext, $avatar_dir . '/' . $smf_avatar_filename);
	else
		@copy($phpbb_avatar_upload_path . '/' . $row['avatar'], $avatar_dir . '/' . $smf_avatar_filename);

	convert_insert('attachments', array('id_msg', 'id_member', 'filename', 'attachment_type'),
		array(0, $row['id_member'], substr(addslashes($smf_avatar_filename), 0, 255), $attachment_type)
	);

	$row['avatar'] = '';
}
elseif ($row['user_avatar_type'] == 3)
	$row['avatar'] = substr('gallery/' . $row['avatar'], 0, 255);
unset($row['user_avatar_type']);

if ($row['signature_uid'] != '')
	$row['signature'] = preg_replace('~(:u:|:1:|:)' . preg_quote($row['signature_uid'], '~') . '~i', '', $row['signature']);

$row['signature'] = preg_replace(
	array(
		'~\[quote=&quot;(.+?)&quot;(:.+?)?\]~is',
		'~\[quote(:.+?)?\]~is',
		'~\[/quote(:.+?)?\]~is',
		'~\[b(:.+?)?\]~is',
		'~\[/b(:.+?)?\]~is',
		'~\[i(:.+?)?\]~is',
		'~\[/i(:.+?)?\]~is',
		'~\[u(:.+?)?\]~is',
		'~\[/u(:.+?)?\]~is',
		'~\[url:(.+?)\]~is',
		'~\[/url:(.+?)?\]~is',
		'~\[url=(.+?):(.+?)\]~is',
		'~\[/url:(.+?)?\]~is',
		'~\<a(.+?) href="(.+?)">(.+?)</a>~is',
		'~\[img:(.+?)?\]~is',
		'~\[/img:(.+?)?\]~is',
		'~\[size=(.+?):(.+?)\]~is',
		'~\[/size(:.+?)?\]~is',
		'~\[color=(.+?):(.+?)\]~is',
		'~\[/color(:.+?)?\]~is',
		'~\[code=(.+?):(.+?)?\]~is',
		'~\[code(:.+?)?\]~is',
		'~\[/code(:.+?)?\]~is',
		'~\[list=(.+?):(.+?)?\]~is',
		'~\[list(:.+?)?\]~is',
		'~\[/list(:.+?)?\]~is',
		'~\[\*(:.+?)?\]~is',
		'~\[/\*(:.+?)?\]~is',
		'~<!-- (.+?) -->~is',
		'~<img src="{SMILIES_PATH}/(.+?)/(.+?)" alt="(.+?)" title="(.+?)" />~is',
	),
	array(
		'[quote author="$1"]',
		'[quote]',
		'[/quote]',
		'[b]',
		'[/b]',
		'[i]',
		'[/i]',
		'[u]',
		'[/u]',
		'[url]',
		'[/url]',
		'[url=$1]',
		'[/url]',
		'[url=$2]$3[/url]',
		'[img]',
		'[/img]',
		'[size=' . convert_percent_to_px("\1") . 'px]',
		'[/size]',
		'[color=$1]',
		'[/color]',
		'[code=$1]',
		'[code]',
		'[/code]',
		'[list type=$1]',
		'[list]',
		'[/list]',
		'[li]',
		'[/li]',
		'',
		'$3',
	), $row['signature']);

$row['signature'] = preg_replace('~\[size=(.+?)px\]~is', "[size=" . ('\1' > '99' ? 99 : '"\1"') . "px]", $row['signature']);

// This just does the stuff that it isn't work parsing in a regex.
$row['signature'] = strtr($row['signature'], array(
	'[list type=1]' => '[list type=decimal]',
	'[list type=a]' => '[list type=lower-alpha]',
	));

$row['signature'] = substr($row['signature'], 0, 65534);
unset($row['signature_uid']);

if (!is_numeric($row['id_group']))
	$row['id_group'] = 0;
---}
SELECT
	u.user_id AS id_member, SUBSTRING(u.username, 1, 80) AS member_name,
	SUBSTRING(u.username, 1, 255) AS real_name,
	SUBSTRING(u.user_password, 1, 64) AS passwd, u.user_lastvisit AS last_login,
	u.user_regdate AS date_registered,
	u.user_posts AS posts, IF(u.user_rank = 1, 1, IFNULL(mg.id_group, 0)) AS id_group,
	u.user_new_privmsg AS instant_messages,
	SUBSTRING(u.user_email, 1, 255) AS email_address,
	u.user_unread_privmsg AS unread_messages,
	u.user_allow_viewonline AS show_online, u.user_timezone AS time_offset,
	IF(u.user_allow_viewemail = 1, 0, 1) AS hide_email, u.user_avatar AS avatar,
	REPLACE(u.user_sig, '\n', '<br />') AS signature,
	u.user_sig_bbcode_uid AS signature_uid, u.user_avatar_type,
	u.user_notify_pm AS pm_email_notify,
	CASE u.user_inactive_reason WHEN 0 THEN 1 ELSE 0 END AS is_activated,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS usertitle, u.user_ip AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt, '' as openid_uri, '' AS ignore_boards, 
	u.user_ip AS member_ip2
FROM {$from_prefix}users AS u
	LEFT JOIN {$from_prefix}ranks AS r ON (r.rank_id = u.user_rank AND r.rank_special = 1)
	LEFT JOIN {$to_prefix}membergroups AS mg ON (mg.group_name = CONCAT('phpBB ', r.rank_title))
WHERE u.group_id NOT IN (1, 6)
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
		FROM {$from_prefix}groups AS g
			INNER JOIN {$from_prefix}user_group AS ug ON (ug.group_id = g.group_id)
			INNER JOIN {$to_prefix}members AS mem ON (mem.id_member = ug.user_id)
			INNER JOIN {$to_prefix}membergroups AS mg ON (mg.group_name = CONCAT('phpBB ', g.group_name))
		WHERE g.group_name NOT IN ('GUESTS', 'REGISTERED_COPPA', 'BOTS')
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
--- Preparing for categories conversion...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---{
// Add a temp_id column.
alterDatabase('categories', 'add column', array(
	'name' => 'temp_id',
	'type' => 'mediumint',
	'size' => 8,
	'default' => 0));
---}

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---# Converting categories...
---* {$to_prefix}categories
SELECT forum_id AS temp_id, SUBSTRING(forum_name, 1, 255) AS name, left_id AS cat_order
FROM {$from_prefix}forums
WHERE forum_type = 0
ORDER BY left_id;
---*
---#

---# Inserting board for uncategorized boards.
---{
$request = convert_query("
	SELECT COUNT(*)
	FROM {$to_prefix}categories
	WHERE name = 'Uncategorized Boards'");
list ($exists) = convert_fetch_row($request);
convert_free_result($request);

if (empty($exists))
	convert_insert('categories', array('temp_id', 'name', 'cat_order'), array(0, 'Uncategorized Boards', 1), 'replace');
---}
---#

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
---{
if (empty($row['id_cat']))
	$row['id_cat'] = 1;
$row['name'] = str_replace('\n', '<br />', $row['name']);
---}
SELECT
f.forum_id AS id_board, CASE WHEN f.parent_id = c.temp_id THEN 0 ELSE f.parent_id END AS id_parent, f.left_id AS board_order, f.forum_posts_approved AS num_posts,
    f.forum_last_post_id AS id_last_msg, SUBSTRING(f.forum_name, 1, 255) AS name, c.id_cat AS id_cat, '-1,0' AS member_groups,
    SUBSTRING(f.forum_desc, 1, 65534) AS description, f.forum_topics_approved AS num_topics, f.forum_last_post_id AS id_last_msg
FROM {$from_prefix}forums AS f
	LEFT JOIN {$to_prefix}categories AS c ON (c.temp_id = f.parent_id)
WHERE forum_type = 1
GROUP BY id_board;
---*

/******************************************************************************/
--- Fixing categories...
/******************************************************************************/

---{
alterDatabase('categories', 'remove column', 'temp_id');

// Lets fix the order.
$request = convert_query("
	SELECT id_cat, cat_order
	FROM {$to_prefix}categories
	ORDER BY cat_order");
$order = 1;
while ($row = convert_fetch_assoc($request))
{
	convert_query("
		UPDATE {$to_prefix}categories
		SET cat_order = $order
		WHERE id_cat = $row[id_cat]");
	$order++;
}

// Lets order them.
convert_query("
	ALTER TABLE {$to_prefix}categories
	ORDER BY cat_order");
---}

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics
---{
$ignore = true;
$row['id_poll'] = is_null($row['id_poll']) ? '0' : $row['id_poll'];
---}
SELECT
t.topic_id AS id_topic, t.forum_id AS id_board, t.topic_first_post_id AS id_first_msg,
    CASE t.topic_type WHEN 1 THEN 1 WHEN 2 THEN 1 ELSE 0 END AS is_sticky,
    t.topic_last_post_id AS id_last_msg, t.topic_poster AS id_member_started,
    t.topic_last_poster_id AS id_member_updated, po.topic_id AS id_poll,
    t.topic_posts_approved  AS num_replies, t.topic_views AS num_views,
    CASE t.topic_status WHEN 1 THEN 1 ELSE 0 END AS locked
FROM {$from_prefix}topics AS t
	LEFT JOIN {$from_prefix}poll_options AS po ON (po.topic_id = t.topic_id);
---*

/******************************************************************************/
--- Converting posts...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$ignore_slashes = true;
// This does the major work first
$row['body'] = preg_replace(
	array(
		'~\[quote=&quot;(.+?)&quot;\:(.+?)\]~is',
		'~\[quote\:(.+?)\]~is',
		'~\[/quote\:(.+?)\]~is',
		'~\[b\:(.+?)\]~is',
		'~\[/b\:(.+?)\]~is',
		'~\[i\:(.+?)\]~is',
		'~\[/i\:(.+?)\]~is',
		'~\[u\:(.+?)\]~is',
		'~\[/u\:(.+?)\]~is',
		'~\[url\:(.+?)\]~is',
		'~\[/url\:(.+?)\]~is',
		'~\[url=(.+?)\:(.+?)\]~is',
		'~\[/url\:(.+?)\]~is',
		'~\<a(.+?) href="(.+?)">(.+?)</a>~is',
		'~\[img\:(.+?)\]~is',
		'~\[/img\:(.+?)\]~is',
		'~\[size=(.+?)\:(.+?)\]~is',
		'~\[/size\:(.+?)?\]~is',
		'~\[color=(.+?)\:(.+?)\]~is',
		'~\[/color\:(.+?)\]~is',
		'~\[code=(.+?)\:(.+?)\]~is',
		'~\[code\:(.+?)\]~is',
		'~\[/code\:(.+?)\]~is',
		'~\[list=(.+?)\:(.+?)\]~is',
		'~\[list\:(.+?)\]~is',
		'~\[/list\:(.+?)\]~is',
		'~\[\*\:(.+?)\]~is',
		'~\[/\*\:(.+?)\]~is',
		'~\<img src=\"{SMILIES_PATH}/(.+?)\" alt=\"(.+?)\" title=\"(.+?)\" /\>~is',
	),
	array(
		'[quote author="$1"]',
		'[quote]',
		'[/quote]',
		'[b]',
		'[/b]',
		'[i]',
		'[/i]',
		'[u]',
		'[/u]',
		'[url]',
		'[/url]',
		'[url=$1]',
		'[/url]',
		'[url=$2]$3[/url]',
		'[img]',
		'[/img]',
		'[size=' . convert_percent_to_px("\1") . 'px]',
		'[/size]',
		'[color=$1]',
		'[/color]',
		'[code=$1]',
		'[code]',
		'[/code]',
		'[list type=$1]',
		'[list]',
		'[/list]',
		'[li]',
		'[/li]',
		'$2',
	), $row['body']);

$row['body'] = preg_replace('~\[size=(.+?)px\]~is', "[size=" . ('\1' > '99' ? 99 : '"\1"') . "px]", $row['body']);

// This just does the stuff that it isn't work parsing in a regex.
$row['body'] = strtr($row['body'], array(
	'[list type=1]' => '[list type=decimal]',
	'[list type=a]' => '[list type=lower-alpha]',
	));
$row['body'] = stripslashes($row['body']);
---}
SELECT
	p.post_id AS id_msg, p.topic_id AS id_topic, p.forum_id AS id_board,
	p.post_time AS poster_time, p.poster_id AS id_member, p.post_subject AS subject,
	IFNULL(m.username, 'Guest') AS poster_name,
	IFNULL(m.user_email, 'Unknown') AS poster_email,
	IFNULL(p.poster_ip, '0.0.0.0') AS poster_ip,
	p.enable_smilies AS smileys_enabled, p.post_edit_time AS modified_time,
	 p.post_text AS body,
	        (
	            CASE
	                WHEN p.post_edit_user = 0 THEN 'Guest'
	                WHEN m2.username IS NULL THEN 'Guest'
	                ELSE m2.username
	            END
        ) AS modified_name
FROM {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}users AS m ON (m.user_id = p.poster_id)
	LEFT JOIN {$from_prefix}users AS m2 ON (m2.user_id = p.post_edit_user);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	t.topic_id AS id_poll, t.poll_title AS question, t.poll_max_options AS max_votes, IF((t.poll_start + t.poll_length) < 0, 0, (t.poll_start + t.poll_length)) AS expire_time,
	t.poll_vote_change AS change_vote, t.topic_poster AS id_member, IFNULL(m.username, 0) AS poster_name
FROM {$from_prefix}topics AS t
	LEFT JOIN {$from_prefix}users AS m ON (m.user_id = t.topic_poster)
WHERE t.poll_title != '';
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$ignore = true;
---}
SELECT
	topic_id AS id_poll, poll_option_id AS id_choice,
	SUBSTRING(poll_option_text, 1, 255) AS label, poll_option_total AS votes
FROM {$from_prefix}poll_options;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
---{
$ignore = true;
---}
SELECT topic_id AS id_poll, vote_user_id AS id_member, poll_option_id AS id_choice
FROM {$from_prefix}poll_votes
WHERE vote_user_id > 0;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.msg_id AS id_pm, pm.author_id AS id_member_from, pm.message_time AS msgtime,
	SUBSTRING(uf.username, 1, 255) AS from_name, SUBSTRING(pm.message_subject, 1, 255) AS subject,
	SUBSTRING(REPLACE(IF(pm.bbcode_uid = '', pm.message_text, REPLACE(REPLACE(pm.message_text, CONCAT(':1:', pm.bbcode_uid), ''), CONCAT(':', pm.bbcode_uid), '')), '\n', '<br />'), 1, 65534) AS body
FROM {$from_prefix}privmsgs AS pm
	LEFT JOIN {$from_prefix}users AS uf ON (uf.user_id = pm.author_id);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
---{
$ignore = true;
---}
SELECT
	pm.msg_id AS id_pm, pm.user_id AS id_member, '-1' AS labels,
	CASE pm.pm_unread WHEN 1 THEN 0 ELSE 1 END AS is_read, pm.pm_deleted AS deleted
FROM {$from_prefix}privmsgs_to AS pm;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

if (!isset($oldAttachmentDir))
{
	$result = convert_query("
		SELECT config_value
		FROM {$from_prefix}config
		WHERE config_name = 'upload_path'
		LIMIT 1");
	list ($oldAttachmentDir) = convert_fetch_row($result);
	convert_free_result($result);

	if (empty($oldAttachmentDir) || !file_exists($_POST['path_from'] . '/' . $oldAttachmentDir))
		$oldAttachmentDir = $_POST['path_from'] . '/file';
	else
		$oldAttachmentDir = $_POST['path_from'] . '/' . $oldAttachmentDir;
}

// Get $id_attach.
if (empty($id_attach))
{
	$result = convert_query("
		SELECT MAX(id_attach) + 1
		FROM {$to_prefix}attachments");
	list ($id_attach) = convert_fetch_row($result);
	convert_free_result($result);

	$id_attach = empty($id_attach) ? 1 : $id_attach;
}

// Set the default empty values.
$width = 0;
$height = 0;

// Is an an image?
$attachmentExtension = strtolower(substr(strrchr($row['filename'], '.'), 1));
if (!in_array($attachmentExtension, array('jpg', 'jpeg', 'gif', 'png', 'bmp')))
	$attachmentExtension = '';

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;
if (copy($oldAttachmentDir . '/' . $row['physical_filename'], $attachmentUploadDir . '/' . $physical_filename))
{
	// Is an an image?
	if (!empty($attachmentExtension))
	{
		list ($width, $height) = getimagesize($attachmentUploadDir . '/' . $physical_filename);
		// This shouldn't happen but apparently it might
		if(empty($width))
			$width = 0;
		if(empty($height))
			$height = 0;
	}
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
		'width' => $width,
		'height' => $height,
	);
	$id_attach++;
}
---}
SELECT
	post_msg_id AS id_msg, download_count AS downloads,
	real_filename AS filename, physical_filename, filesize AS size
FROM {$from_prefix}attachments;
---*
