/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Deluxe Portal 2.0"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ from_prefix: "`$dbname`."
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---{
alterDatabase('members', 'change column', array(
	'old_name' => 'password_salt',
	'name' => 'password_salt',
	'type' => 'varchar',
	'size' => 255,
	'default' => '',
));
---}

---* {$to_prefix}members
SELECT
	userid AS id_member, SUBSTRING(name, 1, 80) AS member_name,
	SUBSTRING(name, 1, 255) AS real_name, SUBSTRING(password, 1, 64) AS passwd,
	IF(groupid = 1, 1, IF(groupid = 9, 2, 0)) AS id_group,
	posts, SUBSTRING(title, 1, 255) AS usertitle, joindate AS date_registered,
	SUBSTRING(msn, 1, 255) AS msn, SUBSTRING(email, 1, 255) AS email_address,
	SUBSTRING(location, 1, 255) AS location, invisible = 0 AS show_online,
	hide_email AS hide_email, SUBSTRING(icq, 1, 255) AS icq,
	SUBSTRING(aol, 1, 16) AS aim, SUBSTRING(yahoo, 1, 32) AS yim,
	SUBSTRING(IF(website != 'http://', website, ''), 1, 255) AS website_url,
	SUBSTRING(IF(website != 'http://', website, ''), 1, 255) AS website_title,
	SUBSTRING(signature, 1, 65534) AS signature, notify_pm AS pm_email_notify,
	lastactivity AS last_login, SUBSTRING(user_salt, 1, 5) AS password_salt,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS avatar, '' AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS member_ip2
FROM {$from_prefix}user;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT forumid AS id_cat, SUBSTRING(name, 1, 255) AS name, ordered AS cat_order
FROM {$from_prefix}forum
WHERE parentid = 0;
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
	forumid AS id_board, SUBSTRING(name, 1, 255) AS name,
	parentid AS id_parent, ordered AS board_order,
	SUBSTRING(description, 1, 65534) AS description, posts AS num_posts,
	threads AS num_topics, countposts = 0 AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}forum
WHERE parentid != 0;
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
	IF(t.poll = '', 0, t.threadid) AS id_poll, t.views AS num_views,
	t.userid AS id_member_started, t.lastuserid AS id_member_updated,
	t.posts - 1 AS num_replies, t.closed AS locked,
	MIN(p.postid) AS id_first_msg, t.lastpostid AS id_last_msg
FROM {$from_prefix}thread AS t
	INNER JOIN {$from_prefix}post AS p ON (p.threadid = t.threadid)
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
SELECT
	p.postid AS id_msg, p.threadid AS id_topic, t.forumid AS id_board,
	p.postdate AS poster_time, p.userid AS id_member,
	SUBSTRING(p.ip, 1, 255) AS poster_ip,
	SUBSTRING(IF(p.subject = '', CONCAT('Re: ', t.name), p.subject), 1, 255) AS subject,
	SUBSTRING(u.email, 1, 255) AS poster_email,
	SUBSTRING(p.username, 1, 255) AS poster_name,
	p.smilies AS smileys_enabled, p.editedby_date AS modified_time,
	SUBSTRING(IF(p.editedby_date = 0, '', p.editedby_username), 1, 255) AS modified_name,
	SUBSTRING(REPLACE(p.message, '\r', ''), 1, 65534) AS body, 'xx' AS icon
FROM {$from_prefix}post AS p
	INNER JOIN {$from_prefix}thread AS t ON (t.threadid = p.threadid)
	LEFT JOIN {$from_prefix}user AS u ON (u.userid = p.userid);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	t.threadid AS id_poll, SUBSTRING(t.poll, 1, 255) AS question,
	t.userid AS id_member, SUBSTRING(t.username, 1, 255) AS poster_name,
	p.postdate + t.poll_days * 86400 AS expire_time
	/* // !!! t.poll_multiple = 1 AS max_votes */
FROM {$from_prefix}thread AS t
	INNER JOIN {$to_prefix}topics AS t2 ON (t2.id_topic = t.threadid)
	INNER JOIN {$from_prefix}post AS p ON (p.postid = t2.id_first_msg)
WHERE t.poll != '';
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
SELECT
	threadid AS id_poll, ordered AS id_choice,
	SUBSTRING(choice, 1, 255) AS label, votes
FROM {$from_prefix}poll;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT threadid AS id_poll, userid AS id_member, choice AS id_choice
FROM {$from_prefix}whovoted;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	privatemessageid AS id_pm, sentdate AS msgtime,
	SUBSTRING(subject, 1, 255) AS subject, fromuserid AS id_member_from,
	SUBSTRING(fromusername, 1, 255) AS from_name,
	SUBSTRING(REPLACE(message, '\r', ''), 1, 65534) AS body
FROM {$from_prefix}privatemessage
WHERE folder != 'sent';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	privatemessageid AS id_pm, touserid AS id_member, isread = 1 AS is_read,
	'-1' AS label
FROM {$from_prefix}privatemessage
WHERE folder != 'sent';
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT userid AS id_member, threadid AS id_topic
FROM {$from_prefix}subscribedthread;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT userid AS id_member, forumid AS id_board
FROM {$from_prefix}subscribedforum;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT userid AS id_member, forumid AS id_board
FROM {$from_prefix}moderator;
---*

/******************************************************************************/
--- Converting topic view logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_topics;

---* {$to_prefix}log_topics
SELECT mr.threadid AS id_topic, mr.userid AS id_member, p.postdate AS log_time
FROM {$from_prefix}markread AS mr
	INNER JOIN {$from_prefix}post AS p ON (p.postid = mr.postid)
GROUP BY id_topic, id_member;
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

$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

fwrite($fp, $row['attachment']);
fclose($fp);

$rows[] = array(
	'id_attach' => $id_attach,
	'size' => $row['size'],
	'filename' => $row['filename'],
	'file_hash' => $file_hash,
	'id_msg' => $row['id_msg'],
	'downloads' => 0,
);
$id_attach++;
---}
SELECT postid AS id_msg, attachment, size, name AS filename
FROM {$from_prefix}attachment;
---*