/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "LDU 802"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/datas/config.php"
---~ globals: config
---~ from_prefix: "`{$cfg['mysqldb']}`.ldu_"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
if ($row['birthdate'] > 0)
	$row['birthdate'] = date('Y-m-d',$row['birthdate']);

$row['signature'] = preg_replace(
array(
		'~\[mail=\"(.+?)\"\](.+?)\[\/mail\]~is',
		'~\[-\]~is',
		'~\[/-\]~is',
		'~=\"(.+?)\"]~is',
		'~\[mail\]~is',
		'~\[/mail\]~is',
		'~\[php\]~is',
		'~\[/php\]~is',
		'~\[ac=~is',
		'~\[/ac\]~is',
		'~\[p\]~is',
		'~\[/p\]~is',
		'~\[thumb=datas\/(.+?)\](.+?)\[\/thumb\]~is',
		'~\[page=(.+?)\](.+?)\[\/page\]~is',
		'~\[user=(.+?)\](.+?)\[\/user\]~is',
		'~\[f\](.+?)\[\/f\]~is',
		'~\[pfs\](.+?)\[\/pfs\]~is',
		'~\[topic\](.+?)\[\/topic\]~is',
		'~\[post\](.+?)\[\/post\]~is',
		'~\[pm\](.+?)\[\/pm\]~is',
		'~\[grey\](.+?)\[\/grey\]~is',
		'~\[sea\](.+?)\[\/sea\]~is',
		'~\[sky\](.+?)\[\/sky\]~is',
		'~\[yellow\](.+?)\[\/yellow\]~is',
		'~\[orange\](.+?)\[\/orange\]~is',
		'~\[pink\](.+?)\[\/pink\]~is',
		'~\[purple\](.+?)\[\/purple\]~is',
		'~\[style=(.+?)\](.+?)\[\/style\]~is',
	),
	array(
		'[email]$1[/email]',
		'[s]',
		'[/s]',
		'=$1]',
		'[email]',
		'[/email]',
		'[code]',
		'[/code]',
		'[acronym=',
		'[/acronym]',
		'',
		'',
		'[img]$1[/img]',
		'$2',
		'[iurl=index.php?action=profile;u=$1]$2[/iurl]',
		'',
		'',
		'[iurl=index.php?topic=$1.0]index.php?topic=$1.0[/iurl]',
		'',
		'[url=index.php?action=pm;sa=send;u=$1]index.php?action=pm;sa=send;u=$1[/url]',
		'[color=#B9B9B9]$1[/color]',
		'[color=#171A97]$1[/color]',
		'[color=#D1F4F9]$1[/color]',
		'[color=#FFFF00]$1[/color]',
		'[color=#FF9900]$1[/color]',
		'[color=#FFC0FF]$1[/color]',
		'[color=#A22ADA]$1[/color]',
		'$2',
	),
	trim($row['signature'])
);

//this is done in a seperate step, we dont want to destroy the BBCODEs
$row['signature'] = htmlspecialchars($row['signature']);
---}

SELECT
	user_id AS id_member, SUBSTRING(user_name, 1, 255) AS member_name,
	SUBSTRING(user_name, 1, 255) AS real_name, user_email AS email_address,
	SUBSTRING(user_password, 1, 64) AS passwd,
	user_postcount AS posts, '' AS usertitle,
	user_lastlog AS last_login,
	CASE user_level
		WHEN '99' THEN '1'
		WHEN '50' THEN '1'
		WHEN '40' THEN '2'
		ELSE '0'
	END AS id_group,
	user_regdate AS date_registered, SUBSTRING(user_website, 1, 255) AS website_url,
	SUBSTRING(user_website, 1, 255) AS website_title,
	SUBSTRING(user_icq, 1, 255) AS icq, '' AS aim,
	'' AS yim, SUBSTRING(user_msn, 1, 255) AS msn,
	SUBSTRING(user_text, 1, 65534) AS signature, user_hideemail AS hide_email,
	'' AS buddy_list, user_lastip AS member_ip, user_lastip AS member_ip2,
	'' AS pm_ignore_list, '' AS unread_messages,
	user_logcount AS total_time_logged_in,
	user_birthdate AS birthdate
FROM {$from_prefix}users;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT DISTINCT fs_id AS id_cat, SUBSTRING(fs_category, 1, 255) AS name, fs_order AS cat_order
FROM {$from_prefix}forum_sections
GROUP BY fs_category;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	b.fs_id AS id_board, SUBSTRING(b.fs_title, 1, 255) AS name,
	CASE b.fs_minlevel
		WHEN '0' THEN '-1,0,1,2'
		ELSE '0'
	END AS member_groups,
	SUBSTRING(b.fs_desc, 1, 65534) AS description, b.fs_order AS board_order,
	0 AS num_posts, 0 AS num_topics, c.id_cat AS id_cat
FROM {$from_prefix}forum_sections AS b
	LEFT JOIN {$to_prefix}categories AS c ON (c.name = b.fs_category);
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
	t.ft_id AS id_topic, t.ft_sectionid AS id_board,
	t.ft_sticky AS is_sticky, t.ft_viewcount AS num_views,
	t.ft_firstposterid AS id_member_started,
	t.ft_lastposterid AS id_member_updated,
	MIN(p.fp_id) AS id_first_msg, MAX(p.fp_id) AS id_last_msg,
	t.ft_postcount AS num_replies, 	t.ft_state AS locked
FROM {$from_prefix}forum_topics AS t
LEFT JOIN {$from_prefix}forum_posts AS p ON (t.ft_id = p.fp_topicid)
GROUP BY t.ft_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~\[mail=\"(.+?)\"\](.+?)\[\/mail\]~is',
		'~\[-\]~is',
		'~\[/-\]~is',
		'~=\"(.+?)\"]~is',
		'~\[mail\]~is',
		'~\[/mail\]~is',
		'~\[php\]~is',
		'~\[/php\]~is',
		'~\[ac=~is',
		'~\[/ac\]~is',
		'~\[p\]~is',
		'~\[/p\]~is',
		'~\[thumb=datas\/(.+?)\](.+?)\[\/thumb\]~is',
		'~\[page=(.+?)\](.+?)\[\/page\]~is',
		'~\[user=(.+?)\](.+?)\[\/user\]~is',
		'~\[f\](.+?)\[\/f\]~is',
		'~\[pfs\](.+?)\[\/pfs\]~is',
		'~\[topic\](.+?)\[\/topic\]~is',
		'~\[post\](.+?)\[\/post\]~is',
		'~\[pm\](.+?)\[\/pm\]~is',
		'~\[grey\](.+?)\[\/grey\]~is',
		'~\[sea\](.+?)\[\/sea\]~is',
		'~\[sky\](.+?)\[\/sky\]~is',
		'~\[yellow\](.+?)\[\/yellow\]~is',
		'~\[orange\](.+?)\[\/orange\]~is',
		'~\[pink\](.+?)\[\/pink\]~is',
		'~\[purple\](.+?)\[\/purple\]~is',
		'~\[style=(.+?)\](.+?)\[\/style\]~is',
	),
	array(
		'[email]$1[/email]',
		'[s]',
		'[/s]',
		'=$1]',
		'[email]',
		'[/email]',
		'[code]',
		'[/code]',
		'[acronym=',
		'[/acronym]',
		'',
		'',
		'[img]$1[/img]',
		'$2',
		'[iurl=index.php?action=profile;u=$1]$2[/iurl]',
		'',
		'',
		'[iurl=index.php?topic=$1.0]index.php?topic=$1.0[/iurl]',
		'',
		'[url=index.php?action=pm;sa=send;u=$1]index.php?action=pm;sa=send;u=$1[/url]',
		'[color=#B9B9B9]$1[/color]',
		'[color=#171A97]$1[/color]',
		'[color=#D1F4F9]$1[/color]',
		'[color=#FFFF00]$1[/color]',
		'[color=#FF9900]$1[/color]',
		'[color=#FFC0FF]$1[/color]',
		'[color=#A22ADA]$1[/color]',
		'$2',
	),
	trim($row['body'])
);

//this is done in a seperate step, we dont want to destroy the BBCODEs
$row['body'] = htmlspecialchars($row['body']);
---}

SELECT
	p.fp_id AS id_msg, p.fp_topicid AS id_topic,
	p.fp_sectionid AS id_board, p.fp_creation AS poster_time,
	p.fp_posterid AS id_member,	p.fp_updated AS id_msg_MODIFIED,
	t.ft_title AS subject,
	p.fp_postername AS poster_name,
	'' AS poster_email,	p.fp_posterip AS poster_ip,
	'1' AS smileys_enabled, p.fp_updated AS modified_time,
	p.fp_updater AS modified_name, p.fp_text AS body, 'xx' AS icon
FROM {$from_prefix}forum_posts AS p
	INNER JOIN {$from_prefix}forum_topics AS t ON (p.fp_topicid = t.ft_id)
GROUP BY p.fp_id;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/
TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace(
	array(
		'~\[mail=\"(.+?)\"\](.+?)\[\/mail\]~is',
		'~\[-\]~is',
		'~\[/-\]~is',
		'~=\"(.+?)\"]~is',
		'~\[mail\]~is',
		'~\[/mail\]~is',
		'~\[php\]~is',
		'~\[/php\]~is',
		'~\[ac=~is',
		'~\[/ac\]~is',
		'~\[p\]~is',
		'~\[/p\]~is',
		'~\[thumb=datas\/(.+?)\](.+?)\[\/thumb\]~is',
		'~\[page=(.+?)\](.+?)\[\/page\]~is',
		'~\[user=(.+?)\](.+?)\[\/user\]~is',
		'~\[f\](.+?)\[\/f\]~is',
		'~\[pfs\](.+?)\[\/pfs\]~is',
		'~\[topic\](.+?)\[\/topic\]~is',
		'~\[post\](.+?)\[\/post\]~is',
		'~\[pm\](.+?)\[\/pm\]~is',
		'~\[grey\](.+?)\[\/grey\]~is',
		'~\[sea\](.+?)\[\/sea\]~is',
		'~\[sky\](.+?)\[\/sky\]~is',
		'~\[yellow\](.+?)\[\/yellow\]~is',
		'~\[orange\](.+?)\[\/orange\]~is',
		'~\[pink\](.+?)\[\/pink\]~is',
		'~\[purple\](.+?)\[\/purple\]~is',
		'~\[style=(.+?)\](.+?)\[\/style\]~is',
	),
	array(
		'[email]$1[/email]',
		'[s]',
		'[/s]',
		'=$1]',
		'[email]',
		'[/email]',
		'[code]',
		'[/code]',
		'[acronym=',
		'[/acronym]',
		'',
		'',
		'[img]$1[/img]',
		'$2',
		'[iurl=index.php?action=profile;u=$1]$2[/iurl]',
		'',
		'',
		'[iurl=index.php?topic=$1.0]index.php?topic=$1.0[/iurl]',
		'',
		'[url=index.php?action=pm;sa=send;u=$1]index.php?action=pm;sa=send;u=$1[/url]',
		'[color=#B9B9B9]$1[/color]',
		'[color=#171A97]$1[/color]',
		'[color=#D1F4F9]$1[/color]',
		'[color=#FFFF00]$1[/color]',
		'[color=#FF9900]$1[/color]',
		'[color=#FFC0FF]$1[/color]',
		'[color=#A22ADA]$1[/color]',
		'$2',
	),
	trim($row['body'])
);

//this is done in a seperate step, we dont want to destroy the BBCODEs
$row['body'] = htmlspecialchars($row['body']);
---}

SELECT
	pm_id AS id_pm, pm_fromuserid AS id_member_from, pm_date AS msgtime,
	SUBSTRING(pm_fromuser, 1, 255) AS from_name,
	SUBSTRING(pm_title, 1, 255) AS subject,
	SUBSTRING(pm_text, 1, 65534) AS body
FROM {$from_prefix}pm;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/
TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm_id AS id_pm, pm_touserid AS id_member, 1 AS is_read, '-1' AS labels
FROM {$from_prefix}pm;
---*

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

---* {$to_prefix}smileys

---{
$no_add = true;
$keys = array('code', 'filename', 'description', 'smpath', 'hidden');

if (!isset($smf_smileys_directory))
{
	/* Find the path for SMF smileys. */
	$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'smileys_dir'
	LIMIT 1");

	list ($smf_smileys_directory) = convert_fetch_row($request);
	convert_free_result($request);
}

/* enable custom smileys */
$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'smiley_enable'
	LIMIT 1");

list ($smiley_enable) = convert_fetch_row($request);
convert_free_result($request);

if (isset($smiley_enable))
	convert_query("
		UPDATE {$to_prefix}settings
		SET value = '1'
		WHERE variable='smiley_enable'");

else
	convert_insert('settings', array('variable' => 'string', 'value' => 'string'),
		array('smiley_enable', '1'), 'ignore'
	);

$row['newfilename'] = substr(strrchr($row['filename'], '/'),1);
$row['description'] = htmlspecialchars($row['description'],ENT_QUOTES);

if (is_file($_POST['path_from'] . '/'. $row['filename']))
{
 	copy($_POST['path_from'] . '/'. $row['filename'] , $smf_smileys_directory . '/default/'.$row['newfilename']);

	convert_insert('smileys', array('code' => 'string', 'filename' => 'string', 'description' => 'string', 'hidden' => 'int'),
		array($row['code'], $row['newfilename'], $row['description'], 1), 'ignore'
	);
}
---}
SELECT
	smilie_image AS filename, smilie_code AS code, smilie_text AS description
FROM {$from_prefix}smilies;
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$row['filename'] = substr(strrchr($row['user_avatar'], '/'),1);
$file_hash = 'avatar_' . $row['id_member'] . strrchr($row['filename'], '.');

if (copy($_POST['path_from'] . '/' . $row['user_avatar'] , $attachmentUploadDir . '/' . $physical_filename))
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
FROM {$from_prefix}users
WHERE user_avatar LIKE 'datas%';
---*

/******************************************************************************/
--- Copy the thumbnail images for messages compability...
/******************************************************************************/

---# Copying over thumbnails directory ...
---{
$thumbnail_gallery_path = $_POST['path_from'] . '/datas/thumbs';

/* Copy thumbnails...*/
@mkdir($_POST['path_to'] . '/thumbs', 0777);
copy_dir($thumbnail_gallery_path, $_POST['path_to'] . '/thumbs');
---}