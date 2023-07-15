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

/*
 * This class should match the file name except we do not need the "convert_" or the extension.
 * This should extend the ConverterBase always.
 */
class mybb18x_to_smf extends ConverterBase
{
	/*
	 * The info method is critical as it contains all the information we need to present to the conversion process
	 */
	public static function info(): array
	{
		return [
			// Name of the source software
			'name' => 'SampleSoft 1.2',
			// The SMF version this was written for.
			'version' => 'SMF 2.1.*',
			// On th e source software, the configuraiton file.  We can specify mulitple files.
			'settings' => ['/Settings.php', '/Special.php'],
			// We can specify any globals.  This will be called when we need to work with the config files or do something like database loading.
			'globals' => ['config'],
			// Add any defines.  These are called prior to loading any files from the source software.  If a equals is present, we will use that as the value for the define, otherwise its 1.
			'defines' => ['MYSOFT', 'TEST=1']
			// If this is a falt file system,
			'flatfile' => true,
			// This is the format of our from prefix for conversion.
			'from_prefix' => '`{$dbname}`.{$dbprefix}',
			// Inform the system we will need cross database joins.
			'crossdbreq' => true,
			// We will perform a test against this database to verify we can access the database.
			'test_table' => '{from_prefix}users',
			// Additional parameters to converter script.
			'parameters' => [
				[
					// The id of the param, this is also used in the input variable.
					'id' => 'purge',
					// The type of variable this is.
					'type' => 'checked',
					// A label for it.
					'label' => 'Clear current SMF posts and members during conversion.',
				],
			],
		];
	}
	
	/*
	 * When we are getting ready to do stuff, we will attempt to connect to this database.
	 * We do this because we can support cross database systems (mysql to postgresql) in the future.
	 */
	public static function connectDb(): object
	{
		global $config;

		return smf_db_initiate(
			$config['hostname'],
			$config['database'],
			$config['username'],
			$config['password'],
			$config['table_prefix']
		);
	}

	/*
	 * Prior to starting the conversion logic, this will execute and allow us to do any additional checks/setups we need.
	 */
	public static function prepareSystem(): void
	{
		// We should always call the parent up.
		parent::prepareSystem();

		// A good example is we get the parameter (from our info) and store if for later use.
		self::$purge = Converter::getParameter('purge') ?? false;
	}

	/*
	 * Provides a title to the converter for this step
	 */
	public static string	$convertStep999info = 'TITLE';

	/*
	 * This will provide a standard conversion script logic using a standarized setup
	 */
	public static function	convertStep999(): array
	{
		return [
			// If specified, we will purge data prior to the start (start=0)
			'purge' => [
				// The query we will execute.
				'query' => 'TRUNCATE {to_prefix}messages',
				// We can also specify this as an array.
				'query' => ['TRUNCATE {to_prefix}messages','TRUNCATE {to_prefix}topics']
				// We can also request a reset of the auto column.
				'resetauto' => '{to_prefix}messages',
				// As well, also can be a array.
				'resetauto' => ['{to_prefix}messages','{to_prefix}topics']
			],
			// If specified, this will provide a progress indicator for the start logic.
			'progress' => [
				// Execute a query to tell how much we have done.
				'progress_query' => 'SELECT COUNT(*) FROM {to_prefix}messages WHERE id_msg > {int:myParam}',
				// We can also pass params
				'progress_params' => ['myParam' => 1],
				// If you want to use the 'start' parameter, set this to true and do not provide any progress_query
				'use_counter' => false,
				// Execute a query to tell how much we have done.
				'total_query' => 'SELECT COUNT(*) FROM {from_prefix}posts'
				// Don't forget we can also pass params
				'total_params' => ['myParam' => 1],
			],
			// Prior to the start of the conversion loop, we will call this.  Typically used if we need to get any logic ready for later.
			// This will get called with each page load.
			'pre_process' => function () {
			},
			'process' => [
				// The table we are putting data into.
				'table' => '{to_prefix}messages',
				// If you specify this, no limit is added on.  Should be avoided.
				'no_limit' => false,
				// This allows us to parse a row to change/format data as needed prior to inserting it.
				// $row should be passed by reference as we do not return.
				'parse' => function (&$row) {
					$row['body'] = html_to_bbc($row['body']);
				},
				// If this is provided, we will use these for the columns.  Otherwise we will dynamically figure it out.
				'colulmns' => [],
				// If this is provided, we will use these for the keys.  Otherwise we will dynamically figure it out.
				'keys' => [],
				// You can specify what method we are using.  It defaults to insert, but you can choose ignore or replace.
				'method' => 'insert',
				// The query we will be running.  We do not need to specify the LIMIT or offset, this is handled for us.
				'query' => '
					SELECT
						pm.msg_id AS id_pm,
						pm.user_id AS id_member,
						{string:defaultLabel} AS labels,
						CASE pm.pm_unread WHEN 1 THEN 0 ELSE 1 END AS is_read,
						pm.pm_deleted AS deleted
					FROM {from_prefix}privmsgs_to AS pm',
				// Additional params to pass to the query
				'params' => [
					'defaultLabel' => '-1',
				],
			],
			// This is called after the conversion is done.  Due to the timeouts, this will only get executed at the very end
			'post_process' => function () {
			},
		];
	}

	/*
	 * If you call a 'custom' block, you will have to do all the heavy lifting for processing the logic.
	 * The converter assumes when it can exit this block of code normally, it is finished and moves onto the next step.
	 * If you need to do timeouts, you will handle this (hint: Converter::pastTime($start);
	 * You can acccess anything statically through Converter and ConverterDb.
	 * If you reference itself, you can use self.  static is only needed by the base class for late static bindings.
	 */
	public static function	 convertStep999Custom(): void;
}