#!/usr/bin/env ruby

require 'rest-client'
require 'json'
require 'active_record'
require 'logger'
require 'yaml'
require 'pg'

# Logger configuration
class AppLogger
  def self.logger
    @logger ||= Logger.new(STDOUT).tap do |log|
      log.level = Logger::DEBUG
    end
  end
end

# ActiveRecord configuration
class DatabaseConfig
  def self.setup
    config = YAML.load_file("/var/www/rb-rails/config/database.yml")
    ActiveRecord::Base.establish_connection(config['production'])
  rescue StandardError => e
    AppLogger.logger.error("Database configuration error: #{e.message}")
    exit 1
  end

  def self.verify_connection
    ActiveRecord::Base.connection
    AppLogger.logger.info("Database connection established successfully.")
  rescue ActiveRecord::ConnectionNotEstablished => e
    AppLogger.logger.error("Failed to connect to the database: #{e.message}")
    exit 1
  end
end

# Model definitions
class MacObject < ActiveRecord::Base
  self.table_name = 'redborder_objects'
end

class ObjectType < ActiveRecord::Base
  self.table_name = 'object_types'
end

# GLPI Client
class GLPIClient
  attr_reader :api_url, :logger

  def initialize(api_url, app_token)
    @api_url = api_url
    @app_token = app_token
    @logger = AppLogger.logger
  end

  def initiate_session(user_token)
    response = post_request("#{@api_url}/initSession", { user_token: user_token})
    JSON.parse(response.body)['session_token']
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to start session: #{e.response}")
    nil
  end

  def end_session(session_token)
    post_request("#{@api_url}/killSession", {}, session_token)
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to end session: #{e.response}")
  end

  def get_device_details(device_id, device_type, session_token)
    url = "#{@api_url}/#{device_type}/#{device_id}?expand_dropdowns=true&get_hateoas=true&with_devices=true&with_disks=true&with_softwares=true&with_connections=true&with_networkports=true&with_infocoms=true&with_contracts=true&with_documents=true&with_tickets=true&with_problems=true&with_changes=true&with_notes=true&with_logs=true"
    response = get_request(url, session_token)
    device_details = JSON.parse(response.body)

    mac = get_network_port_mac(device_details, session_token)
    operating_system = get_operating_system(device_id, session_token)
    ip_addresses = search_ip_addresses(device_id, session_token)

    { mac: mac, os: operating_system, ips: ip_addresses, details: device_details }
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to retrieve details for device #{device_id}: #{e.response}")
    { mac: nil, os: nil, ips: nil, details: nil }
  end

  private

  def headers(session_token = nil)
    {
      content_type: :json,
      accept: :json,
      'App-Token' => @app_token,
      'Session-Token' => session_token
    }
  end

  def post_request(url, payload, session_token = nil)
    RestClient.post(url, payload.to_json, headers(session_token))
  end

  def get_request(url, session_token)
    RestClient.get(url, headers(session_token))
  end

  def get_network_port_mac(device_details, session_token)
    network_ports_link = device_details["links"].find { |link| link["rel"] == "NetworkPort" }&.dig("href")
    return nil unless network_ports_link

    response = get_request(network_ports_link, session_token)
    network_ports_details = JSON.parse(response.body)

    mac = network_ports_details.find { |port| port.is_a?(Hash) && port.key?('mac') }&.dig('mac')
    mac
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to retrieve network port details: #{e.response}")
    nil
  end

  def get_operating_system(device_id, session_token)
    url = "#{@api_url}/Computer/#{device_id}/OperatingSystem"
    response = get_request(url, session_token)
    os_details = JSON.parse(response.body)

    os_details.first['name'] if os_details.is_a?(Array) && !os_details.empty?
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to retrieve operating system details for device #{device_id}: #{e.response}")
    nil
  end

  def search_ip_addresses(device_id, session_token)
    search_url = "#{@api_url}/search/Computer"
    query_params = {
      "criteria[0][field]" => "2",  # Field ID for the device ID
      "criteria[0][searchtype]" => "equals",
      "criteria[0][value]" => device_id,
      "forcedisplay[0]" => "126",   # Field ID for IP address
      "itemtype" => "Computer",
      "start" => "0",
      "limit" => "50"
    }
    response = RestClient.get(search_url, headers(session_token).merge(params: query_params))
    results = JSON.parse(response.body)
    logger.debug("Search IP addresses raw response: #{results}")

    ip_addresses = results.dig("data")&.flat_map { |device_data| device_data["126"] }&.compact&.uniq
    ip_addresses
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to search IP addresses: #{e.response}")
    []
  end
end

# Device Processor
class DeviceProcessor
  def initialize(client, user_id)
    @client = client
    @user_id = user_id
    @logger = AppLogger.logger
  end

  def retrieve_device_details(session_token, device_type)
    start = 0
    batch_size = 50

    loop do
      range = "#{start}-#{start + batch_size - 1}"
      url = "#{@client.api_url}/#{device_type}?range=#{range}"
      response = @client.send(:get_request, url, session_token)
      devices = JSON.parse(response.body)
      logger.debug("Number of devices returned from API: #{devices.size}")

      break if devices.empty?

      object_type_record = find_or_create_object_type(device_type)

      devices.each do |device|
        device_id = device["id"]
        logger.info("Processing device ID: #{device_id}, Name: #{device['name']}")
        process_device(device, device_type, session_token, object_type_record)
      end

      content_range = response.headers[:content_range]
      if content_range
        total_devices = content_range.split('/').last.to_i
        start += batch_size
        break if start >= total_devices
      else
        logger.warn("No Content-Range header found in response")
        break
      end

      sleep(10)
    end
  rescue RestClient::ExceptionWithResponse => e
    logger.error("Failed to retrieve #{device_type} data: #{e.response}")
  end

  private

  attr_reader :logger

  def find_or_create_object_type(object_type)
    ObjectType.find_or_create_by(name: object_type) do |type|
      type.comment = "Type for #{object_type}"
    end
  rescue ActiveRecord::RecordInvalid => e
    logger.error("Failed to find or create ObjectType: #{e.message}")
  end

  def find_or_initialize_mac_object(name, value, object_type)
    MacObject.find_or_initialize_by(name: name, value: value).tap do |obj|
      obj.object_type = object_type
      obj.user_id = @user_id
    end
  end

  def process_device(device, device_type, session_token, object_type_record)
    device_details = @client.get_device_details(device["id"], device_type, session_token)
    mac = device_details[:mac]
    os = device_details[:os]
    ips = device_details[:ips]&.join(', ')
    comment = device["comment"]

    ActiveRecord::Base.transaction do
      mac_object = find_or_initialize_mac_object(device["name"], mac, object_type_record.name)
      mac_object.comment = comment
      mac_object.type = "MacObject"
      mac_object.object_type = object_type_record.name
      mac_object.operating_system = os
      mac_object.ip_addresses = ips
      if mac_object.save
        logger.info("Added or updated MacObject for device ID: #{device['id']}")
      else
        logger.error("Failed to save MacObject: #{mac_object.errors.full_messages.join(", ")}")
      end
    end
  end
end

# Main script execution
begin
  user_token, api_url, app_token, user_id = ARGV
  DatabaseConfig.setup
  DatabaseConfig.verify_connection

  client = GLPIClient.new(api_url, app_token)
  session_token = client.initiate_session(user_token)
  if session_token.nil?
    AppLogger.logger.error("Failed to initiate session. Exiting...")
    exit 1
  end

  device_processor = DeviceProcessor.new(client, user_id)
  device_types = ["Computer", "NetworkEquipment", "Phone", "Peripheral"]

  device_types.each do |type|
    device_processor.retrieve_device_details(session_token, type)
  end

  exit 0


ensure
  client.end_session(session_token) if session_token
  ActiveRecord::Base.connection.close
  AppLogger.logger.info("Script completed and all connections closed.")
end
