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

class yabb25x_to_smf extends ConverterBase
{
	public static bool $purge = false;

	public static function info(): array
	{
		return [
			'name' => 'YaBB 2.5',
			'version' => 'SMF 2.1.*',
			'flatfile' => true,
			'settings' => ['/Paths.pl', '/Variables/Paths.pl'],
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
			'convertStep1' => 1, // Converting membergroups
			'convertStep2' => 3, // Converting membergroups
			'convertStep3' => 12, // Converting members
			'convertStep4' => 4, // Converting member options
			'convertStep5' => 1, // Converting settings
			'convertStep6' => 6, // Converting personal messages (part 1)
			'convertStep7' => 3, // Converting personal messages (part 2)
			'convertStep8' => 5, // Converting boards and categories
			'convertStep9' => 9, // Converting topics (part 1)
			'convertStep10' => 5, // Converting topics (part 2)
			'convertStep11' => 20, // Converting posts (part 1 - this may take some time)
			'convertStep12' => 12, // Converting posts (part 2)
			'convertStep13' => 8, // Converting attachments
			'convertStep14' => 5, // Cleaning up messages
			'convertStep15' => 2, // Converting polls and poll choices (part 1)
			'convertStep16' => 2, // Converting polls and poll choices (part 2)
			'convertStep17' => 2, // Converting poll votes
		];
	}

	public static array $blockSizes = [
		'members' => 100,
		'pms' => 100,
		'topics' => 1000,
		'posts1' => 5000,
		'posts2' => 10000,
		'attachments' => 100,
		'cleanup' => 150,
		'polls1' => 50,
		'polls2' => 200,
		'polls3' => 50,
	];

	public static function prepareSystem(): void
	{
		parent::prepareSystem();

		self::$purge = Converter::getParameter('purge') ?? false;
	}

	public static function fixRelativePath($path, $cwd_path): string
	{
		// Fix the . at the start, clear any duplicate slashes, and fix any trailing slash...
		return addslashes(preg_replace(array('~^\.([/\\\]|$)~', '~[/]+~', '~[\\\]+~', '~[/\\\]$~'), array($cwd_path . '$1', '/', '\\', ''), $path));
	}

	public static function loadConverterSettings(): void
	{
		global $yabb;

		if (empty(Converter::getVar('convertPathFrom')) || (!file_exists(Converter::getVar('convertPathFrom') . '/Paths.pl') && !file_exists(Converter::getVar('convertPathFrom') . '/Variables/Paths.pl')))
			return;

		if (file_exists(Converter::getVar('convertPathFrom') . '/Paths.pl'))
			$data = file(Converter::getVar('convertPathFrom') . '/Paths.pl');
		else
			$data = file(Converter::getVar('convertPathFrom') . '/Variables/Paths.pl');
		foreach ($data as $line)
		{
			$line = trim($line);
			if (empty($line) || substr($line, 0, 1) == '#')
				continue;

			if (preg_match('~\$([^ =]+?)\s*=\s*[q]?([\^"\']?)(.+?)\\2;~', $line, $match) != 0)
				$yabb[$match[1]] = $match[2] == '^' ? addslashes($match[3]) : $match[3];
		}

		$paths = array('boarddir', 'boardsdir', 'datadir', 'memberdir', 'sourcedir', 'vardir', 'facesdir', 'uploaddir');
		foreach ($paths as $path)
			$yabb[$path] = self::fixRelativePath($yabb[$path], Converter::getVar('convertPathFrom'));

		// In some cases $boarddir is not parsed causing the paths to be incorrect.
		foreach ($paths as $path)
			if (substr($yabb[$path], 0, 9) == '$boarddir')
				$yabb[$path] = str_replace('$boarddir', $yabb['boarddir'], $yabb[$path]);

		$data = file($yabb['vardir'] . '/Settings.pl');
		foreach ($data as $line)
		{
			$line = trim($line);
			if (empty($line) || substr($line, 0, 1) == '#')
				continue;

			if (preg_match('~\$([^ =]+?)\s*=\s*[q]?([\^"\']?)(.+?)\\2;~', $line, $match) != 0)
				$yabb[$match[1]] = $match[2] == '^' ? addslashes($match[3]) : $match[3];
		}
	}

	public static function parse_time(string $field, bool $use_now = true): string
	{
		$field = trim(str_replace([' um', ' de', ' en', ' la', ' om', ' at'], '', $field));

		if ($field == '')
			$field = $use_now ? time() : 0;
		elseif (strtotime($field) != -1)
			$field = strtotime($field);
		elseif (preg_match('~(\d\d)/(\d\d)/(\d\d)(.*?)(\d\d)\:(\d\d)\:(\d\d)~i', $field, $matches) != 0)
			$field = strtotime("$matches[5]:$matches[6]:$matches[7] $matches[1]/$matches[2]/$matches[3]");
		else
			$field = $use_now ? time() : 0;
		return date("Y-m-d", $field);
	}

	public static function doBlock(string $table, array &$block, bool $ignore = false, bool $return_first = false, bool $return_last = false, bool $no_prefix = false)
	{
		if (empty($block))
			return;

		if ($table == 'members')
		{
			$block_names = [];
			foreach ($block as $i => $row)
				$block_names[$row['member_name']] = $i;

			$request = ConverterDb::query('
				SELECT member_name
				FROM {to_prefix}members
				WHERE member_name IN ({array_string:block_names})
				LIMIT {int:block_count}',
				[
					'block_names' => array_keys($block_names),
					'block_count' => count($block_names)
			]);
			while ($row = ConverterDb::fetch_assoc($request))
				if (isset($block_names[$row['member_name']]))
					unset($block[$block_names[$row['member_name']]]);
			ConverterDb::free_result($request);

			if (empty($block))
				return;

			unset($block_names);
		}

		$insert_block = [];
		$first = 0;
		$last = 0;
		foreach ($block as $row)
		{
			if (isset($row['temp']))
			{
				$temp = $row['temp'];
				unset($row['temp']);
			}

			$result = ConverterDb::insert(
				'{to_prefix}' . $table,
				array_keys($row),
				$row,
				[], // Keys,
				$ignore ? 'ignore' : 'replace'
			);

			$last = ConverterDb::insert_id($table);
			if (empty($first))
				$first = $last;

			if (isset($temp))
				ConverterDb::insert(
					'{to_prefix}convert',
					['real_id', 'temp', 'type'],
					[$last, $temp, $table],
				);
		}

		$block = [];

		if ($return_first && $return_last)
			return [$first, $last];
		elseif ($return_first)
			return $first;
		elseif ($return_last)
			return $last;
	}

	public static string	$convertStep1info = 'Resetting temporary tales';
	public static function	 convertStep1Custom(): void
	{
		Converter::debugMsg('Dropping convert table');
		ConverterDb::drop_table('{to_prefix}convert');

		Converter::debugMsg('Creating convert table');
		ConverterDb::create_table(
			'{to_prefix}convert',
			[
				['name' => 'real_id',	'type' => 'tinytext', 'null' => false],
				['name' => 'temp',		'type' => 'tinytext', 'null' => false],
				['name' => 'type',		'type' => 'tinytext', 'null' => false],
			],
			[], // Indexes
			[], // Params
			'overwrite', // if_exists
		);
	}

	public static string	$convertStep2info = 'Converting membergroups';
	public static function	 convertStep2Custom(): void
	{
		global $yabb;

		$knownGroups = $extraGroups = [];
		$newbie = false;

		$groups = file($yabb['vardir'] . '/Settings.pl');
		foreach ($groups as $i => $group)
		{
			if (preg_match('~^\$Group\{\'(Administrator|Global Moderator|Moderator)\'\} = [\'|"]([^|]*)\|(\d*)\|([^|]*)\|([^|]*)~', $group, $match) != 0)
			{
				$id_group = $match[1] == 'Administrator' ? 1 : ($match[1] == 'Global Moderator' ? 2 : 3);
				$knownGroups[] = [
					$id_group,
					substr($match[2], 0, 80),
					substr($match[5], 0, 20),
					-1,
					substr($match[3] . '#' . $match[4], 0, 255),
				];
			}
			elseif (preg_match('~\$Post\{\'(\d+)\'\} = [\'|"]([^|]*)\|(\d*)\|([^|]*)\|([^|]*)~', $group, $match) != 0)
			{
				$extraGroups[] = [
					substr($match[2], 0, 80),
					substr($match[5], 0, 20),
					max(0, $match[0]),
					substr($match[3] . '#' . $match[4], 0, 255),
				];

				if ($match[3] < 1)
					$newbie = true;
			}
			elseif (preg_match('~\$NoPost\{\'?(\d+)\'?\} = [\'|"]([^|]*)\|(\d*)\|([^|]*)\|([^|]*)~', $group, $match) != 0)
				$extraGroups[] = [
					substr($match[2], 0, 80),
					substr($match[5], 0, 20),
					-1,
					substr($match[3] . '#' . $match[4], 0, 255),
				];
		}

		if (self::$purge)
		{
			Converter::debugMsg('Purging old membergroup');
			ConverterDb::query('
				DELETE FROM {to_prefix}permissions
				WHERE id_group > ' . ($newbie ? 3 : 4));
			ConverterDb::query('
				DELETE FROM {to_prefix}membergroups
				WHERE id_group > ' . ($newbie ? 3 : 4));
		}

		Converter::debugMsg('Adding Membergroups');
		if (!empty($knownGroups))
			ConverterDb::insert(
				'{to_prefix}membergroups',
				['id_group', 'group_name', 'online_color', 'min_posts', 'icons'],
				$knownGroups,
				[], // keys
				'replace'
			);

		if (!empty($extraGroups))
			ConverterDb::insert(
				'{to_prefix}membergroups',
				['group_name', 'online_color', 'min_posts', 'icons'],
				$extraGroups,
			);
	}

	public static string	$convertStep3info = 'Converting members';
	public static function	 convertStep3Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') == 0 && self::$purge)
			ConverterDb::query('TRUNCATE {to_prefix}members');

		Converter::pastTime(0);

		$request = ConverterDb::query('
			SELECT id_group, group_name
			FROM {to_prefix}membergroups
			WHERE id_group != 3');
		$groups = [
			'Administrator' => 1,
			'Global Moderator' => 2,
			'Moderator' => 0
		];
		while ($row = ConverterDb::fetch_assoc($request))
			$groups[$row['group_name']] = $row['id_group'];
		ConverterDb::free_result($request);

		$currentStart = Converter::getVar('currentStart');
		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$block = $block_options = [];
		$text_columns = [
			'member_name' => 80,
			'lngfile' => 255,
			'real_name' => 255,
			'buddy_list' => 255,
			'pm_ignore_list' => 255,
			'passwd' => 64,
			'email_address' => 255,
			'personal_text' => 255,
			'website_title' => 255,
			'website_url' => 255,
			'time_format' => 80,
			'signature' => 255,
			'avatar' => 255,
			'usertitle' => 255,
			'member_ip' => 255,
			'member_ip2' => 255,
			'secret_question' => 255,
			'secret_answer' => 64,
			'validation_code' => 10,
			'additional_groups' => 255,
			'smiley_set' => 48,
			'password_salt' => 5,
		];

		if (Converter::getVar('currentStart') > 0)
			Converter::debugMsg('Current Start:' . Converter::getVar('currentStart'));

		while ($entry = $dir->read())
		{
			if ($currentStart < 0)
				break;
			else if ($file_n++ < $currentStart)
				continue;
			else if (strrchr($entry, '.') != '.vars' && strrchr($entry, '.') != '.dat')
				continue;

			$name = substr($entry, 0, strrpos($entry, '.'));

			$userData = file($yabb['memberdir'] . '/' . $entry);
			if (count($userData) < 3)
				continue;

			$data = [];
			foreach ($userData as $i => $v)
			{
				$userData[$i] = trim($userData[$i]);

				if (strrchr($entry, '.') == '.vars' && preg_match('~^\'([^\']+)\',"([^"]+)"~', $userData[$i], $match) != 0)
					$data[$match[1]] = $match[2];
			}

			// Is it an invalid user?
			if (empty($data))
				continue;

			if (strrchr($entry, '.') != '.vars')
			{
				$userData = array_pad($userData, 31, '');
				$data = [
					'password' => $userData[0],
					'realname' => $userData[1],
					'email' => $userData[2],
					'webtitle' => $userData[3],
					'weburl' => $userData[4],
					'signature' => $userData[5],
					'postcount' => $userData[6],
					'position' => $userData[7],
					'usertext' => $userData[12],
					'userpic' => $userData[13],
					'regdate' => $userData[14],
					'bday' => $userData[16],
					'lastonline' => $userData[23],
					'im_ignorelist' => $userData[26],
					'im_notify' => $userData[27],
				];
			}

			$row = [
				'member_name' => substr(htmlspecialchars(trim($name)), 0, 80),
				'passwd' => strlen($data['password']) == 22 ? bin2hex(base64_decode($data['password'])) : md5($data['password']),
				'real_name' => htmlspecialchars($data['realname']),
				'email_address' => htmlspecialchars($data['email']),
				'website_title' => isset($data['website']) ? htmlspecialchars($data['webtitle']) : '',
				'website_url' => isset($data['weburl']) ? htmlspecialchars($data['weburl']) : '',
				'signature' => isset($data['signature']) ? str_replace(['&amp;&amp;', '&amp;lt;', '&amp;gt;'], ['<br />', '&lt;'. '&gt;'], strtr($data['signature'], ['\'' => '&#039;'])) : '',
				'posts' => (int) $data['postcount'],
				'id_group' => isset($data['position']) && isset($groups[$data['position']]) ? $groups[$data['position']] : 0,
				'personal_text' => isset($data['usertext']) ? htmlspecialchars($data['usertext']) : '',
				'avatar' => $data['userpic'],
				'date_registered' => (int) self::parse_time($data['regdate'] ?? '1970-01-01'),
				'birthdate' => isset($data['bday']) ? ($data['bday'] == '' || strtotime($data['bday']) == 0 ? '0001-01-01' : strftime('%Y-%m-%d', strtotime($data['bday']))) : '0001-01-01',
				'last_login' => isset($data['lastonline']) ? $data['lastonline'] : '0',
				'ignore_boards' => '',
			];

			// Make sure these columns have a value and don't exceed max width.
			foreach ($text_columns as $text_column => $max_size)
				$row[$text_column] = isset($row[$text_column]) ? substr($row[$text_column], 0, $max_size) : '';

			if ($row['birthdate'] == '0001-01-01' && !empty($data['bday']) && self::parse_time($data['bday'], false) != 0)
				$row['birthdate'] = strftime('%Y-%m-%d', self::parse_time($data['bday'], false));

			$block[] = $row;

			if (count($block) > self::getBlockSize('members'))
			{
				self::doBlock('members', $block);
				Converter::pastTime($file_n);
			}
		}
		$dir->close();

		self::doBlock('members', $block);
		Converter::debugMsg('Finished');
	}

	public static string	$convertStep4info = 'Converting member options';
	public static function	 convertStep4Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') == 0 && self::$purge)
			ConverterDb::query('DELETE FROM {to_prefix}themes WHERE id_member > 0');

		Converter::pastTime(0);

		$currentStart = Converter::getVar('currentStart');
		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$block = $names = [];

		if (Converter::getVar('currentStart') > 0)
			Converter::debugMsg('Current Start:' . Converter::getVar('currentStart'));

		while ($entry = $dir->read())
		{
			if ($currentStart < 0)
				break;
			else if ($file_n++ < $currentStart)
				continue;
			else if (strrchr($entry, '.') != '.vars' && strrchr($entry, '.') != '.dat')
				continue;

			$name = substr($entry, 0, strrpos($entry, '.'));

			$userData = file($yabb['memberdir'] . '/' . $entry);
			if (count($userData) < 3)
				continue;

			$data = [];
			foreach ($userData as $i => $v)
			{
				$userData[$i] = trim($userData[$i]);

				if (strrchr($entry, '.') == '.vars' && preg_match('~^\'([^\']+)\',"([^"]+)"~', $userData[$i], $match) != 0)
					$data[$match[1]] = $match[2];
			}

			// Is it an invalid user?
			if (empty($data))
				continue;

			if (strrchr($entry, '.') != '.vars')
			{
				$userData = array_pad($userData, 31, '');
				$data = [
					'icq' => $userData[8],
					'gender' => $userData[11],
					'location' => $userData[15],
				];
			}

			$member_name = substr(htmlspecialchars(trim($name)), 0, 80);
			$names[] = $member_name;

			$block[] = [
				'temp' => $member_name,
				'id_member' => 0,
				'id_theme' => 0,
				'variable' => 'cust_icq',
				'value' => isset($data['icq']) ? substr(htmlspecialchars($data['icq']), 0, 255) : '',
			];

			$block[] = [
				'temp' => $member_name,
				'id_member' => 0,
				'id_theme' => 0,
				'variable' => 'cust_gender',
				'value' => isset($data['gender']) ? ($data['gender'] == 'Male' ? 1 : ($data['gender'] == 'Female' ? 2 : 0)) : 0,
			];

			$block[] = [
				'temp' => $member_name,
				'id_member' => 0,
				'id_theme' => 0,
				'variable' => 'cust_loca',
				'value' => isset($data['location']) ? substr(htmlspecialchars($data['location']), 0, 255) : '',
			];

			if (count($block) > self::getBlockSize('members'))
			{
				$result = ConverterDb::query('
					SELECT id_member, member_name
					FROM {to_prefix}members
					WHERE member_name IN ({array_string:member_names})
					LIMIT {int:member_names_count}',
					[
						'member_names' => $names,
						'member_names_count' => count($names)
				]);
				while ($row = ConverterDb::fetch_assoc($result))
					foreach ($block[] as $k => &$v)
						if ($v['temp'] == $row['member_name'])
						{
							unset($v['temp']);
							$v['id_member'] = $row['id_member'];
						}
				ConverterDb::free_result($result);
				foreach ($block[] as $k => &$v)
					if (isset($v['temp']) || empty($v['id_member']))
						unset($v);

				self::doBlock('themes', $block, true);
				ConverterDb::pastTime($file_n);
			}
		}
		$dir->close();

		if (!empty($block))
		{
			$result = ConverterDb::query('
				SELECT id_member, member_name
				FROM {to_prefix}members
					WHERE member_name IN ({array_string:member_names})
					LIMIT {int:member_names_count}',
					[
						'member_names' => $names,
						'member_names_count' => count($names)
				]);
			while ($row = ConverterDb::fetch_assoc($result))
				foreach ($block as $k => &$v)
					if ($v['temp'] == $row['member_name'])
					{
						unset($block[$k]['temp']);
						$v['id_member'] = $row['id_member'];
					}
			ConverterDb::free_result($result);
			foreach ($block as $k => &$v)
				if (isset($v['temp']) || empty($v['id_member']))
					unset($v);

			self::doBlock('themes', $block, true);
		}

		Converter::debugMsg('Finished');
	}

	public static string	$convertStep5info = 'Converting settings';
	public static function	 convertStep5Custom(): void
	{
		global $yabb;

		$temp = file($yabb['vardir'] . '/reservecfg.txt');
		$settings = [
			'allow_guestAccess' => isset($yabb['guestaccess']) ? (int) $yabb['guestaccess'] : 0,
			'news' => strtr(implode('', file($yabb['vardir'] . '/news.txt')), array("\r" => '')),
			'cookieTime' => !empty($yabb['Cookie_Length']) && $yabb['Cookie_Length'] > 1 ? (int) $yabb['Cookie_Length'] : 60,
			'requireAgreement' => !empty($yabb['RegAgree']) ? 1 : 0,
			'registration_method' => !empty($yabb['emailpassword']) ? 1 : 0,
			'send_validation_onChange' => !empty($yabb['emailnewpass']) ? 1 : 0,
			'send_welcomeEmail' => !empty($yabb['emailwelcome']) ? 1 : 0,
			'mail_type' => empty($yabb['mailtype']) ? 0 : 1,
			'smtp_host' => isset($yabb['smtp_server']) ? $yabb['smtp_server'] : '',
			'smtp_username' => !empty($yabb['smtp_auth_required']) && isset($yabb['authuser']) ? $yabb['authuser'] : '',
			'smtp_password' => !empty($yabb['smtp_auth_required']) && isset($yabb['authpass']) ? $yabb['authpass'] : '',
			'defaultMaxTopics' => !empty($yabb['maxdisplay']) ? (int) $yabb['maxdisplay'] : 20,
			'defaultMaxMessages' => !empty($yabb['maxmessagedisplay']) ? (int) $yabb['maxmessagedisplay'] : 15,
			'max_messageLength' => !empty($yabb['MaxMessLen']) ? (int) $yabb['MaxMessLen'] : 10000,
			'max_signatureLength' => (int) $yabb['MaxSigLen'],
			'spamWaitTime' => (int) $yabb['timeout'],
			'hotTopicPosts' => isset($yabb['HotTopic']) ? (int) $yabb['HotTopic'] : 15,
			'hotTopicVeryPosts' => isset($yabb['VeryHotTopic']) ? (int) $yabb['VeryHotTopic'] : 25,
			'avatar_max_width_external' => isset($yabb['userpic_width']) ? (int) $yabb['userpic_width'] : 0,
			'avatar_max_height_external' => isset($yabb['userpic_height']) ? (int) $yabb['userpic_height'] : 0,
			'avatar_max_width_upload' => isset($yabb['userpic_width']) ? (int) $yabb['userpic_width'] : 0,
			'avatar_max_height_upload' => isset($yabb['userpic_height']) ? (int) $yabb['userpic_height'] : 0,
			'reserveWord' => trim($temp[0]) == 'checked' ? '1' : '0',
			'reserveCase' => trim($temp[1]) == 'checked' ? '1' : '0',
			'reserveUser' => trim($temp[2]) == 'checked' ? '1' : '0',
			'reserveName' => trim($temp[3]) == 'checked' ? '1' : '0',
			'reserveNames' => strtr(implode('', file($yabb['vardir'] . '/reserve.txt')), array("\r" => '')),
		];

		$inserts = [];
		array_walk($settings, function($v, $k) use(&$inserts) {
			$inserts[] = [$k, substr($v, 0, 65534)];
		});

		ConverterDb::insert(
			'{to_prefix}settings',
			['variable', 'value'],
			$inserts,
			['variable'], // Keys
			'replace'
		);
	}

	public static string	$convertStep6info = 'Converting personal messages (part 1)';
	public static function	 convertStep6Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') == 0 && self::$purge)
		{
			ConverterDb::query('TRUNCATE {to_prefix}personal_messages');
			ConverterDb::query('TRUNCATE {to_prefix}pm_recipients');
		}

		$currentStart = Converter::getVar('currentStart');
		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$block = $names = [];

		if (Converter::getVar('currentStart') > 0)
			Converter::debugMsg('Current Start:' . Converter::getVar('currentStart'));

		while ($entry = $dir->read())
		{
			if ($currentStart < 0)
				break;
			else if ($file_n++ < $currentStart)
				continue;
			else if (strrchr($entry, '.') != '.msg' && strrchr($entry, '.') != '.outbox')
				continue;

			$is_outbox = strrchr($entry, '.') == '.outbox';

			$userData = file($yabb['memberdir'] . '/' . $entry);
			foreach ($userData as $i => $v)
			{
				$userData[$i] = explode('|', rtrim($userData[$i]));
				if (count($userData[$i]) <= 2 || empty($userData[$i]))
					continue;

				if (isset($userData[$i][3]) && substr($userData[$i][3], -10) == '#nosmileys')
					$userData[$i][3] = substr($userData[$i][3], 0, -10);

				$row = [
					'from_name' => substr(htmlspecialchars($userData[$i][1]), 0, 255),
					'subject' => substr($userData[$i][5], 0, 255),
					'msgtime' => !empty($userData[$i][6]) ? (int) $userData[$i][6] : '0',
					'body' => substr(!empty($userData[$i][3]) || empty($userData[$i][7]) ? $userData[$i][3] : $userData[$i][7], 0, 65534),
					'id_member_from' => 0,
					'deleted_by_sender' => $is_outbox ? 0 : 1,
					'temp' => htmlspecialchars(substr($entry, 0, -4)),
				];

				$names[strtolower($row['from_name'])][] = &$row['id_member_from'];

				$block[] = $row;
			}

			if (count($block) > self::getBlockSize('pms'))
			{
				$result = ConverterDb::query('
					SELECT id_member, member_name
					FROM {to_prefix}members
					WHERE member_name IN ({array_string:member_names})
					LIMIT {int:member_names_count}',
					[
						'member_names' => array_keys($names),
						'member_names_count' => count($names)
				]);
				while ($row = ConverterDb::fetch_assoc($result))
					foreach ($names[strtolower($row['member_name'])] as $k => $v)
						$names[strtolower($row['member_name'])][$k] = $row['id_member'];
				ConverterDb::free_result($result);
				$names = [];

				self::doBlock('personal_messages', $block);
				ConverterDb::pastTime($file_n);
			}
		}
		$dir->close();

		if (!empty($block))
		{
			$result = ConverterDb::query('
				SELECT id_member, member_name
				FROM {to_prefix}members
				WHERE member_name IN ({array_string:member_names})
				LIMIT {int:member_names_count}',
				[
					'member_names' => array_keys($names),
					'member_names_count' => count($names)
			]);
			while ($row = ConverterDb::fetch_assoc($result))
				foreach ($names[strtolower($row['member_name'])] as $k => $v)
					$names[strtolower($row['member_name'])][$k] = $row['id_member'];
			ConverterDb::free_result($result);

			$result = ConverterDb::query("
				SELECT id_member, member_name
				FROM {to_prefix}members
				WHERE member_name IN ('" . implode("', '", array_keys($names)) . "')
				LIMIT " . count($names));
			while ($row = ConverterDb::fetch_assoc($result))
			{
				foreach ($names[strtolower(addslashes($row['member_name']))] as $k => $v)
					$names[strtolower(addslashes($row['member_name']))][$k] = $row['id_member'];
			}
			ConverterDb::free_result($result);
			$names = [];

			self::doBlock('personal_messages', $block);
		}
	}

	public static string	$convertStep7info = 'Converting personal messages (part 2)';
	public static function	 convertStep7Custom(): void
	{
		ConverterDb::query('
			INSERT IGNORE INTO {to_prefix}pm_recipients
				(id_pm, id_member, is_read)
			SELECT pm.id_pm, mem.id_member, 1 AS is_read
			FROM {to_prefix}personal_messages AS pm
				INNER JOIN {to_prefix}convert AS c
					ON (c.type = {literal:personal_messages} AND c.real_id = pm.id_pm)
				INNER JOIN {to_prefix}members AS mem
					ON (mem.member_name = c.temp)
			WHERE pm.deleted_by_sender = 1
			ORDER BY id_pm, msgtime'
				. (ConverterDb::IsTitle(POSTGRE_TITLE) ? '
			ON CONFLICT DO NOTHING' : '')
		);
	}

	public static string	$convertStep8info = 'Converting boards and categories';
	public static function	 convertStep8Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') == 0 && self::$purge)
		{
			ConverterDb::query('TRUNCATE {to_prefix}categories');
			ConverterDb::query('TRUNCATE {to_prefix}boards');
			ConverterDb::query('TRUNCATE {to_prefix}moderators');

			ConverterDb::insert(
				'{to_prefix}settings',
				['variable', 'value'],
				[
					['recycle_enable', 0],
					['recycle_board', 0],
				],
				['variable'], // Keys
				'replace'
			);
		}

		$request = ConverterDb::query('
			SELECT id_group, group_name
			FROM {to_prefix}membergroups
			WHERE id_group != 3');
		$groups = [
			'Administrator' => 1,
			'Global Moderator' => 2,
			'Moderator' => 0
		];
		while ($row = ConverterDb::fetch_assoc($request))
			$groups[$row['group_name']] = $row['id_group'];
		ConverterDb::free_result($request);

		$cat_data = file($yabb['boardsdir'] . '/forum.master');
		$cat_order = $cats = $boards = [];
		foreach ($cat_data as $line)
		{
			if (preg_match('~^\$board\{\'(.+?)\'\} = ([^|]+)~', $line, $match) != 0)
				$boards[$match[1]] = trim($match[2], '"');
			elseif (preg_match('~^\$catinfo\{\'(.+?)\'\} = ([^|]+?)\|([^|]*?)\|([^|]+?);~', $line, $match) != 0)
			{
				$match[3] = explode(',', $match[3]);
				if (trim($match[3][0]) == '')
					$cat_groups = array_merge($groups, [2, 0, -1]);
				else
				{
					$cat_groups = [2];
					foreach ($match[3] as $group)
					{
						if (isset($groups[trim($group)]))
							$cat_groups[] = $groups[trim($group)];
					}
				}

				// Make the tempCatID lowercase
				$match[1] = strtolower(trim($match[1]));

				$cats[$match[1]]['name'] = trim($match[2], '"');
				$cats[$match[1]]['groups'] = implode(',', $cat_groups);
				$cats[$match[1]]['can_collapse'] = !empty($match[4]);
			}
			elseif (preg_match('~^@categoryorder = qw\((.+?)\);~', $line, $match) != 0)
				$cat_order = array_flip(explode(' ', strtolower(trim($match[1]))));
		}

		$cat_rows = [];
		foreach ($cats as $temp_id => $cat)
		{
			$temp_id = strtolower(trim($temp_id));
			$cat_rows[] = [
				'name' => str_replace(array('qq~', 'qw~'), '', substr($cat['name'], 0, 255)),
				'cat_order' => (int) @$cat_order[$temp_id],
				'description' => '',
				'temp' => $temp_id,
			];
		}
		self::doBlock('categories', $cat_rows);

		$request = ConverterDb::query('
			SELECT cat.id_cat AS id_cat, con.temp AS cat_temp
			FROM {to_prefix}categories AS cat
				INNER JOIN {to_prefix}convert AS con
					ON (con.type = {literal:categories} AND con.real_id = cat.id_cat)');
		$catids = [];
		while ($row = ConverterDb::fetch_assoc($request))
			$catids[$row['cat_temp']] = $row['id_cat'];

		$board_data = file($yabb['boardsdir'] . '/forum.control');
		$board_order = 1;
		$moderators = $board_rows = [];
		$recycle_board = '';
		foreach ($board_data as $line)
		{
			list ($tempCatID, $temp_id, , $description, $mods, , , , , $doCountPosts, , , $is_recycle) = explode('|', rtrim($line));

			// Is this the recycle board?
			if ($is_recycle == 1)
				$recycle_board = $temp_id;

			// Set lower case since case matters in PHP
			$tempCatID = strtolower(trim($tempCatID));

			$board_rows[] = [
				'name' => !isset($boards[$temp_id]) ? $temp_id : str_replace(['qq~', 'qw~'], '', substr($boards[$temp_id], 0, 255)),
				'description' => self::hmtl_to_bbc(substr($description, 0, 500)),
				'count_posts' => empty($doCountPosts) ? 0 : 1,
				'board_order' => $board_order++,
				'member_groups' => !empty($tempCatID) && !empty($cats[$tempCatID]['groups']) ? $cats[$tempCatID]['groups'] : '1',
				'temp' => $temp_id,
				'id_cat' => !empty($tempcatID) ? $catids[$tempCatID] : 1,
			];

			$moderators[$temp_id] = preg_split('~(, | |,)~', $mods);
		}
		self::doBlock('boards', $board_rows);

		foreach ($moderators as $boardid => $names)
		{
			$result = ConverterDb::query('
				SELECT b.id_board
				FROM {to_prefix}boards AS b
					INNER JOIN {to_prefix}convert AS con
						ON (con.type = {literal:boards} AND con.real_id = b.id_board)
				WHERE con.temp = {string:board}
				LIMIT 1',
				[
					'board' => $boardid,
			]);
			list ($id_board) = ConverterDb::fetch_row($result);
			ConverterDb::free_result($result);

			ConverterDb::query('
				INSERT IGNORE INTO {to_prefix}moderators
					(id_board, id_member)
				SELECT {int:board}, id_member
				FROM {to_prefix}members
				WHERE member_name IN ({array_string:members})
				LIMIT {int:member_count}',
				[
					'board' => $id_board,
					'members' => $names,
					'member_count' => count($names)
			]);
		}

		// Set our recycle board if we got one.
		if (!empty($recycle_board))
		{
			$result = ConverterDb::query('
				SELECT b.id_board
				FROM {to_prefix}boards AS b
					INNER JOIN {to_prefix}convert AS con
						ON (con.type = {literal:boards} AND con.real_id = b.id_board)
				WHERE con.temp = {string:board}
				LIMIT 1',
				[
					'board' => $recycle_board,
			]);
			list ($id_board) = ConverterDb::fetch_row($result);
			ConverterDb::free_result($result);

			if (!empty($id_board))
				ConverterDb::insert(
					'{to_prefix}settings',
					['variable', 'value'],
					[
						['recycle_enable', 1],
						['recycle_board', $id_board],
					],
					['variable'], // Keys
					'replace'
				);
		}
	}

	public static string	$convertStep9info = 'Converting topics (part 1)';
	public static function	 convertStep9Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') == 0 && self::$purge)
			ConverterDb::query('TRUNCATE {to_prefix}topics');

		$result = ConverterDb::query('
			SELECT b.id_board, con.temp
			FROM {to_prefix}boards AS b
				INNER JOIN {to_prefix}convert AS con
					ON (con.type = {literal:boards} AND con.real_id = b.id_board)');
		$boards = [];
		while ($row = ConverterDb::fetch_assoc($result))
			$boards[$row['temp']] = $row['id_board'];
		ConverterDb::free_result($result);

		$currentStart = Converter::getVar('currentStart');
		$data_n = 0;
		$block = [];

		if (Converter::getVar('currentStart') > 0)
			Converter::debugMsg('Current Start:' . Converter::getVar('currentStart'));

		foreach ($boards as $boardname => $id_board)
		{
			if ($currentStart < 0)
				break;
			else if (!file_exists($yabb['boardsdir'] . '/' . $boardname . '.txt'))
				continue;

			$topicListing = file($yabb['boardsdir'] . '/' . $boardname . '.txt');
			$topicListing = array_reverse($topicListing);

			foreach ($topicListing as $topicData)
			{
				if ($data_n++ < $currentStart)
					continue;

				$topicInfo = explode('|', rtrim($topicData));
				$temp_id = (int) $topicInfo[0];

				if (!file_exists($yabb['datadir'] . '/' . $temp_id . '.txt'))
					continue;

				$views = @implode('', file($yabb['datadir'] . '/' . $temp_id . '.ctb'));
				if (preg_match('~\'views\',"([^"]+)"~', $views, $match) != 0)
					$views = $match[1];

				$block[] = [
					'temp' => $temp_id,
					'id_board' => $id_board,
					'is_sticky' => isset($topicInfo[8]) && strpos($topicInfo[8], 's') !== false ? 1 : 0,
					'locked' => isset($topicInfo[8]) && strpos($topicInfo[8], 'l') !== false ? 1 : 0,
					'num_views' => (int) $views < 0 ? 0 : $views,
					// Give this some bs value.
					'id_last_msg' => $temp_id,
					'id_first_msg' => $temp_id,
				];

				if (count($block) > self::getBlockSize('topics'))
				{
					self::doBlock('topics', $block);
					Converter::pastTime($data_n);
				}
			}
		}

		self::doBlock('topics', $block);
	}

	public static string	$convertStep10info = 'Converting topics (part 2)';
	public static function	 convertStep10Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') == 0 && self::$purge)
		{
			ConverterDb::query('TRUNCATE {to_prefix}log_boards');
			ConverterDb::query('TRUNCATE {to_prefix}log_mark_read');
			ConverterDb::query('TRUNCATE {to_prefix}log_topics');
		}

		Converter::pastTime(0);

		$result = ConverterDb::query('
			SELECT b.id_board, con.temp
			FROM {to_prefix}boards AS b
				INNER JOIN {to_prefix}convert AS con
					ON (con.type = {literal:boards} AND con.real_id = b.id_board)');
		$boards = [];
		while ($row = ConverterDb::fetch_assoc($result))
			$boards[$row['temp']] = $row['id_board'];
		ConverterDb::free_result($result);

		$result = ConverterDb::query('
			SELECT t.id_topic, con.temp
			FROM {to_prefix}topics AS t
				INNER JOIN {to_prefix}convert AS con
					ON (con.type = {literal:boards} AND con.real_id = t.id_topic)');
		$topics = [];
		while ($row = ConverterDb::fetch_assoc($result))
			$topics[$row['temp']] = $row['id_topic'];
		ConverterDb::free_result($result);

		$currentStart = Converter::getVar('currentStart');
		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$mark_read_block = $boards_block = $topics_block = [];

		while ($entry = $dir->read())
		{
			if ($currentStart < 0)
				break;
			if ($file_n++ < $currentStart)
				continue;
			if (strrchr($entry, '.') != '.log')
				continue;

			$result = ConverterDb::query('
				SELECT id_member
				FROM {to_prefix}members
				WHERE member_name = {string:member}
				LIMIT 1',
				[
					'member' => substr($entry, 0, -4)
			]);
			list ($id_member) = ConverterDb::fetch_row($result);
			ConverterDb::free_result($result);

			$logData = file($yabb['memberdir'] . '/' . $entry);
			foreach ($logData as $log)
			{
				$parts = array_pad(explode('|', $log), 3, '');
				if (trim($parts[0]) == '')
					continue;

				$row = [];
				$row['id_member'] = $id_member;

				if (is_numeric(trim($parts[0])) && isset($topics[trim($parts[0])]) && trim($parts[0]) > 10000)
				{
					$row['id_topic'] = $topics[trim($parts[0])];
					$topics_block[] = $row;
				}
				else
				{
					if (substr(trim($parts[0]), -6) == '--mark' && isset($boards[substr(trim($parts[0]), 0, -6)]))
					{
						$row['id_board'] = $boards[substr(trim($parts[0]), 0, -6)];
						$mark_read_block[] = $row;
					}
					elseif (isset($boards[trim($parts[0])]))
					{
						$row['id_board'] = $boards[trim($parts[0])];
						$boards_block[] = $row;
					}
				}
			}

			// Because of the way steps are done, we have to flush all of these at once, or none.
			if (count($mark_read_block) > 250 || count($boards_block) > 250 || count($topics_block) > 250)
			{
				self::doBlock('log_mark_read', $mark_read_block, true);
				self::doBlock('log_boards', $boards_block, true);
				self::doBlock('log_topics', $topics_block, true);

				Converter::pastTime($file_n);
			}
		}
		$dir->close();

		self::doBlock('log_mark_read', $mark_read_block, true);
		self::doBlock('log_boards', $boards_block, true);
		self::doBlock('log_topics', $topics_block, true);

		Converter::debugMsg('Finished');
	}

	public static string	$convertStep11info = 'Converting posts (part 1 - this may take some time)';
	public static function	 convertStep11Custom(): void
	{
		global $yabb;

		if (Converter::getVar('currentStart') <= 0 && self::$purge)
		{
			ConverterDb::query('TRUNCATE {to_prefix}messages');
			Converter::pastTime(-2);

			self::removeAllAttachments();
			Converter::pastTime(-1);

			ConverterDb::query('TRUNCATE {to_prefix}attachments');
			Converter::pastTime(0);
		}

		$currentStart = Converter::getVar('currentStart');
		$block = [];
		while (true)
		{
			$result = ConverterDb::query('
				SELECT t.id_topic, con.temp, t.id_board
				FROM {to_prefix}topics AS t
					INNER JOIN {to_prefix}convert AS con
						ON (con.type = {literal:topics} AND con.real_id = t.id_topic)
				WHERE t.id_first_msg = con.temp
				LIMIT {int:block_size}',
				[
					'block_size' => self::getBlockSize('posts1')
			]);
			while ($topic = ConverterDb::fetch_assoc($result))
			{
				$messages = file($yabb['datadir'] . '/' . $topic['temp'] . '.txt');
				if (empty($messages))
				{
					ConverterDb::query('
						DELETE FROM {to_prefix}topics
						WHERE id_topic = {int:id_topic}
						LIMIT 1',
						[
							'id_topic' => $topic['id_topic']
					]);

					Converter::pastTime($currentStart);
					continue;
				}

				foreach ($messages as $message)
				{
					if (trim($message) == '')
						continue;

					$message = array_pad(explode('|', $message), 12, '');
					foreach ($message as $k => $v)
						$message[$k] = rtrim($v);

					if (substr($message[8], -10) == '#nosmileys')
						$message[8] = substr($message[8], 0, -10);

					$row = [
						'id_topic' => (int) $topic['id_topic'],
						'id_board' => (int) $topic['id_board'],
						'subject' => substr($message[0], 0, 255),
						'poster_name' => substr(htmlspecialchars($message[4] == 'Guest' ? trim($message[1]) : trim($message[4])), 0, 255),
						'poster_email' => substr(htmlspecialchars($message[2]), 0, 255),
						'poster_time' => !empty($message[3]) ? $message[3] : 0,
						'icon' => substr($message[5], 0, 16),
						'poster_ip' => substr($message[7], 0, 255),
						'body' => substr(preg_replace('~\[quote author=.+? link=.+?\]~i', '[quote]', $message[8]), 0, 65534),
						'smileys_enabled' => empty($message[9]) ? 1 : 0,
						'modified_time' => !empty($message[10]) ? $message[10] : 0,
						'modified_name' => substr($message[11], 0, 255),
					];

					// Do we have attachments?.
					if (isset($yabb['uploaddir']) && !empty($message[12]) && file_exists($yabb['uploaddir'] . '/' . $message[12]))
						ConverterDb::insert(
							'{to_prefix}convert',
							['real_id', 'temp', 'type'],
							[$message[12], $row['poster_time'] . ':' . $row['poster_name'], 'msg_attach'],
						);

					$block[] = $row;

					if (count($block) > self::getBlockSize('posts1'))
					{
						list($first, $last) = self::doBlock('messages', $block, false, true, true);
						ConverterDb::query('
							UPDATE {to_prefix}topics
							SET id_first_msg = {int:first},
								id_last_msg = {int:last}
							WHERE id_topic = {int:topic}',
							[
								'first' => $first,
								'last' => $last,
								'id_topic' => $topic['id_topic']
						]);

						Converter::pastTime($currentStart + count($block));
					}
				}

				list($first, $last) = self::doBlock('messages', $block, false, true, true);
				if (!empty($first) && !empty($last))
					ConverterDb::query('
						UPDATE {to_prefix}topics
						SET id_first_msg = {int:first},
							id_last_msg = {int:last}
						WHERE id_topic = {int:topic}',
						[
							'first' => $first,
							'last' => $last,
							'topic' => $topic['id_topic']
					]);

				Converter::pastTime($currentStart + count($block));
			}

			if (ConverterDb::num_rows($result) < self::getBlockSize('posts1'))
				break;

			ConverterDb::free_result($result);
		}

		list($first, $last) = self::doBlock('messages', $block, false, true, true);
		if (!empty($first) && !empty($last))
			ConverterDb::query('
				UPDATE {to_prefix}topics
				SET id_first_msg = {int:first},
					id_last_msg = {int:last}
				WHERE id_topic = {int:topic}',
				[
					'first' => $first,
					'last' => $last,
					'id_topic' => $topic['id_topic']
			]);
	}

	public static string	$convertStep12info = 'Converting posts (part 2)';
	public static function	 convertStep12Custom(): void
	{
		global $yabb;

		Converter::pastTime(0);
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$result = ConverterDb::query('
				SELECT m.id_msg, mem.id_member
				FROM {to_prefix}messages AS m
					INNER JOIN {to_prefix}members AS mem
				WHERE m.poster_name = mem.member_name
					AND m.id_member = 0
				LIMIT {int:block_size}',
				[
					'block_size' => self::getBlockSize('posts2')
			]);
			$numRows = ConverterDb::num_rows($result);

			while ($row = ConverterDb::fetch_assoc($result))
				ConverterDb::query('
					UPDATE {to_prefix}messages
					SET id_member = {int:id_member}
					WHERE id_msg = {int:id_msg}',
					[
						'id_member' => $row['id_member'],
						'id_msg' => $row['id_msg'],
				]);
			ConverterDb::free_result($result);

			$currentStart += $numRows;
			Converter::pastTime($currentStart);

			if ($numRows < 1)
				break;
			else
				Converter::pastTime($currentStart);
		}
	}

	public static string	$convertStep13info = 'Converting attachments';
	public static function	 convertStep13Custom(): void
	{
		global $yabb;

		if (!isset($yabb['uploaddir']))
			return;

		$result = ConverterDb::query('
			SELECT value
			FROM {to_prefix}settings
			WHERE variable = {literal:attachmentUploadDir}
			LIMIT 1');
		list ($attachmentUploadDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		// Danger, Will Robinson!
		if ($yabb['uploaddir'] == $attachmentUploadDir)
			return;

		$result = ConverterDb::query('
			SELECT MAX(id_attach)
			FROM {to_prefix}attachments');
		list ($id_attach) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		$id_attach++;
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			Converter::pastTime($currentStart);
			$attachments = [];

			$result = ConverterDb::query('
				SELECT m.id_msg, con.real_id as temp_filename
				FROM {to_prefix}messages AS m
					INNER JOIN {to_prefix}convert AS con
						ON (con.type = {literal:msg_attach} AND con.temp = CONCAT(m.poster_time, {string:colon}, m.poster_name))
				LIMIT {int:offset}, {int:limit}',
				[
					'colon' => ':',
					'offset' => $currentStart,
					'limit' => self::getBlockSize('attachments')
			]);
			while ($row = ConverterDb::fetch_assoc($result))
			{
				$size = filesize($yabb['uploaddir'] . '/' . $row['temp_filename']);
				$file_hash = getAttachmentFilename($row['temp_filename'], $id_attach, null, true);

				// Is this an image???
				$attachmentExtension = strtolower(substr(strrchr($row['temp_filename'], '.'), 1));
				if (!in_array($attachmentExtension, ['jpg', 'jpeg', 'gif', 'png']))
					$attachmentExtension = '';

				if (strlen($filename) <= 255 && copy($yabb['uploaddir'] . '/' . $row['temp_filename'], $attachmentUploadDir . '/' . $file_hash))
				{
					// Set the default empty values.
					$width = '0';
					$height = '0';

					// Is an an image?
					if (!empty($attachmentExtension))
					{
						list ($width, $height) = getimagesize($yabb['uploaddir'] . '/' . $row['temp_filename']);
						// This shouldn't happen but apparently it might
						if (empty($width))
							$width = 0;
						if (empty($height))
							$height = 0;
					}

					$attachments[] = [$id_attach++, $size, 0, $row['temp_filename'], $file_hash, $row['id_msg'], $width, $height];
				}
			}

			if (!empty($attachments))
				ConverterDb::insert(
					'{to_prefix}attachments',
					['id_attach' => 'int', 'size' => 'int', 'downloads' => 'int', 'filename' => 'string', 'file_hash' => 'string', 'id_msg' => 'int', 'width' => 'int', 'height' => 'int'],
					$attachments,
				);

			$currentStart += self::getBlockSize('attachments');

			if (ConverterDb::num_rows($result) < self::getBlockSize('attachments'))
				break;

			ConverterDb::free_result($result);
		}
	}

	public static string	$convertStep14info = 'Cleaning up messages';
	public static function	 convertStep14Custom(): void
	{
		global $yabb;

		$currentStart = Converter::getVar('currentStart');

		while ($currentStart >= 0)
		{
			Converter::pastTime($currentStart);

			$result = ConverterDb::query('
				SELECT t.id_topic, MIN(m.id_msg) AS id_first_msg, MAX(m.id_msg) AS id_last_msg
				FROM {to_prefix}topics AS t
					INNER JOIN {to_prefix}messages AS m
				WHERE m.id_topic = t.id_topic
				GROUP BY t.id_topic
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('cleanup')
			]);
			while ($row = ConverterDb::fetch_assoc($result))
			{
				$result2 = ConverterDb::query('
					SELECT id_member
					FROM {to_prefix}messages
					WHERE id_msg = {int:id_msg}
					LIMIT 1',
					[
						'id_msg' => $row['id_last_msg']
				]);
				list ($row['id_member_updated']) = ConverterDb::fetch_row($result2);
				ConverterDb::free_result($result2);

				$result2 = ConverterDb::query('
					SELECT id_member
					FROM {to_prefix}messages
					WHERE id_msg = {int:id_msg}
					LIMIT 1',
					[
						'id_msg' => $row['id_first_msg']
				]);
				list ($row['id_member_started']) = ConverterDb::fetch_row($result2);
				ConverterDb::free_result($result2);

				ConverterDb::query('
					UPDATE {to_prefix}topics
					SET
						id_first_msg = {int:id_first_msg},
						id_last_msg = {int:id_last_msg},
						id_member_started = {int:id_member_started},
						id_member_updated = {int:id_member_updated}
					WHERE id_topic = {int:id_topic}',
					[
						'id_first_msg' => $row['id_first_msg'],
						'id_last_msg' => $row['id_last_msg'],
						'id_member_started'=> $row['id_member_started'],
						'id_member_updated' => $row['id_member_updated'],
						'id_topic' => $row['id_topic']
				]);
			}

			$currentStart += ConverterDb::num_rows($result);
			if (ConverterDb::num_rows($result) < self::getBlockSize('cleanup'))
				break;

			ConverterDb::free_result($result);
		}
	}

	public static string	$convertStep15info = 'Converting polls and poll choices (part 1)';
	public static function	 convertStep15Custom(): void
	{
		global $yabb;

		// If set remove the old data
		if (Converter::getVar('currentStart') <= 0 && self::$purge)
		{
			ConverterDb::query('TRUNCATE {to_prefix}polls');
			Converter::pastTime(-2);

			ConverterDb::query('TRUNCATE {to_prefix}poll_choices');
			Converter::pastTime(-1);

			ConverterDb::query('TRUNCATE {to_prefix}log_polls');
			Converter::pastTime(0);
		}

		$currentStart = Converter::getVar('polls1');
		$file_n = 0;
		$dir = dir($yabb['datadir']);
		$pollQuestionsBlock = $pollChoicesBlock = $member_names = [];
		while ($entry = $dir->read())
		{
			if ($currentStart < 0)
				break;
			else if ($file_n++ < $currentStart)
				continue;
			else if (strrchr($entry, '.') != '.poll')
				continue;

			$pollData = file($yabb['datadir'] . '/' . $entry);

			$id_poll = substr($entry, 0, strrpos($entry, '.'));

			foreach ($pollData as $i => $v)
			{
				$pollData[$i] = explode('|', rtrim($pollData[$i]));

				// Is this the poll option/question?  If so set the data.
				if (count($pollData[$i]) > 3)
					$pollQuestionsBlock[] = [
						'question' => substr(htmlspecialchars($pollData[$i][0]), 0, 255),
						'voting_locked' => (int) $pollData[$i][1],
						'max_votes' => (int) $pollData[$i][8],
						'expire_time' => 0,
						'hide_results' => (int) $pollData[$i][7],
						'change_vote' => 0,
						'id_member' => 0,
						'poster_name' => empty($pollData[$i][3]) ? 'Guest' : substr(htmlspecialchars($pollData[$i][3]), 0, 255),
						'temp' => (int) $id_poll,
					];

				// Are these the choices?
				if (count($pollData[$i]) == 2)
					$pollChoicesBlock[] = [
						'id_poll' => (int) $id_poll,
						'id_choice' => $i - 1, // Make sure to subtract the first row since that's the question
						'label' => $pollData[$i][1],
						'votes' => (int) $pollData[$i][0],
					];
			}

			$name_temp = [];
			foreach ($pollQuestionsBlock as $temp)
				if ($temp['poster_name'] != 'Guest')
					$name_temp[] = $temp['poster_name'];

			if (!empty($name_temp))
			{
				$names = [];
				$temp = '"' . implode(',', $name_temp) . '"';

				$request = ConverterDb::query('
					SELECT id_member, real_name
					FROM {to_prefix}members
					WHERE real_name IN ({array_string:real_names})',
					[
						'real_names' => $name_temp
				]);
				while ($row = ConverterDb::fetch_assoc($request))
					$names[$row['real_name']] = $row['id_member'];
				ConverterDb::free_result($request);

				$request = ConverterDb::query('
					SELECT id_member, member_name
					FROM {to_prefix}members
					WHERE member_name IN ({array_string:real_names})
						AND real_name NOT IN ({array_string:real_names})',
					[
						'real_names' => $name_temp
				]);
				while ($row = ConverterDb::fetch_assoc($request))
					$names[$row['member_name']] = $row['id_member'];
				ConverterDb::free_result($request);
			}

			foreach ($pollQuestionsBlock as $key => $poll)
				$pollQuestionsBlock[$key]['id_member'] = $poll['poster_name'] == 'Guest' || !isset($names[$poll['poster_name']]) ? 0 : $names[$poll['poster_name']];

			// Then insert it.
			self::doBlock('polls', $pollQuestionsBlock);

			$poll_ids = [];
			// Now get the correct ids.
			$request = ConverterDb::query('
				SELECT p.id_poll, con.temp
				FROM {to_prefix}polls AS p
					INNER JOIN {to_prefix}convert AS con
						ON (con.type = {literal:polls} AND con.real_id = p.id_poll)');
			while ($row = ConverterDb::fetch_assoc($request))
				$poll_ids[$row['temp']] = $row['id_poll'];

			foreach ($pollChoicesBlock as $key => $choice)
				$pollChoicesBlock[$key]['id_poll'] = $poll_ids[$choice['id_poll']];

			// Now for the choices.
			self::doBlock('poll_choices', $pollChoicesBlock);

			// Increase the time
			$currentStart += $file_n;
			Converter::pastTime($currentStart);
		}

		$dir->close();
	}

	public static string	$convertStep16info = 'Converting polls and poll choices (part 2)';
	public static function	 convertStep16Custom(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			Converter::pastTime($currentStart);

			$request = ConverterDb::query('
				SELECT p.id_poll, pcon.temp, t.id_topic
				FROM {to_prefix}polls AS p
					INNER JOIN {to_prefix}convert AS pcon
						ON (pcon.type = {literal:polls} AND pcon.real_id = p.id_poll)
					INNER JOIN {to_prefix}convert AS tcon
						ON (tcon.type = {literal:topics} AND tcon.temp = pcon.temp)
					INNER JOIN {to_prefix}topics AS t ON (t.id_topic = tcon.real_id)',
				[
			]);

			while ($row = ConverterDb::fetch_assoc($request))
			{
				ConverterDb::query('
					UPDATE {to_prefix}topics
					SET id_poll = {int:id_poll}
					WHERE id_topic = {int:id_topic}',
					[
						'id_poll' => $row['id_poll'],
						'id_topic' => $row['id_topic']
				]);
				/*
				 * Not sure what this is attempting to do...
				ConverterDb::query('
					UPDATE {to_prefix}poll_choices
					SET id_poll = $row[id_poll]
					WHERE id_poll = {int:temp}',
					[
						'id_poll' => $row['id_poll'],
						'temp' => $row['temp']
				]);
				*/
			}
			$currentStart += ConverterDb::num_rows($request);
			if (ConverterDb::num_rows($request) < self::getBlockSize('polls2'))
				break;

			ConverterDb::free_result($request);
		}
	}

	public static string	$convertStep17info = 'Converting poll votes';
	public static function	 convertStep17Custom(): void
	{
		global $yabb;

		$currentStart = Converter::getVar('currentStart');
		$file_n = 0;
		$dir = dir($yabb['datadir']);
		$pollVotesBlock = $members = $pollIdsBlock = [];

		while ($entry = $dir->read())
		{
			if ($currentStart < 0)
				break;
			else if ($file_n++ < $currentStart)
				continue;
			else if (strrchr($entry, '.') != '.polled')
				continue;

			$pollVotesData = file($yabb['datadir'] . '/' . $entry);
			$id_poll = substr($entry, 0, strrpos($entry, '.'));

			$pollIdsBlock[] = $id_poll;
			// Get the data from each line/
			foreach ($pollVotesData as $i => $votes)
			{
				$pollVotesData[$i] = explode('|', rtrim($pollVotesData[$i]));

				// We just need the member_name and id_choice here.
				if (count($pollVotesData) > 2)
				{
					// Set the members.
					$members[] = $pollVotesData[$i][1];

					// Set the other poll data
					$pollVotesBlock[] = [
						'id_poll' => 0,
						'id_member' => 0,
						'id_choice' => !empty($pollVotesData[$i][2]) ? (int) $pollVotesData[$i][2] : 0,
						'temp' => $id_poll,
						'member_name' => trim($pollVotesData[$i][1])
					];
				}
			}

			// Now time to insert the votes.
			if (count($pollVotesBlock) > self::getBlockSize('polls3'))
			{
				$request = ConverterDb::query('
					SELECT id_member, member_name
					FROM {to_prefix}members
					WHERE member_name IN ({array_string:members})',
					[
						'members' => $members
				]);

				// Asssign the id_member to the poll.
				while ($row = ConverterDb::fetch_assoc($request))
				{
					foreach ($pollVotesBlock as $key => $avlue)
					{
						if (isset($avlue['member_name']) && $avlue['member_name'] == $row['member_name'])
						{
							// Assign id_member
							$pollVotesBlock[$key]['id_member'] = $row['id_member'];

							// Now lets unset member_name since we don't need it any more
							unset($pollVotesBlock[$key]['member_name'], $pollVotesBlock[$key]['member_name']);
						}
					}
				}

				$request = ConverterDb::query('
					SELECT id_member, real_name
					FROM {to_prefix}members
					WHERE real_name IN ({array_string:members})',
					[
						'members' => $members
				]);

				// Asssign the id_member to the poll.
				while ($row = ConverterDb::fetch_assoc($request))
				{
					foreach ($pollVotesBlock as $key => $avlue)
					{
						if (isset($avlue['member_name']) && $avlue['member_name'] == $row['real_name'])
						{
							// Assign id_member
							$pollVotesBlock[$key]['id_member'] = $row['id_member'];

							// Now lets unset member_name since we don't need it any more
							unset($pollVotesBlock[$key]['member_name'], $pollVotesBlock[$key]['member_name']);
						}
					}
				}

				// Get the id_poll form the temp ID
				$request = ConverterDb::query('
					SELECT p.id_poll, con.temp
					FROM {to_prefix}polls AS p
						INNER JOIN {to_prefix}convert AS con
							ON (pcon.type = {literal:polls} AND con.real_id = p.id_poll)
					WHERE con.temp IN ({array_string:temp})',
					[
						'temp' => $pollIdsBlock
				]);

				// Assign the id_poll
				while ($row = ConverterDb::fetch_assoc($request))
				{
					foreach ($pollVotesBlock as $key => $value)
					{
						if (isset($pollVotesBlock[$key]['temp']) && $pollVotesBlock[$key]['temp'] == $row['temp'])
						{
							$pollVotesBlock[$key]['id_poll'] = $row['id_poll'];
							unset($pollVotesBlock[$key]['temp'], $pollVotesBlock[$key]['temp']);
						}
					}
				}

				// Lets unset the remaining member_names
				foreach ($pollVotesBlock as $key => $value)
				{
					if (isset($pollVotesBlock[$key]['member_name']))
						unset($pollVotesBlock[$key]);
				}

				self::doBlock('log_polls', $pollVotesBlock, true);
			}

			// Some time has passed so do something
			Converter::pastTime($currentStart += $file_n);
		}
		$dir->close();
	}
}