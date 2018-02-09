require 'json'

module Sensu::Extension
  # Sensu::Extension::Metrics
  #
  # This mutator is meant to be used in conjuction with Sensu::Extension::Relay
  # It prepares metrics for relay over persistent TCP connections to metric
  # stores.
  #
  # Metrics sent to sensu in the following JSON format will be mutated
  # accordingly based on the endpoints defined in the "relay" config section.
  # Currently supported endpoints are Graphite and OpenTSDB.
  #
  # { name: "metric.name", value: 1, tags: { host: "hostname" } }
  #
  # Metric checks also need to specify their output type, e.g.
  #
  # output_type: "json" Or output_type: "graphite"
  #
  # Checks should also specify whether or not the hostname should be
  # automatically added to the formatted metric output. In the case of graphite,
  # the hostname is prepended to the metric name, e.g. host.fqdn.com.metric.name
  # In the case of OpenTSDB, the hostname is added with the "host" tag.
  #
  # DEFAULTS:
  #
  # output_type: "graphite" auto_tag_host: "yes"
  #
  # Metrics sent in graphite format will be mutated to OpenTSDB if an OpenTSDB
  # endpoint is defined.
  #
  # Author: Greg Poirier http://github.com/grepory and @grepory on Twitter
  # greg.poirier at opower.com
  #
  # Many thanks to Sean Porter, Zach Dunn, Brett Witt, and Jesse Kempf,
  # and Jeff Kolesky for feedback and review.
  class Metrics < Mutator
    def initialize
      @endpoints = {}
      @mutators = {
        graphite: method(:graphite),
        opentsdb: method(:opentsdb)
      }
      @event = nil
    end

    def definition
      {
        type: 'extension',
        name: 'metrics'
      }
    end

    def name
      'metrics'
    end

    def description
      'mutates metrics for relay to metric stores'
    end

    def run(event)
      @event = event
      logger.debug("metrics.run(): Handling event - #{event}")
      # The unwritten standard is graphite, if they don't specify it, assume that's
      # the case.
      event[:check][:output_type] ||= 'graphite'
      # We also assume that people want to auto tag their metrics.
      event[:check][:auto_tag_host] ||= 'yes'

      settings[:relay].keys.each do |endpoint_name|
        ep_name = endpoint_name.intern
        mutator = @mutators[ep_name] || next
        mutate(mutator, ep_name)
      end unless settings[:relay].nil? # keys.each
      # if we aren't configured we simply pass nil to the handler which it then
      # guards against. fail silently.
      yield(@endpoints, 0)
    end # run

    def mutate(mutator, ep_name)
      logger.debug("metrics.run mutating for #{ep_name.inspect}")
      check = @event[:check]
      output = check[:output]
      output_type = check[:output_type]
      endpoint_name = ep_name.to_s

      # if we receive json, we mutate based on the endpoint name
      if output_type == 'json'
        @endpoints[ep_name] = ''
        metrics = JSON.parse(output)
        if metrics.is_a?(Hash)
          metrics = [metrics]
        end
        metrics.each do |metric|
          mutated = mutator.call(metric)
          @endpoints[ep_name] << mutated
        end
      # don't mutate
      elsif output_type == endpoint_name
        @endpoints[ep_name] = output
      elsif output_type == 'graphite' && endpoint_name == 'opentsdb'
        @endpoints[:opentsdb] = graphite_to_opentsdb
      end
    end

    private

    def graphite(metric)
      out = ''
      out << "#{@event[:client][:name].split(/\./).reverse.join('.')}." unless @event[:check][:auto_tag_host] == 'no'
      out << "#{metric['name']}\t#{metric['value']}\t#{metric['timestamp']}\n"
      out
    end

    def opentsdb(metric)
      check = @event[:check]
      out = "put #{metric['name']} #{metric['timestamp']} #{metric['value']}"
      out << " check_name=#{check[:name]}" unless check[:name].nil?
      out << " host=#{@event[:client][:name]}" unless check[:auto_tag_host] == 'no'
      metric['tags'].each do |tag, value|
        out << ' ' << [tag, value].join('=')
      end if metric.key?('tags')
      out << "\n"
    end

    def graphite_to_opentsdb
      out = ''
      metrics = @event[:check][:output]
      client_name = @event[:client][:name]

      metrics.split("\n").each do |output_line|
        (metric_name, metric_value, epoch_time) = output_line.split
        # Sometimes checks outputthings we don't want or expect.
        # Only attempt to parse things that look like they might make sense.
        next unless metric_name && metric_value && epoch_time
        metric_value = metric_value.rstrip
        # attempt to strip complete hostname from the beginning, otherwise
        # passthrough metric name as-is
        metric_name = metric_name.sub(/^#{client_name}\./, '')
        out << "put #{metric_name} #{epoch_time} #{metric_value} host=#{client_name}\n"
      end
      out
    end

    def logger
      Sensu::Logger.get
    end
  end # Metrics
end # Sensu::Extension
