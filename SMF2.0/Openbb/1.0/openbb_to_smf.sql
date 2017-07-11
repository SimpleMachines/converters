/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "OpenBB 1.0.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/lib/sqldata.php"
---~ from_prefix: "`{$database_server['database']}`.{$database_server['prefix']}"
---~ table_test: "{$from_prefix}profiles"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	p.id AS id_member, SUBSTRING(p.username, 1, 80) AS member_name,
	SUBSTRING(p.username, 1, 255) AS real_name,
	SUBSTRING(p.password, 1, 64) AS passwd,
	SUBSTRING(p.email, 1, 255) AS email_address,
	SUBSTRING(homepage, 1, 255) AS website_url,
	SUBSTRING(p.homepagedesc, 1, 255) AS website_title,
	SUBSTRING(p.icq, 1, 255) AS icq, SUBSTRING(p.aim, 1, 16) AS aim,
	SUBSTRING(p.yahoo, 1, 32) AS yim, SUBSTRING(p.msn, 1, 255) AS msn,
	SUBSTRING(p.location, 1, 255) AS location, p.showemail = 0 AS hide_email,
	p.birthdate, IF(ug.isadmin, 1, IF(ug.ismoderator, 2, 0)) AS id_group,
	p.posts, p.joindate AS date_registered, p.timeoffset AS time_offset,
	SUBSTRING(IF(p.avatar = 'blank.gif', '', p.avatar), 1, 255) AS avatar,
	SUBSTRING(p.custom, 1, 255) AS usertitle, p.invisible = 0 AS show_online,
	SUBSTRING(p.sig, 1, 65534) AS signature, SUBSTRING(ip, 1, 255) AS member_ip,
	SUBSTRING(ip, 1, 255) AS member_ip2,
	p.lastactive AS last_login, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	'' AS time_format, '' AS secret_question, '' AS secret_answer,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set,
	'' AS password_salt
FROM {$from_prefix}profiles AS p
	LEFT JOIN {$from_prefix}usergroup AS ug ON (ug.id = p.id)
WHERE p.username != '';
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	forumid AS id_cat, SUBSTRING(title, 1, 255) AS name,
	displayorder AS cat_order
FROM {$from_prefix}forum_display
WHERE type = 1;
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
	forumid AS id_board, parent AS id_parent, displayorder AS board_order,
	SUBSTRING(title, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, postcount AS num_posts,
	threadcount AS num_topics, dcount AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}forum_display
WHERE type IN (3, 6);
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
	t.id AS id_topic, t.forumid AS id_board, t.smode AS is_sticky, t.locked,
	t.posterid AS id_member_started, t.lastposterid AS id_member_updated,
	t.replies AS num_replies, t.views AS num_views, t.pollid AS id_poll,
	MIN(p.id) AS id_first_msg, MAX(p.id) AS id_last_msg
FROM {$from_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.threadid = t.id)
WHERE t.totopic = 0
GROUP BY id_topic
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
$row['subject'] = stripslashes($row['subject']);
$row['body'] = stripslashes($row['body']);
---}
SELECT
	p.id AS id_msg, p.threadid AS id_topic,
	SUBSTRING(p.poster, 1, 255) AS poster_name,
	SUBSTRING(p.title, 1, 255) AS subject, p.dateline AS poster_time,
	p.lastupdate AS modified_time,
	SUBSTRING(p.lastupdateby, 1, 255) AS modified_name, p.forumid AS id_board,
	m.id AS id_member, p.dsmiley = 0 AS smileys_enabled,
	SUBSTRING(p.ip, 1, 255) AS poster_ip,
	SUBSTRING(m.email, 1, 255) AS poster_email,
	SUBSTRING(REPLACE(p.message, '\n', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}profiles AS m ON (m.username = p.poster);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.id AS id_poll, SUBSTRING(t.title, 1, 255) AS question,
	t.posterid AS id_member, SUBSTRING(t.poster, 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	INNER JOIN {$from_prefix}topics AS t ON (t.pollid = p.id);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

for ($i = 1; $i <= 10; $i++)
{
	if (trim($row['option' . $i]) != '')
		$rows[] = "$row[id_poll], $i, SUBSTRING('" . addslashes($row['option' . $i]) . "', 1, 255), " . $row['answer' . $i];
}
---}
SELECT
	id AS id_poll, option1, option2, option3, option4, option5, option6,
	option7, option8, option9, option10, answer1, answer2, answer3, answer4,
	answer5, answer6, answer7, answer8, answer9, answer10
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT p.id AS id_poll, m.id AS id_member, 0 AS id_choice
FROM {$from_prefix}polls AS p
	INNER JOIN {$from_prefix}profiles AS m
WHERE FIND_IN_SET(m.username, p.total);
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['subject'] = substr(stripslashes($row['subject']), 0, 255);
$row['body'] = substr(stripslashes($row['body']), 0, 65534);
---}
SELECT
	id AS id_pm, userid AS id_member_from, time AS msgtime,
	SUBSTRING(send, 1, 255) AS from_name, subject,
	REPLACE(message, '\n', '<br />') AS body
FROM {$from_prefix}pmsg
WHERE box != 'outbox';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT pm.id AS id_pm, m.id AS id_member, isread AS is_read, '' AS labels
FROM {$from_prefix}pmsg AS pm
	INNER JOIN {$from_prefix}profiles AS m ON (m.username = pm.accept)
WHERE pm.box != 'outbox';
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT m.id AS id_member, threadid AS id_topic, visit AS sent
FROM {$from_prefix}favorites AS f
	INNER JOIN {$from_prefix}profiles AS m ON (m.username = f.username)
WHERE f.email = 1;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT modid AS id_member, forumid AS id_board
FROM {$from_prefix}moderators;
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

fwrite($fp, $row['filecontent']);
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
SELECT p.id AS id_msg, a.filecontent, a.downloaded AS downloads, a.filename
FROM {$from_prefix}attachments AS a
	INNER JOIN {$from_prefix}posts AS p ON (p.attachid = a.id);
---*