/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "UseBB 0.5.1"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ globals: dbs
---~ defines: INCLUDED
---~ from_prefix: "`{$dbs['dbname']}`.{$dbs['prefix']}"
---~ table_test: "{$from_prefix}members"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	id AS id_member, SUBSTRING(name, 1, 80) AS member_name,
	SUBSTRING(email, 1, 255) AS email_address, email_show = 0 AS hide_email,
	SUBSTRING(passwd, 1, 64) AS passwd, regdate AS date_registered,
	IF(level = 3, 1, 0) AS id_group, active AS is_activated,
	SUBSTRING(active_key, 1, 10) AS validation_code,
	last_pageview AS last_login, hide_from_online_list = 0 AS show_online, posts,
	SUBSTRING(avatar_remote, 1, 255) AS avatar,
	SUBSTRING(displayed_name, 1, 255) AS real_name,
	SUBSTRING(signature, 1, 65534) AS signature, birthday AS birthdate,
	SUBSTRING(location, 1, 255) AS location,
	SUBSTRING(website, 1, 255) AS website_url,
	SUBSTRING(website, 1, 255) AS website_title,
	SUBSTRING(msnm, 1, 255) AS msn, SUBSTRING(yahoom, 1, 32) AS yim,
	SUBSTRING(aim, 1, 16) AS aim, SUBSTRING(icq, 1, 255) AS icq
FROM {$from_prefix}members;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT id AS id_cat, SUBSTRING(name, 1, 255) AS name, sort_id AS cat_order
FROM {$from_prefix}cats;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	id AS id_board, SUBSTRING(name, 1, 255) AS name, cat_id AS id_cat,
	SUBSTRING(descr, 1, 65534) AS description, topics AS num_topics,
	posts AS num_posts, sort_id AS board_order,
	increase_post_count = 0 AS count_posts, '-1,0' AS member_groups
	/* // !!! auth? */
FROM {$from_prefix}forums;
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
	t.id AS id_topic, t.forum_id AS id_board, t.status_sticky AS is_sticky,
	t.count_views AS num_views, t.count_replies AS num_replies,
	t.status_locked AS locked, t.first_post_id AS id_first_msg,
	t.last_post_id AS id_last_msg, pf.poster_id AS id_member_started,
	pl.poster_id AS id_member_updated
FROM {$from_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS pf ON (pf.id = t.first_post_id)
	INNER JOIN {$from_prefix}posts AS pl ON (pl.id = t.last_post_id)
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
	p.id AS id_msg, p.topic_id AS id_topic, t.forum_id AS id_board,
	p.poster_id AS id_member, SUBSTRING(p.poster_ip_addr, 1, 255) AS poster_ip,
	SUBSTRING(IF(p.poster_guest = '', mem.name, p.poster_guest), 1, 255) AS poster_name,
	p.post_time AS poster_time, SUBSTRING(t.topic_title, 1, 255) AS subject,
	SUBSTRING(mem.email, 1, 255) AS poster_email,
	p.enable_smilies AS smileys_enabled,
	SUBSTRING(edit_mem.displayed_name, 1, 255) AS modified_name,
	p.post_edit_time AS modified_time,
	SUBSTRING(REPLACE(p.content, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}topics AS t ON (t.id = p.topic_id)
	LEFT JOIN {$from_prefix}members AS mem ON (mem.id = p.poster_id)
	LEFT JOIN {$from_prefix}members AS edit_mem ON (edit_mem.id = p.post_edit_by);
---*

/******************************************************************************/
--- Clearing unused tables...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;
TRUNCATE {$to_prefix}personal_messages;
TRUNCATE {$to_prefix}pm_recipients;

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT user_id AS id_member, topic_id AS id_topic
FROM {$from_prefix}subscriptions;
---*

/******************************************************************************/
--- Converting censored words...
/******************************************************************************/

DELETE FROM {$to_prefix}settings
WHERE variable IN ('censor_vulgar', 'censor_proper');

---# Moving censored words...
---{
$result = convert_query("
	SELECT word, replacement
	FROM {$from_prefix}badwords");
$censor_vulgar = array();
$censor_proper = array();
while ($row = convert_fetch_assoc($result))
{
	$censor_vulgar[] = $row['word'];
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
SELECT user_id AS id_member, forum_id AS id_board
FROM {$from_prefix}moderators;
---*