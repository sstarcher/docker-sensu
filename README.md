Dockerized Sensu
================

This git repo provides [Sensu](https://sensuapp.org/) in a Docker container.

Project: [https://github.com/sstarcher/docker-sensu]
(https://github.com/sstarcher/docker-sensu)

Docker image: [https://registry.hub.docker.com/u/sstarcher/sensu/]
(https://registry.hub.docker.com/u/sstarcher/sensu/)

[![](https://badge.imagelayers.io/sstarcher/sensu:latest.svg)](https://imagelayers.io/?images=sstarcher/sensu:latest 'Get your own badge on imagelayers.io')
[![Docker Registry](https://img.shields.io/docker/pulls/sstarcher/sensu.svg)](https://registry.hub.docker.com/u/sstarcher/sensu)&nbsp;

This is a base container for Sensu Core. It contains `sensu-api`, `sensu-client`, `sensu-server`, but does *not* contain any plugins.

Default configuration allows for local linkage to `rabbitmq` and `redis`, by using docker links. If you need to reference external servers set the following variables as needed.

This container can be configured to use runtime system information for checks and metrics from it's *host*.


## Note

Installed plugins for now can change without warning. If you need a specific plugin installed either build a container based off of this one our use `RUNTIME_INSTALL` to ensure your plugins are installed.


## Configuration

The client by default only loads files from `/etc/sensu/conf.d`.

The API by default loads files from:

- `/etc/sensu/conf.d`
- `/etc/sensu/check.d`

The server by default loads files from:

- `/etc/sensu/conf.d`
- `/etc/sensu/check.d`
- `/etc/sensu/handlers`

These defaults could be configured via environment variables:

```
ENV CONFIG_DIR /etc/sensu/conf.d
ENV CHECK_DIR /etc/sensu/check.d
ENV HANDLERS_DIR /etc/sensu/handlers
```

If you want `sensu-client` to use runtime system information for checks and metrics from container's *host* system (*not* from `sensu` container itself) you should:

1. Define volumes to access host's filesystem from `sensu` container :

  ```
  /dev:/host_dev/:ro
  /proc:/host_proc/:ro
  /sys:/host_sys/:ro
  ```

2. Redefine environment variables :

  ```
  HOST_DEV_DIR: /host_dev
  HOST_PROC_DIR: /host_proc
  HOST_SYS_DIR: /host_sys
  ```

All Sensu plugins will be automatically configured to use these paths instead of default ones.


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
REDIS_PASSWORD ""
REDIS_DB 0
REDIS_AUTO_RECONNECT true
REDIS_RECONNECT_ON_ERROR false
```

Client specific settings.

```
CLIENT_NAME *no default*
CLIENT_ADDRESS *no default*
CLIENT_SUBSCRIPTIONS all, default
CLIENT_KEEPALIVE_HANDLER default
```


An example `docker-compose.yml` file of running everything locally:

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
  image: sstarcher/sensu
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

`RUNTIME_INSTALL` will allow you to install additional plugins from github during runtime.
