/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "versatileBulletinBoard 1.0.0"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/admin/config.inc.php", "/admin/dbstart.php"
---~ from_prefix: "`$databasename`.{$dbprefix}_"
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$row['signature'] = substr(stripslashes($row['signature']), 0, 65534);
---}
SELECT
	u.ID AS id_member, SUBSTRING(u.name, 1, 80) AS member_name,
	SUBSTRING(u.name, 1, 255) AS real_name, SUBSTRING(u.pass, 1, 64) AS passwd,
	SUBSTRING(u.email, 1, 255) AS email_address,
	SUBSTRING(u.web, 1, 255) AS website_title,
	SUBSTRING(u.web, 1, 255) AS website_url,
	UNIX_TIMESTAMP(u.registered) AS date_registered,
	SUBSTRING(u.icq, 1, 255) AS icq, SUBSTRING(u.aim, 1, 16) AS aim,
	SUBSTRING(u.yahoo, 1, 32) AS yim, SUBSTRING(u.msn, 1, 255) AS msn,
	u.numposts AS posts, SUBSTRING(u.comment, 1, 255) AS personal_text,
	u.signature, UNIX_TIMESTAMP(u.lastlogin) AS last_login,
	SUBSTRING(u.last_IP, 1, 255) AS member_ip,
	SUBSTRING(u.last_IP, 1, 255) AS member_ip2,
	u.show_email != 'yes' AS hide_email, u.birthday AS birthdate,
	CASE u.gender WHEN 'M' THEN 1 WHEN 'F' THEN 2 ELSE 0 END AS gender,
	IF(ul.level = 5, 1, 0) AS id_group
FROM {$from_prefix}user AS u
	LEFT JOIN {$from_prefix}userlevel AS ul ON (ul.user_ID = u.ID)
WHERE pass != 'impossible'
GROUP BY u.ID;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT ID AS id_cat, corder AS cat_order, SUBSTRING(name, 1, 255) AS name
FROM {$from_prefix}category;
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
	ID AS id_board, forder AS board_order, category_ID AS id_cat,
	SUBSTRING(name, 1, 255) AS name, SUBSTRING(comment, 1, 65534) AS description,
	numposts AS num_posts, numthreads AS num_topics, parent AS id_parent,
	'-1,0' AS member_groups
FROM {$from_prefix}forum;
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
	t.ID AS id_topic, t.forum_ID AS id_board, t.closed != 'false' AS locked,
	t.user_ID AS id_member_started, t.numviews AS num_views, pt.ID AS id_poll,
	t.numreplies AS num_replies, t.fixed != 'false' AS is_sticky,
	t.ID AS id_first_msg, IFNULL(MAX(r.ID), t.ID) AS id_last_msg
FROM {$from_prefix}message AS t
	LEFT JOIN {$from_prefix}message AS r ON (r.reply = t.ID)
	LEFT JOIN {$from_prefix}mod_POLL_topic AS pt ON (pt.message_ID = t.ID)
WHERE t.reply = 0
	AND t.movelink = 0
GROUP BY t.ID
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, m.user_ID AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}message AS m ON (m.ID = t.id_last_msg);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$row['body'] = substr(stripslashes($row['body']), 0, 65534);
---}
SELECT
	m.ID AS id_msg, IF(m.reply = 0, m.ID, m.reply) AS id_topic,
	m.forum_ID AS id_board, UNIX_TIMESTAMP(m.date) AS poster_time,
	m.user_ID AS id_member, SUBSTRING(m.user_IP, 1, 255) AS poster_ip,
	SUBSTRING(m.subject, 1, 255) AS subject,
	SUBSTRING(u.email, 1, 255) AS poster_email,
	SUBSTRING(IFNULL(u.name, m.guestname), 1, 255) AS poster_name,
	SUBSTRING(REPLACE(m.content, '\r', ''), 1, 65534) AS body
FROM {$from_prefix}message AS m
	LEFT JOIN {$from_prefix}user AS u ON (u.ID = m.user_ID);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	pt.ID AS id_poll, SUBSTRING(pt.name, 1, 255) AS question,
	pt.creator AS id_member, pt.active != 'true' AS voting_locked,
	SUBSTRING(u.name, 1, 255) AS poster_name
FROM {$from_prefix}mod_POLL_topic AS pt
	LEFT JOIN {$from_prefix}user AS u ON (u.ID = pt.creator);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---{
alterDatabase('poll_choices', 'add column', array(
	'name' => 'temp_id',
	'type' => 'int',
	'size' => 10,
	'default' => 0,
));

---}

---* {$to_prefix}poll_choices
---{
if (!isset($_SESSION['convert_last_poll']) || $_SESSION['convert_last_poll'] != $row['id_poll'])
{
	$_SESSION['convert_last_poll'] = $row['id_poll'];
	$_SESSION['convert_last_choice'] = 0;
}

$row['id_choice'] = ++$_SESSION['convert_last_choice'];
---}
/* Its name for the id_poll is misleading, but right. */
SELECT
	po.topic_ID AS id_poll, 0 AS id_choice,
	SUBSTRING(po.option_name, 1, 255) AS label, COUNT(pv.ID) AS votes,
	po.ID AS temp_id
FROM {$from_prefix}mod_POLL_option AS po
	LEFT JOIN {$from_prefix}mod_POLL_vote AS pv ON (pv.xoption = po.ID)
GROUP BY po.ID
ORDER BY po.ID;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pv.poll_ID AS id_poll, pv.user_ID AS id_member, pc.id_choice
FROM {$from_prefix}mod_POLL_vote AS pv
	INNER JOIN {$to_prefix}poll_choices AS pc ON (pc.temp_id = pv.xoption)
WHERE pv.user_ID != 0;
---*

---{
alterDatabase('poll_choices', 'remove column', 'temp_id');
---}

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = stripslashes($row['body']);
---}
SELECT
	pm.ID AS id_pm, pm.from_user AS id_member_from,
	SUBSTRING(pm.subject, 1, 255) AS subject,
	UNIX_TIMESTAMP(pm.date) AS msgtime,
	SUBSTRING(u.name, 1, 255) AS from_name,
	SUBSTRING(REPLACE(pm.body, '\r', ''), 1, 65534) AS body
FROM {$from_prefix}pm AS pm
	LEFT JOIN {$from_prefix}user AS u ON (u.ID = pm.from_user);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	ID AS id_pm, to_user AS id_member, b_read != 'no' AS is_read, '-1' AS labels
FROM {$from_prefix}pm;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT user_ID AS id_member, forum_ID AS id_board
FROM {$from_prefix}subs;
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

if (copy($_POST['path_from'] . '/attachments/' . $row['filename'], $attachmentUploadDir . '/' . $physical_filename))
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
SELECT message_ID AS id_msg, filename, size, downloads
FROM {$from_prefix}attachment;
---*