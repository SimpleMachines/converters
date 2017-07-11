/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "FUDforum 2.6.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/GLOBALS.php"
---~ globals: MSG_STORE_DIR
---~ from_prefix: "`$DBHOST_DBNAME`.$DBHOST_TBL_PREFIX"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
// Try to pull out the actual URL...
if (!empty($row['avatar']) && preg_match('~<img\ssrc="(.+?)"\s~', $row['avatar'], $matches) != 0 && !empty($matches[1]))
	$row['avatar'] = $matches[1];
else
	$row['avatar'] = '';
---}
SELECT
	id AS id_member, SUBSTRING(login, 1, 80) AS member_name,
	SUBSTRING(alias, 1, 255) AS real_name, SUBSTRING(passwd, 1, 64) AS passwd,
	SUBSTRING(email, 1, 255) AS email_address,
	SUBSTRING(location, 1, 255) AS location, SUBSTRING(icq, 1, 255) AS icq,
	SUBSTRING(aim, 1, 16) AS aim, SUBSTRING(yahoo, 1, 32) AS yim,
	SUBSTRING(msnm, 1, 255) AS msn, bday AS birthdate,
	join_date AS date_registered, posted_msg_count AS posts,
	IF(users_opt & 1048576 = 0, 0, 1) AS id_group, last_visit AS last_login,
	SUBSTRING(home_page, 1, 255) AS website_url,
	SUBSTRING(home_page, 1, 255) AS website_title,
	INET_NTOA(reg_ip) AS member_ip, INET_NTOA(reg_ip) AS member_ip2,
	SUBSTRING(avatar_loc, 1, 255) AS avatar,
	SUBSTRING(REPLACE(sig, "\n", ""), 1, 65534) AS signature, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS usertitle,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt
FROM {$from_prefix}users
WHERE passwd != '1';
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id AS id_cat, SUBSTRING(name, 1, 255) AS name, view_order AS cat_order
FROM {$from_prefix}cat;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	id AS id_board, cat_id AS id_cat, SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(descr, 1, 65534) AS description, thread_count AS num_topics,
	post_count AS num_posts, view_order AS board_order, '-1,0' AS member_groups
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
	id AS id_topic, forum_id AS id_board, replies AS num_replies,
	views AS num_views, IF(thread_opt & 4, 1, 0) AS is_sticky,
	thread_opt & 1 AS locked, root_msg_id AS id_first_msg,
	last_post_id AS id_last_msg
FROM {$from_prefix}thread
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, m.poster_id AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}msg AS m ON (m.id = t.id_last_msg);
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, m.poster_id AS id_member_started
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}msg AS m ON (m.id = t.id_first_msg);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
// This is the most annoying system ever!!
if (!file_exists($GLOBALS['MSG_STORE_DIR'] . 'msg_' . $row['file_id']))
	continue;

$fp = fopen($GLOBALS['MSG_STORE_DIR'] . 'msg_' . $row['file_id'], 'rb');
fseek($fp, $row['foff']);

$row['body'] = substr(strtr(fread($fp, $row['length']), array("\n" => '')), 0, 65534);

fclose($fp);

// Clean up...
unset($row['file_id'], $row['foff'], $row['length']);
---}
SELECT
	m.id AS id_msg, m.thread_id AS id_topic, t.forum_id AS id_board,
	m.post_stamp AS poster_time, m.poster_id AS id_member,
	SUBSTRING(m.subject, 1, 255) AS subject,
	SUBSTRING(IFNULL(u.alias, 'Guest'), 1, 255) AS poster_name,
	SUBSTRING(m.ip_addr, 1, 255) AS poster_ip,
	SUBSTRING(IFNULL(u.email, ''), 1, 255) AS poster_email,
	m.msg_opt & 2 != 0 AS smileys_enabled,
	m.file_id, m.foff, m.length, '' AS modified_name, 'xx' AS icon
FROM {$from_prefix}msg AS m
	INNER JOIN {$from_prefix}thread AS t ON (t.id = m.thread_id)
	LEFT JOIN {$from_prefix}users AS u ON (u.id = m.poster_id);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.id AS id_poll, SUBSTRING(p.name, 1, 255) AS question,
	p.owner AS id_member,
	SUBSTRING(IFNULL(u.alias, 'Guest'), 1, 255) AS poster_name,
	p.max_votes AS max_votes, p.creation_date + p.expiry_date AS expire_time
FROM {$from_prefix}poll AS p
	LEFT JOIN {$from_prefix}users AS u ON (u.id = p.owner);
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, m.poll_id AS id_poll
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}msg AS m ON (m.id = t.id_first_msg)
	AND m.poll_id != 0;
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

/* We need this, unfortunately, for the log_polls table. */
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
if (!isset($_SESSION['id_choice']))
	$_SESSION['id_choice'] = 1;

// Last poll id?
if (!isset($_SESSION['last_poll_id']))
	$_SESSION['last_poll_id'] = $row['id_poll'];
// New poll - reset choice count!
elseif ($_SESSION['last_poll_id'] != $row['id_poll'])
{
	$_SESSION['id_choice'] = 1;
	$_SESSION['last_poll_id'] = $row['id_poll'];
}
else
	$_SESSION['id_choice']++;

$row['id_choice'] = $_SESSION['id_choice'];
---}
SELECT
	id AS temp_id, poll_id AS id_poll, 1 AS id_choice,
	SUBSTRING(name, 1, 255) AS label, `count` AS votes
FROM {$from_prefix}poll_opt;
---*

/******************************************************************************/
--- Converting poll logs...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT
	pot.poll_id AS id_poll, pot.user_id AS id_member,
	pc.id_choice AS id_choice
FROM {$from_prefix}poll_opt_track AS pot
	INNER JOIN {$to_prefix}poll_choices AS pc ON (pc.temp_id = pot.poll_opt);
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
// More of this crap!
if (!file_exists($GLOBALS['MSG_STORE_DIR'] . 'private'))
	continue;

$fp = fopen($GLOBALS['MSG_STORE_DIR'] . 'private', 'rb');
fseek($fp, $row['foff']);

$row['body'] = substr(strtr(fread($fp, $row['length']), array("\n" => '')), 0, 65534);

fclose($fp);

// Clean up...
unset($row['foff'], $row['length']);
---}
SELECT
	pm.id AS id_pm, pm.ouser_id AS id_member_from, pm.post_stamp AS msgtime,
	SUBSTRING(IFNULL(uf.alias, 'Guest'), 1, 255) AS from_name,
	SUBSTRING(pm.subject, 1, 255) AS subject, pm.foff, pm.length
FROM {$from_prefix}pmsg AS pm
	LEFT JOIN {$from_prefix}users AS uf ON (uf.id = pm.ouser_id)
WHERE pm.fldr != 3;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	id AS id_pm, duser_id AS id_member, read_stamp != 0 AS is_read,
	'-1' AS labels
FROM {$from_prefix}pmsg
WHERE fldr != 3;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT user_id AS id_member, thread_id AS id_board
FROM {$from_prefix}thread_notify;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT user_id AS id_member, forum_id AS id_board
FROM {$from_prefix}forum_notify;
---*

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

UPDATE {$to_prefix}smileys
SET hidden = 1;

---{
$specificSmileys = array(
	':)' => 'smiley',
	':-)' => 'smiley',
	'=)' => 'smiley',
	':|' => 'undecided',
	':-|' => 'undecided',
	':neutral:' => 'undecided',
	':(' => 'sad',
	':-(' => 'sad',
	':sad:' => 'sad',
	':]' => 'grin',
	':-]' => 'grin',
	':brgin:' => 'grin',
	'8o' => 'shocked',
	'8-o' => 'shocked',
	':shock:' => 'shocked',
	':o' => 'shocked',
	':-o' => 'shocked',
	':eek:' => 'shocked',
	';)' => 'wink',
	':wink:' => 'wink',
	';-)' => 'wink',
	';/' => 'rolleyes',
	':p' => 'tongue',
	':-p' => 'tongue',
	':razz:' => 'tongue',
	':lol:' => 'cheesy',
	':rolleyes:' => 'rolleyes',
	'8)' => 'cool',
	'8-)' => 'cool',
	':cool:' => 'cool',
	':x' => 'angry',
	':-x' => 'angry',
	':mad:' => 'angry',
	':blush:' => 'embarrassed',
	':?' => 'huh',
	':-?' => 'huh',
	':???:' => 'huh',
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

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($row['location'], $attachmentUploadDir . '/' . $physical_filename))
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
	message_id AS id_msg, location, dlcount AS downloads,
	original_name AS filename, fsize AS size
FROM {$from_prefix}attach;
---*