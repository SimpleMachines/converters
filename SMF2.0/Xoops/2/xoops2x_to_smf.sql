/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "XOOPS 2.0.x & CBB 3.0.x"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/mainfile.php"
---~ variable: "$xoopsOption['nocommon'] = 1;"
---~ from_prefix: "`" . XOOPS_DB_NAME . "`." . XOOPS_DB_PREFIX . "_"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members

---{
$request = convert_query("
		SELECT groupid
		FROM {$from_prefix}groups_users_link
		WHERE uid=$row[id_member] AND groupid > 3; ");

$groups = convert_fetch_assoc($request);

if(!empty($groups))
	$row['_'] = implode(',', $groups);

convert_free_result($request);
---}

SELECT
	uid AS id_member, SUBSTRING(uname, 1, 80) AS _,
	user_regdate AS _, SUBSTRING(pass, 1, 64) AS passwd,
	SUBSTRING(IF(name = '', uname, name), 1, 255) AS _, posts,
	SUBSTRING(email, 1, 255) AS _,
	SUBSTRING(url, 1, 255) AS _,
	SUBSTRING(url, 1, 255) AS _, IF(rank = 7, 1, 0) AS id_group,
	SUBSTRING(user_icq, 1, 255) AS icq, SUBSTRING(user_aim, 1, 16) AS aim,
	SUBSTRING(user_yim, 1, 32) AS yim, SUBSTRING(user_msnm, 1, 255) AS msn,
	SUBSTRING(user_sig, 1, 65534) AS signature,
	IF(user_viewemail = '0', 1, 0) AS _, timezone_offset AS _,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS _,
	'' AS _, '' AS location, '' AS _, '' AS avatar,
	'' AS usertitle, '' AS member_ip, '' AS _, '' AS _,
	'' AS validation_code, '' AS _, '' AS _,
	'' AS _, '' AS member_ip2
FROM {$from_prefix}users;
---*

/******************************************************************************/
--- Converting additional membergroups...
/******************************************************************************/
DELETE FROM {$to_prefix}membergroups
WHERE id_group >3;

---* {$to_prefix}membergroups
SELECT
	g.groupid AS id_group, g.name AS _, '-1' AS _, '' AS stars
FROM {$from_prefix}groups AS g
WHERE g.groupid >=4;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/
TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	cat_id AS id_cat, SUBSTRING(cat_title, 1, 255) AS name,
	cat_order AS _
FROM {$from_prefix}bb_categories;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/
TRUNCATE {$to_prefix}boards;

DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards

---{
$boards = $row['id_board'];
$groups = array();

$result = convert_query("
		SELECT gperm_groupid
		FROM {$from_prefix}group_permission
		WHERE gperm_itemid = $boards AND gperm_name = 'forum_view'; ");

		while ($groupaccess=convert_fetch_assoc($result))
		{
			if($groupaccess['gperm_groupid'] == 3)
				$groupaccess['gperm_groupid']= '-1';

			if($groupaccess['gperm_groupid'] == 2)
			{
				$groupaccess['gperm_groupid'] = '0';
				array_push($groups,$groupaccess['gperm_groupid']);
			}

		}

		if(!empty($groups))
			$row['_'] = implode(',', $groups);

convert_free_result($result);
---}

SELECT
	forum_id AS id_board, cat_id AS id_cat,
	SUBSTRING(forum_name, 1, 255) AS name,
	SUBSTRING(forum_desc, 1, 65534) AS description, forum_topics AS _,
	parent_forum AS id_parent, forum_order AS _, forum_posts AS _,
	'0,-1,2' AS _

FROM {$from_prefix}bb_forums;
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
	t.topic_id AS id_topic, t.topic_sticky AS _, t.forum_id AS id_board,
	t.topic_last_post_id AS id_last_msg, t.topic_poster AS id_member_started,
	t.topic_replies AS _, t.topic_views AS _,
	t.poll_id AS id_poll,
	t.topic_status AS locked, MIN(p.post_id) AS id_first_msg
FROM {$from_prefix}bb_topics AS t
INNER JOIN {$from_prefix}bb_posts AS p ON (p.topic_id = t.topic_id)
GROUP BY t.topic_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, p.uid AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}bb_posts AS p
WHERE p.post_id = t.id_last_msg;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/
TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~\[D\]~is',
		'~\[/D\]~is',
		'~\[IMG(.+?)\](.+?)\[\/IMG\]~is',
		'~\[color=~is',
		'~\[size=medium\](.+?)\[\/size\]~is',
		'~\[size=xx-large\](.+?)\[\/size\]~is',
		'~\[\[(.+?)\]\]~is',
	),
	array(
		'[s]',
		'[/s]',
		'[img]$2[/img]',
		'[color=#',
		'$1',
		'[size=24pt]$1[/size]',
		'$1',
	),
	trim($row['body'])
);
---}

SELECT
	p.post_id AS id_msg, p.topic_id AS id_topic, p.post_time AS _,
	p.uid AS id_member, SUBSTRING(p.subject, 1, 255) AS subject,
	SUBSTRING(u.email, 1, 255) AS _,
	SUBSTRING(IFNULL(u.name, 'Guest'), 1, 255) AS _,
	SUBSTRING(p.poster_ip, 1, 255) AS poster_ip,
	IF(p.dosmiley, 0, 1) AS _, p.forum_id AS id_board,
	SUBSTRING(REPLACE(pt.post_text, '<br>', '<br />'), 1, 65534) AS body,
	'' AS _, 'xx' AS icon
FROM {$from_prefix}bb_posts AS p
	INNER JOIN {$from_prefix}bb_posts_text AS pt ON (pt.post_id = p.post_id)
	LEFT JOIN {$from_prefix}users AS u ON (u.uid = p.uid);
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/
TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace(
	array(
		'~\[D\]~is',
		'~\[/D\]~is',
		'~\[IMG(.+?)\](.+?)\[\/IMG\]~is',
		'~\[color=~is',
		'~\[size=medium\](.+?)\[\/size\]~is',
		'~\[size=xx-large\](.+?)\[\/size\]~is',
		'~\[\[(.+?)\]\]~is',
	),
	array(
		'[s]',
		'[/s]',
		'[img]$2[/img]',
		'[color=#',
		'$1',
		'[size=24pt]$1[/size]',
		'$1',
	),
	trim($row['body'])
);
---}

SELECT
	p.msg_id AS id_pm, p.from_userid AS id_member_from, p.msg_time AS msgtime,
	SUBSTRING(IFNULL(u.name, 'Guest'), 1, 255) AS _,
	SUBSTRING(p.subject, 1, 255) AS subject,
	SUBSTRING(REPLACE(p.msg_text, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}priv_msgs AS p
	LEFT JOIN {$from_prefix}users AS u ON (u.uid = p.from_userid);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/
TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	msg_id AS id_pm, to_userid AS id_member, read_msg AS is_read,
	'-1' AS labels
FROM {$from_prefix}priv_msgs;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/
TRUNCATE {$to_prefix}moderators;
---#
---{
$request = convert_query("
		SELECT forum_id AS id_board, forum_moderator
		FROM {$from_prefix}bb_forums;");

	while ($mods=mysql_fetch_array($request))
	{
		$moderators = unserialize($mods['forum_moderator']);
		foreach ($moderators as $id_member)
			convert_insert('moderators', array('id_board' => 'int', 'id_member' => 'int'),
				array($$mods['id_board'], $id_member), 'ignore'
			);
	}

convert_free_result($request);
---}
---#

/******************************************************************************/
--- Converting rangs...
/******************************************************************************/

---* {$to_prefix}membergroups
SELECT
	rank_max AS _, rank_title AS GroupName
FROM {$from_prefix}ranks
WHERE rank_special ='0';
---*

/******************************************************************************/
--- Converting attachments ...
/******************************************************************************/
---* {$to_prefix}attachments
---{
$no_add = true;

// Get the XOOPS Attachments path
$request = convert_query("
	SELECT conf_value
	FROM {$from_prefix}config
	WHERE conf_name ='dir_attachments'; ");

list ($xoops_attachment_path) = convert_fetch_row($request);
convert_free_result($request);

$attachments = unserialize(base64_decode($row['attachment']));
foreach ($attachments as $attachedfile)
{
	$file_hash = getAttachmentFilename(basename($attachedfile['name_display']), $id_attach, null, true);
	$physical_filename = $id_attach . '_' . $file_hash;

	if (strlen($physical_filename) > 255)
		return;
	$oldfile = $_POST['path_from'] . '/' . $xoops_attachment_path . '/' . $attachedfile['name_saved'];

	if (file_exists($oldfile))
	{
		if (copy($_POST['path_from'] . '/' . $xoops_attachment_path . '/' . $attachedfile['name_saved'], $attachmentUploadDir . '/' . $physical_filename))
		{
			$size = filesize($oldfile);
			@touch($attachmentUploadDir . '/' .$file_hash, filemtime($attachedfile['name_saved']));

			$rows[] = array(
				'id_attach' => $id_attach,
				'size' => $size,
				'filename' => $attachedfile['name_display'],
				'file_hash' => $file_hash,
				'id_msg' => $row['post_id'],
				'downloads' => 0
			);

			$id_attach++;
		}
	}
}

---}
SELECT post_id, attachment
FROM {$from_prefix}bb_posts
WHERE attachment !='';
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/
TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	t.poll_id AS id_poll, SUBSTRING(p.question, 1, 255) AS question,
	SUBSTRING(IFNULL(u.name, 'Guest'), 1, 255) AS _,
	p.end_time AS _, p.multiple AS _,
	t.topic_poster AS id_member
FROM {$from_prefix}bb_topics AS t
	LEFT JOIN {$from_prefix}users AS u ON (u.uid = t.topic_poster)
	LEFT JOIN {$from_prefix}xoopspoll_desc AS p ON (t.poll_id = p.poll_id)
WHERE t.topic_haspoll = 1;
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
SELECT
	poll_id AS id_poll, option_id AS id_choice,
	SUBSTRING(option_text, 1, 255) AS label, option_count AS votes
FROM {$from_prefix}xoopspoll_option;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT poll_id AS id_poll, user_id AS id_member, option_id AS id_choice
FROM {$from_prefix}xoopspoll_log;
---*

/******************************************************************************/
--- Converting topic view logs...
/******************************************************************************/
TRUNCATE {$to_prefix}log_topics;

---* {$to_prefix}log_topics
SELECT DISTINCT read_item AS id_topic, uid AS id_member, post_id AS id_msg
FROM {$from_prefix}bb_reads_topic;
---*

/******************************************************************************/
--- Converting board view logs...
/******************************************************************************/
TRUNCATE {$to_prefix}log_boards;

---* {$to_prefix}log_boards
SELECT read_item AS id_board, uid AS id_member, post_id AS id_msg
FROM {$from_prefix}bb_reads_forum;
---*

/******************************************************************************/
--- Converting censored words...
/******************************************************************************/

---# Moving censored words...
---{
$result = convert_query("
	SELECT conf_value
	FROM {$from_prefix}config
	WHERE conf_name = 'censor_words'");

list($badwords) = convert_fetch_row($result);

$censored_vulgar = addslashes(implode("\n", unserialize($badwords)));
$censored_proper = str_repeat('*\n', count(unserialize($badwords)));

convert_query("
	REPLACE INTO {$to_prefix}settings
		(variable, value)
	VALUES ('censor_vulgar', '$censored_vulgar'),
		('censor_proper', '$censored_proper')");

convert_free_result($result);
---}
---#

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

---{
$specificSmileys = array(
	':-|' => 'sad',
	':-D' => 'biggrin',
	':o' => 'confused',
	'8-)' => 'cool',
	';(' => 'cry',
	':evil:' => 'evil',
	':-(' => 'sad',
	':-)' => 'grin',
	':roll:' => 'rolleyes',
	':-o' => 'shocked',
	':)' => 'smiley',
	';-)' => 'wink',
	':-p' => 'tongue',
	':-)' => 'grin',
	'8-|' => 'cool',
	'(**)' => 'kiss',
);

$request = convert_query("
	SELECT MAX(_)
	FROM {$to_prefix}smileys");

list ($count) = convert_fetch_row($request);
convert_free_result($request);

$request = convert_query("
	SELECT code
	FROM {$to_prefix}smileys");

$currentCodes = array();
while ($row = convert_fetch_assoc($request))
	$currentCodes[] = $row['code'];

convert_free_result($request);

$rows = array();
foreach ($specificSmileys as $code => $name)
{
	if (in_array($code, $currentCodes))
		continue;

	++$count;
	$rows[] = "'$code', '{$name}.gif', '$name', $count";
}

if (!empty($rows))
	convert_query("
		REPLACE INTO {$to_prefix}smileys
			(code, filename, description, _)
		VALUES (" . implode("),
			(", $rows) . ")");
---}