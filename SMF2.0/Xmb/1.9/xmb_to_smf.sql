/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "XMB 1.9 Nexus"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/config.php"
---~ defines: IN_CODE
---~ from_prefix: "`$dbname`.$tablepre"
---~ table_test: "{$from_prefix}members"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
// Because this will get slashes removed the extra ones.
$row['signature'] = stripslashes($row['signature']);
---}
SELECT
	uid AS id_member, SUBSTRING(username, 1, 80) AS member_name,
	regdate AS date_registered, postnum AS posts, lastvisit AS last_login,
	SUBSTRING(username, 1, 255) AS real_name,
	SUBSTRING(password, 1, 64) AS passwd,
	SUBSTRING(email, 1, 255) AS email_address,
	SUBSTRING(customstatus, 1, 255) AS personal_text,
	SUBSTRING(site, 1, 255) AS website_title,
	SUBSTRING(site, 1, 255) AS website_url,
	SUBSTRING(location, 1, 255) AS location,
	SUBSTRING(icq, 1, 255) AS icq, SUBSTRING(aim, 1, 16) AS aim,
	SUBSTRING(yahoo, 1, 32) AS yim, SUBSTRING(msn, 1, 255) AS msn,
	IF(showemail = 1, 0, 1) AS hide_email,
	SUBSTRING(sig, 1, 65534) AS signature, SUBSTRING(avatar, 1, 255) AS avatar,
	CASE status
		WHEN 'Super Administrator' THEN 1
		WHEN 'Administrator' THEN 1
		WHEN 'Super Moderator' THEN 2
		ELSE 0
	END AS id_group, '' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list,
	'' AS message_labels, '' AS time_format, '' AS usertitle, '' AS member_ip,
	'' AS secret_question, '' AS secret_answer, '' AS validation_code,
	'' AS additional_groups, '' AS smiley_set, '' AS password_salt,
	'' AS member_ip2
FROM {$from_prefix}members
WHERE uid != 0;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
---{
$row['name'] = stripslashes($row['name']);
---}
SELECT
	fid AS id_cat, SUBSTRING(name, 1, 255) AS name,
	(displayorder + 2) AS cat_order
FROM {$from_prefix}forums
WHERE type = 'group';
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

/* The converter will set id_cat for us based on id_parent being wrong. */
---* {$to_prefix}boards
---{
$row['name'] = stripslashes($row['name']);
---}
SELECT
	fid AS id_board, fup AS id_parent, displayorder AS board_order,
	SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, threads AS num_topics,
	posts AS num_posts, '-1,0,1' AS member_groups
FROM {$from_prefix}forums
WHERE type != 'group';
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
	t.tid AS id_topic, t.topped AS is_sticky, t.fid AS id_board,
	IFNULL(uf.uid, 0) AS id_member_started, t.replies AS num_replies,
	t.views AS num_views,
	CASE WHEN t.closed = 'yes' THEN 1 ELSE 0 END AS locked, MIN(p.pid) AS id_first_msg,
	MAX(p.pid) AS id_last_msg, IF(t.pollopts != '', t.tid, 0) AS id_poll
FROM {$from_prefix}threads AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.tid = t.tid)
	LEFT JOIN {$from_prefix}members AS uf ON (uf.username = t.author)
GROUP BY t.tid
HAVING id_first_msg != 0
	AND id_last_msg != 0;
---*

---* {$to_prefix}topics (update id_topic)
SELECT t.id_topic, uf.uid AS id_member_updated
FROM {$to_prefix}topics AS t
	INNER JOIN {$from_prefix}posts AS p ON (p.pid = t.id_last_msg)
	INNER JOIN {$from_prefix}members AS uf ON (uf.username = p.author);
---*

/******************************************************************************/
--- Converting posts (this may take some time)...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}messages 200
---{
$ignore = true;
$row['subject'] = stripslashes($row['subject']);
$row['body'] = preg_replace('~\[align=(center|right|left)\](.+?)\[/align\]~i', '[$1]$2[/$1]', stripslashes($row['body']));
---}
SELECT
	p.pid AS id_msg, p.tid AS id_topic, p.dateline AS poster_time,
	uf.uid AS id_member, SUBSTRING(p.subject, 1, 255) AS subject,
	SUBSTRING(p.author, 1, 255) AS poster_name,
	SUBSTRING(uf.email, 1, 255) AS poster_email,
	SUBSTRING(p.useip, 1, 255) AS poster_ip, p.fid AS id_board,
	IF(p.smileyoff = 0, 1, 0) AS smileys_enabled,
	SUBSTRING(REPLACE(p.message, '<br>', '<br />'), 1, 65534) AS body,
	'' AS modified_name, 'xx' AS icon
FROM {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}members AS uf ON (uf.username = p.author);
---*

/******************************************************************************/
--- Converting posts (part2)
/******************************************************************************/

---* {$to_prefix}messages (update id_topic)
SELECT p.tid AS id_topic, p.subject
FROM {$from_prefix}posts AS p
WHERE p.subject != '';
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	t.tid AS id_poll, SUBSTRING(t.subject, 1, 255) AS question,
	SUBSTRING(t.author, 1, 255) AS poster_name, uf.uid AS id_member
FROM {$from_prefix}threads AS t
	LEFT JOIN {$from_prefix}members AS uf ON (uf.username = t.author)
WHERE t.pollopts != '';
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$choices = explode('#|#', $row['choices']);
foreach ($choices as $i => $choice)
{
	$choice = explode('||~|~||', $choice);
	if (isset($choice[1]))
		$rows[] = "$row[id_poll], " . ($i + 1) . ", SUBSTRING('" . addslashes(trim($choice[0])) . "', 1, 255), " . (int) trim($choice[1]);
}
---}
SELECT tid AS id_poll, pollopts AS choices
FROM {$from_prefix}threads
WHERE pollopts != '';
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT t.tid AS id_poll, mem.uid AS id_member
FROM {$from_prefix}threads AS t
	INNER JOIN {$from_prefix}members AS mem
WHERE LOCATE(CONCAT(' ', mem.username, ' '), t.pollopts, LENGTH(t.pollopts) - LOCATE('#|#', REVERSE(t.pollopts)) + 2)
	AND t.pollopts != '';
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
---{
$row['subject'] = substr(stripslashes($row['subject']), 0, 255);
$row['body'] = substr(preg_replace('~\[align=(center|right|left)\](.+?)\[/align\]~i', '[$1]$2[/$1]', stripslashes($row['body'])), 0, 65534);
---}
SELECT
	pm.u2uid AS id_pm,
	IFNULL(uf.uid, 0) AS id_member_from,
	pm.dateline AS msgtime,
	SUBSTRING(pm.msgfrom, 1, 255) AS from_name, pm.subject AS subject,
	pm.message AS body
FROM {$from_prefix}u2u AS pm
	LEFT JOIN {$from_prefix}members AS uf ON (uf.username = pm.msgfrom)
	LEFT JOIN {$from_prefix}members AS uf2 ON (uf2.username = pm.msgto)
WHERE pm.folder != 'outbox';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pm.u2uid AS id_pm, uf.uid AS id_member, pm.readstatus = 'yes' AS is_read,
	'-1' AS labels
FROM {$from_prefix}u2u AS pm
	INNER JOIN {$from_prefix}members AS uf ON (uf.username = pm.msgto)
WHERE pm.folder != 'outbox';
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
SELECT uf.uid AS id_member, f.tid AS id_topic
FROM {$from_prefix}favorites AS f
	INNER JOIN {$from_prefix}members AS uf
WHERE uf.username = f.username;
---*

/******************************************************************************/
--- Converting banned users...
/******************************************************************************/

TRUNCATE {$to_prefix}ban_items;
TRUNCATE {$to_prefix}ban_groups;

---* {$to_prefix}ban_groups
---{
// Give the ban a unique name.
$group_count = isset($group_count) ? $group_count + 1 : $_REQUEST['start'] + 1;
$row['name'] .= $group_count;
$row['id_ban_group'] = $group_count;
---}
SELECT
	'Migrated_' AS name, dateline AS ban_time, 'Migrated from XMB' AS notes,
	1 AS cannot_access, '' AS reason
FROM {$from_prefix}banned;
---*

---* {$to_prefix}ban_items
---{
// Check we give a valid ban group.
$item_count = isset($item_count) ? $item_count + 1 : $_REQUEST['start'] + 1;
$row['id_ban_group'] = $item_count;
---}
SELECT
	ip1 AS ip_low1, ip1 AS ip_high1, ip2 AS ip_low2, ip2 AS ip_high2,
	ip3 AS ip_low3, ip3 AS ip_high3, ip4 AS ip_low4, ip4 AS ip_high4,
	'' AS email_address, '' AS hostname
FROM {$from_prefix}banned;
---*

/******************************************************************************/
--- Converting settings...
/******************************************************************************/

---# Converting settings...
---{
$result = convert_query("
	SELECT
		hottopic AS hotTopicPosts, postperpage AS defaultMaxMessages,
		topicperpage AS defaultMaxTopics, memberperpage AS defaultMaxMembers,
		floodctrl AS spamWaitTime, tickercontents AS news
	FROM {$from_prefix}settings");
$row = convert_fetch_assoc($result);
convert_free_result($result);

$settings = array();
foreach ($row as $key => $value)
	$settings[] = array(addslashes($key), substr(addslashes($value), 0, 65534));

if (!empty($settings))
	convert_insert('settings', array('variable', 'value'), $settings, 'replace');
---}
---#

---# Moving file type settings...
---{
$result = convert_query("
	SELECT
		bbstatus = 'off' AS maintenance, bbname AS mbname,
		adminemail AS webmaster_email
	FROM {$from_prefix}settings");

$row = convert_fetch_assoc($result);
$settings = array();
foreach ($row as $key => $value)
	$settings[$key] = "'$value'";

updateSettings($settings);

convert_free_result($result);
---}
---#

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT u.uid AS id_member, f.fid AS id_board
FROM {$from_prefix}forums AS f
	INNER JOIN {$from_prefix}members AS u
WHERE f.moderator != ''
	AND FIND_IN_SET(u.username, f.moderator);
---*

/******************************************************************************/
--- Converting smileys...
/******************************************************************************/

UPDATE {$to_prefix}smileys
SET hidden = 1;

---{
$specificSmileys = array(
	':)' => 'smiley',
	':(' => 'sad',
	':D' => 'grin',
	';)' => 'wink',
	':cool:' => 'cool',
	':mad:' => 'angry',
	':o' => 'shocked',
	':P' => 'tongue',
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

	$count++;
	$rows[] = array($code, $name . '.gif', $name, $count);
}

if (!empty($rows))
	convert_insert('smileys', array('code', 'filename', 'description', 'smiley_order'), $rows, 'replace');
---}

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

$fp = @fopen($attachmentUploadDir . '/' . $physical_filename, 'wb');
if (!$fp)
	return;

// XMB encodes several filetypes so we are going to do the opposite - by the same method!!
$toConvert = array('exe', 'bz', 'tar', 'zip', 'gz', 'bz2');
if (in_array(substr(strrchr($row['filename'], '.'), 1), $toConvert))
	$row['filedata'] = base64_decode($row['filedata']);

fwrite($fp, $row['filedata']);
fclose($fp);

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
	pid AS id_msg, attachment AS filedata, downloads AS downloads,
	filename AS filename
FROM {$from_prefix}attachments;
---*