#!/usr/bin/php
<?php

require_once(__DIR__ . '/classes/sensu_client.php');

$handler = new SensuClientCleanup(true);

exit($handler->cleanup());
