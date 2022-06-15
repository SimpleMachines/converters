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

class elkarte11x_to_smf extends ConverterBase
{
	public static bool $purge = false;

	public static function info(): array
	{
		return [
			'name' => 'ElkArte 1.1.x',
			'version' => 'SMF 2.1.*',
			'settings' => ['/Settings.php'],
			'globals' => ['db_server', 'db_name', 'db_user', 'db_passwd', 'db_prefix', 'boarddir'],
			'from_prefix' => '{$db_prefix}',
			'test_table' => '{from_prefix}members',
			'parameters' => [
				[
					'id' => 'purge',
					'type' => 'checked',
					'label' => 'Clear current SMF posts and members during conversion.',
				],
			],
			'startup' => self::startup(),
		];
	}

	public static function startup(): void
	{
		global $db_server, $db_name, $db_user, $db_passwd, $db_prefix, $protection, $boarddir;

		// Protect these as SMF also uses them.
		foreach (['db_server', 'db_name', 'db_user', 'db_passwd', 'db_prefix', 'boarddir'] as $v)
			if (!isset($protection[$v]))
				$protection[$v] = $$v;
	}

	public static function connectDb(): object
	{
		global $db_server, $db_name, $db_user, $db_passwd, $db_prefix, $protection, $boarddir, $from_boarddir;

		$con = smf_db_initiate($db_server, $db_name, $db_user, $db_passwd, $db_prefix);
		$from_boarddir = $boarddir;

		// Restore these as SMF needs theme.
		foreach (['db_server', 'db_name', 'db_user', 'db_passwd', 'db_prefix', 'boarddir'] as $v)
			$$v = $protection[$v];

		return $con;
	}

	public static function checkAndFixPath(string $path): string
	{
		global $from_boarddir;

		$open_base_dir = ini_get('open_basedir');
		if (!empty($open_base_dir))
		{
			$exists = false;
			foreach ((explode(':', ini_get('open_basedir')) ?? []) as $dir)
			{
				if (strpos($dir, $path) !== false && is_writable($dir))
				{
					$exists = true;
					break;
				}
			}
		}
		else
			$exists = true;

		if ($exists && file_exists($path))
			return $path;

		return str_replace($from_boarddir, Converter::getVar('convertPathFrom'), $path);
	}

	public static function prepareSystem(): void
	{
		parent::prepareSystem();

		self::$purge = Converter::getParameter('purge') ?? false;
	}

	public static function convertdec2IPv6(...$decs)
	{
		foreach ($decs as &$dec)
			$dec = dechex($dec);

		return implode(':', $decs);
	}

	public static string	$convertStep1info = 'Converting membergroups';
	public static function	 convertStep1(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}membergroups',
				'resetauto' => '{to_prefix}membergroups',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}membergroups',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}membergroups'
			],
			'process' => [
				'table' => '{to_prefix}membergroups',
				'query' => '
					SELECT
						id_group, group_name, description, online_color, min_posts, max_messages, icons,
						group_type, hidden, id_parent
					FROM {from_prefix}membergroups',
			],
		];
	}

	public static string	$convertStep2info = 'Converting members';
	public static function	 convertStep2(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}members',
				'resetauto' => '{to_prefix}members',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}members',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}members'
			],
			'process' => [
				'table' => '{to_prefix}members',
				'query' => '
					SELECT
						id_member, member_name, date_registered, posts, id_group, lngfile, last_login, real_name, personal_messages AS instant_messages, unread_messages, new_pm, buddy_list, pm_ignore_list, pm_prefs, mod_prefs, passwd, email_address, birthdate, website_title, website_url, show_online, time_format, signature, time_offset, avatar, usertitle, member_ip, member_ip2, secret_question, secret_answer, id_theme, is_activated, validation_code, id_msg_last_visit, additional_groups, smiley_set, id_post_group, total_time_logged_in, password_salt, ignore_boards, warning, passwd_flood, receive_from AS pm_receive_from
					FROM {from_prefix}members',
			],
		];
	}

	public static string	$convertStep3info = 'Converting custom profile field';
	public static function	 convertStep3(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}custom_fields',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}custom_fields',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}custom_fields'
			],
			'process' => [
				'table' => '{to_prefix}custom_fields',
				'query' => '
					SELECT
						id_field, col_name, field_name, field_desc, field_type, field_length, field_options, vieworder AS field_order, mask, show_reg, show_display, show_memberlist AS show_mlist, show_profile, private, active, bbc, can_search, default_value, enclose, placement
					FROM {from_prefix}custom_fields',
			],
		];
	}

	public static string	$convertStep4info = 'Converting custom profile field values';
	public static function	 convertStep4(): array
	{
		return [
			'purge' => [
				'query' => 'DELETE FROM {to_prefix}themes WHERE id_member > 0 AND variable = {literal:cust_gender}',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}themes WHERE id_member > 0 AND variable = {literal:cust_gender}',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}custom_fields_data'
			],
			'process' => [
				'table' => '{to_prefix}custom_fields_data',
				'query' => '
					SELECT
						id_member,
						0 AS id_theme,
						variable,
						value
					FROM {from_prefix}custom_fields_data',
			],
		];
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
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}categories'
			],
			'process' => [
				'table' => '{to_prefix}categories',
				'query' => '
					SELECT id_cat, cat_order, name, can_collapse
					FROM {from_prefix}categories'
			],
		];
	}

	public static string	$convertStep6info = 'Converting boards';
	public static function	 convertStep6(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}boards',
				'resetauto' => '{to_prefix}boards',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}boards',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}boards'
			],
			'process' => [
				'table' => '{to_prefix}boards',
				'query' => '
					SELECT
						id_board, id_cat, child_level, id_parent, board_order, id_last_msg, id_msg_updated, member_groups, id_profile, name, description, num_topics, num_posts, count_posts, id_theme, override_theme, unapproved_posts, unapproved_topics, redirect
					FROM {from_prefix}boards'
			],
		];
	}

	public static string	$convertStep7info = 'Converting topics';
	public static function	 convertStep7(): array
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
				'query' => '
					SELECT
						id_topic, is_sticky, id_board, id_first_msg, id_last_msg, id_member_started, id_member_updated, id_poll, id_previous_board, id_previous_topic, num_replies, num_views, locked, unapproved_posts, approved
					FROM {from_prefix}topics'
			],
		];
	}

	public static string	$convertStep8info = 'Converting messages';
	public static function	 convertStep8(): array
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
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}messages'
			],
			'process' => [
				'table' => '{to_prefix}messages',
				'query' => '
					SELECT
						id_msg, id_topic, id_board, poster_time, id_member, id_msg_modified, subject, poster_name, poster_email, poster_ip, smileys_enabled, modified_time, modified_name, body, icon, approved
					FROM {from_prefix}messages',
			],
		];
	}

	public static string	$convertStep9info = 'Converting polls';
	public static function	 convertStep9(): array
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
						id_poll, question, voting_locked, max_votes, expire_time, hide_results, change_vote, guest_vote, num_guest_voters, reset_poll, id_member, poster_name
					FROM {from_prefix}polls'
			],
		];
	}

	public static string	$convertStep10info = 'Converting poll choices';
	public static function	 convertStep10(): array
	{
		return [
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}poll_choices',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}poll_choices'
			],
			'process' => [
				'table' => '{to_prefix}poll_choices',
				'query' => '
					SELECT
						id_poll, id_choice, label, votes
					FROM {from_prefix}poll_choices'
			],
		];
	}

	public static string	$convertStep11info = 'Converting poll votes';
	public static function	 convertStep11(): array
	{
		return [
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_polls',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_polls'
			],
			'process' => [
				'table' => '{to_prefix}log_polls',
				'query' => '
					SELECT
						id_poll, id_member, id_choice
					FROM {from_prefix}log_polls'
			],
		];
	}

	public static string	$convertStep12info = 'Converting personal messages (part 1 - pms)';
	public static function	 convertStep12(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}personal_messages',
				'resetauto' => '{to_prefix}personal_messages',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}personal_messages',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}personal_messages'
			],
			'process' => [
				'table' => '{to_prefix}personal_messages',
				'query' => '
					SELECT
						id_pm, id_pm_head, id_member_from, deleted_by_sender, from_name, msgtime, subject, body
					FROM {from_prefix}personal_messages',
			],
		];
	}

	public static string	$convertStep13info = 'Converting personal messages (part 2 -recipients)';
	public static function	 convertStep13(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}pm_recipients',
				'resetauto' => '{to_prefix}pm_recipients',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}pm_recipients',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}pm_recipients'
			],
			'process' => [
				'table' => '{to_prefix}pm_recipients',
				'query' => '
					SELECT
						id_pm, id_member, bcc, is_read, is_new, deleted,
						CASE WHEN FIND_IN_SET({int:minusone}, labels)
							THEN 1
						ELSE 0 END AS in_inbox
					FROM {from_prefix}pm_recipients',
				'params' => [
					'minusone' => -1,
				],
			],
		];
	}

	public static string	$convertStep14info = 'Converting personal messages (part 3 - labels)';
	public static function	 convertStep14Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$result = ConverterDb::query('
				SELECT id_member, message_labels
				FROM {from_prefix}members
				WHERE message_labels != {empty}
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('members')
			]);

			$inserts = [];
			while ($row = ConverterDb::fetch_assoc($result))
				foreach(explode(',', $row['message_labels']) as $l)
					$inserts[] = ['id_member' => $row['id_member'], 'name' => $l];

			if (ConverterDb::num_rows($result) < self::getBlockSize('members'))
				break;
			ConverterDb::free_result($result);

			ConverterDb::insert(
				'{to_prefix}pm_labels',
				array_keys($inserts[0]),
				$inserts,
			);

			Converter::pastTime($currentStart += self::getBlockSize('members'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}pm_labels',
				array_keys($inserts[0]),
				$inserts,
			);
	}

	public static string	$convertStep15info = 'Converting personal messages (part 4 - labled messages)';
	public static function	 convertStep15Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$inserts = $tempA = $tempB = $members = [];

			$result = ConverterDb::query('
				SELECT pr.id_pm, pr.labels, pr.id_member, m.message_labels
				FROM {from_prefix}pm_recipients AS pr
                	INNER JOIN {from_prefix}members AS m ON (m.id_member = pr.id_member)
				WHERE pr.labels != {empty} AND pr.labels != {string:minusone}
				LIMIT {int:offset}, {int:limit}',
				[
					'minusone' => -1,
					'offset' => $currentStart,
					'limit' => self::getBlockSize('members')
			]);

			if (ConverterDb::num_rows($result) == 0)
				break;

			while ($row = ConverterDb::fetch_assoc($result))
				$tempA[$row['id_member']][$row['id_pm']] = $row;
			ConverterDb::free_result($result);
			$members = array_keys($tempA);

			if (empty($tempA) || empty($members))
				break;

			$result = ConverterDb::query('
				SELECT id_label, id_member, name
				FROM {to_prefix}pm_labels
				WHERE id_member IN ({array_int:members})',
				[
					'members' => $members
			]);
			while ($row = ConverterDb::fetch_assoc($result))
				$tempB[$row['id_member']][$row['name']] = $row['id_label'];

			foreach ($tempA as $id_member => $r)
			{
				foreach ($r as $id_pm => $data)
				{
					$lbls = explode(',', $data['message_labels']);
					foreach (explode(',', $data['labels']) as $lblidx)
					{
						if ($lblidx == '-1')
							continue;

						$inserts[] = [
							'id_label' => $tempB[$id_member][$lbls[$lblidx]],
							'id_pm' => $id_pm
						];
					}
				}
			}

			if (ConverterDb::num_rows($result) < self::getBlockSize('members'))
				break;
			ConverterDb::free_result($result);

			ConverterDb::insert(
				'{to_prefix}pm_labeled_messages',
				array_keys($inserts[0]),
				$inserts,
			);

			Converter::pastTime($currentStart += self::getBlockSize('members'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}pm_labeled_messages',
				array_keys($inserts[0]),
				$inserts,
			);
	}

	public static string	$convertStep16info = 'Converting attachments';
	public static function	 convertStep16Custom(): void
	{
		$attachmentUploadDir = static::getAttachmentDir();

		$result = ConverterDb::query('
			SELECT value
			FROM {from_prefix}settings
			WHERE variable = {literal:attachmentUploadDir}
			LIMIT 1');
		list ($oldAttachmentDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		$result = ConverterDb::query('
			SELECT value
			FROM {from_prefix}settings
			WHERE variable = {literal:currentAttachmentUploadDir}
			LIMIT 1');
		list ($oldcurrentAttachmentUploadDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		$result = ConverterDb::query('
			SELECT value
			FROM {to_prefix}settings
			WHERE variable = {literal:currentAttachmentUploadDir}
			LIMIT 1');
		list ($tocurrentAttachmentUploadDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		// We may have a non multiple attachment directory support.
		if (!empty($oldcurrentAttachmentUploadDir))
			$attachDirs = safe_unserialize($oldAttachmentDir);

		$currentStart = Converter::getVar('currentStart');
		while (true)
		{
			$inserts = [];
			$result = ConverterDb::query('
				SELECT
					id_attach, id_thumb, id_msg, id_member, id_folder, attachment_type, filename, file_hash, fileext, size, downloads, width, height, mime_type, approved
				FROM {from_prefix}attachments
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('attachments')
			]);
			while ($row = ConverterDb::fetch_assoc($result))
			{
				$old_physical_filename = self::checkAndFixPath(
					(!empty($oldcurrentAttachmentUploadDir) ? $attachDirs[$row['id_folder']] : $oldAttachmentDir)
					. '/' . $row['id_attach'] . '_' . $row['file_hash'] . '.elk'
				);

				// Trying to support moving files into multiple attachment directories is too complicated.  One dir it is.
				$new_physical_filename = $attachmentUploadDir . '/' . $row['id_attach'] . '_' . $row['file_hash'] . '.dat';

				if (copy($old_physical_filename, $new_physical_filename))
				{
					$inserts[] = [
						'id_attach' => $row['id_attach'],
						'id_thumb' => $row['id_thumb'],
						'id_msg' => $row['id_msg'],
						'id_member' => $row['id_member'],
						'id_folder' => $tocurrentAttachmentUploadDir,
						'attachment_type' => $row['attachment_type'],
						'filename' => $row['filename'],
						'file_hash' => $row['file_hash'],
						'fileext' => $row['fileext'],						
						'size' => filesize($new_physical_filename),
						'downloads' => $row['downloads'],
						'width' => $row['width'] ?? 0,
						'height' => $row['height'] ?? 0,
						'mime_type' => $row['mime_type'],
						'approved' => $row['approved']
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

	public static string	$convertStep17info = 'Converting approval queue';
	public static function	 convertStep17(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}approval_queue',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}approval_queue',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}approval_queue'
			],
			'process' => [
				'table' => '{to_prefix}approval_queue',
				'method' => 'ignore',
				'query' => '
					SELECT
						id_msg, id_attach, id_event
					FROM {from_prefix}approval_queue',
			],
		];
	}

	public static string	$convertStep18info = 'Converting ban groups';
	public static function	 convertStep18(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}ban_groups',
				'resetauto' => '{to_prefix}ban_groups',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}ban_groups',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}ban_groups'
			],
			'process' => [
				'table' => '{to_prefix}ban_groups',
				'query' => '
					SELECT
						id_ban_group, name, ban_time, IFNULL(expire_time, 0) AS expire_time, cannot_access, cannot_register, cannot_post, cannot_login, reason, notes
					FROM {from_prefix}ban_groups',
			],
			'post_process' => function() {
				// SMF has a issue where we can't insert "NULL" values because of a isset check.
				ConverterDb::query('
					UPDATE {to_prefix}ban_groups
					SET expire_time = NULL
					WHERE expire_time = 0');
			}
		];
	}

	public static string	$convertStep19info = 'Converting ban items';
	public static function	 convertStep19(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}ban_items',
				'resetauto' => '{to_prefix}ban_items',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}ban_items',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}ban_items'
			],
			'process' => [
				'table' => '{to_prefix}ban_items',
				'parse' => function (&$row) {
					// Make sure IPv6 is converted.
					if (!empty($row['ip_low5']) || !empty($row['ip_low6']) || !empty($row['ip_low7']) || !empty($row['ip_low8'])
						|| !empty($row['ip_high5']) || !empty($row['ip_high6']) || !empty($row['ip_high7']) || !empty($row['ip_high8'])
						|| $row['ip_low1'] > 255 || $row['ip_low2'] > 255 || $row['ip_low3'] > 255 || $row['ip_low4'] > 255
						|| $row['ip_high1'] > 255 || $row['ip_high2'] > 255 || $row['ip_high3'] > 255 || $row['ip_high4'] > 255
					)
					{
						$row['ip_low'] = self::convertdec2IPv6($row['ip_low1'], $row['ip_low2'], $row['ip_low3'], $row['ip_low4'], $row['ip_low5'], $row['ip_low6'], $row['ip_low7'], $row['ip_low8']);
						$row['ip_high'] = self::convertdec2IPv6($row['ip_high1'], $row['ip_high2'], $row['ip_high3'], $row['ip_high4'], $row['ip_high5'], $row['ip_high6'], $row['ip_high7'], $row['ip_high8']);
					}
					// IPv4
					else
					{
						$row['ip_low'] = $row['ip_low1'] . '.' . $row['ip_low2'] . '.' . $row['ip_low3'] . '.' . $row['ip_low4'];
						$row['ip_high'] = $row['ip_high1'] . '.' . $row['ip_high2'] . '.' . $row['ip_high3'] . '.' . $row['ip_high4'];
					}
			
					unset($row['ip_low1'], $row['ip_low2'], $row['ip_low3'], $row['ip_low4'], $row['ip_low5'], $row['ip_low6'], $row['ip_low7'], $row['ip_low8'], $row['ip_high1'], $row['ip_high2'], $row['ip_high3'], $row['ip_high4'], $row['ip_high5'], $row['ip_high6'], $row['ip_high7'], $row['ip_high8']);
				},
				'query' => '
					SELECT
						id_ban, id_ban_group, ip_low1, ip_high1, ip_low2, ip_high2, ip_low3, ip_high3, ip_low4, ip_high4, ip_low5, ip_high5, ip_low6, ip_high6, ip_low7, ip_high7, ip_low8, ip_high8, hostname, email_address, id_member, hits
					FROM {from_prefix}ban_items',
			],
			'post_process' => function() {
				ConverterDb::insert(
					'{to_prefix}settings',
					['variable', 'value'],
					[
						['banLastUpdated', time()]
					],
					[], // Keys
					'replace'
				);
			},
		];
	}

	public static string	$convertStep20info = 'Converting board permissions';
	public static function	 convertStep20(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}board_permissions',
				'resetauto' => '{to_prefix}board_permissions',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}board_permissions',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}board_permissions'
			],
			'process' => [
				'table' => '{to_prefix}board_permissions',
				'query' => '
					SELECT
						id_group, id_profile, permission, add_deny
					FROM {from_prefix}board_permissions',
			],
		];
	}

	public static string	$convertStep21info = 'Converting calendar';
	public static function	 convertStep21(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}calendar',
				'resetauto' => '{to_prefix}calendar',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}calendar',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}calendar'
			],
			'process' => [
				'table' => '{to_prefix}calendar',
				'query' => '
					SELECT
						id_event, start_date, end_date, id_board, id_topic, title, id_member
					FROM {from_prefix}calendar',
			],
		];
	}

	public static string	$convertStep22info = 'Converting calendar holidays';
	public static function	 convertStep22(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}calendar_holidays',
				'resetauto' => '{to_prefix}calendar_holidays',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}calendar_holidays',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}calendar_holidays'
			],
			'process' => [
				'table' => '{to_prefix}calendar_holidays',
				'query' => '
					SELECT
						id_holiday, event_date, title
					FROM {from_prefix}calendar_holidays',
			],
		];
	}

	public static string	$convertStep23info = 'Converting collapsed categories';
	public static function	 convertStep23(): array
	{
		return [
			'purge' => [
				'query' => 'DELETE FROM {to_prefix}themes WHERE id_member > 0 AND variable LIKE {string:collapse_category}',
				'params' => ['collapse_category' => 'collapse_category%'],
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}themes WHERE id_member > 0 AND variable LIKE {string:collapse_category}',
				'progress_params' => ['collapse_category' => 'collapse_category%'],
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}collapsed_categories'
			],
			'process' => [
				'table' => '{to_prefix}themes',
				'query' => '
					SELECT
						id_member,
						1 AS id_theme,
						CONCAT({literal:collapse_category_}, id_cat) AS variable,
						id_cat AS value
					FROM {from_prefix}collapsed_categories',
			],
		];
	}

	public static string	$convertStep24info = 'Converting group moderators';
	public static function	 convertStep24(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}group_moderators',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}group_moderators',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}group_moderators'
			],
			'process' => [
				'table' => '{to_prefix}group_moderators',
				'query' => '
					SELECT
						id_group, id_member
					FROM {from_prefix}group_moderators',
			],
		];
	}

	public static string	$convertStep25info = 'Converting message icons';
	public static function	 convertStep25(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}message_icons',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}message_icons',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}message_icons'
			],
			'process' => [
				'table' => '{to_prefix}message_icons',
				'query' => '
					SELECT
						id_icon, title, filename, id_board, icon_order
					FROM {from_prefix}message_icons',
			],
		];
	}

	public static string	$convertStep26info = 'Converting board moderators';
	public static function	 convertStep26(): array
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
				'query' => '
					SELECT
						id_board, id_member
					FROM {from_prefix}moderators',
			],
		];
	}

	public static string	$convertStep27info = 'Converting permission profiles';
	public static function	 convertStep27(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}permission_profiles',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}permission_profiles',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}permission_profiles'
			],
			'process' => [
				'table' => '{to_prefix}permission_profiles',
				'query' => '
					SELECT
						id_profile, profile_name
					FROM {from_prefix}permission_profiles',
			],
		];
	}

	public static string	$convertStep28info = 'Converting permissions';
	public static function	 convertStep28(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}permissions',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}permissions',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}permissions'
			],
			'process' => [
				'table' => '{to_prefix}permissions',
				'query' => '
					SELECT
						id_group, permission, add_deny
					FROM {from_prefix}permissions',
			],
		];
	}

	public static string	$convertStep29info = 'Converting known good settings';
	public static function	 convertStep29(): array
	{
		return [
			'process' => [
				'table' => '{to_prefix}settings',
				'method' => 'replace',
				// Avoid any directories, urls or integration settings.
				'query' => '
					SELECT
						variable, value
					FROM {from_prefix}settings
					WHERE
						variable IN ({array_string:knownGood})',
				'params' => [
					'knownGood' => ['allow_disableAnnounce', 'allow_editDisplayName', 'allow_guestAccess', 'allow_hideOnline', 'attachmentCheckExtensions', 'attachmentDirFileLimit', 'attachmentDirSizeLimit', 'attachmentEnable', 'attachmentExtensions', 'attachmentNumPerPostLimit', 'attachmentPostLimit', 'attachmentShowImages', 'attachmentSizeLimit', 'attachmentThumbHeight', 'attachmentThumbnails', 'attachmentThumbWidth', 'attachment_image_paranoid', 'attachment_image_reencode', 'attachment_thumb_png', 'autoFixDatabase', 'autoLinkUrls', 'avatar_action_too_large', 'avatar_download_png', 'avatar_paranoid', 'avatar_reencode', 'banLastUpdated', 'birthday_email', 'cache_enable', 'cal_daysaslink', 'cal_days_for_index', 'cal_defaultboard', 'cal_enabled', 'cal_maxspan', 'cal_maxyear', 'cal_minyear', 'cal_showbdays', 'cal_showevents', 'cal_showholidays', 'cal_showweeknum', 'censorIgnoreCase', 'censor_proper', 'censor_vulgar', 'compactTopicPagesContiguous', 'compactTopicPagesEnable', 'cookieTime', 'defaultMaxMembers', 'defaultMaxMessages', 'defaultMaxTopics', 'default_personal_text', 'default_timezone', 'edit_disable_time', 'edit_wait_time', 'enableAllMessages', 'enableBBC', 'enableCompressedOutput', 'enableErrorLogging', 'enableParticipation', 'enablePostHTML', 'enablePreviousNext', 'enable_buddylist', 'failed_login_threshold', 'global_character_set', 'httponlyCookies', 'jquery_source', 'knownThemes', 'lastActive', 'last_mod_report_action', 'latestMember', 'latestRealName', 'mail_next_send', 'mail_recent', 'mail_type', 'maxMsgID', 'max_image_height', 'max_image_width', 'max_messageLength', 'memberlist_updated', 'mostDate', 'mostOnline', 'mostOnlineToday', 'mostOnlineUpdated', 'news', 'next_task_time', 'number_format', 'oldTopicDays', 'onlineEnable', 'package_make_backups', 'permission_enable_deny', 'permission_enable_postgroups', 'pm_spam_settings', 'pollMode', 'pruningOptions', 'rand_seed', 'recycle_board', 'recycle_enable', 'registration_method', 'reg_verification', 'requireAgreement', 'reserveCase', 'reserveName', 'reserveNames', 'reserveUser', 'reserveWord', 'search_cache_size', 'search_floodcontrol_time', 'search_max_results', 'search_results_per_page', 'search_weight_age', 'search_weight_first_message', 'search_weight_frequency', 'search_weight_length', 'search_weight_subject', 'secureCookies', 'send_validation_onChange', 'send_welcomeEmail', 'settings_updated', 'signature_settings', 'smiley_sets_default', 'smiley_sets_known', 'smiley_sets_names', 'smtp_host', 'smtp_password', 'smtp_port', 'smtp_username', 'spamWaitTime', 'theme_allow', 'theme_default', 'theme_guests', 'timeLoadPageEnable', 'time_format', 'time_offset', 'titlesEnable', 'todayMod', 'topicSummaryPosts', 'totalMembers', 'totalMessages', 'totalTopics', 'trackStats', 'unapprovedMembers', 'userLanguage', 'use_subdirectories_for_attachments', 'visual_verification_type', 'warning_mute', 'warning_settings', 'warning_watch', 'who_enabled', 'xmlnews_enable', 'xmlnews_maxlen']
				],
			],
		];
	}

	public static string	$convertStep30info = 'Converting smileys (Part 1)';
	public static function	 convertStep30(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}smileys',
				'resetauto' => '{to_prefix}smileys',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}smileys',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}smileys'
			],
			'process' => [
				'table' => '{to_prefix}smileys',
				// Avoid any directories, urls or integration settings.
				'query' => '
					SELECT
						id_smiley, code, description, smiley_row, smiley_order, hidden
					FROM {from_prefix}smileys',
			],
		];
	}

	public static string	$convertStep31info = 'Converting smileys (Part 2)';
	public static function	 convertStep31Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');

		$result = ConverterDb::query('
			SELECT value
			FROM {from_prefix}settings
			WHERE variable = {literal:smiley_sets_known}',
		);
		list($smiley_sets_known) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);
		$dirs = explode(',', $smiley_sets_known);	

		while (true)
		{
			$result = ConverterDb::query('
				SELECT id_smiley, filename
				FROM {from_prefix}smileys',
			);

			$inserts = [];
			while ($row = ConverterDb::fetch_assoc($result))
				foreach($dirs as $d)
					$inserts[] = [
						'id_smiley' => $row['id_smiley'],
						'smiley_set' => $d,
						'filename' => $row['filename']
					];

			if (ConverterDb::num_rows($result) < self::getBlockSize('members'))
				break;
			ConverterDb::free_result($result);

			ConverterDb::insert(
				'{to_prefix}smiley_files',
				array_keys($inserts[0]),
				$inserts,
				[], // Keys,
				'ignore'
			);

			Converter::pastTime($currentStart += self::getBlockSize('members'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}smiley_files',
				array_keys($inserts[0]),
				$inserts,
				[], // Keys,
				'ignore'
			);
	}

	public static string	$convertStep32info = 'Converting smileys (Part 3)';
	public static function	 convertStep32Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');

		// Use a smaller block size as we are copying files
		$blockSize = self::getBlockSize('smiley_set_files') ?? 25;

		$result = ConverterDb::query('
			SELECT value
			FROM {from_prefix}settings
			WHERE variable = {literal:smileys_dir}',
		);
		list($from_smileys_dir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		// Try to correct a from path.
		$from_smileys_dir = self::checkAndFixPath($from_smileys_dir);

		if (!file_exists($from_smileys_dir))
			Converter::skip('Smileys source directory does not exist or is not writable');

		$result = ConverterDb::query('
			SELECT value
			FROM {to_prefix}settings
			WHERE variable = {literal:smileys_dir}',
		);
		list($to_smileys_dir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		$result = ConverterDb::query('
			SELECT value
			FROM {to_prefix}settings
			WHERE variable = {literal:smiley_sets_known}',
		);
		list($smiley_sets_known) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);
		$dirs = explode(',', $smiley_sets_known);	

		while (true)
		{
			$result = ConverterDb::query('
				SELECT id_smiley, filename
				FROM {from_prefix}smileys
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => $blockSize
			]);

			$inserts = [];
			while ($row = ConverterDb::fetch_assoc($result))
			{
				foreach ($dirs as $dir)
				{
					// Skip it if it exists.
					if (file_exists($to_smileys_dir . '/' . $dir . '/' . $row['filename']))
						continue;
					
					// If it doesn't exist in the default in the old, skip it.
					if (file_exists($from_smileys_dir . '/default/' . $row['filename']))
						continue;

					// Copy it from the default
					@copy(
						$from_smileys_dir . '/default/' . $row['filename'],
						$to_smileys_dir . '/' . $dir . '/' . $row['filename']
					);
				}
			}
			if (ConverterDb::num_rows($result) < $blockSize)
				break;
			ConverterDb::free_result($result);

			Converter::pastTime($currentStart += $blockSize);
		}
	}

	public static string	$convertStep33info = 'Converting arachnids';
	public static function	 convertStep33(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}spiders',
				'resetauto' => '{to_prefix}spiders',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}spiders',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}spiders'
			],
			'process' => [
				'table' => '{to_prefix}spiders',
				'query' => '
					SELECT
						id_spider, spider_name, user_agent, ip_info
					FROM {from_prefix}spiders',
			],
		];
	}

	public static string	$convertStep34info = 'Converting subscriptions';
	public static function	 convertStep34(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}subscriptions',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}subscriptions',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}subscriptions'
			],
			'process' => [
				'table' => '{to_prefix}subscriptions',
				'query' => '
					SELECT
						id_subscribe, name, description, cost, length, id_group, add_groups, active, repeatable, allow_partial, reminder, email_complete
					FROM {from_prefix}subscriptions',
			],
		];
	}

	public static string	$convertStep35info = 'Converting log actions';
	public static function	 convertStep35(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_actions',
				'resetauto' => '{to_prefix}log_actions',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_actions',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_actions'
			],
			'process' => [
				'table' => '{to_prefix}log_actions',
				'query' => '
					SELECT
						id_action, id_log, log_time, id_member, ip, action, id_board, id_topic, id_msg, extra
					FROM {from_prefix}log_actions',
			],
		];
	}

	public static string	$convertStep36info = 'Converting log activity';
	public static function	 convertStep36(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_activity',
				'resetauto' => '{to_prefix}log_activity',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_activity',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_activity'
			],
			'process' => [
				'table' => '{to_prefix}log_activity',
				// case maters for detection of the proper databse type.
				'query' => '
					SELECT
						date AS DATE, hits, topics, posts, registers, most_on
					FROM {from_prefix}log_activity',
			],
		];
	}

	public static string	$convertStep37info = 'Converting log banned';
	public static function	 convertStep37(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_banned',
				'resetauto' => '{to_prefix}log_banned',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_banned',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_banned'
			],
			'process' => [
				'table' => '{to_prefix}log_banned',
				'query' => '
					SELECT
						id_ban_log, id_member, ip, email, log_time
					FROM {from_prefix}log_banned',
			],
		];
	}

	public static string	$convertStep38info = 'Converting log boards';
	public static function	 convertStep38(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_boards',
				'resetauto' => '{to_prefix}log_boards',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_boards',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_boards'
			],
			'process' => [
				'table' => '{to_prefix}log_boards',
				'query' => '
					SELECT
						id_member, id_board, id_msg
					FROM {from_prefix}log_boards',
			],
		];
	}

	public static string	$convertStep39info = 'Converting log comments';
	public static function	 convertStep39(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_comments',
				'resetauto' => '{to_prefix}log_comments',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_comments',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_comments'
			],
			'process' => [
				'table' => '{to_prefix}log_comments',
				'query' => '
					SELECT
						id_comment, id_member, member_name, comment_type, id_recipient, recipient_name, log_time, id_notice, counter, body
					FROM {from_prefix}log_comments',
			],
		];
	}

	public static string	$convertStep40info = 'Converting log digest';
	public static function	 convertStep40(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_digest',
				'resetauto' => '{to_prefix}log_digest',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_digest',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_digest'
			],
			'process' => [
				'table' => '{to_prefix}log_digest',
				'query' => '
					SELECT
						id_topic, id_msg, note_type, daily, exclude
					FROM {from_prefix}log_digest',
			],
		];
	}

	public static string	$convertStep41info = 'Converting log group requests';
	public static function	 convertStep41(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_group_requests',
				'resetauto' => '{to_prefix}log_group_requests',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_group_requests',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_group_requests'
			],
			'process' => [
				'table' => '{to_prefix}log_group_requests',
				'query' => '
					SELECT
						id_request, id_member, id_group, time_applied, reason
					FROM {from_prefix}log_group_requests',
			],
		];
	}

	public static string	$convertStep42info = 'Converting log mark read';
	public static function	 convertStep42(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_mark_read',
				'resetauto' => '{to_prefix}log_mark_read',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_mark_read',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_mark_read'
			],
			'process' => [
				'table' => '{to_prefix}log_mark_read',
				'query' => '
					SELECT
						id_member, id_board, id_msg
					FROM {from_prefix}log_mark_read',
			],
		];
	}

	public static string	$convertStep43info = 'Converting log moderator notices';
	public static function	 convertStep43(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_member_notices',
				'resetauto' => '{to_prefix}log_member_notices',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_member_notices',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_member_notices'
			],
			'process' => [
				'table' => '{to_prefix}log_member_notices',
				'query' => '
					SELECT
						id_notice, subject, body
					FROM {from_prefix}log_member_notices',
			],
		];
	}

	public static string	$convertStep44info = 'Converting log notify';
	public static function	 convertStep44(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_notify',
				'resetauto' => '{to_prefix}log_notify',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_notify',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_notify'
			],
			'process' => [
				'table' => '{to_prefix}log_notify',
				'query' => '
					SELECT
						id_member, id_topic, id_board, sent
					FROM {from_prefix}log_notify',
			],
		];
	}

	public static string	$convertStep45info = 'Converting log reported';
	public static function	 convertStep45(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_reported',
				'resetauto' => '{to_prefix}log_reported',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_reported',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_reported'
			],
			'process' => [
				'table' => '{to_prefix}log_reported',
				'query' => '
					SELECT
						id_report, id_msg, id_topic, id_board, id_member, membername, subject, body, time_started, time_updated, num_reports, closed, ignore_all
					FROM {from_prefix}log_reported',
			],
		];
	}

	public static string	$convertStep46info = 'Converting log reported comments';
	public static function	 convertStep46(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_reported_comments',
				'resetauto' => '{to_prefix}log_reported_comments',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_reported_comments',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_reported_comments'
			],
			'process' => [
				'table' => '{to_prefix}log_reported_comments',
				'query' => '
					SELECT
						id_comment, id_report, id_member, membername, email_address, member_ip, comment, time_sent
					FROM {from_prefix}log_reported_comments',
			],
		];
	}

	public static string	$convertStep47info = 'Converting log spider hits';
	public static function	 convertStep47(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_spider_hits',
				'resetauto' => '{to_prefix}log_spider_hits',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_spider_hits',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_spider_hits'
			],
			'process' => [
				'table' => '{to_prefix}log_spider_hits',
				'query' => '
					SELECT
						id_hit, id_spider, log_time, url, processed
					FROM {from_prefix}log_spider_hits',
			],
		];
	}

	public static string	$convertStep48info = 'Converting log spider stats';
	public static function	 convertStep48(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_spider_stats',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_spider_stats',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_spider_stats'
			],
			'process' => [
				'table' => '{to_prefix}log_spider_stats',
				'query' => '
					SELECT
						id_spider, page_hits, last_seen, stat_date
					FROM {from_prefix}log_spider_stats',
			],
		];
	}

	public static string	$convertStep49info = 'Converting log subscribed';
	public static function	 convertStep49(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_subscribed',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_subscribed',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_subscribed'
			],
			'process' => [
				'table' => '{to_prefix}log_subscribed',
				'query' => '
					SELECT
						id_sublog, id_subscribe, id_member, old_id_group, start_time, end_time, status, payments_pending, pending_details, reminder_sent, vendor_ref
					FROM {from_prefix}log_subscribed',
			],
		];
	}

	public static string	$convertStep50info = 'Converting log topics';
	public static function	 convertStep50(): array
	{
		return [
			'purge' => [
				'query' => 'TRUNCATE {to_prefix}log_topics',
			],
			'progress' => [
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}log_topics',
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}log_topics'
			],
			'process' => [
				'table' => '{to_prefix}log_topics',
				'query' => '
					SELECT
						id_member, id_topic, id_msg
					FROM {from_prefix}log_topics',
			],
		];
	}
}