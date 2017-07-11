/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "wowBB 1.7"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ from_prefix: "`" . DB_NAME. "`. ".FILE_SYSTEM. "_"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting Membergroups...
/******************************************************************************/
DELETE FROM {$to_prefix}membergroups
WHERE id_group >3 AND min_posts = -1;

ALTER TABLE {$to_prefix}membergroups
ADD COLUMN temp_id varchar(32),
ADD INDEX temp_id (temp_id(32));

---* {$to_prefix}membergroups
SELECT
	g.user_group_id AS temp_id, g.user_group_name AS group_name, '-1' AS min_posts,
	'' AS stars
FROM {$from_prefix}user_groups AS g
WHERE g.user_group_id >6;
---*

/******************************************************************************/
--- Converting group access...
/******************************************************************************/
DELETE FROM {$to_prefix}permissions
WHERE id_group > 3;

---#
---{
$ignore = true;
$request = convert_query("
	SELECT
		m.id_group AS id_group, view_board, view_member_info,
		post_new_topics, post_polls, vote_on_polls,
		reply_to_others_topics, edit_own_posts,
		post_attachments, pm, search, view_whos_online,
		view_public_events, post_public_events
	FROM {$from_prefix}user_groups AS g
		INNER JOIN {$to_prefix}membergroups AS m ON (g.user_group_id = m.temp_id)
	WHERE g.user_group_id >6;");

while ($row = convert_fetch_assoc($request))
{
	$this_group = array();
	$this_board = array();

	//view the members infos
	if ($row['view_member_info'] =='1')
	{
		$this_group[] = 'view_mlist';
		$this_group[] = 'profile_view_any';
		$this_group[] = 'profile_view_own';
		$this_group[] = 'profile_extra_own';
		$this_group[] = 'profile_identity_own';
		$this_group[] = 'view_stats';
	}

	//view whos online
	if ($row['view_whos_online'] =='1')
		$this_group[] = 'who_view';

	//attachments permissions
	if ($row['post_attachments'] =='1')
	{
		$this_board[] = 'view_attachments';
		$this_board[] = 'post_attachments';
	}

	//search permissions
	if ($row['search'] =='1')
		$this_group[] = 'search_posts';

	//calendar permissions
	if ($row['view_public_events'] =='1')
		$this_group[] = 'calendar_view';
	if ($row['post_public_events'] =='1')
		$this_group[] = 'calendar_post';

	//topics permissions
	if ($row['post_new_topics'] =='1' )
	{
		$this_board[] = 'post_new';
		$this_board[] = 'lock_own';
		$this_board[] = 'mark_notify';
		$this_board[] = 'mark_any_notify';
	}
	if ($row['reply_to_others_topics'] == '1')
	{
	$this_board[] = 'post_reply_any';
	$this_board[] = 'post_reply_own';
	}

	//posts permissions
	if ($row['edit_own_posts'] =='1')
	{
		$this_board[] = 'modify_own';
		$this_board[] = 'delete_own';
	}

	//poll permissions
	if ($row['post_polls'] =='1')
	{
		$this_board[] = 'poll_post';
		$this_board[] = 'poll_add_own';
		$this_board[] = 'poll_edit_own';
		$this_board[] = 'poll_lock_own';
	}
	if ($row['vote_on_polls'] =='1')
	{
		$this_board[] = 'poll_vote';
		$this_board[] = 'poll_view';
	}

	//pm permisssions
	if ($row['pm'] =='1')
	{
		$this_group[] = 'pm_read';
		$this_group[] = 'pm_send';
	}

	$setStringpermissions = '';
	$this_group = array_unique($this_group);
	foreach ($this_group as $perm)
	{
		$setStringpermissions .= "
			($row[id_group], '$perm'),";
	}

	if ($setStringpermissions != '')
		convert_query("
			INSERT IGNORE INTO {$to_prefix}permissions
				(id_group, permission)
			VALUES" . substr($setStringpermissions, 0, -1));

	$setStringboard = '';
	$this_board = array_unique($this_board);

	foreach ($this_board as $boardperm)
	{
		$setStringboard .= "
			($row[id_group], '0', '$boardperm'),";
	}

	if ($setStringboard != '')
		convert_query("
			INSERT IGNORE INTO {$to_prefix}board_permissions
				(id_group, id_board, permission)
			VALUES" . substr($setStringboard, 0, -1));
}
convert_free_result($request);
---}
---#

/******************************************************************************/
--- Converting members...
/******************************************************************************/
TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
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
		'~\[size=\"(.+?)\"](.+?)\[\/size\]~is',
		'~=\"(.+?)\"]~is',
		'~\[b\]\[user=(.+?)\](.+?)\[\/user\] wrote: \[\/b\]\[quote\]~is',
		'~\[b\]\[user=(.+?)\](.+?)\[\/user\] wrote: \[\/b\]\\n\[quote\]~is',
		'~\[user=(.+?)\](.+?)\[\/user\] wrote: \[quote\]~is',
		'~\[scroll=(.+?)\](.+?)\[\/scroll\]~is',
		'~\[align=(.+?)\](.+?)\[\/align\]~is',
		'~\[align=center\]~is',
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
		'[size=$1]$2[/size]',
		'=$1]',
		'[quote=$2]',
		'[quote=$2]',
		'[quote=$2]',
		'[move]$2[/move]',
		'[$1]$2[/$1]',
		'',
	),
	trim($row['signature'])
);

if (preg_match('/galleries/i', $row['avatar']))
	$row['avatar'] = preg_replace('/images\/avatars\/galleries\//','',$row['avatar']);
elseif (preg_match('/images\/avatars/i', $row['avatar']))
	$row['avatar'] = '';
else
{
	if (isset($row['avatar']))
		$row['avatar'] = $row['avatar'];
}
---}
SELECT
	u.user_id AS id_member, SUBSTRING(u.user_name, 1, 80) AS member_name,
	SUBSTRING(u.user_name, 1, 255) AS real_name, u.user_email AS email_address,
	SUBSTRING(u.user_password, 1, 64) AS passwd, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	u.user_homepage AS website_title, u.user_homepage AS website_url,
	u.user_country AS location, u.user_icq AS icq, u.user_aim AS aim,
	u.user_ym AS yim, u.user_msnm AS msn, '' AS usertitle, '' AS member_ip,
	'' AS member_ip2, '' AS secret_question, IF(u.user_group_id > 6, 0, '') AS additional_groups,
	CASE u.user_group_id
		WHEN '1' THEN '1'
		WHEN '2' THEN '0'
		WHEN '3' THEN '0'
		WHEN '4' THEN '0'
		WHEN '5' THEN '2'
		WHEN '6' THEN '1'
		ELSE m.id_group
	END AS id_group,
	UNIX_TIMESTAMP(u.user_joined) AS date_registered, '' AS last_login,
	u.user_avatar AS avatar, IF(u.user_invisible = '1', 0, 1) AS show_online,
	IF(u.user_view_email = '1', 0, 1) AS hide_email,	u.user_posts AS posts, 0 AS gender,
	u.user_birthday AS birthdate, IF (u.user_activation_key != '', 0, 1) AS is_activated,
	u.user_activation_key AS validation_code,
	SUBSTRING(u.user_signature, 1, 65534) AS signature
FROM {$from_prefix}users AS u
	LEFT JOIN {$to_prefix}membergroups AS m ON (u.user_group_id = m.temp_id);
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/
TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	category_id AS id_cat, SUBSTRING(category_name, 1, 255) AS name,
	category_order AS cat_order
FROM {$from_prefix}categories;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/
TRUNCATE {$to_prefix}boards;

DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
---{
$membergroup=array();
$request = convert_query("
		SELECT
			m.id_group AS member_groups, g.user_group_id AS oldGroup
		FROM {$from_prefix}forum_permissions AS p
			LEFT JOIN {$to_prefix}membergroups AS m ON (p.user_group_id = m.temp_id)
			LEFT JOIN {$from_prefix}user_groups AS g ON (g.user_group_id=p.user_group_id)
		WHERE view_forum ='1'
		AND p.forum_id = $row[id_board]; ");

while ($members=mysql_fetch_array($request))
{
	if($members['oldGroup']==1)
		array_push($membergroup, '-1');

	elseif($members['oldGroup']==2)
		array_push($membergroup, '0');

	elseif($members['oldGroup']==3)
		{}
	elseif($members['oldGroup']==4)
		array_push($membergroup, '0');

	elseif($members['oldGroup']==5)
		array_push($membergroup, '2');

	elseif($members['oldGroup']==6)
		array_push($membergroup, '1');

	elseif($members['member_groups']>6)
		array_push($membergroup, $members['0']);
}
convert_free_result($request);

if (!empty($membergroup))
	$row['member_groups'] = implode(',',$membergroup);
---}
SELECT
	forum_id AS id_board, category_id AS id_cat, SUBSTRING(forum_name, 1, 255) AS name,
	SUBSTRING(forum_description, 1, 65534) AS description,
	forum_topics AS num_topics, '0,2' AS member_groups, forum_posts AS num_posts,
	forum_order AS board_order, forum_last_post_id AS id_last_msg
FROM {$from_prefix}forums;
---*

/******************************************************************************/
--- Converting topics...
/******************************************************************************/
TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

ALTER TABLE {$to_prefix}membergroups
DROP COLUMN temp_id;

---* {$to_prefix}topics
SELECT
	t.topic_id AS id_topic, IF(t.topic_moved_to != '', t.topic_moved_to, t.forum_id) AS id_board,
	t.topic_last_post_id AS id_last_msg, t.topic_starter_id AS id_member_started,
	t.topic_replies AS num_replies, t.topic_views AS num_views,
	t.poll_id AS id_poll, IF(t.topic_type > 0, 1, 0) AS is_sticky,
	t.topic_status AS locked, p.post_id AS id_first_msg
FROM {$from_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.topic_id = t.topic_id)
GROUP BY t.topic_id
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/
TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$row['body'] = preg_replace(
	array(
		'~\[shadow="(.+?)"\](.+?)\[\/shadow\]~is',
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
		'~\[size=\"(.+?)\"](.+?)\[\/size\]~is',
		'~=\"(.+?)\"]~is',
		'~\[b\]\[user=(.+?)\](.+?)\[\/user\] wrote: \[\/b\]\[quote\]~is',
		'~\[scroll=(.+?)\](.+?)\[\/scroll\]~is',
		'~\[align=(.+?)\](.+?)\[\/align\]~is',
		'~\[\/\*\]~is',
		'~\[glow=(.+?)\](.+?)\[\/glow\]~is',
		'~\[media=(.+?)\](.+?)\[\/media\]~is',
		'~\[real=(.+?)\](.+?)\[\/real\]~is',
		'~\[quicktime=(.+?)\](.+?)\[\/quicktime\]~is',
		'~\[shadow=(.+?)\](.+?)\[\/shadow\]~is',
		'~\[user=(.+?)\](.+?)\[\/user\]~is',
		'~\[size=\+1\]~is',
		'~\[size=\-1\]~is',
		'~\[/size\]~is',
		'~\[indent\]~is',
		'~\[/indent\]~is',
	),
	array(
		'[shadow=$1,250]$2[/shadow]',
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
		'[size=$1]$2[/size]',
		'=$1]',
		'[quote=$2]',
		'[move]$2[/move]',
		'[$1]$2[/$1]',
		'',
		'[glow=$1,250]$2[/glow]',
		'$2',
		'$2',
		'$2',
		'[shadow=$1,250]$2[/shadow]',
		'$2',
		'[size=14pt]',
		'[size=10pt]',
		'[/size]',
		'',
		'',
	),
	trim($row['body'])
);
---}

SELECT
	p.post_id AS id_msg, p.topic_id AS id_topic, p.forum_id AS id_board,
	UNIX_TIMESTAMP(p.post_date_time) AS poster_time, p.user_id AS id_member,
	p.post_last_edited_on AS id_msg_MODIFIED, t.topic_name AS subject,
	p.post_user_name AS poster_name, u.user_email AS poster_email,
	p.post_ip AS poster_ip, '1' AS smileys_enabled,
	UNIX_TIMESTAMP(p.post_last_edited_on) AS modified_time,
	e.user_name AS modified_name, m.post_text AS body, 'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}post_texts AS m ON (m.post_id = p.post_id)
	INNER JOIN {$from_prefix}topics AS t ON (p.topic_id = t.topic_id)
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id = p.user_id)
	LEFT JOIN {$from_prefix}users AS e ON (p.post_last_edited_by = e.user_id);
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/
TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.poll_id AS id_poll, SUBSTRING(p.question, 1, 255) AS question,
	t.topic_starter_user_name AS poster_name, p.poll_ends AS expire_time,
	p.multiple_choice AS max_votes, t.topic_starter_id AS id_member
FROM {$from_prefix}poll_questions AS p
	LEFT JOIN {$from_prefix}topics AS t ON (t.poll_id = p.poll_id);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
SELECT
	poll_id AS id_poll, poll_option_id AS id_choice,
	SUBSTRING(option_text, 1, 255) AS label, votes AS votes
FROM {$from_prefix}poll_options;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT
	poll_id AS id_poll, user_id AS id_member, poll_option_id AS id_choice
FROM {$from_prefix}poll_votes;
---*

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/
TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT
	forum_id AS id_board, user_id AS id_member
FROM {$from_prefix}moderators;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/
TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['body'] = preg_replace(
	array(
		'~\[shadow="(.+?)"\](.+?)\[\/shadow\]~is',
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
		'~\[size=\"(.+?)\"](.+?)\[\/size\]~is',
		'~=\"(.+?)\"]~is',
		'~\[b\]\[user=(.+?)\](.+?)\[\/user\] wrote: \[\/b\]\[quote\]~is',
		'~\[scroll=(.+?)\](.+?)\[\/scroll\]~is',
		'~\[align=(.+?)\](.+?)\[\/align\]~is',
		'~\[\/\*\]~is',
		'~\[glow=(.+?)\](.+?)\[\/glow\]~is',
		'~\[media=(.+?)\](.+?)\[\/media\]~is',
		'~\[real=(.+?)\](.+?)\[\/real\]~is',
		'~\[quicktime=(.+?)\](.+?)\[\/quicktime\]~is',
		'~\[shadow=(.+?)\](.+?)\[\/shadow\]~is',
		'~\[user=(.+?)\](.+?)\[\/user\]~is',
	),
	array(
		'[shadow=$1,250]$2[/shadow]',
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
		'[size=$1]$2[/size]',
		'=$1]',
		'[quote=$2]',
		'[move]$2[/move]',
		'[$1]$2[/$1]',
		'',
		'[glow=$1,250]$2[/glow]',
		'$2',
		'$2',
		'$2',
		'[shadow=$1,250]$2[/shadow]',
		'$2',
	),
	trim($row['body'])
);
---}
SELECT
	pm.pm_id AS id_pm, pm.pm_from AS id_member_from,
	UNIX_TIMESTAMP(pm.pm_date_time) AS msgtime,
	IF(u.user_name IS NULL, 'Guest', SUBSTRING(u.user_name, 1, 255)) AS from_name,
	SUBSTRING(pm.pm_subject, 1, 255) AS subject, SUBSTRING(t.pm_text, 1, 65534) AS body
FROM {$from_prefix}pm AS pm
	INNER JOIN {$from_prefix}pm_texts AS t ON (pm.pm_id=t.pm_id)
	LEFT JOIN {$from_prefix}users AS u ON (u.user_id=pm.pm_from)
WHERE pm.user_id = pm.pm_from;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/
TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm_id AS id_pm, pm_to AS id_member, pm_status AS is_read,'0' AS deleted,
	pm_cc AS bcc, '-1' AS labels
FROM {$from_prefix}pm
WHERE user_id = pm_from;
---*

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
$wowbb_avatar_gallery_path = $_POST['path_from'] . '/images/avatars/galleries';

/* Copy gallery avatars...*/
@mkdir($smf_avatar_directory . '', 0777);
copy_dir($wowbb_avatar_gallery_path, $smf_avatar_directory);
---}
---#

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;
$filename = preg_replace('/images\/avatars\//','',$row['user_avatar']);
$filepath = $row['user_avatar'];
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
FROM {$from_prefix}users
WHERE user_avatar NOT LIKE '%galleries%'
AND user_avatar !='';
---*

/******************************************************************************/
--- Converting attachments ...
/******************************************************************************/
---* {$to_prefix}attachments
---{
$no_add = true;
$file_hash = getAttachmentFilename(basename($row['filename']), $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

$file = fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
fwrite($file, $row['file_contents']);
fclose($file);

@touch($attachmentUploadDir . '/' . $physical_filename, filemtime($row['filename']));
$rows[] = array(
	'id_attach' => $id_attach,
	'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
	'filename' => $row['filename'],
	'file_hash' => $file_hash,
	'id_msg' => $row['id_msg'],
	'downloads' => $row['downloads'],
);
$id_attach++;
---}
SELECT
	a.attachment_id, a.file_contents, p.post_id AS id_msg, a.file_name AS filename,
	'' AS size, a.downloads AS downloads
FROM {$from_prefix}attachments AS a
	INNER JOIN {$from_prefix}posts AS p ON (a.attachment_id = p.attachment_id);
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/
TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
SELECT
	user_id AS id_member, topic_id AS id_topic
FROM {$from_prefix}notifications
WHERE notify = '1';
---*

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

---* {$to_prefix}smileys
---{
$no_add = true;
$keys = array('code', 'filename', 'description', 'smpath', 'hidden');

$row['filename'] = preg_replace('~images\/emoticons\/~is', '', $row['filename']);

if (!isset($smf_smileys_directory))
{
	// Find the path for SMF avatars.
	$request = convert_query("
	SELECT value
	FROM {$to_prefix}settings
	WHERE variable = 'smileys_dir'
	LIMIT 1");

	list ($smf_smileys_directory) = convert_fetch_row($request);
	convert_free_result($request);
}

// Enable Custom Smileys if not set already.
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

if (is_file($_POST['path_from'] . '/images/emoticons/'. $row['filename']))
{
	copy($_POST['path_from'] . '/images/emoticons/'. $row['filename'] , $smf_smileys_directory . '/default/'.$row['filename']);
	convert_insert('smileys', array('code' => 'string', 'filename' => 'string', 'description' => 'string', 'hidden' => 'int'),
		array($row['code'], $row['newfilename'], $row['description'], 1), 'ignore'
	);
}
---}
SELECT
	emoticon_url AS filename, emoticon_code AS code, emoticon_name AS description
FROM {$from_prefix}emoticons;
---*