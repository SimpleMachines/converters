<?php

/**
 * Simple Machines Forum (SMF)
 *
 * @package SMF
 * @author Simple Machines http://www.simplemachines.org
 * @copyright 2011 Simple Machines
 * @license http://www.simplemachines.org/about/smf/license.php BSD
 *
 * @version 2.0
 */

$convert_data = array(
	'name' => 'YaBB 1 Gold',
	'version' => 'SMF 2.0',
	'flatfile' => true,
	'settings' => array('/Settings.pl'),
	'parameters' => array(
		array(
			'id' => 'db_purge',
			'type' => 'checked',
			'label' => 'Clear current SMF posts and members during conversion.',
		),
	),
);

if (!function_exists('convert_query'))
{
	if (file_exists(dirname(__FILE__) . '/convert.php'))
		header('Location: http://' . (empty($_SERVER['HTTP_HOST']) ? $_SERVER['SERVER_NAME'] . (empty($_SERVER['SERVER_PORT']) || $_SERVER['SERVER_PORT'] == '80' ? '' : ':' . $_SERVER['SERVER_PORT']) : $_SERVER['HTTP_HOST']) . (strtr(dirname($_SERVER['PHP_SELF']), '\\', '/') == '/' ? '' : strtr(dirname($_SERVER['PHP_SELF']), '\\', '/')) . '/convert.php?convert_script=' . basename(__FILE__));
	else
	{
		echo '<html>
	<head>
		<title>Unable to continue!</title>
	</head>
	<body>
		<h1>Sorry, this file can\'t work alone</h1>

		<p>Please download convert.php from <a href="http://www.simplemachines.org/">www.simplemachines.org</a> and use it.  This file should be in the same directory as it.</p>
	</body>
</html>';
	}

	exit;
}

if (empty($preparsing))
{
	// Memory, please!!
	@ini_set('memory_limit', '128M');

	function load_converter_settings()
	{
		global $yabb;

		if (isset($_SESSION['convert_parameters']['db_purge']))
			$_SESSION['purge'] = !empty($_SESSION['convert_parameters']['db_purge']);

		if (!isset($_POST['path_from']) || !file_exists($_POST['path_from'] . '/Settings.pl'))
			return;

		$data = file($_POST['path_from'] . '/Settings.pl');
		foreach ($data as $line)
		{
			$line = trim($line);
			if (empty($line) || substr($line, 0, 1) == '#')
				continue;

			if (preg_match('~\$([^ =]+?)\s*=\s*[q]?([\^"\']?)(.+?)\\2;~', $line, $match) != 0)
				$yabb[$match[1]] = $match[2] == '^' ? addslashes($match[3]) : $match[3];
		}

		$paths = array('boarddir', 'boardsdir', 'datadir', 'memberdir', 'sourcedir', 'vardir', 'facesdir', 'upload_dir');
		foreach ($paths as $path)
		{
			if (isset($yabb[$path]))
				$yabb[$path] = fixRelativePath($yabb[$path], $_POST['path_from']);
		}
	}

	function convertStep1()
	{
		global $to_prefix, $yabb;

		echo 'Converting membergroups...';

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				DELETE FROM {$to_prefix}permissions
				WHERE id_group > 8");
			convert_query("
				DELETE FROM {$to_prefix}membergroups
				WHERE id_group > 8");
		}

		$groups = file($yabb['vardir'] . '/membergroups.txt');
		foreach ($groups as $i => $group)
			$groups[$i] = addslashes(trim($group));

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[0]'
			WHERE id_group = 1
			LIMIT 1");

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[1]'
			WHERE id_group = 3
			LIMIT 1");

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[2]', min_posts = 0
			WHERE id_group = 4
			LIMIT 1");

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[3]', min_posts = " . (int) $yabb['JrPostNum'] . "
			WHERE id_group = 5
			LIMIT 1");

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[4]', min_posts = " . (int) $yabb['FullPostNum'] . "
			WHERE id_group = 6
			LIMIT 1");

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[5]', min_posts = " . (int) $yabb['SrPostNum'] . "
			WHERE id_group = 7
			LIMIT 1");

		convert_query("
			UPDATE {$to_prefix}membergroups
			SET group_name = '$groups[6]', min_posts = " . (int) $yabb['GodPostNum'] . "
			WHERE id_group = 8
			LIMIT 1");

		for ($i = 7; $i < count($groups); $i++)
		{
			if ($groups[$i] == '')
				continue;

			convert_insert('membergroups', array('group_name', 'online_color', 'min_posts', 'stars'), array(substr($groups[$i], 0, 80), '', -1, ''), 'replace');
		}
	}

	function convertStep2()
	{
		global $to_prefix, $yabb;

		echo 'Converting members...';

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				TRUNCATE {$to_prefix}members");
		}
		if ($_GET['substep'] == 0)
		{
			// Get rid of the primary key... we have to resort anyway.
			alterDatabase('members', 'remove index', 'primary');
			alterDatabase('members', 'change column', array(
				'old_name' => 'id_member',
				'name' => 'id_member',
				'type' => 'mediumint',
				'size' => 8,
				'default' => 0,
			));
		}

		pastTime(0);

		$request = convert_query("
			SELECT id_group, group_name
			FROM {$to_prefix}membergroups
			WHERE id_group NOT IN (2, 3)");
		$groups = array('Administrator' => 1, 'Moderator' => 0);
		while ($row = convert_fetch_assoc($request))
			$groups[$row['group_name']] = $row['id_group'];
		convert_free_result($request);

		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$block = array();
		$text_columns = array(
			'member_name' => 80,
			'lngfile' => 255,
			'real_name' => 255,
			'buddy_list' => 255,
			'pm_ignore_list' => 255,
			'message_labels' => 65534,
			'passwd' => 64,
			'email_address' => 255,
			'personal_text' => 255,
			'website_title' => 255,
			'website_url' => 255,
			'location' => 255,
			'icq' => 255,
			'aim' => 16,
			'yim' => 32,
			'msn' => 255,
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
		);
		while ($entry = $dir->read())
		{
			if ($_GET['substep'] < 0)
				break;
			if ($file_n++ < $_GET['substep'])
				continue;
			if (strrchr($entry, '.') != '.dat')
				continue;

			$userData = file($yabb['memberdir'] . '/' . $entry);
			foreach ($userData as $i => $v)
				$userData[$i] = rtrim($userData[$i]);
			if (count($userData) < 3)
				continue;

			$row = array(
				'member_name' => substr(htmlspecialchars(substr($entry, 0, -4)), 0, 80),
				'passwd' => md5($userData[0]),
				'real_name' => @$userData[1] == 'Guest' || @$userData[1] == '' ? $row['member_name'] : htmlspecialchars($userData[1]),
				'email_address' => htmlspecialchars(@$userData[2]),
				'website_title' => htmlspecialchars(@$userData[3]),
				'website_url' => htmlspecialchars(@$userData[4]),
				'signature' => str_replace(array('&amp;&amp;', '&amp;lt;'), array('<br />', '&lt;'), htmlspecialchars(@$userData[5], ENT_QUOTES)),
				'posts' => (int) @$userData[6],
				'id_group' => isset($groups[@$userData[7]]) ? $groups[@$userData[7]] : 0,
				'icq' => htmlspecialchars(@$userData[8]),
				'aim' => substr(htmlspecialchars(@$userData[9]), 0, 16),
				'yim' => substr(htmlspecialchars(@$userData[10]), 0, 32),
				'gender' => @$userData[11] == 'Male' ? 1 : (@$userData[11] == 'Female' ? 2 : 0),
				'personal_text' => htmlspecialchars(@$userData[12]),
				'avatar' => @$userData[13],
				'date_registered' => parse_time(@$userData[14]),
				'location' => htmlspecialchars(@$userData[15]),
				'birthdate' => @$userData[16] == '' || strtotime(@$userData[16]) == 0 ? '0001-01-01' : strftime('%Y-%m-%d', strtotime($userData[16])),
				'time_offset' => (float) @$userData[18],
				'hide_email' => @$userData[19] == 'checked' ? '1' : '0',
			);

			if ($row['birthdate'] == '0001-01-01' && parse_time(@$userData[16], false) != 0)
				$row['birthdate'] = strftime('%Y-%m-%d', parse_time(@$userData[16], false));

			// Make sure these columns have a value and don't exceed max width.
			foreach ($text_columns as $text_column => $max_size)
				$row[$text_column] = isset($row[$text_column]) ? substr($row[$text_column], 0, $max_size) : '';

			if (file_exists($yabb['memberdir'] . '/' . substr($entry, 0, -4) . '.karma'))
			{
				$karma = (int) implode('', file($yabb['memberdir'] . '/' . substr($entry, 0, -4) . '.karma'));
				$row['karma_good'] = $karma > 0 ? $karma : 0;
				$row['karma_bad'] = $karma < 0 ? -$karma : 0;
			}
			else
			{
				$row['karma_good'] = 0;
				$row['karma_bad'] = 0;
			}
			if (file_exists($yabb['memberdir'] . '/' . substr($entry, 0, -4) . '.imconfig'))
			{
				$imconfig = file($yabb['memberdir'] . '/' . substr($entry, 0, -4) . '.imconfig');
				//$row['pm_ignore_list'] = !empty($imconfig[0]) ? strtr(trim($imconfig[0]), '|', ',') : '';
				$row['pm_email_notify'] = empty($imconfig[1]) || trim($imconfig[1]) == '' ? '0' : '1';
			}
			else
			{
				//$row['pm_ignore_list'] = '';
				$row['pm_email_notify'] = '1';
			}

			$block[] = addslashes_recursive($row);

			if (count($block) > 100)
			{
				doBlock('members', $block);
				pastTime($file_n);
			}
		}
		$dir->close();

		doBlock('members', $block);

		pastTime(-1);

		// Part 2: Now we get to resort the members table!
		if ($_GET['substep'] >= -1)
		{
			convert_query("
				ALTER TABLE {$to_prefix}members
				ORDER BY id_member, date_registered");
			pastTime(-2);
		}
		if ($_GET['substep'] >= -2)
		{
			alterDatabase('members', 'change column', array(
				'old_name' => 'id_member',
				'name' => 'id_member',
				'type' => 'mediumint',
				'size' => 8,
				'auto' => true,
				'default' => 0,
			));
			alterDatabase('members', 'add index', array(
				'type' => 'primary',
				'columns' => array('id_member'),
			));

			pastTime(-3);
		}
		if ($_GET['substep'] >= -3)
		{
			convert_query("
				ALTER TABLE {$to_prefix}members
				ORDER BY id_member");
		}
	}

	function convertStep3()
	{
		global $to_prefix, $yabb;

		echo 'Converting settings...';

		$fp = @fopen($_POST['path_to'] . '/agreement.txt', 'wb');
		if ($fp)
		{
			fwrite($fp, strtr(implode('', file($yabb['vardir'] . '/agreement.txt')), array("\r" => '')));
			fclose($fp);
		}

		$settings = array();
		$settings['news'] = addslashes(strtr(implode('', file($yabb['vardir'] . '/news.txt')), array("\r" => '')));
		$settings['maxdays'] = (int) implode('', file($yabb['vardir'] . '/oldestmes.txt'));
		$settings['cookieTime'] = !empty($yabb['Cookie_Length']) ? (int) $yabb['Cookie_Length'] : 60;
		$settings['requireAgreement'] = !empty($yabb['RegAgree']) ? 1 : 0;
		$settings['registration_method'] = !empty($yabb['emailpassword']) ? 1 : 0;
		$settings['send_validation_onChange'] = !empty($yabb['emailnewpass']) ? 1 : 0;
		$settings['send_welcomeEmail'] = !empty($yabb['emailwelcome']) ? 1 : 0;
		$settings['mail_type'] = empty($yabb['mailtype']) ? 0 : 1;
		$settings['smtp_host'] = isset($yabb['smtp_server']) ? $yabb['smtp_server'] : '';
		$settings['time_offset'] = (int) $yabb['timeoffset'];
		$settings['defaultMaxMembers'] = !empty($yabb['MembersPerPage']) ? (int) $yabb['MembersPerPage'] : 20;
		$settings['defaultMaxTopics'] = !empty($yabb['maxdisplay']) ? (int) $yabb['maxdisplay'] : 20;
		$settings['defaultMaxMessages'] = !empty($yabb['maxmessagedisplay']) ? (int) $yabb['maxmessagedisplay'] : 15;
		$settings['max_messageLength'] = !empty($yabb['MaxMessLen']) ? (int) $yabb['MaxMessLen'] : 10000;
		$settings['signature_settings'] = '1,' . (int) $yabb['MaxSigLen'] . ',5,0,1,0,0,0:';
		$settings['spamWaitTime'] = (int) $yabb['timeout'];
		$settings['avatar_max_width_external'] = (int) $yabb['userpic_width'];
		$settings['avatar_max_height_external'] = (int) $yabb['userpic_height'];
		$settings['avatar_max_width_upload'] = (int) $yabb['userpic_width'];
		$settings['avatar_max_height_upload'] = (int) $yabb['userpic_height'];

		$temp = file($yabb['vardir'] . '/reservecfg.txt');
		$settings['reserveWord'] = trim($temp[0]) == 'checked' ? '1' : '0';
		$settings['reserveCase'] = trim($temp[1]) == 'checked' ? '1' : '0';
		$settings['reserveUser'] = trim($temp[2]) == 'checked' ? '1' : '0';
		$settings['reserveName'] = trim($temp[3]) == 'checked' ? '1' : '0';
		$settings['reserveNames'] = addslashes(strtr(implode('', file($yabb['vardir'] . '/reserve.txt')), array("\r" => '')));

		$vulgar = array();
		$proper = array();
		$temp = file($yabb['vardir'] . '/censor.txt');
		foreach ($temp as $word)
		{
			if (trim($word) == '')
				continue;

			list ($word, $word2) = explode('=', $word);
			$vulgar[] = trim($word);
			$proper[] = trim($word2);
		}
		$settings['censor_vulgar'] = addslashes(implode("\n", $vulgar));
		$settings['censor_proper'] = addslashes(implode("\n", $proper));

		$setString = array();
		foreach ($settings as $var => $val)
			$setString[] = array($var, substr($val, 0, 65534));

		convert_insert('settings', array('variable', 'value'), $setString, 'replace');
	}

	function convertStep4()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				TRUNCATE {$to_prefix}personal_messages");
			convert_query("
				TRUNCATE {$to_prefix}pm_recipients");
		}
		if ($_GET['substep'] == 0)
		{
			alterDatabase('personal_messages', 'remove index', 'primary');
			alterDatabase('personal_messages', 'change column', array(
				'old_name' => 'id_pm',
				'name' => 'id_pm',
				'type' => 'mediumint',
				'size' => 8,
				'default' => 0,
			));
		}

		echo 'Converting personal messages...';

		$names = array();

		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$block = array();
		while ($entry = $dir->read())
		{
			if ($_GET['substep'] < 0)
				break;
			if ($file_n++ < $_GET['substep'])
				continue;
			if (strrchr($entry, '.') != '.msg')
				continue;

			$userData = file($yabb['memberdir'] . '/' . $entry);
			foreach ($userData as $i => $v)
			{
				$userData[$i] = explode('|', rtrim($userData[$i]));

				if (substr($userData[$i][3], -10) == '#nosmileys')
					$userData[$i][3] = substr($userData[$i][3], 0, -10);

				$row = array(
					'from_name' => substr(htmlspecialchars($userData[$i][0]), 0, 255),
					'subject' => substr($userData[$i][1], 0, 255),
					'msgtime' => parse_time($userData[$i][2]),
					'body' => substr($userData[$i][3], 0, 65534),
					'id_member_from' => 0,
					'deleted_by_sender' => 1,
					'temp_to_name' => htmlspecialchars(substr($entry, 0, -4)),
				);

				$names[strtolower(addslashes($row['from_name']))][] = &$row['id_member_from'];

				$block[] = addslashes_recursive($row);
			}

			if (count($block) > 100)
			{
				$result = convert_query("
					SELECT id_member, member_name
					FROM {$to_prefix}members
					WHERE member_name IN ('" . implode("', '", array_keys($names)) . "')
					LIMIT " . count($names));
				while ($row = convert_fetch_assoc($result))
				{
					foreach ($names[strtolower(addslashes($row['member_name']))] as $k => $v)
						$names[strtolower(addslashes($row['member_name']))][$k] = $row['id_member'];
				}
				convert_free_result($result);
				$names = array();

				doBlock('personal_messages', $block);
				pastTime($file_n);
			}
		}
		$dir->close();

		if (!empty($block))
		{
			$result = convert_query("
				SELECT id_member, member_name
				FROM {$to_prefix}members
				WHERE member_name IN ('" . implode("', '", array_keys($names)) . "')
				LIMIT " . count($names));
			while ($row = convert_fetch_assoc($result))
			{
				foreach ($names[strtolower(addslashes($row['member_name']))] as $k => $v)
					$names[strtolower(addslashes($row['member_name']))][$k] = $row['id_member'];
			}
			convert_free_result($result);
			$names = array();

			doBlock('personal_messages', $block);
		}

		pastTime(-1);

		// Part 2: Now we get to resort the personal messages table!
		if ($_GET['substep'] >= -1)
		{
			convert_query("
				ALTER TABLE {$to_prefix}personal_messages
				ORDER BY id_pm, msgtime");

			pastTime(-2);
		}
		if ($_GET['substep'] >= -2)
		{
			alterDatabase('personal_messages', 'change column', array(
				'old_name' => 'id_pm',
				'name' => 'id_pm',
				'type' => 'int',
				'size' => 10,
				'auto' => true,
			));
			alterDatabase('personal_messages', 'add index', array(
				'type' => 'primary',
				'columns' => array('id_temp'),
			));

			pastTime(-3);
		}
		if ($_GET['substep'] >= -3)
		{
			/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
			convert_query("
				INSERT INTO {$to_prefix}pm_recipients
					(id_pm, id_member, labels)
				SELECT pm.id_pm, mem.id_member, '' AS labels
				FROM {$to_prefix}personal_messages AS pm
					INNER JOIN {$to_prefix}members AS mem ON (mem.member_name = pm.temp_to_name)
				WHERE pm.temp_to_name != ''");

			pastTime(-4);
		}
		if ($_GET['substep'] >= -4)
		{
			alterDatabase('personal_messages', 'remove column', 'temp_to_name');

			pastTime(-5);
		}
		if ($_GET['substep'] >= -5)
		{
			convert_query("
				ALTER TABLE {$to_prefix}personal_messages
				ORDER BY id_pm");
		}
	}

	function convertStep5()
	{
		global $to_prefix, $yabb;

		echo 'Converting boards and categories...';

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				TRUNCATE {$to_prefix}categories");
			convert_query("
				TRUNCATE {$to_prefix}boards");
			convert_query("
				TRUNCATE {$to_prefix}moderators");
		}
		if ($_GET['substep'] == 0)
		{
			alterDatabase('categories', 'add column', array(
				'name' => 'temp_id',
				'type' => 'tinytext',
			));
			alterDatabase('boards', 'add column', array(
				'name' => 'temp_id',
				'type' => 'tinytext',
			));
			alterDatabase('boards', 'add column', array(
				'name' => 'temp_cat_id',
				'type' => 'tinytext',
			));
		}

		pastTime(0);

		$request = convert_query("
			SELECT id_group, group_name
			FROM {$to_prefix}membergroups
			WHERE id_group NOT IN (2, 3)");
		$groups = array('Administrator' => 1, 'Moderator' => 0);
		while ($row = convert_fetch_assoc($request))
			$groups[$row['group_name']] = $row['id_group'];
		convert_free_result($request);

		$cats = file($yabb['vardir'] . '/cat.txt');
		$board_order = 1;
		$cat_rows = array();
		$board_rows = array();
		foreach ($cats as $i => $cat)
		{
			if (!file_exists($yabb['boardsdir'] . '/' . trim($cat) . '.cat'))
				continue;

			$data = file($yabb['boardsdir'] . '/' . trim($cat) . '.cat');
			foreach ($data as $i => $v)
				$data[$i] = rtrim($data[$i]);

			$row = array();
			$row['name'] = $data[0];
			$row['cat_order'] = $i + 1;
			$row['temp_id'] = trim($cat);
			$cat_rows[] = addslashes_recursive($row);

			$data[1] = explode(',', $data[1]);
			if ($data[1][0] == '')
				$cat_groups = array_merge($groups, array(2, 0, -1));
			else
			{
				$cat_groups = array(2);
				foreach ($data[1] as $group)
				{
					if (isset($groups[trim($group)]))
						$cat_groups[] = $groups[trim($group)];
				}
			}
			$cat_groups = implode(',', $cat_groups);

			for ($j = 2; $j < count($data); $j++)
			{
				if ($data[$j] == '')
					continue;

				$row2 = array(
					'temp_id' => $data[$j],
					'temp_cat_id' => trim($cat),
					'member_groups' => $cat_groups,
					'board_order' => $board_order++,
				);

				$board_rows[addslashes($data[$j])] = $row2;
			}
		}

		doBlock('categories', $cat_rows);

		$moderators = array();
		foreach ($board_rows as $boardid => $v)
		{
			if (!file_exists($yabb['boardsdir'] . '/' . stripslashes($boardid) . '.dat') || !file_exists($yabb['boardsdir'] . '/' . stripslashes($boardid) . '.txt'))
				continue;

			$data = file($yabb['boardsdir'] . '/' . stripslashes($boardid) . '.dat');
			$board_rows[$boardid]['member_groups'] = '-1,0';
			$board_rows[$boardid]['name'] = substr(trim($data[0]), 0, 255);
			$board_rows[$boardid]['description'] = substr(trim($data[1]), 0, 65534);

			$moderators[$boardid] = explode('|', trim(@$data[2]));
		}

		$board_rows = addslashes_recursive(array_values($board_rows));
		doBlock('boards', $board_rows);

		$result = convert_query("
			SELECT id_cat, temp_id
			FROM {$to_prefix}categories
			WHERE temp_id != ''");
		while ($row = convert_fetch_assoc($result))
		{
			convert_query("
				UPDATE {$to_prefix}boards
				SET id_cat = $row[id_cat]
				WHERE temp_cat_id = '$row[temp_id]'");
		}
		convert_free_result($result);

		foreach ($moderators as $boardid => $names)
		{
			$result = convert_query("
				SELECT id_board
				FROM {$to_prefix}boards
				WHERE temp_id = '$boardid'
				LIMIT 1");
			list ($id_board) = convert_fetch_row($result);
			convert_free_result($result);

			/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
			convert_query("
				INSERT INTO {$to_prefix}moderators
					(id_board, id_member)
				SELECT $id_board, id_member
				FROM {$to_prefix}members
				WHERE member_name IN ('" . implode("', '", addslashes_recursive($names)) . "')
				LIMIT " . count($names));
		}

		alterDatabase('categories', 'remove column', 'temp_id');
		alterDatabase('boards', 'remove column', 'temp_cat_id');
	}

	function convertStep6()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				TRUNCATE {$to_prefix}log_boards");
			convert_query("
				TRUNCATE {$to_prefix}log_mark_read");
			convert_query("
				TRUNCATE {$to_prefix}log_topics");
		}
		if ($_GET['substep'] == 0)
		{
			alterDatabase('log_topics', 'remove index', 'primary');
			alterDatabase('personal_messages', 'add column', array(
				'name' => 'temp_to_name',
				'type' => 'int',
				'size' => 10,
				'default' => 0,
			));
		}

		echo 'Converting mark read data...';

		$result = convert_query("
			SELECT id_board, temp_id
			FROM {$to_prefix}boards");
		$boards = array();
		while ($row = convert_fetch_assoc($result))
			$boards[$row['temp_id']] = $row['id_board'];
		convert_free_result($result);

		$file_n = 0;
		$dir = dir($yabb['memberdir']);
		$mark_read_block = array();
		$boards_block = array();
		$topics_block = array();
		while ($entry = $dir->read())
		{
			if ($_GET['substep'] < 0)
				break;
			if ($file_n++ < $_GET['substep'])
				continue;
			if (strrchr($entry, '.') != '.log')
				continue;

			$result = convert_query("
				SELECT id_member
				FROM {$to_prefix}members
				WHERE member_name = '" . substr($entry, 0, -4) . "'
				LIMIT 1");
			list ($id_member) = convert_fetch_row($result);
			convert_free_result($result);

			$logData = file($yabb['memberdir'] . '/' . $entry);
			foreach ($logData as $log)
			{
				$parts = array_pad(explode('|', $log), 3, '');
				if (trim($parts[0]) == '')
					continue;

				$row = array();
				$row['log_time'] = $parts[1] != '' ? (int) $parts[1] : (int) trim($parts[2]);
				$row['id_member'] = $id_member;

				if (is_numeric(trim($parts[0])) && trim($parts[0]) > 10000)
				{
					$row['temp_id'] = trim($parts[0]);
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
				doBlock('log_mark_read', $mark_read_block);
				doBlock('log_boards', $boards_block);
				doBlock('log_topics', $topics_block);

				pastTime($file_n);
			}
		}
		$dir->close();

		doBlock('log_mark_read', $mark_read_block);
		doBlock('log_boards', $boards_block);
		doBlock('log_topics', $topics_block);
	}

	function convertStep7()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				TRUNCATE {$to_prefix}topics");
		}
		if ($_GET['substep'] == 0)
		{
			alterDatabase('topics', 'remove index', 'primary');
			alterDatabase('topics', 'remove index', 'last_message');
			alterDatabase('topics', 'remove index', 'first_message');
			alterDatabase('topics', 'remove index', 'poll');
			alterDatabase('topics', 'change column', array(
				'old_name' => 'id_topic',
				'name' => 'id_topic',
				'type' => 'mediumint',
				'size' => 8,
				'default' => 0,
			));
			alterDatabase('topics', 'add column', array(
				'name' => 'temp_id',
				'type' => 'int',
				'size' => 10,
				'default' => 0,
			));
		}

		echo 'Converting topics (part 1)...';

		pastTime(0);

		$stickies = array();
		if (file_exists($yabb['boardsdir'] . '/sticky.stk'))
		{
			$stickyData = file($yabb['boardsdir'] . '/sticky.stk');

			foreach ($stickyData as $line)
			{
				if (trim($line) != '')
					$stickies[] = (int) trim($line);
			}
		}

		$result = convert_query("
			SELECT id_board, temp_id
			FROM {$to_prefix}boards
			WHERE temp_id != ''");
		$boards = array();
		while ($row = convert_fetch_assoc($result))
			$boards[$row['temp_id']] = $row['id_board'];
		convert_free_result($result);

		$data_n = 0;
		$block = array();
		foreach ($boards as $boardname => $id_board)
		{
			if ($_GET['substep'] < 0)
				break;
			if (!file_exists($yabb['boardsdir'] . '/' . $boardname . '.txt'))
				continue;

			$topicListing = file($yabb['boardsdir'] . '/' . $boardname . '.txt');
			foreach ($topicListing as $topicData)
			{
				if ($data_n++ < $_GET['substep'])
					continue;

				$topicInfo = explode('|', rtrim($topicData));
				$temp_id = (int) $topicInfo[0];

				if (!file_exists($yabb['datadir'] . '/' . $temp_id . '.txt'))
					continue;

				$block[] = array(
					'temp_id' => $temp_id,
					'id_board' => (int) $id_board,
					'is_sticky' => (int) in_array($temp_id, $stickies),
					'locked' => (int) $topicInfo[8],
					'num_views' => (int) @implode('', @file($yabb['datadir'] . '/' . $temp_id . '.data')),
				);

				if (count($block) > 100)
				{
					doBlock('topics', $block);
					pastTime($data_n);
				}
			}
		}

		doBlock('topics', $block);

		pastTime(-1);

		if ($_GET['substep'] >= -1)
		{
			convert_query("
				UPDATE {$to_prefix}topics
				SET temp_id = id_topic
				WHERE temp_id = 0");

			pastTime(-2);
		}
		if ($_GET['substep'] >= -2)
		{
			convert_query("
				ALTER TABLE {$to_prefix}topics
				ORDER BY id_topic, temp_id");

			pastTime(-3);
		}
		if ($_GET['substep'] >= -3)
		{
			alterDatabase('topics', 'change column', array(
				'old_name' => 'id_topic',
				'name' => 'id_topic',
				'type' => 'mediumint',
				'size' => 8,
				'auto' => true,
			));
			alterDatabase('topics', 'add index', array(
				'type' => 'primary',
				'columns' => array('id_topic'),
			));

			pastTime(-4);
		}
		if ($_GET['substep'] >= -4)
			convert_query("
				ALTER TABLE {$to_prefix}topics
				ORDER BY id_topic");
	}

	function convertStep8()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0)
			alterDatabase('boards', 'remove column', 'temp_id');

		echo 'Converting topics (part 2)...';

		while (true)
		{
			pastTime($_GET['substep']);

			$result = convert_query("
				SELECT id_topic, temp_id
				FROM {$to_prefix}topics
				WHERE temp_id != id_topic
				LIMIT $_GET[substep], 150");
			while ($row = convert_fetch_assoc($result))
			{
				convert_query("
					UPDATE {$to_prefix}log_topics
					SET id_topic = $row[id_topic]
					WHERE temp_id = $row[temp_id]");
			}

			$_GET['substep'] += 150;
			if (convert_num_rows($result) < 150)
				break;

			convert_free_result($result);
		}

		convert_query("
			DELETE FROM {$to_prefix}log_topics
			WHERE id_topic = 0 OR id_member = 0");

		alterDatabase('log_topics', 'remove column', 'temp_id');
		alterDatabase('members', 'add index', array(
			'type' => 'primary',
			'columns' => array('id_topic', 'id_member'),
		));
	}

	function convertStep9()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
			convert_query("
				TRUNCATE {$to_prefix}log_notify");

		echo 'Converting notifications...';

		while (true)
		{
			pastTime($_GET['substep']);

			$result = convert_query("
				SELECT id_topic, temp_id
				FROM {$to_prefix}topics
				WHERE temp_id != id_topic
				LIMIT $_GET[substep], 150");
			while ($row = convert_fetch_assoc($result))
			{
				if (!file_exists($yabb['datadir'] . '/' . $row['temp_id'] . '.mail'))
					continue;

				$list = file($yabb['datadir'] . '/' . $row['temp_id'] . '.mail');
				foreach ($list as $k => $v)
					$list[$k] = addslashes(htmlspecialchars(rtrim($v)));

				/*!!! CONVERT THIS FROM MYSQL SPECIFIC QUERY!!! */
				convert_query("
					INSERT INTO {$to_prefix}log_notify
						(id_topic, id_member)
					SELECT $row[id_topic], id_member
					FROM {$to_prefix}members
					WHERE email_address IN ('" . implode("', '", $list) . "')");
			}

			$_GET['substep'] += 150;
			if (convert_num_rows($result) < 150)
				break;

			convert_free_result($result);
		}
	}

	function convertStep10()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0 && !empty($_SESSION['purge']))
		{
			convert_query("
				TRUNCATE {$to_prefix}messages");
			convert_query("
				TRUNCATE {$to_prefix}attachments");
		}
		if ($_GET['substep'] == 0)
		{
			// Remove the auto_incrementing so we know we get the right order.
			alterDatabase('messages', 'remove index', 'primary');
			alterDatabase('messages', 'remove index', 'topic');
			alterDatabase('messages', 'remove index', 'id_board');
			alterDatabase('messages', 'change column', array(
				'old_name' => 'id_msg',
				'name' => 'id_msg',
				'type' => 'int',
				'size' => 10,
				'default' => 0
			));

			// Do we have attachments?
			if (isset($yabb['uploaddir']))
				alterDatabase('personal_messages', 'add column', array(
					'name' => 'temp_filename',
					'type' => 'tinytext',
				));
		}

		echo 'Converting posts (part 1 - this may take some time)...';

		$block = array();
		while (true)
		{
			$result = convert_query("
				SELECT id_topic, temp_id, id_board
				FROM {$to_prefix}topics
				WHERE temp_id != id_topic
				LIMIT $_GET[substep], 100");
			while ($topic = convert_fetch_assoc($result))
			{
				$messages = file($yabb['datadir'] . '/' . $topic['temp_id'] . '.txt');
				if (empty($messages))
				{
					convert_query("
						DELETE FROM {$to_prefix}topics
						WHERE id_topic = $topic[id_topic]
						LIMIT 1");

					pastTime($_GET['substep']);
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

					$row = array(
						'id_topic' => $topic['id_topic'],
						'id_board' => $topic['id_board'],
						'subject' => substr($message[0], 0, 255),
						'poster_name' => substr(htmlspecialchars($message[4] == 'Guest' ? $message[1] : $message[4]), 0, 255),
						'poster_email' => substr(htmlspecialchars($message[2]), 0, 255),
						'poster_time' => parse_time($message[3]),
						'icon' => substr($message[5], 0, 16),
						'poster_ip' => substr($message[7], 0, 255),
						'body' => substr(preg_replace('~\[quote author=.+? link=.+?\]~i', '[quote]', $message[8]), 0, 65534),
						'smileys_enabled' => empty($message[9]),
						'modified_time' => parse_time($message[10], false),
						'modified_name' => substr($message[11], 0, 255),
					);

					if (isset($yabb['upload_dir']) && isset($message[13]) && file_exists($yabb['upload_dir'] . '/' . $message[13]))
						$row['temp_filename'] = $message[13];
					elseif (isset($yabb['upload_dir']))
						$row['temp_filename'] = '';

					$block[] = addslashes_recursive($row);

					if (count($block) > 100)
						doBlock('messages', $block);
				}

				doBlock('messages', $block);
				pastTime(++$_GET['substep']);
			}

			if (convert_num_rows($result) < 100)
				break;

			convert_free_result($result);
		}

		doBlock('messages', $block);
	}

	function convertStep11()
	{
		global $to_prefix, $yabb;

		if ($_GET['substep'] == 0)
			convert_query("
				ALTER TABLE {$to_prefix}messages
				ORDER BY poster_time");

		echo 'Converting posts (part 2)...';

		$request = convert_query("
			SELECT @msg := IFNULL(MAX(id_msg), 0)
			FROM {$to_prefix}messages");
		convert_free_result($request);

		while (true)
		{
			pastTime($_GET['substep']);

			convert_query("
				UPDATE {$to_prefix}messages
				SET id_msg = (@msg := @msg + 1)
				WHERE id_msg = 0
				LIMIT 150");

			$_GET['substep'] += 150;
			if (convert_affected_rows() < 150)
				break;
		}

		alterDatabase('messages', 'change column', array(
			'old_name' => 'id_msg',
			'name' => 'id_msg',
			'type' => 'int',
			'size' => 10,
			'auto' => true,
			'default' => 0,
		));
		alterDatabase('messages', 'add index', array(
			'type' => 'primary',
			'columns' => array('id_msg'),
		));
	}

	function convertStep12()
	{
		global $to_prefix, $yabb;

		echo 'Converting posts (part 3)...';

		while (true)
		{
			pastTime($_GET['substep']);

			$result = convert_query("
				SELECT m.id_msg, mem.id_member
				FROM {$to_prefix}messages AS m
					INNER JOIN {$to_prefix}members AS mem ON (mem.member_name = m.poster_name)
				WHERE m.id_member = 0
				LIMIT 150");
			while ($row = convert_fetch_assoc($result))
				convert_query("
					UPDATE {$to_prefix}messages
					SET id_member = $row[id_member]
					WHERE id_msg = $row[id_msg]
					LIMIT 1");

			$_GET['substep'] += 150;
			if (convert_num_rows($result) < 150)
				break;

			convert_free_result($result);
		}
	}

	function convertStep13()
	{
		global $to_prefix, $yabb;

		echo 'Converting attachments (if the mod is installed)...';

		if (!isset($yabb['upload_dir']))
			return;

		$result = convert_query("
			SELECT value
			FROM {$to_prefix}settings
			WHERE variable = 'attachmentUploadDir'
			LIMIT 1");
		list ($attachmentUploadDir) = convert_fetch_row($result);
		convert_free_result($result);

		// Danger, Will Robinson!
		if ($yabb['upload_dir'] == $attachmentUploadDir)
			return;

		$result = convert_query("
			SELECT MAX(id_attach)
			FROM {$to_prefix}attachments");
		list ($id_attach) = convert_fetch_row($result);
		convert_free_result($result);

		$id_attach++;

		while (true)
		{
			pastTime($_GET['substep']);
			$attachments = array();

			$result = convert_query("
				SELECT id_msg, temp_filename
				FROM {$to_prefix}messages
				WHERE temp_filename != ''
				LIMIT $_GET[substep], 100");
			while ($row = convert_fetch_assoc($result))
			{
				$size = filesize($yabb['upload_dir'] . '/' . $row['temp_filename']);
				$file_hash = getAttachmentFilename($row['temp_filename'], $id_attach, null, true);

				if (strlen($filename) <= 255 && copy($yabb['upload_dir'] . '/' . $row['temp_filename'], $attachmentUploadDir . '/' . $file_hash))
				{
					$attachments[] = array($id_attach, $size, 0, $row['temp_filename'], $file_hash, $row['id_msg'], 0, 0);

					$id_attach++;
				}
			}

			if (!empty($attachments))
				convert_insert('attachments', array('id_attach' => 'int', 'size' => 'int', 'downloads' => 'int', 'filename' => 'string', 'file_hash' => 'string', 'id_msg' => 'int', 'width' => 'int', 'height' => 'int'), $attachments, 'insert');

			$_GET['substep'] += 100;
			if (convert_num_rows($result) < 100)
				break;

			convert_free_result($result);
		}

		alterDatabase('messages', 'remove column', 'temp_filename');
	}

	function convertStep14()
	{
		global $to_prefix, $yabb;

		echo 'Cleaning up (part 1)...';

		if ($_GET['substep'] <= 0)
		{
			alterDatabase('messages', 'add index', array(
				'type' => 'unique',
				'name' => 'topic',
				'columns' => array('id_topic', 'id_msg'),
			));

			pastTime(1);
		}
		if ($_GET['substep'] <= 1)
		{
			alterDatabase('messages', 'add index', array(
				'type' => 'unique',
				'name' => 'id_board',
				'columns' => array('id_board', 'id_msg'),
			));

			pastTime(2);
		}
		if ($_GET['substep'] <= 2)
		{
			alterDatabase('messages', 'add index', array(
				'name' => 'id_topic',
				'columns' => array('id_topic'),
			));

			pastTime(3);
		}
		if ($_GET['substep'] <= 3)
			alterDatabase('messages', 'add index', array(
				'type' => 'unique',
				'name' => 'id_member',
				'columns' => array('id_member', 'id_msg'),
			));
	}

	function convertStep15()
	{
		global $to_prefix, $yabb;

		echo 'Cleaning up (part 2)...';

		while ($_GET['substep'] >= 0)
		{
			pastTime($_GET['substep']);

			$result = convert_query("
				SELECT t.id_topic, MIN(m.id_msg) AS id_first_msg, MAX(m.id_msg) AS id_last_msg
				FROM {$to_prefix}topics AS t
					INNER JOIN {$to_prefix}messages AS m ON (m.id_topic = t.id_topic)
				GROUP BY t.id_topic
				LIMIT $_GET[substep], 150");
			while ($row = convert_fetch_assoc($result))
			{
				$result2 = convert_query("
					SELECT id_member
					FROM {$to_prefix}messages
					WHERE id_msg = $row[id_last_msg]
					LIMIT 1");
				list ($row['id_member_updated']) = convert_fetch_row($result2);
				convert_free_result($result2);

				$result2 = convert_query("
					SELECT id_member
					FROM {$to_prefix}messages
					WHERE id_msg = $row[id_first_msg]
					LIMIT 1");
				list ($row['id_member_started']) = convert_fetch_row($result2);
				convert_free_result($result2);

				convert_query("
					UPDATE {$to_prefix}topics
					SET id_first_msg = '$row[id_first_msg]', id_last_msg = '$row[id_last_msg]',
						id_member_started = '$row[id_member_started]', id_member_updated = '$row[id_member_updated]'
					WHERE id_topic = $row[id_topic]
					LIMIT 1");
			}

			$_GET['substep'] += 150;
			if (convert_num_rows($result) < 150)
				break;

			convert_free_result($result);
		}

		if ($_GET['substep'] > -1)
		{
			alterDatabase('topics', 'add index', array(
				'type' => 'unique',
				'name' => 'last_message',
				'columns' => array('id_last_msg', 'id_board'),
			));

			pastTime(-2);
		}
		if ($_GET['substep'] > -2)
			alterDatabase('messages', 'add index', array(
				'type' => 'unique',
				'name' => 'first_message',
				'columns' => array('id_first_msg', 'id_board'),
			));
	}

	function fixRelativePath($path, $cwd_path)
	{
		// Fix the . at the start, clear any duplicate slashes, and fix any trailing slash...
		return addslashes(preg_replace(array('~^\.([/\\\]|$)~', '~[/]+~', '~[\\\]+~', '~[/\\\]$~'), array($cwd_path . '$1', '/', '\\', ''), $path));
	}

	function parse_time($field, $use_now = true)
	{
		$field = trim(str_replace(array(' um', ' de', ' en', ' la', ' om', ' at'), '', $field));

		if ($field == '')
			$field = $use_now ? time() : 0;
		elseif (strtotime($field) != -1)
			$field = strtotime($field);
		elseif (preg_match('~(\d\d)/(\d\d)/(\d\d)(.*?)(\d\d)\:(\d\d)\:(\d\d)~i', $field, $matches) != 0)
			$field = strtotime("$matches[5]:$matches[6]:$matches[7] $matches[1]/$matches[2]/$matches[3]");
		else
			$field = $use_now ? time() : 0;

		$field = date("Y-m-d", $field);
		return $field;
	}

	function doBlock($table, &$block, $ignore = false)
	{
		global $to_prefix;

		if (empty($block))
			return;

		if ($table == 'members')
		{
			$block_names = array();
			foreach ($block as $i => $row)
				$block_names[$row['member_name']] = $i;

			$request = convert_query("
				SELECT member_name
				FROM {$to_prefix}members
				WHERE member_name IN ('" . implode("', '", array_keys($block_names)) . "')
				LIMIT " . count($block_names));
			while ($row = convert_fetch_assoc($request))
				unset($block[$block_names[$row['member_name']]]);
			convert_free_result($request);

			if (empty($block))
				return;

			unset($block_names);
		}

		convert_insert($table, array_keys($block[0]), $block, 'insert');

		$block = array();
	}
}

?>