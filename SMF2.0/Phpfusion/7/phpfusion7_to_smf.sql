/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "PHPFusion 7.0.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ from_prefix: "`{$db_name}`.$db_prefix"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$temp = explode('.', $row['additional_groups']);

$new_groups = array();
foreach ($temp AS $grp)
	$new_groups[] = $grp + 8;

$row['additional_groups'] = implode(',', $new_groups);
---}
SELECT
	user_id AS id_member, SUBSTRING(user_name, 1, 80) AS member_name,
	user_joined AS date_registered, user_posts AS posts, SUBSTRING(user_password, 1, 64) AS passwd,
	SUBSTRING(user_web, 1, 255) AS website_title,
	SUBSTRING(user_web, 1, 255) AS website_url, user_lastvisit AS last_login,
	user_birthdate AS birthdate, SUBSTRING(user_icq , 1, 255) AS icq,
	SUBSTRING(user_name, 1, 255) AS real_name,
	'' AS lngfile,
	SUBSTRING(user_email, 1, 255) AS email_address,
	SUBSTRING(user_aim, 1, 16) AS aim,
	'' AS personal_text,
	user_hide_email AS hide_email, SUBSTRING(user_ip , 1, 255) AS member_ip,
	SUBSTRING(user_ip , 1, 255) AS member_ip2,
	SUBSTRING(user_yahoo, 1, 32) AS yim, 0 AS gender,
	SUBSTRING(user_msn, 1, 255) AS msn,
	SUBSTRING(REPLACE(user_sig, '<br>', '<br />'), 1, 65534) AS signature,
	SUBSTRING(user_location, 1, 255) AS location, user_offset AS time_offset,
	SUBSTRING(user_avatar, 1, 255) AS avatar,
	'' AS usertitle, 0 AS pm_email_notify, 0 AS karma_bad, 0 AS karma_good,
	0 AS notify_announcements, '' AS secret_question, '' AS secret_answer,
	IF(user_level = 103, 1, 0) AS id_group, '' AS buddy_list, '' AS pm_ignore_list,
	'' AS message_labels, '' AS validation_code, user_groups AS additional_groups,
	'' AS smiley_set, '' AS password_salt
FROM {$from_prefix}users;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT forum_id AS id_cat, SUBSTRING(forum_name, 1, 255) AS name, forum_order AS cat_order, 1 AS can_collapse
FROM {$from_prefix}forums
WHERE forum_cat = 0;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

---* {$to_prefix}boards
SELECT
	forum_id AS id_board, forum_cat AS id_cat, SUBSTRING(forum_name, 1, 255) AS name, forum_order AS board_order,
	SUBSTRING(forum_description, 1, 65534) AS description, 0 AS num_topics, 0 AS num_posts,
	0 AS count_posts,
	CASE forum_access
		WHEN 0 THEN '-1,0'
		WHEN 101 THEN '0'
		WHEN 102 THEN '2'
		WHEN 103 THEN ''
		ELSE (forum_access + 8)
	END AS member_groups
FROM {$from_prefix}forums
WHERE forum_cat != 0;
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
/* Oddly enough the converter script doesn't like us using this unless its set in a variable */
$temp = $row['id_topic'];

$request = convert_query("
	SELECT
		COUNT(post_id) - 1 as num_replies, IFNULL(MIN(post_id), 0) as id_first_msg, IFNULL(MAX(post_id), 0) AS id_last_msg
	FROM {$from_prefix}posts
	WHERE thread_id = " . $temp);

list($row['num_replies'], $row['id_first_msg'], $row['id_last_msg']) = convert_fetch_row($request);
---}
SELECT
	thread_id AS id_topic, forum_id AS id_board, thread_sticky AS is_sticky, 0 AS id_poll,
	thread_views AS num_views, thread_author AS id_member_started, thread_lastuser AS id_member_updated, 0 AS num_replies, thread_locked AS locked,
	0 AS id_first_msg, 0 AS id_last_msg
FROM {$from_prefix}threads;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~\[quote\]\[b\](.*?) wrote:\[/b\]~is',
		'~\[mail\](.+?)\[/mail\]~is',
		'~\[mail=(.+?)\](.+?)\[/mail\]~is',
		'~\[small\](.+?)\[/small\]~is',
	),
	array(
		'[quote author=$1]',
		'[email]$1[/email]',
		'[email=$1]$2[/email]',
		'[size=8px]$1[/size]',

	), $row['body']);

---}
SELECT
	p.post_id AS id_msg, p.thread_id AS id_topic, p.forum_id AS id_board, p.post_author AS id_member, p.post_datestamp AS poster_time,
	SUBSTRING(mem.user_name, 1, 255) AS poster_name,
	SUBSTRING(mem.user_email, 1, 255) AS poster_email,
	SUBSTRING(p.post_ip, 1, 255) AS poster_ip, 'xx' AS icon,
	SUBSTRING(t.thread_subject, 1, 255) AS subject, p.post_smileys AS smileys_enabled,
	p.post_edittime AS modified_time, SUBSTRING(modmem.user_name, 1, 255) AS modified_name,
	SUBSTRING(REPLACE(p.post_message, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}threads AS t ON (p.thread_id = t.thread_id)
	LEFT JOIN {$from_prefix}users AS mem ON (p.post_author = mem.user_id)
	LEFT JOIN {$from_prefix}users AS modmem ON (p.post_edituser = modmem.user_id);

---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.message_id AS id_pm, pm.message_from AS id_member_from, pm.message_datestamp AS msgtime,
	SUBSTRING(fmem.user_name, 1, 255) AS from_name,
	SUBSTRING(pm.message_subject, 1, 255) AS subject,
	SUBSTRING(pm.message_message, 1, 65534) AS body,
	0 AS deleted_by_sender
FROM {$from_prefix}messages AS pm
	LEFT JOIN {$from_prefix}users AS fmem ON (pm.message_from = fmem.user_id);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
/* for saftey we treat all messages as read */
SELECT
	message_id AS id_pm, message_to AS id_member, message_read AS is_read,
	0 AS deleted, '-1' AS labels
FROM {$from_prefix}messages;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
/* Assume all notifications are sent or we might get mass mailings. */
SELECT
	notify_user AS id_member, thread_id AS id_topic, notify_status AS sent
FROM {$from_prefix}thread_notify;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;
$ignore = true;

// Hopefully we have the path to php-fusion.
if (!file_exists($_POST['path_from']))
	return;

$yAttachmentDir = $_POST['path_from'] . '/forum/attachments';

if (!file_exists($yAttachmentDir))
	return;

$file_hash = getAttachmentFilename($row['filename'], $row['id_attach'], null, true);
$physical_filename = $row['id_attach'] . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($yAttachmentDir . '/' . $row['filename'], $attachmentUploadDir . '/' . $physical_filename))
{
	$no_add = false;
	$rows[] = array(
		'id_attach' => $row['id_attach'],
		'size' => $row['size'],
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
		'width' => $row['width'],
		'height' => $row['height'],
	);
}
---}
SELECT
	attach_id AS id_attach, attach_size AS size, attach_name AS filename,
	post_id AS id_msg, 0 AS downloads, 0 AS width, 0 AS height
FROM {$from_prefix}forum_attachments;
---*

/******************************************************************************/
--- Converting membergroups...
/******************************************************************************/

DELETE FROM {$to_prefix}permissions
WHERE id_group > 8;

DELETE FROM {$to_prefix}membergroups
WHERE id_group > 8;

---* {$to_prefix}membergroups
	/* To get around weird ids we jump a little. We skip 8 just so its easier to know where the ids went */
	SELECT group_id + 8 AS id_group, group_name AS group_name, '' AS online_color, '-1' AS min_posts, '0' AS max_messages, '0' AS stars
	FROM {$from_prefix}user_groups;
---*
