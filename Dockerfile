FROM ubuntu:zesty-20170411
MAINTAINER Shane Starcher <shanestarcher@gmail.com>

ENV SENSU_VERSION=0.29.0-7


RUN \
    apt-get update &&\
    apt-get install -y curl ca-certificates apt-transport-https &&\
    curl -s https://sensu.global.ssl.fastly.net/apt/pubkey.gpg | apt-key add - &&\
    echo "deb     https://sensu.global.ssl.fastly.net/apt xenial main" > /etc/apt/sources.list.d/sensu.list &&\
    apt-get update &&\
    apt-get install -y sensu=${SENSU_VERSION} &&\
    rm -rf /opt/sensu/embedded/lib/ruby/gems/2.4.0/{cache,doc}/* && \
    find /opt/sensu/embedded/lib/ruby/gems/ -name "*.o" -delete && \
    rm -rf /var/lib/apt/lists/*

ENV PATH /opt/sensu/embedded/bin:$PATH
RUN gem install --no-document yaml2json

ENV DUMB_INIT_VERSION=1.2.0
RUN \
    curl -Ls https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_amd64.deb > dumb-init.deb &&\
    dpkg -i dumb-init.deb &&\
    rm dumb-init.deb

ENV ENVTPL_VERSION=0.2.3
RUN \
    curl -Ls https://github.com/arschles/envtpl/releases/download/${ENVTPL_VERSION}/envtpl_linux_amd64 > /usr/local/bin/envtpl &&\
    chmod +x /usr/local/bin/envtpl

COPY templates /etc/sensu/templates
COPY bin /bin/

ENV DEFAULT_PLUGINS_REPO=sensu-plugins \
    DEFAULT_PLUGINS_VERSION=master \

    #Client Config
    CLIENT_SUBSCRIPTIONS=all,default \
    CLIENT_BIND=127.0.0.1 \
    CLIENT_DEREGISTER=true \

    #Transport
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

    #Common Config
    RUNTIME_INSTALL='' \
    LOG_LEVEL=warn \
    CONFIG_FILE=/etc/sensu/config.json \
    CONFIG_DIR=/etc/sensu/conf.d \
    CHECK_DIR=/etc/sensu/check.d \
    EXTENSION_DIR=/etc/sensu/extensions \
    PLUGINS_DIR=/etc/sensu/plugins \
    HANDLERS_DIR=/etc/sensu/handlers \

    #Config for gathering host metrics
    HOST_DEV_DIR=/dev \
    HOST_PROC_DIR=/proc \
    HOST_SYS_DIR=/sys

RUN mkdir -p $CONFIG_DIR $CHECK_DIR $EXTENSION_DIR $PLUGINS_DIR $HANDLERS_DIR

EXPOSE 4567
VOLUME ["/etc/sensu/conf.d"]

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/bin/start"]
