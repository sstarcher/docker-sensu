#!/usr/bin/env ruby
#
# see https://raw.githubusercontent.com/runningman84/sensu-plugins-aws/ca40f4bd9ae2a35cd71e95a2bf825b51e99a14ba/bin/handler-ec2_node.rb
#
# CHANGELOG:
# * 0.8.0:
#   - Added support to use ec2_region from client definition
# * 0.7.0:
#   - Added method instance_id to check in client config section
#   - Update to new API event naming and simplifying ec2_node_should_be_deleted method and fixing
#      match that will work with any user state defined.
# * 0.6.0:
#   - Fixed ec2_node_should_be_deleted to account for an empty insances array
# * 0.5.0:
#   - Adds configuration to filter by state reason
# * 0.4.0:
#   - Adds ability to specify a list of states an individual client can have in
#     EC2. If none is specified, it filters out 'terminated' and 'stopped'
#     instances by default.
#   - Updates how we are "puts"-ing to the log.
# * 0.3.0:
#   - Updates handler to additionally filter stopped instances.
# * 0.2.1:
#   - Updates requested configuration snippets so they'll be redacted by
#     default.
# * 0.2.0:
#   - Renames handler from chef_ec2_node to ec2_node
#   - Removes Chef-related stuff from handler
#   - Updates documentation
# * 0.1.0:
#   - Initial release
#
# This handler deletes a Sensu client if it's been stopped or terminated in EC2.
# Optionally, you may specify a client attribute `ec2_states`, a list of valid
# states an instance may have.
#
# You may also specify a client attribute `ec2_state_reasons`, a list of regular
# expressions to match state reasons against. This is useful if you want to fail
# on any `Client.*` state reason or on `Server.*` state reason. The default is
# to match any state reason `.*` Regardless, eventually a client will be
# deleted once AWS stops responding that the instance id exists.
#
# You could specify a ec2_states.json config file for the states like so:
#
#  {
#   "ec2_node": {
#    "ec2_states": [
#     "terminated",
#     "stopping",
#     "shutting-down",
#     "stopped"
#     ]
#    }
#  }
#
# And add that to your /etc/sensu/conf.d directory.
# If you do not specify any states the handler would not work
#
# NOTE: The implementation for correlating Sensu clients to EC2 instances may
# need to be modified to fit your organization. The current implementation
# assumes that Sensu clients' names are the same as their instance IDs in EC2.
# If this is not the case, you can either sub-class this handler and override
# `ec2_node_should_be_deleted?` in your own organization-specific handler, or modify this
# handler to suit your needs.
#
#
# A Sensu Client configuration using the ec2_region attribute:
#   {
#     "client": {
#       "name": "i-424242",
#       "address": "127.0.0.1",
#       "ec2_region": "eu-west-1",
#       "subscriptions": ["all"]
#     }
#   }
# or embeded in the ec2
#   {
#     "client": {
#       "name": "i-424242",
#       "address": "127.0.0.1",
#       "ec2" : {
#         "region": "eu-west-1"
#       },
#       "subscriptions": ["all"]
#     }
#   }
#
# Or a Sensu Server configuration snippet:
#   {
#     "aws": {
#       "access_key": "adsafdafda",
#       "secret_key": "qwuieohajladsafhj23nm",
#       "region": "us-east-1c"
#     }
#   }
#
# Or you can set the following environment variables:
#   - AWS_ACCESS_KEY_ID
#   - AWS_SECRET_ACCESS_KEY
#   - EC2_REGION
#
# If none of the settings are found it will then attempt to
# generate temporary credentials from the IAM instance profile
#
# If region is not specified in either of the above 3 mechanisms
# we will make a request for the EC2 instances current region.
#
# To use, you can set it as the keepalive handler for a client:
#   {
#     "client": {
#       "name": "i-424242",
#       "address": "127.0.0.1",
#       "keepalive": {
#         "handler": "ec2_node"
#       },
#       "subscriptions": ["all"]
#     }
#   }
#
# You can also use this handler with a filter:
#   {
#     "filters": {
#       "ghost_nodes": {
#         "attributes": {
#           "check": {
#             "name": "keepalive",
#             "status": 2
#           },
#           "occurrences": "eval: value > 2"
#         }
#       }
#     },
#     "handlers": {
#       "ec2_node": {
#         "type": "pipe",
#         "command": "/etc/sensu/handlers/ec2_node.rb",
#         "severities": ["warning","critical"],
#         "filter": "ghost_nodes"
#       }
#     }
#   }
#
# Copyleft 2013 Yet Another Clever Name
#
# Based off of the `chef_node` handler by Heavy Water Operations, LLC
#
# Released under the same terms as Sensu (the MIT license); see
# LICENSE for details

require 'timeout'
require 'sensu-handler'
require 'net/http'
require 'uri'
require 'aws-sdk'
# require 'sensu-plugins-aws'
require 'json'

class Ec2Node < Sensu::Handler
  # include Common
  def initialize
    super()
    aws_config
  end

  def aws_config
    Aws.config[:credentials] = Aws::Credentials.new(config[:aws_access_key], config[:aws_secret_access_key]) if config[:aws_access_key] && config[:aws_secret_access_key]

    Aws.config.update(
      region: config[:aws_region]
    ) if config.key?(:aws_region)
  end

  def filter; end

  # Method handle
  def handle
    # Call ec2_node_should_be_deleted method and check for instance state and if valid delete from the sensu API otherwise
    # instance is in invalid state
    if ec2_node_should_be_deleted?
      delete_sensu_client!
    else
      puts "[EC2 Node] #{instance_id} is in an invalid state"
    end
  end

  # Method to delete client from sensu API
  def delete_sensu_client!
    response = api_request(:DELETE, '/clients/' + @event['client']['name']).code
    deletion_status(response)
  end

  def instance_id
    @event['client']['name']
  end

  def account_id
    @event.dig('client', 'ec2', 'account_id') || settings.dig('ec2_node', 'account_id') || settings.dig('ec2_node', 'ec2', 'account_id')
  end

  def assume_role
    stash_req = api_request('GET', "/stash/aws/account/#{account_id}/service_role/assumed")
    case stash_req.code
    when '200'
      return JSON.parse(stash_req.body)
    when '404'
      dyn = Aws::DynamoDB::Client.new({region: region_server})
      # TODO: getItem, query or index?
      dyn_resp = dyn.scan({
        filter_expression: 'account_id = :account',
        expression_attribute_values: {
          ':account' => account_id
        },
        table_name: 'shared_monitoring_customer_accounts'
      })
      if (dyn_resp.items[0].key?('fixed_access_key_id') && dyn_resp.items[0].key?('fixed_secret_access_key')) then
        assumed_role = {
          access_key_id: dyn_resp.items[0]['fixed_access_key_id'],
            secret_access_key: dyn_resp.items[0]['fixed_secret_access_key']
        }
        path = '/stashes'
        api_request('POST', path) do |req|
          domain = api_settings['host'].start_with?('http') ? api_settings['host'] : 'http://' + api_settings['host']
          uri = URI("#{domain}:#{api_settings['port']}#{path}")
          req.body = JSON.generate({
            path: "/stash/aws/account/#{account_id}/service_role/assumed",
            expire: 3000,
            content: assumed_role
          })
          req.content_type = 'application/json'
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(req)
          end
        end
        return Aws::Credentials.new(assumed_role[:access_key_id], assumed_role[:secret_access_key])
      else
        role_arn = dyn_resp.items[0].key?('service_role_arn') ? dyn_resp.items[0]['service_role_arn'] : "arn:aws:iam::#{account_id}:role/AsyServiceRole"
        sts = Aws::STS::Client.new({region: region_server})
        sts_resp = sts.assume_role({
          role_arn: role_arn,
          role_session_name: "ec2-node-handler-#{account_id}"
        })
        assumed_role = {
          access_key_id: sts_resp.credentials.access_key_id,
          secret_access_key: sts_resp.credentials.secret_access_key,
          session_token: sts_resp.credentials.session_token
        }
        path = '/stashes'
        api_request('POST', path) do |req|
          domain = api_settings['host'].start_with?('http') ? api_settings['host'] : 'http://' + api_settings['host']
          uri = URI("#{domain}:#{api_settings['port']}#{path}")
          req.body = JSON.generate({
            path: "/stash/aws/account/#{account_id}/service_role/assumed",
            expire: 3000,
            content: assumed_role
          })
          req.content_type = 'application/json'
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(req)
          end
        end
        return Aws::Credentials.new(assumed_role[:access_key_id], assumed_role[:secret_access_key], assumed_role[:session_token])
      end
    else
      puts "ERROR in sensu api /stashes access"
      return {}
    end
  end

  # Method to check if there is any instance and if instance is in a valid state that could be deleted
  def ec2_node_should_be_deleted?
    # Defining region for aws SDK object
    credentials = {}
    unless region_client == region_server
      puts "[EC2 Node] #{instance_id} is in region #{region_client} server is in region #{region_server}"
    end
    unless account_id == Aws::STS::Client.new({region: region_server}).get_caller_identity.account
      puts "[EC2 Node] #{instance_id} is in account #{account_id} server is in account #{Aws::STS::Client.new({region: region_server}).get_caller_identity.account}"
      begin
        credentials = assume_role
      rescue Aws::DynamoDB::Errors::ResourceNotFoundException
        puts "[EC2 Node] Role switch failed due to missing DynamoDB item"
        return false
      end
    end
    ec2 = Aws::EC2::Client.new({region: region_client, credentials: credentials})
    settings['ec2_node'] = {} unless settings['ec2_node']
    instance_states = @event['client']['ec2_states'] || settings['ec2_node']['ec2_states'] || ['shutting-down', 'terminated', 'stopping', 'stopped']
    instance_reasons = @event['client']['ec2_state_reasons'] || settings['ec2_node']['ec2_state_reasons'] || %w(Client.UserInitiatedShutdown Server.SpotInstanceTermination Client.InstanceInitiatedShutdown)

    begin
      # Finding the instance
      instances = ec2.describe_instances({instance_ids: [instance_id]}).reservations[0]
      # If instance is empty/nil instance id is not valid so client can be deleted
      if instances.nil? || instances.empty?
        true
      else
        # Checking for instance state and reason, and if matches any of the user defined or default reasons then
        # method returns True

        # Returns instance state reason in AWS i.e: "Client.UserInitiatedShutdown"
        instance_state_reason = instances.instances[0].state_reason.nil? ? nil : instances.instances[0].state_reason.code
        # Returns the instance state i.e: "terminated"
        instance_state = instances.instances[0].state.name

        # Return true is instance state and instance reason is valid
        instance_states.include?(instance_state) && instance_reasons.include?(instance_state_reason)
      end
    rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
      true
    end
  end

  def region_client
    @region_client ||= begin
      region_check = ENV['EC2_REGION']
      region_check = settings['aws']['region'] if settings.key?('aws')
      region_check = @event['client']['ec2_region'] if @event['client'].key?('ec2_region')
      region_check = @event['client']['ec2']['region'] if @event['client'].key?('ec2') && @event['client']['ec2'].key?('region')
      if region_check.nil? || region_check.empty?
        region_check = Net::HTTP.get(URI('http://169.254.169.254/latest/meta-data/placement/availability-zone'))
        matches = /(\w+\-\w+\-\d+)/.match(region_check)
        if !matches.nil? && !matches.captures.empty?
          region_check = matches.captures[0]
        end
      end
      region_check
    end
  end

  def region_server
    @region_server ||= begin
      region_check = ENV['EC2_REGION']
      region_check = settings['aws']['region'] if settings.key?('aws')
      if region_check.nil? || region_check.empty?
        region_check = Net::HTTP.get(URI('http://169.254.169.254/latest/meta-data/placement/availability-zone'))
        matches = /(\w+\-\w+\-\d+)/.match(region_check)
        if !matches.nil? && !matches.captures.empty?
          region_check = matches.captures[0]
        end
      end
      region_check
    end
  end

  def deletion_status(code)
    case code
    when '202'
      puts "[EC2 Node] 202: Successfully deleted Sensu client: #{@event['client']['name']}"
    when '404'
      puts "[EC2 Node] 404: Unable to delete #{@event['client']['name']}, doesn't exist!"
    when '500'
      puts "[EC2 Node] 500: Miscellaneous error when deleting #{@event['client']['name']}"
    else
      puts "[EC2 Node] #{code}: Completely unsure of what happened!"
    end
  end
end
