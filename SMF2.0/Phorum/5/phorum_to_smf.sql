/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Phorum 5"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ defines: PHORUM
---~ settings: "/include/db/config.php"
---~ from_prefix: "`{$PHORUM['DBCONFIG']['name']}`.{$PHORUM['DBCONFIG']['table_prefix']}_"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	user_id AS id_member, SUBSTRING(username, 1, 80) AS member_name,
	SUBSTRING(username, 1, 255) AS real_name,
	SUBSTRING(password, 1, 64) AS passwd,
	SUBSTRING(email, 1, 255) AS email_address, hide_email AS hide_email,
	date_added AS date_registered, date_last_active AS last_login,
	IF(hide_activity = 1, 0, 1) AS show_online, active AS is_activated,
	SUBSTRING(signature, 1, 65534) AS signature, posts,
	IF(admin = 1, 1, 0) AS id_group, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	'' AS website_title, '' AS website_url, '' AS location, '' AS icq, '' AS aim,
	'' AS yim, '' AS msn, '' AS time_format, '' AS avatar, '' AS usertitle,
	'' AS member_ip, '' AS secret_question, '' AS secret_answer,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set,
	'' AS password_salt, '' AS member_ip2
FROM {$from_prefix}users;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---{
convert_insert('categories', array('id_cat', 'name'), array(1, 'General Category'));
---}

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	forum_id AS id_board, 1 AS id_cat, display_order AS board_order,
	SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, thread_count AS num_topics,
	message_count AS num_posts, '-1,0' AS member_groups
FROM {$from_prefix}forums
GROUP BY forum_id;
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
	m.thread AS id_topic, m.forum_id AS id_board, m.message_id AS id_first_msg,
	m.user_id AS id_member_started, (m.thread_count - 1) AS num_replies,
	m.viewcount AS num_views, IF(m.sort = 1, 1, 0) AS is_sticky,
	MAX(m2.message_id) AS id_last_msg, m.closed AS locked
FROM {$from_prefix}messages AS m
	INNER JOIN {$from_prefix}messages AS m2 ON (m2.thread = m.thread)
WHERE m.message_id = m.thread
	AND m.parent_id = 0
GROUP BY m.thread
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, m.user_id AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}messages AS m ON (m.message_id = t.id_last_msg);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
SELECT
	m.message_id AS id_msg, m.thread AS id_topic, m.datestamp AS poster_time,
	m.user_id AS id_member, SUBSTRING(m.subject, 1, 255) AS subject,
	SUBSTRING(IFNULL(u.email, m.email), 1, 255) AS poster_email,
	SUBSTRING(IFNULL(u.username, m.author), 1, 255) AS poster_name,
	m.forum_id AS id_board,
	SUBSTRING(IF(m.ip = 'localhost', '127.0.0.1', m.ip), 1, 255) AS poster_ip,
	SUBSTRING(REPLACE(m.body, '<br>', '<br />'), 1, 65534) AS body,
	'' AS modified_name, 'xx' AS icon
FROM {$from_prefix}messages AS m
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = m.user_id);
---*

/******************************************************************************/
--- Removing polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	p.private_message_id AS id_pm, p.from_user_id AS id_member_from,
	p.datestamp AS msgtime,
	SUBSTRING(IFNULL(u.username, p.from_username), 1, 255) AS from_name,
	SUBSTRING(p.subject, 1, 255) AS subject,
	SUBSTRING(p.message, 1, 255) AS body, p.from_del_flag AS deleted_by_sender
FROM {$from_prefix}private_messages AS p
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = p.from_user_id);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	private_message_id AS id_pm, to_user_id AS id_member, read_flag AS is_read,
	to_del_flag AS deleted, '-1' AS labels
FROM {$from_prefix}private_messages;
---*

/******************************************************************************/
--- Converting thread suscriptions...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT user_id AS id_member, thread AS id_topic
FROM {$from_prefix}subscribers;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (strlen($file_hash) > 255)
	return;
$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

fwrite($fp, base64_decode($row['filedata']));
fclose($fp);

$rows[] = array(
	'id_attach' => $id_attach,
	'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
	'filename' => $row['filename'],
	'file_hash' => $file_hash,
	'id_msg' => $row['id_msg'],
	'downloads' => $row['downloads'],
);
$id_attach++;
---}
SELECT file_data AS filedata, filename AS filename, message_id AS id_msg
FROM {$from_prefix}files;
---*