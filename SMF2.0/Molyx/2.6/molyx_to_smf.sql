/* ATTENTION: You don't need to run or use this file!  The converphp script does everything for you! */

/******************************************************************************/
---~ name: "Molyx 2.6"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/includes/config.php"
---~ globals: config
---~ from_prefix: "`{$config['dbname']}`.{$config['tableprefix']}"
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
ALTER TABLE {$to_prefix}members
CHANGE COLUMN password_salt password_salt varchar(255) NOT NULL default '';

---* {$to_prefix}members
SELECT
	id AS id_member, SUBSTRING(name, 1, 255) AS member_name,
	SUBSTRING(name, 1, 255) AS real_name, email AS email_address,
	SUBSTRING(password, 1, 64) AS passwd, SUBSTRING(salt, 1, 5) AS password_salt,
	posts AS posts, SUBSTRING(customtitle, 1, 255) AS usertitle,
	lastvisit AS last_login, IF(usergroupid = 4, 1, 0) AS id_group,
	joindate AS date_registered, SUBSTRING(website, 1, 255) AS website_url,
	SUBSTRING(website, 1, 255) AS website_title,
	SUBSTRING(icq, 1, 255) AS icq, SUBSTRING(aim, 1, 16) AS aim,
	SUBSTRING(yahoo, 1, 32) AS yim, SUBSTRING(msn, 1, 255) AS msn,
	SUBSTRING(signature, 1, 65534) AS signature, 1 AS hide_email,
	SUBSTRING(host, 1, 255) AS member_ip, SUBSTRING(host, 1, 255) AS member_ip2,
	CASE
		WHEN birthday = '' THEN '0001-01-01'
		ELSE CONCAT_WS('-', RIGHT(birthday, 4), SUBSTRING(birthday, LOCATE('-', birthday) + 1, LOCATE('-', birthday, LOCATE('-', birthday) + 1) - LOCATE('-', birthday) - 1), LEFT(birthday, LOCATE('-', birthday) - 1))
	END AS birthdate, onlinetime AS total_time_logged_in
FROM {$from_prefix}user;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id AS id_cat, SUBSTRING(name, 1, 255) AS name, displayorder AS cat_order
FROM {$from_prefix}forum
WHERE parentid = -1;
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
	id AS id_board, SUBSTRING(name, 1, 255) AS name, parentid AS id_cat,
	SUBSTRING(description, 1, 65534) AS description, displayorder AS board_order,
	post AS num_posts, thread AS num_topics, parentid AS id_parent,
	countposts AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}forum
WHERE parentid > -1;
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
	tid AS id_topic, forumid AS id_board, sticky AS is_sticky,
	pollstate AS id_poll, views AS num_views, postuserid AS id_member_started,
	lastposterid AS id_member_updated, post AS num_replies,
	IF(open = 1, 0, 1) AS locked, firstpostid AS id_first_msg,
	lastpostid AS id_last_msg
FROM {$from_prefix}thread;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
SELECT
	p.pid AS id_msg, p.threadid AS id_topic, t.forumid AS id_board,
	p.userid AS id_member, SUBSTRING(p.username, 1, 255) AS poster_name,
	p.dateline AS poster_time, SUBSTRING(p.host, 1, 255) AS poster_ip,
	SUBSTRING(t.title, 1, 255) AS subject, SUBSTRING(u.email, 1, 255) AS poster_email,
	p.allowsmile AS smileys_enabled,
	SUBSTRING(REPLACE(p.pagetext, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}post AS p
	INNER JOIN {$from_prefix}thread AS t ON (t.tid = p.threadid)
	INNER JOIN {$from_prefix}user AS u ON (u.id = p.userid);
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.pmid AS id_pm, pm.fromuserid AS id_member_from, pm.dateline AS msgtime,
	SUBSTRING(uf.name, 1, 255) AS from_name,
	SUBSTRING(pm.title, 1, 255) AS subject,
	SUBSTRING(REPLACE(t.message, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}pm AS pm
	LEFT JOIN {$from_prefix}user AS uf ON (uf.id = pm.fromuserid)
	INNER JOIN {$from_prefix}pmtext AS t ON (pm.messageid = t.pmtextid)
WHERE pm.folderid != -1;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pmid AS id_pm, touserid AS id_member, pmread AS is_read, '-1' AS labels
FROM {$from_prefix}pm
WHERE folderid != -1;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
SELECT
	userid AS id_member, threadid AS id_topic
FROM {$from_prefix}subscribethread;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
SELECT
	userid AS id_member, forumid AS id_board
FROM {$from_prefix}subscribeforum;
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pollid AS id_poll, SUBSTRING(p.question, 1, 255) AS question, '0' AS voting_locked,
	t.postuserid AS id_member, '0' AS expire_time,
	SUBSTRING(t.postusername, 1, 255) AS poster_name
FROM {$from_prefix}poll AS p
	LEFT JOIN {$from_prefix}thread AS t ON (t.tid = p.tid);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$polloptions = unserialize($row['options']);

foreach ($polloptions as $option)
	$rows[] = $row['id_poll'] . ', ' . ($option['0'] +1) . ", SUBSTRING('" . addslashes($option['1']) . "', 1, 255), '" . $option[2] . "'";
---}
SELECT pollid AS id_poll, options, votes
FROM {$from_prefix}poll;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
---{
$no_add = true;
$keys = array('id_poll', 'id_member', 'id_choice');

$voters = explode(',', $row['voters']);

foreach ($voters as $member)
{
	if(!empty($member))
		$rows[] = $row['id_poll'] . ', ' . $member . ', ' . '1';
}
---}
SELECT
	pollid AS id_poll, voters, '1' AS id_choice
FROM {$from_prefix}poll;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT
	userid AS id_member, forumid AS id_board
FROM {$from_prefix}moderator
WHERE forumid != 0;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getLegacyAttachmentFilename(basename($row['filename']), $id_attach);
$oldfile = $_POST['path_from'] . '/data/uploads/' . $row['attachpath'] . '/' . $row['location'] ;
if (file_exists($oldfile) && copy($_POST['path_from'] . '/data/uploads/' . $row['attachpath'] . '/' . $row['location'], $attachmentUploadDir . '/' . $physical_filename))
{
	@touch($attachmentUploadDir . '/' . $physical_filename, filemtime($row['filename']));
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => basename($row['filename']),
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
	);
	$id_attach++;
}

---}
SELECT
	postid AS id_msg, location, attachpath, filename AS filename,
	counter AS downloads
FROM {$from_prefix}attachment
WHERE postid !=0;
---*