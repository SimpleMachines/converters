/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "MyPHP Forum 3.0"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ from_prefix: "`$dbname`.{$tablepre}"
---~ table_test: "{$from_prefix}member"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$row['signature'] = substr(strtr($row['signature'], array('[mail' => '[email', '[/mail]' => '[/email]')), 0, 65534);
---}
SELECT
	uid AS id_member, SUBSTRING(username, 1, 255) AS member_name,
	SUBSTRING(username, 1, 255) AS real_name,
	SUBSTRING(password, 1, 64) AS passwd, SUBSTRING(ip, 1, 255) AS member_ip,
	SUBSTRING(email, 1, 255) AS email_address,
	SUBSTRING(website, 1, 255) AS website_url,
	SUBSTRING(website, 1, 255) AS website_title,
	SUBSTRING(aim, 1, 16) AS aim, SUBSTRING(msn, 1, 255) AS msn,
	SUBSTRING(location, 1, 255) AS location,
	REPLACE(sig, '\n', '<br />') AS signature,
	IF(status = 'Administrator', 1, 0) AS id_group, regdate AS date_registered,
	posts, SUBSTRING(yahoo, 1, 32) AS yim, private AS hide_email,
	SUBSTRING(tag, 1, 255) AS personal_text,
	CONCAT(RIGHT(birthday, 4), '-', LEFT(birthday, 5)) AS birthdate,
	IF(gender = 'Male', 1, 2) AS gender, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS icq, '' AS time_format,
	'' AS avatar, '' AS usertitle, '' AS secret_question, '' AS secret_answer,
	'' AS validation_code, '' AS additional_groups, '' AS smiley_set,
	'' AS password_salt, SUBSTRING(ip, 1, 255) AS member_ip2
FROM {$from_prefix}member;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---{
convert_insert('categories', array('id_cat', 'cat_order', 'name', 'can_collapse'), array(1, 0, 'General Category', 1), 'insert ignore');
---}

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	fid AS id_board, 1 AS id_cat, SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS name, dorder AS board_order
FROM {$from_prefix}forum;
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
	t.tid AS id_topic, t.fid AS id_board, t.replies AS num_replies,
	t.views AS num_views, t.topped = 'yes' AS is_sticky, t.status = 2 AS locked,
	mem.uid AS id_member_started, MIN(p.pid) AS id_first_msg,
	MAX(p.pid) AS id_last_msg
FROM {$from_prefix}topic AS t
	INNER JOIN {$from_prefix}post AS p ON (p.tid = t.tid)
	LEFT JOIN {$from_prefix}member AS mem ON (mem.username = t.author)
GROUP BY t.tid
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, mem.uid AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}post AS p ON (p.pid = t.id_last_msg)
	INNER JOIN {$from_prefix}member AS mem ON (mem.username = p.author);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$row['body'] = substr(strtr($row['body'], array('[mail' => '[email', '[/mail]' => '[/email]')), 0, 65534);
---}
SELECT
	p.pid AS id_msg, p.tid AS id_topic, t.fid AS id_board,
	SUBSTRING(mem.ip, 1, 255) AS poster_ip, mem.uid AS id_member,
	p.dateline AS poster_time, SUBSTRING(p.author, 1, 255) AS poster_name,
	SUBSTRING(mem.email, 1, 255) AS poster_email,
	SUBSTRING(REPLACE(p.message, '\n', '<br />'), 1, 65534) AS body,
	SUBSTRING(IF(p.subject = '', CONCAT('Re:', t.name), p.subject), 1, 255) AS subject,
	'' AS modified_name, 'xx' AS icon
FROM {$from_prefix}post AS p
	INNER JOIN {$from_prefix}topic AS t ON (t.tid = p.tid)
	LEFT JOIN {$from_prefix}member AS mem ON (mem.username = p.author);
---*

/******************************************************************************/
--- Removing polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = strtr($row['body'], array('[mail' => '[email', '[/mail]' => '[/email]'));
---}
SELECT
	pm.id AS id_pm, mem.uid AS id_member_from, pm.time AS msgtime,
	SUBSTRING(pm.sender, 1, 255) AS from_name,
	SUBSTRING(pm.topic, 1, 255) AS subject,
	SUBSTRING(REPLACE(pm.message, '\n', '<br />'), 1, 65534) AS body
FROM {$from_prefix}privmsg AS pm
	LEFT JOIN {$from_prefix}member AS mem ON (mem.username = pm.sender);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT pm.id AS id_pm, mem.uid AS id_member, '' AS labels
FROM {$from_prefix}privmsg AS pm
	INNER JOIN {$from_prefix}member AS mem ON (mem.username = pm.receiver);
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
	FROM {$from_prefix}words");
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