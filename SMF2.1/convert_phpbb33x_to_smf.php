<?php

/**
 * Simple Machines Forum (SMF)
 *
 * @package SMF
 * @author Simple Machines https://www.simplemachines.org
 * @copyright 2022 Simple Machines
 * @license https://www.simplemachines.org/about/smf/license.php BSD
 *
 * @version 2.1
 */
if (basename($_SERVER['PHP_SELF']) === basename(__FILE__))
{
	$secure = false;
	if (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] == 'on')
		$secure = true;
	elseif (!empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' || !empty($_SERVER['HTTP_X_FORWARDED_SSL']) && $_SERVER['HTTP_X_FORWARDED_SSL'] == 'on')
		$secure = true;

	if (file_exists(dirname(__FILE__) . '/convert.php'))
		header('Location: http' . ($secure ? 's' : '') . '://' . (empty($_SERVER['HTTP_HOST']) ? $_SERVER['SERVER_NAME'] . (empty($_SERVER['SERVER_PORT']) || $_SERVER['SERVER_PORT'] == '80' ? '' : ':' . $_SERVER['SERVER_PORT']) : $_SERVER['HTTP_HOST']) . (strtr(dirname($_SERVER['PHP_SELF']), '\\', '/') == '/' ? '' : strtr(dirname($_SERVER['PHP_SELF']), '\\', '/')) . '/convert.php?convert_script=' . basename(__FILE__));
	else
		die('This tool requires convert.php to function, please place convert.php in the same directory as this script.');
}

class phpbb33x_to_smf extends ConverterBase
{
	public static bool $purge = false;

	public static function info(): array
	{
		return [
			'name' => 'phpBB 3.3',
			'version' => 'SMF 2.1.*',
			'settings' => ['/config.php'],
			'defines' => ['IN_PHPBB'],
			'globals' => ['dbhost', 'dbname', 'dbname', 'dbuser', 'dbpasswd', 'table_prefix'],
			'from_prefix' => '`$dbname`.$table_prefix',
			'test_table' => '{from_prefix}users',
			'parameters' => [
				[
					'id' => 'purge',
					'type' => 'checked',
					'label' => 'Clear current SMF posts and members during conversion.',
				],
			],
		];
	}

	public static function stepWeights(): array
	{
		return [
			'convertStep1' => 1, // Converting ranks
			'convertStep2' => 3, // Converting groups
			'convertStep3' => 17, // Converting members
			'convertStep4' => 4, // Converting additional member groups
			'convertStep5' => 2, // Converting categories
			'convertStep6' => 6, // Converting boards
			'convertStep7' => 2, // Fixing categories
			'convertStep8' => 10, // Converting topics
			'convertStep9' => 27, // Converting messages
			'convertStep10' => 3, // Converting polls
			'convertStep11' => 3, // Converting poll options
			'convertStep12' => 3, // Converting poll votes
			'convertStep13' => 4, // Converting personal messages (part 1)
			'convertStep14' => 5, // Converting personal messages (part 2)
			'convertStep15' => 6, // Converting attachments
			'convertStep16' => 2, // Converting PM notifications
		];
	}

	public static function connectDb(): object
	{
		global $dbhost, $dbname, $dbuser, $dbpasswd, $table_prefix, $dbport;

		return smf_db_initiate($dbhost, $dbname, $dbuser, $dbpasswd, $table_prefix, ['port' => $dbport]);
	}

	public static function prepareSystem(): void
	{
		parent::prepareSystem();

		self::$purge = Converter::getParameter('purge') ?? false;
	}

	public static function fixBBC(string $msg): string
	{
		$msg = preg_replace(
		[
			'~\[quote=&quot;(.+?)&quot;(:.+?)?\]~is',
			'~\[quote(:.+?)?\]~is',
			'~\[/quote(:.+?)?\]~is',
			'~\[b(:.+?)?\]~is',
			'~\[/b(:.+?)?\]~is',
			'~\[i(:.+?)?\]~is',
			'~\[/i(:.+?)?\]~is',
			'~\[u(:.+?)?\]~is',
			'~\[/u(:.+?)?\]~is',
			'~\[url:(.+?)\]~is',
			'~\[/url:(.+?)?\]~is',
			'~\[url=(.+?):(.+?)\]~is',
			'~\[/url:(.+?)?\]~is',
			'~\<a(.+?) href="(.+?)">(.+?)</a>~is',
			'~\[img:(.+?)?\]~is',
			'~\[/img:(.+?)?\]~is',
			'~\[size=(.+?):(.+?)\]~is',
			'~\[/size(:.+?)?\]~is',
			'~\[color=(.+?):(.+?)\]~is',
			'~\[/color(:.+?)?\]~is',
			'~\[code=(.+?):(.+?)?\]~is',
			'~\[code(:.+?)?\]~is',
			'~\[/code(:.+?)?\]~is',
			'~\[list=(.+?):(.+?)?\]~is',
			'~\[list(:.+?)?\]~is',
			'~\[/list(:.+?)?\]~is',
			'~\[\*(:.+?)?\]~is',
			'~\[/\*(:.+?)?\]~is',
			'~<!-- (.+?) -->~is',
			'~<img src="{SMILIES_PATH}/(.+?)/(.+?)" alt="(.+?)" title="(.+?)" />~is',
		],
		[
			'[quote author="$1"]',
			'[quote]',
			'[/quote]',
			'[b]',
			'[/b]',
			'[i]',
			'[/i]',
			'[u]',
			'[/u]',
			'[url]',
			'[/url]',
			'[url=$1]',
			'[/url]',
			'[url=$2]$3[/url]',
			'[img]',
			'[/img]',
			'[size=' . static::convertPercent2px("\1") . 'px]',
			'[/size]',
			'[color=$1]',
			'[/color]',
			'[code=$1]',
			'[code]',
			'[/code]',
			'[list type=$1]',
			'[list]',
			'[/list]',
			'[li]',
			'[/li]',
			'',
			'$3',
		],
		$msg);

		$msg = preg_replace('~\[size=(.+?)px\]~is', "[size=" . ('\1' > '99' ? 99 : '"\1"') . "px]", $msg);

		// This just does the stuff that it isn't work parsing in a regex.
		return strtr($msg, [
			'[list type=1]' => '[list type=decimal]',
			'[list type=a]' => '[list type=lower-alpha]',
		]);
	}

	public static string	$convertStep1info = 'Converting ranks';
	public static function	 convertStep1(): array
	{
		return [
			'purge' => [
				'query' => '
					DELETE FROM {to_prefix}membergroups
					WHERE id_group > 8',
				'resetauto' => '{to_prefix}membergroups',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}membergroups WHERE id_group > 8',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}ranks'
			],
			'pre_process' => function(){
				if (!isset($_SESSION['convert_num_stars']))
				{
					$_SESSION['convert_num_stars'] = 1;

					ConverterDb::query('
						DELETE FROM {to_prefix}membergroups
						WHERE min_posts != -1
							AND id_group > 4');
				}
			},
			'process' => [
				'table' => '{to_prefix}membergroups',
				'parse' => function (&$row) {
					if ($row['min_posts'] > -1)
					{
						$row['stars'] = sprintf('%d#icon.png', $_SESSION['convert_num_stars']);
						if ($_SESSION['convert_num_stars'] < 5)
							$_SESSION['convert_num_stars']++;
					}
				},
				'query' => '
					SELECT
						SUBSTRING(CONCAT({string:phpbb_title}, rank_title), 1, 255) AS group_name,
						rank_image AS icons, {empty} AS description, IF(rank_special = 0, rank_min, -1) AS min_posts,
						{empty} AS online_color
					FROM {from_prefix}ranks
					ORDER BY rank_min',
				'params' => [
					'phpbb_title' => 'phpBB '
				],
			],
		];
	}

	public static string	$convertStep2info = 'Converting groups';
	public static function	 convertStep2(): array
	{
		return [
			'progress' => [
				'progress_query' => 'SELECT COUNT(*)-{int:offset} FROM {to_prefix}membergroups WHERE id_group > 8',
				'progress_params' => ['offset' => $_SESSION['progress_ranks'] ?? 0],
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}groups'
			],
			'pre_process' => function() {
				if (!isset($_SESSION['progress_ranks']))
				{
					$result = ConverterDb::query('SELECT COUNT(*) FROM {to_prefix}membergroups WHERE id_group > 8');
					list($_SESSION['progress_ranks']) = ConverterDb::db_fetch_row($result);
					ConverterDb::free_result($result);
				}
			},
			'process' => [
				'table' => '{to_prefix}membergroups',
				'query' => '
					SELECT
						SUBSTRING(CONCAT({string:phpbb_title}, group_name), 1, 255) AS group_name,
					-1 AS min_posts, {empty}  AS icons, {empty}  AS description, group_colour AS online_color
					FROM {from_prefix}groups
					WHERE group_id NOT IN (1, 6)',
				'params' => [
					'phpbb_title' => 'phpBB '
				],
			],
		];
	}

	public static string	$convertStep3info = 'Converting members';
	public static function	 convertStep3(): array
	{
		return [
			'purge' => [
				'query' => [
					'TRUNCATE {to_prefix}members',
					'TRUNCATE {to_prefix}attachments'
				],
				'resetauto' => [
					'{to_prefix}members',
					'{to_prefix}attachments',
				],
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}members',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}users'
			],
			'pre_process' => function() {
				global $_confs;

				$request = ConverterDb::query('
					SELECT config_value
					FROM {from_prefix}config
					WHERE config_name = {literal:board_timezone}
					LIMIT 1');
				list ($_confs['board_timezone']) = ConverterDb::fetch_row($request);
				ConverterDb::free_result($request);

				// Find out where uploaded avatars go
				$request = ConverterDb::query('
					SELECT value
					FROM {to_prefix}settings
					WHERE variable = {literal:custom_avatar_enabled}
					LIMIT 1');
				if (ConverterDb::num_rows($request) > 0)
					list ($_confs['custom_avatar_enabled']) = ConverterDb::fetch_row($request);
				else
					$_confs['ustom_avatar_enabled'] = false;
				ConverterDb::free_result($request);

				// Custom avatar dir.
				$request = ConverterDb::query('
					SELECT value
					FROM {to_prefix}settings
					WHERE variable = ' . (!empty($_confs['custom_avatar_enabled']) ? '{literal:custom_avatar_dir}' : '{literal:attachmentUploadDir}') . '
					LIMIT 1');
				list ($_confs['avatar_dir']) = ConverterDb::fetch_row($request);
				$_confs['attachment_type'] = !empty($_confs['custom_avatar_enabled']) ? '1' : '0';
				ConverterDb::free_result($request);

				$request = ConverterDb::query('
					SELECT config_value
					FROM {from_prefix}config
					WHERE config_name = {literal:avatar_path}
					LIMIT 1');
				$_confs['phpbb_avatar_upload_path'] = Converter::getVar('convertPathFrom') . '/' . ConverterDb::result($request, 0, 'config_value');
				ConverterDb::free_result($request);

				$request = ConverterDb::query('
					SELECT config_value
					FROM {from_prefix}config
					WHERE config_name = {literal:avatar_salt}
					LIMIT 1');
				$_confs['phpbb_avatar_salt'] = ConverterDb::result($request, 0, 'config_value');
				ConverterDb::free_result($request);
			},
			'process' => [
				'table' => '{to_prefix}members',
				'parse' => function (&$row) {
					global $_confs;

					// time_offset = phpBB user TZ - phpBB board TZ.
					$row['time_offset'] = (float) ($row['time_offset'] ?? 0);// - $_confs['board_timezone'];

					if ($row['user_avatar_type'] == 0)
						$row['avatar'] = '';
					// If the avatar type is uploaded (type = 1) copy avatar with the correct name.
					elseif ($row['user_avatar_type'] == 1 && strlen($row['avatar']) > 0)
					{
						$phpbb_avatar_ext = substr(strchr($row['avatar'], '.'), 1);
						$smf_avatar_filename = 'avatar_' . $row['id_member'] . strrchr($row['avatar'], '.');

						if (file_exists($_confs['phpbb_avatar_upload_path'] . '/' . $_confs['phpbb_avatar_salt'] . '_' . $row['id_member'] . '.' . $phpbb_avatar_ext))
							@copy($_confs['phpbb_avatar_upload_path'] . '/' . $_confs['phpbb_avatar_salt'] . '_' . $row['id_member'] . '.' . $phpbb_avatar_ext, $_confs['avatar_dir'] . '/' . $smf_avatar_filename);
						else
							@copy($_confs['phpbb_avatar_upload_path'] . '/' . $row['avatar'], $_confs['avatar_dir'] . '/' . $smf_avatar_filename);

						// Do a manual insert.
						ConverterDb::insert(
							'{to_prefix}attachments',
							['id_msg' => 'int', 'id_member' => 'int', 'filename' => 'int', 'attachment_type' => 'int'],
							[0, $row['id_member'], substr(addslashes($smf_avatar_filename), 0, 255), $_confs['attachment_type']],
						);

						$row['avatar'] = '';
					}
					elseif ($row['user_avatar_type'] == 3)
						$row['avatar'] = substr('gallery/' . $row['avatar'], 0, 255);
					unset($row['user_avatar_type']);

					if ($row['signature_uid'] != '')
						$row['signature'] = preg_replace('~(:u:|:1:|:)' . preg_quote($row['signature_uid'], '~') . '~i', '', $row['signature']);

					$row['signature'] = substr(self::fixBBC($row['signature']), 0, 65534);
					unset($row['signature_uid']);

					if (!is_numeric($row['id_group']))
						$row['id_group'] = 0;
				},
				'query' => '
					SELECT
						u.user_id AS id_member,
						SUBSTRING(u.username, 1, 80) AS member_name,
						SUBSTRING(u.username, 1, 255) AS real_name,
						SUBSTRING(u.user_password, 1, 64) AS passwd,
						u.user_lastvisit AS last_login,
						u.user_regdate AS date_registered,
						u.user_posts AS posts,
						IF(u.user_rank = 1, 1, IFNULL(mg.id_group, 0)) AS id_group,
						u.user_new_privmsg AS instant_messages,
						SUBSTRING(u.user_email, 1, 255) AS email_address,
						u.user_unread_privmsg AS unread_messages,
						u.user_allow_viewonline AS show_online,
						u.user_timezone AS time_offset,
						u.user_avatar AS avatar,
						u.user_sig AS signature,
						u.user_sig_bbcode_uid AS signature_uid,
						u.user_avatar_type,
						CASE u.user_inactive_reason WHEN 0 THEN 1 ELSE 0 END AS is_activated,
						{empty} AS lngfile,
						{empty} AS buddy_list,
						{empty} AS pm_ignore_list,
						{empty} AS personal_text,
						{empty} AS time_format,
						{empty} AS usertitle,
						u.user_ip AS member_ip,
						{empty} AS secret_question,
						{empty} AS secret_answer,
						{empty} AS validation_code,
						{empty} AS additional_groups,
						{empty} AS smiley_set,
						{empty} AS password_salt,
						{empty} AS ignore_boards, 
						u.user_ip AS member_ip2
					FROM {from_prefix}users AS u
						LEFT JOIN {from_prefix}ranks AS r
							ON (r.rank_id = u.user_rank AND r.rank_special = 1)
						LEFT JOIN LATERAL (
							SELECT *
							FROM {to_prefix}membergroups AS xmg
							WHERE xmg.group_name = CONCAT({string:phpbb_title}, r.rank_title)
							LIMIT 1
						) AS mg
							ON true
					WHERE u.group_id NOT IN (1, 6)
					', // GROUP BY u.user_id
				'params' => [
					'phpbb_title' => 'phpBB '
				],
			],
		];
	}

	public static string	$convertStep4info = 'Converting additional member groups';
	public static function	 convertStep4Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$result = ConverterDb::query('
				SELECT DISTINCT mg.id_group, mem.id_member
				FROM {from_prefix}groups AS g
					INNER JOIN {from_prefix}user_group AS ug
						ON (ug.group_id = g.group_id)
					INNER JOIN {to_prefix}members AS mem
						ON (mem.id_member = ug.user_id)
					INNER JOIN {to_prefix}membergroups AS mg ON (mg.group_name = CONCAT({string:phpbb_title}, g.group_name))
				WHERE g.group_name NOT IN ({literal:GUESTS}, {literal:REGISTERED_COPPA}, {literal:BOTS})
				ORDER BY id_member
				LIMIT {int:offset}, {int:limit}',
				[
					'phpbb_title' => 'phpBB ',
					'offset' => $currentStart,
					'limit' => self::getBlockSize('members')
			]);

			$additional_groups = '';
			$last_member = 0;
			while ($row = ConverterDb::fetch_assoc($result))
			{
				if (empty($last_member))
					$last_member = $row['id_member'];

				if ($last_member != $row['id_member'])
				{
					ConverterDb::query('
						UPDATE {to_prefix}members
						SET additional_groups = {string:additional_groups}
						WHERE id_member = {int:last_member}
						LIMIT 1',
						[
							'additional_groups' => $additional_groups,
							'last_member' => $last_member
					]);
					$last_member = $row['id_member'];
					$additional_groups = $row['id_group'];
				}
				else
				{
					if ($additional_groups == '')
						$additional_groups = $row['id_group'];
					else
						$additional_groups = $additional_groups . ',' . $row['id_group'];
				}
			}

			if (ConverterDb::num_rows($result) < self::getBlockSize('members'))
				break;
			ConverterDb::free_result($result);

			Converter::pastTime($currentStart += self::getBlockSize('members'));
		}

		if ($last_member != 0)
			ConverterDb::query('
				UPDATE {to_prefix}members
				SET additional_groups = {string:additional_groups}
				WHERE id_member = {int:last_member}
				LIMIT 1',
				[
					'additional_groups' => $additional_groups,
					'last_member' => $last_member
			]);
	}

	public static string	$convertStep5info = 'Converting categories';
	public static function	 convertStep5(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}categories',
				'resetauto' => '{to_prefix}categories',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}categories',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}forums WHERE forum_type = 0'
			],
			'pre_process' => function() {
				ConverterDb::add_column(
					'{to_prefix}categories',
					[
						'name' => 'temp_id',
						'type' => 'mediumint',
						'default' => 0
					]
				);
			},
			'process' => [
				'table' => '{to_prefix}categories',
				'query' => '
					SELECT forum_id AS temp_id, SUBSTRING(forum_name, 1, 255) AS name, left_id AS cat_order
					FROM {from_prefix}forums
					WHERE forum_type = 0
					ORDER BY left_id'
			],
			'post_process' => function() {
				$lostBoardName = 'Uncategorized Boards';

				$request = ConverterDb::query('
					SELECT COUNT(*)
					FROM {to_prefix}categories
					WHERE name = {string:lostBoardName}',
					[
						'lostBoardName' => $lostBoardName
				]);
				list ($exists) = ConverterDb::fetch_row($request);
				ConverterDb::free_result($request);

				if (empty($exists))
					ConverterDb::insert(
						'{to_prefix}categories',
						['temp_id', 'name', 'cat_order'],
						[[0, 'Uncategorized Boards', 1]],
						[], // Keys
						'replace'
					);
			},
		];
	}

	public static string	$convertStep6info = 'Converting boards';
	public static function	 convertStep6(): array
	{
		return [
			'purge' => [
				'query' => [
					'TRUNCATE {to_prefix}boards',
					'DELETE FROM {to_prefix}board_permissions WHERE id_profile > 4'
				],
				'resetauto' => [
					'{to_prefix}boards',
					'{to_prefix}board_permissions',
				],
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}boards',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}forums WHERE forum_type = 1'
			],
			'process' => [
				'table' => '{to_prefix}boards',
				'parse' => function (&$row) {
					if (empty($row['id_cat']))
						$row['id_cat'] = 1;
					$row['name'] = str_replace('\n', '<br />', $row['name']);
				},
				'query' => '
					SELECT
						f.forum_id AS id_board,
						CASE WHEN f.parent_id = c.temp_id THEN 0 ELSE f.parent_id END AS id_parent,
						f.left_id AS board_order,
						f.forum_posts_approved AS num_posts,
						f.forum_last_post_id AS id_last_msg,
						SUBSTRING(f.forum_name, 1, 255) AS name,
						c.id_cat AS id_cat,
						{string:default_mbr_grps} AS member_groups,
						SUBSTRING(f.forum_desc, 1, 65534) AS description,
						f.forum_topics_approved AS num_topics,
						f.forum_last_post_id AS id_last_msg
						FROM {from_prefix}forums AS f
							LEFT JOIN {to_prefix}categories AS c
								ON (c.temp_id = f.parent_id)
						WHERE forum_type = 1', // GROUP BY id_board
				'params' => [
					'default_mbr_grps' => '-1,0'
				],
			],
		];
	}

	public static string	$convertStep7info = 'Fixing categories';
	public static function	 convertStep7Custom(): void
	{
		ConverterDb::remove_column(
			'{to_prefix}categories',
			'temp_id'
		);

		// Lets fix the order.
		$request = ConverterDb::query('
			SELECT id_cat, cat_order
			FROM {to_prefix}categories
			ORDER BY cat_order');
		$order = 1;
		while ($row = ConverterDb::fetch_assoc($request))
		{
			ConverterDb::query('
				UPDATE {to_prefix}categories
				SET cat_order = {int:order}
				WHERE id_cat = {int:id_cat}',
				[
					'order' => $order,
					'id_cat' => $row['id_cat']
			]);
			$order++;
		}
		ConverterDb::free_result($request);
	}

	public static string	$convertStep8info = 'Converting topics';
	public static function	 convertStep8(): array
	{
		return [
			'purge' => [
				'query' => [
					'TRUNCATE {to_prefix}topics',
					'TRUNCATE {to_prefix}log_topics',
					'TRUNCATE {to_prefix}log_boards',
					'TRUNCATE {to_prefix}log_mark_read'
				],
				'resetauto' => [
					'{to_prefix}topics',
				],
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}topics',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}topics'
			],
			'process' => [
				'table' => '{to_prefix}topics',
				'method' => 'ignore',
				'query' => '
					SELECT
						t.topic_id AS id_topic,
						t.forum_id AS id_board,
						t.topic_first_post_id AS id_first_msg,
						CASE t.topic_type WHEN 1 THEN 1 WHEN 2 THEN 1 ELSE 0 END AS is_sticky,
						t.topic_last_post_id AS id_last_msg,
						t.topic_poster AS id_member_started,
						t.topic_last_poster_id AS id_member_updated,
						IFNULL(po.topic_id, 0) AS id_poll,
						t.topic_posts_approved  AS num_replies,
						t.topic_posts_unapproved  AS unapproved_posts,
						t.topic_views AS num_views,
						CASE t.topic_status WHEN 1 THEN 1 ELSE 0 END AS locked,
						CASE t.topic_visibility WHEN 0 THEN 0 WHEN 4 THEN 0 ELSE 1 END AS approved
					FROM {from_prefix}topics AS t
						LEFT JOIN {from_prefix}poll_options AS po
							ON (po.topic_id = t.topic_id)'
			],
		];
	}

	public static string	$convertStep9info = 'Converting messages';
	public static function	 convertStep9(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}messages',
				'resetauto' => '{to_prefix}messages',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}messages',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}posts'
			],
			'process' => [
				'table' => '{to_prefix}messages',
				'limit' => 200,
				'parse' => function (&$row) {
					$row['body'] = self::fixBBC($row['body']);
				},
				'query' => '
					SELECT
						p.post_id AS id_msg,
						p.topic_id AS id_topic,
						p.forum_id AS id_board,
						p.post_time AS poster_time,
						p.poster_id AS id_member,
						p.post_subject AS subject,
						IFNULL(m.username, {literal:Guest}) AS poster_name,
						IFNULL(m.user_email, {literal:Unknown}) AS poster_email,
						IFNULL(p.poster_ip, {inet:defaultIP}) AS poster_ip,
						p.enable_smilies AS smileys_enabled,
						p.post_edit_time AS modified_time,
						p.post_text AS body,
						CASE
							WHEN p.post_edit_user = 0 THEN {literal:Guest}
							WHEN m2.username IS NULL THEN {literal:Guest}
							ELSE m2.username
						END AS modified_name,
						CASE p.post_visibility WHEN 0 THEN 0 WHEN 4 THEN 0 ELSE 1 END AS approved
					FROM {from_prefix}posts AS p
						LEFT JOIN {from_prefix}users AS m
							ON (m.user_id = p.poster_id)
						LEFT JOIN {from_prefix}users AS m2
							ON (m2.user_id = p.post_edit_user)',
				'params' => [
					'defaultIP' => '0.0.0.0'
				],
			],
		];
	}

	public static string	$convertStep10info = 'Converting polls';
	public static function	 convertStep10(): array
	{
		return [
			'purge' => [
				'query' => [
					'TRUNCATE {to_prefix}polls',
					'TRUNCATE {to_prefix}poll_choices',
					'TRUNCATE {to_prefix}log_polls',
				],
				'resetauto' => [
					'{to_prefix}polls',
					'{to_prefix}poll_choices',
				],
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}polls',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}topics WHERE poll_title != {empty}'
			],
			'process' => [
				'table' => '{to_prefix}polls',
				'query' => '
					SELECT
						t.topic_id AS id_poll,
						t.poll_title AS question,
						t.poll_max_options AS max_votes,
						IF((t.poll_start + t.poll_length) < 0, 0, (t.poll_start + t.poll_length)) AS expire_time,
						t.poll_vote_change AS change_vote,
						t.topic_poster AS id_member,
						IFNULL(m.username, 0) AS poster_name
					FROM {from_prefix}topics AS t
						LEFT JOIN {from_prefix}users AS m
							ON (m.user_id = t.topic_poster)
					WHERE t.poll_title != {empty}'
			],
		];
	}

	public static string	$convertStep11info = 'Converting poll options';
	public static function	 convertStep11(): array
	{
		return [
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}poll_choices',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}poll_options'
			],
			'process' => [
				'table' => '{to_prefix}poll_choices',
				'method' => 'ignore',
				'query' => '
					SELECT
						topic_id AS id_poll,
						poll_option_id AS id_choice,
						SUBSTRING(poll_option_text, 1, 255) AS label,
						poll_option_total AS votes
					FROM {from_prefix}poll_options'
			],
		];
	}

	public static string	$convertStep12info = 'Converting poll votes';
	public static function	 convertStep12(): array
	{
		return [
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_polls',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}poll_votes WHERE vote_user_id > 0'
			],
			'process' => [
				'table' => '{to_prefix}log_polls',
				'method' => 'ignore',
				'query' => '
					SELECT
						topic_id AS id_poll,
						vote_user_id AS id_member,
						poll_option_id AS id_choice
					FROM {from_prefix}poll_votes
					WHERE vote_user_id > 0'
			],
		];
	}

	public static string	$convertStep13info = 'Converting personal messages (part 1)';
	public static function	 convertStep13(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}personal_messages',
				'resetauto' => '{to_prefix}personal_messages',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}personal_messages',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}privmsgs'
			],
			'process' => [
				'table' => '{to_prefix}personal_messages',
				'query' => '
					SELECT
						pm.msg_id AS id_pm,
						pm.author_id AS id_member_from,
						pm.message_time AS msgtime,
						SUBSTRING(uf.username, 1, 255) AS from_name,
						SUBSTRING(pm.message_subject, 1, 255) AS subject,
						SUBSTRING(REPLACE(IF(pm.bbcode_uid = {empty}, pm.message_text, REPLACE(REPLACE(pm.message_text, CONCAT({string:colon1}, pm.bbcode_uid), {empty}), CONCAT({string:colon}, pm.bbcode_uid), {empty})), {string:linebreak}, {string:br}), 1, 65534) AS body
					FROM {from_prefix}privmsgs AS pm
						LEFT JOIN {from_prefix}users AS uf ON (uf.user_id = pm.author_id)',
				'params' => [
					'colon1' => ':1:',
					'colon' => ':',
					'linebreak' => '\n',
					'br' => '<br />'
				],
			],
		];
	}

	public static string	$convertStep14info = 'Converting personal messages (part 2)';
	public static function	 convertStep14(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}pm_recipients',
				'resetauto' => '{to_prefix}pm_recipients',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}pm_recipients',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}privmsgs_to'
			],
			'process' => [
				'table' => '{to_prefix}pm_recipients',
				'query' => '
					SELECT
						pm.msg_id AS id_pm,
						pm.user_id AS id_member,
						{string:defaultLabel} AS labels,
						CASE pm.pm_unread WHEN 1 THEN 0 ELSE 1 END AS is_read,
						pm.pm_deleted AS deleted
					FROM {from_prefix}privmsgs_to AS pm',
				'params' => [
					'defaultLabel' => '-1',
				],
			],
		];
	}

	public static string	$convertStep15info = 'Converting attachments';
	public static function	 convertStep15Custom(): void
	{
		$attachmentUploadDir = static::getAttachmentDir();

		$result = ConverterDb::query('
			SELECT config_value
			FROM {from_prefix}config
			WHERE config_name = {literal:upload_path}
			LIMIT 1');
		list ($oldAttachmentDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		if (empty($oldAttachmentDir) || !file_exists(Converter::getVar('convertPathFrom') . '/' . $oldAttachmentDir))
			$oldAttachmentDir = Converter::getVar('convertPathFrom') . '/file';
		else
			$oldAttachmentDir = Converter::getVar('convertPathFrom') . '/' . $oldAttachmentDir;

		// Get $id_attach.
		$id_attach = static::getLastAttachmentID();

		// Set the default empty values.
		$width = 0;
		$height = 0;

		$currentStart = Converter::getVar('currentStart');
		while (true)
		{
			$inserts = [];
			$result = ConverterDb::query('
				SELECT
					post_msg_id AS id_msg,
					download_count AS downloads,
					real_filename AS filename,
					physical_filename,
					filesize AS size,
					extension,
					mimetype
				FROM {from_prefix}attachments
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('attachments')
			]);
			while ($row = ConverterDb::fetch_assoc($result))
			{
				$file_hash = getAttachmentFilename($row['filename'], $id_attach, null, true);
				$physical_filename = $id_attach . '_' . $file_hash . '.dat';

				if (strlen($physical_filename) > 255)
					return;

				if (copy($oldAttachmentDir . '/' . $row['physical_filename'], $attachmentUploadDir . '/' . $physical_filename))
				{
					// Is an an image?
					if (in_array($row['extension'], ['jpg', 'jpeg', 'gif', 'png', 'bmp']))
						list ($width, $height) = getimagesize($attachmentUploadDir . '/' . $physical_filename);

					$inserts[] = [
						'id_attach' => $id_attach,
						'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
						'downloads' => $row['downloads'],
						'filename' => $row['filename'],
						'file_hash' => $file_hash,
						'fileext' => $row['extension'],
						'id_msg' => $row['id_msg'],
						'width' => $width ?? 0,
						'height' => $height ?? 0,
						'mime_type' => $row['mimetype']
					];
					$id_attach++;
				}
			}

			if (ConverterDb::num_rows($result) < self::getBlockSize('attachments'))
				break;
			ConverterDb::free_result($result);

			ConverterDb::insert(
				'{to_prefix}attachments',
				array_keys($inserts[0]),
				$inserts,
			);

			Converter::pastTime($currentStart += self::getBlockSize('attachments'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}attachments',
				array_keys($inserts[0]),
				$inserts,
			);
	}

	public static string	$convertStep16info = 'Converting PM notifications';
	public static function	 convertStep16(): array
	{
		return [
			'progress' => [
				'use_counter' => true,
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}users'
			],
			'process' => [
				'table' => '{to_prefix}user_alerts_prefs',
				'method' => 'replace',
				'query' => '
					SELECT
						u.user_id AS id_member,
						{literal:pm_notify} AS alert_pref,
						u.user_notify_pm AS alert_value
					FROM {from_prefix}users AS u
					WHERE u.group_id NOT IN (1, 6)',
			],
		];
	}
}