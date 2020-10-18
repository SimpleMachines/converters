/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "MyBulletinBoard 1.8"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/inc/config.php"
---~ globals: config
---~ from_prefix: "`{$config['database']['database']}`.{$config['database']['table_prefix']}"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/



TRUNCATE {$to_prefix}members;
ALTER TABLE {$to_prefix}members
CHANGE COLUMN password_salt password_salt varchar(255) NOT NULL default '';

---* {$to_prefix}members
---{
if (!filter_var($row['member_ip'], FILTER_VALIDATE_IP))
	$row['member_ip'] = @inet_ntop($row['member_ip']);
	
if (!filter_var($row['member_ip2'], FILTER_VALIDATE_IP))	
	$row['member_ip2'] = @inet_ntop($row['member_ip2']);
	
$context['utf8'] = false;
$context['server']['complex_preg_chars'] = false;
$row['real_name'] = trim(preg_replace('~[\t\n\r \x0B\0' . ($context['utf8'] ? ($context['server']['complex_preg_chars'] ? '\x{A0}\x{AD}\x{2000}-\x{200F}\x{201F}\x{202F}\x{3000}\x{FEFF}' : "\xC2\xA0\xC2\xAD\xE2\x80\x80-\xE2\x80\x8F\xE2\x80\x9F\xE2\x80\xAF\xE2\x80\x9F\xE3\x80\x80\xEF\xBB\xBF") : '\x00-\x08\x0B\x0C\x0E-\x19\xA0') . ']+~' . ($context['utf8'] ? 'u' : ''), ' ', $row['real_name']));
	
---}
SELECT
	uid AS id_member, SUBSTRING(username, 1, 255) AS member_name,
	SUBSTRING(username, 1, 255) AS real_name, email AS email_address,
	SUBSTRING(password, 1, 64) AS passwd, SUBSTRING(salt, 1, 8) AS password_salt,
	postnum AS posts, SUBSTRING(usertitle, 1, 255) AS usertitle,
	lastvisit AS last_login, IF(usergroup = 4, 1, 0) AS id_group,
	regdate AS date_registered, SUBSTRING(website, 1, 255) AS website_url,
	SUBSTRING(website, 1, 255) AS website_title,
	SUBSTRING(signature, 1, 65534) AS signature, hideemail AS hide_email,
	SUBSTRING(buddylist, 1, 255) AS buddy_list,
	SUBSTRING(regip, 1, 255) AS member_ip, SUBSTRING(regip, 1, 255) AS member_ip2,
	SUBSTRING(ignorelist, 1, 255) AS pm_ignore_list,
	timeonline AS total_time_logged_in,
	'' AS message_labels, '' AS openid_uri, '' AS location, '' AS avatar, '' AS personal_text,
	'' AS secret_question, '' AS ignore_boards, '' AS additional_groups 
FROM {$from_prefix}users;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT fid AS id_cat, SUBSTRING(name, 1, 255) AS name, disporder AS cat_order
FROM {$from_prefix}forums
WHERE type = 'c';
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

/* The converter will set id_cat for us based on id_parent being wrong. */
---* {$to_prefix}boards
SELECT
	fid AS id_board, SUBSTRING(name, 1, 255) AS name,
	SUBSTRING(description, 1, 65534) AS description, disporder AS board_order,
	posts AS num_posts, threads AS num_topics, pid AS id_parent,
	usepostcounts != 'yes' AS count_posts, '-1,0' AS member_groups
FROM {$from_prefix}forums
WHERE type = 'f';
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
	t.tid AS id_topic, t.fid AS id_board, t.sticky AS is_sticky,
	t.poll AS id_poll, t.views AS num_views, IFNULL(t.uid, 0) AS id_member_started,
	IFNULL(ul.uid, 0) AS id_member_updated, t.replies AS num_replies,
	CASE
		WHEN (t.closed = '1') THEN 1
		ELSE 0
	END AS locked,
	MIN(p.pid) AS id_first_msg, MAX(p.pid) AS id_last_msg
FROM {$from_prefix}threads AS t
	INNER JOIN {$from_prefix}posts AS p
	LEFT JOIN {$from_prefix}users AS ul ON (BINARY ul.username = t.lastposter)
WHERE p.tid = t.tid
GROUP BY t.tid
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
$ignore_slashes = true;
$row['poster_ip'] = @inet_ntop($row['poster_ip']);
---}
SELECT
	p.pid AS id_msg, p.tid AS id_topic, t.fid AS id_board, p.uid AS id_member,
	SUBSTRING(p.username, 1, 255) AS poster_name, p.dateline AS poster_time,
	SUBSTRING(p.ipaddress, 1, 255) AS poster_ip,
	SUBSTRING(IF(p.subject = '', t.subject, p.subject), 1, 255) AS subject,
	SUBSTRING(IF(p.uid > 0, u.email, ''), 1, 255) AS poster_email,
	p.smilieoff = 'no' AS smileys_enabled,
	SUBSTRING(REPLACE(p.message, '<br>', '<br />'), 1, 65534) AS body,
	'xx' AS icon
FROM {$from_prefix}posts AS p
	INNER JOIN {$from_prefix}threads AS t
	LEFT JOIN {$from_prefix}users AS u ON (u.uid = p.uid)
	LEFT JOIN {$from_prefix}users AS edit_u ON (edit_u.uid = p.edituid)
WHERE t.tid = p.tid;
---*

/******************************************************************************/
--- Converting polls...
/******************************************************************************/

TRUNCATE {$to_prefix}polls;
TRUNCATE {$to_prefix}poll_choices;
TRUNCATE {$to_prefix}log_polls;

---* {$to_prefix}polls
SELECT
	p.pid AS id_poll, SUBSTRING(p.question, 1, 255) AS question, p.closed AS voting_locked,
	t.uid AS id_member,
	IF(p.timeout = 0, 0, p.dateline + p.timeout * 86400) AS expire_time,
	SUBSTRING(t.username, 1, 255) AS poster_name
FROM {$from_prefix}polls AS p
	LEFT JOIN {$from_prefix}threads AS t ON (t.tid = p.tid);
---*

/******************************************************************************/
--- Converting poll options...
/******************************************************************************/

---* {$to_prefix}poll_choices
---{
$no_add = true;
$keys = array('id_poll', 'id_choice', 'label', 'votes');

$options = explode('||~|~||', $row['options']);
$votes = explode('||~|~||', $row['votes']);

$id_poll = $row['id_poll'];
for ($i = 0, $n = count($options); $i < $n; $i++)
{
	$rows[] = array(
		'id_poll' => $id_poll,
		'id_choice' => ($i + 1),
		'label' => substr('" . addslashes($options[$i]) . "', 1, 255),
		'votes' => @$votes[$i],
	);
}
---}
SELECT pid AS id_poll, options, votes
FROM {$from_prefix}polls;
---*

/******************************************************************************/
--- Converting poll votes...
/******************************************************************************/

---* {$to_prefix}log_polls
SELECT pid AS id_poll, uid AS id_member, voteoption AS id_choice
FROM {$from_prefix}pollvotes;
---*

/******************************************************************************/
--- Converting personal messages (step 1)...
/******************************************************************************/

TRUNCATE {$to_prefix}personal_messages;

---* {$to_prefix}personal_messages
SELECT
	pm.pmid AS id_pm, pm.fromid AS id_member_from, pm.dateline AS msgtime,
	SUBSTRING(pm.subject, 1, 255) AS subject,
	SUBSTRING(REPLACE(pm.message, '<br>', '<br />'), 1, 65534) AS body
FROM {$from_prefix}privatemessages AS pm
	LEFT JOIN {$from_prefix}users AS uf ON (uf.uid = pm.fromid)
WHERE pm.folder != 2;
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT pmid AS id_pm, toid AS id_member, readtime != 0 AS is_read, '-1' AS labels
FROM {$from_prefix}privatemessages
WHERE folder != 2;
---*

/******************************************************************************/
--- Converting topic notifications...
/******************************************************************************/

TRUNCATE {$to_prefix}log_notify;

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
SELECT uid AS id_member, tid AS id_topic
FROM {$from_prefix}threadsubscriptions;
---*

/******************************************************************************/
--- Converting board notifications...
/******************************************************************************/

---* {$to_prefix}log_notify
---{
$ignore = true;
---}
SELECT uid AS id_member, fid AS id_board
FROM {$from_prefix}forumsubscriptions;
---*

/******************************************************************************/
--- Converting censored words...
/******************************************************************************/

DELETE FROM {$to_prefix}settings
WHERE variable IN ('censor_vulgar', 'censor_proper');

---# Moving censored words...
---{
$result = convert_query("
	SELECT badword, replacement
	FROM {$from_prefix}badwords");
$censor_vulgar = array();
$censor_proper = array();
while ($row = convert_fetch_assoc($result))
{
	$censor_vulgar[] = $row['badword'];
	$censor_proper[] = $row['replacement'];
}
convert_free_result($result);

$censored_vulgar = addslashes(implode("\n", $censor_vulgar));
$censored_proper = addslashes(implode("\n", $censor_proper));

convert_query("
	REPLACE INTO {$to_prefix}settings
		(variable, value)
	VALUES ('censor_vulgar', '$censored_vulgar'),
		('censor_proper', '$censored_proper')");
---}
---#

/******************************************************************************/
--- Converting moderators...
/******************************************************************************/

TRUNCATE {$to_prefix}moderators;

---* {$to_prefix}moderators
SELECT id AS id_member, fid AS id_board
FROM {$from_prefix}moderators;
---*

/******************************************************************************/
--- Converting topic view logs...
/******************************************************************************/

TRUNCATE {$to_prefix}log_topics;

---* {$to_prefix}log_topics
SELECT tid AS id_topic, uid AS id_member
FROM {$from_prefix}threadsread;
---*

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

if (!isset($oldAttachmentDir))
{
	$result = convert_query("
		SELECT value
		FROM {$from_prefix}settings
		WHERE name = 'uploadspath'
		LIMIT 1");
	list ($oldAttachmentDir) = convert_fetch_row($result);
	convert_free_result($result);

	$oldAttachmentDir = $_POST['path_from'] . ltrim($oldAttachmentDir, '.');
}

// Is this an image???
$attachmentExtension = strtolower(substr(strrchr($row['filename'], '.'), 1));
if (!in_array($attachmentExtension, array('jpg', 'jpeg', 'gif', 'png')))
	$attachmentExtension = '';

$oldFilename = $row['attachname'];
$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

if (copy($oldAttachmentDir . '/' . $oldFilename, $attachmentUploadDir . '/' . $physical_filename))
{
	// Set the default empty values.
	$width = 0;
	$height = 0;

	// Is an an image?
	if (!empty($attachmentExtension))
	{
		list ($width, $height) = getimagesize($attachmentUploadDir . '/' . $physical_filename);
		// This shouldn't happen but apparently it might
		if(empty($width))
			$width = 0;
		if(empty($height))
			$height = 0;
	}

	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => $row['filename'],
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => $row['downloads'],
		'width' => $width,
		'height' => $height,
	);

	$id_attach++;
}
---}
SELECT pid AS id_msg, downloads, filename, filesize, attachname
FROM {$from_prefix}attachments;
---*
