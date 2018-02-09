# ExponentialDecayTimer
#
# Implement an exponential backoff timer for reconnecting to metrics
# backends.
class ExponentialDecayTimer
  attr_accessor :reconnect_time

  def initialize
    @reconnect_time = 0
  end

  def get_reconnect_time(max_reconnect_time, connection_attempt_count)
    if @reconnect_time < max_reconnect_time
      seconds = @reconnect_time + (2**(connection_attempt_count - 1))
      seconds = seconds * (0.5 * (1.0 + rand))
      @reconnect_time = if seconds <= max_reconnect_time
                          seconds
                        else
                          max_reconnect_time
                        end
    end
    @reconnect_time
  end
end

module Sensu::Extension
  # Setup some basic error handling and connection management. Climb on top
  # of Sensu logging capability to log error states.
  class RelayConnectionHandler < EM::Connection

    # XXX: These should be runtime configurable.
    MAX_RECONNECT_ATTEMPTS = 10
    MAX_RECONNECT_TIME = 300 # seconds

    attr_accessor :message_queue, :connection_pool
    attr_accessor :name, :host, :port, :connected
    attr_accessor :reconnect_timer

    # ignore :reek:TooManyStatements
    def post_init
      @is_closed = false
      @connection_attempt_count = 0
      @max_reconnect_time = MAX_RECONNECT_TIME
      @comm_inactivity_timeout = 0 # disable inactivity timeout
      @pending_connect_timeout = 30 # seconds
      @reconnect_timer = ExponentialDecayTimer.new
    end

    def connection_completed
      @connected = true
    end

    def close_connection(*args)
      @is_closed = true
      @connected = false
      super(*args)
    end

    def comm_inactivity_timeout
      logger.info("Connection to #{@name} timed out.")
      schedule_reconnect
    end

    def unbind
      @connected = false
      unless @is_closed
        logger.info('Connection closed unintentionally.')
        schedule_reconnect
      end
    end

    def send_data(*args)
      super(*args)
    end

    # Override EM::Connection.receive_data to prevent it from calling
    # puts and randomly logging non-sense to sensu-server.log
    def receive_data(data)
    end

    # Reconnect normally attempts to connect at the end of the tick
    # Delay the reconnect for some seconds.
    def reconnect(time)
      EM.add_timer(time) do
        logger.info("Attempting to reconnect relay channel: #{@name}.")
        super(@host, @port)
      end
    end

    def get_reconnect_time
      @reconnect_timer.get_reconnect_time(
        @max_reconnect_time,
        @connection_attempt_count
      )
    end

    def schedule_reconnect
      unless @connected
        @connection_attempt_count += 1
        reconnect_time = get_reconnect_time
        logger.info("Scheduling reconnect in #{@reconnect_time} seconds for relay channel: #{@name}.")
        reconnect(reconnect_time)
      end
      reconnect_time
    end

    def logger
      Sensu::Logger.get
    end

  end # RelayConnectionHandler

  # EndPoint
  #
  # An endpoint is a backend metric store. This is a compositional object
  # to help keep the rest of the code sane.
  class Endpoint

    # EM::Connection.send_data batches network connection writes in 16KB
    # We should start out by having all data in the queue flush in the
    # space of a single loop tick.
    MAX_QUEUE_SIZE = 16384

    attr_accessor :connection, :queue

    def initialize(name, host, port, queue_size = MAX_QUEUE_SIZE)
      @queue = []
      @connection = EM.connect(host, port, RelayConnectionHandler)
      @connection.name = name
      @connection.host = host
      @connection.port = port
      @connection.message_queue = @queue
      EventMachine::PeriodicTimer.new(60) do
        Sensu::Logger.get.info("relay queue size for #{name}: #{queue_length}")
      end
    end

    def queue_length
      @queue
        .map(&:bytesize)
        .reduce(:+) || 0
    end

    def flush_to_net
      sent = @connection.send_data(@queue.join)
      @queue = [] if sent > 0
    end

    def relay_event(data)
      if @connection.connected
        @queue << data
        if queue_length >= MAX_QUEUE_SIZE
          flush_to_net
          Sensu::Logger.get.debug('relay.flush_to_net: successfully flushed to network')
        end
      end
    end

    def stop
      if @connection.connected
        flush_to_net
        @connection.close_connection_after_writing
      end
    end

  end

  # The Relay handler expects to be called from a mutator that has prepared
  # output of the following format:
  # {
  #   :endpoint => { :name => 'name', :host => '$host', :port => $port },
  #   :metric => 'formatted metric as a string'
  # }
  class Relay < Handler

    def initialize
      super
      @endpoints = { }
      @initialized = false
    end

    # ignore :reek:LongMethod
    def post_init
      @settings[:relay].keys.each do |endpoint_name|
        ep_name = endpoint_name.intern
        ep_settings = @settings[:relay][ep_name]
        @endpoints[ep_name] = Endpoint.new(
          ep_name,
          ep_settings['host'],
          ep_settings['port'],
          ep_settings['max_queue_size']
        )
      end
    end

    def definition
      {
        type: 'extension',
        name: 'relay',
        mutator: 'metrics',
      }
    end

    def name
      'relay'
    end

    def description
      'Relay metrics via a persistent TCP connection'
    end

    # ignore :reek:LongMethod
    def run(event_data)
      begin
        event_data.keys.each do |ep_name|
          logger.debug("relay.run() handling endpoint: #{ep_name}")
          @endpoints[ep_name].relay_event(event_data[ep_name]) unless event_data[ep_name].empty?
        end
      rescue => error
        yield(error.to_s, 2)
      end
      yield('', 0)
    end

    def stop
      @endpoints.each_value do |ep|
        ep.stop
      end
      yield if block_given?
    end

    def logger
      Sensu::Logger.get
    end

  end # Relay
end # Sensu::Extension
