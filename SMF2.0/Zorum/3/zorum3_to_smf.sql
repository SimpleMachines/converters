/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Zorum 3"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php", "/constants.php"
---~ variable: "$applName = 'zorum';"
---~ from_prefix: "`$dbName`.{$applName}_"
---~ table_test: "{$from_prefix}zorumuser"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---{
alterDatabase('members', 'add column', array(
	'name' => 'temp_id',
	'type' => 'int',
	'size' => 10,
	'default' => 0));
---}

---* {$to_prefix}members
SELECT
	id AS temp_id, SUBSTRING(name, 1, 80) AS member_name,
	SUBSTRING(name, 1, 255) AS real_name,
	SUBSTRING(email, 1, 255) AS email_address,
	SUBSTRING(password, 1, 64) AS passwd, IF(isAdm, 1, If(isMod, 2, 0)) AS id_group,
	lastClickTime AS last_login, creationtime AS date_registered,
	postnum AS posts, showEmail = 0 AS hide_email,
	SUBSTRING(REPLACE(signature, '\n', '<br />'), 1, 65534) AS signature,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS website_title, '' AS website_url, '' AS location,
	'' AS icq, '' AS aim, '' AS yim, '' AS msn, '' AS time_format, '' AS avatar,
	'' AS usertitle, '' AS member_ip, '' AS secret_question, '' AS secret_answer,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set,
	'' AS password_salt, '' AS member_ip2
FROM {$from_prefix}zorumuser
WHERE password != '';
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id AS id_cat, SUBSTRING(name, 1, 255) AS name, id AS cat_order
FROM {$from_prefix}forum
WHERE iscat = 1;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	f.id AS id_board, IFNULL(cat.id, 1) AS id_cat, f.id AS board_order,
	SUBSTRING(f.name, 1, 255) AS name,
	SUBSTRING(f.description, 1, 65534) AS description, f.topicnum AS num_topics,
	f.postnum AS num_posts, '-1,0' AS member_groups
FROM {$from_prefix}forum AS f
	LEFT JOIN {$from_prefix}forum AS cat ON (cat.treeidx < f.treeidx AND cat.iscat = 1)
WHERE f.iscat = 0;
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
	t.id AS id_topic, t.pid AS id_board, t.postnum - 1 AS num_replies,
	t.viewnum AS num_views, IF(t.poll, p.id, 0) AS id_poll,
	memf.id_member AS id_member_started, MIN(m.id) AS id_first_msg,
	MAX(m.id) AS id_last_msg
FROM {$from_prefix}topic AS t
	INNER JOIN {$from_prefix}message AS m ON (m.tid = t.id)
	LEFT JOIN {$from_prefix}poll AS p ON (p.tid = t.id)
	LEFT JOIN {$to_prefix}members AS memf ON (memf.temp_id = t.ownerId)
GROUP BY t.id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, meml.id_member AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}message AS m ON (m.id = t.id_last_msg)
	INNER JOIN {$to_prefix}members AS meml ON (meml.temp_id = m.ownerId);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
SELECT
	m.id AS id_msg, m.pid AS id_board, m.tid AS id_topic,
	SUBSTRING(m.iplog, 1, 255) AS poster_ip,
	SUBSTRING(IF(m.subject = '', t.subject, m.subject), 1, 255) AS subject,
	mem.id_member, SUBSTRING(REPLACE(m.txt, '\n', '<br />'), 1, 65534) AS body,
	m.creationtime AS poster_time, m.smiley AS smileys_enabled,
	SUBSTRING(mem.email_address, 1, 255) AS poster_email,
	SUBSTRING(IFNULL(mem.member_name, u.name), 1, 255) AS poster_name,
	'' AS modified_name, 'xx' AS icon
FROM {$from_prefix}message AS m
	INNER JOIN {$from_prefix}topic AS t ON (t.id = m.tid)
	LEFT JOIN {$to_prefix}members AS mem ON (mem.temp_id = m.ownerId)
	LEFT JOIN {$from_prefix}zorumuser AS u ON (u.id = m.ownerId);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.id AS id_poll, SUBSTRING(p.question, 1, 255) AS question, mem.id_member,
	SUBSTRING(IFNULL(mem.member_name, u.name), 1, 255) AS poster_name
FROM {$from_prefix}poll AS p
	LEFT JOIN {$to_prefix}members AS mem ON (mem.temp_id = p.ownerId)
	LEFT JOIN {$from_prefix}zorumuser AS u ON (u.id = p.ownerId);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

/* This makes counting the votes up much, much easier. */
---{
alterDatabase('poll_choices', 'remove index', 'primary');
alterDatabase('poll_choices', 'add column', array(
	'name' => 'id_temp',
	'type' => 'int',
	'size' => 10,
	'auto' => true,
	'default' => 0));
alterDatabase('poll_choices', 'add index', array(
	'type' => 'primary'
	'columns' => array('id_temp'),
	));
---}

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

for ($i = 1; $i <= 10; $i++)
{
	if (trim($row['q' . $i]) != '')
		$rows[] = "$row[id_poll], $i, '" . addslashes(substr($row['q' . $i], 0, 255)) . "', 0";
}
---}
SELECT id AS id_poll, q1, q2, q3, q4, q5, q6, q7, q8, q9, q10
FROM {$from_prefix}poll;
---*

---* {$to_prefix}poll_choices (update ID_TEMP)
SELECT pc.ID_TEMP, COUNT(*) AS votes
FROM {$to_prefix}poll_choices AS pc
	INNER JOIN {$from_prefix}subscribe AS s ON (s.objid = pc.id_poll AND s.info = pc.id_choice)
WHERE s.type = 65536
GROUP BY pc.ID_TEMP;
---*

---{
alterDatabase('poll_choices', 'remove index', 'primary');
alterDatabase('poll_choices', 'remove column', 'id_temp');
alterDatabase('poll_choices', 'add index', array(
	'type' => 'primary'
	'columns' => array('id_poll', 'id_choice'),
	));
---}

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT s.objid AS id_poll, mem.id_member, s.info AS id_choice
FROM {$from_prefix}subscribe AS s
	INNER JOIN {$to_prefix}members AS mem ON (mem.temp_id = s.userid)
WHERE s.type = 65536;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT mem.id_member, s.objid AS id_topic
FROM {$from_prefix}subscribe AS s
	INNER JOIN {$to_prefix}members AS mem ON (mem.temp_id = s.userid)
WHERE s.type = 16;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT mem.id_member, s.objid AS id_board
FROM {$from_prefix}subscribe AS s
	INNER JOIN {$to_prefix}members AS mem ON (mem.temp_id = s.userid)
WHERE s.type = 8;
---*

/******************************************************************************/
--- Cleaning up...
/******************************************************************************/

---{
alterDatabase('members', 'remove column', 'temp_id');
---}

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

$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

fwrite($fp, $row['file']);
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
SELECT
	m.id AS id_msg, m.downloaded AS downloads, m.att_file_upload AS filename,
	m.attsize AS size, a.file
FROM {$from_prefix}attach AS a
	INNER JOIN {$from_prefix}message AS m ON (m.id = a.id);
---*