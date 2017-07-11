/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "bbPress 0.8.3"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ from_prefix: "`" . BBDB_NAME . "`.$bb_table_prefix"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$row['date_registered'] = strtotime($row['date_registered']);
$request = convert_query("
	SELECT meta_key, meta_value
	FROM {$from_prefix}usermeta
	WHERE user_id = $row[id_member]
		AND meta_key IN ('bbpress_capabilities', 'bbpress_topics_replied', 'bbpress_title', 'from')");
while ($row2 = convert_fetch_assoc($request))
{
	if ($row2['meta_key'] == 'bbpress_topics_replied')
		$row['posts'] = (int) $row2['meta_value'];
	elseif ($row2['meta_key'] == 'bbpress_title')
		$row['usertitle'] = trim($row2['meta_value']);
	elseif ($row2['meta_key'] == 'from')
		$row['location'] = trim($row2['meta_value']);
	elseif ($row2['meta_key'] == 'bbpress_capabilities')
	{
		$is_admin = @unserialize($row2['meta_value']);
		$row['id_group'] = isset($is_admin['keymaster']) && $is_admin['keymaster'] == 1 ? '1' : '0';
	}
}
convert_free_result($request);
---}
SELECT
	ID AS id_member, SUBSTRING(m.user_login, 1, 80) AS member_name, SUBSTRING(m.user_login, 1, 255) AS real_name,
	m.user_pass AS passwd, m.user_email AS email_address, SUBSTRING(m.user_url, 1, 255) AS website_title,
	SUBSTRING(m.user_url, 1, 255) AS website_url, m.user_registered AS date_registered, 0 AS posts,
	1 AS hide_email, '' AS avatar,'' AS member_ip, '' AS member_ip2, '' AS password_salt, 0 AS id_group,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	'' AS time_format, '' AS usertitle, '' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS location, '' AS ICQ, '' AS AIM, '' AS MSN, '' AS YIM,
	'' AS signature
FROM {$from_prefix}users AS m;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

---* {$to_prefix}boards
SELECT
	b.forum_id AS id_board, 1 AS id_cat, b.forum_parent AS id_parent, b.posts AS num_posts,
	b.topics AS num_topics, '-1,0' AS member_groups, SUBSTRING(b.forum_name, 1, 255) AS name,
	SUBSTRING(b.forum_desc, 1, 65534) AS description, b.forum_order AS board_order
FROM {$from_prefix}forums AS b;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics 20
SELECT
	t.topic_id AS id_topic, t.topic_sticky AS is_sticky, t.forum_id AS id_board,
	IFNULL(MIN(p.post_id), 0) AS id_first_msg, IFNULL(MAX(p.post_id), 0) AS id_last_msg,
	t.topic_poster AS id_member_started, t.topic_last_poster AS id_member_updated,
	t.topic_posts AS num_replies, CASE t.topic_open WHEN 1 THEN 0 ELSE 1 END AS locked
FROM {$from_prefix}topics AS t
	LEFT JOIN {$from_prefix}posts AS p ON (p.topic_id = t.topic_id)
GROUP BY p.topic_id;
---*

/******************************************************************************/
--- Converting posts...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['poster_time'] = strtotime($row['poster_time']);
$row['body'] = preg_replace(
	array(
		'~<p>~',
		'~</p>~',
		'~<a\s*href="(.+?)">(.+?)</a>~',
		'~<strong>~',
		'~</strong>~',
		'~<em>~',
		'~</em>~',
		'~<code>~',
		'~</code>~',
		'~<(?:ul|ol)>~',
		'~</(?:ul|ol)>~',
		'~<li>~',
		'~</li>~',
		'~<pre>~',
		'~</pre>~',
	),
	array(
		'',
		'',
		'[url=$1]$2[/url]',
		'[b]',
		'[/b]',
		'[i]',
		'[/i]',
		'[code]',
		'[/code]',
		'[list]',
		'[/list]',
		'[li]',
		'[/li]',
		'',
		'',
	),
	trim($row['body'])
);
---}
SELECT
	p.post_id AS id_msg, p.topic_id AS id_topic, p.forum_id AS id_board,
	p.post_time AS poster_time, p.poster_id AS id_member, t.topic_title AS subject,
	m.user_login AS poster_name, m.user_email AS poster_email, p.poster_ip AS poster_ip,
	0 AS modified_time, '' AS modified_name, p.post_text AS body
FROM {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}topics AS t ON (t.topic_id = p.topic_id)
	LEFT JOIN {$from_prefix}users AS m ON (m.ID = p.poster_id)
WHERE p.post_status = 0;
---*
