/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "THWBoard 3.x "
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/inc/config.inc.php"
---~ from_prefix: "`" . $mysql_db . "`.$pref"
---~ table_test: "{$from_prefix}user"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;
TRUNCATE {$to_prefix}attachments;

---* {$to_prefix}members
---{
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
		'~\[noparse\]~is',
		'~\[/noparse\]~is',

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
		'',
		'',
	),
	trim($row['signature'])
);

//this is done in a seperate step, we dont want to destroy the BBCODEs
$row['signature'] = htmlspecialchars($row['signature']);
---}
SELECT
	userid AS id_member, SUBSTRING(username, 1, 255) AS member_name,
	SUBSTRING(username, 1, 255) AS real_name, useremail AS email_address,
	SUBSTRING(userpassword, 1, 60) AS passwd, userposts AS posts,
	SUBSTRING(usertitle, 1, 255) AS usertitle,
	userlocation AS location, userlastpost AS last_login,
	IF(userisadmin = '1', 1, 0) AS id_group, userjoin AS date_registered,
	SUBSTRING(userhomepage, 1, 255) AS website_url, useravatar AS avatar,
	SUBSTRING(userhomepage, 1, 255) AS website_title, SUBSTRING(usericq, 1, 255) AS icq,
	SUBSTRING(useraim, 1, 16) AS aim, '' AS yim, userinvisible AS show_online,
	SUBSTRING(usermsn, 1, 255) AS msn, SUBSTRING(usersignature, 1, 65534) AS signature,
	userhideemail AS hide_email, '' AS total_time_logged_in,
	IF(useractivate = '0', 1, 0) AS is_activated, userbday AS birthdate
FROM {$from_prefix}user;
---*

/******************************************************************************/
--- Converting categories...
/******************************************************************************/

TRUNCATE {$to_prefix}categories;

---* {$to_prefix}categories
SELECT
	categoryid AS id_cat, categoryname AS name, categoryorder AS cat_order
FROM {$from_prefix}category;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;
DELETE FROM {$to_prefix}board_permissions
WHERE id_profile > 4;

---* {$to_prefix}boards
SELECT
	boardid AS id_board, SUBSTRING(boardname, 1, 255) AS name, '-1,0,1,2' AS member_groups,
	SUBSTRING(boarddescription, 1, 65534) AS description, boardorder AS board_order,
	boardposts AS num_posts, boardthreads AS num_topics, categoryid AS id_cat
FROM {$from_prefix}board;
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
	t.threadid AS id_topic, t.boardid AS id_board,
	t.threadtop AS is_sticky, t.threadviews AS num_views,
	u.userid AS id_member_started,
	r.userid AS id_member_updated,
	MIN(p.postid) AS id_first_msg, MAX(p.postid) AS id_last_msg,
	t.threadviews AS num_replies, 	t.threadclosed AS locked
FROM {$from_prefix}thread AS t
	LEFT JOIN {$from_prefix}user AS u ON (t.threadauthor = u.username)
	INNER JOIN {$from_prefix}post AS p ON (p.threadid=t.threadid)
	LEFT JOIN {$from_prefix}user AS r ON (t.threadlastreplyby = r.userid)
GROUP BY t.threadid
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
		'~\[noparse\]~is',
		'~\[/noparse\]~is',

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
		'',
		'',
	),
	trim($row['body'])
);

//this is done in a seperate step, we dont want to destroy the BBCODEs
$row['body'] = htmlspecialchars($row['body']);
---}
SELECT
	p.postid AS id_msg, p.threadid AS id_topic,
	t.boardid AS id_board, p.posttime AS poster_time,
	p.userid AS id_member,	p.postlastedittime AS id_msg_MODIFIED,
	t.threadtopic AS subject,
	IF(p.postguestname != '',p.postguestname, u.username) AS poster_name,
	u.useremail AS poster_email,	p.postip AS poster_ip,
	p.postsmilies AS smileys_enabled, p.postlastedittime AS modified_time,
	p.postlasteditby AS modified_name, p.posttext AS body, 'xx' AS icon
FROM {$from_prefix}post AS p
	INNER JOIN {$from_prefix}thread AS t ON (t.threadid = p.threadid)
	LEFT JOIN {$from_prefix}user AS u ON (u.userid = p.userid)
GROUP BY p.postid;
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
		'~\[noparse\]~is',
		'~\[/noparse\]~is',

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
		'',
		'',
	),
	trim($row['body'])
);

//this is done in a seperate step, we dont want to destroy the BBCODEs
$row['body'] = htmlspecialchars($row['body']);
---}
SELECT
	pm.pmid AS id_pm, pm.pmfromid AS id_member_from, pm.pmtime AS msgtime,
	IF(u.username IS NULL, 'Guest', SUBSTRING(u.username, 1, 255)) AS from_name,
	SUBSTRING(pm.pmtopic, 1, 255) AS subject,
	SUBSTRING(pm.pmtext, 1, 65534) AS body
FROM {$from_prefix}pm AS pm
	LEFT JOIN {$from_prefix}user AS u ON (u.userid=pm.pmfromid)
WHERE pmfolder ='0';
---*

/******************************************************************************/
--- Converting personal messages (step 2)...
/******************************************************************************/

TRUNCATE {$to_prefix}pm_recipients;

---* {$to_prefix}pm_recipients
SELECT
	pmid AS id_pm, pmtoid AS id_member, '1' AS is_read,
	'' AS deleted, '-1' AS labels
FROM {$from_prefix}pm;
---*