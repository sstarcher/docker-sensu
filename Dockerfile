FROM debian:jessie
MAINTAINER Shane Starcher <shanestarcher@gmail.com>

RUN \
    apt-get update &&\
    apt-get install -y curl ca-certificates &&\ 
    rm -rf /var/lib/apt/lists/*

RUN curl -s http://repositories.sensuapp.org/apt/pubkey.gpg | apt-key add -
RUN echo "deb     http://repositories.sensuapp.org/apt sensu main" > /etc/apt/sources.list.d/sensu.list

ENV SENSU_VERSION=0.25.2-1
RUN \
	apt-get update && \
    apt-get install -y sensu=${SENSU_VERSION} && \
    rm -rf /var/lib/apt/lists/*

ENV PATH /opt/sensu/embedded/bin:$PATH

#Nokogiri is needed by aws plugins
RUN \
	apt-get update && \
    apt-get install -y libxml2 libxml2-dev libxslt1-dev zlib1g-dev build-essential  && \
    gem install --no-ri --no-rdoc nokogiri yaml2json && \
    apt-get remove -y libxml2-dev libxslt1-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*


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
    CLIENT_BIND=127.0.0.0 \

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
RUN /bin/install http

EXPOSE 4567
VOLUME ["/etc/sensu/conf.d"]

ENTRYPOINT ["/bin/start"]
