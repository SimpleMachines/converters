/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "bbPress 2.6.6"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ from_prefix: "" . BBDB_NAME . ".$bb_table_prefix"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Pre-Conversion Tasks and Converting Members ...
/******************************************************************************/

/* Need to fix some issues and copy some data in the BBPress 'users' table */
DROP TABLE IF EXISTS {$from_prefix}users_convert;

CREATE TABLE {$from_prefix}users_convert
LIKE {$from_prefix}users;

INSERT INTO {$from_prefix}users_convert
SELECT * FROM {$from_prefix}users;

UPDATE {$from_prefix}users_convert
SET user_login = REPLACE(user_login, '&', '&amp;')
WHERE user_login LIKE '%&%' AND user_login NOT LIKE '%&#%';

UPDATE {$from_prefix}users_convert
SET display_name = user_login
WHERE display_name = '';

/* Copy the details of the SMF Admin account so they can be re-added later */
CREATE TABLE IF NOT EXISTS {$to_prefix}members_admin
LIKE {$to_prefix}members;

INSERT IGNORE INTO {$to_prefix}members_admin
SELECT * FROM {$to_prefix}members
WHERE id_member = 1;

/* Start converting members */
TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$row['date_registered'] = strtotime($row['date_registered']);
$request = convert_query("
	SELECT meta_key, meta_value
	FROM {$from_prefix}usermeta
	WHERE user_id = $row[id_member]
		AND meta_key IN ('signature', 'user_registration_profile_pic_url', 'wc_last_active', 'wp__bbp_topic_count')");
while ($row2 = convert_fetch_assoc($request))
{
	if ($row2['meta_key'] == 'signature')
		$row['signature'] = TRIM($row2['meta_value']);
	elseif ($row2['meta_key'] == 'user_registration_profile_pic_url')
		$row['avatar'] = TRIM($row2['meta_value']);
	elseif ($row2['meta_key'] == 'wc_last_active')
		$row['last_login'] = TRIM($row2['meta_value']);
	elseif ($row2['meta_key'] == 'wp__bbp_topic_count')
		$row['posts'] = TRIM($row2['meta_value']);
}
convert_free_result($request);
---}
SELECT
	ID AS id_member, SUBSTRING(m.user_login, 1, 80) AS member_name, m.user_registered AS date_registered,
	SUBSTRING(TRIM(m.display_name), 1, 255) AS real_name, m.user_pass AS passwd, m.user_email AS email_address,
	SUBSTRING(m.user_url, 1, 255) AS website_title, SUBSTRING(m.user_url, 1, 255) AS website_url,
	'' AS avatar, '' AS signature, 0 AS last_login, 0 AS posts
FROM {$from_prefix}users AS m;
---*

/******************************************************************************/
--- Converting Boards ...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

---* {$to_prefix}boards
SELECT
	ID AS id_board, menu_order AS board_order, post_title AS name, post_content AS description,
	1 AS id_cat, '-1,0,2' AS member_groups
FROM {$from_prefix}posts
WHERE post_type = 'forum';
---*

/******************************************************************************/
--- Converting Posts - First Message ...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~<img.+src=[\'"](?P<src>.+?)[\'"].*>~i',
		'~\[quote quote=~',
		'~<p>~',
		'~</p>~',
		'~<a\s*href="(.+?)">(.+?)</a>~',
		'~<b>~',
		'~</b>~',
		'~<strong>~',
		'~</strong>~',
		'~<u>~',
		'~</u>~',
		'~<i>~',
		'~</i>~',
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
		'[img]$1[/img]',
		'[quote=',
		'',
		'',
		'[url=$1]$2[/url]',
		'[b]',
		'[/b]',
		'[b]',
		'[/b]',
		'[u]',
		'[/u]',
		'[i]',
		'[/i]',
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
	TRIM($row['body'])
);
$row['body'] = str_replace(
	array("Â", "â€™", "â€œ", 'â€“', 'â€', chr(145), chr(146), chr(147), chr(148), chr(150), chr(151), chr(133)),
	array("", "'", '"', '-', '"', "'", "'", '"', '"', '-', '--', '...'),
	$row['body']
);
$row['subject'] = str_replace(
	array("Â", "â€™", "â€œ", 'â€“', 'â€', chr(145), chr(146), chr(147), chr(148), chr(150), chr(151), chr(133)),
	array("", "'", '"', '-', '"', "'", "'", '"', '"', '-', '--', '...'),
	$row['subject']
);
---}
SELECT
	ID AS id_msg, ID AS id_topic, UNIX_TIMESTAMP(post_date) AS poster_time, post_author AS id_member,
	TRIM(post_title) AS subject, post_author AS poster_name, post_content AS body
FROM {$from_prefix}posts
WHERE post_type = 'topic' AND post_status = 'publish';
---*

/******************************************************************************/
--- Converting Posts - Replies ...

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~<img.+src=[\'"](?P<src>.+?)[\'"].*>~i',
		'~\[quote quote=~',
		'~<p>~',
		'~</p>~',
		'~<a\s*href="(.+?)">(.+?)</a>~',
		'~<b>~',
		'~</b>~',
		'~<strong>~',
		'~</strong>~',
		'~<u>~',
		'~</u>~',
		'~<i>~',
		'~</i>~',
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
		'[img]$1[/img]',
		'[quote=',
		'',
		'',
		'[url=$1]$2[/url]',
		'[b]',
		'[/b]',
		'[b]',
		'[/b]',
		'[u]',
		'[/u]',
		'[i]',
		'[/i]',
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
	TRIM($row['body'])
);
$row['body'] = str_replace(
	array("Â", "â€™", "â€œ", 'â€“', 'â€', chr(145), chr(146), chr(147), chr(148), chr(150), chr(151), chr(133)),
	array("", "'", '"', '-', '"', "'", "'", '"', '"', '-', '--', '...'),
	$row['body']
);
---}
SELECT
	ID AS id_msg, post_parent AS id_topic, UNIX_TIMESTAMP(post_date) AS poster_time,
	post_author AS id_member, post_author AS poster_name, post_content AS body
FROM {$from_prefix}posts
WHERE post_type = 'reply' AND post_status = 'publish';
---*

/******************************************************************************/
--- Converting topics ...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics
---{
$request = convert_query("
	SELECT meta_key, meta_value
	FROM {$from_prefix}postmeta
	WHERE post_id = $row[id_topic]
		AND meta_key IN ('_bbp_reply_count')");
while ($row2 = convert_fetch_assoc($request))
{
		$row['num_replies'] = $row2['meta_value'];
}
convert_free_result($request);
---}
SELECT
	ID AS id_topic, post_parent AS id_board, post_author AS id_member_started,
	id_msgmin AS id_first_msg, id_msgmax AS id_last_msg
FROM {$from_prefix}posts
LEFT JOIN (
	SELECT MIN(id_msg) AS id_msgmin, MAX(id_msg) AS id_msgmax, id_topic
	FROM {$to_prefix}messages
	GROUP BY id_topic
)
AS minmax
ON {$from_prefix}posts.ID = minmax.id_topic
WHERE post_type = 'topic' AND post_status = 'publish';
---*

/******************************************************************************/
--- Post-Conversion Tasks ...
/******************************************************************************/

/***********************************/
/* Post-conversion Tasks - Members */
/***********************************/

/* Re-add the Admin account */
UPDATE {$to_prefix}members m
JOIN {$to_prefix}members_admin a
ON (m.id_member = a.id_member)
SET
	m.member_name = a.member_name, m.date_registered = a.date_registered, m.id_group = a.id_group,
	m.real_name = a.real_name, m.passwd = a.passwd, m.email_address = a.email_address,
	m.password_salt = a.password_salt, m.website_title = a.website_title, m.website_url = a.website_url,
	m.avatar = a.avatar, m.signature = a.signature;

/* Fix ampersands and apostrophes in the member_name after the '&' character was removed */
UPDATE {$to_prefix}members
SET member_name = REPLACE(member_name, 'amp;', '&amp;')
WHERE member_name LIKE '%amp;%';

UPDATE {$to_prefix}members
SET member_name = REPLACE(member_name, '#039;', '&#039;')
WHERE member_name LIKE '%#039;%';

/* Signature - Remove backslashes before single quotes/apostrophes */
UPDATE {$to_prefix}members
SET signature = REPLACE(signature, '\\\'', '\'')
WHERE signature LIKE '%\'%';

/* Signature - Remove backslashes before double quotes */
UPDATE {$to_prefix}members
SET signature = REPLACE(signature, '\\\"', '"')
WHERE signature LIKE '%\"%';


/***********************************/
/* Post-conversion Tasks - Boards  */
/***********************************/

/* Description - Remove backslashes before single quotes/apostrophes */
UPDATE {$to_prefix}boards
SET description = REPLACE(description, '\\\'', '\'')
WHERE description LIKE '%\'%';

/* Description - Remove backslashes before double quotes */
UPDATE {$to_prefix}boards
SET description = REPLACE(description, '\\\"', '"')
WHERE description LIKE '%\"%';

/***********************************/
/* Post-conversion Tasks - Posts   */
/***********************************/

/* Subject - Remove backslashes before single quotes/apostrophes */
UPDATE {$to_prefix}messages
SET subject = REPLACE(subject, '\\\'', '\'')
WHERE subject LIKE '%\'%';

/* Subject - Remove backslashes before double quotes */
UPDATE {$to_prefix}messages
SET subject = REPLACE(subject, '\\\"', '"')
WHERE subject LIKE '%\"%';

/* Body - Remove backslashes before single quotes/apostrophes */
UPDATE {$to_prefix}messages
SET body = REPLACE(body, '\\\'', '\'')
WHERE body LIKE '%\'%';

/* Body - Remove backslashes before double quotes */
UPDATE {$to_prefix}messages
SET body = REPLACE(body, '\\\"', '"')
WHERE body LIKE '%\"%';

/* Add the board ID to all messages */
UPDATE {$to_prefix}messages AS m
LEFT JOIN {$to_prefix}topics AS t
ON m.id_topic = t.id_topic
SET m.id_board = t.id_board;

/* Add the subject to replies */
UPDATE {$to_prefix}messages AS a
INNER JOIN {$to_prefix}messages AS b
ON a.id_topic = b.id_topic
SET a.subject = b.subject
WHERE a.id_msg != b.id_topic;

/* Copy the member email address to the poster email */
UPDATE {$to_prefix}messages
SET poster_email = (
	SELECT email_address
	FROM {$to_prefix}members
	WHERE {$to_prefix}members.id_member = {$to_prefix}messages.id_member
);

/* Copy the member name to the poster name */
UPDATE {$to_prefix}messages
SET poster_name = (
	SELECT member_name
	FROM {$to_prefix}members
	WHERE {$to_prefix}members.id_member = {$to_prefix}messages.id_member
);

/* Use the member number for the poster name if there is no poster name */
/* (This can happen when the member account has been deleted)           */
UPDATE {$to_prefix}messages
SET poster_name = CONCAT('Member ID ', id_member)
WHERE poster_name = '';

