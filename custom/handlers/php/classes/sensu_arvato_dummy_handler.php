<?php

require_once(__DIR__ . '/httpful.phar');
require_once(__DIR__ . '/sensu_arvato_handler.php');

class SensuArvatoDummyHandler extends SensuArvatoHandler {

    public function getHandlerName() {
        return 'dummy';
    }

    protected function _handleCreate() {
        $this->log("Handle create", "warn");
    }

    protected function _handleResolve() {
        $this->log("Handle resolve", "warn");
    }

}
