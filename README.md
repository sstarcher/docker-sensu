docker-sensu
============

This is a base container for Sensu Core.  It contains sensu-api, sensu-client, sensu-server, but does not contain any plugins.
For running the client use docker-sensu-client container image that contains the sensu plugins.

Default configuration allows for local linkage to rabbitmq and redis, by using docker links.  If you need to reference external servers set the following variables as needed.

Dependencies:
  - Server
    - rabbitmq
    - redis
    - api
  - Api
    - rabbitmq
    - redis
  - Client
    - rabbitmq


```
RABBITMQ_PORT 5672
RABBITMQ_HOST rabbitmq
RABBITMQ_USER guest
RABBITMQ_PASSWORD guest
RABBITMQ_VHOST /

REDIS_HOST redis
REDIS_PORT 6379
```

Client specific settings.

```
CLIENT_NAME *no default*
CLIENT_ADDRESS *no default*
CLIENT_SUBSCRIPTIONS all, default
CLIENT_KEEPALIVE_HANDLER default
```



An example docker-compose.yml file of running everything locally

```
api:
  image: sstarcher/sensu
  command: api
  links:
    - rabbitmq
    - redis
server:
  image: sstarcher/sensu
  command: server
  links:
    - rabbitmq
    - redis
    - api
client:
  image: sstarcher/sensu-client
  command: client
  environment:
    CLIENT_NAME: bob
    RUNTIME_INSTALL: sstarcher/aws sstarcher/consul
  links:
    - rabbitmq
uchiwa:
  build: docker-uchiwa
  links:
    - api:sensu
  ports:
    - '80:3000'
rabbitmq:
  image: rabbitmq:3.5-management
redis:
  image: redis
 ```


RUNTIME_INSTALL will allow you to install additional plugins from github during runtime
