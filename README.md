docker-sensu
============

This is a base container for Sensu Core.  It contains sensu-api, sensu-client, sensu-server, but does not contain any plugins.
For running the client use docker-sensu-client container image that contains the sensu plugins.

Default configuration allows for local linkage to rabbitmq and redis, by using docker links.  If you need to reference external servers set the following variables as needed.

RABBITMQ_PORT 5672
RABBITMQ_HOST rabbitmq
RABBITMQ_USER guest
RABBITMQ_PASSWORD guest
RABBITMQ_VHOST /

REDIS_HOST redis
REDIS_PORT 6379


An example of running everything locally

```
api:
  image: sstarcher/sensu
  environment:
    SENSU_SERVICE: api
  links:
    - rabbitmq
    - redis
server:
  image: sstarcher/sensu
  environment:
    SENSU_SERVICE: server
  links:
    - rabbitmq
    - redis
client:
  image: sstarcher/sensu-client
  environment:
    CLIENT_NAME: client_name
  links:
    - rabbitmq
    - redis
uchiwa:
  image: sstarcher/uchiwa
  links:
    - api:sensu
  ports:
    - '80:3000'
rabbitmq:
  image: rabbitmq:3.5-management
redis:
  image: redis
 ```

