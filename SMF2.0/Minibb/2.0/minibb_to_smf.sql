/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "MiniBB 2.0"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/setup_options.php"
---~ from_prefix: "`$DBname`."
---~ globals: Tf, Tp, Tt, Tu, Ts, Tb, admin_usr
---~ table_test: "{$from_prefix}{$Tu}"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	user_id AS id_member, SUBSTRING(username, 1, 80) AS member_name,
	SUBSTRING(username, 1, 255) AS real_name,
	UNIX_TIMESTAMP(user_regdate) AS date_registered,
	SUBSTRING(user_email, 1, 255) AS email_address,
	UNIX_TIMESTAMP(user_regdate) AS last_login,
	SUBSTRING(user_from, 1, 255) AS location,
	SUBSTRING(user_password, 1, 64) AS passwd,
	SUBSTRING(user_icq, 1, 255) AS icq,
	SUBSTRING(user_website, 1, 255) AS website_title,
	SUBSTRING(user_website, 1, 255) AS website_url,
	IF(user_viewemail = 1, 0, 1) AS hide_email, num_posts AS posts,
	IF('{$admin_usr}' = username, 1, 0) AS id_group, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS aim, '' AS yim, '' AS msn, '' AS time_format,
	'' AS signature, '' AS avatar, '' AS usertitle, '' AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt, '' AS member_ip2
FROM {$from_prefix}{$Tu};
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---{
convert_insert('categories', array('id_cat', 'name'), array(1, 'General Category'));
---}

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	forum_id AS id_board, 1 AS id_cat, forum_order AS board_order,
	SUBSTRING(forum_name, 1, 255) AS name,
	SUBSTRING(forum_desc, 1, 65534) AS description, topics_count AS num_topics,
	posts_count AS num_posts, '-1,0' AS member_groups
FROM {$from_prefix}{$Tf};
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
	t.topic_id AS id_topic, t.sticky AS is_sticky, t.forum_id AS id_board,
	t.topic_poster AS id_member_started, (t.posts_count - 1) AS num_replies,
	t.topic_views AS num_views, t.topic_status AS locked,
	MIN(p.post_id) AS id_first_msg, MAX(p.post_id) AS id_last_msg
FROM {$from_prefix}{$Tt} AS t
	INNER JOIN {$from_prefix}{$Tp} AS p ON (p.topic_id = t.topic_id)
GROUP BY t.topic_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, p.poster_id AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}{$Tp} AS p ON (p.post_id = t.id_last_msg);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
SELECT
	p.post_id AS id_msg, p.topic_id AS id_topic,
	SUBSTRING(t.topic_title, 1, 255) AS subject,
	UNIX_TIMESTAMP(p.post_time) AS poster_time,
	SUBSTRING(p.poster_ip, 1, 255) AS poster_ip, p.poster_id AS id_member,
	SUBSTRING(IFNULL(u.username, p.poster_name), 1, 255) AS poster_name,
	SUBSTRING(IFNULL(u.user_email, ''), 1, 255) AS poster_email,
	p.forum_id AS id_board,
	SUBSTRING(REPLACE(p.post_text, '<br>', '<br />'), 1, 65534) AS body,
	'' modified_name, 'xx' AS icon
FROM {$from_prefix}{$Tp} AS p
	INNER JOIN {$from_prefix}{$Tt} AS t ON (t.topic_id = p.topic_id)
	LEFT JOIN {$from_prefix}{$Tu} AS u ON (u.user_id = p.poster_id);
---*

/******************************************************************************/
--- Clearing unused SMF tables...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;
TRUNCATE {$to_prefix}personal_messages;
TRUNCATE {$to_prefix}pm_recipients;