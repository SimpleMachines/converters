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

/**
 * The minimum required version.
 *
 * @var string
 */
$GLOBALS['required_php_version'] = '7.4.0';
$GLOBALS['required_mysql_version'] = '5.6.0';
$GLOBALS['required_postgresql_version'] = '9.6';

/**
 * The current path to the upgrade.php file.
 *
 * @var string
 */
$convert_path = dirname(__FILE__);

/**
 * The URL of the current page.
 *
 * @var string
 */
$converturl = $_SERVER['PHP_SELF'];

/**
 * Flag to disable the required administrator login.
 *
 * @var bool
 */
$disable_security = false;

// Load up SMF.
try {
	@include_once($convert_path . '/SSI.php');

	// Database driven session can make things go weird, disable it.
	if (!isset($_GET['FixDbSession']) && ($modSettings['databaseSession_enable'] ?: 0) == 1)
	{
		updateSettings(['databaseSession_enable' => 0]);
		redirectexit($_SERVER['REQUEST_SCHEME'] . '://' . $_SERVER['SERVER_NAME'] . $converturl . '?FixDbSession');
	}
}
catch (exception $e) {
	 die('Unable to locate SSI.php, place the convert.php and related converter script in your SMF root directory');
}

// CLI or Browser based access.
if ((php_sapi_name() == 'cli' || (isset($_SERVER['TERM']) && $_SERVER['TERM'] == 'xterm')) && empty($_SERVER['REMOTE_ADDR']))
	Converter::RunCLI($convert_path, $converturl, true);
else
	Converter::Run($convert_path, $converturl, $disable_security);

/**
 * Our master class for our converter logic.  This does all the routing and processing.
 */
class Converter
{
	/**
	 * How long the script will run until it executes a pause.  This should be set lower than your PHP's max execution time to allow time for current processes to finish.
	 *
	 * @var int
	 */
	private int		$timeout = 10;

	/**
	 * The path and url of the current page.  Thesse should not be changed as its populated above.
	 * The security is also set above.
	 *
	 * @var string|bool
	 */
	private string	$convert_path = '';
	private string	$converturl = '';
	private bool	$disable_security = false;

	/**
	 * These variables are passed in from get/post/sessiond data.
	 *
	 * @var mixed
	 */
	private bool	$debug = false;
	private string	$convertScript = '';
	private string	$convertDbPass = '';
	private string	$convertPathFrom = '';
	private int		$currentStep = 0;
	private int		$currentSubStep = 0;
	private int		$currentStart = 0;

	/**
	 * These variables are used by the templating engine.
	 *
	 * @var mixed
	 */
	private string	$pageTitle = 'SMF Converter';
	private string	$sectionTitle = 'SMF Converter';
	private string	$template = '';
	private int		$overallPercent = 0;
	private int		$stepProgress = -1;
	private int		$subStepProgress = -1;
	private string	$subStepProgressName = '';
	private int		$TimeStarted = 0;
	private string	$CustomWarning = '';
	private bool	$continue = true;
	private bool	$disableContinue = false;
	private bool	$allowSkip = false;
	private bool	$pause = false;

	/**
	 * These variables are used by the converter to keep track of appilcation data.
	 *
	 * @var mixed
	 */
	private bool	$isCli = false;
	private array	$script = [];
	private string	$toPrefix = '';
	private string	$fromPrefix = '';
	private	bool	$nextStep = false;

	/**
	 * [FUTURE] Allow automatic adjustment of the block size between 0.1 and 5.0
	 *
	 * @var float
	 */
	private bool	$allowParitalConverts = false;
	private float	$blockSizeAdjustment = 1.0;

	/**
	 * All the steps we have in the converter logic.
	 * The array is as follows
	 	step id = [
	 				step number (for the UI),
	 				text string for the step,
	 				function to execute,
	 				step weight (out of 100)
	 			]
	 */
	private array $steps = [
		0 => [1, 'convert_step_checkenv', 'stepSantityChecks', 1],
		1 => [2, 'convert_step_selectscript', 'stepSelectScript', 2],
		2 => [3, 'convert_step_options', 'stepConvertOptions', 5],
		3 => [4, 'convert_step_database', 'stepConvertDatabase', 65],
		4 => [5, 'convert_step_cleanup', 'stepCleanupDatabase', 25],
		5 => [6, 'convert_step_finish', 'stepFinishConvert', 2],
	];


	/**
	 * Build a new Converter class.  This really is still procedural, but keeps our logic cleaner.
	 *
	 * @param string $convert_path The path to this file.
	 * @param string $converturl The url to this file
	 * @param bool	 $disable_security Disable the security checks, not advised.
	 */
	public function __construct(string $convert_path, string $converturl, bool $disable_security)
	{
		global $context, $smcFunc, $modSettings;

		foreach (['convert_path', 'converturl', 'disable_security'] as $v)
			$this->{$v} = $$v;

		foreach (['smcFunc', 'context'] as $v)
			$this->{$v} = &$$v;
		$this->context['msgItems'] = [];

		// Some language strings in SMF we may want.
		loadLanguage('index+install');

		// We need the html_to_bbc tool sometimes.
		$this->loadSource('Subs-Editor');
		// Start the clock.
		if (!isset($_SESSION['TimeStarted']))
			$_SESSION['TimeStarted'] = microtime(true);
		$this->TimeStarted = $_SESSION['TimeStarted'];

		$this->loadTxt();
		$this->setUTF8();

		// SMF tries to protect us, but we need to make some unsafe queries.
		$modSettings['disableQueryCheck'] = 1;
	}

	/**
	 * Try to set some server settings to make the script operate better.
	 */
	private function setupServer()
	{
		try {
			error_reporting(E_ALL);
			set_time_limit(600);
			ini_set('mysql.connect_timeout', -1);
			ini_set('default_socket_timeout', 900);
			ini_set('memory_limit', '512M');
			ignore_user_abort(true);
			umask(0);

			// When in debug mode, we log our errors. Request hasn't been properly setup yet though.
			if ($this->getRequestVar('debug'))
				set_error_handler('Converter::ErrorHandler');
			ob_start();
			trySetupSession();
		}
		catch (exception $e) {}
	}

	/**
	 * Start the script.  This will retrieve all variables we need to (re)start the script.
	 * If we don't have a script or have not passed security checks, we are limited in what steps we can proceed to.
	 * This will execute steps and then run the templating.
	 */
	public function startRun()
	{
		// When starting up, we need to find this or default it.
		$this->currentStep = $this->getStep();
		$this->currentSubStep = $this->getSubStep();
		$this->currentStart = $this->getStart();
		$this->debug = !is_null($this->getRequestVar('debug')) ?? false;
		$this->convertScript = (string) $this->getRequestVar('convert_script') ?? '';
		$this->convertDbPass = (string) $this->getRequestVar('convertDbPass') ?? '';
		$this->convertPathFrom = (string) $this->getRequestVar('convertPathFrom') ?? '';

		// If we have a valid database password, we can get some more admin errors.
		if ($this->convertScript == '')
			$this->currentStep = min($this->currentStep, 1);
		else if (!empty($this->convertDbPass) && $this->verifySMFpassword($this->convertDbPass))
			$this->setErrorHandlers();
		else
			$this->currentStep = min($this->currentStep, 2);

/*
		if (isset($_GET['delete']))
			$this->destorySelf();
		else
*/
		if (isset($_REQUEST['empty_error_log']))
			$this->clearErrorLog();

		$this->overallPercent = 0;
		for ($i = 0; $i < $this->currentStep; ++$i)
			$this->overallPercent += $this->steps[$i][3];

		if (isset($this->steps[$this->currentStep]) && method_exists($this, $this->steps[$this->currentStep][2]))
			call_user_func([$this, $this->steps[$this->currentStep][2]]);

		$this->runTemplates();
	}
	/**
	 * Starts the script in CLI mode.  We do not need to worry about security checks or templating.  If somebody can execute this as CLI, they have server level access.
	 */
	public function startRunCli()
	{
		$this->setErrorHandlers(true);

		$this->convertScript = (string) $this->getRequestVar('convert_script') ?? '';
		$this->convertDbPass = (string) $this->getRequestVar('convertDbPass') ?? '';
		$this->convertPathFrom = (string) $this->getRequestVar('convertPathFrom') ?? '';

		if (isset($this->steps[$this->currentStep]) && method_exists($this, $this->steps[$this->currentStep][2]))
			call_user_func([$this, $this->steps[$this->currentStep][2]]);
	}

	/**
	 * Handle a standard PHP error, log it and try to pass it through to our converter tool.
	 */
	public function doErrorHandler($error_level, $error_string, $file, $line, $errorContext = array(), $is_database_error = false)
	{
		global $cachedir, $command_line;

		// Our error_log
		$convert_error_log = is_writable($cachedir . '/convert_error_log') ? $cachedir . '/convert_error_log' : dirname($this->convert_path) . '/convert_error_log';

		// Is it Database Specific?
		if (!empty($is_database_error))
		{
			/*
				Note, Unlike php this is slightly different.
				error_level = errror from database
				error_string = original query
			*/

			// The array is easier than using \r as well makes it easier for command line.
			$error_array = [
				'',
				$this->doTxt('convert_database_encountered_error', $line),
				$this->doTxt('convert_database_error_received'),
				"---",
				$error_level,
				"---",
				$this->doTxt('convert_databse_query_ran_was'),
				"---",
				$error_string,
				"---",
			];
		}
		else
		{
			// Generate a simple error message familer to PHP errors, expect we do them one better.
			$error_array = [
				'',
				$error_level % 255 == E_ERROR ? 'Error' : ($error_level % 255 == E_WARNING ? 'Warning' : 'Notice') . ': ' . $error_string . ' in ' . $file . ' on line ' . $line,
				$this->doTxt('convert_backtrace_report'),
				"---"
			];

			// Lets leave a paper trail.
			$error_array[] = print_r(debug_backtrace(), true);
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
			$this->doError($error_data[1]);
		// If its not command lind and not a database error, echo the error info (without backtrack).
		elseif (!$is_database_error)
		{
			foreach ($error_array as $e)
				echo '<pre>', $e, '</pre>';
		}
	}

	/**
	 * Process a error into the converter script.  For CLI we just output, for UI we pause execution and prevent auto continues.
	 *
	 * @param string $msg The error message
	 * @param bool $showDbError If true, it tries to show the error received by the database.
	 * @param string $db_query This will show the database query we tried to execute
	 * @return void We do not return anything, the process should exit.
	 */
	public function doSkip(string $msg): void
	{
		global $context, $smcFunc, $db_connection;

		if ($this->isCli)
		{
			$this->sendMsgToCli($msg);
			$this->sendMsgToCli($this->doTxt('convert_skipping'));
		}

		$this->CustomWarning = $msg;
		$this->nextStep = false;
		$this->pause = false;
		$this->allowSkip = true;
		$this->runTemplates();
		die;
	}

	/**
	 * Process a error into the converter script.  For CLI we just output, for UI we pause execution and prevent auto continues.
	 *
	 * @param string $msg The error message
	 * @param bool $showDbError If true, it tries to show the error received by the database.
	 * @param string $db_query This will show the database query we tried to execute
	 * @return void We do not return anything, the process should exit.
	 */
	public function doError(string $msg, bool $showDbError = false, string $db_query = '', $conn = null): void
	{
		global $context, $smcFunc, $db_connection;

		if ($this->isCli)
		{
			$this->sendMsgToCli($msg);
			if ($showDbError && !is_null($db_connection))
				$this->sendMsgToCli($smcFunc['db_error']($db_connection));
			if ($showDbError && !empty($db_query))
				$this->sendMsgToCli(trim($db_query));
			die;
		}

		$this->CustomWarning = $msg;

		if ($showDbError && !is_null($db_connection))
			$this->CustomWarning .= '<br>' . $smcFunc['db_error']($conn ?? $db_connection);
		if ($showDbError && !empty($db_query))
			$this->CustomWarning .= '<br>' . nl2br(htmlspecialchars(trim($db_query)));

		$this->pause = false;
		$this->runTemplates();
		die;
	}

	/**
	 * Check if we should pause execution.  For CLI we just return.  For UI we check the timeout value and pause execution
	 * 
	 * @param int $start What our currentStart is, we will update this
	 * @param callback $func If we have a special function we need to execute prior to doing our timeout.
	 * @param array $funcArgs  We will pass these to the special timeout function
	 */
	public function doPastTime(int $start, callback $func = null, array $funcArgs = [])
	{
		$this->currentStart = $start;

		// Need to call something extra.
		if (is_callable($func))
			$func(...$funcArgs);

		if ($this->isCli)
		{
			$this->sendMsgToCli('.', false);
			return;
		}

		try
		{
			set_time_limit(300);
			if (function_exists('apache_reset_timeout'))
				apache_reset_timeout();
		}
		catch (exception $e) {}

		if (time() - TIME_START < $this->timeout)
			return;

		// Make sure we pause.
		$this->overallPercent += $this->steps[$this->currentStep][3] * ($this->stepProgress / 100);

		$this->pause = true;
		$this->runTemplates();
	}

	/**
	 * Get a language string and optionally provide a sprintf.
	 * 
	 * @param string $key The text string key
	 * @param callback $func If we have a special function we need to execute prior to doing our timeout.
	 * @param array $funcArgs  We will pass these to the special timeout function
	 */
	public function doTxt(string $key, string ...$args): string
	{
		global $txt;

		// If we have args passed, we want to pass this to sprintf.  We will keep args in a array and unpack it into sprintf.
		if (!empty($args))
			return isset($txt[$key]) ? sprintf($txt[$key], ...$args) : $key;
	
		return $txt[$key] ?? $key;
	}

	/*
	 * Make sure our enviornment is sane.  Such as PHP versions, supported databases, etc.
	 * This executes first and typically should not do any errors
	*/
	public function stepSantityChecks()
	{
		global $smcFunc;

		$this->sectionTitle = $this->doTxt('convert_title_SantityChecks');
		$this->template = 'SantityChecks';

		if (!is_null($this->getRequestVar('restart', false, false)))
			$_SESSION = $_POST = $_GET = [];
		if ($this->IsUnSupportedDatabase())
			$this->doError($this->doTxt('convert_unsupported_databases', $this->smcFunc['db_title']));

		if (version_compare(PHP_VERSION, $GLOBALS['required_php_version'], '<'))
			$this->doError($this->doTxt('convert_unsupported_version', 'PHP ' . PHP_VERSION));

		db_extend();
		if ($this->smcFunc['db_title'] == MYSQL_TITLE && version_compare($this->smcFunc['db_get_version'](), $GLOBALS['required_mysql_version'], '<'))
			$this->doError($this->doTxt('convert_unsupported_version', 'MySQL ' . $this->smcFunc['db_get_version']()));

		if ($this->smcFunc['db_title'] == POSTGRE_TITLE && version_compare($this->smcFunc['db_get_version'](), $GLOBALS['required_postgresql_version'], '<'))
			$this->doError($this->doTxt('convert_unsupported_version', 'Postgresql ' . $this->smcFunc['db_get_version']()));

		// We have completed all checks.  Continue.
		$this->goToNextStep();
		$this->runTemplates();
	}

	/*
	 * Most enviornments will not have multiple scripts.  But provide a UI for this.
	 * Upon selecting the script, the logic will attempt to proceed to the next step.
	*/
	public function stepSelectScript() {
		global $context;

		$this->sectionTitle = $this->doTxt('convert_title_SelectScript');
		$this->template = 'SelectScript';

		$context['converter_scripts'] = $this->findConverterScripts();
		sort($context['converter_scripts']);

		// If we found only one, we can skip this step.
		if (count($context['converter_scripts']) == 1)
		{
			$this->convertScript = $_SESSION['convert_script'] = $context['converter_scripts'][0]['path'];
			$this->goToNextStep(true);
			return;
		}
		elseif ($this->getRequestVar('convert_script') == '')
			$this->continue = false;

		// If we have a valid script, go to the next step.
		if ($this->getRequestVar('convert_script') != '')
		{
			$this->convertScript = $this->getRequestVar('convert_script');
			$this->goToNextStep(true);
		}
	}

	/*
	 * We will handle any options needed.  This typically is only asking for the path to the forum and the SMF database password.
	 * Scripts can pass parameters to here for additional questions/configurations.
	*/
	public function stepConvertOptions()
	{
		$this->sectionTitle = $this->doTxt('convert_title_ConvertOptions');
		$this->template = 'ConvertOptions';

		$this->context['script'] = $this->script = $this->loadConverterScript();
		// Load up anything we need to do the scripts.
		$this->loadSettings($this->script);

		$this->context['steps'] = [];
		for($i = 1; isset($this->script['class']::${'convertStep' . $i . 'info'}); ++$i)
			$this->context['steps'][$i] = $this->script['class']::${'convertStep' . $i . 'info'};

		// Nothing yet, don't try to validate stuff.
		if (empty($this->getRequestVar('convertPathFrom')) || empty($this->getRequestVar('convertDbPass')))
		{
			$this->showSteps = true;
			return;
		}

		$found = empty($this->script['settings']);
		if ($this->getRequestVar('convertPathFrom') != '' && isset($this->script['settings']))
			foreach ($this->script['settings'] as $file)
				$found |= file_exists($this->getRequestVar('convertPathFrom') . $file);
		$this->context['fromFound'] = $found;

		// We are trying to 
		if (!empty($this->getRequestVar('convertPathFrom')))
		{
			if (ini_get('open_basedir') != '' && !$found)
				$this->doError($this->doTxt('convert_open_basedir', $this->script['name']));
			elseif (!$found)
				$this->doError($this->doTxt('convert_from_settings_missing', $this->script['name']));
		}

		if (!empty($this->getRequestVar('convertDbPass')) && !$this->verifySMFpassword($this->getRequestVar('convertDbPass')))
			$this->doError($this->doTxt('convert_bad_smf_db_passwd'));

		$this->setToPrefix();

		// At this point, we can try to load the settings.
		if (!$this->loadConverterSettings($this->script))
				$this->doError($this->doTxt('convert_from_database_no_access', $this->script['name']), true);

		// Try this.
		$this->SetMysqlLargeJoins();

		// Everything is set, continue on.
		$this->goToNextStep(true);
	}

	/*
	 * This is the main script that will execute all the conversion steps in the converter script.
	 * We do various tasks here on repeat each time the script is reloaded in the UI.
	 */
	public function stepConvertDatabase()
	{
		$this->sectionTitle = $this->doTxt('convert_title_ConvertDatabase');
		$this->template = 'ConvertDatabase';

		// Skip leg day?
		if (!empty($this->getRequestVar('skip', false, false) ?? 0))
			++$this->currentSubStep;

		// Loop ints.
		$this->currentStart = $this->getRequestVar('currentStart');

		// Pawsed.
		$this->pause = true;
		$this->setToPrefix();
		if (empty($this->script))
		{
			$this->script = $this->loadConverterScript();
			// Load up anything we need to do the scripts.
			$this->loadConverterSettings($this->script);
		}

		$convclass = $this->script['class'];

		// Ensure we load any system preperations.
		call_user_func($convclass . '::prepareSystem');

		// Load any settings required by the system.
		call_user_func($convclass . '::loadConverterSettings');

		// Replay any messages.
		$weights = call_user_func($convclass . '::stepWeights');

		for($i = 1; isset($convclass::${'convertStep' . $i . 'info'}) && $i <= $this->currentSubStep; ++$i)
		{
			$this->sendMsg($convclass::${'convertStep' . $i . 'info'});
			$this->stepProgress += $weights['convertStep' . $i] ?? 0;
		}

		if (!empty($this->getRequestVar('skip', false, false) ?? 0))
			$this->sendMsg($this->doTxt('convert_skiped'));

		// Loop all the steps.
		for($i = $this->currentSubStep + 1; method_exists($convclass, 'convertStep' . $i . 'Custom') || method_exists($convclass, 'convertStep' . $i); ++$i)
		{
			if (isset($convclass::${'convertStep' . $i . 'info'}))
			{
				$this->subStepProgressName = $convclass::${'convertStep' . $i . 'info'};
				$this->sendMsg($this->subStepProgressName);
			}

			// Run the logic where we want to do the entire conversion ourselves.
			if (method_exists($convclass, 'convertStep' . $i . 'Custom'))
				call_user_func($convclass . '::convertStep' . $i . 'Custom');
			elseif (method_exists($convclass, 'convertStep' . $i))
				call_user_func_array($convclass . '::doConvert', [call_user_func($convclass . '::convertStep' . $i)]);

			$this->doPastTime(0);

			// Completed, go to the next step.
			$this->stepProgress += $weights['convertStep' . $i] ?? 0;
			$this->currentSubStep = $i;
			$this->currentStart = 0;
		}

		// Everything is set, continue on.
		$this->currentSubStep = $this->stepProgress = 0;
		$this->goToNextStep(false);
	}

	/*
	 * After conversion, sometimes pieces are left in bad states.  Rather than getting the all converters to fix these,
	 * 		this section will run all cleanup and repair tools to get SMF into a stable state.
	 */
	public function stepCleanupDatabase()
	{
		$this->sectionTitle = $this->doTxt('convert_title_ConvertDatabase');
		$this->template = 'ConvertDatabase';

		// Loop ints.
		$this->currentStart = $this->getRequestVar('currentStart');
		$this->pause = true;
		$this->setToPrefix();

		// Load up anything we need to do the scripts.
		$convclass = 'CleanupDatabase';

		// Ensure we load any system preperations.
		call_user_func($convclass . '::prepareSystem');

		// Load any settings required by the system.
		call_user_func($convclass . '::loadConverterSettings');

		// Replay any messages.
		$weights = call_user_func($convclass . '::stepWeights');

		for($i = 1; isset($convclass::${'convertStep' . $i . 'info'}) && $i <= $this->currentSubStep; ++$i)
		{
			$this->sendMsg($convclass::${'convertStep' . $i . 'info'});
			$this->stepProgress += $weights['convertStep' . $i] ?? 0;
		}

		// Loop all the steps.
		for($i = $this->currentSubStep + 1; method_exists($convclass, 'convertStep' . $i); ++$i)
		{
			if (isset($convclass::${'convertStep' . $i . 'info'}))
				$this->sendMsg($convclass::${'convertStep' . $i . 'info'});

			// Run the logic where we want to do the entire conversion ourselves.
			call_user_func($convclass . '::convertStep' . $i);

			$this->doPastTime(0);

			// Completed, go to the next step.
			$this->stepProgress += $weights['convertStep' . $i] ?? 0;
			$this->currentSubStep = $i;
			$this->currentStart = 0;
		}

		// Everything is set, continue on.
		$this->currentSubStep = $this->stepProgress = 0;
		$this->goToNextStep(false);
	}

	/*
	 * We have finished the conversion, we let SMF know to let us login with older passwords and allow deletion of this script.
	 */
	public function stepFinishConvert()
	{
		$this->sectionTitle = $this->doTxt('convert_title_FinishConvert');
		$this->template = 'FinishConvert';

		$this->setToPrefix();
		$this->context['script'] = $this->script = $this->loadConverterScript();
		ConverterDb::insert(
			'{to_prefix}settings',
			['variable', 'value'],
			[
				['conversion_time', time()],
				['conversion_from', $this->convertScript],
				['enable_password_conversion', 1]			],
			['variable'], // Keys
			'replace'
		);

		// For you CLI users, you are done.
		if ($this->isCli)
		{
			$this->sendMsg($this->doTxt('convert_completed'));
			$this->sendMsg($this->doTxt('convert_delete_script'));
			die;
		}

		// Can we delete ourselves.
		$this->context['can_delete_self'] = is_writable(dirname($this->convert_path)) && is_writable($this->convert_path);
		$this->pause = false;
		$this->continue = false;
		$this->runTemplates();
	}

	/*
	 * SEnd a message to the UI or CLI.  For UI this appears in the message list, for CLI we just print to the console.
	 *
	 * @param string $msg The message we are sending
	 * @param bool $isDebug If this is a debug message, we will send it only if we are in debug mode.
	 * @return void Nothing is returned, these are send to the client.
	 */
	public function sendMsg(string $msg, bool $isDebug = false): void
	{
		if ($isDebug && empty($this->debug))
			return;

		if ($this->isCli)
			$this->sendMsgToCli($msg);
		else
			$this->context['msgItems'][] = $msg;
	}

	/*
	 * Run our template header, content and footer.  Nothing is returned, all information is outputted.
	 */
	private function runTemplates(): void
	{
		template_convert_above();
		if (!empty($this->template) && function_exists('template_convert_' . $this->template))
			call_user_func('template_convert_' . $this->template);
		template_convert_below();
		die;
	}

	/*
	 * Get the current step
	 *
	 * @return int
	 */
	private function getStep(): int
	{
		return (int) ($_REQUEST['step'] ?? 0);
	}

	/*
	 * Get the current sub step
	 *
	 * @return int
	 */
	private function getSubStep(): int
	{
		return (int) ($_REQUEST['substep'] ?? 0);
	}

	/*
	 * Get the current start
	 *
	 * @return int
	 */
	private function getStart(): int
	{
		return (int) ($_REQUEST['start'] ?? 0);
	}

	/*
	 * Get a variable from our input or session.  If we can get it, we also save it to session for later.
	 *
	 * @param string $key the key we are looking for.
	 * @param bool $trySession If this is false, we won't try to look in our session data.
	 * @param bool $saveSession If this is false, we don't save this into our session data.
	 * @return mixed
	 */
	private function getRequestVar(string $key, bool $trySession = true, bool $saveSession = true)
	{
		$data = null;

		if (isset($_POST[$key]))
			$data = $_POST[$key];
		elseif (isset($_GET[$key]))
			$data = $_GET[$key];
		elseif ($trySession && isset($_SESSION[$key]))
			$data = $_SESSION[$key];
		elseif (isset($this->{$key}))
			$data = $this->{$key};

		if ($saveSession && (!isset($_SESSION[$key]) || $_SESSION[$key] != $data))
			$_SESSION[$key] = $data;

		return $data;
	}
	/*
	 * Get a variable for our converter script from our input or session.  If we can get it, we also save it to session for later.
	 *
	 * @param string $key the key we are looking for.
	 * @param bool $trySession If this is false, we won't try to look in our session data.
	 * @param bool $saveSession If this is false, we don't save this into our session data.
	 * @return mixed
	 */
	private function dogetParameter(string $key, bool $trySession = true, bool $saveSession = true)
	{
		$data = null;

		if (isset($_POST['parameters'][$key]))
			$data = $_POST['parameters'][$key];
		elseif (isset($_GET['parameters'][$key]))
			$data = $_GET['parameters'][$key];
		elseif (isset($_SESSION['parameters'][$key]))
			$data = $_SESSION['parameters'][$key];

		if ($saveSession && (!isset($_SESSION['parameters'][$key]) || $_SESSION['parameters'][$key] != $data))
			$_SESSION['parameters'][$key] = $data;

		return $data;
	}

	/*
	 * Takes CLI parameters and processes them as if they where POST variables, allowing our script to get this data easier later.
	 */
	private function parseCliParams()
	{
		// If we are not sure, leave it blank, but the first argv may have the path.
		$pathToPHP = '/path/to/php';
		if (isset($_SERVER['argv'][0]) && basename($_SERVER['argv'][0]) == 'php')
			$pathToPHP = trim($_SERVER['argv'][0]);

		// Lets get the path_to and path_from
		foreach ($_SERVER['argv'] as $i => $arg)
		{
			// Trim spaces.
			$arg = trim($arg);

			if (preg_match('~^--path_from=(.+)$~', $arg, $match) != 0)
				$_POST['convertPathFrom'] = substr($match[1], -1) == '/' ? substr($match[1], 0, -1) : $match[1];
			elseif (preg_match('~^--db_pass=(.+)?$~', $arg, $match) != 0)
				$_POST['convertDbPass'] = isset($match[1]) ? $match[1] : '';
			elseif ($arg == '--debug')
				$_POST['debug'] = $this->debug = true;
			elseif (preg_match('~^--convert_script=(.+)$~', $arg, $match) != 0)
				$_REQUEST['convert_script'] = $match[1];
			elseif ($arg == '--help' || $arg == '-h' || $i = 0)
			{
				print_error('SMF Command-line Converter
		Usage: ' . $pathToPHP . ' -f ' . basename($this->convert_path) . ' -- [OPTION]...

		--path_from             Path to the software that you are converting from.
		--convert_script        The name of the script. (old_forum_to_smf.sql)
		--db_pass               SMF database password. "The Database password (for verification only.)"
		--debug                 Output debugging information.', true);
			}

			// We have extra params.
			if (preg_match('~^--(.+)=(.+)$~', $arg, $match) != 0 && !array_key_exists($match[1], $_POST))
				$_POST[$match[1]] = $match[2];
			// We have extra params for the converter params
			if (preg_match('~^--param\[(.+)\]=(.+)$~', $arg, $match) != 0 && !array_key_exists($match[1], $_POST))
				$_POST['parameters'][$match[1]] = $match[2];
		}
	}

	/*
	 * Try to startup a SMF session.
	 * We try to use the standard method, but we fall back to writing to the cache if needed.
	 */
	private function trySetupSession()
	{
		global $cachedir;

		session_start();

		if (ini_get('session.save_handler') == 'user')
			ini_set('session.save_handler', 'files');
		session_start();

		// Check session path is writable
		$session_path = ini_get('session.save_handler');

		// If not lets try another place just for the conversion...
		if (!is_writable($session_path) && file_exists($cachedir))
			ini_set('session.save_path', $cachedir);
		elseif (!is_writable($session_path))
			ini_set('session.save_path', dirname($this->convert_path) . '/cache');
	}

	/*
	 * Simple here.  If requested, we wil delete all converter related scripts.
	 */
	private function destorySelf()
	{
		global $cachedir;

		unlink($cachedir . '/convert_error_log');
		unlink($this->convert_path . '/convert_error_log');
		unlink($this->convert_path . '/convert.php');
		if (preg_match('~_to_smf\.(php|sql)$~', $_SESSION['convert_script']) != 0)
			@unlink($this->convert_path . '/' . $_SESSION['convert_script']);
		$_SESSION['convert_script'] = null;

		exit;
	}

	/*
	 * Try to delete the converter error log
	 */
	private function clearErrorLog()
	{
		global $cachedir;

		unset($_REQUEST['empty_error_log']);
		@unlink($cachedir . '/convert_error_log');
		@unlink($this->convert_path . '/convert_error_log');
	}

	/*
	 * We will use this to match our SMF database version and ensure the converter script supports us.
	 *
	 * @param string $version The version we are checking against.
	 * @return bool True if we have a version that can be used by the converter script.
	 */
	private function matchPackageVersion(string $version): bool
	{
		global $modSettings;
		return matchPackageVersion($modSettings['smfVersion'], $version);
	}

	/*
	 * Sending a message to the CLI.  We are writing to the stderr if possible.
	 * This will also strip out any html tags so its friendly for CLI.
	 *
	 * @param string $msg The message to send to the client.
	 * @param bool $addEnding If true, we will add a \n line ending.
	 * @param bool $fatal If true, this message is fatal and we stop execution.
	 * @return void nothing is returned, we output to the client.
	 */
	private function sendMsgToCli(string $msg, bool $addEnding = true, bool $fatal = false): void
	{
		static $fp = null;

		$msg = preg_replace('~<([A-Z][A-Z0-9]*)\b[^>]*>(.*?)</\1>~i', '$2', $msg);

		if ($fp === null)
			$fp = fopen('php://stderr', 'wb');

		fwrite($fp, $message);
		fwrite($fp, $add_ending ? "\n" : '');

		if ($fatal)
			exit;
	}

	/*
	 * Loads a specific converter script up and gets it ready.  Also performs some version checks
	 *
	 * @return array All the script data we need.  This is the info data from the script + className
	 */
	private function loadConverterScript(): array
	{
		static $script = [];

		if (!empty($script))
			return $script;

		if (empty($this->context['converter_scripts']))
			$this->context['converter_scripts'] = $this->findConverterScripts();

		$found = false;
		foreach($this->context['converter_scripts'] as $s)
			if ($s['path'] == $this->convertScript)
			{
				$found = true;
				break;
			}
		if (empty($found))
			$this->doError($this->doTxt('convert_unable_to_find_scripts'));

		try {
			@include_once($this->convert_path . '/' . $this->convertScript);
		}
		catch (exception $e) {
			if ($this->debug)
				var_dump($e);
		}

		$p = pathinfo($this->convertScript);
		$className = preg_replace('~^convert_([a-z0-9\-_\.]*)_to_smf\.php$~i', '\1_to_smf', $p['basename']);

		if (!method_exists($className, 'info'))
			$this->doError($this->doTxt('convert_missing_info_class'));

		$script = call_user_func($className . '::info');
		if (empty($script))
			$this->doError($this->doTxt('convert_invalid_info_class'));

		// Make sure this script is for this version.
		if (!$this->matchPackageVersion($script['version']))
			$this->doError($this->doTxt('convert_invalid_smf_version'));

		$script['class'] = $className;

		return $script; 
	}

	/*
	 * This will look inside the convert_path for any scripts matching a converter and seem to contain valid converter scripts.
	 *
	 * @return array A list of all converter files we can use.
	 */
	private function findConverterScripts(): array
	{
		$this->loadSource('Subs-Package');

		$scripts = [];
		$files = new RecursiveDirectoryIterator($this->convert_path, RecursiveDirectoryIterator::SKIP_DOTS);

		foreach ($files as $file)
		{
			if (
				$file->getExtension() != 'php'
				|| !$file->isFile()
				|| !$file->isReadable()
				|| !preg_match('~^convert_[a-z0-9\-_\.]*_to_smf\.php$~i', $file->getFilename())
			)
				continue;
			try {
				@include_once($this->convert_path . '/' . $file->getFilename());
			}
			catch (exception $e) {
				if ($this->debug)
					var_dump($e);
			}

			$className = preg_replace('~^convert_([a-z0-9\-_\.]*)_to_smf\.php$~i', '\1_to_smf', $file->getFilename());
			if (!method_exists($className, 'info'))
				continue;
			$infoData = call_user_func($className . '::info');
			if (empty($infoData))
				continue;

			// Make sure this script is for this version.
			if (!$this->matchPackageVersion($infoData['version']))
				continue;

			$scripts[] = [
				'path' => $file->getFilename(),
				'name' => $infoData['name']
			];
		}

		return $scripts;
	}

	/*
	 * Load a SMF source file.
	 *
	 * @param string $file the source file to load.
	 */
	private function loadSource(string $file): void
	{
		global $sourcedir;

		require_once($sourcedir . '/' . $file . '.php');
	}

	/*
	 * Load the initial settings for the converter.
	 * Run any custom code we need to execute early on.
	 *
	 * @param array $convert_data The converter data loaded from the script.
	 */
	private function loadSettings(array $convert_data): void
	{
		if (isset($convert_data['globals']))
			foreach ($convert_data['globals'] as $global)
				global $$global;

		if (isset($convert_data['defines']))
		{
			foreach ($convert_data['defines'] as $define)
			{
				$define = explode('=', $define);
				define($define[0], isset($define[1]) ? $define[1] : '1');
			}
		}

		if (!empty($convert_data['eval']))
			eval($convert_data['eval']);

		if (isset($convert_data['startup']))
				$func($this);

		if (!empty($convert_data['parameters']))
			foreach ($convert_data['parameters'] as $param)
				${$param['id']} = $this->getRequestVar($param['id']);
	}

	/*
	 * Loads the conversion script ready for executions such as converting steps and connecting to databases.
	 *
	 * @param array $convert_data The converter data loaded from the script.
	 * @return bool if this returns false, we failed to startup the system to run a conversion.
	 */
	private function loadConverterSettings(array $convert_data): bool
	{
		global $smcFunc;

		$this->loadSettings($convert_data);

		if (isset($convert_data['globals']))
			foreach ($convert_data['globals'] as $global)
				global $$global;

		if (isset($this->script['settings']))
			foreach ($convert_data['settings'] as $file)
				if (file_exists($this->convertPathFrom . $file) && empty($convert_data['flatfile']))
					require_once($this->convertPathFrom . $file);

		$from_prefix = '';
		if (isset($convert_data['from_prefix']))
			$from_prefix = eval('return "' . $this->fixDbPrefix($convert_data['from_prefix'], $smcFunc['db_title']) . '";');

		if (preg_match('~^`[^`]+`.\d~', $from_prefix) != 0)
			$from_prefix = strtr($from_prefix, array('`' => ''));

		$this->setFromPrefix($from_prefix);
		$this->fromPrefix = $from_prefix;

		ConverterDb::fromCon(call_user_func($convert_data['class'] . '::connectDb'));
		
		return true;
	}

	/*
	 * Tests a database in the source system to ensure it exists.  If this fails, we failed to connect.
	 *
	 * @param array $convert_data The converter data loaded from the script.
	 * @return bool If we successfully tested the source database or not.
	 */
	private function testFromTable(array $convert_data): bool
	{
		if (empty($convert_data['table_test']))
			return true;

		$result = ConverterDb::FromQuery('
			SELECT COUNT(*)
			FROM ' . eval('return "' . $convert_data['table_test'] . '";'), true);

		$res = !($result === false);
		ConverterDb::free_result($result);
		return $res;
	}

	/*
	 * Verify that we have entered the proper SMF database passsword.
	 * This is ignored if we have disabled password security.
	 */
	private function verifySMFpassword(string $password): bool
	{
		global $db_passwd;

		return empty($this->disable_security) || $db_passwd === $password;
	}

	/*
	 * Checks if we are running a unsupported database.
	 */
	private function IsUnSupportedDatabase(): bool
	{
		return in_array($this->smcFunc['db_title'], ['SQLite', 'PostgreSQL']);
	}

	/*
	 * Enforces SMF to run in UTF8. SMF 2.1+ only supports UTF8
	 */
	private function setUTF8(): void
	{
		$this->smcFunc['db_query']('', 'SET NAMES utf8', 'security_override');
	}

	/*
	 * Sets up the to prefix we use for covnersions.
	 * SMF 2.1.0 to 2.1.2 have a bug that makes our db_* functions not work on SSI, we hack around this.
	 */
	private function setToPrefix(): void
	{
		global $smcFunc, $db_prefix, $db_name, $db_connection;

		// SMF 2.1.2 and below, had a bug where we didn't handle the database prefix properly when operating from SSI, make work around.
		if (version_compare(SMF_VERSION, '2.1.2', '<=') && (strpos($db_prefix, $db_name) === 0 || strpos($db_prefix, '`' . $db_name) === 0))
		{
			$toPrefix = substr($db_prefix, strlen(substr($db_prefix, 0, 1) === '`' ? '`' . $db_name . '`.' :$db_name . '.'));

			// Hack around mysql select db required.			if ($smcFunc['db_title'] === 'MySQL')
				mysqli_select_db($db_connection, $db_name);
		}
		else if (strpos($db_prefix, '.') === false)
			$toPrefix = is_numeric(substr($db_prefix, 0, 1)) ? $db_name . '.' . $db_prefix : '`' . $db_name . '`.' . $db_prefix;
		else
			$toPrefix = $db_prefix;

		$this->toPrefix = $_SESSION['toPrefix'] = $toPrefix;
	}

	/*
	 * Get our ToPrefix variable.
	 */
	private function getToPrefix(): string
	{
		return $this->toPrefix = $_SESSION['toPrefix'] ?? '';
	}

	/*
	 * Sets our From Prefix variable.  we build this after we have a converter script and have passed security checks.
	 *
	 * @param string $from_prefix The source database prefix
	 */
	private function setFromPrefix(string $from_prefix): void
	{
		$_SESSION['from_prefix'] = $from_prefix;
	}

	/*
	 * Get the From/source database prefix
	 */
	private function getFromPrefix(): string
	{
		return $_SESSION['from_prefix'] ?? '';
	}

	/*
	 * We may need to perform large SQL joins.  So this sets our database session variables to allow it
	 */
	private function SetMysqlLargeJoins(): void
	{
		global $db_connection;

		if ($this->smcFunc['db_title'] != 'MySQL')
			return;

		// Fix MySQL 5.6 variable name change
		$max_join_var_name = 'SQL_MAX_JOIN_SIZE';

		$mysql_version = $this->smcFunc['db_server_info']($db_connection);

		if (stripos($mysql_version,"MariaDB") > 0 ||  version_compare($mysql_version, '5.6.0') >= 0)
			$max_join_var_name = 'max_join_size';

		$results = $this->smcFunc['db_query']('', "SELECT @@SQL_BIG_SELECTS, @@$max_join_var_name", 'security_override');
		list($big_selects, $sql_max_join) = $this->smcFunc['db_fetch_row']($results);

		// Only waste a query if its worth it.
		if (empty($big_selects) || ($big_selects != 1 && $big_selects != '1'))
			$this->smcFunc['db_query']('', "SET @@SQL_BIG_SELECTS = 1", 'security_override');

		// Lets set MAX_JOIN_SIZE to something we should
		if (empty($sql_max_join) || ($sql_max_join == '18446744073709551615' && $sql_max_join == '18446744073709551615'))
			$this->smcFunc['db_query']('', "SET @@$max_join_var_name = 18446744073709551615", 'security_override');
	}

	/*
	 * Advances to the next step.  If we do a automove, it will execute the next step automatically.
	 *
	 * @param bool $autoMove If true, we execute the next step.
	 */
	private function goToNextStep(bool $autoMove = false)
	{
		$this->nextStep = true;

		if (empty($autoMove))
			return;

		++$this->currentStep;

		$this->overallPercent = 0;
		for ($i = 0; $i < $this->currentStep; ++$i)
			$this->overallPercent += $this->steps[$i][3];

		call_user_func([$this, $this->steps[$this->currentStep][2]]);
	}

	/*
	 * Sets our database prefix to be valid as various database systems handle the prefix differently.
	 */
	private function fixDbPrefix($prefix, $db_type)
	{
		if ($db_type == 'MySQL')
			return $prefix;
		elseif ($db_type == 'PostgreSQL')
		{
			$temp = explode('.', $prefix);
			return str_replace('`', '', $temp[0] . '.public.' . $temp[1]);
		}
		else
			die('Unknown Database: ' . $db_type);
	}

	/*
	 * Set our error handlers.  This is done only after we have verified they can pass security checks.
	 *
	 * @param bool $isCli If this is true, we will use error handler that are more CLI friendly
	 */
	private function setErrorHandlers(bool $isCli = false): void
	{
		// Set a friendly error handler.
		set_error_handler('Converter::error_handler');

		// Tell SMF we will handle the error here.
		global $ssi_on_error_method;
		$ssi_on_error_method = 'Converter::ssi_on_error_method' . ($isCli ? '_cli' : '');

		// We shall lie to SMF and say we are a admin.
		global $user_info;
		$user_info['admin'] = $this->context['user']['is_admin'] = true;
	}

	/*
	 * This is a singleton loader for our scripts.
	*/
	private static function ld(): self
	{
		return $GLOBALS['converter'];
	}

	/*
	 * Initialize the converter script.
	 *
	 * @param string $convert_path The path to the converter file, typically __FILE___
	 * @param string $converturl The url to the script, typically $_SERVER['PHP_SELF']
	 * @param bool $disable_security If true, byapasses security checks.
	 * @return self This class loaded as a object.
	 */
	public static function load(string $convert_path, string $converturl, bool $disable_security): self
	{
		if (!isset($GLOBALS['converter']))
			$GLOBALS['converter'] = new self($convert_path, $converturl, $disable_security);
		return $GLOBALS['converter'];
	}

	/*
	 * Just a simple wrapper for calling the script and executing it for a normal UI.
	 * This takes the same params as load()
	 */
	public static function Run(string $convert_path, string $converturl, bool $disable_security)
	{
		return static::load($convert_path, $converturl, $disable_security)->startRun();
	}

	/*
	 * Just a simple wrapper for calling the script and executing it for CLI.
	 * This takes the same params as load() except no security needed.
	 */
	public static function RunCLI(string $convert_path, string $converturl)
	{
		return static::load($convert_path, $converturl, false)->startRunCli();
	}

	/*
	 * A magic method to call a method statically as long as the method is prefixed with 'do'
	 *
	 * @param string $method the method we will call.
	 * @param array $args all args we will pass onto the method.
	 */
	public static function __callStatic($method, $args = [])
	{
		return static::ld()->{'do' . $method}(...$args);
	}

	/*
	 * Get a variable for later use.
	 */
	public function dogetVar(string $key)
	{
		return $this->{$key} ?? '';
	}

	/*
	 * Send a debug message to the client.
	 */
	public static function debugMsg(string $msg)
	{
		return static::ld()->sendMsg('[DEBUG] ' . $msg, true);
	}

	/**
	 * Helper method to try to display SMF's error messages.  SMF doesn't pass anything params, but we can get the message from $context.  It is HTML formatted and we don't need that for here, but it isn't nescarry to strip htmlt tags as its debug output.
	 * @return void We display a error.
	 */
	public static function ssi_on_error_method(): void
	{
		global $context;
		self::error($context['error_message']);
	}

	/**
	 * Helper method to try to display SMF's error messages.  SMF doesn't pass anything params, but we can get the message from $context.  It is HTML formatted and we don't need that for here, but it isn't nescarry to strip htmlt tags as its debug output.
	 * @return void We display a error.
	 */
	public static function ssi_on_error_method_cli(): void
	{
		global $context, $txt;

		echo "\n" . ($txt['covnert_fatal_error'] ?? 'A fatal error has occurred in SMF') . "\n";
		echo "---------------------------------------------\n";
		echo $context['error_message'];
		echo "\n---------------------------------------------\n";

		die();
	}

	/*
	 * Get the amounnt of time we have ran this script and display it.  To simplify it, we simply show a time formated string.
	 */
	public static function getElapsedTime(): string
	{
		global $txt;

		$elapsed = time() - Converter::getVar('TimeStarted');
		if ($elapsed < 86400)
			return gmdate("H:i:s", $elapsed);

		$d = explode('|', gmdate("z|H:i:s", $elapsed));
		return self::txt('convert_time_day', $d[0], $d[1]);
	}

	/**
	 * Helper method to try to handle errors, instead of SMF.
	 * @return void We display a error.
	*/
	public static function error_handler($error_level, $error_string, $file, $line): void
	{
		// Error was suppressed with the @-operator.
		if (error_reporting() == 0 || error_reporting() == (E_ERROR | E_PARSE | E_CORE_ERROR | E_COMPILE_ERROR | E_USER_ERROR | E_RECOVERABLE_ERROR))
			return;

		self::error(
			($error_level % 255 == E_ERROR ? 'Error' : ($error_level % 255 == E_WARNING ? 'Warning' : 'Notice'))
			. ': ' . $error_string . ' in ' . $file . ' on line ' . $line
		);
	}

	/*
	 * Load the text strings for the converter.
	 * In the future, this will simply load the correct language file from SMF.
	 */
	public function loadTxt()
	{
		global $txt;

		$txt['convert_utility'] = 'SMF Converter';
		$txt['convert_progress'] = 'Progress';
		$txt['convert_step'] = 'Step';
		$txt['convert_overall_progress'] = 'Overall Progress';
		$txt['convert_step_progress'] = 'Step Progress';
		$txt['convert_time_elapsed'] = 'Time Elapsed';
		$txt['convert_incomplete'] = 'Incomplete';
		$txt['convert_not_quite_done'] = 'Not quite done yet!';
		$txt['convert_paused_overload'] = 'This conversion has been paused to avoid overloading your server. Do not worry, nothing is wrong. Simply click the <label for="contbutt">continue button</label> below to keep going.';
		$txt['convert_note'] = 'Note!';
		$txt['convert_continue'] = 'Continue';
		$txt['convert_skip'] = 'Skip';
		$txt['convert_skipping'] = 'Skipping...';
		$txt['convert_skiped'] = '...Skipped';

		$txt['convert_step_selectscript'] = 'Select Script';
		$txt['convert_step_checkenv'] = 'Check Environment';
		$txt['convert_step_options'] = 'Configure Options';
		$txt['convert_step_database'] = 'Convert Database';
		$txt['convert_step_cleanup'] = 'Cleanup Database';
		$txt['convert_step_finish'] = 'Finish';

		$txt['convert_time_day'] = '%1$s days %2$s';
		$txt['convert_database_encountered_error'] = 'The database encountered an error on line %1$s.';
		$txt['convert_database_error_received'] = 'The error received was:';
		$txt['convert_databse_query_ran_was'] = 'The query ran was:';
		$txt['convert_backtrace_report'] = 'Backtrace report';

		$txt['convert_title_SantityChecks'] = 'Checking the environment';
		$txt['convert_unsupported_databases'] = 'The converter detected that you are using %1$s. The SMF Converter does not currently support this database type.';
		$txt['convert_unsupported_version'] = 'This converter tool requires %1$s or higher';
		$txt['convert_environment_sane'] = 'No issues with the environment detected.';

		$txt['convert_title_SelectScript'] = 'Which software are you using?';
		$txt['convert_no_scripts_found'] = 'The converter did not find any conversion data files.  Please check to see if the one you want is available for download at <a href="%1$s">$2$s</a>.  If it isn\'t, we may be able to write one for you - just ask us!';
		$txt['covnert_no_scripts_folder'] = 'After you download it, simply upload it into the same folder as <strong>this convert.php file</strong>.  If you\'re having any other problems with this converter, don\'t hesitate to look for help on our <a href="%1$s">community forum</a>.';
		$txt['convert_try_again'] = 'Try again';
		$txt['convert_multiple_found'] = 'The converter found multiple conversion data files.  Please choose the one you wish to use.';
		$txt['convert_not_found'] = 'It\'s not here!';
		$txt['convert_not_found_find_more'] = 'If the software you\'re looking for doesn\'t appear above, please check to see if it is available for download at <a href="%1$s">%2$s</a> or <a href="%3$s">Git repository</a>.  If it isn\'t, we may be able to write one for you - just ask us!';
		$txt['convert_not_found_help'] = 'If you\'re having any other problems with this converter, don\'t hesitate to look for help on our <a href="%1$s">community forum</a>.';

		$txt['convert_title_ConvertOptions'] = 'Configure the converter';
		$txt['convert_open_basedir'] = 'The converter detected that your host has open_basedir enabled on this server.  Please ask your host to disable this setting or try moving the contents of your %1$s to the public html folder of your site.';
		$txt['convert_from_settings_missing'] = 'Unable to find the settings for %1$s. Please double check the path and try again.';
		$txt['convert_bad_smf_db_passwd'] = 'The database password you entered was incorrect.  Please make sure you are using the right password (for the SMF user!) and try it again.  If in doubt, use the password from Settings.php in the SMF installation.';
		$txt['convert_from_database_no_access'] = 'Sorry, the database connection information used in the specified installation of SMF cannot access the installation of %1$s.  This may either mean that the installation doesn\'t exist, or that the Database account used does not have permissions to access it.';
		$txt['convert_option_flatfile'] = 'If the two softwares are installed in separate directories, the Database account SMF was installed using will need access to the other database.  Either way, both must be installed on the same Database server.';
		$txt['convert_option_crossdbreq'] = 'This script requires cross database joins.  Ensure your SMF database user has access to the %1$s database.';
		$txt['convert_option_info'] = 'The converter should only need to know where the two installations are, after which it should be able to handle everything for itself.';
		$txt['convert_option_pathto'] = 'Path to %1$s:';
		$txt['convert_option_fromFound'] = 'This may be the right path.';
		$txt['convert_option_fromNotFound'] = 'You will need to change the value in this box.';
		$txt['convert_option_convertDbPass'] = 'SMF database password:';
		$txt['convert_option_empty_error_log'] = 'Empty the convert error log?';
		$txt['convert_parital_conversion'] = 'Paritial Conversion:';
		$txt['convert_parital_conversion_info'] = 'If choosen, this will convert only the choosen sections.';
		$txt['convert_conversion_steps'] = 'Conversion steps:';

		$txt['convert_title_ConvertDatabase'] = 'Converting your forum';

		$txt['convert_title_ConvertDatabase'] = 'Cleaning up your forum';

		$txt['convert_title_FinishConvert'] = 'Conversion Complete';
		$txt['convert_completed'] = 'Conversion Complete!';
		$txt['convert_delete_script'] = 'Please delete this file as soon as possible for security reasons.';
		$txt['convert_finished_info'] = 'Congratulations, the conversion has completed successfully.  If you have or had any problems with this converter, or need help using SMF, please feel free to <a href="%1$s">look to us for support</a>.';
		$txt['convert_delete_script_box'] = 'Please check this box to delete the converter right now for security reasons.';
		$txt['convert_doesnt_work_on_all_servers'] = 'doesn\'t work on all servers.';
		$txt['convert_everything_done'] = 'Now that everything is converted over, <a href="%1$s">your SMF installation</a> should have all the posts, boards, and members from the %2$s installation.';
		$txt['convert_smooth_transition'] = 'We hope you had a smooth transition!';

		$txt['convert_unable_to_find_scripts'] = 'Unable to find the converter script.  Please double check the path and try again.';
		$txt['convert_missing_info_class'] = 'Missing information method, invalid class.';
		$txt['convert_invalid_info_class'] = 'Unable to find the converter script configuration.  Please double check the path and try again.';
		$txt['convert_invalid_smf_version'] = 'This converter is not available for your version of SMF.';

		$txt['covnert_fatal_error'] = 'A fatal error has occurred in SMF';
	}
}

/**
 * Our base class for all converter.  All converters will inherit this class.
 * This defines common/standard functions/variables we expect to find.
 * Converters can override these if needed.
 * We do use late static binding here
 */
class ConverterBase
{
	/*
	 * Extra HTML Entities we will undo, in addition to standard html entities
	 */
	public static array $unHtmlEntities = [
		'&#039;' => '\'',
		'&nbsp;' => ' '
	];

	/*
	 * Converters will typically run their own code to prepare the system, but we add some memory here
	 */
	public static function prepareSystem(): void
	{
		ini_set('memory_limit', '128M');

		// Provide some basic progress bars if we don't have one.
		if (count(static::stepWeights()) === 0)
		{
			for($totalSteps = 1; isset(static::${'convertStep' . $totalSteps . 'info'}); ++$totalSteps);

			// May procude slightly more than 100..
			$avg = ceil($totalSteps / 100);

			$stepWeights = [];
			for($i = 1; isset(static::${'convertStep' . $i . 'info'}); ++$i)
				$stepWeights['convertStep' . $i] = $avg;

			static::$stepWeightsBackup = $stepWeights;
		}
	}

	/*
	 * Converters may provide information about how heavy each step is in relation to a 100%.
	 * This allows the progress bars to provide user feedback about how far along we are in the process.
	 */
	public static array $stepWeightsBackup = [];
	public static function stepWeights(): array
	{
		return static::$stepWeightsBackup;
	}

	/*
	 * Converters will define this for any additional settings we need to load/process
	 */
	public static function loadConverterSettings(): void
	{
	}

	/*
	 * Connect to the from/source system database
	 */
	public static function connectDb()
	{
	}

	/*
	 * Add slasshes recursively to an array|string.  If this is a string, we just addslashes.
	 * This is not commonly used anymore.  SMF handles escaping data with the database layer.
	 *
	 * @param array|string $v The array|string we will add slashes on.
	 * @return array|string The slashed data.
	 */
	public static function addslashes_recursive($v)
	{
		return is_array($v) ? array_map('self::addslashes_recursive', $v) : addslashes($v);
	}

	/*
	 * Strip slasshes recursively to an array|string.  If this is a string, we just stripslashes.
	 * This is not commonly used anymore.  SMF handles escaping data with the database layer.
	 *
	 * @param array|string $v The array|string we will strip slashes on.
	 * @param bool $fixKeys Sometimes our keys got slashed, so we this option will also clean them.
	 * @return array|string The clean data.
	 */
	public static function stripslashes_recursive($var, bool $fixKeys = false)
	{
		if (empty($fixKeys))
			return is_array($var) ? array_map('self::stripslashes_recursive', $var) : stripslashes($var);
		else if (is_string($var))
			return stripslashes($var);

		$new_var = [];
		foreach ($var as $k => $v)
			$new_var[stripslashes($k)] = is_array($v) ? self::stripslashes_recursive($v, true) : stripslashes($v);
		return $new_var;
	}

	/*
	 * undo htmlspecialchars function.  This is using a more modern htmlspecialchars_decode but adds in our extra entities
	 *
	 * @param string $string the data we will undo.
	 * @param bool $usLegacy if true, we use a older method to do this.
	 */
	public static function un_htmlspecialchars(string $string, bool $useLegacy = false): string
	{
		if ($useLegacy)
			return strtr(
				$string,
				array_flip(get_html_translation_table(HTML_SPECIALCHARS, ENT_QUOTES))
					+ self::$unHtmlEntities
			);

		return strtr(htmlspecialchars_decode($string), self::$unHtmlEntities);
	}

	// Special metho to clear our attachments.
	/*
	 * Converters should call this when we want to strip out all attachments as it will also remove all physical files.
	 */
	public static function removeAllAttachments(): void
	{
		global $smcFunc;

		// !!! This should probably be done in chunks too.
		$result = ConverterDb::query('
			SELECT id_attach, filename, id_folder, file_hash
			FROM {to_prefix}attachments');
		while ($row = ConverterDb::fetch_assoc($result))
		{
			$physical_filename = getAttachmentFilename($row['filename'], $row['id_attach'], $row['id_folder'], false, $row['file_hash']);
			if (file_exists($physical_filename))
				@unlink($physical_filename);
		}
		ConverterDb::free_result($result);
	}

	/*
	 * Get the block size of the query.  This has a fallback to 500 if we can't find anything.
	 * We can also do a adjustment that will come from the admin to adjust the block size for faster/slow servers.
	 * The $blockSizes will contain an array with a key (such as topics/members/attachments) and return a int.
	 *
	 * @param string $the name of the block we are converting,
	 * @return int The size of the block data we will request.
	 */
	public static function getBlockSize(string $block): int
	{
		return (static::$blockSizes[$block] ?? 500) * (Converter::getVar('blockSizeAdjustment') ?? 1.0);
	}

	/*
	 * Converts html to bbc.  SMF doesn't use this, but there are sometimes legacy systems that have HTML where BBC should be used.
	 *
	 * @param string $msg The data we will convert.
	 * @return string The string with as much bbc conversion as possible done.
	 */
	public static function hmtl_to_bbc(string $data): string
	{
		global $smcFunc;
		return $smcFunc['htmlspecialchars'](strip_tags(html_to_bbc($data)));
	}

	/*
	 * Copy a directory to another.  Typically used if we are going to copy smileys or other images to SMF.
	 *
	 * @param string $source The source directory we will start from.
	 * @param string $dest The destination directory we will send files/folders to.
	 * @return True if this was successfull or not.
	 */
	public static function copy_dir(string $source, string $dest): bool
	{
		if (!is_dir($source) || !($dir = opendir($source)))
			return false;

		try
		{
			while ($file = readdir($dir))
			{
				if ($file == '.' || $file == '..')
					continue;

				// If we have a directory create it on the destination and copy contents into it!
				if (is_dir($source . '/' . $file))
				{
					if (!is_dir($dest))
						mkdir($dest, 0777);
					copy_dir($source . '/' . $file, $dest . '/' . $file);
				}
				else
				{
					if (!is_dir($dest))
						mkdir($dest, 0777);
					copy($source . '/' . $file, $dest . '/' . $file);
				}
			}
			closedir($dir);

			return true;
		}
		catch (exception $e)
		{
			return false;
		}
	}

	/*
	 * This does a conversion using a standard (non custom) set of instructions.
	 * This does all the heavy lifting, provides timeouts and progress bars.
	 * Any scripts using cusotm blocks, will have to do all the heavy lifting themselves.
	 *
	 * @param array $stepinfo All the data related to this step.
	 */
	public static function doConvert(array $stepinfo)
	{
		global $db_name;

		$currentStart = Converter::getVar('currentStart') ?? 0;

		// Purge the data.
		if (isset($stepinfo['purge']) && static::$purge && $currentStart == 0)
		{
			// Support either a closure, array of queries or a single query.
			if (isset($stepinfo['purge']['function']) && is_callable($stepinfo['purge']['function']))
				$stepinfo['purge']['function']();
			elseif (isset($stepinfo['purge']['query']) && is_array($stepinfo['purge']['query']))
				array_walk($stepinfo['purge']['query'], function ($q) {
					ConverterDb::query($q, $stepinfo['purge']['params'] ?? []);
				});
			elseif (isset($stepinfo['purge']['query']))
				ConverterDb::query(
					$stepinfo['purge']['query'],
					$stepinfo['purge']['params'] ?? []
				);

			// Reset the auto column.
			if (!empty($stepinfo['purge']['resetauto']))
			{
				$autos = (array) $stepinfo['purge']['resetauto'];

				array_walk($autos, function ($q) {
					if (empty($auto_col = ConverterDb::find_auto_col($q)))
						return;

					// This is postgresql, a bit more complicated, but it works.
					if (ConverterDb::IsTitle(POSTGRE_TITLE))
						ConverterDb::query(
							'SELECT setval(pg_get_serial_sequence({string:table}, {string:auto_col}), coalesce(max(id), 0) + 1, false) FROM ' . $q . ';',
							[
								'table' => $q,
								'auto_col' => $auto_col
						]);
					else
						ConverterDb::query('ALTER TABLE ' . $q . ' AUTO_INCREMENT = 1');
				});
			}
		}

		// We have a pre-process step we need to execute
		if (isset($stepinfo['pre_process']) && is_callable($stepinfo['pre_process']))
				$stepinfo['pre_process']();

		// FIgure out big our limit is.  This doesn't use $blockSizes as we can more easily just define it in the array of data..
		$limit = ($stepinfo['process']['limit'] ?? 500) * (Converter::getVar('blockSizeAdjustment') ?? 1.0);

		// Get a progress bar.
		if (isset($stepinfo['progress']))
		{
			if (isset($stepinfo['progress']['progress_query']))
			{
				$result = ConverterDb::query(
					$stepinfo['progress']['progress_query'],
					$stepinfo['progress']['progress_params'] ?? []
				);
				list($current_progress) = ConverterDb::db_fetch_row($result);
				ConverterDb::free_result($result);
			}
			else/*if (isset($stepinfo['progress']['use_counter']))*/
				$current_progress = &$currentStart;

			$result = ConverterDb::query(
				$stepinfo['progress']['total_query'],
				$stepinfo['progress']['total_params'] ?? []
			);
			list($total_items) = ConverterDb::db_fetch_row($result);
			ConverterDb::free_result($result);
		}

		while (true)
		{
			// Params we need.
			$params = $stepinfo['process']['params'] ?? [];

			// Add a limiter to the query..
			if (empty($stepinfo['process']['no_limit']))
			{
				$stepinfo['process']['query'] .= '
					LIMIT {int:offset}, {int:limit}';
				$params['offset'] = $currentStart;
				$params['limit'] = $limit;
			}

			$result = ConverterDb::query(
				$stepinfo['process']['query'],
				$params
			);
			$row_count = ConverterDb::num_rows($result);

			$block = [];
			while ($row = ConverterDb::fetch_assoc($result))
			{
				// Parse the row data.
				if (isset($stepinfo['process']['parse']) && is_callable($stepinfo['process']['parse']))
					$stepinfo['process']['parse']($row);

				$block[] = $row;
			}
			ConverterDb::free_result($result);

			if (!empty($block))
			{
				$columns = $stepinfo['process']['colulmns'] ?? array_keys($block[0]) ?? [];
				$keys = $stepinfo['process']['keys'] ?? $columns;

				// Do the inserts.
				ConverterDb::insert(
					$stepinfo['process']['table'],
					$columns,
					$block,
					$keys,
					$stepinfo['process']['method'] ?? 'insert'
				);
			}
			// We didn't get as many as our block size?  We are done.
			if ($row_count < $limit)
				break;

			// Check the time.
			Converter::pastTime(
				$currentStart += $row_count,
				static::updateSubStepProgress,
				[Converter::ld(), $current_progress, $total_items]
			);
		}

		// We have a pre-process step we need to execute
		if (isset($stepinfo['post_process']) && is_callable($stepinfo['post_process']))
			$stepinfo['post_process']();
	}

	/*
	 * This provides a dynamitcally moving sub step progress par based on our progress
	 *
	 * @param Converter $conv The current master converter object
	 * @param int $current_progress How many items we have processed so far.
	 * @param int $total_items The total amount of items we have to process.
	 */
	public static function updateSubStepProgress(Converter $conv, int $current_progress, int $total_items): void
	{
		$subStepProgress = $conv->$subStepProgress = ($current_progress / $total_items) * 100;
	}

	/*
	 * Convert a percentage into px for CSS magic.
	 *
	 * @param int The current percentage, this sometimes is sent as a string, so we let it be fixed later.
	 * @return int The number of pixels
	 */
	public static function convertPercent2px($percent): int
	{
		return intval(11 * (intval((int) $percent) / 100.0));
	}

	/*
	 * Conversions may need to access attachment information.  This simplifies the process and handles multiple attachment directories.
	 *
	 * @param int $id_folder If specified, we will use this folder.  Otherwise we will use the current one.
	 * @return string SMF's attachment directory.
	 */
	public static function getAttachmentDir(int $id_folder = 0): string
	{
		global $smcFunc;

		$result = ConverterDb::query('
			SELECT value
			FROM {to_prefix}settings
			WHERE variable = {literal:attachmentUploadDir}
			LIMIT 1');
		list ($attachmentUploadDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		$result = ConverterDb::query('
			SELECT value
			FROM {to_prefix}settings
			WHERE variable = {literal:currentAttachmentUploadDir}
			LIMIT 1');
		list ($currentAttachmentUploadDir) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		// String or unknown.
		if (strpos($attachmentUploadDir, '{"') === false)
			return $attachmentUploadDir;

		$dirs = $smcFunc['json_decode']($attachmentUploadDir, true);

		if ($id_folder > 0 && isset($dirs[$id_folder]))
			return $dirs[$id_folder];
		else
			return $dirs[$currentAttachmentUploadDir];
	}

	/*
	 * Get the next id_attach from our attachments table.
	 */
	public static function getLastAttachmentID(): int
	{
		$result = ConverterDb::query('
			SELECT MAX(id_attach) + 1
			FROM {to_prefix}attachments');
		list ($id_attach) = ConverterDb::fetch_row($result);
		ConverterDb::free_result($result);

		return empty($id_attach) ? 1 : $id_attach;
	}

	/*
	 * This is a useful tool that will determine how the base directory has shifted if the forum was moved
	 */
	public static function checkAndFixPath(string $path, string $basepath = ''): string
	{
		if (empty($basepath))
			$basepath = static::$basepath;

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

		return str_replace($basepath, Converter::getVar('convertPathFrom') . (static::$frompathappend ?? ''), $path) ;
	}
}

/*
 * This class holds all the database logic for the conversions.
 * This will hold the source and SMF database connections, prefixes and other data.
 * This will call the correct methods in SMF to run queries.
 * This will handle {to_prefix} and {from_prefix}
 */
class ConverterDb
{
	/**
	 * These variables are used by the converter to keep track of appilcation data.
	 *
	 * @var mixed
	 */
	private			$to_connection = null;
	private			$from_connection = null;
	private array	$smcFunc = [];
	private string	$toPrefix = '';

	/**
	 * Is SMF extended to handle additional functions?
	 *
	 * @var bool
	 */
	private bool	$isExtended = false;

	/**
	 * These calls require us to extend SMF.
	 */
	private array	$dbExtendMethods = [
		'db_add_column',
		'db_remove_column',
		'db_change_column',
		'db_add_index',
		'db_remove_index',
		'db_drop_table',
		'db_create_table'
	];

	/**
	 * These calls specify the table as the first argument.
	 */
	private array	$dbTblMethods = [
		'db_insert_id',
		'db_insert',
		'db_add_column',
		'db_remove_column',
		'db_change_column',
		'db_add_index',
		'db_remove_index',
		'db_drop_table',
		'db_create_table'
	];

	/**
	 * These calls use a result resource.
	 */
	private array	$dbResultMethods = [
		'db_fetch_row',
		'db_fetch_assoc',
		'db_num_rows',
		'db_free_result'
	];

	/**
	 * No params are passed to these calls.
	 */
	private array	$dbNoParamMethods = [
		'db_affected_rows'
	];

	/**
	 * Builds the class and stores a few things for later..
	 */
	public function __construct()
	{
		global $smcFunc, $db_connection;

		$this->toPrefix = Converter::getVar('toPrefix');
		$this->fromPrefix = Converter::getVar('fromPrefix');
		$this->smcFunc = &$smcFunc;
		$this->to_connection = &$db_connection;
	}

	/**
	 * Our master converter class will inform us when we have a connection to the source database.
	 *
	 * @param resource the database connection resource.
	 */
	public function setFromConnection($con)
	{
		$this->from_connection = $con;
	}

	/**
	 * Our master converter class will inform us when we have a connection to the source database.
	 *
	 * @param resource the database connection resource.
	 */
	public static function fromCon($conn)
	{
		return (self::load())->setFromConnection($conn);
	}

	/*
	 * If we find a from prefix and no to_prefix in the query, we will use the from prefix databse connection.
	 * If from prefix and to prefix are specified, we will be making a cross database query and the SMF databse user is the onwe making it.
	 *
	 * @param string $query A database query that we will check for these prefixes.
	 */
	public function findConnectionByQuery(string $query)
	{
		return stripos($query, '{from_prefix}') &&  stripos($query, '{to_prefix}') === false ? $this->from_connection : $this->to_connection;
	}

	/*
	 * Perform a database insert, but unlink SMF, we move the method to later one.
	 * This will try to find missing columns that are required and add them with blank values.
	 * This will take the columns and try to find the correct database type.
	 *
	 * @param string $table The database table we are inserting on.
	 * @param array $columns Columns we will be inserting with.
	 * @param array $data Multi-dimensional array of data we will be inserting.
	 * @param array $keys If specified, this is the keys we will be using.  Otherwise we will derive it from $columns.
	 * @param string $method When specified, we will insert with a different method than insert.  Currently 'replace' and 'ignore' are supported.
	 * @param int $returnmode SMF's returnmode specification.  Currently not used.
	 * @param resource $connection If specificed, uses the requested databse connection.
	 */
	public function db_insert(string $table, array $columns, array $data, array $keys = [], string $method = 'insert', int $returnmode = 0, $connection = null)
	{
		$conn = $this->findConnectionByQuery($table);
		$table = $this->replaceSpecial($table);

		// Try to find any columns we forgot to add and add them.
		$missingRequiredCols = $this->findColumnTypes($keys, $columns, $table);
		if (!empty($missingRequiredCols))
		{
			foreach ($missingRequiredCols as $col_name => $data_type)
			{
				$columns[$col_name] = $data_type;

				foreach ($data as $row => $d)
					$data[$row][$col_name] = '';
			}
		}

		return $this->smcFunc['db_insert'](
			$method,
			$table,
			$columns,
			$data,
			$keys,
			$returnmode,
			$connection ?? $conn
		);
	}

	/*
	 * Parses a query and returns it, does not execute it.
	 *
	 * @param string $db_string Query we are parsing.
	 * @param array $db_values Values we will inject into the query.
	 * @param resource $connection If specificed, uses the requested databse connection.
	 */
	public function db_quote(string $db_string, array $db_values = [], $connection = null)
	{
		return $this->smcFunc['db_quote']($this->replaceSpecial($db_string), $db_values, $connection ?? $this->findConnectionByQuery($db_string));
	}

	/*
	 * Executes a query and returns the resource or error if it fails.
	 *
	 * @param string $db_string Query we are parsing.
	 * @param array $db_values Values we will inject into the query.
	 * @param bool $return_error If true, we will return even if a error occurs.
	 * @param resource $connection If specificed, uses the requested databse connection.
	 */
	public function db_query(string $db_string, array $db_values = [], bool $return_error = false, $db_connection = null)
	{
		$conn = $this->findConnectionByQuery($db_string);
		$db_string = $this->replaceSpecial($db_string);

		// Add some values..
		if (!isset($db_values['overide_security']))
			$db_values['overide_security'] = true;
		if (!isset($db_values['db_error_skip']))
			$db_values['db_error_skip'] = true;

		$result = $this->smcFunc['db_query'](
			'',
			$db_string,
			$db_values,
			$db_connection ?? $conn
		);

		if ($result !== false || $return_error)
			return $result;

		Converter::error('Query failed', true, $this->db_quote($db_string, $db_values), $db_connection ?? $conn);
	}

	/*
	 * Magic method to wrap all of our calls over to $smcFunc with the args.
	 * This will do logic to figure out which order we do some replaces against.
	 *
	 * @param string $method The $smcFunc method we will execute
	 * @param array $args All args to be passed to the method.
	 */
	public function __call(string $method, $args)
	{
		// We need to extend SMF to have more $smcFuncs
		if (in_array($method, $this->dbExtendMethods) && !$this->isExtended)
			$this->extendDb();

		// We are only going to support these right now for changing stuff.
		if (in_array($method, $this->dbTblMethods))
		{
			// The first arg has the table.
			$args[0] = $this->replaceSpecial($args[0]);
			return $this->smcFunc[$method](...$args);
		}
		// Result based methods.
		if (in_array($method, $this->dbResultMethods))
			return $this->smcFunc[$method](...$args);
		// We support these, but no params to worry about.
		elseif (in_array($method, $this->dbNoParamMethods))
			return $this->smcFunc[$method]();
	}

	/*
	 * Magic method to wrap all of our calls over to the object with the args.
	 * This will call the various objects or possibly the __call magic method.
	 *
	 * @param string $method The $smcFunc method we will execute
	 * @param array $args All args to be passed to the method.
	 */
	public static function __callStatic(string $method, $args)
	{
		return (self::load())->{'db_' . $method}(...$args);
	}

	/*
	 * Take a request and return a single row from the results.
	 *
	 * @param result A database query result.
	 * @param int $offset the number of rows to offset.
	 * @param string $field the field we need to get.
	 * @return mixed The data received.
	 */
	public function db_result($request, int $offset = 0, string $field_name = '')
	{
		// Pg has this..
		if ($this->smcFunc['db_title'] == 'PostgreSQL')
			return pg_fetch_result($request, $offset, $field_name);
		else
		{
			$request->data_seek($offset);
			$row = $request->fetch_array();
			return $row[$field_name];
		}
	}

	/*
	 * Does special replacements for {to_prefix} and {from_prefix}
	 *
	 * @param string $query the query string we will parse.
	 * @param bool $prefixOnly ***FUTURE*** We can limit our requests to just prefixes, incase we have other special replacements later.
	 * @return string the parsed string
	 */
	private function replaceSpecial(string $query, bool $prefixOnly = false): string
	{
		$database_keywords = [
			'{to_prefix}' => $this->toPrefix,
			'{from_prefix}' => $this->fromPrefix
		];

		return str_replace(array_keys($database_keywords), array_values($database_keywords), $query);
	}

	/*
	 * When called, we will extend SMF with additional tools.
	 * This sets a variable to avoid additional calls later for optimization.
	 */
	private function extendDb(): void
	{
		$this->isExtended = true;
		db_extend('packages');
	}

	/*
	 * Given a table, find the auto increment column.
	 *
	 * @param string $table the table we will want to search.
	 * @return string the auto column or a blank string.
	 */
	private function db_find_auto_col(string $table): string
	{
		$table = $this->replaceSpecial($table);

		if (!$this->isExtended)
			$this->extendDb();

		$column_info = $this->smcFunc['db_list_columns']($table, true, ['no_prefix' => true]);

		foreach ($column_info as $col)
			if (!empty($col['auto']))
				break;

		return $col['name'] ?? '';
	}

	/*
	 * This will take the keys and columns and build a list of data types.
	 * As well it process keys and return any missing required columsn to be aded later.
	 *
	 * @param array (pointer) $keys The table key columns.
	 * @param array (pointer) $columns All the columns we have.
	 * @param string $table The table we are working with.
	 */
	private function findColumnTypes(array &$keys, array &$columns, string $table)
	{
		if (!$this->isExtended)
			$this->extendDb();

		$keys = $columns;
		$columns = $temp = $missingRequiredCols = [];

		$column_info = $this->smcFunc['db_list_columns']($table, true);

		foreach ($column_info as $col)
		{
			// Only get the useful ones.
			if (
				in_array($col['name'], $keys)
				|| ($col['not_null'] && is_null($col['default']) && !in_array($col['name'], $keys) && empty($col['auto']))
			)
			{
				if ($col['type'] == 'varbinary' && stripos($col['name'], 'ip') !== false)
					$data_type = 'inet';
				elseif (in_array($col['type'], ['float', 'string', 'int', 'date']))
					$data_type = $col['type'];
				elseif (in_array($col['type'], ['tinyint', 'smallint', 'mediumint', 'bigint']))
					$data_type = 'int';
				else
					$data_type = 'string';

				$temp[$col['name']] = $data_type;

				// Is this required but missing?
				if ($col['not_null'] && !in_array($col['name'], $keys))
					$missingRequiredCols[$col['name']] = $data_type;
			}
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

		return $missingRequiredCols;
	}

	/*
	 * Compare the database title and return if it matches
	 *
	 * @param string Database title we are matching.
	 * @return bool True If it matches else false
	 */
	public static function IsTitle(string $title): bool
	{
		global $smcFunc;
		return $smcFunc['db_title'] === $title;
	}

	/*
	 * Initialize the converter datbase object.
	 */
	public static function load(): self
	{
		if (!isset($GLOBALS['converterdb']))
			$GLOBALS['converterdb'] = new self();
		return $GLOBALS['converterdb'];
	}
}

/*
 * This is the cleanup tasks performed by the converter.
 * This operates just like a converter in its execution.
 */
class CleanupDatabase extends ConverterBase
{
	public static function stepWeights(): array
	{
		return [
			'convertStep1' => 6, // Correct boards with incorrect msg ids
			'convertStep2' => 7, // Correct any incorrect groups
			'convertStep3' => 3, // Update our statitics
			'convertStep4' => 12, // Correct any posts groups
			'convertStep5' => 13, // Correct all board topics/post counts
			'convertStep6' => 10, // Removing any topics that have zero messages
			'convertStep7' => 11, // Correct the number of replies
			'convertStep8' => 7, // Fix the Categories and board layout
			'convertStep9' => 2, // Correct category orders
			'convertStep10' => 9, // Reorder boards
			'convertStep11' => 10, // Correct any incorrect attachments
			'convertStep12' => 7, // Rebuilding indexes for topics
			'convertStep13' => 3, // Fix board permission view
		];
	}

	public static array $blockSizes = [
		'convertStep6' => 200,
		'convertStep7' => 200,
		'convertStep11' => 500,
	];

	public static function prepareSystem(): void
	{
		global $sourcedir;

		// Make sure we have the function "getMsgMemberID"
		require_once($sourcedir . '/Subs-Boards.php');
	}

	public static string 	$convertStep1info = 'Correct boards with incorrect msg ids';
	public static function	convertStep1(): void
	{
		$request = ConverterDb::query('
			SELECT id_board, MAX(id_msg) AS id_last_msg, MAX(modified_time) AS last_edited
			FROM {to_prefix}messages
			GROUP BY id_board');
		$modifyData = $modifyMsg = [];
		while ($row = ConverterDb::fetch_assoc($request))
		{
			ConverterDb::query('
				UPDATE {to_prefix}boards
				SET id_last_msg = {int:id_last_msg}, id_msg_updated = {int:id_msg_updated}
				WHERE id_board = {int:id_board}',
				[
					'id_last_msg' => $row['id_last_msg'],
					'id_msg_updated' => $row['id_last_msg'],
					'id_board' => $row['id_board']
			]);
			$modifyData[$row['id_board']] = array(
				'last_msg' => $row['id_last_msg'],
				'last_edited' => $row['last_edited'],
			);
			$modifyMsg[] = $row['id_last_msg'];
		}
		ConverterDb::free_result($request);

		// Are there any boards where the updated message is not the last?
		if (!empty($modifyMsg))
		{
			Converter::debugMsg('Correct any boards that do not show the correct last message');

			$request = ConverterDb::query('
				SELECT id_board, id_msg, modified_time, poster_time
				FROM {to_prefix}messages
				WHERE id_msg IN ({array_int:modifyMsg})',
				[
					'modifyMsg' => $modifyMsg,
			]);
			while ($row = ConverterDb::fetch_assoc($request))
			{
				// Have we got a message modified before this was posted?
				if (max($row['modified_time'], $row['poster_time']) < $modifyData[$row['id_board']]['last_edited'])
				{
					// Work out the ID of the message (This seems long but it won't happen much.
					$request2 = ConverterDb::query('
						SELECT id_msg
						FROM {to_prefix}messages
						WHERE modified_time = {int:modified_time}
						LIMIT ',
						[
							'modified_time' => $modifyData[$row['id_board']]['last_edited']
					]);
					if (ConverterDb::num_rows($request2) != 0)
					{
						list ($id_msg) = ConverterDb::fetch_row($request2);

						ConverterDb::query('
							UPDATE {to_prefix}boards
							SET id_msg_updated = {int:id_msg_updated}
							WHERE id_board = {int:id_board}
							LIMIT 1',
							[
								'id_msg_updated' => $id_msg,
								'id_board' => $row['id_board']
						]);
					}
					ConverterDb::free_result($request2);
				}
			}
			ConverterDb::free_result($request);
		}
	}

	public static string 	$convertStep2info = 'Correct any incorrect groups';
	public static function	convertStep2(): void
	{
		$request = ConverterDb::query('
			SELECT id_group
			FROM {to_prefix}membergroups
			WHERE min_posts = -1');
		$all_groups = [];
		while ($row = ConverterDb::fetch_assoc($request))
			$all_groups[] = $row['id_group'];
		ConverterDb::free_result($request);

		$request = ConverterDb::query('
			SELECT id_board, member_groups
			FROM {to_prefix}boards
			WHERE FIND_IN_SET(0, member_groups)');
		while ($row = ConverterDb::fetch_assoc($request))
			ConverterDb::query('
				UPDATE {to_prefix}boards
				SET member_groups = {string:member_groups}
				WHERE id_board = {int:id_board}
				LIMIT 1',
				[
					'member_groups' => implode(',', array_unique(array_merge($all_groups, explode(',', $row['member_groups'])))),
					'id_board' => $row['id_board']
			]);
		ConverterDb::free_result($request);
	}

	public static string 	$convertStep3info = 'Update our statitics';
	public static function	convertStep3(): void
	{
		// Get the number of messages...
		$result = ConverterDb::query('
			SELECT COUNT(*) AS total_messages, MAX(id_msg) AS max_msg_id
			FROM {to_prefix}messages');
		$row = ConverterDb::fetch_assoc($result);
		ConverterDb::free_result($result);

		// Update the latest member.  (highest id_member)
		$result = ConverterDb::query('
			SELECT id_member AS latest_member, real_name AS latest_real_name
			FROM {to_prefix}members
			ORDER BY id_member DESC
			LIMIT 1');
		if (ConverterDb::num_rows($result))
			$row += ConverterDb::fetch_assoc($result);
		ConverterDb::free_result($result);

		// Update the member count.
		$result = ConverterDb::query('
			SELECT COUNT(*) AS total_members
			FROM {to_prefix}members');
		$row += ConverterDb::fetch_assoc($result);
		ConverterDb::free_result($result);

		// Get the number of topics.
		$result = ConverterDb::query('
			SELECT COUNT(*) AS total_topics
			FROM {to_prefix}topics');
		$row += ConverterDb::fetch_assoc($result);
		ConverterDb::free_result($result);

		ConverterDb::insert(
			'{to_prefix}settings',
			['variable', 'value'],
			[
				['latest_member', $row['latest_member']],
				['latest_real_name', $row['latest_real_name']],
				['total_members', $row['total_members']],
				['total_messages', $row['total_messages']],
				['max_msg_id', $row['max_msg_id']],
				['total_topics', $row['total_topics']],
				['disable_hash_time', time() + 7776000],
			],
			['variable'], // Keys
			'replace'
		);
	}

	public static string 	$convertStep4info = 'Correct any posts groups';
	public static function	convertStep4(): void
	{
		$currentStart = Converter::getVar('currentStart');

		$request = ConverterDb::query('
			SELECT id_group, min_posts
			FROM {to_prefix}membergroups
			WHERE min_posts != -1
				AND id_group >= {int:id_group}
			ORDER BY min_posts DESC',
			[
				'id_group' => $currentStart
		]);
		$post_groups = [];
		while ($row = ConverterDb::fetch_assoc($request))
			$post_groups[$row['min_posts']] = $row['id_group'];
		ConverterDb::free_result($request);

		$request = ConverterDb::query('
			SELECT id_member, posts
			FROM {to_prefix}members');
		$mg_updates = [];
		while ($row = ConverterDb::fetch_assoc($request))
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
		ConverterDb::free_result($request);

		foreach ($mg_updates as $group_to => $update_members)
		{
			ConverterDb::query('
				UPDATE {to_prefix}members
				SET id_post_group = {int:id_post_group}
				WHERE id_member IN ({array_int:update_members})',
				[
					'id_post_group' => $group_to,
					'update_members' => $update_members
			]);

			ConverterDb::pastTime(++$currentStart);
		}
	}

	public static string 	$convertStep5info = 'Correct all board topics/post counts';
	public static function	convertStep5(): void
	{
		$currentStart = Converter::getVar('currentStart');
		// Needs to be done separately for each board.
		$result_boards = ConverterDb::query('
			SELECT id_board
			FROM {to_prefix}boards
			WHERE id_board >= {int:id_board}',
			[
				'id_board' => $currentStart
		]);
		$boards = [];
		while ($row_boards = ConverterDb::fetch_assoc($result_boards))
			$boards[] = $row_boards['id_board'];
		ConverterDb::free_result($result_boards);

		foreach ($boards as $id_board)
		{
			// Get the number of topics, and iterate through them.
			$result_topics = ConverterDb::query('
				SELECT COUNT(*)
				FROM {to_prefix}topics
				WHERE id_board = {int:id_board}',
				[
					'id_board' => $id_board
			]);
			list ($num_topics) = ConverterDb::fetch_row($result_topics);
			ConverterDb::free_result($result_topics);

			// Find how many messages are in the board.
			$result_posts = ConverterDb::query('
				SELECT COUNT(*)
				FROM {to_prefix}messages
				WHERE id_board = {int:id_board}',
				[
					'id_board' => $id_board
			]);
			list ($num_posts) = ConverterDb::fetch_row($result_posts);
			ConverterDb::free_result($result_posts);

			// Fix the board's totals.
			ConverterDb::query('
				UPDATE {to_prefix}boards
				SET num_topics = {int:num_topics}, num_posts = {int:num_posts}
				WHERE id_board = {int:id_board}',
				[
					'num_topics' => $num_topics,
					'num_posts' => $num_posts,
					'id_board' => $id_board
			]);

			ConverterDb::pastTime(++$currentStart);
		}
	}

	public static string 	$convertStep6info = 'Removing any topics that have zero messages';
	public static function	convertStep6(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$resultTopic = ConverterDb::query('
				SELECT t.id_topic, COUNT(m.id_msg) AS num_msg
				FROM {to_prefix}topics AS t
					LEFT JOIN {to_prefix}messages AS m ON (m.id_topic = t.id_topic)
				GROUP BY t.id_topic
				HAVING num_msg = 0
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('convertStep6')
			]);
			$numRows = ConverterDb::num_rows($resultTopic);

			if ($numRows > 0)
			{
				$stupidTopics = [];
				while ($topicArray = ConverterDb::fetch_assoc($resultTopic))
					$stupidTopics[] = $topicArray['id_topic'];
				ConverterDb::query('
					DELETE FROM {to_prefix}topics
					WHERE id_topic IN ({array_int:topics})',
					[
						'topics' => $stupidTopics
				]);
				ConverterDb::query('
					DELETE FROM {to_prefix}log_topics
					WHERE id_topic IN ({array_int:topics})',
					[
						'topics' => $stupidTopics
				]);
			}
			ConverterDb::free_result($resultTopic);

			if ($numRows < self::getBlockSize('convertStep6'))
				break;

			Converter::pastTime($currentStart += self::getBlockSize('convertStep6'));
		}
	}

	public static string 	$convertStep7info = 'Correct the number of replies';
	public static function	convertStep7(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$resultTopic = ConverterDb::query('
				SELECT
					t.id_topic, MIN(m.id_msg) AS myid_first_msg, t.id_first_msg,
					MAX(m.id_msg) AS myid_last_msg, t.id_last_msg, COUNT(m.id_msg) - 1 AS my_num_replies,
					t.num_replies
				FROM {to_prefix}topics AS t
					LEFT JOIN {to_prefix}messages AS m ON (m.id_topic = t.id_topic)
				GROUP BY t.id_topic
				HAVING id_first_msg != myid_first_msg OR id_last_msg != myid_last_msg OR num_replies != my_num_replies
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('convertStep7')
			]);

			$numRows = ConverterDb::num_rows($resultTopic);

			while ($topicArray = ConverterDb::fetch_assoc($resultTopic))
			{
				$memberStartedID = getMsgMemberID($topicArray['myid_first_msg']);
				$memberUpdatedID = getMsgMemberID($topicArray['myid_last_msg']);

				ConverterDb::query('
					UPDATE {to_prefix}topics
					SET id_first_msg = {int:id_first_msg},
						id_member_started = {int:id_member_started}, id_last_msg = {int:id_last_msg},
						id_member_updated = {int:id_member_updated}, num_replies = {int:num_replies}
					WHERE id_topic = {int:id_topic}
					LIMIT 1',
					[
						'id_first_msg' => $topicArray['myid_first_msg'],
						'id_member_started' => $memberStartedID,
						'id_last_msg' => $topicArray['myid_last_msg'],
						'id_member_updated' => $memberUpdatedID,
						'num_replies' => $topicArray['my_num_replies'],
						'id_topic' => $topicArray['id_topic']
				]);
			}
			ConverterDb::free_result($resultTopic);

			if ($numRows < self::getBlockSize('convertStep7'))
				break;

			Converter::pastTime($currentStart += self::getBlockSize('convertStep7'));
		}
	}

	public static string 	$convertStep8info = 'Fix the Categories and board layout';
	public static function	convertStep8(): void
	{
		// First, let's get an array of boards and parents.
		$request = ConverterDb::query('
			SELECT id_board, id_parent, id_cat
			FROM {to_prefix}boards');
		$child_map = [];
		$cat_map = [];
		while ($row = ConverterDb::fetch_assoc($request))
		{
			$child_map[$row['id_parent']][] = $row['id_board'];
			$cat_map[$row['id_board']] = $row['id_cat'];
		}
		ConverterDb::free_result($request);

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

				$child_map[0] = array_merge(isset($child_map[0]) ? $child_map[0] : [], $dummy);
				unset($child_map[$parent]);
			}
		}

		// The above id_parents and id_cats may all be wrong; we know id_parent = 0 is right.
		$solid_parents = array(array(0, 0));
		$fixed_boards = [];
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
			ConverterDb::query('
				UPDATE {to_prefix}boards
				SET id_parent = {int:id_parent}, id_cat = {int:id_cat}, child_level = {int:child_level}
				WHERE id_board = {int:id_board}',
				[
					'id_parent' => (int) $fix[0],
					'id_cat' => (int) $fix[1],
					'child_level' => (int) $fix[2],
					'id_board' => (int) $board
			]);
		}

		// Leftovers should be brought to the root.  They had weird parents we couldn't find.
		if (count($fixed_boards) < count($cat_map))
			ConverterDb::query('
				UPDATE {to_prefix}boards
				SET child_level = 0, id_parent = 0' . (empty($fixed_boards) ? '' : '
				WHERE id_board NOT IN ({array_int:boards})'),
				[
					'boards' => array_keys($fixed_boards),
			]);

		// Last check: any boards not in a good category?
		$request = ConverterDb::query('
			SELECT id_cat
			FROM {to_prefix}categories');
		$real_cats = [];
		while ($row = ConverterDb::fetch_assoc($request))
			$real_cats[] = $row['id_cat'];
		ConverterDb::free_result($request);

		$fix_cats = [];
		foreach ($cat_map as $board => $cat)
			if (!in_array($cat, $real_cats))
				$fix_cats[] = $cat;

		if (!empty($fix_cats))
		{
			ConverterDb::insert(
				'{db_prefix}categories',
				['name'],
				[['name' => 'General Category']],
				['name']
			);
			$catch_cat = ConverterDb::insert_id('{db_prefix}categories');

			ConverterDb::query('
				UPDATE {to_prefix}boards
				SET id_cat = {int:new_cat}
				WHERE id_cat IN ({array_int:bad_cats})',
				[
					'new_cat' => (int) $catch_cat,
					'bad_cats' => array_unique($fix_cats)
			]);
		}
	}

	public static string 	$convertStep9info = 'Correct category orders';
	public static function	convertStep9(): void
	{
		$request = ConverterDb::query('
			SELECT c.id_cat, c.cat_order, b.id_board, b.board_order
			FROM {to_prefix}categories AS c
				LEFT JOIN {to_prefix}boards AS b ON (b.id_cat = c.id_cat)
			ORDER BY c.cat_order, b.child_level, b.board_order, b.id_board');
		$cat_order = $board_order = $curCat = -1;
		while ($row = ConverterDb::fetch_assoc($request))
		{
			if ($curCat != $row['id_cat'])
			{
				$curCat = $row['id_cat'];
				if (++$cat_order != $row['cat_order'])
					ConverterDb::query('
						UPDATE {to_prefix}categories
						SET cat_order = {int:cat_order}
						WHERE id_cat = {int:id_cat}',
						[
							'cat_order' => $cat_order,
							'id_cat' => $row['id_cat']
					]);
			}
			if (!empty($row['id_board']) && ++$board_order != $row['board_order'])
				ConverterDb::query('
					UPDATE {to_prefix}boards
					SET board_order = {int:board_order}
					WHERE id_board = {int:id_board}
					LIMIT 1',
					[
						'board_order' => $board_order,
						'id_board' => $row['id_board']
				]);
		}
		ConverterDb::free_result($request);
	}

	public static string 	$convertStep10info = 'Reorder boards';
	public static function	convertStep10(): void
	{
		global $user_info;
		$user_info['query_see_board'] = '1=1';

		// THIS CALLS getBoardTree, which  needs {query_see_board} setup.
		// Update our BoardOrder
		reorderBoards();
	}

	public static string 	$convertStep11info = 'Correct any incorrect attachments';
	public static function	convertStep11(): void
	{
		$request = ConverterDb::query('
			SELECT COUNT(*)
			FROM {to_prefix}attachments');
		list ($attachments) = ConverterDb::fetch_row($request);
		ConverterDb::free_result($request);

		$currentStart = Converter::getVar('currentStart');

		while ($currentStart < $attachments)
		{
			$request = ConverterDb::query('
				SELECT id_attach, filename, attachment_type
				FROM {to_prefix}attachments
				WHERE id_thumb = 0
					AND (RIGHT(filename, 4) IN ({array_string:imgexts3}) OR RIGHT(filename, 5) = {string:jpeg})
					AND width = 0
					AND height = 0
				LIMIT {int:offset}, {int:limit}',
				[
					'imgexts3' => ['.gif', '.jpg', '.png', '.bmp'],
					'jpeg' => '.jpeg',
					'offset' => $currentStart,
					'limit' => self::getBlockSize('convertStep6')
			]);

			if (ConverterDb::num_rows($request) == 0)
				break;
			while ($row = ConverterDb::fetch_assoc($request))
			{
				if ($row['attachment_type'] == 1)
				{
					$request2 = ConverterDb::query('
						SELECT value
						FROM {to_prefix}settings
						WHERE variable = {literal:custom_avatar_dir}');
					list ($custom_avatar_dir) = ConverterDb::fetch_row($request2);
					ConverterDb::free_result($request2);

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
					ConverterDb::query('
						UPDATE {to_prefix}attachments
						SET
							size = {int:size},
							width = {int:width},
							height = {int:height}
						WHERE id_attach = {int:id_attach}
						LIMIT 1',
						[
							'size' => (int) $filesize,
							'width' => (int) $size[0],
							'height' => (int) $size[1],
							'id_attach' => $row['id_attach']
					]);
			}
			ConverterDb::free_result($request);

			Converter::pastTime($currentStart += self::getBlockSize('convertStep11'));
		}
	}

	public static string 	$convertStep12info = 'Rebuilding indexes for topics';
	public static function	convertStep12(): void
	{
		$indexes = ConverterDb::list_indexes('{to_prefix}topics', true, ['no_prefix' => true]);

		if (!isset($indexes['PRIMARY']))
			ConverterDb::add_index(
				'{to_prefix}topics',
				[
					'type' => 'PRIMARY',
					'columns' => ['id_topic']
				],
				['no_prefix' => true]
			);
		if (!isset($indexes['last_message']))
			ConverterDb::add_index(
				'{to_prefix}topics',
				[
					'type' => 'UNIQUE',
					'name' => 'last_message',
					'columns' => ['id_last_msg', 'id_board']
				],
				['no_prefix' => true]
			);
		if (!isset($indexes['first_message']))
			ConverterDb::add_index(
				'{to_prefix}topics',
				[
					'type' => 'UNIQUE',
					'name' => 'first_message',
					'columns' => ['id_first_msg', 'id_board']
				],
				['no_prefix' => true]
			);
		if (!isset($indexes['poll']))
			ConverterDb::add_index(
				'{to_prefix}topics',
				[
					'type' => 'UNIQUE',
					'name' => 'poll',
					'columns' => ['id_poll', 'id_topic']
				],
				['no_prefix' => true]
			);
		if (!isset($indexes['is_sticky']))
			ConverterDb::add_index(
				'{to_prefix}topics',
				[
					'type' => 'INDEX', // no key
					'name' => 'is_sticky',
					'columns' => ['is_sticky']
				],
				['no_prefix' => true]
			);
		if (!isset($indexes['id_board']))
			ConverterDb::add_index(
				'{to_prefix}topics',
				[
					'type' => 'INDEX', // no key
					'name' => 'id_board',
					'columns' => ['id_board']
				],
				['no_prefix' => true]
			);
	}

	public static string 	$convertStep13info = 'Fix board permission view';
	public static function	convertStep13(): void
	{
		$currentStart = Converter::getVar('currentStart');

		while (true)
		{
			$inserts = [];
			// Find all areas where we believe the board view permissions are wrong.
			$results = ConverterDb::query('
					SELECT
						b.id_board,
						b.member_groups,
						pv.mbrgrp
					FROM {to_prefix}boards AS b
					LEFT JOIN (
						SELECT
							xpv.id_board, 
							GROUP_CONCAT(xpv.id_group ORDER BY xpv.id_group) AS mbrgrp
						FROM {to_prefix}board_permissions_view AS xpv
							GROUP BY xpv.id_board
						) AS pv ON pv.id_board = b.id_board
					WHERE 
						pv.id_board IS NULL
						OR b.member_groups != pv.mbrgrp
				LIMIT {int:offset}, {int:limit}',
				[
					'offset' => $currentStart,
					'limit' => self::getBlockSize('convertStep7')
			]);

			$numRows = ConverterDb::num_rows($results);

			while ($row = ConverterDb::fetch_assoc($results))
				foreach (explode(',', $row['member_groups']) as $id_group)
					$inserts[] = [
						'id_group' => (int) $id_group,
						'id_board' => (int) $row['id_board'],
						'deny' => 0
					];
			ConverterDb::free_result($results);

			ConverterDb::insert(
				'{to_prefix}board_permissions_view',
				array_keys($inserts[0]),
				$inserts,
				array_keys($inserts[0]),
				'replace'
			);

			if ($numRows < self::getBlockSize('convertStep13'))
				break;

			Converter::pastTime($currentStart += self::getBlockSize('convertStep13'));
		}

		if (!empty($inserts))
			ConverterDb::insert(
				'{to_prefix}board_permissions_view',
				array_keys($inserts[0]),
				$inserts,
				array_keys($inserts[0]),
				'replace'
			);
	}
}

function template_convert_above()
{
	global $context, $txt, $settings;

	echo '<!DOCTYPE html>
<html', $txt['lang_rtl'] == true ? ' dir="rtl"' : '', '>
<head>
	<meta charset="', isset($txt['lang_character_set']) ? $txt['lang_character_set'] : 'UTF-8', '">
	<meta name="robots" content="noindex">
	<title>', Converter::getVar('pageTitle'), '</title>
	<link rel="stylesheet" href="', $settings['default_theme_url'], '/css/index.css">
	<link rel="stylesheet" href="', $settings['default_theme_url'], '/css/install.css">
	', $txt['lang_rtl'] == true ? '<link rel="stylesheet" href="' . $settings['default_theme_url'] . '/css/rtl.css">' : '', '
	<script src="https://ajax.googleapis.com/ajax/libs/jquery/', JQUERY_VERSION, '/jquery.min.js"></script>
	<script src="', $settings['default_theme_url'], '/scripts/script.js"></script>
	<script>
		var smf_scripturl = \'', Converter::getVar('upgradeurl'), '\';
		var smf_charset = \'UTF-8\';
		var startPercent = ', Converter::getVar('overallPercent'), ';
		var allow_xhjr_credentials = false;

		// This function dynamically updates the step progress bar - and overall one as required.
		function updateStepProgress(current, max, overall_weight)
		{
			// What out the actual percent.
			var width = parseInt((current / max) * 100);
			if (document.getElementById(\'step_progress\'))
			{
				document.getElementById(\'step_progress\').style.width = width + "%";
				setInnerHTML(document.getElementById(\'step_text\'), width + "%");
			}
			if (overall_weight && document.getElementById(\'overall_progress\'))
			{
				overall_width = parseInt(startPercent + width * (overall_weight / 100));
				document.getElementById(\'overall_progress\').style.width = overall_width + "%";
				setInnerHTML(document.getElementById(\'overall_text\'), overall_width + "%");
			}
		}
	</script>
</head>
<body>
	<div id="footerfix">
	<div id="header">
		<h1 class="forumtitle">', Converter::getVar('pageTitle'), '</h1>
		<img id="smflogo" src="', $settings['default_theme_url'], '/images/smflogo.svg" alt="Simple Machines Forum" title="Simple Machines Forum">
	</div>
	<div id="wrapper">
		<div id="content_section">
			<div id="main_content_section">
				<div id="main_steps">
					<h2>', $txt['convert_progress'], ' - ', Converter::getVar('script')['name'] ?? '', '</h2>
					<ul class="steps_list">';

	foreach (Converter::getVar('steps') as $num => $step)
		echo '
						<li', $num == Converter::getVar('currentStep') ? ' class="stepcurrent"' : '', '>
							', $txt['convert_step'], ' ', $step[0], ': ', $txt[$step[1]], '
						</li>';

	echo '
					</ul>
				</div><!-- #main_steps -->

				<div id="install_progress">
					<div id="progress_bar" class="progress_bar progress_green">
						<h3>', $txt['convert_overall_progress'], '</h3>
						<div id="overall_progress" class="bar" style="width: ', Converter::getVar('overallPercent'), '%;"></div>
						<span id="overall_text">', Converter::getVar('overallPercent'), '%</span>
					</div>';

	if (Converter::getVar('overallPercent') > -1)
		echo '
					<div id="progress_bar_step" class="progress_bar progress_yellow">
						<h3>', $txt['convert_step_progress'], '</h3>
						<div id="step_progress" class="bar" style="width: ', Converter::getVar('stepProgress') > -1 ? Converter::getVar('stepProgress') : 0, '%;"></div>
						<span id="step_text">', Converter::getVar('stepProgress') > -1 ? Converter::getVar('stepProgress') : 0, '%</span>
					</div>';

	echo '
					<div id="substep_bar_div" class="progress_bar ', Converter::getVar('subStepProgress') > -1 ? '' : 'hidden', '">
						<h3 id="substep_name">', Converter::getVar('subStepProgressName'), '</h3>
						<div id="substep_progress" class="bar" style="width: ', Converter::getVar('subStepProgress') > -1 ? Converter::getVar('subStepProgress') : 0, '%;"></div>
						<span id="substep_text">', Converter::getVar('subStepProgress') > -1 ? Converter::getVar('subStepProgress') : 0, '%</span>
					</div>';

	// How long have we been running this?
	echo '
					<div class="smalltext time_elapsed">
						', $txt['convert_time_elapsed'], ':
						<span id="time_elasped">', Converter::getElapsedTime(), '</span>
					</div>';
	echo '
				</div><!-- #install_progress -->
				<div id="main_screen" class="clear">
					<h2>', Converter::getVar('sectionTitle'), '</h2>
					<div class="panel">
						<form action="', Converter::getVar('converturl'), '" method="post" name="convform" id="convform">';
}

// Show the footer.
function template_convert_below()
{
	global $upcontext, $txt;

	echo '
							<input type="hidden" name="step" value="' . (Converter::getVar('currentStep') + (Converter::getVar('nextStep') ?? 0)) . '" />
							<input type="hidden" name="substep" value="' . Converter::getVar('currentSubStep') . '" />
							<input type="hidden" name="currentStart" value="' . Converter::getVar('currentStart') . '" />';

	if (!empty(Converter::getVar('pause')))
		echo '
							<em>', $txt['convert_incomplete'], '.</em><br>

							<h2 style="margin-top: 2ex;">', $txt['convert_not_quite_done'], '</h2>
							<h3>
								', $txt['convert_paused_overload'], '
							</h3>';

	if (!empty(Converter::getVar('CustomWarning')))
		echo '
							<div class="errorbox">
								<h3>', $txt['convert_note'], '</h3>
								', Converter::getVar('CustomWarning'), '
							</div>';

	echo '
							<div class="righttext buttons">';

	if (Converter::getVar('continue'))
		echo '
								<input type="submit" id="contbutt" name="contbutt" value="', $txt['convert_continue'], '"', Converter::getVar('disableContinue') ? ' disabled' : '', ' class="button">';
	if (Converter::getVar('allowSkip'))
		echo '
								<input type="submit" id="skip" name="skip" value="', $txt['convert_skip'], '" onclick="dontSubmit = true; document.getElementById(\'contbutt\').disabled = \'disabled\'; return true;" class="button">';

	echo '
							</div>
						</form>
					</div><!-- .panel -->
				</div><!-- #main_screen -->
			</div><!-- #main_content_section -->
		</div><!-- #content_section -->
	</div><!-- #wrapper -->
	</div><!-- #footerfix -->
	<div id="footer">
		<ul>
			<li class="copyright"><a href="https://www.simplemachines.org/" title="Simple Machines Forum" target="_blank" rel="noopener">SMF &copy; ' . SMF_SOFTWARE_YEAR . ', Simple Machines</a></li>
		</ul>
	</div>';

	// Are we on a pause?
	if (Converter::getVar('pause'))
	{
		echo '
	<script>
		window.onload = doAutoSubmit;
		var countdown = 3;
		var dontSubmit = false;

		function doAutoSubmit()
		{
			if (countdown == 0 && !dontSubmit)
				document.convform.submit();
			else if (countdown == -1)
				return;

			document.getElementById(\'contbutt\').value = "', $txt['convert_continue'], ' (" + countdown + ")";
			countdown--;

			setTimeout("doAutoSubmit();", 1000);
		}
	</script>';
	}

	echo '
</body>
</html>';
}

function template_convert_SantityChecks()
{
	global $txt;

	echo '
		<p>', $txt['convert_environment_sane'], '</p>';
}

function template_convert_SelectScript()
{
	global $context, $txt;

	if (empty($context['converter_scripts']))
	{
		echo '
			<h3>', Converter::txt('convert_no_scripts_found', 'https://www.simplemachines.org', 'www.simplemachines.org'), '</h3>

			<p>', Converter::txt('covnert_no_scripts_folder', 'https://www.simplemachines.org/community/'), '</p>
			<br />
			<a href="', Converter::getVar('converturl'), '?step=1">', $txt['convert_try_again'], '</a>';
	}
	else
	{
		echo '
			<h3>', $txt['convert_multiple_found'], '</h3>

			<ul>';

		foreach ($context['converter_scripts'] as $script)
			echo '
				<li><a href="', Converter::getVar('converturl'), '?step=2;convert_script=', $script['path'], '">', $script['name'], '</a> <em>(', $script['path'], ')</em></li>';

		echo '
			</ul>

			<h2>', $txt['convert_not_found'], '</h2>
			<h3>', Converter::txt('convert_not_found_find_more', 'https://www.simplemachines.org/community/', 'www.simplemachines.org', 'https://github.com/SimpleMachines/converters'), '</h3>

			<p>', Converter::txt('convert_not_found_help', 'https://www.simplemachines.org/community/'), '</p>';
	}
}

function template_convert_ConvertOptions()
{
	global $context, $txt;

	if (empty($context['script']['flatfile']))
		echo '
		<div style="margin-bottom: 2ex;">', $txt['convert_option_flatfile'], '</div>';

	if (!empty($context['script']['crossdbreq']))
		echo '
		<div style="margin-bottom: 2ex;">', Converter::txt('convert_option_crossdbreq', $script['name']), '</div>';

	echo '
		<h3>', $txt['convert_option_info'], '</h3>
		<dl class="settings">';

	if (!empty($context['script']['settings']))
	{
		echo '
			<dt>
				<label for="convertPathFrom">Path to ', Converter::txt('convert_option_pathto', $context['script']['name']), '</label>
			</dt>
			<dd>
				<input type="text" name="convertPathFrom" id="convertPathFrom" value="', Converter::getVar('convertPathFrom'), '" size="60" class="input_text" />
				<div class="smalltext">', !empty($context['fromFound']) ? $txt['convert_option_fromFound'] : $txt['convert_option_fromNotFound'], '</div>
			</dd>';
	}

	if (!empty($context['script']['parameters']))
	{
		foreach ($context['script']['parameters'] as $param)
		{
			if ($param['type'] == 'checked' || $param['type'] == 'checkbox')
				echo '
			<dt>
				<label for="parameters[', $param['id'], ']">', $param['label'], ':</label>
			</dt>
			<dd>
				<input type="checkbox" name="parameters[', $param['id'], ']" id="parameters_', $param['id'], '" value="1"', $param['type'] == 'checked' ? ' checked="checked"' : '', ' class="input_check" />
				', (!empty($param['info']) ? '<div class="smalltext">' . $param['info'] . '</div>' : '') , '
			</dd>';
			// How about a list?
			elseif (($param['type'] == 'list' || $param['type'] == 'select') && isset($param['options']) && is_array($param['options']))
			{
				echo '
			<dt>
				<label for="parameters[', $param['id'], ']">', $param['label'], ':</label>
			</dt>
			<dd>
				<select name="parameters[', $param['id'], ']" id="parameters_', $param['id'], '">';

				foreach ($param['options'] as $id => $option)
					echo '
					<option value="', $id, '"', (isset($param['default_option']) && $param['default_option'] == $id ? ' selected="selected"' : ''), '>', $option, '</option>';

				echo '
				</select>
				<div class="smalltext">', $txt['install_settings_reg_mode_info'], '</div>
			</dd>';
			}
			// Super secret data.
			elseif ($param['type'] == 'password')
				echo '
			<dt>
				<label for="parameters[', $param['id'], ']">', $param['label'], ':</label>
			</dt>
			<dd>
				<input type="password" name="parameters[', $param['id'], ']" id="parameters_', $param['id'], '" value="" size="60" class="input_password" />
				<div class="smalltext">', $txt['db_settings_password_info'], '</div>
			</dd>';
			// Fall back to text.
			else
				echo '
			<dt>
				<label for="parameters[', $param['id'], ']">', $param['label'], ':</label>
			</dt>
			<dd>
				<input type="text" name="parameters[', $param['id'], ']" id="parameters_', $param['id'], '" value="" size="60" class="input_text" />
				<div class="smalltext">', $txt['db_settings_password_info'], '</div>
			</dd>';
		}
	}

	// Prompt for the SMF Database password.
	echo '
			<dt>
				<label for="convertDbPass">', $txt['convert_option_convertDbPass'], '</label>
			</dt>
			<dd>
				<input type="password" name="convertDbPass" id="convertDbPass" value="" size="60" class="input_password" autofill="new-password" />
				<div class="smalltext">The Database password (for verification only).</div>
			</dd>
			<dt>
				<label for="empty_error_log">', $txt['convert_option_empty_error_log'], '</label>
			</dt>
			<dd>
				<input type="checkbox" name="empty_error_log" id="empty_error_log" value="1" class="input_check" />
				', (!empty($param['info']) ? '<div class="smalltext">' . $param['info'] . '</div>' : '') , '
			</dd>';

	echo '
		</dl>';

	// Now for the steps.
	if (!empty($context['steps']) && Converter::getVar('allowParitalConverts') ?? false)
	{
			echo '
		<h2>', $txt['convert_parital_conversion'], '</h2>
		<h3>', $txt['convert_parital_conversion_info'], '</h3>
		<dl class="settings">';

		// !!! TODO: Make this work.
		foreach ($context['steps'] as $key => $step)
			echo '
			<dt>
				<label for="doSteps[', $key, ']">', $step, ':</label>
			</dt>
			<dd>
				<input type="checkbox" name="doSteps[', $key, ']" id="doStep_', $key, '" value="1" checked="checked" class="input_check" />
			</dd>';

		echo '
		</dl>';
	}
	elseif (!empty($context['steps']) && Converter::getVar('showSteps') ?? false)
	{
			echo '
		<h2>', $txt['convert_conversion_steps'], '</h2>
		<ul>';

		// !!! TODO: Make this work.
		foreach ($context['steps'] as $key => $step)
			echo '
			<li>', $step, '</li>';

		echo '
		</li>';
	}
}

function template_convert_ConvertDatabase()
{
	global $context;

	echo '
		<ul id="msgItems">';

	foreach ($context['msgItems'] as $msg)
		echo '
			<li>', $msg, '</li>';

	echo '
		</ul>
		<input type="hidden" name="currentStart" value="' . Converter::getVar('currentStart') . '" />';}

function template_convert_FinishConvert()
{
	global $context, $boardurl, $txt;

	echo '
		<h3>', Converter::txt('convert_finished_info', 'https://www.simplemachines.org/community'), '</h3>';

	if (!empty($context['can_delete_self']))
		echo '
		<div style="margin: 1ex; font-weight: bold;">
			<label for="delete_self"><input type="checkbox" id="delete_self" onclick="doTheDelete();" class="input_check" />', $txt['convert_delete_script_box'], '</label> (', $txt['convert_doesnt_work_on_all_servers'], ')
		</div>
		<script type="text/javascript"><!-- // --><![CDATA[
			function doTheDelete()
			{
				var theCheck = document.getElementById ? document.getElementById("delete_self") : document.all.delete_self;
				var tempImage = new Image();

				tempImage.src = "', Converter::getVar('converturl'), '?delete=1&" + (new Date().getTime());
				tempImage.width = 0;
				theCheck.disabled = true;
			}
		// ]]></script>
		<br />';

	echo '
		<p>', Converter::txt('convert_everything_done', $boardurl . '/index.php', $context['script']['name']), '</p>
		<p>', $txt['convert_smooth_transition'], '</p>';
}