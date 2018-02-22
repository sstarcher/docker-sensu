#!/usr/bin/env ruby
# Released under the same terms as Sensu (the MIT license)

require 'sensu-handler'
require 'aws-sdk'
require 'json'

class SnsNotifier < Sensu::Handler
  def topic_arn
    settings['sns']['topic_arn']
  end

  def region
    settings['sns']['region'] || 'us-east-1'
  end

  def filter
    return false
  end

  def event_name
    "#{@event['client']['name']}/#{@event['check']['name']}"
  end

  def handle
    sns = Aws::SNS::Client.new(region: region)

    subject = if @event['action'].eql?('resolve') then
                "RESOLVED - [#{event_name}]"
              else
                "ALERT - [#{event_name}]"
              end

    options = {
      subject: subject,
      message: JSON.generate({
        default: JSON.generate(@event),
        email: "Sensu event #{event_name} status changed to #{@event['action'].eql?('resolve') ? 'resolved' : 'failure'}.\n\nThis is the full event:\n#{JSON.generate(@event)}"
      }),
      message_structure: 'json',
      topic_arn: topic_arn
    }

    sns.publish(options)
  rescue StandardError => e
    puts "Exception occured in SnsNotifier: #{e.message}", e.backtrace
  end
end