/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Land Down Under 80x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/datas/config.php"
---~ globals: $db_users, $db_forum_sections, $db_forum_topics, $db_forum_posts
---~ globals: $db_polls, $db_polls_options, $db_polls_voters, $db_pm
---~ from_prefix: "`{$cfg['mysqldb']}`."
---~ table_test: "{$from_prefix}$db_users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
SELECT
	user_id AS id_member, user_active AS is_activated,
	SUBSTRING(user_name, 1, 80) AS member_name,
	SUBSTRING(user_name, 1, 255) AS real_name,
	SUBSTRING(user_password, 1, 64) AS passwd,
	SUBSTRING(user_location, 1, 255) AS location,
	IF(user_level > 94, 1, 0) AS id_group, SUBSTRING(user_msn, 1, 255) AS msn,
	SUBSTRING(user_icq, 1, 255) AS icq,
	SUBSTRING(REPLACE(user_text, '\n', '<br />'), 1, 65534) AS signature,
	SUBSTRING(user_lastip, 1, 255) AS member_ip,
	SUBSTRING(user_lastip, 1, 255) AS member_ip2,
	FROM_UNIXTIME(user_birthdate) AS birthdate,
	SUBSTRING(user_website, 1, 255) AS website_title,
	SUBSTRING(user_website, 1, 255) AS website_url, user_hideemail AS hide_email,
	CASE user_gender WHEN 'M' THEN 1 WHEN 'F' THEN 2 ELSE 0 END AS gender,
	SUBSTRING(user_email, 1, 255) AS email_address,
	user_pmnotify AS pm_email_notify, user_regdate AS date_registered,
	user_lastlog AS last_login, user_postcount AS posts, '' AS lngfile,
	'' AS buddy_list, '' AS pm_ignore_list, '' AS personal_text, '' AS aim,
	'' AS yim, '' AS time_format, '' AS avatar, '' AS usertitle,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt
FROM {$from_prefix}{$db_users};
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT DISTINCT SUBSTRING(fs_category, 1, 255) AS name
FROM {$from_prefix}{$db_forum_sections}
ORDER BY fs_order;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	fs.fs_id AS id_board, fs.fs_order AS board_order,
	SUBSTRING(fs.fs_title, 1, 255) AS name, c.id_cat,
	SUBSTRING(fs.fs_desc, 1, 65534) AS description,
	fs.fs_postcount AS num_posts, fs_topiccount AS num_topics,
	fs_countposts = 0 AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}{$db_forum_sections} AS fs
	INNER JOIN {$to_prefix}categories AS c ON (c.name = fs.fs_category);
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
	t.ft_id AS id_topic, t.ft_state = 1 AS locked, t.ft_sticky AS is_sticky,
	t.ft_sectionid AS id_board, t.ft_postcount - 1 AS num_replies,
	t.ft_viewcount AS num_views, t.ft_lastposterid AS id_member_updated,
	t.ft_firstposterid AS id_member_started, MIN(p.fp_id) AS id_first_msg,
	MAX(p.fp_id) AS id_last_msg, t.ft_poll AS id_poll
FROM {$from_prefix}{$db_forum_topics} AS t
	INNER JOIN {$from_prefix}{$db_forum_posts} AS p ON (p.fp_topicid = t.ft_id)
	AND ft_movedto = 0
GROUP BY t.ft_id
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
	p.fp_id AS id_msg, p.fp_topicid AS id_topic, p.fp_sectionid AS id_board,
	p.fp_posterid AS id_member,
	SUBSTRING(p.fp_postername, 1, 255) AS poster_name,
	p.fp_creation AS poster_time,
	SUBSTRING(p.fp_updater, 1, 255) AS modified_name,
	IF(p.fp_updated != p.fp_creation, p.fp_updated, 0) AS modified_time,
	SUBSTRING(REPLACE(p.fp_text, '\n', '<br />'), 1, 65534) AS body,
	SUBSTRING(p.fp_posterip, 1, 255) AS poster_ip,
	SUBSTRING(t.ft_title, 1, 255) AS subject,
	SUBSTRING(u.user_email, 1, 255) AS poster_email, 'xx' AS icon
FROM {$from_prefix}{$db_forum_posts} AS p
	INNER JOIN {$from_prefix}{$db_forum_topics} AS t ON (t.ft_id = p.fp_topicid)
	LEFT JOIN {$from_prefix}{$db_users} AS u ON (u.user_id = p.fp_posterid);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.poll_id AS id_poll, IF(p.poll_state != 0, 1, 0) AS voting_locked,
	SUBSTRING(p.poll_text, 1, 255) AS question,
	t.ft_firstposterid AS id_member,
	SUBSTRING(t.ft_firstpostername, 1, 255) AS poster_name
FROM {$from_prefix}{$db_polls} AS p
	INNER JOIN {$from_prefix}{$db_forum_topics} AS t ON (t.ft_poll = p.poll_id)
WHERE p.poll_type = 1;
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
if (!isset($_SESSION['convert_last_poll']) || $_SESSION['convert_last_poll'] != $row['id_poll'])
{
	$_SESSION['convert_last_poll'] = $row['id_poll'];
	$_SESSION['convert_last_choice'] = 0;
}

$row['id_choice'] = ++$_SESSION['convert_last_choice'];
---}
SELECT
	po_pollid AS id_poll, 0 AS id_choice,
	SUBSTRING(po_text, 1, 255) AS label, po_count AS votes
FROM {$from_prefix}{$db_polls_options}
ORDER BY po_pollid;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pv_pollid AS id_poll, pv_userid AS id_member
FROM {$from_prefix}{$db_polls_voters};
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm_id AS id_pm, pm_fromuserid AS id_member_from, pm_date AS msgtime,
	SUBSTRING(pm_fromuser, 1, 255) AS from_name,
	SUBSTRING(pm_title, 1, 255) AS subject,
	SUBSTRING(REPLACE(pm_text, '\n', '<br />'), 1, 65534) AS body
FROM {$from_prefix}{$db_pm};
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm_id AS id_pm, pm_touserid AS id_member, pm_state != 0 AS is_read,
	'-1' AS labels
FROM {$from_prefix}{$db_pm};
---*