#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2024 ENEO Tecnología S.L.
## This file is part of redBorder.
## redBorder is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
## redBorder is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License License for more details.
## You should have received a copy of the GNU Affero General Public License License
## along with redBorder. If not, see <http://www.gnu.org/licenses/>.
########################################################################

# Import required libraries
require 'json'
require 'net/http'
require 'uri'
require 'pg'
require 'yaml'
require 'date'

# Logger class for handling logging messages
class Logger
  class << self
    # Log informational messages
    def info(message)
      puts "[INFO]: #{message}"
    end

    # Log error messages
    def error(message)
      puts "[ERROR]: #{message}"
    end

    # Print a separator line
    def break_line
      puts "-" * 60
      puts
    end
  end
end

# FileManager: Class to handle writing data to JSON files.
class FileManager
  def self.save_to_file(data, file_path)
    # Organize each host object by hostid within the 'result' array
    result_data = data['result'].map do |host|
      { host['hostid'] => host }
    end

    # Construct the final data structure with 'jsonrpc' and 'result'
    final_data = {
      'jsonrpc' => data['jsonrpc'],
      'result' => result_data
    }

    # Save the structured data to file
    File.open(file_path, 'w') { |f| f.write(JSON.pretty_generate(final_data)) }
    Logger.info("Data saved to #{file_path}")
  end
end

# ZabbixAPI: Class to interact with the Zabbix API.
class ZabbixAPI
  attr_reader :zabbix_url, :auth_token, :zabbix_user, :zabbix_password

  def initialize(zabbix_url, auth_token, zabbix_user, zabbix_password)
    @zabbix_url = zabbix_url
    @auth_token = auth_token
    @zabbix_user = zabbix_user
    @zabbix_password = zabbix_password
  end

  # fetch_data: Method to fetch data from Zabbix API.
  def fetch_data
    uri = URI.parse(@zabbix_url)
    headers = { 'Content-Type' => 'application/json' }
    data = {
      jsonrpc: "2.0",
      method: "host.get",
      params: {
        output: "extend",
        selectInterfaces: "extend",
        selectParentTemplates: "extend",
        selectTags: "extend",
        selectInventory: "extend",
        selectItems: ["itemid", "name", "key_", "lastvalue"]
      },
      auth: @auth_token,
      id: 2
    }
  
    # Perform POST request to Zabbix API
    response = post_request(uri, headers, data.to_json)
    JSON.parse(response.body)
  rescue StandardError => e
    Logger.error("Error fetching data from Zabbix API: #{e.message}")
    nil
  end

  private

  # post_request: Method to perform an HTTP POST request.
  def post_request(uri, headers, body)
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Post.new(uri, headers)
      request.body = body
      response = http.request(request)
      raise "API communication error: #{response.message}" unless response.is_a?(Net::HTTPSuccess)
      response
    end
  end
end

# DeviceClassifier: Class to classify device type.
class DeviceClassifier
  DEVICE_TYPES = {
    "router" => "Router",
    "switch" => "Switch",
    "server" => "Server",
    "firewall" => "Firewall",
    "printer" => "Printer",
    "linux" => "Linux",
    "windows" => "Windows",
    "vmware" => "VMware",
    "database" => "Database"
  }.freeze

  # classify: Method to classify device type based on templates and tags.
  def self.classify(host)
    template_names = host['parentTemplates'].to_a.map { |t| t['name'].downcase }
    tag_values = host['tags'].to_a.map { |t| t['value'].downcase if t['tag'].downcase == 'device_type' }.compact

    # Look through host templates to determine device type
    template_names.each do |template_name|
      DEVICE_TYPES.each { |keyword, device_type| return device_type if template_name.include?(keyword) }
    end

    # Use tags to determine device type if not found in templates
    tag_values.each { |tag_value| return tag_value unless tag_value.empty? }

    'UnknownDevice'
  end
end

# DatabaseManager: Class to handle database connection and operations.
class DatabaseManager
  CONFIG_PATH = '/var/www/rb-rails/config/database.yml'

  def initialize
    # Load database configuration from YAML file
    @config = YAML.load_file(CONFIG_PATH)["production"]
    # Establish connection to PostgreSQL database
    @connection = PG.connect(
      dbname: @config["database"],
      user: @config["username"],
      password: @config["password"],
      port: @config["port"],
      host: @config["host"]
    )
  end

  # close: Method to close database connection.
  def close
    @connection.close
    Logger.info("Database connection closed.")
  end

  # process_host_data: Method to update data in database if conditions are met.
  def process_host_data(zabbix_data)
    return unless zabbix_data && zabbix_data['result'] && zabbix_data['result'].respond_to?(:each)

    Logger.info("Processing host data...")

    updated_entries_count = 0

    zabbix_data['result'].each do |host|
      name = normalize_host_name(host['name'])
      interfaces = host['interfaces']
      interfaces.each do |interface|
        ip = normalize_ip(interface['ip'])
        mac = normalize_mac(interface['mac'])
        next if name == ip  # Skip update if name is the same as IP
        device_type = DeviceClassifier.classify(host)

        # Ensure the device_type exists in object_types table
        ensure_device_type_exists(device_type)

        timestamp = current_timestamp
        user_id = 1

        if ip
          type = 'NetObject'
          existing_entry = fetch_existing_entry(ip)
        elsif mac
          type = 'MacObject'
          existing_entry = fetch_existing_entry(mac)
        end

        if existing_entry
          if entry_needs_update?(existing_entry, name, type)
            update_entry(name, device_type, timestamp, ip || mac, type)
            updated_entries_count += 1
          end
        end
      end
    end

    Logger.info("Data processing completed.")
    Logger.info("Updated #{updated_entries_count} existing objects.")
  end

  private

  # entry_needs_update?: Method to check if an existing entry needs update.
  def entry_needs_update?(existing_entry, name, type)
    existing_name = existing_entry['name']
    existing_type = existing_entry['object_type']

    existing_name != name || existing_type != type
  end

  def normalize_host_name(name)
    # Remove any numeric suffix like _2
    name.gsub(/_\d+$/, '')
  end

  def normalize_ip(ip)
    # Remove any numeric suffix like _2
    ip.gsub(/_\d+$/, '')
  end

  def normalize_mac(mac)
    # Remove any numeric suffix like _2
    mac.gsub(/_\d+$/, '') if mac
  end

  # current_timestamp: Method to get current timestamp in specific format.
  def current_timestamp
    DateTime.now.strftime('%Y-%m-%d %H:%M:%S.%6N')
  end

  # fetch_existing_entry: Method to fetch existing entry in database by IP or MAC.
  def fetch_existing_entry(value)
    result = @connection.exec_params('SELECT * FROM redborder_objects WHERE value = $1;', [value])
    result.ntuples > 0 ? result[0] : nil
  end

  # update_entry: Method to update an entry in the database.
  def update_entry(name, object_type, timestamp, value, type)
    @connection.exec_params(
      'UPDATE redborder_objects SET name = $1, object_type = $2, updated_at = $3, comment = $4, type = $5 WHERE value = $6;',
      [name, object_type, timestamp, 'By - Zabbix', type, value]
    )
  end

  # ensure_device_type_exists: Method to ensure the device_type exists in object_types table.
  def ensure_device_type_exists(device_type)
    unless device_type_exists?(device_type)
      insert_device_type(device_type)
    end
  end

  # device_type_exists?: Method to check if a device_type exists in object_types table.
  def device_type_exists?(device_type)
    result = @connection.exec_params('SELECT * FROM object_types WHERE name = $1;', [device_type])
    result.ntuples > 0
  end

  # insert_device_type: Method to insert a new device_type into object_types table.
  def insert_device_type(device_type)
    timestamp = current_timestamp
    @connection.exec_params(
      'INSERT INTO object_types (name, comment, created_at, updated_at) VALUES ($1, $2, $3, $4);',
      [device_type, '', timestamp, timestamp]
    )
    Logger.info("Inserted new device type: #{device_type}")
  end
end

# FileNotFoundError: Custom exception to handle file not found errors.
class FileNotFoundError < StandardError; end

# ZabbixHostManager: Main class for managing Zabbix hosts.
class ZabbixHostManager
  attr_reader :zabbix_url, :auth_token, :zabbix_user, :zabbix_password

  def initialize(zabbix_url, auth_token, zabbix_user, zabbix_password)
    @zabbix_url = zabbix_url
    @auth_token = auth_token
    @zabbix_user = zabbix_user
    @zabbix_password = zabbix_password
  end

  # execute: Method to execute the Zabbix data synchronization process.
  def execute
    zabbix_api = ZabbixAPI.new(zabbix_url, auth_token, zabbix_user, zabbix_password)
    Logger.info("Connecting to Zabbix API...")
    zabbix_data = zabbix_api.fetch_data
    return if zabbix_data.nil?
  
    FileManager.save_to_file(zabbix_data, '/tmp/data_zabbix.json')
  
    db_manager = DatabaseManager.new
    begin
      db_manager.process_host_data(zabbix_data)
    ensure
      db_manager.close
    end
  rescue StandardError => e
    Logger.error("Error: #{e.message}")
  end
end

if __FILE__ == $0
  zabbix_url = ARGV[0]
  auth_token = ARGV[1]
  zabbix_user = ARGV[2]
  zabbix_password = ARGV[3]

  if zabbix_url.nil? || auth_token.nil? || zabbix_user.nil? || zabbix_password.nil?
    Logger.error('ERROR: Missing input parameters. You must provide url, token, user, and password.')
    exit 1
  end
  
  manager = ZabbixHostManager.new(zabbix_url, auth_token, zabbix_user, zabbix_password)
  manager.execute
end
