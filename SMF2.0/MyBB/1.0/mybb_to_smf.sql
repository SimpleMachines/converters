/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "MyBulletinBoard 1.0"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/inc/config.php"
---~ globals: config
---~ from_prefix: "`{$config['database']}`.{$config['table_prefix']}"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	uid AS id_member, SUBSTRING(username, 1, 255) AS member_name,
	SUBSTRING(username, 1, 255) AS real_name,
	SUBSTRING(password, 1, 64) AS passwd, email AS email_address,
	postnum AS posts, SUBSTRING(usertitle, 1, 255) AS usertitle,
	lastvisit AS last_login, IF(usergroup = 4, 1, 0) AS id_group,
	regdate AS date_registered, SUBSTRING(website, 1, 255) AS website_url,
	SUBSTRING(website, 1, 255) AS website_title,
	SUBSTRING(icq, 1, 255) AS icq, SUBSTRING(aim, 1, 16) AS aim,
	SUBSTRING(yahoo, 1, 32) AS yim, SUBSTRING(msn AS msn, 1, 255) AS msn,
	SUBSTRING(signature, 1, 65534) AS signature, hideemail AS hide_email,
	SUBSTRING(buddylist, 1, 255) AS buddy_list,
	SUBSTRING(regip, 1, 255) AS member_ip,
	SUBSTRING(regip, 1, 255) AS member_ip2,
	SUBSTRING(ignorelist, 1, 255) AS pm_ignore_list,
	timeonline AS total_time_logged_in,
	IF(birthday = '', '0001-01-01', CONCAT_WS('-', RIGHT(birthday, 4), SUBSTRING(birthday, LOCATE('-', birthday) + 1, LOCATE('-', birthday, LOCATE('-', birthday) + 1) - LOCATE('-', birthday) - 1), SUBSTRING(birthday, 0, LOCATE('-', birthday) - 1))) AS birthdate
FROM {$from_prefix}users;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT fid AS id_cat, SUBSTRING(name, 1, 255) AS name, disporder AS cat_order
FROM {$from_prefix}forums
WHERE type = 'c';
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile >;

/* The converter will set id_cat for us based on id_parent being wrong. */
---* {$to_prefix}boards
SELECT
	fid AS id_board, SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, disporder AS board_order,
	posts AS num_posts, threads AS num_topics, pid AS id_parent,
	usepostcounts != 'yes' AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}forums
WHERE type = 'f';
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
	t.tid AS id_topic, t.fid AS id_board, t.sticky AS is_sticky,
	t.poll AS id_poll, t.views AS num_views, t.uid AS id_member_started,
	ul.uid AS id_member_updated, t.replies AS num_replies, t.closed AS locked,
	MIN(p.pid) AS id_first_msg, MAX(p.pid) AS id_last_msg
FROM {$from_prefix}threads AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.tid = t.tid)
	LEFT JOIN {$from_prefix}users AS ul ON (ul.username = t.lastposter)
GROUP BY t.tid
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
	p.pid AS id_msg, p.tid AS id_topic, t.fid AS id_board, p.uid AS id_member,
	SUBSTRING(p.username, 1, 255) AS poster_name, p.dateline AS poster_time,
	SUBSTRING(p.ipaddress, 1, 255) AS poster_ip,
	SUBSTRING(IF(p.subject = '', t.subject, p.subject), 1, 255) AS subject,
	SUBSTRING(u.email, 1, 255) AS poster_email,
	p.smilieoff = 'no' AS smileys_enabled,
	SUBSTRING(edit_u.username, 1, 255) AS modified_name,
	p.edittime AS modified_time,
	SUBSTRING(REPLACE(p.message, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}threads AS t ON (t.tid = p.tid)
	LEFT JOIN {$from_prefix}users AS u ON (u.uid = p.uid)
	LEFT JOIN {$from_prefix}users AS edit_u ON (edit_u.uid = p.edituid);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pid AS id_poll, SUBSTRING(p.question, 1, 255), p.closed AS voting_locked,
	t.uid AS id_member,
	IF(p.timeout = 0, 0, p.dateline + p.timeout * 86400) AS expire_time,
	SUBSTRING(t.username, 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	LEFT JOIN {$from_prefix}threads AS t ON (t.tid = p.tid);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$options = explode('||~|~||', $row['options']);
$votes = explode('||~|~||', $row['votes']);

$id_poll = $row['id_poll'];
for ($i = 0, $n = count($options); $i < $n; $i++)
{
	$rows[] = array(
		'id_poll' => $id_poll,
		'id_choice' => ($i + 1),
		'label' => substr('" . addslashes($options[$i]) . "', 1, 255),
		'votes' => @$votes[$i],
	);
}
---}
SELECT pid AS id_poll, options, votes
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pid AS id_poll, uid AS id_member, voteoption AS id_choice
FROM {$from_prefix}pollvotes;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.pmid AS id_pm, pm.fromid AS id_member_from, pm.dateline AS msgtime,
	SUBSTRING(uf.username, 1, 255) AS from_name,
	SUBSTRING(pm.subject, 1, 255) AS subject,
	SUBSTRING(REPLACE(pm.message, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}privatemessages AS pm
	LEFT JOIN {$from_prefix}users AS uf ON (uf.uid = pm.fromid)
WHERE pm.folder != 2;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT pmid AS id_pm, toid AS id_member, readtime != 0 AS is_read, '-1' AS labels
FROM {$from_prefix}privatemessages
WHERE folder != 2;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT uid AS id_member, tid AS id_topic
FROM {$from_prefix}favorites;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT uid AS id_member, fid AS id_board
FROM {$from_prefix}forumsubscriptions;
---*

/******************************************************************************/
--- Converting censored words...
/******************************************************************************/

DELETE FROM {$to_prefix}settings
WHERE variable IN ('censor_vulgar', 'censor_proper');

---# Moving censored words...
---{
$result = convert_query("
	SELECT badword, replacement
	FROM {$from_prefix}badwords");
$censor_vulgar = array();
$censor_proper = array();
while ($row = convert_fetch_assoc($result))
{
	$censor_vulgar[] = $row['badword'];
	$censor_proper[] = $row['replacement'];
}
convert_free_result($result);

$censored_vulgar = addslashes(implode("\n", $censor_vulgar));
$censored_proper = addslashes(implode("\n", $censor_proper));

convert_insert('settings', array('variable', 'value'),
	array(
		array('censor_vulgar', $censored_vulgar)
		array('censor_proper', $censored_proper)
	), 'replace');
---}
---#

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT uid AS id_member, fid AS id_board
FROM {$from_prefix}moderators;
---*

/******************************************************************************/
--- Converting topic view logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_topics;

---* {$to_prefix}log_topics
SELECT tid AS id_topic, uid AS id_member, dateline AS log_time
FROM {$from_prefix}threadsread;
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

fwrite($fp, $row['filedata']);
fclose($fp);

$rows[] = array(
	'id_attach' => $id_attach,
	'size' => $row['filesize'],
	'filename' => $row['filename'],
	'file_hash' => $file_hash,
	'id_msg' => $row['id_msg'],
	'downloads' => $row['downloads'],
);
$id_attach++;
---}
SELECT pid AS id_msg, filedata, downloads, filename, filesize
FROM {$from_prefix}attachments;
---*