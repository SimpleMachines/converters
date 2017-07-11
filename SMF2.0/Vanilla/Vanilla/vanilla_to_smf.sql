/* ATTENTION: You don't need to run or use this file!  The convert.php script does everything for you! */

/******************************************************************************/
---~ name: "Vanilla"
/******************************************************************************/
---~ version: "SMF 2.0"
---~ settings: "/conf/database.php", "/conf/settings.php"
---~ from_prefix: "`$Configuration[DATABASE_NAME]`.$Configuration[DATABASE_TABLE_PREFIX]"
---~ table_test: "{$from_prefix}User"

/******************************************************************************/
--- Converting members...
/******************************************************************************/

TRUNCATE {$to_prefix}members;

---* {$to_prefix}members
---{
$row['date_registered'] = strtotime($row['date_registered']);
$row['last_login'] = strtotime($row['last_login']);
$row['real_name'] = trim($row['real_name']) == '' ? $row['member_name'] : $row['real_name'];
---}
SELECT
	m.UserID AS id_member, m.Name as member_name, m.DateFirstVisit AS date_registered,
	(m.CountDiscussions + m.CountComments) AS posts, m.DateLastActive AS last_login,
	CASE m.RoleID WHEN 4 THEN 1 ELSE 0 END AS id_group, m.Password AS passwd,
	CONCAT_WS(' ', m.FirstName, m.LastName) AS real_name, m.Email AS email_address,
	CASE m.UtilizeEmail WHEN 1 THEN 0 ELSE 1 END as hide_email, m.Picture AS avatar,
	m.RemoteIp AS member_ip, m.RemoteIp AS member_ip2, '' AS password_salt,
	'' AS lngfile, '' AS buddy_list, '' AS pm_ignore_list, '' AS message_labels,
	'' AS personal_text, '' AS time_format, '' AS usertitle, '' AS secret_question,
	'' AS secret_answer, '' AS validation_code, '' AS additional_groups, '' AS smiley_set
FROM {$from_prefix}User AS m;
---*

/******************************************************************************/
--- Converting boards...
/******************************************************************************/

TRUNCATE {$to_prefix}boards;

---* {$to_prefix}boards
SELECT
	c.CategoryID AS id_board, 1 AS id_cat, 0 AS id_parent, 0 AS num_posts,
	0 AS num_topics, '-1,0' AS member_groups, SUBSTRING(c.Name, 1, 255) AS name,
	SUBSTRING(c.Description, 1, 65534) AS description, c.Priority AS board_order
FROM {$from_prefix}Category AS c;
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
	t.DiscussionID AS id_topic, t.Sticky AS is_sticky, t.CategoryID AS id_board,
	MIN(p.CommentID) AS id_first_msg, MAX(p.CommentID) AS id_last_msg,
	t.AuthUserID AS id_member_started, t.LastUserID AS id_member_updated,
	t.CountComments AS num_replies, t.Closed AS locked
FROM {$from_prefix}Discussion AS t
	LEFT JOIN {$from_prefix}Comment AS p ON (p.DiscussionID = t.DiscussionID)
GROUP BY p.DiscussionID;
---*

/******************************************************************************/
--- Converting posts...
/******************************************************************************/

TRUNCATE {$to_prefix}messages;

---* {$to_prefix}messages 200
---{
$row['poster_time'] = strtotime($row['poster_time']);
$row['modified_time'] = is_null($row['modified_time']) ? 0 : strtotime($row['modified_time']);
$row['modified_name'] = is_null($row['modified_name']) ? '' : $row['modified_name'];
---}
SELECT
	p.CommentID AS id_msg, p.DiscussionID AS id_topic, t.CategoryID AS id_board,
	p.DateCreated AS poster_time, p.AuthUserID AS id_member, t.Name AS subject,
	m.Name AS poster_name, m.Email AS poster_email, p.RemoteIp AS poster_ip,
	p.DateEdited AS modified_time, m2.Name AS modified_name, p.Body AS body
FROM {$from_prefix}Comment AS p
	LEFT JOIN {$from_prefix}Discussion AS t ON (t.DiscussionID = p.DiscussionID)
	LEFT JOIN {$from_prefix}User AS m ON (m.UserID = p.AuthUserID)
	LEFT JOIN {$from_prefix}User AS m2 ON (m2.UserID = p.EditUserID)
WHERE p.CommentID > 0;
---*

/******************************************************************************/
--- Converting settings...
/******************************************************************************/

---{
$settings = array();

//SMTP?
if (isset($Configuration['SMTP_HOST']))
{
	$settings['smtp_host'] = $Configuration['SMTP_HOST'];
	$settings['mail_type'] = '1';
}
if (isset($Configuration['SMTP_USER']))
	$settings['smtp_username'] = $Configuration['SMTP_USER'];
if (isset($Configuration['SMTP_PASSWORD']))
	$settings['smtp_password'] = $Configuration['SMTP_PASSWORD'];

// Direct registration?
if (empty($Configuration['ALLOW_IMMEDIATE_ACCESS']))
	$settings['registration_method'] = '2';
// Post length?
if (isset($Configuration['MAX_COMMENT_LENGTH']))
	$settings['max_messageLength'] = $Configuration['MAX_COMMENT_LENGTH'];
// Topics per page?
if (isset($Configuration['DISCUSSIONS_PER_PAGE']))
	$settings['defaultMaxTopics'] = $Configuration['DISCUSSIONS_PER_PAGE'];
// Messages per page?
if (isset($Configuration['COMMENTS_PER_PAGE']))
	$settings['defaultMaxMessages'] = $Configuration['COMMENTS_PER_PAGE'];
// Search results per page?
if (isset($Configuration['SEARCH_RESULTS_PER_PAGE']))
	$settings['search_results_per_page'] = $Configuration['SEARCH_RESULTS_PER_PAGE'];

$inserts = array();
foreach ($settings as $variable => $value)
	$inserts[] = "('$variable', '$value')";

if (!empty($inserts))
	convert_query("
		REPLACE INTO {$to_prefix}settings
			(variable, value)
		VALUES " . implode(',
			', $inserts));
---}