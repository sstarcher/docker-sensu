FROM ubuntu:18.04
MAINTAINER Shane Starcher <shanestarcher@gmail.com>

ARG DEBIAN_FRONTEND=noninteractive
ARG SENSU_VERSION=1.2.1-2
ARG DUMB_INIT_VERSION=1.2.0
ARG ENVTPL_VERSION=0.2.3

RUN \
    apt-get update &&\
    apt-get install -y --no-install-recommends curl ca-certificates apt-transport-https gnupg locales build-essential &&\
    # Setup default locale & cleanup unneeded
    echo "LC_ALL=en_US.UTF-8" >> /etc/environment &&\
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen &&\
    echo "LANG=en_US.UTF-8" > /etc/locale.conf &&\
    locale-gen en_US.UTF-8 &&\
    find /usr/share/i18n/locales ! -name en_US -type f -exec rm -v {} + &&\
    find /usr/share/i18n/charmaps ! -name UTF-8.gz -type f -exec rm -v {} + &&\
    # Install Sensu
    curl -s https://sensu.global.ssl.fastly.net/apt/pubkey.gpg | apt-key add - &&\
    echo "deb https://sensu.global.ssl.fastly.net/apt stretch main" > /etc/apt/sources.list.d/sensu.list &&\
    apt-get update &&\
    apt-get install -y sensu=${SENSU_VERSION} &&\
    # Custom Plugins
    /opt/sensu/embedded/bin/gem install --no-ri --no-rdoc sensu-plugins-sensu && \
    # Install Sensu snssqs support
    /opt/sensu/embedded/bin/gem install --no-ri --no-rdoc sensu-transport-snssqs-ng && \
    # Cleanup sensu
    rm -rf /opt/sensu/embedded/lib/ruby/gems/2.4.0/cache/* &&\
    rm -rf /opt/sensu/embedded/lib/ruby/gems/2.4.0/doc/* &&\
    find /opt/sensu/embedded/lib/ruby/gems/ -name "*.o" -delete &&\
    # Install php
    apt-get install -y php-cli php-curl &&\
    # Cleanup debian
    apt-get remove -y gnupg build-essential &&\
    apt-get autoremove -y &&\
    rm -rf /var/lib/apt/lists/* &&\
    # Install dumb-init
    curl -Ls https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_amd64.deb > dumb-init.deb &&\
    dpkg -i dumb-init.deb &&\
    rm dumb-init.deb &&\
    # Install envtpl & yaml2json
    curl -Ls https://github.com/arschles/envtpl/releases/download/${ENVTPL_VERSION}/envtpl_linux_amd64 > /usr/local/bin/envtpl &&\
    chmod +x /usr/local/bin/envtpl &&\
    /opt/sensu/embedded/bin/gem install --no-document yaml2json &&\
    mkdir -p /etc/sensu/conf.d /etc/sensu/check.d /etc/sensu/extensions/server /etc/sensu/extensions/client /etc/sensu/plugins /etc/sensu/handlers

COPY templates /etc/sensu/templates
COPY custom/conf.d /etc/sensu/conf.d
COPY custom/handlers /etc/sensu/handlers
COPY custom/extensions /etc/sensu/extensions

COPY bin /bin/

RUN chown sensu.sensu -R /etc/sensu
RUN chmod +x /etc/sensu/handlers/ruby/*.rb
RUN chmod +x /etc/sensu/handlers/php/*.php

ENV DEFAULT_PLUGINS_REPO=sensu-plugins \
    DEFAULT_PLUGINS_VERSION=master \
    # Client Config
    CLIENT_SUBSCRIPTIONS=all,default \
    CLIENT_BIND=127.0.0.1 \
    CLIENT_DEREGISTER=true \
    # Transport
    TRANSPORT_NAME=redis \
    RABBITMQ_PORT=5672 \
    RABBITMQ_HOST=rabbitmq \
    RABBITMQ_USER=guest \
    RABBITMQ_PASSWORD=guest \
    RABBITMQ_VHOST=/ \
    RABBITMQ_PREFETCH=1 \
    RABBITMQ_SSL_SUPPORT=false \
    RABBITMQ_SSL_CERT='' \
    RABBITMQ_SSL_KEY='' \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_DB=0 \
    REDIS_AUTO_RECONNECT=true \
    REDIS_RECONNECT_ON_ERROR=false \
    SNSSQS_MAX_NUMBER_OF_MESSAGES=10 \
    SNSSQS_WAIT_TIME_SECONDS=2 \
    SNSSQS_REGION=us-east-1 \
    SNSSQS_CONSUMING_SQS_QUEUE_URL='' \
    SNSSQS_PUBLISHING_SNS_TOPIC_ARN='' \
    SNS_TOPIC_ARN='' \
    SNS_REGION=us-east-1 \
    ARGOS_LIVE=false \
    ARGOS_DEBUG=false \
    ARGOS_SIMULATE=true \
    ARGOS_URL='' \
    ARGOS_API_KEY='' \
    ARGOS_OP_TOOL_KIT=false \
    GRAPHITE_HOST='' \
    GRAPHITE_PORT=2003 \
    # Common Config
    RUNTIME_INSTALL='' \
    PARALLEL_INSTALLATION=1 \
    UNINSTALL_BUILD_TOOLS=1 \
    LOG_LEVEL=warn \
    CONFIG_FILE=/etc/sensu/config.json \
    CONFIG_DIR=/etc/sensu/conf.d \
    CHECK_DIR=/etc/sensu/check.d \
    EXTENSION_DIR=/etc/sensu/extensions \
    PLUGINS_DIR=/etc/sensu/plugins \
    HANDLERS_DIR=/etc/sensu/handlers \
    # Config for gathering host metrics
    HOST_DEV_DIR=/dev \
    HOST_PROC_DIR=/proc \
    HOST_SYS_DIR=/sys \
    # Include sensu installation into path
    PATH=/opt/sensu/embedded/bin:$PATH \
    # Set default locale & collations
    LC_ALL=en_US.UTF-8 \
    # -W0 avoids sensu client output to be spoiled with ruby 2.4 warnings
    RUBYOPT=-W0

EXPOSE 4567
VOLUME ["/etc/sensu/conf.d", "/etc/sensu/check.d", "/etc/sensu/handlers"]

USER sensu

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/bin/start"]
