<?php

require_once(__DIR__ . '/httpful.phar');

class SensuClientCleanup {

  private $_api_url = 'http://localhost:4567';

  private $_max_diff = 3600;

  public function cleanup() {

    $response = \Httpful\Request::get($this->_api_url . '/clients')->expectsJson()->send();
    if($response->code > 299) throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');
    $clients = $response->body;

    $response = \Httpful\Request::get($this->_api_url . '/events')->expectsJson()->send();
    if($response->code > 299) throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');
    $events = $response->body;

    $blacklist = array();

    foreach($events as $event) {
      if($event->check->name != 'keepalive') continue;
      $blacklist[$event->client->name] = true;
    }

    foreach($clients as $client) {
      # filter clients without timestamp
      if(!isset($client->timestamp)) continue;
      $time_diff = time() - $client->timestamp;
      # filter clients with recent timestamp
      if($time_diff < $this->_max_diff) continue;
      # filter clients with keepalive events
      if(isset($blacklist[$client->name])) continue;
      # remove old clients
      $response = \Httpful\Request::delete($this->_api_url . '/clients/' . $client->name)->send();
      if($response->code > 299) throw new Exception('Unexpected response code ' . $response->code . ' from sensu api');
    }

    return 0;
  }

}
