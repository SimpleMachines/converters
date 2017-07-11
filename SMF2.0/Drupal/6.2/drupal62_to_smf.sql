---~ name: "Drupal 6.2 "
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/drupal_migration.php"
---~ from_prefix: "`" . $drupal_database . "`.$drupal_prefix"
---~ table_test: "{$from_prefix}users"

/******************************************************************************/
--- Converting members...
/******************************************************************************/
TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
$ignore = true;
---}
SELECT
	uid AS id_member, SUBSTRING(name, 1, 255) AS member_name,
	SUBSTRING(name, 1, 255) AS real_name, mail AS email_address,
	pass AS passwd, '' AS lngfile, '' AS buddy_list,
	'' AS pm_ignore_list, '' AS message_labels, '' AS personal_text,
	'' AS website_title, '' AS website_url, '' AS location, '' AS icq, '' AS aim,
	'' AS msn, '' AS usertitle, '' AS member_ip, '' AS member_ip2, '' AS secret_question,
	'' AS additional_groups,
	access AS last_login,
	IF(uid = '1' , 1, 0) AS id_group,
		created AS date_registered, '' AS avatar,
	SUBSTRING(signature, 1, 65534) AS signature
FROM {$from_prefix}users where uid > 0;
---*
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT u.uid AS id_member
		FROM {$from_prefix}users AS u
			LEFT JOIN {$from_prefix}users_roles AS r ON (u.uid=r.uid)
			INNER JOIN {$from_prefix}permission AS p ON (r.rid=p.rid)
		WHERE p.perm LIKE '%administer forums%'
		LIMIT $_REQUEST[start], 250");
	while ($row = convert_fetch_assoc($result))
	{
		convert_query("
			UPDATE {$to_prefix}members
			SET id_group= 1
			WHERE id_member = $row[id_member]
			LIMIT 1");
	}

	$_REQUEST['start'] += 250;
	if (convert_num_rows($result) < 250)
		break;

	convert_free_result($result);
}

$_REQUEST['start'] = 0;
---}

/******************************************************************************/
--- Converting categories...
/******************************************************************************/
TRUNCATE {$to_prefix}categories;

---{
$no_add = true;
$keys = array('id_cat', 'name', 'cat_order');

$request = convert_query("
	SELECT value
	FROM {$from_prefix}variable
	WHERE name ='forum_containers'
	LIMIT 1");
list($containers) = convert_fetch_row($request);
convert_free_result($request);
$cont = unserialize($containers);

foreach ($cont as $categories)
{

	$request = convert_query("
		SELECT name
		FROM {$from_prefix}term_data
		WHERE tid = $categories
		LIMIT 1");
	list($name) = convert_fetch_row($request);
	convert_free_result($request);

	convert_insert('categories', array('id_cat', 'name', 'catorder'),
		array($categories, $name ,0)
	);
}
---}

---{
$no_add = true;
$keys = array('id_cat', 'cat_order');
$neworder = -1;

$request = convert_query("
	SELECT c.id_cat AS id_cat
	FROM {$to_prefix}categories AS c
	INNER JOIN {$from_prefix}term_data AS t ON (c.id_cat = t.tid)
	ORDER BY t.weight ASC, c.name ASC");

while ($row= convert_fetch_assoc($request))
	convert_query("
		UPDATE {$to_prefix}categories
		SET cat_order = " . ++$neworder . "
		WHERE id_cat = $row[id_cat]");
convert_free_result($request);
---}

/******************************************************************************/
--- Converting boards...
/******************************************************************************/
TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
---{
$no_add = true;
$keys = array('id_board', 'name', 'description', 'id_parent', 'id_cat');

convert_insert('boards', array('id_board', 'name', 'description', 'id_parent', 'id_cat'),
	array($row['id_board'], $row['name'], $row['description'], $row['id_parent'], $row['id_cat']),
	'insert ignore');
---}

SELECT t.tid AS id_board, SUBSTRING(t.name, 1, 255) AS name, SUBSTRING(t.description, 1, 255) AS description,
	IF(h.parent=c.id_cat, 0, h.parent) AS id_parent,
	IF(c.id_cat IS NULL , 0, c.id_cat) AS id_cat
FROM {$from_prefix}term_data AS t
	INNER JOIN {$from_prefix}term_hierarchy AS h ON (t.tid = h.tid)
	LEFT JOIN {$to_prefix}categories AS c ON (h.parent = c.id_cat);
---*

---{
$no_add = true;
$keys = array('id_cat', 'name', 'cat_order');

$request = convert_query("
	SELECT value
	FROM {$from_prefix}variable
	WHERE name ='forum_containers'
	LIMIT 1");
list($containers) = convert_fetch_row($request);
convert_free_result($request);
$cont = unserialize($containers);

foreach ($cont as $categories)
{
	$request = convert_query("
		SELECT name
		FROM {$from_prefix}term_data
		WHERE tid = $categories
		LIMIT 1");
	list($name) = convert_fetch_row($request);
	convert_free_result($request);

	convert_query("
		DELETE FROM {$to_prefix}boards
		WHERE id_board = $categories ");
	}
---}

---{
$no_add = true;
$keys = array('id_board', 'board_order');
$neworder = -1;

$request = convert_query("
	SELECT b.id_board AS id_board
	FROM {$to_prefix}boards AS b
		INNER JOIN {$from_prefix}term_data AS t ON (b.id_board = t.tid)
	ORDER BY t.weight ASC, b.name ASC");

while ($row= convert_fetch_assoc($request))
	convert_query("
		UPDATE {$to_prefix}boards
		SET board_order = " . ++$neworder . "
		WHERE id_board = $row[id_board]");
convert_free_result($request);

---}

/******************************************************************************/
--- Converting topics...
/******************************************************************************/
TRUNCATE {$to_prefix}topics;
TRUNCATE {$to_prefix}log_topics;
TRUNCATE {$to_prefix}log_boards;
TRUNCATE {$to_prefix}log_mark_read;

---* {$to_prefix}topics
---{
/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
/*
Actually its not a mysql specific query, but why are we doing this?
Just letting the select do its work would be a better option here
*/
$no_add = true;

convert_insert('topics', array('id_topic' => 'int', 'id_board' => 'int', 'is_sticky' => 'int', 'id_first_msg' => 'int', 'id_last_msg' => 'int', 'id_member_started' => 'int', 'id_member_updated' => 'int'),
	array($row['id_topic'], $row['id_board'], $row['is_sticky'], $row['id_first_msg'], $row['id_last_msg'], $row['id_member_started'], $row['id_member_updated'])
);
---}

SELECT
	t.nid AS id_topic, f.tid AS id_board, t.sticky AS is_sticky,
	t.nid AS id_first_msg,
	IF (MAX(c.nid)>0, MAX(c.nid), t.nid) AS id_last_msg,
	t.uid AS id_member_started,
	IF (MAX(c.uid)>0, MAX(c.uid), t.uid) AS id_member_updated
FROM {$from_prefix}node AS t
	INNER JOIN {$from_prefix}forum AS f ON (f.nid = t.nid)
	LEFT JOIN {$from_prefix}comments AS c ON (c.nid = t.nid)
WHERE t.type='forum'
GROUP BY t.nid;
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
		'~<p>~',
		'~</p>~',
		'~<a href=(.+?)>(.+?)</a>~',
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
		'~<dd>~',
		'~</dd>~',
		'~<dl>~',
		'~</dl>~',
		'~<dt>~',
		'~</dt>~',
		'~<cite>~',
		'~</cite>~',
		'~<\?php~',
		'~\?>~',
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
		'',
		'',
		'',
		'',
		'',
		'',
		'[quote]',
		'[/quote]',
		'[code]&lt;?php',
		'?&gt;[/code]',
	),
	trim($row['body'])
);
---}

SELECT
	p.nid AS id_msg, p.nid AS id_topic, f.tid AS id_board, p.uid AS id_member,
	p.timestamp AS poster_time,
	t.title AS subject,
	p.body AS body,
	u.name AS poster_name, '' as poster_ip, '' as modified_name,
	u.mail AS poster_email,
	'xx' AS icon
FROM {$from_prefix}node_revisions AS p
	INNER JOIN {$from_prefix}node AS t ON (p.nid = t.nid)
	INNER JOIN {$from_prefix}forum AS f ON (t.nid = f.nid)
	INNER JOIN {$from_prefix}users AS u ON (u.uid = t.uid)
WHERE t.type='forum';
---*

/******************************************************************************/
--- Converting posts - Part 2(this may take some time)...
/******************************************************************************/

---* {$to_prefix}messages 200
SELECT
	p.nid AS id_topic, f.tid AS id_board, c.uid AS id_member,
	c.timestamp AS poster_time,
	c.subject AS subject,
	c.comment AS body, '' AS poster_ip, '' AS modified_name,
	c.name AS poster_name,
	u.mail AS poster_email,
	'xx' AS icon
FROM {$from_prefix}comments AS c
	INNER JOIN {$from_prefix}node AS t ON (c.nid = t.nid)
	INNER JOIN {$from_prefix}node_revisions AS p ON (p.nid = t.nid)
	INNER JOIN {$from_prefix}forum AS f ON (t.nid = f.nid)
	INNER JOIN {$from_prefix}users AS u ON (u.uid=c.uid)
WHERE t.type='forum'
ORDER BY c.cid;
---*

---# Get all the members posts...
---{
while (true)
{
	pastTime($substep);

	$result = convert_query("
		SELECT m.id_member, COUNT(m.id_msg) AS posts
		FROM {$to_prefix}messages AS m
			INNER JOIN {$to_prefix}boards AS b ON (m.id_board = b.id_board)
		WHERE b.count_posts = 0
		GROUP BY m.id_member
		LIMIT $_REQUEST[start], 250");
	while ($row = convert_fetch_assoc($result))
	{
		$row['posts'] = (int) $row['posts'];

		convert_query("
			UPDATE {$to_prefix}members
			SET posts = " . (int) $row['posts'] . "
			WHERE id_member = $row[id_member]
			LIMIT 1");
	}

	$_REQUEST['start'] += 250;
	if (convert_num_rows($result) < 250)
		break;

	convert_free_result($result);
}

$_REQUEST['start'] = 0;
---}
---#

/******************************************************************************/
--- Converting attachments...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;

$file_hash = getAttachmentFilename(basename($row['filename']), $id_attach, null, true);
$physical_filename = $id_attach . '_' . $file_hash;

if (strlen($physical_filename) > 255)
	return;

$oldfile = $_POST['path_from'] . '/' . $row['filepath'];
if (file_exists($oldfile) && copy($_POST['path_from'] . '/'.$row['filepath'], $attachmentUploadDir . '/' . $physical_filename))
{
	@touch($attachmentUploadDir . '/' . $physical_filename, filemtime($row['filename']));
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => basename($row['filename']),
		'file_hash' => $file_hash,
		'id_msg' => $row['id_msg'],
		'downloads' => 0,
	);

	$id_attach++;
}
---}

SELECT u.nid AS id_msg, f.filename, f.filepath
FROM {$from_prefix}upload AS u
	LEFT JOIN {$from_prefix}files AS f ON (u.fid = f.fid);
---*

/******************************************************************************/
--- Converting avatars...
/******************************************************************************/

---* {$to_prefix}attachments
---{
$no_add = true;
$filepath = $row['picture'];
$row['filename'] = substr(strrchr($row['picture'], '/'), 1);
$file_hash = 'avatar_' . $row['id_member'] . strrchr($row['filename'], '.');
if (copy($_POST['path_from'] . '/' . $filepath , $attachmentUploadDir . '/' . $physical_filename))
{
	$rows[] = array(
		'id_attach' => $id_attach,
		'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
		'filename' => basename($row['filename']),
		'file_hash' => $file_hash,
		'id_member' => $row['id_member'],
	);
	$id_attach++;
}
---}

SELECT uid AS id_member, picture
FROM {$from_prefix}users
WHERE picture != '';
---*