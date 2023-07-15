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

class mybb18x_to_smf extends ConverterBase
{
	public static bool $purge = false;

	public static function info(): array
	{
		return [
			'name' => 'myBB 1.8',
			'version' => 'SMF 2.1.*',
			'settings' => ['/inc/config.php'],
			'globals' => ['config'],
			'from_prefix' => '`{$config[\'database\'][\'database\']}`.{$config[\'database\'][\'table_prefix\']}',
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

	public static function connectDb(): object
	{
		global $config;

		return smf_db_initiate(
			$config['database']['hostname'],
			$config['database']['database'],
			$config['database']['username'],
			$config['database']['password'],
			$config['database']['table_prefix']
		);
	}

	public static function prepareSystem(): void
	{
		parent::prepareSystem();

		self::$purge = Converter::getParameter('purge') ?? false;
	}

	public static string	$convertStep1info = 'Converting members';
	public static function	 convertStep1(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}members',
				'resetauto' => '{to_prefix}members',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}members',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}users'
			],
			'process' => [
				'table' => '{to_prefix}members',
				'parse' => function (&$row) {
					if (!filter_var($row['member_ip'], FILTER_VALIDATE_IP))
						$row['member_ip'] = @inet_ntop($row['member_ip']);
					if (!filter_var($row['member_ip2'], FILTER_VALIDATE_IP))
						$row['member_ip2'] = @inet_ntop($row['member_ip2']);
				},
				'query' => '
					SELECT
						uid AS id_member,
						SUBSTRING(username, 1, 80) AS member_name,
						SUBSTRING(username, 1, 255) AS real_name,
						email AS email_address,
						SUBSTRING(password, 1, 64) AS passwd,
						salt AS password_salt,
						postnum AS posts,
						SUBSTRING(usertitle, 1, 255) AS usertitle,
						lastvisit AS last_login,
						IF(usergroup = 4, 1, 0) AS id_group,
						regdate AS date_registered,
						SUBSTRING(website, 1, 255) AS website_url,
						SUBSTRING(website, 1, 255) AS website_title,
						SUBSTRING(signature, 1, 65534) AS signature,
						SUBSTRING(buddylist, 1, 255) AS buddy_list,
						SUBSTRING(regip, 1, 255) AS member_ip,
						SUBSTRING(regip, 1, 255) AS member_ip2,
						SUBSTRING(ignorelist, 1, 255) AS pm_ignore_list,
						timeonline AS total_time_logged_in,
						{empty} AS avatar,
						{empty} AS personal_text,
						{empty} AS secret_question,
						{empty} AS ignore_boards,
						{empty} AS additional_groups 
					FROM {from_prefix}users',
			],
		];
	}

	public static string	$convertStep2info = 'Converting categories';
	public static function	 convertStep2(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}categories',
				'resetauto' => '{to_prefix}categories',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}categories',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}forums WHERE type = {literal:c}'
			],
			'process' => [
				'table' => '{to_prefix}categories',
				'query' => '
					SELECT fid AS id_cat,
					SUBSTRING(name, 1, 255) AS name,
					disporder AS cat_order
					FROM {from_prefix}forums
					WHERE type = {literal:c}'
			],
		];
	}

	public static string	$convertStep3info = 'Converting boards';
	public static function	 convertStep3(): array
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
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}forums WHERE type = {literal:f}'
			],
			'process' => [
				'table' => '{to_prefix}boards',
				'query' => '
					SELECT
						fid AS id_board,
						SUBSTRING(name, 1, 255) AS name,
						SUBSTRING(description, 1, 65534) AS description,
						disporder AS board_order,
						posts AS num_posts,
						threads AS num_topics,
						pid AS id_parent,
						usepostcounts != {literal:yes} AS count_posts,
						{string:defaultGrps} AS member_groups
					FROM {from_prefix}forums
					WHERE type = {literal:f}',
				'params' => [
					'defaultGrps' => '-1,0',
				],
			],
		];
	}

	public static string	$convertStep4info = 'Converting topics';
	public static function	 convertStep4(): array
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
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}threads'
			],
			'process' => [
				'table' => '{to_prefix}topics',
				'query' => '
					SELECT
						t.tid AS id_topic,
						t.fid AS id_board,
						t.sticky AS is_sticky,
						t.poll AS id_poll,
						t.views AS num_views,
						IFNULL(t.uid, 0) AS id_member_started,
						IFNULL(ul.uid, 0) AS id_member_updated,
						t.replies AS num_replies,
						CASE
							WHEN (t.closed = {literal:1}) THEN 1
							ELSE 0
						END AS locked,
						p.id_first_msg,
						p.id_last_msg
					FROM {from_prefix}threads AS t
						LEFT JOIN LATERAL (
							SELECT
								MIN(xp.pid) as id_first_msg,
								MAX(xp.pid) AS id_last_msg
							FROM mybb_posts AS xp
							WHERE xp.tid = t.tid
							GROUP BY xp.tid
						) AS p
							ON true
						LEFT JOIN {from_prefix}users AS ul
							ON (BINARY ul.username = t.lastposter)'
			],
		];
	}

	public static string	$convertStep5info = 'Converting messages';
	public static function	 convertStep5(): array
	{
		return [
			'purge' => [
				'query' => [
					'TRUNCATE {to_prefix}messages',
					'TRUNCATE {to_prefix}attachments',
				],
				'resetauto' => [
					'{to_prefix}messages',
					'{to_prefix}attachments',
				],
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}messages',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}posts'
			],
			'process' => [
				'table' => '{to_prefix}messages',
				'limit' => 200,
				'parse' => function (&$row) {
					$row['poster_ip'] = @inet_ntop($row['poster_ip']);
				},
				'query' => '
					SELECT
						p.pid AS id_msg,
						p.tid AS id_topic,
						t.fid AS id_board,
						p.uid AS id_member,
						SUBSTRING(p.username, 1, 255) AS poster_name,
						p.dateline AS poster_time,
						SUBSTRING(p.ipaddress, 1, 255) AS poster_ip,
						SUBSTRING(IF(p.subject = {empty}, t.subject, p.subject), 1, 255) AS subject,
						SUBSTRING(IF(p.uid > 0, u.email, {empty}), 1, 255) AS poster_email,
						p.smilieoff = {literal:no} AS smileys_enabled,
						SUBSTRING(p.message, 1, 65534) AS body,
						{literal:xx} AS icon
					FROM {from_prefix}posts AS p
						INNER JOIN {from_prefix}threads AS t
						LEFT JOIN {from_prefix}users AS u
							ON (u.uid = p.uid)
						LEFT JOIN {from_prefix}users AS edit_u
							ON (edit_u.uid = p.edituid)
					WHERE t.tid = p.tid',
			],
		];
	}

	public static string	$convertStep6info = 'Converting polls';
	public static function	 convertStep6(): array
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
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}polls'
			],
			'process' => [
				'table' => '{to_prefix}polls',
				'query' => '
					SELECT
						p.pid AS id_poll,
						SUBSTRING(p.question, 1, 255) AS question,
						p.closed AS voting_locked,
						t.uid AS id_member,
						IF(p.timeout = 0, 0, p.dateline + p.timeout * 86400) AS expire_time,
						SUBSTRING(t.username, 1, 255) AS poster_name
					FROM {from_prefix}polls AS p
						LEFT JOIN {from_prefix}threads AS t
							ON (t.tid = p.tid)'
			],
		];
	}

	public static string	$convertStep7info = 'Converting poll options';
	public static function	 convertStep7Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');
		while (true)
		{
			$inserts = [];

			$result = ConverterDb::query('
				SELECT
					pid AS id_poll,
					options,
					votes
				FROM {from_prefix}polls
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('poll_choices')
			]);
			while ($row = ConverterDb::fetch_assoc($result))
			{
				$options = explode('||~|~||', $row['options']);
				$votes = explode('||~|~||', $row['votes']);

				$id_poll = $row['id_poll'];
				for ($i = 0, $n = count($options); $i < $n; $i++)
				{
					$inserts[] = array(
						'id_poll' => $id_poll,
						'id_choice' => ($i + 1),
						'label' => substr($options[$i], 1, 255),
						'votes' => $votes[$i] ?? 0,
					);
				}
			}

			if (ConverterDb::num_rows($result) < self::getBlockSize('poll_choices'))
				break;
			ConverterDb::free_result($result);

			ConverterDb::insert(
				'{to_prefix}poll_choices',
				array_keys($inserts[0]),
				$inserts,
			);

			Converter::pastTime($currentStart += self::getBlockSize('poll_choices'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}poll_choices',
				array_keys($inserts[0]),
				$inserts,
			);
	}

	public static string	$convertStep8info = 'Converting poll votes';
	public static function	 convertStep8(): array
	{
		return [
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_polls',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}pollvotes'
			],
			'process' => [
				'table' => '{to_prefix}log_polls',
				'method' => 'ignore',
				'query' => '
					SELECT
						pid AS id_poll,
						uid AS id_member,
						voteoption AS id_choice
					FROM {from_prefix}pollvotes'
			],
		];
	}

	public static string	$convertStep9info = 'Converting personal messages (part 1)';
	public static function	 convertStep9(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}personal_messages',
				'resetauto' => '{to_prefix}personal_messages',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}personal_messages',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}privatemessages WHERE folder != 2'
			],
			'process' => [
				'table' => '{to_prefix}personal_messages',
				'query' => '
					SELECT
						pm.pmid AS id_pm,
						pm.fromid AS id_member_from,
						pm.dateline AS msgtime,
						SUBSTRING(pm.subject, 1, 255) AS subject,
						SUBSTRING(pm.message, 1, 65534) AS body
					FROM {from_prefix}privatemessages AS pm
						LEFT JOIN {from_prefix}users AS uf
							ON (uf.uid = pm.fromid)
					WHERE pm.folder != 2',
			],
		];
	}

	public static string	$convertStep10info = 'Converting personal messages (part 2)';
	public static function	 convertStep10(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}pm_recipients',
				'resetauto' => '{to_prefix}pm_recipients',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}pm_recipients',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}privatemessages WHERE folder != 2'
			],
			'process' => [
				'table' => '{to_prefix}pm_recipients',
				'query' => '
					SELECT
						pmid AS id_pm,
						toid AS id_member,
						readtime != 0 AS is_read,
						{string:defaultLabel} AS labels
					FROM {from_prefix}privatemessages
					WHERE folder != 2',
				'params' => [
					'defaultLabel' => '-1',
				],
			],
		];
	}

	public static string	$convertStep11info = 'Converting topic notifications';
	public static function	 convertStep11(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_notify',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_notify',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}threadsubscriptions'
			],
			'process' => [
				'table' => '{to_prefix}log_notify',
				'method' => 'ignore',
				'query' => '
					SELECT
						uid AS id_member,
						tid AS id_topic
					FROM {from_prefix}threadsubscriptions',
			],
		];
	}

	public static string	$convertStep12info = 'Converting board notifications';
	public static function	 convertStep12(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_notify',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_notify',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}forumsubscriptions'
			],
			'process' => [
				'table' => '{to_prefix}log_notify',
				'method' => 'ignore',
				'query' => '
					SELECT
						uid AS id_member,
						fid AS id_board
					FROM {from_prefix}forumsubscriptions',
			],
		];
	}

	public static string	$convertStep13info = 'Converting censored words';
	public static function	 convertStep13Custom(): void
	{
		ConverterDb::query('
			DELETE FROM {to_prefix}settings
			WHERE variable IN ({literal:censor_vulgar}, {literal:censor_proper})'
		);

		$result = ConverterDb::query('
			SELECT badword, replacement
			FROM {from_prefix}badwords');
		$censor_vulgar = $censor_proper = [];
		while ($row = ConverterDb::fetch_assoc($result))
		{
			$censor_vulgar[] = $row['badword'];
			$censor_proper[] = $row['replacement'];
		}
		ConverterDb::free_result($result);

		$censored_vulgar = implode("\n", $censor_vulgar);
		$censored_proper = implode("\n", $censor_proper);

		ConverterDb::insert(
			'{to_prefix}settings',
			['variable', 'value'],
			[
				['censor_vulgar', $censored_vulgar],
				['censor_proper', $censored_proper]
			],
			[], // Keys
			'replace'
		);
	}

	public static string	$convertStep14info = 'Converting moderators';
	public static function	 convertStep14(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}moderators',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}moderators',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}moderators'
			],
			'process' => [
				'table' => '{to_prefix}moderators',
				'method' => 'ignore',
				'query' => '
					SELECT
						id AS id_member,
						fid AS id_board
					FROM {from_prefix}moderators',
			],
		];
	}

	public static string	$convertStep15info = 'Converting topic view logs';
	public static function	 convertStep15(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}moderators',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_topics',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}threadsread'
			],
			'process' => [
				'table' => '{to_prefix}log_topics',
				'method' => 'ignore',
				'query' => '
					SELECT
						tid AS id_topic,
						uid AS id_member
					FROM {from_prefix}threadsread',
			],
		];
	}

	public static string	$convertStep16info = 'Converting attachments';
	public static function	 convertStep16Custom(): void
	{
		$attachmentUploadDir = static::getAttachmentDir();

		$result = ConverterDb::query('
			SELECT value
			FROM {from_prefix}settings
			WHERE name = {literal:uploadspath}
			LIMIT 1');
		list ($oldAttachmentDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		$oldAttachmentDir = Converter::getVar('convertPathFrom') . ltrim($oldAttachmentDir, '.');

		// Set the default empty values.
		$width = 0;
		$height = 0;

		$currentStart = Converter::getVar('currentStart');
		while (true)
		{
			$inserts = [];
			$result = ConverterDb::query('
				SELECT
					aid AS id_attach,
					pid AS id_msg,
					downloads,
					filename,
					filetype,
					filesize,
					attachname,
					visible
				FROM {from_prefix}attachments
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('attachments')
			]);
			while ($row = ConverterDb::fetch_assoc($result))
			{
				$file_hash = getAttachmentFilename($row['filename'], $row['id_attach'], null, true);
				$physical_filename = $row['id_attach'] . '_' . $file_hash . '.dat';

				if (strlen($physical_filename) > 255)
					return;

				if (copy($oldAttachmentDir . '/' . $row['attachname'], $attachmentUploadDir . '/' . $physical_filename))
				{
					$p = pathinfo($row['filename']);
					// Is an an image?
					if (in_array($p['extension'], ['jpg', 'jpeg', 'gif', 'png', 'bmp']))
						list ($width, $height) = getimagesize($attachmentUploadDir . '/' . $physical_filename);

					$inserts[] = [
						'id_attach' => $row['id_attach'],
						'size' => filesize($attachmentUploadDir . '/' . $physical_filename),
						'downloads' => $row['downloads'],
						'filename' => $row['filename'],
						'file_hash' => $file_hash,
						'fileext' => $p['extension'],
						'id_msg' => $row['id_msg'],
						'width' => $width ?? 0,
						'height' => $height ?? 0,
						'mime_type' => $row['filetype'],
						'approved' => $row['visible']
					];
				}
			}

			ConverterDb::insert(
				'{to_prefix}attachments',
				array_keys($inserts[0]),
				$inserts,
				[], // Keys,
				'replace'
			);

			if (ConverterDb::num_rows($result) < self::getBlockSize('attachments'))
				break;
			ConverterDb::free_result($result);

			Converter::pastTime($currentStart += self::getBlockSize('attachments'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}attachments',
				array_keys($inserts[0]),
				$inserts,
				[], // Keys,
				'replace'
			);
	}
}