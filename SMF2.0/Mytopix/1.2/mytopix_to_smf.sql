/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "MyTopix 1.2.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config/settings.php"
---~ from_prefix: "`{$config['db_name']}`.{$config['db_pref']}"
---~ table_test: "{$from_prefix}members"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	members_id AS id_member, SUBSTRING(members_name, 1, 255) AS member_name,
	SUBSTRING(members_ip, 1, 255) AS member_ip,
	SUBSTRING(members_ip, 1, 255) AS member_ip2,
	SUBSTRING(members_name, 1, 255) AS real_name,
	SUBSTRING(members_pass, 1, 64) AS passwd, members_posts AS posts,
	SUBSTRING(members_pass_salt, 1, 5) AS password_salt,
	SUBSTRING(members_email, 1, 255) AS email_address,
	SUBSTRING(members_homepage, 1, 255) AS website_url,
	SUBSTRING(members_homepage, 1, 255) AS website_title,
	members_registered AS date_registered, members_lastaction AS last_login,
	IF(members_is_admin, 1, IF(members_is_super_mod, 2, 0)) AS id_group,
	members_show_email = 0 AS hide_email,
	SUBSTRING(members_location, 1, 255) AS location,
	SUBSTRING(members_aim, 1, 16) AS aim,
	SUBSTRING(members_icq, 1, 255) AS icq,
	SUBSTRING(members_yim, 1, 32) AS yim,
	SUBSTRING(members_msn, 1, 255) AS msn,
	members_noteNotify AS pm_email_notify,
	SUBSTRING(REPLACE(REPLACE(members_sig, '\r', ''), '\n', '<br />'), 1, 65534) AS signature,
	SUBSTRING(IF(members_avatar_type = 2, members_avatar_location, ''), 1, 255) AS avatar,
	CONCAT_WS('-', members_birth_year, members_birth_month, members_birth_day) AS birthdate,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS usertitle,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set
	/* // !!! members_avatar_type: 1 = gallery, 3 = upload */
FROM {$from_prefix}members
WHERE members_pass != '';
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	forum_id AS id_cat, SUBSTRING(forum_name, 1, 255) AS name,
	forum_position AS cat_order
FROM {$from_prefix}forums
WHERE forum_parent = 0;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	forum_id AS id_board, forum_parent AS id_parent,
	SUBSTRING(forum_name, 1, 255) AS name,
	SUBSTRING(forum_description, 1, 65534) AS description,
	forum_topics AS num_topics, forum_posts AS num_posts,
	forum_position AS board_order, forum_enable_post_counts = 0 AS count_posts,
	'-1,0' AS member_groups
FROM {$from_prefix}forums
WHERE forum_parent != 0;
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
	t.topics_id AS id_topic, t.topics_forum AS id_board,
	IF(t.topics_author = 1, 0, t.topics_author) AS id_member_started,
	IF(t.topics_last_poster = 1, 0, t.topics_last_poster) AS id_member_updated,
	t.topics_views AS num_views, t.topics_state = 0 AS locked,
	IF(t.topics_is_poll = 1, pl.poll_id, 0) AS id_poll,
	t.topics_pinned AS is_sticky, MIN(p.posts_id) AS id_first_msg,
	MAX(p.posts_id) AS id_last_msg
FROM {$from_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.posts_topic = t.topics_id)
	LEFT JOIN {$from_prefix}polls AS pl ON (pl.poll_topic = t.topics_id)
WHERE t.topics_moved = 0
GROUP BY t.topics_id
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
	p.posts_id AS id_msg, p.posts_topic AS id_topic,
	SUBSTRING(p.posts_ip, 1, 255) AS poster_ip,
	IF(p.posts_author = 1, 0, p.posts_author) AS id_member,
	p.posts_date AS poster_time, p.posts_emoticons AS smileys_enabled,
	SUBSTRING(REPLACE(REPLACE(p.posts_body, '\r', ''), '\n', '<br />'), 1, 65534) AS body,
	SUBSTRING(t.topics_title, 1, 255) AS subject,
	SUBSTRING(p.posts_author_name, 1, 255) AS poster_name,
	SUBSTRING(mem.members_email, 1, 255) AS poster_email,
	t.topics_forum AS id_board, '' AS modified_name, 'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}topics AS t ON (t.topics_id = p.posts_topic)
	LEFT JOIN {$from_prefix}members AS mem ON (mem.members_id = p.posts_author);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.poll_id AS id_poll, SUBSTRING(p.poll_question, 1, 255) AS question,
	p.poll_end_date AS expire_time, p.poll_vote_lock AS voting_locked,
	IF(t.topics_author = 1, 0, t.topics_author) AS id_member,
	SUBSTRING(t.topics_author_name, 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	LEFT JOIN {$from_prefix}topics AS t ON (t.topics_id = p.poll_topic);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$choices = @unserialize($row['choices']);

if (is_array($choices))
	foreach ($choices as $choice)
	{
		$choice = addslashes_recursive($choice);
		$rows[] = "$row[id_poll], $choice[id], SUBSTRING('$choice[choice]', 1, 255), $choice[votes]";
	}
---}
SELECT poll_id AS id_poll, REPLACE(poll_choices, '\r', '') AS choices
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT p.poll_id AS id_poll, v.vote_user AS id_member
FROM {$from_prefix}voters AS v
	INNER JOIN {$from_prefix}polls AS p ON (v.vote_topic = p.poll_topic);
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	n.notes_id AS id_pm, n.notes_date AS msgtime,
	SUBSTRING(n.notes_title, 1, 255) AS subject,
	n.notes_sender AS id_member_from,
	SUBSTRING(memf.members_name, 1, 255) AS from_name,
	SUBSTRING(REPLACE(REPLACE(n.notes_body, '\r', ''), '\n', '<br />'), 1, 65534) AS body
FROM {$from_prefix}notes AS n
	LEFT JOIN {$from_prefix}members AS memf ON (memf.members_id = n.notes_sender);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	notes_id AS id_pm, notes_recipient AS id_member, notes_isRead AS is_read,
	'-1' AS labels
FROM {$from_prefix}notes;
---*

/******************************************************************************/
--- Converting notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT
	track_user AS id_member, track_topic AS id_topic, track_forum AS id_board,
	track_sent AS sent
FROM {$from_prefix}tracker;
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

if (copy($_POST['path_from'] . '/uploads/attachments/' . $row['old_encrypt'] . '.' . $row['ext'], $attachmentUploadDir . '/' . $physical_filename))
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
	upload_post AS id_msg, upload_name AS filename, upload_file AS old_encrypt,
	upload_size AS size, upload_ext AS ext, upload_hits AS downloads
FROM {$from_prefix}uploads;
---*