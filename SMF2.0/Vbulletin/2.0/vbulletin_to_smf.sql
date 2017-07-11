/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "vBulletin 2"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/admin/config.php", "/includes/config.php"
---~ from_prefix: "`$dbname`."
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	userid AS id_member, SUBSTRING(username, 1, 80) AS member_name,
	joindate AS date_registered, posts, SUBSTRING(username, 1, 255) AS real_name,
	SUBSTRING(password, 1, 64) AS passwd,
	SUBSTRING(email, 1, 255) AS email_address,
	IF(usergroupid = 6, 1, IF(usergroupid = 5 OR usergroupid = 7, 2, 0)) AS id_group,
	lastvisit AS last_login, SUBSTRING(customtitle, 1, 255) AS personal_text,
	birthday AS birthdate, SUBSTRING(homepage, 1, 255) AS website_url,
	SUBSTRING(homepage, 1, 255) AS website_title,
	SUBSTRING(usertitle, 1, 255) AS usertitle, SUBSTRING(icq, 1, 255) AS icq,
	SUBSTRING(aim, 1, 16) AS aim, SUBSTRING(yahoo, 1, 32) AS yim,
	emailonpm AS pm_email_notify,
	IF(showemail = 0, 1, 0) AS hide_email, IF(invisible = 1, 0, 1) AS show_online,
	SUBSTRING(signature, 1, 65534) AS signature,
	emailnotification AS notify_announcements, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS location, '' AS msn,
	'' AS time_format, '' AS avatar, '' AS member_ip, '' AS secret_question,
	'' AS secret_answer, '' AS validation_code, '' AS additional_groups,
	'' AS smiley_set, '' AS password_salt, '' AS member_ip2
FROM {$from_prefix}user
WHERE userid != 0;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	forumid AS id_cat, SUBSTRING(title, 1, 255) AS name,
	displayorder AS cat_order
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
	forumid AS id_board, SUBSTRING(title, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description,
	displayorder AS board_order, replycount AS num_posts,
	threadcount AS num_topics, parentid AS id_parent,
	countposts = 0 AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}forum
WHERE parentid != -1;
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
	t.threadid AS id_topic, t.forumid AS id_board, t.sticky AS is_sticky,
	t.pollid AS id_poll, t.views AS num_views, t.postuserid AS id_member_started,
	ul.userid AS id_member_updated, t.replycount AS num_replies,
	IF(t.open, 0, 1) AS locked, MIN(p.postid) AS id_first_msg,
	MAX(p.postid) AS id_last_msg
FROM {$from_prefix}thread AS t
	INNER JOIN {$from_prefix}post AS p ON (p.threadid = t.threadid)
	LEFT JOIN {$from_prefix}user AS ul ON (ul.username = t.lastposter)
GROUP BY t.threadid
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
$row['body'] = preg_replace('~\[(quote)=([^\]]+)\]~i', '[$1=&quot;$2&quot;]', strtr($row['body'], array('"' => '&quot;')));
$row['body'] = preg_replace('~\[(url|email)=&quot;(.+?)&quot;\]~i', '[$1=$2]', $row['body']);
---}
SELECT
	p.postid AS id_msg, p.threadid AS id_topic, t.forumid AS id_board,
	p.dateline AS poster_time, p.userid AS id_member,
	SUBSTRING(p.ipaddress, 1, 255) AS poster_ip,
	SUBSTRING(IF(p.title = '', t.title, p.title), 1, 255) AS subject,
	SUBSTRING(u.email, 1, 255) AS poster_email,
	SUBSTRING(p.username, 1, 255) AS poster_name,
	p.allowsmilie AS smileys_enabled, p.editdate AS modified_time,
	SUBSTRING(edit_u.username, 1, 255) AS modified_name,
	SUBSTRING(REPLACE(p.pagetext, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}post AS p
	INNER JOIN {$from_prefix}thread AS t ON (t.threadid = p.threadid)
	LEFT JOIN {$from_prefix}user AS u ON (u.userid = p.userid)
	LEFT JOIN {$from_prefix}user AS edit_u ON (edit_u.userid = p.edituserid);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pollid AS id_poll, SUBSTRING(p.question, 1, 255) AS question,
	IF(p.active = 0, 1, 0) AS voting_locked,
	IF(p.timeout = 0, 0, p.dateline + p.timeout * 86400) AS expire_time,
	t.postuserid AS id_member, SUBSTRING(t.postusername, 1, 255) AS poster_name
FROM {$from_prefix}poll AS p
	LEFT JOIN {$from_prefix}thread AS t ON (t.pollid = p.pollid);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$options = explode('|||', $row['options']);
$votes = explode('|||', $row['votes']);
$id_poll = $row['id_poll'];
for ($i = 0, $n = count($options); $i < $n; $i++)
{
	$rows[] = array(
		'id_poll' => $id_poll,
		'id_choice' => ($i + 1),
		'label' => substr(addslashes($options[$i]), 1, 255),
		'votes' => @$votes[$i],
	);
}
---}
SELECT pollid AS id_poll, options, votes
FROM {$from_prefix}poll;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pollid AS id_poll, userid AS id_member, voteoption AS id_choice
FROM {$from_prefix}pollvote;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace('~\[(quote)=([^\]]+)\]~i', '[$1=&quot;$2&quot;]', $row['body']);
---}
SELECT
	pm.privatemessageid AS id_pm, pm.fromuserid AS id_member_from,
	pm.dateline AS msgtime, SUBSTRING(uf.username, 1, 255) AS from_name,
	SUBSTRING(pm.title, 1, 255) AS subject,
	SUBSTRING(REPLACE(pm.message, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}privatemessage AS pm
	LEFT JOIN {$from_prefix}user AS uf ON (uf.userid = pm.fromuserid)
WHERE pm.folderid != 'sent';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	privatemessageid AS id_pm, touserid AS id_member,
	messageread = 1 AS is_read, '-1' AS labels
FROM {$from_prefix}privatemessage
WHERE folderid != 'sent';
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT userid AS id_member, threadid AS id_topic
FROM {$from_prefix}subscribethread;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT userid AS id_member, forumid AS id_board
FROM {$from_prefix}subscribeforum;
---*

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
	':o' => 'embarrassed',
	';)' => 'wink',
	':D' => 'grin',
	':)' => 'smiley',
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

$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

fwrite($fp, $row['filedata']);
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
SELECT p.postid AS id_msg, a.filedata, a.counter AS downloads, a.filename
FROM {$from_prefix}attachment AS a
	INNER JOIN {$from_prefix}post AS p ON (p.attachmentid = a.attachmentid);
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

// !!! This can't be right!
$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

fwrite($fp, $row['avatardata']);
fclose($fp);

$rows[] = array(
	'id_attach' => $id_attach,
	'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
	'filename' => $row['filename'],
	'file_hash' => $file_hash,
	'id_member' => $row['id_member'],
);
$id_attach++;

// !!! Break this out?
convert_query("
	UPDATE {$to_prefix}members
	SET avatar = ''
	WHERE id_member = $row[id_member]
	LIMIT 1");
---}
SELECT userid AS id_member, avatardata, filename
FROM {$from_prefix}customavatar;
---*