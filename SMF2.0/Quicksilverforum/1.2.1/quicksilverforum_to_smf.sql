/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Quick Silver Forum 1.2.1"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/settings.php"
---~ from_prefix: "`$set[db_name]`.$set[prefix]"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	u.user_id AS id_member, SUBSTRING(u.user_name, 1, 80) AS member_name,
	u.user_posts AS posts, u.user_joined AS date_registered,
	u.user_lastvisit AS last_login,
	IF(g.group_type = 'ADMIN', 1, 0) AS id_group,
	SUBSTRING(u.user_name, 1, 255) AS real_name,
	u.user_pm AS instant_messages, SUBSTRING(u.user_password, 1, 64) AS passwd,
	SUBSTRING(u.user_email, 1, 255) AS email_address,
	u.user_birthday AS birthdate,
	SUBSTRING(u.user_homepage, 1, 255) AS website_title,
	SUBSTRING(u.user_homepage, 1, 255) AS website_url,
	SUBSTRING(u.user_location, 1, 255) AS location,
	SUBSTRING(u.user_icq, 1, 255) AS icq, SUBSTRING(u.user_aim, 1, 16) AS aim,
	SUBSTRING(u.user_yahoo, 1, 32) AS yim,
	SUBSTRING(u.user_msn, 1, 255) AS msn,
	SUBSTRING(u.user_signature, 1, 65534) AS signature,
	IF(u.user_email_show, 0, 1) AS hide_email, u.user_timezone AS time_offset,
	SUBSTRING(IF(u.user_avatar_type != 'url', '', u.user_avatar), 1, 255) AS avatar,
	SUBSTRING(u.user_title, 1, 255) AS usertitle, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS member_ip, '' AS secret_question,
	'' AS secret_answer, '' AS validation_code, '' AS additional_groups,
	'' AS smiley_set, '' AS password_salt
FROM {$from_prefix}users AS u
	LEFT JOIN {$from_prefix}groups AS g ON (g.group_id = u.user_group)
WHERE u.user_id != 1;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	forum_id AS id_cat, SUBSTRING(forum_name, 1, 255) AS name,
	forum_position AS cat_order
FROM {$from_prefix}forums
WHERE forum_parent = 0;
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
	forum_id AS id_board, forum_parent AS id_parent,
	SUBSTRING(forum_name, 1, 255) AS name, forum_position AS board_order,
	SUBSTRING(forum_description, 1, 65534) AS description,
	forum_topics AS num_topics, forum_replies + forum_topics AS num_posts,
	'-1,0' AS member_groups
FROM {$from_prefix}forums
WHERE forum_parent != 0;
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
	t.topic_id AS id_topic, IF(t.topic_modes & 16, 1, 0) AS is_sticky,
	t.topic_forum AS id_board, t.topic_starter AS id_member_started,
	t.topic_last_poster AS id_member_updated, t.topic_replies AS num_replies,
	t.topic_views AS num_views, IF(t.topic_modes & 1, 1, 0) AS locked,
	MIN(p.post_id) AS id_first_msg, MAX(p.post_id) AS id_last_msg
FROM {$from_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.post_topic = t.topic_id)
GROUP BY t.topic_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
SELECT
	p.post_id AS id_msg, p.post_topic AS id_topic, p.post_time AS poster_time,
	p.post_author AS id_member, SUBSTRING(t.topic_title, 1, 255) AS subject,
	SUBSTRING(p.post_ip, 1, 255) AS poster_ip,
	SUBSTRING(IFNULL(u.user_name, 'Guest'), 1, 255) AS poster_name,
	t.topic_forum AS id_board,
	SUBSTRING(IFNULL(u.user_email, ''), 1, 255) AS poster_email,
	p.post_emoticons AS smileys_enabled,
	SUBSTRING(REPLACE(p.post_text, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}topics AS t ON (t.topic_id = p.post_topic)
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = p.post_author);
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
	WHERE id_topic = $row[id_poll]
	LIMIT 1");
---}
SELECT
	t.topic_id AS id_poll, SUBSTRING(t.topic_title, 1, 255) AS question,
	SUBSTRING(IFNULL(u.user_name, 'Guest'), 1, 255) AS poster_name,
	t.topic_starter AS id_member
FROM {$from_prefix}topics AS t
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = t.topic_starter)
WHERE t.topic_modes & 4;
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
if (!isset($last_id_poll) || $last_id_poll != $row['id_poll'])
{
	if (isset($last_id_poll) && !empty($choices))
	{
		foreach ($choices as $id => $label)
			$rows[] = "$last_id_poll, '" . addslashes($label) . "', " . ($id + 1) . ", 0";
		$choices = array();
	}

	$last_id_poll = $row['id_poll'];
	$choices = explode("\n", $row['label']);
}

$row['label'] = substr($choices[$row['id_choice'] - 1], 0, 255);
unset($choices[$row['id_choice'] - 1]);
---}
SELECT
	t.topic_id AS id_poll, t.topic_poll_options AS label,
	(v.vote_option + 1) AS id_choice, COUNT(DISTINCT v.vote_user) AS votes
FROM {$from_prefix}topics AS t
	LEFT JOIN {$from_prefix}votes AS v ON (v.vote_topic = t.topic_id)
WHERE t.topic_poll_options != ''
GROUP BY t.topic_id, v.vote_option;
---*

---{
if (isset($last_id_poll) && !empty($choices))
{
	$rows = array();
	foreach ($choices as $id => $label)
		$rows[] = array($last_id_poll, addslashes($label), ($id + 1), 0);
	$choices = array();

	convert_insert('poll_choices', array('id_poll', 'label', 'id_choice', 'votes'), $rows, 'replace');
}
---}

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT
	vote_topic AS id_poll, vote_user AS id_member,
	(vote_option + 1) AS id_choice
FROM {$from_prefix}votes;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	p.pm_id AS id_pm, p.pm_from AS id_member_from, p.pm_time AS msgtime,
	SUBSTRING(IFNULL(u.user_name, 'Guest'), 1, 255) AS from_name,
	SUBSTRING(p.pm_title, 1, 255) AS subject,
	SUBSTRING(p.pm_message, 1, 65534) AS body
FROM {$from_prefix}pmsystem AS p
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = p.pm_from)
WHERE p.pm_folder != 1;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT pm_id AS id_pm, pm_to AS id_member, pm_read AS is_read, '-1' AS labels
FROM {$from_prefix}pmsystem
WHERE pm_folder != 1;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

// Get the filesize!
$row['size'] = filesize($_POST['path_from'] . '/attachments/' . $row['attach_file']);

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($_POST['path_from'] . '/attachments/' . $row['attach_file'], $attachmentUploadDir . '/' . $physical_filename))
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
SELECT
	attach_file, attach_name AS filename, attach_post AS id_msg,
	attach_downloads AS downloads
FROM {$from_prefix}attach;
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;
$keys = array('id_member', 'filename', 'width', 'height', 'size');

$originalName = str_replace('./avatars/uploaded/', '', $row['filename']);

$row['size'] = filesize($_POST['path_from'] . '/avatars/uploaded/' . $originalName);
$fileName = str_replace(array('.avtr', './avatars/uploaded/'), array('.jpg', ''), $row['filename']);
$file_hash = getLegacyAttachmentFilename($fileName, $id_attach);

if (strlen($file_hash) <= 225 && (file_exists($_POST['path_from'] . '/avatars/uploaded/' . $originalName) && copy($_POST['path_from'] . '/avatars/uploaded/' . $originalName, $attachmentUploadDir . '/' . $physical_filename)))
	$rows[] = array(
		'id_attach' => $id_attach,
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_member' => $row['id_member'],
		'width' => $row['width'],
		'height' => $row['height'],
		'size' => $row['size'],
	);

$id_attach++;
---}
SELECT
	user_id AS id_member, user_avatar AS filename, user_avatar_width AS width,
	user_avatar_height AS height
FROM {$from_prefix}users
WHERE user_avatar_type = 'uploaded';
---*