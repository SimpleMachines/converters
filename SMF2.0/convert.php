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
define('SMF', 'convert');
error_reporting(E_ALL);

$GLOBALS['required_php_version'] = '4.1.0';
$GLOBALS['required_mysql_version'] = '4.0.18';
$GLOBALS['required_postgresql_version'] = '8.0';

// Buy some time
@set_time_limit(600);

// When in debug mode, we log our errors. Request hasn't been properly setup yet though.
if (isset($_GET['debug']) || isset($_POST['debug']))
	set_error_handler('convert_error_handler');

// We now have CLI support.
if ((php_sapi_name() == 'cli' || (isset($_SERVER['TERM']) && $_SERVER['TERM'] == 'xterm')) && empty($_SERVER['REMOTE_ADDR']))
{
	$command_line = true;
	cmdStep0();
	exit;
}
else
{
	$command_line = false;
	initialize_inputs();
}

if (!empty($_GET['step']))
	$current_step = $_GET['step'];

template_convert_above();

if (!empty($_GET['step']) && ($_GET['step'] == 1 || $_GET['step'] == 2))
	echo '
			<div class="panel">
				<h2>Converting...</h2>';

if (function_exists('doStep' . $_GET['step']))
	call_user_func('doStep' . $_GET['step']);

if (!empty($_GET['step']) && ($_GET['step'] == 1 || $_GET['step'] == 2))
	echo '
			</div>';

template_convert_below();

function initialize_inputs()
{
	global $sourcedir, $smcFunc;

	$smcFunc = array();

	// Save here so it doesn't get overwritten when sessions are restarted.
	$convert_script = @$_REQUEST['convert_script'];

	// Clean up after unfriendly php.ini settings.
	if (function_exists('set_magic_quotes_runtime'))
		@set_magic_quotes_runtime(0);
	error_reporting(E_ALL);
	ignore_user_abort(true);
	umask(0);

	@ob_start();

	if (@ini_get('session.save_handler') == 'user')
		@ini_set('session.save_handler', 'files');
	@session_start();

	// Check session path is writable
	$session_path = @ini_get('session.save_handler');
	// If not lets try another place just for the conversion...
	if (!is_writable($session_path))
		@ini_set('session.save_path', dirname(__FILE__) . '/cache');

	// Add slashes, as long as they aren't already being added.
	if (function_exists('get_magic_quotes_gpc') && @get_magic_quotes_gpc() != 0)
		$_POST = convert_stripslashes_recursive($_POST);

	// This is really quite simple; if ?delete is on the URL, delete the converter...
	if (isset($_GET['delete']))
	{
		@unlink(dirname(__FILE__) . '/convert_error_log');
		@unlink(__FILE__);
		if (preg_match('~_to_smf\.(php|sql)$~', $_SESSION['convert_script']) != 0)
			@unlink(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
		$_SESSION['convert_script'] = null;

		exit;
	}
	// Empty the error log?
	if (isset($_REQUEST['empty_error_log']))
	{
		unset($_REQUEST['empty_error_log']);
		@unlink(dirname(__FILE__) . '/convert_error_log');
	}

	// The current step - starts at 0.
	$_GET['step'] = (int) @$_GET['step'];
	$_REQUEST['start'] = (int) @$_REQUEST['start'];

	// Check for the password...
	if (isset($_POST['db_pass']))
		$_SESSION['convert_db_pass'] = $_POST['db_pass'];
	elseif (isset($_SESSION['convert_db_pass']))
		$_POST['db_pass'] = $_SESSION['convert_db_pass'];

	if (isset($_SESSION['convert_paths']) && !empty($_SESSION['convert_paths'][0]) && !empty($_SESSION['convert_paths'][1]) && !isset($_POST['path_from']) && !isset($_POST['path_to']))
		list ($_POST['path_from'], $_POST['path_to']) = $_SESSION['convert_paths'];
	elseif (isset($_POST['path_from']) || isset($_POST['path_to']))
	{
		if (isset($_POST['path_from']))
			$_POST['path_from'] = substr($_POST['path_from'], -1) == '/' ? substr($_POST['path_from'], 0, -1) : $_POST['path_from'];
		if (isset($_POST['path_to']))
			$_POST['path_to'] = substr($_POST['path_to'], -1) == '/' ? substr($_POST['path_to'], 0, -1) : $_POST['path_to'];

		$_SESSION['convert_paths'] = array(@$_POST['path_from'], @$_POST['path_to']);
	}

	// If we have $convert_script then set it to the session.
	if (!empty($convert_script))
		$_SESSION['convert_script'] = $convert_script;
	if (isset($_SESSION['convert_script']) && file_exists(dirname(__FILE__) . '/' . $_SESSION['convert_script']) && preg_match('~_to_smf\.(php|sql)$~', $_SESSION['convert_script']) != 0)
	{
		if (substr($_SESSION['convert_script'], -4) == '.php')
			preparse_php(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
		else
			preparse_sql(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
	}
	else
		unset($_SESSION['convert_script']);
}

function preparse_sql($script_filename)
{
	global $convert_data;

	$fp = fopen($script_filename, 'r');
	$data = fread($fp, 4096);
	fclose($fp);

	$convert_data['parameters'] = array();

	// This loads name, settings, table_test, from_prefix, defines, and globals.
	preg_match_all('~---\~ ([^:]+):\s*(.+?)\s*\n~', $data, $matches);
	for ($i = 0, $n = count($matches[1]); $i < $n; $i++)
	{
		// String value?
		if (in_array($matches[1][$i], array('name', 'table_test', 'from_prefix', 'version', 'database_type', 'block_size', 'step2_block_size')))
			$convert_data[$matches[1][$i]] = stripslashes(substr(trim($matches[2][$i]), 1, -1));
		// Maybe it is a eval statement?
		elseif ($matches[1][$i] == 'eval')
			$convert_data['eval'][] = $matches[2][$i];
		// No... so it must be an array.
		else
		{
			if (strpos($matches[2][$i], '"') === false)
				preg_match_all('~()([^,]+?)(,|$)~', trim($matches[2][$i]), $values);
			else
				preg_match_all('~(")?([^,]+?)\\1(,|$)~', trim($matches[2][$i]), $values);

			if (!isset($convert_data[$matches[1][$i]]))
				$convert_data[$matches[1][$i]] = array();
			$convert_data[$matches[1][$i]] = array_merge($convert_data[$matches[1][$i]], $values[2]);
		}
	}

	if (empty($convert_data['defines']))
		$convert_data['defines'] = array();
	if (empty($convert_data['globals']))
		$convert_data['globals'] = array();
	if (empty($convert_data['settings']))
		$convert_data['settings'] = array();
	if (empty($convert_data['variable']))
		$convert_data['variable'] = array();
	if (empty($convert_data['database_support']))
		$convert_data['database_support'] = array('mysql');

	// Merge all eval statements together.
	if (!empty($convert_data['eval']))
		$convert_data['eval'] = implode("\r", $convert_data['eval']);

	if (!empty($convert_data['parameters']))
	{
		foreach ($convert_data['parameters'] as $i => $param)
		{
			if (is_array($param))
				continue;

			list ($id, $label) = explode('=', $param);
			if (strpos($id, ' ') !== false)
				list ($id, $type) = explode(' ', $id);
			else
				$type = 'text';

			$convert_data['parameters'][$i] = array(
				'id' => $id,
				'label' => $label,
				'type' => $type,
			);
			$convert_data['globals'][] = $id;
		}
	}

	foreach ($convert_data['globals'] as $k => $v)
	{
		$v = trim($v);
		$convert_data['globals'][$k] = $v[0] == '$' ? substr($v, 1) : $v;
	}

	if (isset($_POST['path_to']) && !empty($_GET['step']))
		loadSettings();
}

function preparse_php($script_filename)
{
	global $convert_data;

	$preparsing = true;
	require($script_filename);

	if (empty($convert_data['parameters']))
		$convert_data['parameters'] = array();
	if (empty($convert_data['defines']))
		$convert_data['defines'] = array();
	if (empty($convert_data['globals']))
		$convert_data['globals'] = array();
	if (empty($convert_data['settings']))
		$convert_data['settings'] = array();
	if (empty($convert_data['variable']))
		$convert_data['variable'] = array();
	if (empty($convert_data['database_support']))
		$convert_data['database_support'] = array('mysql');

	foreach ($convert_data['globals'] as $k => $v)
	{
		$v = trim($v);
		$convert_data['globals'][$k] = $v[0] == '$' ? substr($v, 1) : $v;
	}

	if (isset($_POST['path_to']) && !empty($_GET['step']))
		loadSettings();
}

function loadSettings()
{
	global $convert_data, $from_prefix, $to_prefix, $convert_dbs, $command_line, $smcFunc;
	global $db_persist, $db_connection, $db_server, $db_user, $db_passwd, $modSettings;
	global $db_type, $db_name, $ssi_db_user, $ssi_db_passwd, $sourcedir, $db_prefix;

	foreach ($convert_data['defines'] as $define)
	{
		$define = explode('=', $define);
		define($define[0], isset($define[1]) ? $define[1] : '1');
	}
	foreach ($convert_data['globals'] as $global)
		global $$global;

	if (!empty($convert_data['eval']))
		eval($convert_data['eval']);

	// Cannot find Settings.php?
	if (!$command_line && !file_exists($_POST['path_to'] . '/Settings.php'))
	{
		template_convert_above();
		return doStep0('This converter was unable to find SMF in the path you specified.<br /><br />Please double check the path, and that it is already installed there.');
	}
	elseif ($command_line && !file_exists($_POST['path_to'] . '/Settings.php'))
		return print_error('This converter was unable to find SMF in the path you specified.<br /><br />Please double check the path, and that it is already installed there.', true);

	$found = empty($convert_data['settings']);
	foreach ($convert_data['settings'] as $file)
		$found |= file_exists($_POST['path_from'] . $file);

	/*
		Check if open_basedir is enabled.  If it's enabled and the converter file was not found then that means
		that the user hasn't moved the files to the public html dir.  With this enabled and the file not found, we can't go anywhere from here.
	*/
	if (!$command_line && @ini_get('open_basedir') != '' && !$found)
	{
		template_convert_above();
		return doStep0('The converter detected that your host has open_basedir enabled on this server.  Please ask your host to disable this setting or try moving the contents of your ' . $convert_data['name'] . ' to the public html folder of your site.');
	}
	elseif ($command_line && @ini_get('open_basedir') != '' && !$found)
		return print_error('The converter detected that your host has open_basedir enabled on this server.  Please ask your host to disable this setting or try moving the contents of your ' . $convert_data['name'] . ' to the public html folder of your site.', true);

	if (!$command_line && !$found)
	{
		template_convert_above();
		return doStep0('Unable to find the settings for ' . $convert_data['name'] . '.  Please double check the path and try again.');
	}
	elseif (!$command_line && !$found)
		return print_error('Unable to find the settings for ' . $convert_data['name'] . '.  Please double check the path and try again.', true);

	// Any parameters to speak of?
	if (!empty($convert_data['parameters']) && !empty($_SESSION['convert_parameters']))
	{
		foreach ($convert_data['parameters'] as $param)
		{
			if (isset($_POST[$param['id']]))
				$_SESSION['convert_parameters'][$param['id']] = $_POST[$param['id']];
		}

		// Should already be global'd.
		foreach ($_SESSION['convert_parameters'] as $k => $v)
			$$k = $v;
	}
	elseif (!empty($convert_data['parameters']))
	{
		$_SESSION['convert_parameters'] = array();
		foreach ($convert_data['parameters'] as $param)
		{
			if (isset($_POST[$param['id']]))
				$_SESSION['convert_parameters'][$param['id']] = $_POST[$param['id']];
			else
				$_SESSION['convert_parameters'][$param['id']] = null;
		}

		foreach ($_SESSION['convert_parameters'] as $k => $v)
			$$k = $v;
	}

	// Everything should be alright now... no cross server includes, we hope...
	require($_POST['path_to'] . '/Settings.php');
	require_once($sourcedir . '/QueryString.php');
	require_once($sourcedir . '/Subs.php');
	require_once($sourcedir . '/Errors.php');
	require_once($sourcedir . '/Load.php');
	require_once($sourcedir . '/Security.php');
	require_once($sourcedir . '/Subs-Admin.php');
	// PHP4 users compatibility
	if (@version_compare(PHP_VERSION, '5') == -1)
		require_once($sourcedir . '/Subs-Compat.php');

	$GLOBALS['boardurl'] = $boardurl;
	$modSettings['disableQueryCheck'] = true; // !!! Do we really need this?

	if (!$command_line && $_SESSION['convert_db_pass'] != $db_passwd)
	{
		template_convert_above();
		return doStep0('The database password you entered was incorrect.  Please make sure you are using the right password (for the SMF user!) and try it again.  If in doubt, use the password from Settings.php in the SMF installation.');
	}
	elseif ($command_line && $_SESSION['convert_db_pass'] != $db_passwd)
		return print_error('The database password you entered was incorrect.  Please make sure you are using the right password (for the SMF user!) and try it again.  If in doubt, use the password from Settings.php in the SMF installation.', true);

	// Check the steps that we have decided to go through.
	if (!$command_line && isset($_POST['do_steps']) && empty($_POST['do_steps']))
	{
		template_convert_above();
		return doStep0('You must select at least one step to convert.');
	}
	elseif (!$command_line && isset($_POST['do_steps']))
	{
		unset($_SESSION['do_steps']);
		foreach ($_POST['do_steps'] as $next_step_line => $step)
		{
			//$explode = explode(',', $step);
			//$_SESSION['do_steps'][$key] = array(
			//	'cur_step_line' => $explode[0],
			//	'prev_step_line' => $explode[1],
			//	'next_prev_line' => $explode[2],
			//);
			$_SESSION['do_steps'][$next_step_line] = $step;
		}
	}

	if (isset($_SESSION['convert_parameters']['database_type']) && !isset($convert_data['database_type']))
		$convert_data['database_type'] = $_SESSION['convert_parameters']['database_type'];
	if (isset($convert_data['database_type']) && (function_exists($convert_data['database_type'] . '_query') || function_exists($convert_data['database_type'] . '_exec') || ($convert_data['database_type'] == 'ado' && class_exists('com'))))
	{
		$convert_dbs = $convert_data['database_type'];

		if (isset($convert_data['connect_string']))
			$connect_string = eval('return "' . $convert_data['connect_string'] . '";');
		elseif (isset($_SESSION['convert_parameters']['connect_string']))
			$connect_string = $_SESSION['convert_parameters']['connect_string'];

		if ($convert_dbs == 'odbc')
			$GLOBALS['odbc_connection'] = odbc_connect($connect_string, '', '');
		elseif ($convert_dbs == 'ado')
		{
			$GLOBALS['ado_connection'] = new COM('ADODB.Connection');
			$GLOBALS['ado_connection']->Open($connect_string);

			register_shutdown_function(function () {$GLOBALS['ado_connection']->Close();});
		}
	}
	elseif (!$command_line && isset($convert_data['database_type']))
	{
		template_convert_above();
		return doStep0('PHP doesn\'t support the database type this converter was written for, \'' . $convert_data['database_type'] . '\'.');
	}
	elseif ($command_line && isset($convert_data['database_type']))
		return print_error('PHP doesn\'t support the database type this converter was written for, \'' . $convert_data['database_type'] . '\'.', true);
	else
		$convert_dbs = 'smf_db';

	// Create a connection to the SMF database.
	loadDatabase();
	db_extend('packages');

	// Currently SQLite and PostgreSQL do not have support for cross database work.
	if ($command_line && in_array($smcFunc['db_title'], array('SQLite', 'PostgreSQL')))
		return print_error('The converter detected that you are using ' . $smcFunc['db_title'] . '. The SMF Converter does not currently support this database type.', true);
	elseif (in_array($smcFunc['db_title'], array('SQLite', 'PostgreSQL')))
	{
		template_convert_above();
		return doStep0('The converter detected that you are using ' . $smcFunc['db_title'] . '. The SMF Converter does not currently support this database type.');
	}

	// Does this converter support the current database type being used?
	if ($command_line && !in_array(strtolower($smcFunc['db_title']), $convert_data['database_support']))
		return print_error('The converter detected that you are using ' . $smcFunc['db_title'] . '. This converter only supports ' . explode (', ', $convert_data['database_support']) . '.', true);
	elseif (!in_array(strtolower($smcFunc['db_title']), $convert_data['database_support']))
	{
		template_convert_above();
		return print_error('The converter detected that you are using ' . $smcFunc['db_title'] . '. This converter only supports ' . explode (', ', $convert_data['database_support']) . '.', true);
	}

	// UTF8
	$charset = findSupportedCharsets();
	$charset = array_flip($charset);
	$charset = isset($_POST['charsets']) && isset($charset[$_POST['charsets']]) ? $_POST['charsets'] : '';
	$charset = !empty($charset) ? $charset : (isset($db_character_set) && preg_match('~^\w+$~', $db_character_set) === 1 ? $db_character_set : '');
	if (!empty($charset))
		$smcFunc['db_query']('', "SET NAMES $charset", 'security_override');

	if (strpos($db_prefix, '.') === false)
		$to_prefix = is_numeric(substr($db_prefix, 0, 1)) ? $db_name . '.' . $db_prefix : '`' . $db_name . '`.' . $db_prefix;
	else
		$to_prefix = $db_prefix;

	// Keep in mind our important variables, we don't want them swept away by the code we're running
	$smf_db_prefix = $db_prefix;
	$smf_db_type = $db_type;

	foreach ($convert_data['variable'] as $eval_me)
		eval($eval_me);

	foreach ($convert_data['settings'] as $file)
	{
		if (file_exists($_POST['path_from'] . $file) && empty($convert_data['flatfile']))
			require_once($_POST['path_from'] . $file);
	}

	if (isset($convert_data['from_prefix']))
		$from_prefix = eval('return "' . fixDbPrefix($convert_data['from_prefix'], $smcFunc['db_title']) . '";');

	if (preg_match('~^`[^`]+`.\d~', $from_prefix) != 0)
		$from_prefix = strtr($from_prefix, array('`' => ''));

	// recall our variables in case the software we're converting from defines one itself...
	$db_prefix = $smf_db_prefix;
	$db_type = $smf_db_type;

	if ($_REQUEST['start'] == 0 && empty($_GET['substep']) && empty($_GET['cstep']) && ($_GET['step'] == 1 || $_GET['step'] == 2) && isset($convert_data['table_test']))
	{
		$result = convert_query("
			SELECT COUNT(*)
			FROM " . eval('return "' . $convert_data['table_test'] . '";'), true);
		if (!$command_line && $result === false)
		{
			template_convert_above();
			doStep0('Sorry, the database connection information used in the specified installation of SMF cannot access the installation of ' . $convert_data['name'] . '.  This may either mean that the installation doesn\'t exist, or that the Database account used does not have permissions to access it.<br /><br />The error that was received from the Database was: ' . $smcFunc['db_error']());
		}
		elseif ($command_line && $result === false)
			print_error("Sorry, the database connection information used in the specified installation of SMF cannot access the installation of " . $convert_data['name'] . ".  This may either mean that the installation doesn\'t exist, or that the Database account used does not have permissions to access it.\n\nThe error that was received from the Database: " . $smcFunc['db_error'](), true);
		convert_free_result($result);
	}

	// Attempt to allow big selects, only for mysql so far though.
	if ($smcFunc['db_title'] == 'MySQL')
	{

		// Fix MySQL 5.6 variable name change
		$max_join_var_name = 'SQL_MAX_JOIN_SIZE';

		$mysql_version = $smcFunc['db_server_info']($db_connection);

		if (stripos($mysql_version,"MariaDB") > 0 ||  version_compare($mysql_version, '5.6.0') >= 0)
			$max_join_var_name = 'max_join_size';

		$results = $smcFunc['db_query']('', "SELECT @@SQL_BIG_SELECTS, @@$max_join_var_name", 'security_override');
		list($big_selects, $sql_max_join) = $smcFunc['db_fetch_row']($results);

		// Only waste a query if its worth it.
		if (empty($big_selects) || ($big_selects != 1 && $big_selects != '1'))
			$smcFunc['db_query']('', "SET @@SQL_BIG_SELECTS = 1", 'security_override');

		// Lets set MAX_JOIN_SIZE to something we should
		if (empty($sql_max_join) || ($sql_max_join == '18446744073709551615' && $sql_max_join == '18446744073709551615'))
			$smcFunc['db_query']('', "SET @@$max_join_var_name = 18446744073709551615", 'security_override');
	}

	// Since we use now the attachment functions in Subs.php, we'll need this:
	$result = convert_query("
			SELECT value
			FROM {$to_prefix}settings
			WHERE variable = 'attachmentUploadDir'
			LIMIT 1");
	list($attachmentUploadDir) = $smcFunc['db_fetch_row']($result);
	$modSettings['attachmentUploadDir'] = $attachmentUploadDir;
	$smcFunc['db_free_result']($result);

}

function findConvertScripts()
{
	global $convert_data;

	if (isset($_REQUEST['convert_script']))
	{
		if ($_REQUEST['convert_script'] != '' && preg_match('~^[a-z0-9\-_\.]*_to_smf\.(sql|php)$~i', $_REQUEST['convert_script']) != 0)
		{
			$_SESSION['convert_script'] = preg_replace('~[\.]+~', '.', $_REQUEST['convert_script']);
			if (substr($_SESSION['convert_script'], -4) == '.php')
				preparse_php(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
			else
				preparse_sql(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
		}
		else
			$_SESSION['convert_script'] = null;
	}

	$preparsing = true;

	$dir = dir(dirname(__FILE__));
	$scripts = array();
	while ($entry = $dir->read())
	{
		if (substr($entry, -11) != '_to_smf.sql' && substr($entry, -11) != '_to_smf.php')
			continue;

		$fp = fopen(dirname(__FILE__) . '/' . $entry, 'r');
		$data = fread($fp, 4096);
		fclose($fp);

		if (substr($entry, -11) == '_to_smf.sql')
		{
			if (preg_match('~---\~ name:\s*"(.+?)"~', $data, $match) != 0)
				$scripts[] = array('path' => $entry, 'name' => $match[1]);
		}
		elseif (substr($entry, -11) == '_to_smf.php')
		{
			if (preg_match('~\$convert_data =~', $data) != 0)
			{
				require(dirname(__FILE__) . '/' . $entry);
				$scripts[] = array('path' => $entry, 'name' => $convert_data['name']);
			}
		}
	}
	$dir->close();

	if (isset($_SESSION['convert_script']))
	{
		if (count($scripts) > 1)
			$GLOBALS['possible_scripts'] = $scripts;
		return false;
	}

	if (count($scripts) == 1)
	{
		$_SESSION['convert_script'] = basename($scripts[0]['path']);
		if (substr($_SESSION['convert_script'], -4) == '.php')
			preparse_php(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
		else
			preparse_sql(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
		return false;
	}

	echo '
		<div class="panel">
			<h2>Which software are you using?</h2>';

	if (!empty($scripts))
	{
		echo '
			<h3>The converter found multiple conversion data files.  Please choose the one you wish to use.</h3>

			<ul>';

		foreach ($scripts as $script)
			echo '
				<li><a href="', $_SERVER['PHP_SELF'], '?convert_script=', $script['path'], '">', $script['name'], '</a> <em>(', $script['path'], ')</em></li>';

		echo '
			</ul>

			<h2>It\'s not here!</h2>
			<h3>If the software you\'re looking for doesn\'t appear above, please check to see if it is available for download at <a href="http://www.simplemachines.org/">www.simplemachines.org</a>.  If it isn\'t, we may be able to write one for you - just ask us!</h3>

			If you\'re having any other problems with this converter, don\'t hesitate to look for help on our <a href="http://www.simplemachines.org/community/index.php">forum</a>.';
	}
	else
	{
		echo '
			<h3>The converter did not find any conversion data files.  Please check to see if the one you want is available for download at <a href="http://www.simplemachines.org/">www.simplemachines.org</a>.  If it isn\'t, we may be able to write one for you - just ask us!</h3>

			After you download it, simply upload it into the same folder as <strong>this convert.php file</strong>.  If you\'re having any other problems with this converter, don\'t hesitate to look for help on our <a href="http://www.simplemachines.org/community/index.php">forum</a>.<br />
			<br />
			<a href="', $_SERVER['PHP_SELF'], '?convert_script=">Try again</a>';
	}

	echo '
		</div>';

	return true;
}

// Looks at the converter and returns the steps that it's able to make.
function findSteps()
{
	global $current_type, $convert_data;

	// No file?
	if (empty($_SESSION['convert_script']))
		return array();

	$steps = array();
	$count_steps = 1;

	// Can we support php files?
	if (substr($_SESSION['convert_script'], -4) == '.php')
	{
		// Load the file.
		if (empty($convert_data))
		{
			$preparsing = true;
			require(dirname(__FILE__) . '/' . $_SESSION['convert_script']);
		}

		if (!empty($convert_data['steps']))
			return $convert_data['steps'];
		elseif (!empty($convert_data['num_steps']))
		{
			$i = 1;
			while ($i <= $convert_data['num_steps'])
			{
				$steps[$count_steps] = array(
					'name' => 'SubStep #' . $i,
					'cur_step_line' => $i,
					'prev_step_line' => $i - 1,
					'next_step_line' => $i + 1,
					'count' => $count_steps++,
				);
				++$i;
			}
			return $steps;
		}
	}

	// Load the file.
	$lines = file(dirname(__FILE__) . '/' . $_SESSION['convert_script']);

	// Need an outside counter for the steps.
	foreach ($lines as $line_number => $line)
	{
		// Get rid of any comments in the beginning of the line...
		if (substr(trim($line), 0, 2) === '/*')
			$line = preg_replace('~/\*.+?\*/~', '', $line);

		if (trim($line) === '')
			continue;

		// We found the treasure :P.
		if (substr($line, 0, 4) === '--- ')
		{
			$steps[$count_steps] = array(
				'name' => trim(substr(htmlspecialchars($line), 4)),
				'cur_step_line' => $line_number,
				'prev_step_line' => 0,
				'next_step_line' => 0,
				'count' => $count_steps,
			);

			// Previous step line number.
			if (isset($steps[$count_steps - 1]))
			{
				$steps[$count_steps]['prev_step_line'] = $steps[$count_steps - 1]['cur_step_line'];
				$steps[$count_steps - 1]['next_step_line'] = $line_number;
			}
			$count_steps++;
		}
		else
			continue;
	}

	return $steps;
}

function findSupportedCharsets()
{
	global $smcFunc;

	// Just assume these.
	if ($smcFunc['db_title'] == 'SQLite')
		return $charsets = array(
			'ISO-8859-1' => 'latin1',
			'UTF-8' => 'utf8',
		);

	// The character sets used in SMF's language files with their db equivalent.
	$charsets = array(
		// Chinese-traditional.
		'big5' => 'big5',
		// Chinese-simplified.
		'gbk' => 'gbk',
		// West European.
		'ISO-8859-1' => 'latin1',
		// Romanian.
		'ISO-8859-2' => 'latin2',
		// Turkish.
		'ISO-8859-9' => 'latin5',
		// West European with Euro sign.
		'ISO-8859-15' => 'latin9',
		// Thai.
		'tis-620' => 'tis620',
		// Persian, Chinese, etc.
		'UTF-8' => 'utf8',
		// Russian.
		'windows-1251' => 'cp1251',
		// Greek.
		'windows-1253' => 'utf8',
		// Hebrew.
		'windows-1255' => 'utf8',
		// Arabic.
		'windows-1256' => 'cp1256',
	);

	// Get a list of character sets supported by your Database server.
	$result = @$smcFunc['db_query']('', "
		SHOW CHARACTER SET", 'security_override');
	$db_charsets = array();
	while ($row = $smcFunc['db_fetch_assoc']($result))
		$db_charsets[] = $row['Charset'];

	// Character sets supported by both Database and SMF's language files.
	return $charsets = array_intersect($charsets, $db_charsets);
}

// Correct the prefix
function fixDbPrefix($prefix, $db_type)
{
	if ($db_type == 'MySQL')
		return $prefix;
	elseif ($db_type == 'PostgreSQL')
	{
		$temp = explode('.', $prefix);
		return str_replace('`', '', $temp[0] . '.public.' . $temp[1]);
	}
	elseif ($db_type == 'SQLite')
		return str_replace(array('`', '.'), '', $prefix);
	else
		die('Unknown Database: ' . $db_type);
}

// Main Window
function doStep0($error_message = null)
{
	global $convert_data, $current_step;

	$current_step = 0;
	if (findConvertScripts())
		return true;

	// If these aren't set (from an error..) default to the current directory.
	if (!isset($_POST['path_from']))
		$_POST['path_from'] = dirname(__FILE__);
	if (!isset($_POST['path_to']))
		$_POST['path_to'] = dirname(__FILE__);

	$test_from = empty($convert_data['settings']);
	foreach ($convert_data['settings'] as $s)
		$test_from |= file_exists($_POST['path_from'] . $s);

	$test_to = file_exists($_POST['path_to'] . '/Settings.php');

	// Do we have steps?
	$steps = findSteps();
	// How about charater sets.
	$charsets = array(
		// Chinese-traditional.
		'big5' => 'big5',
		// Chinese-simplified.
		'gbk' => 'gbk',
		// West European.
		'ISO-8859-1' => 'latin1',
		// Romanian.
		'ISO-8859-2' => 'latin2',
		// Turkish.
		'ISO-8859-9' => 'latin5',
		// West European with Euro sign.
		'ISO-8859-15' => 'latin9',
		// Thai.
		'tis-620' => 'tis620',
		// Persian, Chinese, etc.
		'UTF-8' => 'utf8',
		// Russian.
		'windows-1251' => 'cp1251',
		// Greek.
		'windows-1253' => 'utf8',
		// Hebrew.
		'windows-1255' => 'utf8',
		// Arabic.
		'windows-1256' => 'cp1256',
	);

	// Was an error message specified?
	if ($error_message !== null)
		echo '
			<div class="error_message">
				<div style="color: red;">', $error_message, '</div>
			</div>
			<br />';

	echo '
			<div class="panel">
				<form action="', $_SERVER['PHP_SELF'], '?step=1', isset($_REQUEST['debug']) ? '&amp;debug=' . $_REQUEST['debug'] : '', '" method="post">
					<h2>Before you continue</h2>
					<div style="margin-bottom: 2ex;">This converter assumes you have already installed SMF and that your installation is working properly.  It copies posts and data from your &quot;source&quot; installation of ', $convert_data['name'], ' into SMF, so it won\'t work without an installation of SMF.  All or some of the data in your installation of SMF will be <strong>overwritten</strong>.</div>';

	if (empty($convert_data['flatfile']))
		echo '
					<div style="margin-bottom: 2ex;">If the two software\'s are installed in separate directories, the Database account SMF was installed using will need access to the other database.  Either way, both must be installed on the same Database server.</div>';

	echo '

					<h2>Where are they?</h2>
					<h3>The converter should only need to know where the two installations are, after which it should be able to handle everything for itself.</h3>

					<table width="100%" cellpadding="0" cellspacing="0" border="0" align="center">
						<tr>
							<td width="20%" valign="top" class="textbox"><label for="path_to">Path to SMF:</label></td>
							<td style="padding-bottom: 1ex;">
								<input type="text" name="path_to" id="path_to" value="', $_POST['path_to'], '" size="60" class="input_text" />
								<div style="font-style: italic; font-size: smaller;">', $test_to ? 'This may be the right path.' : 'You will need to change the value in this box.', '</div>
							</td>';

	if (!empty($convert_data['settings']))
		echo '
						</tr><tr>
							<td valign="top" class="textbox"><label for="path_from">Path to ', $convert_data['name'], ':</label></td>
							<td style="padding-bottom: 1ex;">
								<input type="text" name="path_from" id="path_from" value="', $_POST['path_from'], '" size="60" class="input_text" />
								<div style="font-style: italic; font-size: smaller;">', $test_from ? 'This may be the right path.' : 'You will need to change the value in this box.', '</div>
							</td>';

	if (!empty($convert_data['parameters']))
	{
		foreach ($convert_data['parameters'] as $param)
		{
			echo '
						</tr><tr>';

			// Is it a checkbox?
			if ($param['type'] == 'checked' || $param['type'] == 'checkbox')
				echo '
							<td valign="top" class="textbox"></td>
							<td style="padding-bottom: 1ex;">
								<input type="hidden" name="', $param['id'], '" value="0" />
								<label for="', $param['id'], '"><input type="checkbox" name="', $param['id'], '" id="', $param['id'], '" value="1"', $param['type'] == 'checked' ? ' checked="checked"' : '', ' class="input_check" /> ', $param['label'], '</label>';
			// How about a list?
			elseif (($param['type'] == 'list' || $param['type'] == 'select') && isset($param['options']) && is_array($param['options']))
			{
				echo '
							<td valign="top" class="textbox"></td>
							<td style="padding-bottom: 1ex;">
								<input type="hidden" name="', $param['id'], '" value="0" />
								<label for="', $param['id'], '"><select name="', $param['id'], '" id="', $param['id'], '">';

					foreach ($param['options'] as $id => $option)
						echo '
									<option value="', $id, '"', (isset($param['default_option']) && $param['default_option'] == $id ? ' selected="selected"' : ''), '>', $option, '</option>';

				echo '
								</select></label>';

			}
			elseif ($param['type'] == 'password')
				echo '
							<td valign="top" class="textbox"><label for="', $param['id'], '">', $param['label'], ':</label></td>
							<td style="padding-bottom: 1ex;">
								<input type="password" name="', $param['id'], '" id="', $param['id'], '" value="" size="60" class="input_password" />';
			// Fall back to text.
			else
				echo '
							<td valign="top" class="textbox"><label for="', $param['id'], '">', $param['label'], ':</label></td>
							<td style="padding-bottom: 1ex;">
								<input type="text" name="', $param['id'], '" id="', $param['id'], '" value="" size="60" class="input_text" />';

			echo '
							</td>';
		}
	}

	echo '
						</tr><tr>
							<td valign="top" class="textbox" style="padding-top: 2ex;"><label for="db_pass">SMF database password:</label></td>
							<td valign="top" style="padding-top: 2ex; padding-bottom: 1ex;">
								<input type="password" name="db_pass" size="30" class="text input_password" />
								<div style="font-style: italic; font-size: smaller;">The Database password (for verification only.)</div>
							</td>
						</tr>';

	// Now with this UTF-8 stuff we need to work more on charsets.
	if (!empty($charsets))
	{
		echo '
						<tr>
							<td valign="top" class="textbox"><label for="charsets">Set SMF\'s default character set to:</label></td>
							<td valign="top" style="padding-top: 2ex; padding-bottom: 1ex;">
								<select name="charsets" id="charsets">';
		foreach ($charsets as $name => $id)
			echo '
									<option value="', $id, '"', $id == 'latin1' ? ' selected="selected"' : '', '>', $name, '</option>';
		echo '
								</select>
							</td>
						</tr>';
	}

	// Now for the steps.
	if (!empty($steps) && 1 == 0)
	{
		echo '
						<tr>
							<td valign="top" class="textbox">Convert selected areas ONLY:</td>
							<td valign="top" style="padding-top: 2ex; padding-bottom: 1ex;">';
		foreach ($steps as $key => $step)
			echo '
								<input type="checkbox" name="do_steps[', $step['next_step_line'], ']" id="do_steps[', $step['next_step_line'], ']" value="', $step['count'], '" checked="checked" class="input_check" /><label for="do_steps[', $step['next_step_line'], ']">', ucfirst(str_replace('Converting ', '', $step['name'])), '</label><br />';
		echo '
							</td>
						</tr>';
	}

	// Empty our error log?
	echo '
						</tr><tr>
							<td valign="top" class="textbox" style="padding-top: 2ex;"><label for="empty_error_log">Empty the convert error log?</label></td>
							<td valign="top" style="padding-top: 2ex; padding-bottom: 1ex;">
								<input type="checkbox" name="empty_error_log" value="1" class="input_check" />
							</td>
						</tr>';

	echo '
					</table>
					<div class="righttext" style="margin: 1ex; margin-top: 0;"><input name="b" type="submit" value="Continue" class="submit button_submit" /></div>
				</form>
			</div>';

	if (!empty($GLOBALS['possible_scripts']))
		echo '
			<div class="panel">
				<h2>Not this software?</h2>
				<h3>If this is the wrong software, you can go back and <a href="', $_SERVER['PHP_SELF'], '?convert_script=">pick a different data file</a>.</h3>
			</div>';

	if ($error_message !== null)
	{
		template_convert_below();
		exit;
	}

	return;
}

// Do the main step.
function doStep1()
{
	global $from_prefix, $to_prefix, $convert_data, $command_line, $smcFunc, $modSettings;
	global $current_step, $current_substep, $last_step;

	$current_step = 1;

	if (substr($_SESSION['convert_script'], -4) == '.php')
		return run_php_converter();

	foreach ($convert_data['globals'] as $global)
		global $$global;

	$_GET['substep'] = (int) @$_GET['substep'];

	// In CLI we end lines differently.
	$endl = $command_line ? "\n" : '<br />' . "\n";

	// Staring the converter.
	if ($command_line)
		print_line($endl . 'Starting Conversion');

	$lines = file(dirname(__FILE__) . '/' . $_SESSION['convert_script']);

	// Available steps.  This is the list of all the steps that were found.
	$available_steps = findSteps();

	$current_type = 'sql';
	$current_data = '';
	$substep = 0;
	$last_step = '';
	$special_table = null;
	$special_code = null;

	foreach ($lines as $line_number => $line)
	{
		$do_current = $substep >= $_GET['substep'];

		// Get rid of any comments in the beginning of the line...
		if (substr(trim($line), 0, 2) === '/*')
			$line = preg_replace('~/\*.+?\*/~', '', $line);

		if (trim($line) === '')
			continue;

		// Skipping steps?
		/*if (isset($_SESSION['do_steps']))
		{
			$current_step1 = trim(substr($line, 4));
			$do_steps = $_SESSION['do_steps'];
			$reverse = array_flip($_SESSION['do_steps']);
			//print_r($_SESSION['do_steps']);die;
			//if (isset($reverse[$current_step1]) && (!in_array($current_step1, $do_steps) && ($line_number < $reverse[$current_step1])))
			//	continue;
			//echo $substep;
			//print_r($do_steps);
			if (!in_array($substep, $do_steps))
			{
				// Lets make sure $substep is not 0
				$substep = $substep == 0 ? 1 : $subtep++;
				print_line($current_step1 . ' skipped...');
				$_REQUEST['start'] = 0;
				pastTime($substep);
			}
		}*/

		if (trim(substr($line, 0, 3)) === '---')
		{
			$type = substr($line, 3, 1);

			if (trim($current_data) != '' && $type !== '}')
				print_line('Error in convert script - line ' . $line_number . '!');

			if ($type == ' ')
			{
				if ($do_current && $_GET['substep'] != 0)
				{
					print_line(' Successful.');
					flush();
				}

				$last_step = htmlspecialchars(rtrim(substr($line, 4)));

				if ($do_current)
				{
					$print_line = ($command_line ? ' * ' : '') . $last_step;
					print_line($print_line, false);

					pastTime($substep);
				}
			}
			elseif ($type == '#')
			{
				if (!empty($_SESSION['convert_debug']) && $do_current)
				{
					if (trim($line) == '---#')
						print_line(' done.');
					else
						print_line('&nbsp;&nbsp;&nbsp;', htmlspecialchars(rtrim(substr($line, 4))));
				}

				if ($substep < $_GET['substep'] && $substep + 1 >= $_GET['substep'])
				{
					$print_line = ($command_line ? ' * ' : '') . $last_step;
					print_line($print_line, false);
				}

				// Small step!
				pastTime(++$substep);
			}
			elseif ($type == '{')
				$current_type = 'code';
			elseif ($type == '}')
			{
				$current_type = 'sql';

				if (!$do_current)
				{
					$current_data = '';
					continue;
				}

				if ($special_table !== null)
					$special_code = $current_data;
				else
				{
					if (eval($current_data) === false)
						print_error('
			<strong>Error in convert script ', $_SESSION['convert_script'], ' on line ', $line_number, '!</strong><br />');
				}

				// Done with code!
				$current_data = '';
			}
			elseif ($type == '*')
			{
				if ($substep < $_GET['substep'] && $substep + 1 >= $_GET['substep'])
				{
					$print_line = $last_step . (empty($_SESSION['convert_debug']) ? ' ' : $endl);
					print_line($print_line);
				}

				if ($special_table === null)
				{
					$special_table = strtr(trim(substr($line, 4)), array('{$to_prefix}' => $to_prefix));

					if (preg_match('~^([^ ()]+?)( \(update .+?\))? (\d+)$~', trim($special_table), $match) != 0)
					{
						$special_table = $match[1];
						$special_update = $match[2] != '' ? substr($match[2], 9, -1) : '';
						$special_limit = empty($match[3]) ? (!empty($convert['block_size']) ? $convert['block_size'] : 500) : (int) $match[3];
					}
					elseif (preg_match('~^([^ ()]+?) \(update (.+?)\)$~', trim($special_table), $match) != 0)
					{
						$special_table = $match[1];
						$special_update = $match[2];
						$special_limit = (!empty($convert['block_size']) ? $convert['block_size'] : 200);
					}
					else
					{
						$special_update = false;
						$special_limit = (!empty($convert['block_size']) ? $convert['block_size'] : 500);
					}
				}
				else
				{
					$special_table = null;
					$special_code = null;
				}

				// Increase the substep slightly...
				pastTime(++$substep);
			}

			continue;
		}

		$current_data .= $line;
		if (substr(rtrim($current_data), -1) === ';' && $current_type === 'sql')
		{
			if (!$do_current)
			{
				$current_data = '';
				continue;
			}

			$current_data = strtr(substr(rtrim($current_data), 0, -1), array('{$from_prefix}' => $from_prefix, '{$to_prefix}' => $to_prefix));
			if (strpos($current_data, '{$') !== false)
				$current_data = eval('return "' . addcslashes($current_data, '\\"') . '";');

			if (isset($convert_table) && $convert_table !== null && strpos($current_data, '%d') !== false)
			{
				preg_match('~FROM [(]?([^\s,]+)~i', $convert_data, $match);
				if (!empty($match))
				{
					$result = convert_query("
						SELECT COUNT(*)
						FROM $match[1]");
					list ($special_max) = convert_fetch_row($result);
					$smcFunc['db_free_result']($result);
				}
				else
					$special_max = 0;
			}
			else
				$special_max = 0;

			if ($special_table === null)
				convert_query($current_data);
			elseif ($special_update != false)
			{
				while (true)
				{
					pastTime($substep);

					if (strpos($current_data, '%d') !== false)
						$special_result = convert_query(sprintf($current_data, $_REQUEST['start'], $_REQUEST['start'] + $special_limit - 1) . "\n" . 'LIMIT ' . $special_limit);
					else
						$special_result = convert_query($current_data . "\n" . 'LIMIT ' . $_REQUEST['start'] . ', ' . $special_limit);
					while ($row = convert_fetch_assoc($special_result))
					{
						if ($special_code !== null)
							eval($special_code);

						if (empty($no_add) && count($row) >= 2)
						{
							$setString = array();
							foreach ($row as $k => $v)
							{
								if ($k != $special_update)
									$setString[] = "$k = '" . addslashes($v) . "'";
							}

							convert_query("
								UPDATE " . $special_table . "
								SET " . implode(', ', $setString) . "
								WHERE $special_update = '" . $row[$special_update] . "'");
						}
						else
							$no_add = false;
					}

					$_REQUEST['start'] += $special_limit;
					if (empty($special_max) && convert_num_rows($special_result) < $special_limit)
						break;
					elseif (!empty($special_max) && convert_num_rows($special_result) == 0 && $_REQUEST['start'] > $special_max)
						break;
					convert_free_result($special_result);
				}
			}
			else
			{
				// Are we doing attachments?  They're going to want a few things...
				if ($special_table == $to_prefix . 'attachments')
				{
					if (!isset($id_attach, $attachmentUploadDir))
					{
						$result = convert_query("
							SELECT MAX(id_attach) + 1
							FROM {$to_prefix}attachments");
						list ($id_attach) = $smcFunc['db_fetch_row']($result);
						$smcFunc['db_free_result']($result);

						$result = convert_query("
							SELECT value
							FROM {$to_prefix}settings
							WHERE variable = 'attachmentUploadDir'
							LIMIT 1");
						list ($attachmentUploadDir) = $smcFunc['db_fetch_row']($result);
						$smcFunc['db_free_result']($result);

						if (empty($id_attach))
							$id_attach = 1;
					}
				}

				while (true)
				{
					pastTime($substep);

					if (strpos($current_data, '%d') !== false)
						$special_result = convert_query(sprintf($current_data, $_REQUEST['start'], $_REQUEST['start'] + $special_limit - 1) . "\n" . 'LIMIT ' . $special_limit);
					else
						$special_result = convert_query($current_data . "\n" . 'LIMIT ' . $_REQUEST['start'] . ', ' . $special_limit);
					$rows = array();
					$keys = array();
					while ($row = convert_fetch_assoc($special_result))
					{
						if ($special_code !== null)
							eval($special_code);

						// Here we have various bits of custom code for some known problems global to all converters.
						if ($special_table == $to_prefix . 'members')
						{
							// Let's ensure there are no illegal characters.
							$row['member_name'] = preg_replace('/[<>&"\'=\\\]/is', '', $row['member_name']);
							$row['real_name'] = trim($row['real_name'], " \t\n\r\x0B\0\xA0");

							if (strpos($row['real_name'], '<') !== false || strpos($row['real_name'], '>') !== false || strpos($row['real_name'], '& ') !== false)
								$row['real_name'] = htmlspecialchars($row['real_name'], ENT_QUOTES);
							else
								$row['real_name'] = strtr($row['real_name'], array('\'' => '&#039;'));
						}

						// Not adding anything?
						if (empty($no_add) && empty($ignore_slashes))
						{
							// You don't know where its been.
							$temp = array();

							// Simply loop each row, clean it and put it in a temp array.
							foreach ($row as $key => $dirty_string)
								$temp[$key] = addslashes_recursive($dirty_string);

							// Now that mess is over. Save it.
							$rows[] = $temp;
						}
						elseif (empty($no_add) && !empty($ignore_slashes))
							$rows[] = $row;
						else
							$no_add = false;

						if (!empty($rows))
							$keys = array_keys($rows[0]);
						else
							$keys = array_keys($row);
					}

					// Provide legacy for $ignore
					if (!empty($ignore) && $ignore == 'ignore')
						$type = 'ignore';

					// Simple, if its not set or if its not in that array, force default.
					if (empty($type) || !in_array($type, array('ignore', 'replace', 'insert', 'insert ignore')))
						$type = 'insert';

					// Finally, insert the data. true in this ignores the prefix.
					if (!empty($rows))
						convert_insert($special_table, $keys, $rows, $type, true);

					$_REQUEST['start'] += $special_limit;
					if (empty($special_max) && convert_num_rows($special_result) < $special_limit)
						break;
					elseif (!empty($special_max) && convert_num_rows($special_result) == 0 && $_REQUEST['start'] > $special_max)
						break;
					convert_free_result($special_result);
				}
			}

			$_REQUEST['start'] = 0;
			$special_code = null;
			$current_data = '';
		}
	}

	print_line(' Successful.');
	flush();

	$_GET['substep'] = 0;
	$_REQUEST['start'] = 0;

	return doStep2();
}

function run_php_converter()
{
	global $from_prefix, $to_prefix, $convert_data, $smcFunc;

	foreach ($convert_data['globals'] as $global)
		global $$global;

	$_GET['substep'] = (int) @$_GET['substep'];
	$_GET['cstep'] = (int) @$_GET['cstep'];

	require(dirname(__FILE__) . '/' . $_SESSION['convert_script']);

	if (function_exists('load_converter_settings'))
		load_converter_settings();

	for ($_GET['cstep'] = max(1, $_GET['cstep']); function_exists('convertStep' . $_GET['cstep']); $_GET['cstep']++)
	{
		call_user_func('convertStep' . $_GET['cstep']);
		$_GET['substep'] = 0;
		pastTime(0);

		print_line(' Successful.');
		flush();
	}

	$_GET['substep'] = 0;
	$_REQUEST['start'] = 0;

	return doStep2();
}

function doStep2()
{
	global $convert_data, $from_prefix, $to_prefix, $modSettings, $command_line;
	global $smcFunc, $sourcedir, $current_step;

	$current_step = 2;
	$_GET['step'] = '2';

	$debug = false;
	if (isset($_REQUEST['debug']))
		$debug = true;

	print_line(($command_line ? ' * ' : '') . 'Recalculating forum statistics... ', false);

	if ($_GET['substep'] <= 0)
	{
		if ($debug)
			print_line('Get all members with wrong number of personal messages..');

		// Get all members with wrong number of personal messages.
		$request = convert_query("
			SELECT mem.id_member, COUNT(pmr.id_pm) AS real_num, mem.instant_messages
			FROM {$to_prefix}members AS mem
				LEFT JOIN {$to_prefix}pm_recipients AS pmr ON (mem.id_member = pmr.id_member AND pmr.deleted = 0)
			GROUP BY mem.id_member
			HAVING real_num != instant_messages");
		while ($row = $smcFunc['db_fetch_assoc']($request))
		{
			convert_query("
				UPDATE {$to_prefix}members
				SET instant_messages = $row[real_num]
				WHERE id_member = $row[id_member]
				LIMIT 1");

			pastTime(0);
		}
		$smcFunc['db_free_result']($request);

		if ($debug)
			print_line('Correct all unread messages..');

		$request = convert_query("
			SELECT mem.id_member, COUNT(pmr.id_pm) AS real_num, mem.unread_messages
			FROM {$to_prefix}members AS mem
				LEFT JOIN {$to_prefix}pm_recipients AS pmr ON (mem.id_member = pmr.id_member AND pmr.deleted = 0 AND pmr.is_read = 0)
			GROUP BY mem.id_member
			HAVING real_num != unread_messages");
		while ($row = $smcFunc['db_fetch_assoc']($request))
		{
			convert_query("
				UPDATE {$to_prefix}members
				SET unread_messages = $row[real_num]
				WHERE id_member = $row[id_member]
				LIMIT 1");

			pastTime(0);
		}
		$smcFunc['db_free_result']($request);

		pastTime(1);
	}

	if ($_GET['substep'] <= 1)
	{
		if ($debug)
			print_line('Correct boards with incorrect msg ids..');

		$request = convert_query("
			SELECT id_board, MAX(id_msg) AS id_last_msg, MAX(modified_time) AS last_edited
			FROM {$to_prefix}messages
			GROUP BY id_board");
		$modifyData = array();
		$modifyMsg = array();
		while ($row = $smcFunc['db_fetch_assoc']($request))
		{
			convert_query("
				UPDATE {$to_prefix}boards
				SET id_last_msg = $row[id_last_msg], id_msg_updated = $row[id_last_msg]
				WHERE id_board = $row[id_board]
				LIMIT 1");
			$modifyData[$row['id_board']] = array(
				'last_msg' => $row['id_last_msg'],
				'last_edited' => $row['last_edited'],
			);
			$modifyMsg[] = $row['id_last_msg'];
		}
		$smcFunc['db_free_result']($request);

		// Are there any boards where the updated message is not the last?
		if (!empty($modifyMsg))
		{
			if ($debug)
				print_line('Correct any boards that do not show the correct last message..');

			$request = convert_query("
				SELECT id_board, id_msg, modified_time, poster_time
				FROM {$to_prefix}messages
				WHERE id_msg IN (" . implode(',', $modifyMsg) . ")");
			while ($row = $smcFunc['db_fetch_assoc']($request))
			{
				// Have we got a message modified before this was posted?
				if (max($row['modified_time'], $row['poster_time']) < $modifyData[$row['id_board']]['last_edited'])
				{
					// Work out the ID of the message (This seems long but it won't happen much.
					$request2 = convert_query("
						SELECT id_msg
						FROM {$to_prefix}messages
						WHERE modified_time = " . $modifyData[$row['id_board']]['last_edited'] . "
						LIMIT 1");
					if ($smcFunc['db_num_rows']($request2) != 0)
					{
						list ($id_msg) = $smcFunc['db_fetch_row']($request2);

						convert_query("
							UPDATE {$to_prefix}boards
							SET id_msg_updated = $id_msg
							WHERE id_board = $row[id_board]
							LIMIT 1");
					}
					$smcFunc['db_free_result']($request2);
				}
			}
			$smcFunc['db_free_result']($request);
		}

		pastTime(2);
	}

	if ($_GET['substep'] <= 2)
	{
		if ($debug)
			print_line('Correct any incorrect groups..');

		$request = convert_query("
			SELECT id_group
			FROM {$to_prefix}membergroups
			WHERE min_posts = -1");
		$all_groups = array();
		while ($row = $smcFunc['db_fetch_assoc']($request))
			$all_groups[] = $row['id_group'];
		$smcFunc['db_free_result']($request);

		$request = convert_query("
			SELECT id_board, member_groups
			FROM {$to_prefix}boards
			WHERE FIND_IN_SET(0, member_groups)");
		while ($row = $smcFunc['db_fetch_assoc']($request))
			convert_query("
				UPDATE {$to_prefix}boards
				SET member_groups = '" . implode(',', array_unique(array_merge($all_groups, explode(',', $row['member_groups'])))) . "'
				WHERE id_board = $row[id_board]
				LIMIT 1");
		$smcFunc['db_free_result']($request);

		pastTime(3);
	}

	if ($_GET['substep'] <= 3)
	{
		if ($debug)
			print_line('Update our statitics..');

		// Get the number of messages...
		$result = convert_query("
			SELECT COUNT(*) AS total_messages, MAX(id_msg) AS max_msg_id
			FROM {$to_prefix}messages");
		$row = $smcFunc['db_fetch_assoc']($result);
		$smcFunc['db_free_result']($result);

		// Update the latest member.  (highest id_member)
		$result = convert_query("
			SELECT id_member AS latest_member, real_name AS latest_real_name
			FROM {$to_prefix}members
			ORDER BY id_member DESC
			LIMIT 1");
		if ($smcFunc['db_num_rows']($result))
			$row += $smcFunc['db_fetch_assoc']($result);
		$smcFunc['db_free_result']($result);

		// Update the member count.
		$result = convert_query("
			SELECT COUNT(*) AS total_members
			FROM {$to_prefix}members");
		$row += $smcFunc['db_fetch_assoc']($result);
		$smcFunc['db_free_result']($result);

		// Get the number of topics.
		$result = convert_query("
			SELECT COUNT(*) AS total_topics
			FROM {$to_prefix}topics");
		$row += $smcFunc['db_fetch_assoc']($result);
		$smcFunc['db_free_result']($result);

		$smcFunc['db_insert']('replace',
			'{db_prefix}settings',
			array('variable' => 'string', 'value' => 'string',),
			array(
				array('latest_member', $row['latest_member']),
				array('latest_real_name', $row['latest_real_name']),
				array('total_members', $row['total_members']),
				array('total_messages', $row['total_messages']),
				array('max_msg_id', $row['max_msg_id']),
				array('total_topics', $row['total_topics']),
				array('disable_hash_time', time() + 7776000),
			),
			array('name')
		);

		pastTime(4);
	}

	if ($_GET['substep'] <= 4)
	{
		if ($debug)
			print_line('Correct any posts groups..');

		$request = convert_query("
			SELECT id_group, min_posts
			FROM {$to_prefix}membergroups
			WHERE min_posts != -1
			ORDER BY min_posts DESC");
		$post_groups = array();
		while ($row = $smcFunc['db_fetch_assoc']($request))
			$post_groups[$row['min_posts']] = $row['id_group'];
		$smcFunc['db_free_result']($request);

		$request = convert_query("
			SELECT id_member, posts
			FROM {$to_prefix}members");
		$mg_updates = array();
		while ($row = $smcFunc['db_fetch_assoc']($request))
		{
			$group = 4;
			foreach ($post_groups as $min_posts => $group_id)
				if ($row['posts'] >= $min_posts)
				{
					$group = $group_id;
					break;
				}

			$mg_updates[$group][] = $row['id_member'];
		}
		$smcFunc['db_free_result']($request);

		foreach ($mg_updates as $group_to => $update_members)
			convert_query("
				UPDATE {$to_prefix}members
				SET id_post_group = $group_to
				WHERE id_member IN (" . implode(', ', $update_members) . ")
				LIMIT " . count($update_members));

		// This isn't completely related, but should be rather quick.
		convert_query("
			UPDATE {$to_prefix}members
			SET icq = ''
			WHERE icq = '0'");

		pastTime(5);
	}

	if ($_GET['substep'] <= 5)
	{
		if ($debug)
			print_line('Correct all board topics/post counts..');

		// Needs to be done separately for each board.
		$result_boards = convert_query("
			SELECT id_board
			FROM {$to_prefix}boards");
		$boards = array();
		while ($row_boards = $smcFunc['db_fetch_assoc']($result_boards))
			$boards[] = $row_boards['id_board'];
		$smcFunc['db_free_result']($result_boards);

		foreach ($boards as $id_board)
		{
			// Get the number of topics, and iterate through them.
			$result_topics = convert_query("
				SELECT COUNT(*)
				FROM {$to_prefix}topics
				WHERE id_board = $id_board");
			list ($num_topics) = $smcFunc['db_fetch_row']($result_topics);
			$smcFunc['db_free_result']($result_topics);

			// Find how many messages are in the board.
			$result_posts = convert_query("
				SELECT COUNT(*)
				FROM {$to_prefix}messages
				WHERE id_board = $id_board");
			list ($num_posts) = $smcFunc['db_fetch_row']($result_posts);
			$smcFunc['db_free_result']($result_posts);

			// Fix the board's totals.
			convert_query("
				UPDATE {$to_prefix}boards
				SET num_topics = $num_topics, num_posts = $num_posts
				WHERE id_board = $id_board
				LIMIT 1");
		}

		pastTime(6);
	}

	// Remove all topics that have zero messages in the messages table.
	if ($_GET['substep'] <= 6)
	{
		if ($debug)
			print_line('Removing any topics that have zero messages..');

		while (true)
		{
			$resultTopic = convert_query("
				SELECT t.id_topic, COUNT(m.id_msg) AS num_msg
				FROM {$to_prefix}topics AS t
					LEFT JOIN {$to_prefix}messages AS m ON (m.id_topic = t.id_topic)
				GROUP BY t.id_topic
				HAVING num_msg = 0
				LIMIT $_REQUEST[start], " . (!empty($convert_data['step2_block_size']) ? $convert_data['step2_block_size'] : 200));

			$numRows = $smcFunc['db_num_rows']($resultTopic);

			if ($numRows > 0)
			{
				$stupidTopics = array();
				while ($topicArray = $smcFunc['db_fetch_assoc']($resultTopic))
					$stupidTopics[] = $topicArray['id_topic'];
				convert_query("
					DELETE FROM {$to_prefix}topics
					WHERE id_topic IN (" . implode(',', $stupidTopics) . ')
					LIMIT ' . count($stupidTopics));
				convert_query("
					DELETE FROM {$to_prefix}log_topics
					WHERE id_topic IN (" . implode(',', $stupidTopics) . ')');
			}
			$smcFunc['db_free_result']($resultTopic);

			if ($numRows < 200)
				break;

			$_REQUEST['start'] += 200;
			pastTime(6);
		}

		$_REQUEST['start'] = 0;
		pastTime(7);
	}

	// Get the correct number of replies.
	if ($_GET['substep'] <= 7)
	{
		if ($debug)
			print_line('Correct the number of replies..');

		// Make sure we have the function "getMsgMemberID"
		require_once($sourcedir . '/Subs-Boards.php');

		while (true)
		{
			$resultTopic = convert_query("
				SELECT
					t.id_topic, MIN(m.id_msg) AS myid_first_msg, t.id_first_msg,
					MAX(m.id_msg) AS myid_last_msg, t.id_last_msg, COUNT(m.id_msg) - 1 AS my_num_replies,
					t.num_replies
				FROM {$to_prefix}topics AS t
					LEFT JOIN {$to_prefix}messages AS m ON (m.id_topic = t.id_topic)
				GROUP BY t.id_topic
				HAVING id_first_msg != myid_first_msg OR id_last_msg != myid_last_msg OR num_replies != my_num_replies
				LIMIT $_REQUEST[start], " . (!empty($convert_data['step2_block_size']) ? $convert_data['step2_block_size'] : 200));

			$numRows = $smcFunc['db_num_rows']($resultTopic);

			while ($topicArray = $smcFunc['db_fetch_assoc']($resultTopic))
			{
				$memberStartedID = getMsgMemberID($topicArray['myid_first_msg']);
				$memberUpdatedID = getMsgMemberID($topicArray['myid_last_msg']);

				convert_query("
					UPDATE IGNORE {$to_prefix}topics
					SET id_first_msg = '$topicArray[myid_first_msg]',
						id_member_started = '$memberStartedID', id_last_msg = '$topicArray[myid_last_msg]',
						id_member_updated = '$memberUpdatedID', num_replies = '$topicArray[my_num_replies]'
					WHERE id_topic = $topicArray[id_topic]
					LIMIT 1");
			}
			$smcFunc['db_free_result']($resultTopic);

			if ($numRows < 200)
				break;

			$_REQUEST['start'] += 100;
			pastTime(7);
		}

		$_REQUEST['start'] = 0;
		pastTime(8);
	}

	// Fix id_cat, id_parent, and child_level.
	if ($_GET['substep'] <= 8)
	{
		if ($debug)
			print_line('Fix the Categories and board layout..');

		// First, let's get an array of boards and parents.
		$request = convert_query("
			SELECT id_board, id_parent, id_cat
			FROM {$to_prefix}boards");
		$child_map = array();
		$cat_map = array();
		while ($row = $smcFunc['db_fetch_assoc']($request))
		{
			$child_map[$row['id_parent']][] = $row['id_board'];
			$cat_map[$row['id_board']] = $row['id_cat'];
		}
		$smcFunc['db_free_result']($request);

		// Let's look for any boards with obviously invalid parents...
		foreach ($child_map as $parent => $dummy)
		{
			if ($parent != 0 && !isset($cat_map[$parent]))
			{
				// Perhaps it was supposed to be their id_cat?
				foreach ($dummy as $board)
				{
					if (empty($cat_map[$board]))
						$cat_map[$board] = $parent;
				}

				$child_map[0] = array_merge(isset($child_map[0]) ? $child_map[0] : array(), $dummy);
				unset($child_map[$parent]);
			}
		}

		// The above id_parents and id_cats may all be wrong; we know id_parent = 0 is right.
		$solid_parents = array(array(0, 0));
		$fixed_boards = array();
		while (!empty($solid_parents))
		{
			list ($parent, $level) = array_pop($solid_parents);
			if (!isset($child_map[$parent]))
				continue;

			// Fix all of this board's children.
			foreach ($child_map[$parent] as $board)
			{
				if ($parent != 0)
					$cat_map[$board] = $cat_map[$parent];
				$fixed_boards[$board] = array($parent, $cat_map[$board], $level);
				$solid_parents[] = array($board, $level + 1);
			}
		}

		foreach ($fixed_boards as $board => $fix)
		{
			convert_query("
				UPDATE {$to_prefix}boards
				SET id_parent = " . (int) $fix[0] . ", id_cat = " . (int) $fix[1] . ", child_level = " . (int) $fix[2] . "
				WHERE id_board = " . (int) $board . "
				LIMIT 1");
		}

		// Leftovers should be brought to the root.  They had weird parents we couldn't find.
		if (count($fixed_boards) < count($cat_map))
		{
			convert_query("
				UPDATE {$to_prefix}boards
				SET child_level = 0, id_parent = 0" . (empty($fixed_boards) ? '' : "
				WHERE id_board NOT IN (" . implode(', ', array_keys($fixed_boards)) . ")"));
		}

		// Last check: any boards not in a good category?
		$request = convert_query("
			SELECT id_cat
			FROM {$to_prefix}categories");
		$real_cats = array();
		while ($row = $smcFunc['db_fetch_assoc']($request))
			$real_cats[] = $row['id_cat'];
		$smcFunc['db_free_result']($request);

		$fix_cats = array();
		foreach ($cat_map as $board => $cat)
		{
			if (!in_array($cat, $real_cats))
				$fix_cats[] = $cat;
		}

		if (!empty($fix_cats))
		{
			$smcFunc['db_insert']('insert',
				'{db_prefix}categories',
				array('name' => 'string',),
				array('General Category',),
				array('name')
				);
			$catch_cat = $smcFunc['db_insert_id']('{db_prefix}categories');

			convert_query("
				UPDATE {$to_prefix}boards
				SET id_cat = " . (int) $catch_cat . "
				WHERE id_cat IN (" . implode(', ', array_unique($fix_cats)) . ")");
		}

		pastTime(9);
	}

	if ($_GET['substep'] <= 9)
	{
		if ($debug)
			print_line('Correct category orders..');

		$request = convert_query("
			SELECT c.id_cat, c.cat_order, b.id_board, b.board_order
			FROM {$to_prefix}categories AS c
				LEFT JOIN {$to_prefix}boards AS b ON (b.id_cat = c.id_cat)
			ORDER BY c.cat_order, b.child_level, b.board_order, b.id_board");
		$cat_order = -1;
		$board_order = -1;
		$curCat = -1;
		while ($row = $smcFunc['db_fetch_assoc']($request))
		{
			if ($curCat != $row['id_cat'])
			{
				$curCat = $row['id_cat'];
				if (++$cat_order != $row['cat_order'])
					convert_query("
						UPDATE {$to_prefix}categories
						SET cat_order = $cat_order
						WHERE id_cat = $row[id_cat]
						LIMIT 1");
			}
			if (!empty($row['id_board']) && ++$board_order != $row['board_order'])
				convert_query("
					UPDATE {$to_prefix}boards
					SET board_order = $board_order
					WHERE id_board = $row[id_board]
					LIMIT 1");
		}
		$smcFunc['db_free_result']($request);

		pastTime(10);
	}

	if ($_GET['substep'] <= 10)
	{
		if ($debug)
			print_line('Force the board order..');

		// Update our BoardOrder
		require_once($sourcedir . '/Subs-Boards.php');
		reorderBoards();

		// Update our Smileys table.
		require_once($sourcedir . '/ManageSmileys.php');
		sortSmileyTable();

		pastTime(11);
	}

	if ($_GET['substep'] <= 11)
	{

		if ($debug)
			print_line('Correct any incorrect attachments..');

		$request = convert_query("
			SELECT COUNT(*)
			FROM {$to_prefix}attachments");
		list ($attachments) = $smcFunc['db_fetch_row']($request);
		$smcFunc['db_free_result']($request);

		while ($_REQUEST['start'] < $attachments)
		{
			$request = convert_query("
				SELECT id_attach, filename, attachment_type
				FROM {$to_prefix}attachments
				WHERE id_thumb = 0
					AND (RIGHT(filename, 4) IN ('.gif', '.jpg', '.png', '.bmp') OR RIGHT(filename, 5) = '.jpeg')
					AND width = 0
					AND height = 0
				LIMIT $_REQUEST[start], " . (!empty($convert_data['step2_block_size']) ? $convert_data['step2_block_size'] : 500));
			if ($smcFunc['db_num_rows']($request) == 0)
				break;
			while ($row = $smcFunc['db_fetch_assoc']($request))
			{
				if ($row['attachment_type'] == 1)
				{
					$request2 = convert_query("
						SELECT value
						FROM {$to_prefix}settings
						WHERE variable = 'custom_avatar_dir'
						LIMIT 1");
					list ($custom_avatar_dir) = $smcFunc['db_fetch_row']($request2);
					$smcFunc['db_free_result']($request2);

					$filename = $custom_avatar_dir . '/' . $row['filename'];
				}
				else
					$filename = getAttachmentFilename($row['filename'], $row['id_attach']);

				// Probably not one of the converted ones, then?
				if (!file_exists($filename))
					continue;

				$size = @getimagesize($filename);
				$filesize = @filesize($filename);
				if (!empty($size) && !empty($size[0]) && !empty($size[1]) && !empty($filesize))
					convert_query("
						UPDATE {$to_prefix}attachments
						SET
							size = " . (int) $filesize . ",
							width = " . (int) $size[0] . ",
							height = " . (int) $size[1] . "
						WHERE id_attach = $row[id_attach]
						LIMIT 1");
			}
			$smcFunc['db_free_result']($request);

			// More?
			// We can't keep converting the same files over and over again!
			$_REQUEST['start'] += 500;
			pastTime(11);
		}

		$_REQUEST['start'] = 0;
		pastTime(12);
	}

	// Lets rebuild the indexes.
	if ($_GET['substep'] <= 12)
	{
		if ($debug)
			print_line('rebuilding indexes for topics..');
		db_extend('packages');

		$indexes = $smcFunc['db_list_indexes']($to_prefix . 'topics', true, array('no_prefix' => true));

		if (!isset($indexes['PRIMARY']))
			$smcFunc['db_add_index']($to_prefix . 'topics', array(
				'type' => 'PRIMARY',
				'columns' => array('id_topic')),
				array('no_prefix' => true));
		if (!isset($indexes['last_message']))
			$smcFunc['db_add_index']($to_prefix . 'topics', array(
				'type' => 'UNIQUE',
				'name' => 'last_message',
				'columns' => array('id_last_msg', 'id_board')),
				array('no_prefix' => true));
		if (!isset($indexes['first_message']))
			$smcFunc['db_add_index']($to_prefix . 'topics', array(
				'type' => 'UNIQUE',
				'name' => 'first_message',
				'columns' => array('id_first_msg', 'id_board')),
				array('no_prefix' => true));
		if (!isset($indexes['poll']))
			$smcFunc['db_add_index']($to_prefix . 'topics', array(
				'type' => 'UNIQUE',
				'name' => 'poll',
				'columns' => array('id_poll', 'id_topic')),
				array('no_prefix' => true));
		if (!isset($indexes['is_sticky']))
			$smcFunc['db_add_index']($to_prefix . 'topics', array(
				'type' => 'INDEX', // no key
				'name' => 'is_sticky',
				'columns' => array('is_sticky')),
				array('no_prefix' => true));
		if (!isset($indexes['id_board']))
			$smcFunc['db_add_index']($to_prefix . 'topics', array(
				'type' => 'INDEX', // no key
				'name' => 'id_board',
				'columns' => array('id_board')),
				array('no_prefix' => true));

		$_REQUEST['start'] = 0;
		pastTime(13);
	}

	if ($_GET['substep'] <= 13)
	{
		if ($debug)
			print_line('rebuilding indexes for messages..');
		db_extend('packages');

		$indexes = $smcFunc['db_list_indexes']($to_prefix . 'messages', true, array('no_prefix' => true));

		if (!isset($indexes['PRIMARY']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'PRIMARY',
				'columns' => array('id_msg')),
				array('no_prefix' => true));
		if (!isset($indexes['topic']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'UNIQUE',
				'name' => 'topic',
				'columns' => array('id_topic', 'id_msg')),
				array('no_prefix' => true));
		if (!isset($indexes['id_board']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'UNIQUE',
				'name' => 'id_board',
				'columns' => array('id_board', 'id_msg')),
				array('no_prefix' => true));
		if (!isset($indexes['id_member']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'UNIQUE',
				'name' => 'id_member',
				'columns' => array('id_member', 'id_msg')),
				array('no_prefix' => true));
		if (!isset($indexes['ip_index']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'INDEX', // no key
				'name' => 'ip_index',
				'columns' => array('poster_ip(15)', 'id_topic')),
				array('no_prefix' => true));
		if (!isset($indexes['participation']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'INDEX', // no key
				'name' => 'participation',
				'columns' => array('id_member', 'id_topic')),
				array('no_prefix' => true));
		if (!isset($indexes['show_posts']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'INDEX', // no key
				'name' => 'show_posts',
				'columns' => array('id_member', 'id_member')),
				array('no_prefix' => true));
		if (!isset($indexes['id_topic']))
			$smcFunc['db_add_index']($to_prefix . 'messages', array(
				'type' => 'INDEX', // no key
				'name' => 'id_topic',
				'columns' => array('id_topic')),
				array('no_prefix' => true));

		$_REQUEST['start'] = 0;
		pastTime(14);
	}

	print_line(' Successful.');

	return doStep3();
}

// This isn't a step, its the finish line.
function doStep3()
{
	global $boardurl, $convert_data, $command_line, $current_step;

	// Replace the conversion information.
	convert_insert('settings',
		array('variable', 'value'),
		array(
			array('conversion_time', time()),
			array('conversion_from', $_SESSION['convert_script']),
			array('enable_password_conversion', 1)
		),'replace');

	$current_step = 3;
	if ($command_line)
	{
		print_line('Conversion Complete!');
		print_line('Please delete this file as soon as possible for security reasons.');
		return true;
	}

	echo '
				<h2 style="margin-top: 2ex;">Conversion Complete</h2>
				<h3>Congratulations, the conversion has completed successfully.  If you have or had any problems with this converter, or need help using SMF, please feel free to <a href="http://www.simplemachines.org/community/index.php">look to us for support</a>.</h3>';

	if (is_writable(dirname(__FILE__)) && is_writable(__FILE__))
		echo '
				<div style="margin: 1ex; font-weight: bold;">
					<label for="delete_self"><input type="checkbox" id="delete_self" onclick="doTheDelete();" class="input_check" /> Please check this box to delete the converter right now for security reasons.</label> (doesn\'t work on all servers.)
				</div>
				<script type="text/javascript"><!-- // --><![CDATA[
					function doTheDelete()
					{
						var theCheck = document.getElementById ? document.getElementById("delete_self") : document.all.delete_self;
						var tempImage = new Image();

						tempImage.src = "', $_SERVER['PHP_SELF'], '?delete=1&" + (new Date().getTime());
						tempImage.width = 0;
						theCheck.disabled = true;
					}
				// ]]></script>
				<br />';
	echo '
				Now that everything is converted over, <a href="', $boardurl, '/index.php">your SMF installation</a> should have all the posts, boards, and members from the ', $convert_data['name'], ' installation.<br />
				<br />
				We hope you had a smooth transition!';

	return true;
}

function template_convert_above()
{
	global $convert_data, $time_start, $current_step, $last_step;

	$time_start = time();
	$smfsite = 'https://simplemachines.org/smf';

	$current_action = '';
	$mainsteps = findSteps();

	if (empty($current_step))
	{
		if ((empty($_SESSION['convert_script']) || empty($_REQUEST['convert_script'])) && !empty($convert_data))
			$current_step = 0;
		elseif (empty($_GET['step']))
			$current_step = 1;
		elseif (!empty($_GET['step']))
			$current_step = $_GET['step'] + 1;
	}
	else
		$current_step += 1;

	if (isset($_REQUEST['substep']))
		$current_substep = $_REQUEST['substep'];
	else
		$current_substep = 0;

	$steps = array(
		0 => 'Select Script',
		1 => 'Welcome',
		2 => 'Main Conversion',
		3 => 'Recount Totals and Statistics',
		4 => 'Done',
	);

	echo '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
	<head>
<meta http-equiv="content-type" content="text/html; charset=UTF-8">
		<title>', isset($convert_data['name']) ? $convert_data['name'] . ' to ' : '', 'SMF Converter</title>
		<script type="text/javascript" src="Themes/default/scripts/script.js"></script>
		<link rel="stylesheet" type="text/css" href="', $smfsite, '/style.css" />
	</head>
	<body>
		<div id="header">
			<div title="Bahamut!">', isset($convert_data['name']) ? $convert_data['name'] . ' to ' : '', 'SMF Converter</div>
		</div>
		<div id="content">
			<table width="100%" border="0" cellpadding="0" cellspacing="0" style="padding-top: 1ex;">
			<tr>
				<td width="250" valign="top" style="padding-right: 10px;">
					<table border="0" cellpadding="8" cellspacing="0" class="tborder" width="240">
						<tr>
							<td class="titlebg">Steps</td>
						</tr>
						<tr>
							<td class="windowbg2">';

	// Loop through each step.
	foreach ($steps as $num => $step)
	{
		echo '
						<span class="', $num < $current_step ? 'stepdone' : ($num == $current_step ? 'stepcurrent' : 'stepwaiting'), '">', $step, '</span><br />';

		// Do we have information about step 2?
		if ($num == 2 /*&& isset($_REQUEST['convert_script'])*/)
		{
			foreach ($mainsteps as $substep)
				echo '
						<span class="', $current_step > 2 ? 'stepdone' : ($current_step == 2 ? 'stepcurrent' : 'stepwaiting'), '">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- ', ucfirst(trim(str_replace('Converting ', '', $substep['name']))), '</span><br />';
		}
	}
// Menus

	echo '
							</td>
						</tr>';

/*
	// Not ready yet. For the Future.
	echo '
						<tr>
							<td class="titlebg">Progress</td>
						</tr>
						<tr>
							<td class="windowbg2">
								<div style="font-size: 8pt; height: 12pt; border: 1px solid black; background-color: white; position: relative;">
									<div id="overall_text" style="padding-top: 1pt; width: 100%; z-index: 2; color: black; position: absolute; text-align: center; font-weight: bold;">', $incontext['overall_percent'], '%</div>
									<div id="overall_progress" style="width: ', $incontext['overall_percent'], '%; height: 12pt; z-index: 1; background-color: lime;">&nbsp;</div>
								</div>
							</td>
						</tr>';
*/

	echo '
					</table>
				</td>
				<td width="100%" valign="top">';
}

// Show the footer.
function template_convert_below()
{
	echo '
				</td>
			</tr>
		</table>
		</div>
	</body>
</html>';
}

// Check if we've passed the time limit..
function pastTime($substep = null, $force = false)
{
	global $time_start, $command_line;

	if (isset($_GET['substep']) && $_GET['substep'] < $substep)
		$_GET['substep'] = $substep;

	if ($command_line)
	{
		if (time() - $time_start > 1)
		{
			print_line('.');
			$time_start = time();
		}
		return;
	}

	@set_time_limit(300);
	if (function_exists('apache_reset_timeout'))
		@apache_reset_timeout();

	if (time() - $time_start < 10 && !$force)
		return;

	echo '
			<em>Incomplete.</em><br />

			<h2 style="margin-top: 2ex;">Not quite done yet!</h2>
			<h3>
				This conversion has paused to avoid overloading your server, and hence not working properly.<br />
				Don\'t worry though, <strong>nothing\'s wrong</strong> - simply click the <label for="continue">continue button</label> below to start the converter from where it left off.
			</h3>

			<form action="', $_SERVER['PHP_SELF'], '?step=', $_GET['step'], isset($_GET['substep']) ? '&amp;substep=' . $_GET['substep'] : '', isset($_GET['cstep']) ? '&amp;cstep=' . $_GET['cstep'] : '', '&amp;start=', $_REQUEST['start'], '" method="post" name="autoSubmit">
				<div class="righttext" style="margin: 1ex;"><input name="b" type="submit" value="Continue" class="button_submit" /></div>
			</form>
			<script type="text/javascript"><!-- // --><![CDATA[
				window.onload = doAutoSubmit;
				var countdown = 3;

				function doAutoSubmit()
				{
					if (countdown == 0)
						document.autoSubmit.submit();
					else if (countdown == -1)
						return;

					document.autoSubmit.b.value = "Continue (" + countdown + ")";
					countdown--;

					setTimeout("doAutoSubmit();", 1000);
				}
			// ]]></script>';

	template_convert_below();
	exit;
}

function removeAllAttachments()
{
	global $to_prefix, $smcFunc;

	$result = convert_query("
		SELECT value
		FROM {$to_prefix}settings
		WHERE variable = 'attachmentUploadDir'
		LIMIT 1");
	list ($attachmentUploadDir) = $smcFunc['db_fetch_row']($result);
	$smcFunc['db_free_result']($result);

	// !!! This should probably be done in chunks too.
	$result = convert_query("
		SELECT id_attach, filename
		FROM {$to_prefix}attachments");
	while ($row = $smcFunc['db_fetch_assoc']($result))
	{
		$filename = $row['filename'];
		$id_attach = $row['id_attach'];
		$physical_filename = getAttachmentFilename($filename, $id_attach);

		if (file_exists($physical_filename))
			@unlink($physical_filename);
	}
	$smcFunc['db_free_result']($result);
}

// Add slashes recursively...
function addslashes_recursive($var)
{
	if (!is_array($var))
		return addslashes($var);
	else
	{
		foreach ($var as $k => $v)
			$var[$k] = addslashes_recursive($v);
		return $var;
	}
}

if (!function_exists('un_htmlspecialchars'))
{
	// Removes special entities from strings.  Compatibility...
	function un_htmlspecialchars($string)
	{
		return strtr($string, array_flip(get_html_translation_table(HTML_SPECIALCHARS, ENT_QUOTES)) + array('&#039;' => '\'', '&nbsp;' => ' '));
	}
}

// Remove slashes recursively...
function convert_stripslashes_recursive($var, $level = 0)
{
	if (!is_array($var))
		return stripslashes($var);

	// Reindex the array without slashes, this time.
	$new_var = array();

	// Strip the slashes from every element.
	foreach ($var as $k => $v)
		$new_var[stripslashes($k)] = $level > 25 ? null : convert_stripslashes_recursive($v, $level + 1);

	return $new_var;
}

// The main convert function that does all the big daddy work.
function convert_query($string, $return_error = false)
{
	global $convert_dbs, $to_prefix, $command_line, $smcFunc, $db_connection;

	// Debugging?
	if (isset($_REQUEST['debug']))
		$_SESSION['convert_debug'] = !empty($_REQUEST['debug']);

	if (trim($string) == 'TRUNCATE ' . $GLOBALS['to_prefix'] . 'attachments')
		removeAllAttachments();

	if ($convert_dbs != 'smf_db')
	{
		$clean = '';
		$old_pos = 0;
		$pos = -1;
		while (true)
		{
			$pos = strpos($string, '\'', $pos + 1);
			if ($pos === false)
				break;
			$clean .= substr($string, $old_pos, $pos - $old_pos);

			while (true)
			{
				$pos1 = strpos($string, '\'', $pos + 1);
				$pos2 = strpos($string, '\\', $pos + 1);
				if ($pos1 === false)
					break;
				elseif ($pos2 == false || $pos2 > $pos1)
				{
					$pos = $pos1;
					break;
				}

				$pos = $pos2 + 1;
			}
			$clean .= '%s';

			$old_pos = $pos + 1;
		}
		$clean .= substr($string, $old_pos);
		$clean = trim(preg_replace('~\s+~s', ' ', $clean));

		if (strpos($string, $to_prefix) === false)
		{
			preg_match('~limit (\d+)(?:, (\d+))?\s*$~is', $string, $limit);
			if (!empty($limit))
			{
				$string = preg_replace('~limit (\d+)(?:, (\d+))?$~is', '', $string);
				if (!isset($limit[2]))
				{
					$limit[2] = $limit[1];
					$limit[1] = 0;
				}
			}

			if ($convert_dbs == 'odbc')
			{
				if (!empty($limit))
					$string = preg_replace('~^\s*select~is', 'SELECT TOP ' . ($limit[1] + $limit[2]), $string);

				$result = @odbc_exec($GLOBALS['odbc_connection'], $string);

				if (!empty($limit) && !empty($limit[1]))
					odbc_fetch_row($result, $limit[1]);
			}
			elseif ($convert_dbs == 'ado')
			{
				if (!empty($limit))
					$string = preg_replace('~^\s*select~is', 'SELECT TOP ' . ($limit[1] + $limit[2]), $string);

				if (PHP_VERSION >= 5)
					eval('
						try
						{
							$result = $GLOBALS[\'ado_connection\']->Execute($string);
						}
						catch (com_exception $err)
						{
							$result = false;
						}');
				else
					$result = @$GLOBALS['ado_connection']->Execute($string);

				if ($result !== false && !empty($limit) && !empty($limit[1]))
					$result->Move($limit[1], 1);
			}
			$not_smf_dbs = true;
		}
		else
			$result = $smcFunc['db_query']('', $string,
				array(
					'overide_security' => true,
					'db_error_skip' => true,
			));
	}
	else
		$result = $smcFunc['db_query']('', $string,
			array(
				'overide_security' => true,
				'db_error_skip' => true,
			)
		);

	if ($result !== false || $return_error)
		return $result;

	if (empty($not_smf_dbs))
	{

		$db_error = $smcFunc['db_error']($db_connection);
		$db_errno = $smcFunc['db_title'] == 'MySQL' ? (function_exists('mysqli_errno') ? mysqli_errno($db_connection) : mysql_errno($db_connection)) : ($smcFunc['db_title'] == 'SQLite' ? sqlite_last_error() : ($smcFunc['db_title'] == 'PostgreSQL' ? pg_last_error() : $smcFunc['db_error']($db_connection)));

		// FIrst log it.
		// In the future this may return the actual file it came from.
		if (isset($_GET['debug']) || isset($_POST['debug']))
			convert_error_handler($db_error, $string, 'Converter File', $db_errno, array(), true);

		// Error numbers:
		//    1016: Can't open file '....MYI'
		//    2013: Lost connection to server during query.

		if (trim($db_errno) == 1016)
		{
			if (preg_match('~(?:\'([^\.\']+)~', $db_error, $match) != 0 && !empty($match[1]))
				$smcFunc['db_query']('', "
					REPAIR TABLE $match[1]", 'security_override');

			$result = $smcFunc['db_query']('', $string, 'security_override');

			if ($result !== false)
				return $result;
		}
		elseif (trim($db_errno) == 2013)
		{
			$result = $smcFunc['db_query']('', $string, 'security_override');

			if ($result !== false)
				return $result;
		}

		// Attempt to allow big selects, only for mysql so far though.
		if ($smcFunc['db_title'] == 'MySQL' && (trim($db_errno) == 1104 || strpos($db_error, 'use SET SQL_BIG_SELECTS=1') !== false))
		{
			$mysql_version = $smcFunc['db_server_info']($db_connection);

			// Fix MySQL 5.6 variable name change
			$max_join_var_name = 'SQL_MAX_JOIN_SIZE';

			$mysql_version = $smcFunc['db_server_info']($db_connection);

			if (stripos($mysql_version,"MariaDB") > 0 ||  version_compare($mysql_version, '5.6.0') >= 0)
				$max_join_var_name = 'max_join_size';

			$results = $smcFunc['db_query']('', "SELECT @@SQL_BIG_SELECTS, @$max_join_var_name", 'security_override');
			list($big_selects, $sql_max_join) = $smcFunc['db_fetch_row']($results);

			// Only waste a query if its worth it.
			if (empty($big_selects) || ($big_selects != 1 && $big_selects != '1'))
				$smcFunc['db_query']('', "SET @@SQL_BIG_SELECTS = 1", 'security_override');

			// Lets set MAX_JOIN_SIZE to something we should
			if (empty($sql_max_join) || ($sql_max_join == '18446744073709551615' && $sql_max_join == '18446744073709551615'))
				$smcFunc['db_query']('', "SET @@$max_join_var_name = 18446744073709551615", 'security_override');

			// Try again.
			$result = $smcFunc['db_query']('', $string, 'security_override');

			if ($result !== false)
				return $result;
		}
	}
	elseif ($convert_dbs == 'odbc')
		$db_error = odbc_errormsg($GLOBALS['odbc_connection']);
	elseif ($convert_dbs == 'ado')
	{
		$error = $GLOBALS['ado_connection']->Errors[0];
		$db_error = $error->Description;
	}

	// Get the query string so we pass everything.
	if (isset($_REQUEST['start']))
		$_GET['start'] = $_REQUEST['start'];
	$query_string = '';
	foreach ($_GET as $k => $v)
		$query_string .= '&' . $k . '=' . $v;
	if (strlen($query_string) != 0)
		$query_string = '?' . strtr(substr($query_string, 1), array('&' => '&amp;'));

	if ($command_line)
	{
		print_line("Unsuccessful! Database error message:\n" . $db_error);
		die;
	}

	echo '
			<strong>Unsuccessful!</strong><br />

			This query:<blockquote>' . nl2br(htmlspecialchars(trim($string))) . ';</blockquote>

			Caused the error:<br />
			<blockquote>' . nl2br(htmlspecialchars($db_error)) . '</blockquote>

			<form action="', $_SERVER['PHP_SELF'], $query_string, '" method="post">
				<input type="submit" value="Try again" class="button_submit" />
			</form>
		</div>';

	template_convert_below();
	die;
}

// Inserting stuff?
function convert_insert($table, $columns, $block, $type = 'insert', $no_prefix = false)
{
	global $smcFunc, $db_prefix;

	// Unless I say, we are using a prefix.
	if (empty($no_prefix))
		$table = $db_prefix . $table;

	// Correct the type. We used this as it was easier to understand its meaning.
	if ($type == 'insert ignore')
		$type = 'ignore';

	$keys = $columns;
	$columns = array();
	$temp = array();

	// Loop through the info.
	$column_info = $smcFunc['db_list_columns']($table, true, array('no_prefix' => true));
	foreach ($column_info as $col)
		// Only get the useful ones.
		if (in_array($col['name'], $keys))
		{
			if (in_array($col['type'], array('float', 'string', 'int', 'date')))
				$data_type = $col['type'];
			elseif (in_array($col['type'], array('tinyint', 'smallint', 'mediumint', 'bigint')))
				$data_type = 'int';
			else
				$data_type = 'string';
			$temp[$col['name']] = $data_type;
		}

	// Loop through each key and put it back hopefully in the same order.
	foreach ($keys as $col)
	{
		if (isset($temp[$col]))
			$columns[$col] = $temp[$col];
		else
		{
			if (strpos('id', $col) || strpos('min', $col) || strpos('date', $col))
				$data_type = 'int';
			else
				$data_type = 'string';

			$columns[$col] = $data_type;
		}
	}

	return $smcFunc['db_insert']($type, $table, $columns, $block, array());
}

// Provide a easy way to give our converters an insert id.
function convert_insert_id($table, $no_prefix = false)
{
	global $smcFunc, $db_prefix;

	if (empty($no_prefix))
		$table = $db_prefix . $table;
	return $smcFunc['db_insert_id']($table);
}

// Provide a way to find the affected rows.
function convert_affected_rows()
{
	global $smcFunc;

	return	$smcFunc['db_affected_rows']();
}

// Provide a way to do results with offsets
function convert_result($request, $offset = 0, $field_name = '')
{
	global $smcFunc;

	// SQlite is a pain, This should hopefully work.
	if ($smcFunc['db_title'] == 'SQLite')
	{
		// Perform the query.
		$result = $smcFunc['db_query']('', $request, 'security_override');

		// Now loop throuh it with an array (for ease of use for field_name).
		$t = 0;
		while ($row = sqlite_fetch_array($result))
		{
			// If its not our offset, Add, and get on with it.
			if ($t != $offset)
			{
				++$t;
				continue;
			}

			// We want to be that lazy.. Um I mean, Specific?
			if ($field_name != '')
				return $row[$field_name];
			else
				return $row[0];
		}
	}
	// Luckily Postgresql is with it.
	elseif ($smcFunc['db_title'] == 'PostgreSQL')
		return pg_fetch_result($request, $offset, $field_name);
	else
	{
		if (function_exists("mysqli_connect"))
			return convert_mysqli_result($request, $offset, $field_name);
		else
			return mysql_result($request, $offset, $field_name);
	}

}

function convert_mysqli_result($request, $offset,  $field_name)
{
    $request->data_seek($offset);

    $row = $request->fetch_array();

	return $row[$field_name];
}

function convert_free_result($result)
{
	global $smcFunc;

		return $smcFunc['db_free_result']($result);
}

function convert_fetch_assoc($result)
{
	global $smcFunc;

		return $smcFunc['db_fetch_assoc']($result);
}

function convert_fetch_row($result)
{
	global $smcFunc;

		return $smcFunc['db_fetch_row']($result);
}

function convert_num_rows($result)
{
	global $smcFunc;

		return $smcFunc['db_num_rows']($result);
}

// This is the new function similar to alterTable
// The main purpose of this function is provide a simple way to edit anything in the database with a local method of doing so.
function alterDatabase($table, $type, $parms, $no_prefix = false)
{
	global $smcFunc, $db_prefix;

	// We need packages.
	db_extend('packages');

	$extra_parms = array();
	// Not needing a prefix?
	if (empty($no_prefix))
	{
		// RC2 compatibility: table name needs a prefix, be it already in the name, or sent as placeholder.
		// We can add the actual prefix ourselves and that's that: it should work on RC1.2 as well
		$table = $db_prefix . $table;
	}
	$extra_parms['no_prefix'] = true;

	// Are we adding a column
	if ($type == 'add column')
		$smcFunc['db_add_column']($table, $parms, $extra_parms);
	elseif ($type == 'remove column')
		$smcFunc['db_remove_column']($table, $parms, $extra_parms);
	elseif ($type == 'change column')
	{
		// Remove the old_name column just incase it confuses SMF.
		$temp_column_name = $parms['old_name'];
		unset($parms['old_name']);

		$smcFunc['db_change_column']($table, $temp_column_name, $parms, $extra_parms);
	}
	elseif ($type == 'add index' || $type == 'add key')
		$smcFunc['db_add_index']($table, $parms, $extra_parms);
	elseif ($type == 'remove index' || $type == 'remove key')
	{
		// Attemp it for 2.0 and hope for the best!
		$smcFunc['db_remove_index']($table, $parms, $extra_parms);

		// Since SMF 1.1 used camel case in its ids. Lets try to detect that.
		// Best we can do is only do this for mysql users. Sorry mates.
		if ($smcFunc['db_title'] == 'MySQL' && $parms != strtolower($parms) && strtolower(substr($parms, 0, 2)) != 'id')
		{
			$count = count($parms);
			$i = 0;
			for ($i = 0; $i < $count; $i++)
			{
				if ($parms[$i] == '_')
					break;
			}
			$new_string = strtoupper($parms[($i + 1)]);
			$parms = substr($new_string, 0, $i) . substr($new_string, $i + 1);

			$smcFunc['db_remove_index']($table, $parms, $extra_parms);
		}
		// Its an id column, which is easier.
		elseif ($smcFunc['db_title'] == 'MySQL' && $parms != strtolower($parms) && strtolower(substr($parms, 0, 2)) == 'id')
			$smcFunc['db_remove_index']($table, strtolower($parms), $extra_parms);
	}
	else
		print_error('Unknown type called in alterDatabase.' . var_dump(function_exists('debug_backtrace') ? debug_backtrace() : 'Unable to backtrace'));
}

// This function is depcreated, but we will provide it for legacy reasons for now.
function alterTable($tableName, $knownKeys = '', $knownColumns = '', $alterColumns = '', $reverseKeys = false, $reverseColumns = false)
{
	global $smcFunc, $to_prefix;

	// Ok, you old scripts. Get off it!
	print_error('alterTable is deprecated in convert.php. Please consider using proper \$smcFuncs.' . var_dump(function_exists('debug_backtrace') ? debug_backtrace() : 'Unable to backtrace'));

	// Shorten this up
	$to_table = $to_prefix . $tableName;

	// Get Packing!
	db_extend('packages');

	// Get the keys
	if (!empty($knownKeys))
		$availableKeys = array_flip($smcFunc['db_list_indexes']());
	else
		$knownKeys = array();

	// Are we dealing with columns also?
	if (!empty($knownColumns))
		$availableColumns = array_flip($smcFunc['db_list_columns']("$tableName", true));
	else
		$knownColumns = array();

	// Column to alter
	if (!empty($alterColumns) && is_array($alterColumns))
		$alterColumns = $alterColumns;
	else
		$alterColumns = array();

	// Check indexes
	foreach ($knownKeys as $key => $value)
	{
		// If we are dropping keys then it should unset the known keys if it's NOT available
		if ($reverseKeys == false && !in_array($key, $availableKeys))
			unset($knownKeys[$key], $knownKeys[$key]);
		// Since we are in reverse and we are adding then unknown the known keys that are available
		elseif ($reverseKeys == true && in_array($key, $availableKeys))
			unset($knownKeys[$key], $knownKeys[$key]);
	}

	// Check columns
	foreach ($knownColumns as $column => $value)
	{
		// Here we reverse things.  If the column is not in then we must add it.
		if ($reverseColumns == false && in_array($column, $availableColumns))
			unset($knownColumns[$column], $knownColumns[$column]);
		// If it's in then we must unset it.
		elseif ($reverseColumns == true && !in_array($column, $availableColumns))
			unset($knownColumns[$column], $knownColumns[$column]);
	}

	// Now merge the three
	$alter = array_merge($alterColumns, $knownKeys, $knownColumns);

	// Now lets see what we want to do with them
	$clause = '';
	foreach ($alter as $key)
		$clause .= "
		$key,";

	// Lets do some altering
	convert_query("
		ALTER TABLE $to_table" .
		substr($clause, 0, -1));
}

function copy_smileys($source, $dest)
{
	if (!is_dir($source) || !($dir = opendir($source)))
		return;

	while ($file = readdir($dir))
	{
		if ($file == '.' || $file == '..')
			continue;

		// If we have a directory create it on the destination and copy contents into it!
		if (is_dir($source . '/' . $file))
		{
			if (!is_dir($dest))
				@mkdir($dest . '/' . $file, 0777);
			copy_dir($source . '/' . $file, $dest . '/' . $file);
		}
		else
		{
			if (!is_dir($dest))
				@mkdir($dest . '/' . $file, 0777);
			copy($source . '/' . $file, $dest . '/' . $file);
		}
	}
	closedir($dir);
}

function copy_dir($source, $dest)
{
	if (!is_dir($source) || !($dir = opendir($source)))
		return;

	while ($file = readdir($dir))
	{
		if ($file == '.' || $file == '..')
			continue;

		// If we have a directory create it on the destination and copy contents into it!
		if (is_dir($source . '/' . $file))
		{
			if (!is_dir($dest))
				@mkdir($dest, 0777);
			copy_dir($source . '/' . $file, $dest . '/' . $file);
		}
		else
		{
			if (!is_dir($dest))
				@mkdir($dest, 0777);
			copy($source . '/' . $file, $dest . '/' . $file);
		}
	}
	closedir($dir);
}

// Convert a percent toa pixel. Thanks Elberet.
function convert_percent_to_px($percent)
{
	return intval(11*(intval($percent)/100.0));
}

// CLI
function cmdStep0()
{
	global $time_start;
	$time_start = time();

	@ob_end_clean();
	ob_implicit_flush(true);
	@set_time_limit(600);

	if (!isset($_SERVER['argv']))
		$_SERVER['argv'] = array();

	// If its empty, force help.
	if (empty($_SERVER['argv'][1]))
		$_SERVER['argv'][1] = '--help';

	// Lets get the path_to and path_from
	foreach ($_SERVER['argv'] as $i => $arg)
	{
		// Trim spaces.
		$arg = trim($arg);

		if (preg_match('~^--path_to=(.+)$~', $arg, $match) != 0)
			$_POST['path_to'] = substr($match[1], -1) == '/' ? substr($match[1], 0, -1) : $match[1];
		elseif (preg_match('~^--path_from=(.+)$~', $arg, $match) != 0)
			$_POST['path_from'] = substr($match[1], -1) == '/' ? substr($match[1], 0, -1) : $match[1];
		elseif (preg_match('~^--db_pass=(.+)?$~', $arg, $match) != 0)
			$_POST['db_pass'] = isset($match[1]) ? $match[1] : '';
		elseif ($arg == '--debug')
			$_GET['debug'] = 1;
		elseif (preg_match('~^--convert_script=(.+)$~', $arg, $match) != 0)
			$_REQUEST['convert_script'] = $match[1];
		elseif ($arg == '--help' || $i = 0)
		{
			print_error('SMF Command-line Converter
Usage: /path/to/php -f ' . basename(__FILE__) . ' -- [OPTION]...

    --path_to               Path to SMF (' . dirname(__FILE__) . ').
    --path_from             Path to the software that you are converting from.
    --convert_script        The name of the script. (old_forum_to_smf.sql)
    --db_pass               SMF database password. "The Database password (for verification only.)"
    --debug                 Output debugging information.', true);
		}

		// We have extra params.
		if (preg_match('~^--(.+)=(.+)$~', $arg, $match) != 0 && !array_key_exists($match[1], $_POST))
			$_POST[$match[1]] = $match[2];
	}

	// Do we have the paths and passwords?
	if (!isset($_POST['path_to']))
		print_error('ERROR: You must enter the path_to in order to convert.', true);
	elseif (!isset($_POST['path_from']))
		print_error('ERROR: You must enter the path_from in order to convert.', true);
	elseif (!isset($_POST['db_pass']))
		print_error('ERROR: You must enter SMF\'s database password in order to convert.', true);
	else
	{
		$_GET['step'] = 1;
		initialize_inputs();
		doStep1();
	}

	exit;
}

// We got an error.
function print_error($message, $fatal = false, $add_ending = false)
{
	global $command_line;
	static $fp = null;

	// Incase the message had html, lets strip it.
	if ($command_line)
		$message = preg_replace('~<([A-Z][A-Z0-9]*)\b[^>]*>(.*?)</\1>~i', '$2', $message);

	if ($fp === null)
		$fp = fopen('php://stderr', 'wb');

	fwrite($fp, $message);

	if ($command_line)
		fwrite($fp, $add_ending ? "\n" : '');
	else
		fwrite($fp, $add_ending ? '<br />' . "\n" : '');

	if ($fatal)
		exit;
}

// Print stuff. Let This handle our line endings.
function print_line($line, $return = true)
{
	global $command_line;

	// Support for multiple arguments.
	if ($command_line)
		print_error($line . ($return ? "\n" : ''), false, true);
	else
		echo $line . ($return ? '<br />' . "\n" : '');
}

// Handles our errors.
function convert_error_handler($error_level, $error_string, $file, $line, $errorContext = array(), $is_database_error = false)
{
	global $command_line;

	// Our error_log
	$convert_error_log = dirname(__FILE__) . '/convert_error_log';

	// Is it Database Specific?
	if (!empty($is_database_error))
	{
		/*
			Note, Unlike php this is slightly different.
			error_level = errror from database
			error_string = original query
		*/

		// The array is easier than using \r as well makes it easier for command line.
		$error_array = array(
			'',
			"The database encountered an error on line (from query), " . $line . ".", // . ", from file, " . $file . ".";
			"The error received was:",
			"---",
			$error_level,
			"---",
			"The query ran was:",
			"---",
			$error_string,
			"---",
		);
	}
	else
	{
		// Generate a simple error message familer to PHP errors, expect we do them one better.
		$error_array = array(
			'',
			$error_level % 255 == E_ERROR ? 'Error' : ($error_level % 255 == E_WARNING ? 'Warning' : 'Notice') . ': ' . $error_string . ' in ' . $file . ' on line ' . $line,
			"Backtrace report",
			"---"
		);

		// Lets leave a paper trail.
		$backtrace = debug_backtrace();

		// Now loop through our backtrace for output.
		foreach ($backtrace as $trail)
		{
			foreach ($trail as $key => $value)
			{
				if (!is_array($value))
					$error_array[] = "\t " . $key . " (key): " . $value;
				else
				{
					$error_array[] = "\t" . $key . " (key): ";

					foreach ($value as $vkey => $vvalue)
						$error_array[] = "\t\t" . $vkey . " (key): " . $vvalue;
				}
			}

			// Add an extra return.
			$error_array[] = "";
		}
	}

	// Open the file up for writing (with pointer at end).
	$fp = fopen($convert_error_log, 'a+');

	// Can't open it!
	if (!$fp)
		$no_write_file = true;

	// Send it out to the error log. Only if we can though.
	if (empty($no_write_file))
	{
		// The world implodes!
		$error_data = implode("\r", $error_array);

		fwrite($fp, $error_data);
		fclose($fp);
	}

	// Based on if we are command line or not, this will handle things for us.
	if ($command_line && !$is_database_error)
		print_error($error_data[1]);
	// If its not command lind and not a database error, echo the error info (without backtrack).
	elseif (!$is_database_error)
		echo $error_array[1];
}

// This was not read anyway when needed, but it seems updateSettings does the job now.
// Leaving it here just in case.
if (!function_exists('updateSettingsFile'))
{
	// Update the Settings.php file.
	function updateSettingsFile($config_vars)
	{
		// Load the file.
		$settingsArray = file($_POST['path_to'] . '/Settings.php');

		if (count($settingsArray) == 1)
			$settingsArray = preg_split('~[\r\n]~', $settingsArray[0]);

		for ($i = 0, $n = count($settingsArray); $i < $n; $i++)
		{
			// Don't trim or bother with it if it's not a variable.
			if (substr($settingsArray[$i], 0, 1) != '$')
				continue;

			$settingsArray[$i] = trim($settingsArray[$i]) . "\n";

			// Look through the variables to set....
			foreach ($config_vars as $var => $val)
			{
				if (strncasecmp($settingsArray[$i], '$' . $var, 1 + strlen($var)) == 0)
				{
					$comment = strstr(substr($settingsArray[$i], strpos($settingsArray[$i], ';')), '#');
					$settingsArray[$i] = '$' . $var . ' = ' . $val . ';' . ($comment == '' ? "\n" : "\t\t" . $comment);

					// This one's been 'used', so to speak.
					unset($config_vars[$var]);
				}
			}

			if (trim(substr($settingsArray[$i], 0, 2)) == '?' . '>')
				$end = $i;
		}

		// This should never happen, but apparently it is happening.
		if (empty($end) || $end < 10)
			$end = count($settingsArray) - 1;

		// Still more?  Add them at the end.
		if (!empty($config_vars))
		{
			$settingsArray[$end++] = '';
			foreach ($config_vars as $var => $val)
				$settingsArray[$end++] = '$' . $var . ' = ' . $val . ';' . "\n";
			$settingsArray[$end] = '?' . '>';
		}

		// Sanity error checking: the file needs to be at least 10 lines.
		if (count($settingsArray) < 10)
			return;

		// Blank out the file - done to fix a oddity with some servers.
		$fp = fopen($_POST['path_to'] . '/Settings.php', 'w');
		fclose($fp);

		// Now actually write.
		$fp = fopen($_POST['path_to'] . '/Settings.php', 'r+');
		$lines = count($settingsArray);
		for ($i = 0; $i < $lines - 1; $i++)
			fwrite($fp, strtr($settingsArray[$i], "\r", ''));

		// The last line should have no \n.
		fwrite($fp, rtrim($settingsArray[$i]));
		fclose($fp);
	}
}

// https://stackoverflow.com/questions/2853454/php-unserialize-fails-with-non-encoded-characters/5813058#5813058
function mb_unserialize($string)
{
    $string2 = preg_replace_callback(
        '!s:(\d+):"(.*?)";!s',
        function($m){
            $len = strlen($m[2]);
            $result = "s:$len:\"{$m[2]}\";";
            return $result;

        },
        $string);
    return unserialize($string2);
}
?>