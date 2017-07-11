/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Simpleboard 1.0 and 1.1"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/configuration.php", "../../configuration.php", "../../../configuration.php"
---~ from_prefix: "`$mosConfig_db`.$mosConfig_dbprefix"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	m.id AS id_member, SUBSTRING(m.username, 1, 80) AS member_name,
	SUBSTRING(m.name, 1, 255) AS real_name,
	SUBSTRING(sb.signature, 1, 65534) AS signature, sb.posts,
	SUBSTRING(SUBSTRING_INDEX(m.password, ':', 1), 1, 64) AS passwd, SUBSTRING_INDEX(m.password, ':', -1) AS password_salt,
	sb.karma AS karma_good,
	SUBSTRING(m.email, 1, 255) AS email_address,
	SUBSTRING(cd.country, 1, 255) AS location,
	IF(m.activation = 1, 0, 1) AS is_activated,
	UNIX_TIMESTAMP(m.registerDate) AS date_registered,
	UNIX_TIMESTAMP(m.lastvisitDate) AS last_login,
	IF(cd.params LIKE '%email=0%', 1, 0) AS hide_email,
	IF(m.usertype = 'superadministrator' OR m.usertype = 'administrator', 1, 0) AS id_group,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS website_title, '' AS website_url, '' AS icq,
	'' AS aim, '' AS yim, '' AS msn, '' AS time_format, '' AS avatar,
	'' AS usertitle, '' AS member_ip, '' AS secret_question, '' AS secret_answer,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set,
	'' AS member_ip2
FROM {$from_prefix}users AS m
	LEFT JOIN {$from_prefix}sb_users AS sb ON (sb.userid = m.id)
	LEFT JOIN {$from_prefix}contact_details AS cd ON (cd.user_id = m.id);
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id AS id_cat, SUBSTRING(name, 1, 255) AS name, ordering AS cat_order
FROM {$from_prefix}sb_categories
WHERE parent = 0;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	id AS id_board, parent AS id_cat, ordering AS board_order,
	SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, '-1,0' AS member_groups
FROM {$from_prefix}sb_categories
WHERE parent != 0;
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
	t.id AS id_topic, t.catid AS id_board, t.ordering AS is_sticky, t.locked,
	t.hits AS num_views, t.userid AS id_member_started,
	MIN(m.id) AS id_first_msg, MAX(m.id) AS id_last_msg
FROM {$from_prefix}sb_messages AS t
	INNER JOIN {$from_prefix}sb_messages AS m ON (m.thread = t.id)
WHERE t.parent = 0
GROUP BY t.id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, m.userid AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}sb_messages AS m ON (m.thread = t.id_last_msg);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace('~\[file name=.+?\]http.+?\[/file\]~i', '', $row['body']);
$row['body'] = preg_replace('~\[img size=(\d+)\]~i', '[img width=$1]', $row['body']);
---}
SELECT
	m.id AS id_msg, m.thread AS id_topic, m.time AS poster_time,
	SUBSTRING(m.subject, 1, 255) AS subject, m.userid AS id_member,
	SUBSTRING(m.name, 1, 255) AS poster_name,
	SUBSTRING(m.email, 1, 255) AS poster_email,
	SUBSTRING(m.ip, 1, 255) AS poster_ip, m.catid AS id_board,
	SUBSTRING(mt.message, 1, 65534) AS body, '' AS modified_name, 'xx' AS icon
FROM {$from_prefix}sb_messages AS m
	INNER JOIN {$from_prefix}sb_messages_text AS mt ON (mt.mesid = m.id);
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT DISTINCTROW userid AS id_member, thread AS id_topic
FROM {$from_prefix}sb_subscriptions;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT catid AS id_board, userid AS id_member
FROM {$from_prefix}sb_moderation;
---*

/******************************************************************************/
--- Clearing unused tables...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;
TRUNCATE {$to_prefix}pm_recipients;
TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

UPDATE {$to_prefix}smileys
SET hidden = 1;

---{
$specificSmileys = array(
	':cool:' => 'cool',
	':(' => 'sad',
	':confused:' => 'huh',
	':mad:' => 'angry',
	':rolleyes:' => 'rolleyes',
	':eek:' => 'shocked',
	':p' => 'tongue',
	':redface:' => 'embarassed',
	':wink:' => 'wink',
	':biggrin:' => 'grin',
	':smilie:' => 'smiley',
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
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getLegacyAttachmentFilename(basename($row['filelocation']), $id_attach);
if (copy($row['filelocation'], $attachmentUploadDir . '/' . $physical_filename))
{
	@touch($attachmentUploadDir . '/' . $physical_filename, filemtime($row['filelocation']));
		$rows[] = array(
			'id_attach' => $id_attach,
			'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
			'filename' => basename($row['filelocation']),
			'file_hash' => $file_hash,
			'id_msg' => $row['id_msg'],
			'downloads' => 0,
		);

	$id_attach++;
}
---}
SELECT mesid AS id_msg, filelocation
FROM {$from_prefix}sb_attachments;
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = 'avatar_' . $row['id_member'] . strrchr($row['filename'], '.');
if (copy($_POST['path_from'] . '/components/com_simpleboard/avatars/', $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_member' => $row['id_member'],
	);
	$id_attach++;
}
---}
SELECT userid AS id_member, avatar AS filename
FROM {$from_prefix}sb_users
WHERE avatar != ''
	AND LOCATE('/', avatar) = 0;
---*