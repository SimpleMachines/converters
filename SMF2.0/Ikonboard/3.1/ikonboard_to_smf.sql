/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "IkonBoard 3.1.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ parameters: ib_database text=MySQL database used by IkonBoard
---~ parameters: ib_prefix text=Prefix used by IkonBoard
---~ parameters: ib_uploads text=Path to the uploads directory
---~ from_prefix: "`$ib_database`.$ib_prefix"
---~ table_test: "{$from_prefix}member_profiles"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

DROP TABLE IF EXISTS {$to_prefix}tmp_messages;

ALTER TABLE {$to_prefix}members
ADD COLUMN temp_id varchar(32),
ADD INDEX temp_id (temp_id(32));

CREATE TABLE IF NOT EXISTS {$to_prefix}tmp_messages (
  old_id_msg int(12) NOT NULL default '0',
  old_id_topic int(12) NOT NULL default '0',
  date int(15) NOT NULL default '0'
 );

---* {$to_prefix}members
SELECT
	SUBSTRING(MEMBER_NAME, 1, 80) AS member_name,
	IF(MEMBER_GROUP = 4, 1, 0) AS id_group,
	SUBSTRING(MEMBER_PASSWORD, 1, 64) AS passwd,
	SUBSTRING(MEMBER_EMAIL, 1, 255) AS email_address,
	MEMBER_JOINED AS date_registered, SUBSTRING(MEMBER_IP, 1, 255) AS member_ip,
	SUBSTRING(IF(MEMBER_AVATAR = 'noavatar' OR INSTR(MEMBER_AVATAR, 'upload') != 0, '', MEMBER_AVATAR), 1, 255) AS avatar,
	MEMBER_POSTS AS posts, SUBSTRING(AOLNAME, 1, 16) AS aim,
	SUBSTRING(icqNUMBER, 1, 255) AS icq,
	SUBSTRING(LOCATION, 1, 255) AS location,
	SUBSTRING(REPLACE(SIGNATURE, '<br>', '<br />'), 1, 65534) AS signature,
	SUBSTRING(WEBSITE, 1, 255) AS website_url,
	SUBSTRING(WEBSITE, 1, 255) AS website_title,
	SUBSTRING(YAHOONAME, 1, 32) AS yim,
	SUBSTRING(MEMBER_TITLE, 1, 255) AS personal_text,
	ALLOW_ADMIN_EMAILS AS notify_announcements,
	IFNULL(TIME_ADJUST, 0) AS time_offset, HIDE_EMAIL AS hide_email,
	SUBSTRING(msnNAME, 1, 255) AS msn, LAST_ACTIVITY AS last_login,
	GENDER AS gender, SUBSTRING(MEMBER_NAME, 1, 255) AS real_name,
	MEMBER_ID AS temp_id, '' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list,
	'' AS message_labels, '' AS time_format, '' AS usertitle,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt,
	SUBSTRING(MEMBER_IP, 1, 255) AS member_ip2
FROM {$from_prefix}member_profiles;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	CAT_ID AS id_cat, SUBSTRING(CAT_NAME, 1, 255) AS name, CAT_POS AS cat_order
FROM {$from_prefix}categories;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	FORUM_ID AS id_board, FORUM_TOPICS AS num_topics, FORUM_POSTS AS num_posts,
	SUBSTRING(FORUM_NAME, 1, 255) AS name,
	SUBSTRING(FORUM_DESC, 1, 65534) AS description,
	FORUM_POSITION AS board_order, CATEGORY AS id_cat, '-1,0' AS member_groups
FROM {$from_prefix}forum_info;
---*

/******************************************************************************/
--- preparing messages..
/******************************************************************************/

---* {$to_prefix}tmp_messages 500

SELECT POST_ID AS old_id_msg, POST_DATE as date, TOPIC_ID AS old_id_topic
FROM {$from_prefix}forum_posts;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

ALTER TABLE {$to_prefix}tmp_messages ORDER BY date;
ALTER TABLE {$to_prefix}tmp_messages
	ADD id_msg INT( 12 ) NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST;

ALTER TABLE {$to_prefix}tmp_messages
	ADD INDEX old_id_msg (old_id_msg);

ALTER TABLE {$to_prefix}tmp_messages
	ADD INDEX old_id_topic (old_id_topic);

---* {$to_prefix}topics
SELECT
	t.TOPIC_ID AS id_topic, t.TOPIC_STATE = 'closed' AS locked,
	t.TOPIC_POSTS AS num_replies, memf.id_member AS id_member_started,
	meml.id_member AS id_member_updated, pl.ID AS id_poll,
	t.TOPIC_VIEWS AS num_views, t.FORUM_ID AS id_board,
	t.PIN_STATE AS is_sticky, MIN(temp.id_msg) AS id_first_msg,
	MAX(temp.id_msg) AS id_last_msg
FROM {$from_prefix}forum_topics AS t
	LEFT JOIN {$to_prefix}tmp_messages AS temp ON (t.TOPIC_ID = temp.old_id_topic)
	LEFT JOIN {$from_prefix}forum_polls AS pl ON (pl.POLL_ID = t.TOPIC_ID)
	LEFT JOIN {$to_prefix}members AS memf ON (memf.temp_id = t.TOPIC_STARTER)
	LEFT JOIN {$to_prefix}members AS meml ON (meml.temp_id = t.TOPIC_LAST_POSTER)
WHERE t.MOVED_TO IS NULL
GROUP BY t.TOPIC_ID
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
	temp.id_msg AS id_msg, mem.id_member, p.ENABLE_EMO AS smileys_enabled,
	SUBSTRING(p.IP_ADDR, 1, 255) AS poster_ip, p.POST_DATE AS poster_time,
	SUBSTRING(t.TOPIC_TITLE, 1, 255) AS subject,
	SUBSTRING(REPLACE(p.POST, '<br>', '<br />'), 1, 65534) AS body,
	p.TOPIC_ID AS id_topic, p.FORUM_ID AS id_board,
	SUBSTRING(mem.member_name, 1, 255) AS poster_name,
	SUBSTRING(mem.email_address, 1, 255) AS poster_email
FROM {$to_prefix}tmp_messages AS temp
	INNER JOIN {$from_prefix}forum_posts AS p ON (p.POST_ID = temp.old_id_msg)
	LEFT JOIN {$from_prefix}forum_topics AS t ON (t.TOPIC_ID = p.TOPIC_ID)
	LEFT JOIN {$to_prefix}members AS mem ON (mem.temp_id = p.AUTHOR);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.ID AS id_poll, SUBSTRING(p.POLL_TITLE, 1, 255) AS question,
	mem.id_member, SUBSTRING(p.POLL_STARTER_N, 1, 255) AS poster_name
FROM {$from_prefix}forum_polls AS p
	LEFT JOIN {$to_prefix}members AS mem ON (mem.temp_id = p.POLL_STARTER);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

preg_match_all('/(\d+)~::~<!--\\1-->(.+?)~=~(\d+)\|/', $row['choices'], $choices);
foreach ($choices[1] as $i => $id_choice)
	$rows[] = "$row[id_poll], " . ($id_choice + 1) . ", SUBSTRING('" . addslashes($choices[2][$i]) . "', 1, 255), " . $choices[3][$i];
---}
SELECT ID AS id_poll, POLL_ANSWERS AS choices
FROM {$from_prefix}forum_polls;
---*

/******************************************************************************/
--- Converting poll logs...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pl.ID AS id_poll, mem.id_member
FROM {$from_prefix}forum_poll_voters AS v
	INNER JOIN {$from_prefix}forum_polls AS pl
	INNER JOIN {$to_prefix}members AS mem
WHERE pl.POLL_ID = v.POLL_ID
	AND mem.temp_id = v.MEMBER_ID;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.MESSAGE_ID AS id_pm, pm.DATE AS msgtime,
	SUBSTRING(pm.TITLE, 1, 255) AS subject,
	SUBSTRING(REPLACE(pm.message, '<br>', '<br />'), 1, 65534) AS body,
	SUBSTRING(pm.FROM_NAME, 1, 255) AS from_name,
	mem.id_member AS id_member_from
FROM {$from_prefix}message_data AS pm
	LEFT JOIN {$to_prefix}members AS mem ON (mem.temp_id = pm.FROM_ID)
WHERE pm.VIRTUAL_DIR = 'in';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm.MESSAGE_ID AS id_pm, mem.id_member,
	(pm.READ_STATE = 1) | (pm.REPLY << 1) AS is_read,
	'-1' AS labels
FROM {$from_prefix}message_data AS pm
	INNER JOIN {$to_prefix}members AS mem
WHERE pm.VIRTUAL_DIR = 'in'
	AND mem.temp_id = pm.RECIPIENT_ID;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT mem.id_member, s.TOPIC_ID AS id_topic, tv.SENT AS sent
FROM {$from_prefix}forum_subscriptions AS s
	INNER JOIN {$to_prefix}members AS mem
	LEFT JOIN {$from_prefix}topic_views AS tv ON (tv.TOPIC_ID = s.TOPIC_ID AND tv.MEMBER_ID = s.MEMBER_ID)
WHERE s.TOPIC_ID != 0
	AND mem.tempId = s.MEMBER_ID;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
SELECT mem.id_member, s.FORUM_ID AS id_board
FROM {$from_prefix}forum_subscriptions AS s
	INNER JOIN {$to_prefix}members AS mem
WHERE s.TOPIC_ID = 0
	AND mem.tempId = s.MEMBER_ID;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT mem.id_member, mods.FORUM_ID AS id_board
FROM {$from_prefix}forum_moderators AS mods
	INNER JOIN {$to_prefix}members AS mem
WHERE mem.temp_id = mods.MEMBER_ID;
---*

/******************************************************************************/
--- Converting topic view logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_topics;

---* {$to_prefix}log_topics
SELECT tv.TOPIC_ID AS id_topic, mem.id_member, tv.VIEWED AS log_time
FROM {$from_prefix}topic_views AS tv
	INNER JOIN {$to_prefix}members AS mem
WHERE mem.temp_id = tv.MEMBER_ID;
---*

/******************************************************************************/
--- Cleaning up...
/******************************************************************************/

ALTER TABLE {$to_prefix}members
DROP COLUMN temp_id;

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$real_filename = preg_replace('~^post-\d+-\d+-~', '', $row['filename']);
$file_hash = getLegacyAttachmentFilename($real_filename, $id_attach);
if (copy($ib_uploads . '/' . $row['filename'], $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $real_filename,
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
	);
	$id_attach++;
}
---}
SELECT
	temp.id_msg AS id_msg, p.ATTACH_ID AS old_encrypt, p.ATTACH_HITS AS downloads,
	a.FILE_NAME AS filename
FROM {$from_prefix}forum_posts AS p
INNER JOIN {$to_prefix}tmp_messages AS temp ON (temp.old_id_msg = p.POST_ID)
INNER JOIN {$from_prefix}attachments AS a ON (a.ID = p.ATTACH_ID);
---*