/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "PHPKit 1.6.4 "
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/Pkinc/Rep/Sites/Include/Data/Sql.php"
---~ from_prefix: "`" . pkSQLDATABASE. "`. ". pkSQLPREFIX. "_"
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
if (preg_match('/avatar/i', $row['avatar']))
	$row['avatar'] = 'gallery/' . $row['avatar'];
elseif (preg_match('/avauser/i', $row['avatar']))
	$row['avatar'] = '';
else
	$row['avatar'] = $row['avatar'];

$row['signature'] = preg_replace(
	array(
		'~\[D\]~is',
		'~\[/D\]~is',
		'~\[CODE\]~is',
		'~\[/CODE\]~is',
		'~\[LIST=1\]~is',
		'~\[/LIST=1\]~is',
		'~\[LIST=a\]~is',
		'~\[/LIST=a\]~is',
		'~\[H2\]~is',
		'~\[/H2\]~is',
		'~\[H3\]~is',
		'~\[/H3\]~is',
		'~\[H4\]~is',
		'~\[/H4\]~is',
		'~\[P\]~is',
		'~\[/P\]~is',
		'~\[BLOCK\]~is',
		'~\[/BLOCK\]~is',
		'~\[gray\]~is',
		'~\[/gray\]~is',
		'~\[royalblue\]~is',
		'~\[/royalblue\]~is',
		'~\[navy\]~is',
		'~\[/navy\]~is',
		'~\[orange\]~is',
		'~\[/orange\]~is',
		'~\[yellow\]~is',
		'~\[/yellow\]~is',
		'~\[DimGray\]~is',
		'~\[/DimGray\]~is',
	),
	array(
		'[s]',
		'[/s]',
		'[code]',
		'[/code]',
		'[list type=decimal]',
		'[/list]',
		'[list type=lower-alpha]',
		'[/list]',
		'[size=18pt]',
		'[/size]',
		'[size=16pt]',
		'[/size]',
		'[size=14pt]',
		'[/size]',
		'',
		'',
		'',
		'',
		'[color=#AAAAAA]',
		'[/color]',
		'[color=#0099FF]',
		'[/color]',
		'[color=#003399]',
		'[/color]',
		'[color=#FF7F00]',
		'[/color]',
		'[color=#FFFF00]',
		'[/color]',
		'[color=#333333]',
		'[/color]',
	),
	htmlspecialchars(trim($row['signature']))
);
---}

SELECT
	user_id AS id_member, SUBSTRING(user_name, 1, 80) AS member_name,
	SUBSTRING(user_nick, 1, 255) AS real_name, user_email AS email_address,
	SUBSTRING(user_pw, 1, 64) AS passwd, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	user_hpage AS website_title, user_hpage AS website_url,
	CASE user_country
		WHEN 'ger' THEN 'Germany'
		WHEN 'aut' THEN 'Austria'
		WHEN 'ch' THEN 'Swiss'
		WHEN 'nl' THEN 'Netherlands'
		WHEN 'aut' THEN 'Austria'
		ELSE ''
	END AS location,
	user_icqid AS icq, user_aimid AS aim, user_yim AS yim, '' AS msn, '' AS usertitle,
	'' AS member_ip, '' AS member_ip2, '' AS secret_question,
	'' AS additional_groups,
	logtime AS last_login,
	CASE user_status
		WHEN 'admin' THEN '1'
		WHEN 'mod' THEN '2'
		ELSE '0'
	END AS id_group,
	signin AS date_registered, user_avatar AS avatar,
	user_ghost	AS show_online, IF(user_emailshow ='1', 0, 1) AS hide_email,
	user_posts AS posts, user_sex AS gender, user_activate AS is_activated,
	CONCAT(user_bd_year,'-',user_bd_month,'-',user_bd_day) AS birthdate,
	SUBSTRING(user_sig, 1, 65534) AS signature
FROM {$from_prefix}user where user_id > 0;
---*

/******************************************************************************/
--- Creating general category...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---{
//  PHPKit has no categories, so we only have to clean SMF's categories table and create a General Category */
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
	forumcat_id AS id_board, '1' AS id_cat, forumcat_name AS name, forumcat_order AS board_order,
	forumcat_subcat AS id_parent,
	CASE forumcat_rrights
		WHEN 'member' THEN '0,2'
		WHEN 'user' THEN '0,2'
		WHEN 'mod' THEN '2'
		WHEN 'admin' THEN ''
		ELSE '1,2,3,-1,0'
 	END AS member_groups,
	IF (forumcat_description_show ='1', forumcat_description, '') AS description,
	forumcat_threadcount AS num_topics, forumcat_postcount AS num_posts
FROM {$from_prefix}forumcat;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/

TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;
TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}topics

SELECT
	t.forumthread_id AS id_topic, t.forumthread_catid AS id_board,
	CASE t.forumthread_status
		WHEN '2' THEN '1'
		WHEN '3' THEN '1'
		ELSE '0'
	END AS is_sticky,
	t.forumthread_viewcount AS num_views, t.forumthread_uid AS id_member_started, t.forumthread_lastreply_autor AS id_member_updated,
	MIN(p.forumpost_id) AS id_first_msg, MAX(p.forumpost_id) AS id_last_msg,
	t.forumthread_replycount AS num_replies,
	CASE t.forumthread_status
		WHEN '0' THEN '1'
		WHEN '3' THEN '1'
		ELSE '0'
	END AS locked
FROM {$from_prefix}forumthread AS t
	INNER JOIN {$from_prefix}forumpost AS p ON (p.forumpost_threadid=t.forumthread_id)
GROUP BY t.forumthread_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT DISTINCT
	forumnotify_userid AS id_member, forumnotify_threadid AS id_topic
FROM {$from_prefix}forumnotify;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
if ($row['subject']=='')
{
	$request = convert_query("
		SELECT forumpost_title
		FROM {$from_prefix}forumpost
		WHERE forumpost_threadid = $row[id_topic]
		ORDER BY forumpost_id ASC
		LIMIT 1	");

	while ($row2 = convert_fetch_assoc($request))
		$row['subject'] = $row2['forumpost_title'];
}
$row['body'] = preg_replace(
	array(
		'~\[D\]~is',
		'~\[/D\]~is',
		'~\[CODE\]~is',
		'~\[/CODE\]~is',
		'~\[LIST=1\]~is',
		'~\[/LIST=1\]~is',
		'~\[LIST=a\]~is',
		'~\[/LIST=a\]~is',
		'~\[H2\]~is',
		'~\[/H2\]~is',
		'~\[H3\]~is',
		'~\[/H3\]~is',
		'~\[H4\]~is',
		'~\[/H4\]~is',
		'~\[P\]~is',
		'~\[/P\]~is',
		'~\[BLOCK\]~is',
		'~\[/BLOCK\]~is',
		'~\[gray\]~is',
		'~\[/gray\]~is',
		'~\[royalblue\]~is',
		'~\[/royalblue\]~is',
		'~\[navy\]~is',
		'~\[/navy\]~is',
		'~\[orange\]~is',
		'~\[/orange\]~is',
		'~\[yellow\]~is',
		'~\[/yellow\]~is',
		'~\[DimGray\]~is',
		'~\[/DimGray\]~is',
	),
	array(
		'[s]',
		'[/s]',
		'[code]',
		'[/code]',
		'[list type=decimal]',
		'[/list]',
		'[list type=lower-alpha]',
		'[/list]',
		'[size=18pt]',
		'[/size]',
		'[size=16pt]',
		'[/size]',
		'[size=14pt]',
		'[/size]',
		'',
		'',
		'',
		'',
		'[color=#AAAAAA]',
		'[/color]',
		'[color=#0099FF]',
		'[/color]',
		'[color=#003399]',
		'[/color]',
		'[color=#FF7F00]',
		'[/color]',
		'[color=#FFFF00]',
		'[/color]',
		'[color=#333333]',
		'[/color]',
	),
	htmlspecialchars(trim($row['body']))
);
---}

SELECT
	p.forumpost_id AS id_msg, p.forumpost_threadid AS id_topic,
	t.forumthread_catid AS id_board, p.forumpost_time AS poster_time, p.forumpost_autorid AS id_member, p.forumpost_edittime AS id_msg_MODIFIED,
	IF(p.forumpost_title != '', p.forumpost_title, subject.forumpost_title) AS subject,
	p.forumpost_autor AS poster_name, u.user_email AS poster_email,
	p.forumpost_ipaddr AS poster_ip, p.forumpost_smilies AS smileys_enabled, p.forumpost_edittime AS modified_time, p.forumpost_editautor AS modified_name,
	p.forumpost_text AS body, 'xx' AS icon
FROM {$from_prefix}forumpost AS p
	INNER JOIN {$from_prefix}forumthread AS t ON (t.forumthread_id = p.forumpost_threadid)
	INNER JOIN {$from_prefix}forumpost AS subject ON (p.forumpost_threadid = subject.forumpost_threadid)
	LEFT JOIN {$from_prefix}user AS u ON (u.user_id = p.forumpost_autorid)
GROUP BY p.forumpost_id;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.im_id AS id_pm, pm.im_autor AS id_member_from, pm.im_time AS msgtime,
	IF(u.user_name IS NULL, 'Guest', SUBSTRING(u.user_name, 1, 255)) AS from_name,
	SUBSTRING(pm.im_title, 1, 255) AS subject,
	SUBSTRING(pm.im_text, 1, 65534) AS body
FROM {$from_prefix}im AS pm
	LEFT JOIN {$from_prefix}user AS u ON (u.user_id=pm.im_autor);
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	im_id AS id_pm, im_to AS id_member, IF(im_viewtime !=0, 1, 0) AS is_read,
	im_del AS deleted, '-1' AS labels
FROM {$from_prefix}im;
---*

/******************************************************************************/
--- Converting rangs...
/******************************************************************************/

DELETE FROM {$to_prefix}membergroups
WHERE min_posts > -1;

---* {$to_prefix}membergroups
SELECT
	forumrank_post AS min_posts, forumrank_title AS GroupName
FROM {$from_prefix}forumrank;
---*

/******************************************************************************/
--- Converting buddys..
/******************************************************************************/
---{
$no_add = true;
$keys = array('id_member', 'buddy_list');

$request = convert_query("
	SELECT buddy_userid AS tmp_member
	FROM {$from_prefix}buddy
	GROUP BY buddy_userid");

while ($row = convert_fetch_assoc($request))
{
	$buddies = array();

	$request2 = convert_query("
		SELECT
			buddy_userid AS id_member, buddy_friendid AS buddy_list
		FROM {$from_prefix}buddy
		WHERE buddy_userid = $row[tmp_member]");

	while ($row2 = convert_fetch_assoc($request2))
	{
		array_push($buddies, $row2['buddy_list']);
		$buddylist = implode(',',$buddies);
	}

	convert_query("
		UPDATE {$to_prefix}members
		SET buddy_list = '$buddylist'
		WHERE id_member = $row[tmp_member]");
}
convert_free_result($request);
---}

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;
---{
$no_add = true;
$keys = array('id_board', 'id_member');

$request = convert_query("
	SELECT
		forumcat_id AS id_board, forumcat_mods as tempmods
	FROM {$from_prefix}forumcat");

while ($row = convert_fetch_assoc($request))
{
	$row['tempmods'] = trim(preg_replace('/-/', ' ', $row['tempmods']));
	$mod = explode(' ', $row['tempmods']);
	foreach ($mod as $moderators)
		convert_insert('moderators', array('id_board', 'id_board'), array($row['id_board'], $moderators), 'insert');
}
convert_free_result($request);
---}

/******************************************************************************/
--- Converting avatar gallery images...
/******************************************************************************/

---# Copying over avatar directory...
---{
// Find the path for SMF avatars.
$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'avatar_directory'
	LIMIT 1");

list ($smf_avatar_directory) = convert_fetch_row($request);
convert_free_result($request);

$phpkit_avatar_gallery_path = $_POST['path_from'] . '/images/avatar';

// Copy gallery avatars...
@mkdir($smf_avatar_directory . '/gallery', 0777);
copy_dir($phpkit_avatar_gallery_path, $smf_avatar_directory . '/gallery');

//  delete the user's avatar from the gallery
$gallery = opendir($smf_avatar_directory . '/gallery');

$files = array();
while($line = readdir($gallery))
	array_push($files, $line);

$avatars = preg_grep('/avauser/i', $files);

foreach ($avatars as $user_avatar)
	unlink($smf_avatar_directory . '/gallery/' . $user_avatar);
---}
---#

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;
$filepath = 'images/avatar/' . $row['user_avatar'];
$file_hash = 'avatar_' . $row['id_member'] . strrchr($row['user_avatar'], '.');

if (copy($_POST['path_from'] . '/' . $filepath, $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_member' => $row['id_member'],
	);
	$id_attach++;
}
---}
SELECT
	user_id AS id_member, user_avatar
FROM {$from_prefix}user
WHERE user_avatar LIKE 'avauser_%';
---*

/******************************************************************************/
--- Converting censored words...
/******************************************************************************/

---# Moving censored words...
---{
$result = convert_query("
	SELECT censor_badword
	FROM {$from_prefix}config");

$censor_vulgar = array();
$censor_proper = array();
while ($row = convert_fetch_assoc($result))
{
	$censor_vulgar[] = $row['censor_badword'];
	$censor_proper[] = $row['censor_badword'];
}
convert_free_result($result);

$censored_vulgar = addslashes(implode("\n", $censor_vulgar));
$censored_proper = addslashes(implode("\n", $censor_proper));
$censored_proper = preg_replace('/.*/','*',$censor_proper);

convert_insert('settings', array('variable', 'value'),
	array(
		array('censor_vulgar', $censored_vulgar)
		array('censor_proper', $censored_proper[0])
	), 'replace');
---}
---#

/******************************************************************************/
--- Converting Bans...
/******************************************************************************/

TRUNCATE {$to_prefix}ban_groups;
TRUNCATE {$to_prefix}ban_items;

---{
$no_add = true;
$keys = array('id_member', 'member_name');

$request = convert_query("
	SELECT
		user_id AS id_member, user_name AS member_name
	FROM {$from_prefix}user
	WHERE user_status = 'ban'");

// Only insert if we have results
if (convert_num_rows($request) > 0)
		convert_insert('ban_groups', array('id_ban_group', 'name', 'ban_time', 'expire_time', 'reason', 'notes', 'cannot_access'),
			array(1, "migrated_ban_" . $row['member_name'], time(), NULL, '', 'Migrated from phpkit', 1),
			'insert ignore'
		);

$banid = 1;
while ($row = convert_fetch_assoc($request))
{
	convert_insert('ban_items', array('id_ban', 'id_ban_group', 'id_member'), array($row['id_member'], 1, $row['id_member']), 'insert');

	++$banid;
}
convert_free_result($request);
---}

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

---{
$specificSmileys = array(
	':-|' => 'sad',
	':D' => 'biggrin',
	':o' => 'confused',
	'8-)' => 'cool',
	';(' => 'cry',
	';D' => 'evil',
	':(' => 'sad',
	':-)' => 'grin',
	':-\\' => 'rolleyes',
	':-o' => 'shocked',
	':)' => 'smiley',
	';)' => 'wink',
	':p' => 'tongue',
	':-)' => 'grin',
	'8-|' => 'cool',
	'(**)' => 'kiss',
);

$request = convert_query("
	SELECT MAX(smiley_order)
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
	$rows[] = array($code, $name . '.gif', $name, $count);
}

if (!empty($rows))
	convert_insert('smileys', array('code', 'filename', 'description', 'smiley_order'), $rows, 'replace');
---}