/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "AEF 1.0.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/universal.php", "/dbtables.php"
---~ globals: $dbtables
---~ defines: AEF
---~ from_prefix: "`{$globals['database']}`."
---~ table_test: "{$from_prefix}{$dbtables['users']}"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
---* {$to_prefix}members
---{
$ignore=true;
---}
SELECT
	id AS id_member, SUBSTRING(username, 1, 80) AS member_name,
	r_time AS date_registered, posts, SUBSTRING(password, 1, 64) AS passwd,
	SUBSTRING(www, 1, 255) AS website_title,
	SUBSTRING(www, 1, 255) AS website_url, lastlogin AS last_login,
	birth_date AS birthdate, SUBSTRING(icq, 1, 255) AS icq,
	SUBSTRING(IF(realname !='', realname, username), 1, 255) AS real_name,
	SUBSTRING(email, 1, 255) AS email_address, 	language AS lngfile,
	SUBSTRING(aim, 1, 16) AS aim, SUBSTRING(users_text, 1, 255) AS personal_text,
	hideemail AS hide_email, SUBSTRING(r_ip, 1, 255) AS member_ip,
	SUBSTRING(r_ip, 1, 255) AS member_ip2,
	SUBSTRING(yim, 1, 32) AS yim, gender,
	SUBSTRING(msn, 1, 255) AS msn,
	SUBSTRING(REPLACE(sig, '<br>', '<br />'), 1, 65534) AS signature,
	SUBSTRING(location, 1, 255) AS location, timezone AS time_offset,
	SUBSTRING(avatar, 1, 255) AS avatar,
	SUBSTRING(users_text, 1, 255) AS usertitle,
	pm_email_notify AS pm_email_notify, 0 AS karma_bad, 0 AS karma_good,
	adminemail AS notify_announcements,
	'' AS secret_question,
	'' AS secret_answer,
	IF(u_member_group = 1, 1, IF(u_member_group = -3, 9, u_member_group + 10)) AS id_group, '' AS buddy_list, '' AS pm_ignore_list,
	'' AS message_labels, '' AS validation_code, '' AS additional_groups,
	'' AS smiley_set, salt AS password_salt
FROM {$from_prefix}{$dbtables['users']};
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT cid AS id_cat, SUBSTRING(name, 1, 255) AS name, `order` AS cat_order, collapsable AS can_collapse
FROM {$from_prefix}{$dbtables['categories']};
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

---* {$to_prefix}boards
SELECT
	fid AS id_board, cat_id AS id_cat, SUBSTRING(fname, 1, 255) AS name, forum_order AS board_order,
	SUBSTRING(description, 1, 65534) AS description, ntopic AS num_topics, nposts AS num_posts,
	0 AS count_posts, member_group AS member_groups,
	par_board_id AS id_parent, id_skin AS ID_THEME, override_skin AS override_theme
FROM {$from_prefix}{$dbtables['forums']};
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
	tid AS id_topic, t_bid AS id_board, t_sticky AS is_sticky, poll_id AS id_poll,
	n_views AS num_views, t_mem_id AS id_member_started, mem_id_last_post AS id_member_updated, n_posts AS num_replies, IF(t_status = 0, 1, 0) AS locked,
	first_post_id AS id_first_msg, IF(last_post_id = 0, first_post_id, last_post_id) AS id_last_msg
FROM {$from_prefix}{$dbtables['topics']};
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$ignore=true;
---}
SELECT
	p.pid AS id_msg, p.post_tid AS id_topic, p.post_fid AS id_board, p.poster_id AS id_member, p.ptime AS poster_time,
	SUBSTRING(IF(p.gposter_name = '', mem.username, gposter_name), 1, 255) AS poster_name,
	SUBSTRING(IF(p.gposter_name = '', mem.email, gposter_email), 1, 255) AS poster_email,
	SUBSTRING(p.poster_ip, 1, 255) AS poster_ip, 'xx' AS icon,
	SUBSTRING(t.topic, 1, 255) AS subject,	p.use_smileys AS smileys_enabled,
	p.modtime AS modified_time,	SUBSTRING(modmem.username, 1, 255) AS modified_name,
	SUBSTRING(REPLACE(p.post, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}{$dbtables['posts']} AS p
	INNER JOIN {$from_prefix}{$dbtables['topics']} AS t ON (t.tid = p.post_tid)
	LEFT JOIN {$from_prefix}{$dbtables['users']} AS mem ON (p.poster_id = mem.id)
	LEFT JOIN {$from_prefix}{$dbtables['users']} AS modmem ON (p.modifiers_id = modmem.id);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.poid AS id_poll, SUBSTRING(p.poll_qt, 1, 255) AS question, p.poll_locked AS voting_locked,
	p.poll_mid AS id_member, SUBSTRING(IFNULL(mem.username, 'Guest'), 1, 255) AS poster_name
FROM {$from_prefix}{$dbtables['polls']} AS p
	LEFT JOIN {$from_prefix}{$dbtables['users']} AS mem ON (mem.id = p.poll_mid);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$ignore = true;
---}
SELECT
	poo_poid AS id_poll, pooid AS id_choice, SUBSTRING(poo_option, 1, 255) AS label, poo_votes AS votes
FROM {$from_prefix}{$dbtables['poll_options']};
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pv_poid AS id_poll, pv_mid AS id_member, pv_pooid AS id_choice
FROM {$from_prefix}{$dbtables['poll_voters']};
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.pmid AS id_pm, pm.pm_from AS id_member_from, pm.pm_time AS msgtime,
	SUBSTRING(fmem.username, 1, 255) AS from_name,
	SUBSTRING(pm.pm_subject, 1, 255) AS subject,
	SUBSTRING(pm.pm_body, 1, 65534) AS body,
	0 AS deleted_by_sender
FROM {$from_prefix}{$dbtables['pm']} AS pm
	LEFT JOIN {$from_prefix}{$dbtables['users']} AS fmem ON (pm.pm_from = fmem.id);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
/* for saftey we treat all messages as read */
SELECT
	pmid AS id_pm, pm_to AS id_member, 1 AS is_read,
	0 AS deleted, '' AS labels
FROM {$from_prefix}{$dbtables['pm']};
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
/* Assume all notifications are sent or we might get mass mailings. */
SELECT
	notify_mid AS id_member, notify_tid AS id_topic, 1 AS sent
FROM {$from_prefix}{$dbtables['notify_topic']};
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
/* Assume all notifications are sent or we might get mass mailings. */
SELECT
	notify_mid AS id_member, notify_fid AS id_topic, 1 AS sent
FROM {$from_prefix}{$dbtables['notify_forum']};
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

if (!isset($yAttachmentDir))
{
	$result = convert_query("
		SELECT regval
		FROM {$from_prefix}{$dbtables['registry']}
		WHERE name = 'attachmentdir'
		LIMIT 1");
	list ($yAttachmentDir) = convert_fetch_row($result);
	convert_free_result($result);
}

if (!file_exists($yAttachmentDir))
	return;

$file_hash = getAttachmentFilename($row['filename'], 0, null, true);
$physical_filename = $row['id_attach'] . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($yAttachmentDir . '/' . $row['at_file'], $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $row['id_attach'],
		'id_msg' => $row['id_msg'],
		'id_member' => $row['id_member'],
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'size' => $row['size'],
		'downloads' => $row['downloads'],
		'width' => $row['width'],
		'height' => $row['height'],
	);
}
---}
SELECT
	atid AS id_attach, 0 AS ID_THUMB, at_pid AS id_msg, at_mid AS id_member, at_file,
	at_original_file AS filename, at_size AS size, at_downloads AS downloads, at_width AS width, at_height AS height
FROM {$from_prefix}{$dbtables['attachments']}
WHERE at_original_file IS NOT NULL
	AND at_original_file != '';
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT mod_mem_id AS id_member, mod_fid AS id_board
FROM {$from_prefix}{$dbtables['moderators']};
---*

/******************************************************************************/
--- Converting membergroups...
/******************************************************************************/

DELETE FROM {$to_prefix}permissions
WHERE id_group > 8;

DELETE FROM {$to_prefix}membergroups
WHERE id_group > 8;

---* {$to_prefix}membergroups
	/* To get around weird ids we jump a little. We skip 8 just so its easier to know where the ids went */
	SELECT
		IF(member_group = -3, 9, member_group + 10) AS id_group, mem_gr_name AS group_name,
		mem_gr_colour AS online_color, post_count AS min_posts, max_pm AS max_messages, CONCAT(image_count, '#', image_name) AS stars
	FROM {$from_prefix}{$dbtables['user_groups']}
	WHERE member_group != -1;
---*
