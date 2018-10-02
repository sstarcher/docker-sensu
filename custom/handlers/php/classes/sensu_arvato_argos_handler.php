<?php

require_once(__DIR__ . '/httpful.phar');
require_once(__DIR__ . '/aws.phar');
require_once(__DIR__ . '/sensu_arvato_handler.php');

class SensuArvatoArgosHandler extends SensuArvatoHandler {

    protected $_needed_config_fields = array('live', 'debug', 'simulate', 'api_key', 'url', 'op_tool_kit');
    private $_severity_mapping = array(0 => 'WARNING', 1 => 'MINOR', 2 => 'CRITICAL');

    public function getHandlerName() {
        return 'argos';
    }

    public function getContainerName() {
        ## Gültiger Komponentenname
        $event = $this->getEvent();
        $component = 'CLDPAWSMGMT01';
        if (isset($event['client']['ec2']['tags']['component'])) {
            $component = $event['client']['ec2']['tags']['component'];
        }
        if (isset($event['client']['ec2']['tags']['Component'])) {
            $component = $event['client']['ec2']['tags']['Component'];
        }
        if (isset($event['client']['tags']['component'])) {
            $component = $event['client']['tags']['component'];
        }
        if (isset($event['client']['tags']['Component'])) {
            $component = $event['client']['tags']['Component'];
        }
        if (isset($event['client']['component'])) {
            $component = $event['client']['component'];
        }
        if (isset($event['client']['Component'])) {
            $component = $event['client']['Component'];
        }
        if (isset($event['check']['tags']['component'])) {
            $component = $event['check']['tags']['component'];
        }
        if (isset($event['check']['tags']['Component'])) {
            $component = $event['check']['tags']['Component'];
        }
        if (isset($event['check']['component'])) {
            $component = $event['check']['component'];
        }
        if (isset($event['check']['Component'])) {
            $component = $event['check']['Component'];
        }
        return $component;
    }

    public function getOriginName() {
        ## Cloudformation Stack Name wie DEV-SENSU
        $event = $this->getEvent();
        $stackname = 'UNKNOWN';
        if (isset($event['client']['ec2']['stack_name'])) {
            $stackname = $event['client']['ec2']['stack_name'];
        }
        if (isset($event['client']['ec2']['tags']['aws:cloudformation:stack-name'])) {
            $stackname = $event['client']['ec2']['tags']['aws:cloudformation:stack-name'];
        }
        if (isset($event['client']['tags']['aws:cloudformation:stack-name'])) {
            $stackname = $event['client']['tags']['aws:cloudformation:stack-name'];
        }
        return $stackname;
    }

    public function getEventName() {
        ## z.B. UptrendsProbeFailed
        $event = $this->getEvent();
        return $event['check']['name'];
    }

    public function getEventType() {
        ## Bitte fix auf ALARM setzen
        return 'ALARM';
    }

    public function getEventSeverity() {
        ## WARNING=KeinTicket, MINOR=MediumTicket, CRITICAL=HighTicket
        $event = $this->getEvent();

        if ($event['action'] == 'resolve')
            return 'HARMLESS';

        if (!isset($event['check']['status']))
            return 'UNKNOWN';

        switch ($event['check']['status']) {
            case 0:
                return 'HARMLESS';
                break;
            case 1:
                if ($this->_isCritical())
                    return 'MINOR';
                return 'WARNING';
                break;
            case 2:
                if ($this->_isCritical())
                    return 'CRITICAL';
                if ($this->_isUnCritical())
                    return 'WARNING';
                return 'MINOR';
                break;
            case 3:
                return 'UNKNOWN';
                break;
        }

        return 'UNKNOWN';
    }

    public function getEventUtime() {
        ## optionale Utime in Sekunden (aktuelle Uhrzeit, wenn nicht gesetzt)
        $event = $this->getEvent();
        return $event['timestamp'];
    }

    public function getObjectName() {
        ## Servername
        $event = $this->getEvent();
        return $event['client']['name'];
    }

    public function _createArgosEvent() {
        $config = $this->getHandlerConfig();

        /*
          {
          "containerName": "NameDerKomponente",        ## Gültiger Komponentenname
          "originName"   : "Hostname",                 ## Servername
          "eventName"    : "FehlerName",               ## z.B. UptrendsProbeFailed
          "eventType"    : "ALARM",                    ## Bitte fix auf ALARM setzen
          "eventSeverity": "MINOR",                    ## UNKNOWN=Unbekannt, INFO=OK (ohne ITSM), HARMLESS=OK (mit ITSM), WARNING=KeinTicket, MINOR=MediumTicket, CRITICAL=HighTicket
          "objectName"   : "WelchesObjektBetroffen",   ## optional, z.B. ConradDeB2C
          "eventUtime"   : 1484066701,                 ## optionale Utime in Sekunden (aktuelle Uhrzeit, wenn nicht gesetzt)

          "dsValues": {
          "ShortText": "Was passiert ist",           ## Ticket Short Description
          "LongText" : "Was im Detail passiert ist", ## Ticket Details
          "TodoText" : "Was nun zu tun ist"          ## Ticket Details
          }

         */
        $argosEvent = array(
            'containerName' => $this->getContainerName(),
            'originName' => $this->getOriginName(),
            'eventName' => $this->getEventName(),
            'eventType' => $this->getEventType(),
            'eventSeverity' => $this->getEventSeverity(),
            'objectName' => $this->getObjectName(),
            'eventUtime' => $this->getEventUtime(),
            'dsValues' => array()
        );

        $argosEvent['dsValues']['ShortText'] = $this->getShortText();
        $argosEvent['dsValues']['LongText'] = $this->getLongText();
        $argosEvent['dsValues']['TodoText'] = $this->getTodoText();

        if (!$config['simulate']) {
            $this->log("Sending json request " . var_export($argosEvent, true), "debug");
            try {
                # create event
                $response = \Httpful\Request::post($config['url'])->addHeader('apiKey', $config['api_key'])->sendsJson()->body(json_encode($argosEvent))->send();

                if ($response->code > 299)
                    throw new Exception('Unexpected response code ' . $response->code . ' from argos api');

                $this->log("Got response code " . $response->code . " from argos api", "debug");
            } catch (Exception $e) {
                $this->log("Could not create incident due to: " . $e->getMessage(), "error");
            }
            $this->log("Created argos event", "info");
        } else {
            $this->log("Simulating json request " . var_export($argosEvent, true), "debug");
            sleep(1);
            $this->log("Created argos fake event", "info");
        }

        return true;
    }

    protected function isProductiveAccount() {
      try {
        function isAccountIdSubscription($item) {
          return strpos($item, 'account_id') === 0;
        }
        $event = $this->getEvent();
        $account_id = null;
        foreach ($event['client']['subscriptions'] as $a) {
          if (isAccountIdSubscription($a)) {
            $parts = explode(':', $a);
            $account_id = $parts[1];
            break;
          }
        }

        $response = \Httpful\Request::get($this->_api_url . '/stashes/aws/account/' . $account_id . '/productive')->expectsJson()->send();

        if ($response->code == 200) {
          if (gettype($response->body) == 'string') {
            $account_stash = json_decode($response->body);
            $ret = $account_stash->{'productive'};
          } else {
            $ret = $response->body->productive;
          }
          $this->log('(from stash) result of isProductiveAccount for client: ' . $event['client']['name'] . ', ' . $ret, 'debug');
          return $ret;
        } elseif ($response->code == 404) {
          $sdk = new Aws\Sdk([
            'region' => 'eu-central-1',
            'version' => 'latest'
          ]);
          $dynamodb = $sdk->createDynamoDb();

          $result = $dynamodb->query([
            'IndexName' => 'account_id-index',
            'TableName' => 'shared_monitoring_customer_accounts',
                'KeyConditionExpression' => 'account_id = :account_id',
                'ExpressionAttributeValues' => [
                    ':account_id' => [
                'S' => $account_id
              ]
        		]
          ]);
          $item = $result['Items'][0];

          $ret = isset($item['productive']) ? $item['productive']['S'] == 'true' : false;

          $this->log('(from dynamodb) result of isProductiveAccount for client: ' . $event['client']['name'] . ', ' . $ret, 'debug');

          $post_data = array(
            'path' => 'aws/account/' . $account_id . '/productive',
            'content' => array(
              'productive' => $ret
            ),
            'expire' => 1700
          );

          \Httpful\Request::post($this->_api_url . '/stashes')->sendsJson()->body(json_encode($post_data))->send();

          return $ret;
        } else {
          throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');
        }


      } catch(Exception $e) {
        $this->log("Exception in productive check: " . $e->getMessage(), 'error');
        return false;
      }
    }

    protected function isOpToolKit() {
      $config = $this->getHandlerConfig();
      return $config['op_tool_kit'];
    }

    protected function _handleCreate() {
        if (!$this->_hasMinimumHistory()) {
            $this->log("Abort event history is too short");
            return 1;
        }

        if ($this->_inMaintenance()) {
            $this->log("Abort maintenance found");
            return 1;
        }

        if ($this->_hasDependentEvent()) {
            $this->log("Abort dependent event found");
            return 1;
        }

        if ($this->getContainerName() == 'UNKNOWN') {
            $this->log("Abort component is unknown");
            return 1;
        }

        if ($this->isOpToolKit() && !$this->isProductiveAccount()) {
          $this->log("Not productive account");
          return 1;
        }


        $this->_createArgosEvent();

        return 0;
    }

    protected function _handleResolve() {
        $this->_createArgosEvent();

        return 0;
    }

}
