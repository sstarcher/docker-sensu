<?php

require_once(__DIR__ . '/httpful.phar');

abstract class SensuArvatoHandler {

    protected $_event_infos = array('id' => 'SENSU event id', 'action' => 'SENSU event action', 'timestamp' => 'SENSU event timestamp', 'last_state_change' => 'SENSU event last state change', 'last_ok' => 'SENSU event last ok');
    protected $_client_infos = array('remedy_app' => 'Application',
        'remedy_component' => 'Component',
        'chef' => array(
            'endpoint' => 'Chef endpoint',
            'environment' => 'Chef environment',
            'organisation' => 'Chef organisation',
        ),
        'cloud' => array(
            'provider' => 'Cloud provider',
            'local_ipv4' => 'Cloud local ip',
            'public_ipv4' => 'Cloud public ip'
        ),
        'ec2' => array(
            'az' => 'Cloud availabilty zone',
            'instance_id' => 'Cloud instance id'
        )
    );
    protected $_check_infos = array('name' => 'Check name', 'command' => 'Check command', 'history' => 'Check history', 'occurrences' => 'Check max occurrences', 'total_state_change' => 'Check total status changes', 'executed' => 'Check executed date', 'duration' => 'Check duration', 'output' => 'Check output');
    protected $_min_history_count = 10;
    protected $_event = null;
    protected $_stashes = null;
    protected $_silenced = null;
    protected $_events = null;
    protected $_aggregate = null;
    protected $_handler_config = null;
    protected $_api_url = 'http://localhost:4567';
    protected $_needed_event_fields = array('id', 'client', 'check', 'action', 'timestamp');
    protected $_allowed_event_actions = array('create', 'resolve', 'flapping');
    protected $_needed_config_fields = array('live', 'debug', 'simulate');
    protected $silent = false;

    private function _readEvent() {
        $stdin = fopen('php://stdin', 'r');
        $inputs_json = '';
        // Read all of stdin.
        while ($line = fgets($stdin)) {
            $inputs_json .= $line;
        }
        fclose($stdin);
        $this->_event = json_decode($inputs_json, true);

        foreach ($this->_needed_event_fields as $key) {
            if (!isset($this->_event[$key])) {
                throw new Exception('Event structure is invalid, missing ' . $key . ' key');
            }
        }

        if (!in_array($this->_event['action'], $this->_allowed_event_actions)) {
            throw new Exception('Event structure is invalid, unknown action ' . $this->_event['action'] . '');
        }

        $this->log("Event was parsed as " . var_export($this->_event, true), "debug");

        return $this->_event;
    }

    public function getEvent() {
        return $this->_event;
    }

    public function getEvents() {
        if (!is_null($this->_events))
            return $this->_events;

        try {
            $response = \Httpful\Request::get($this->_api_url . '/events')->expectsJson()->send();
            if ($response->code > 299)
                throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');

            $this->log("Got response code " . $response->code . " from sensu api", "debug");

            $this->_events = $response->body;

            $this->log("Found " . count($this->_events) . " events", "debug");
        } catch (Exception $e) {
            $this->log("Could not read events due to: " . $e->getMessage(), "error");
            return array();
        }

        return $this->_events;
    }

    public function getStashes() {
        if (!is_null($this->_stashes))
            return $this->_stashes;

        try {
            $response = \Httpful\Request::get($this->_api_url . '/stashes')->expectsJson()->send();
            if ($response->code > 299)
                throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');

            $this->log("Got response code " . $response->code . " from sensu api", "debug");

            $this->_stashes = $response->body;

            $this->log("Found " . count($this->_stashes) . " stashes", "debug");
        } catch (Exception $e) {
            $this->log("Could not read stashes due to: " . $e->getMessage(), "error");
            return array();
        }

        return $this->_stashes;
    }

    public function getSilenced() {
        if (!is_null($this->_silenced))
            return $this->_silenced;

        try {
            $response = \Httpful\Request::get($this->_api_url . '/silenced')->expectsJson()->send();
            if ($response->code > 299)
                throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');

            $this->log("Got response code " . $response->code . " from sensu api", "debug");

            $this->_silenced = $response->body;

            $this->log("Found " . count($this->_silenced) . " silenced", "debug");
        } catch (Exception $e) {
            $this->log("Could not read silenced due to: " . $e->getMessage(), "error");
            return array();
        }

        return $this->_silenced;
    }

    protected function _inMaintenance() {
        $event = $this->getEvent();
        $stashes = $this->getStashes();
        $silenced = $this->getSilenced();

        $maintenance_path = array(
            join('/', array(
                'silence',
                $event['client']['name']
            )),
            join('/', array(
                'silence',
                $event['client']['name'],
                $event['check']['name']
            )),
            join('/', array(
                'silence',
                $event['check']['name']
            )),
            join('/', array(
                'silence',
                $this->getHandlerName()
            )),
            join('/', array(
                'maintenance',
                $event['client']['name']
            )),
            join('/', array(
                'maintenance',
                $event['client']['name'],
                $event['check']['name']
            )),
            join('/', array(
                'maintenance',
                $event['check']['name']
            ))
        );

        // check stash
        foreach ($stashes as $stash) {
            foreach ($maintenance_path as $check_path) {
                if ($stash->path == $check_path) {
                    $this->log("Matched stash " . $stash->path . " ", "debug");
                    return true;
                }
            }
        }

        // check silenced
        foreach ($silenced as $silence) {
            if ($silence->subscription == "client:" . $this->getHandlerName()) {
                $this->log("Matched silence " . $silence->subscription . " ", "debug");
                return true;
            }
        }

        return false;
    }

    protected function _hasMinimumHistory() {
        $event = $this->getEvent();

        if (count($event['check']['history']) < $this->_min_history_count) {
            $this->log("Event history contains  " . count($event['check']['history']) . " entires but limit is " . $this->_min_history_count, "debug");
            return false;
        }
        return true;
    }

    protected function _hasDependentEvent() {
        $event = $this->getEvent();

        if (!isset($event['check']['dependencies'])) {
            return false;
        }

        if (count($event['check']['dependencies']) == 0) {
            return false;
        }

        $otherevents = $this->getEvents();

        foreach ($otherevents as $otherevent) {
            if ($event['id'] == $otherevent->id)
                continue;
            if (!$event['client']['name'] == $otherevent->client->name)
                continue;

            foreach ($event['check']['dependencies'] as $dependency) {
                if ($otherevent->check->name == $dependency) {
                    $this->log("Matched dependency " . $dependency . " in event " . $otherevent->id, "debug");
                    return true;
                }
            }
        }

        return false;
    }

    abstract protected function _handleCreate();

    abstract protected function _handleResolve();

    abstract public function getHandlerName();

    public function getHandlerConfig() {
        return $this->_handler_config;
    }

    public function handle() {
        $event = $this->_readEvent();

        switch ($event['action']) {
            case 'flapping':
            case 'create':
                return $this->_handleCreate();
                break;
            case 'resolve':
                return $this->_handleResolve();
                break;
        }

        return 1;
    }

    protected function _getLogFields() {
        $event = $this->getEvent();
        $fields = array();
        if (!is_array($event))
            return $fields;
        $fields['event'] = $event;
        /*
          if (isset($event['id'])) {
          $fields['event']['id'] = $event['id'];
          }
          if (isset($event['action'])) {
          $fields['event']['action'] = $event['action'];
          }
          if (isset($event['occurrences'])) {
          $fields['event']['occurrences'] = $event['occurrences'];
          }
          if (isset($event['status'])) {
          $fields['event']['status'] = $event['status'];
          }
          if (isset($event['client']['name'])) {
          $fields['event']['client']['name'] = $event['client']['name'];
          }
          if (isset($event['check']['name'])) {
          $fields['event']['check']['name'] = $event['check']['name'];
          }
         */

        return $fields;
    }

    public function log($msg, $level = "info") {
        $event = $this->getEvent();
        $config = $this->getHandlerConfig();
        if ($level != 'debug' || $config['debug']) {
            if (!$this->_silent)
                echo trim($msg) . "\n";

            $log = array_merge(array(
                "timestamp" => date("c"),
                "level" => $level,
                "message" => trim($msg)
                    ), $this->_getLogFields());

            if (PHP_VERSION_ID < 70000) {
                $log['function'] = (string) next(debug_backtrace())['function'];
                $log['class'] = (string) next(debug_backtrace())['class'];
            }

            file_put_contents("/var/log/sensu/sensu-" . $this->getHandlerName() . ".log", json_encode($log) . "\n", FILE_APPEND);
        }
    }

    public function getShortText() {
        $event = $this->getEvent();

        $text = 'SENSU check ' . $event['check']['name'] . ' on server ' . $event['client']['name'];
        if($this->getAutoscalingGroupName()) {
          $text = 'SENSU check ' . $event['check']['name'] . ' on autoscaling group ' . $this->getAutoscalingGroupName();
        }

        switch ($event['action']) {
            case 'create':
                return $text . ' failed';
                break;
            case 'resolve':
                return $text . ' failed';
                break;
            case 'flapping':
                return $text . ' failed';
                break;
        }

        throw new Exception('Unknown action ' . $event['action']);
    }

    public function getLongText() {
        $event = $this->getEvent();
        $details = '';

        foreach ($this->_event_infos as $key => $value) {
            if (!isset($event[$key])) {
                continue;
            }

            switch ($key) {
                case 'last_state_change':
                case 'last_ok':
                case 'timestamp':
                    if ($event[$key] > 0) {
                        $details .= $value . ': ' . date('r', $event[$key]) . "\n";
                    }
                    break;
                default:
                    $details .= $value . ': ' . $event[$key] . "\n";
                    break;
            }
        }

        $details .= "\n";

        foreach ($this->_client_infos as $key => $value) {
            if (!isset($event['client'][$key])) {
                continue;
            }
            if (is_array($value)) {
                foreach ($value as $key2 => $value2) {
                    if (!isset($event['client'][$key][$key2])) {
                        continue;
                    }
                    $details .= $value2 . ': ' . $event['client'][$key][$key2] . "\n";
                }
            } else {
                $details .= $value . ': ' . $event['client'][$key] . "\n";
            }
        }

        $details .= "\n";

        foreach ($this->_check_infos as $key => $value) {
            if (!isset($event['check'][$key])) {
                continue;
            }

            switch ($key) {
                case 'history':
                    $details .= $value . ': ' . implode(',', $event['check'][$key]) . "\n";
                    break;
                case 'issued':
                case 'executed':
                    if ($event['check'][$key] > 0) {
                        $details .= $value . ': ' . date('r', $event['check'][$key]) . "\n";
                    }
                    break;
                default:
                    $details .= $value . ': ' . $event['check'][$key] . "\n";
                    break;
            }
        }
        return $details;
    }

    public function getTodoText() {
        $event = $this->getEvent();

        if (isset($event['client']['todo'])) {
            return $event['client']['todo'];
        }

        if (isset($event['check']['todo'])) {
            return $event['check']['todo'];
        }

        return 'Todo not defined on sensu check or client level';
    }

    public function getAutoscalingGroupName() {
        $event = $this->getEvent();

        if (!isset($event['client']['tags']['aws:autoscaling:groupName'])) {
            return null;
        }

        return $event['client']['tags']['aws:autoscaling:groupName'];
    }

    public function getAggregrateName() {
        $event = $this->getEvent();

        if (!isset($event['check']['aggregate'])) {
            return null;
        }

        $name = $event['check']['name'];
        if (is_string($event['check']['aggregate'])) {
            $name = $event['check']['aggregate'];
        }

        return $name;
    }

    public function getAggregrate() {
        $name = $this->getAggregrateName();
        if (is_null($name)) {
            return null;
        }

        if (!is_null($this->_aggregate)) {
            return $this->_aggregate;
        }

        try {
            $response = \Httpful\Request::get($this->_api_url . '/aggregates/' . $name)->expectsJson()->send();
            if ($response->code > 299)
                throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');

            $this->log("Got response code " . $response->code . " from sensu api", "debug");

            $this->_aggregate = $response->body;

            $this->log("Found aggregate " . $name . " with content " . var_export($this->_aggregate, true), "debug");
        } catch (Exception $e) {
            $this->log("Could not read aggregates due to: " . $e->getMessage(), "error");
            return null;
        }

        return $this->_aggregate;
    }

    protected function _isCritical() {
        $event = $this->getEvent();
        if (isset($event['check']['is_critical']) && $event['check']['is_critical'] == true) {
            $this->log("Event is critical due to custom check field is_critical", "debug");
            return true;
        }
        if (isset($event['client']['is_critical']) && $event['client']['is_critical'] == true) {
            $this->log("Event is critical due to custom client field is_critical", "debug");
            return true;
        }
        $aggregate = $this->getAggregrate();
        if (is_null($aggregate)) {
            $this->log("Event is not critical due to missing aggregate", "debug");
            return false;
        }
        if (!isset($aggregate->clients) || !isset($aggregate->results)) {
            $this->log("Event is not critical due to missing clients or results fields", "error");
            return false;
        }
        if ($aggregate->clients == 0) {
            $this->log("Event is critical due to 0 clients", "info");
            return true;
        }

        $max_critical = round($aggregate->clients * 0.50);
        $max_warning = round($aggregate->clients * 0.80);

        if ($aggregate->results->critical >= $max_critical) {
            $this->log("Event is critical due to too many critical aggregation results", "info");
            return true;
        }

        if ($aggregate->results->warning >= $max_warning) {
            $this->log("Event is critical due to too many warning aggregation results", "info");
            return true;
        }

        return false;
    }

    public function createEvent(Array $event) {

        try {
            # create event
            $response = \Httpful\Request::post($this->_api_url . '/results')->sendsJson()->body(json_encode($event))->send();

            if ($response->code > 299)
                throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');

            $this->log("Got response code " . $response->code . " from sensu api", "debug");
        } catch (Exception $e) {
            $this->log("Could not create event due to: " . $e->getMessage(), "error");
        }

        return true;
    }

    public function __construct($silent = false) {
        $filename = '/etc/sensu/conf.d/' . $this->getHandlerName() . '.json';
        if (file_exists($filename)) {
            $config = json_decode(file_get_contents($filename), true);
            if (!isset($config[$this->getHandlerName()]))
                throw new Exception("$filename does not contain " . $this->getHandlerName() . " section\n");
            $this->_handler_config = $config[$this->getHandlerName()];
            if (!isset($this->_handler_config['debug']))
                $this->_handler_config['debug'] = false;
            foreach ($this->_needed_config_fields as $key) {
                if (!isset($this->_handler_config[$key])) {
                    throw new Exception('Config structure is invalid, missing ' . $key . ' key');
                }
            }
        } else {
            throw new Exception("$filename does not exist\n");
        }
        $filename = '/etc/sensu/conf.d/api.json';
        if (file_exists($filename)) {
            $config = json_decode(file_get_contents($filename), true);
            if (isset($config['api']['host']) && isset($config['api']['port'])) {
                $this->_api_url = 'http://' . $config['api']['host'] . ':' . $config['api']['port'];
            }
        }
        $this->_silent = $silent;
    }

}
