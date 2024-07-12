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
require 'resolv'
require 'rest-client'
require 'json'
require 'pg'
require 'yaml'
require 'time'

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

# Module to manage database connections
module DatabaseConnection
  # Establish a connection to the PostgreSQL database
  def self.connect(db_config)
    connection = PG.connect(
      dbname: db_config["database"],
      user: db_config["username"],
      password: db_config["password"],
      port: db_config["port"],
      host: db_config["host"]
    )
    Logger.info("Connection to PostgreSQL established successfully.")
    connection
  rescue PG::Error => e
    Logger.error("Failed to connect to PostgreSQL: #{e.message}")
    nil
  end
end

# Module to handle queries to Druid
module DruidQuery
  DRUID_URL = "http://localhost:8080/druid/v2"

  # Execute a Druid query and return responses for each dimension
  def self.execute(data_source, dimensions, start_time, end_time)
    dimensions.each_with_object({}) do |dimension, responses|
      query = build_query(data_source, dimension, start_time, end_time)
      response = RestClient.post(DRUID_URL, query.to_json, { content_type: :json })
      parsed_response = JSON.parse(response)

      if parsed_response.empty?
        # Logger.info("No data found for dimension #{dimension} in the time range #{start_time} to #{end_time}.")
      else
        responses[dimension.to_sym] = parsed_response
      end
    end
  rescue RestClient::ExceptionWithResponse => e
    Logger.error("Error querying Druid: #{e.message}")
    raise
  rescue JSON::ParserError => e
    Logger.error("Error parsing JSON response from Druid: #{e.message}")
    raise
  end

  # Build the query payload for Druid
  def self.build_query(data_source, dimension, start_time, end_time)
    {
      queryType: "groupBy",
      dataSource: data_source,
      granularity: "all",
      dimensions: ["client_mac", dimension],
      context: { timeout: 90000, skipEmptyBuckets: true },
      limitSpec: { type: "default", limit: 10000, columns: [{ dimension: "client_mac", direction: "ascending" }] },
      intervals: ["#{start_time}/#{end_time}"],
      filter: {
        type: "regex",
        dimension: dimension,
        pattern: /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|fc[0-9a-fA-F]{2}:|fd[0-9a-fA-F]{2}:)/
      }
    }
  end
end

# Main class to handle MAC and IP inventory
class MacIpInventory
  def initialize
    @messages_printed = Hash.new(false)
    @total_ip_insert_count = 0
    @db_config = load_db_config
    @mac_ip_mapping = {}
  end

  # Establish a connection to the PostgreSQL database
  def connect_to_db
    Logger.info("Connecting to the database...")
    DatabaseConnection.connect(@db_config)
  end

  # Process MAC addresses and IPs from data sources
  def process_mac_addresses(conn, data_sources)
    Logger.info("Processing...")
    total_mac_insert_count = 0
    total_ip_insert_count = 0

    # Add 'rb_flow' as the default data source
    data_sources.unshift('rb_flow')
    data_sources.each do |data_source|
      actual_data_source = data_source == 'rb_flow' ? 'rb_flow' : "rb_flow_#{data_source}"
      Logger.info("Searching in data source: #{actual_data_source}")

      # Fetch and process MAC addresses and IPs from the data source
      mac_insert_count, ip_insert_count = fetch_mac_addresses(conn, actual_data_source)

      # Print insertion message if not already printed
      print_insert_message(actual_data_source)

      Logger.info("MACs inserted from #{actual_data_source}: #{mac_insert_count}")
      Logger.info("IPs inserted from #{actual_data_source}: #{ip_insert_count}")
      Logger.break_line

      # Accumulate total counts
      total_mac_insert_count += mac_insert_count
      total_ip_insert_count += ip_insert_count
    end

    Logger.info("Total MACs inserted: #{total_mac_insert_count}")
    Logger.info("Total IPs inserted: #{total_ip_insert_count}")

    total_mac_insert_count + total_ip_insert_count
  end

  private

  # Load database configuration from YAML file
  def load_db_config
    YAML.load_file("/var/www/rb-rails/config/database.yml")["production"]
  end

  # Fetch MAC addresses and IPs from a specified data source
  def fetch_mac_addresses(conn, data_source)
    start_time, end_time = calculate_time_interval
    dimensions = ["lan_ip", "wan_ip"]
    responses = DruidQuery.execute(data_source, dimensions, start_time, end_time)
    process_responses(conn, responses)
  end

  # Process responses for all dimensions
  def process_responses(conn, responses)
    mac_insert_count = 0
    ip_insert_count = 0

    responses.each do |dimension, response_json|
      if [:lan_ip, :wan_ip].include?(dimension)
        ip_insert_count += process_ip(conn, response_json, dimension.to_s)
      end
      mac_insert_count += process_client_mac(conn, response_json)
    end

    [mac_insert_count, ip_insert_count]
  end

  # Process MAC address dimension response
  def process_client_mac(conn, response_json)
    count = 0

    response_json.each do |item|
      client_mac = item['event']['client_mac']
      lan_ip = item['event']['lan_ip']
      wan_ip = item['event']['wan_ip']

      next unless client_mac && (lan_ip || wan_ip)

      [lan_ip, wan_ip].compact.each do |ip|
        resolved_ip = resolve_ip(ip)
        @mac_ip_mapping[client_mac] = resolved_ip if resolved_ip
        count += 1 if insert_mac_address(conn, client_mac, resolved_ip)
      end
    end
    count
  end

  # Process IP address dimension response
  def process_ip(conn, response_json, ip_type)
    response_json.sum do |item|
      ip_address = item['event'][ip_type]
      resolved_ip = resolve_ip(ip_address)
      resolved_ip ? (insert_ip_address(conn, ip_address, resolved_ip) ? 1 : 0) : 0
    end
  end

  # Print an insertion message if not already printed
  def print_insert_message(data_source)
    return if @messages_printed[data_source]

    Logger.info("Inserting MACs and IPs for data source #{data_source}.")
    @messages_printed[data_source] = true
  end

  # Calculate the 1-hour interval from the current time
  def calculate_time_interval
    current_time = Time.now
    one_hour_ago = current_time - 3600
    start_time = one_hour_ago.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    end_time = current_time.strftime("%Y-%m-%dT%H:%M:%S.999Z")
    [start_time, end_time]
  end

  # Resolve the name associated with an IP address using DNS
  def resolve_ip(ip)
    Resolv.getname(ip)
  rescue Resolv::ResolvError
    'UnknownName'
  end

  # Insert or update a MAC address in the PostgreSQL database
  def insert_mac_address(conn, mac_address, resolved_ip)
    conn.transaction do |pg_conn|
      existing_mac = pg_conn.exec_params("SELECT * FROM redborder_objects WHERE value = $1", [mac_address])
      return false if existing_mac.num_tuples > 0

      insert_new_mac(pg_conn, mac_address, resolved_ip)
      true
    end
  end

  # Insert a new MAC address into the PostgreSQL database
  def insert_new_mac(conn, mac_address, resolved_ip)
    current_time = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    resolved_name = @mac_ip_mapping[mac_address] || 'UnknownName'
    conn.exec_params(
      "INSERT INTO redborder_objects (name, value, type, created_at, updated_at, user_id, object_type)
      VALUES ($1, $2, $3, $4, $5, $6, $7)",
      [resolved_name, mac_address, 'MacObject', current_time, current_time, 1, 'UnknownDevice']
    )
  end

  # Insert or update an IP address in the PostgreSQL database
  def insert_ip_address(conn, ip_address, resolved_name)
    conn.transaction do |pg_conn|
      existing_ip = pg_conn.exec_params("SELECT * FROM redborder_objects WHERE value = $1", [ip_address])
      return false if existing_ip.num_tuples > 0

      insert_new_ip(pg_conn, ip_address, resolved_name)
      @total_ip_insert_count += 1
      true
    end
  end

  # Insert a new IP address into the PostgreSQL database
  def insert_new_ip(conn, ip_address, resolved_name)
    current_time = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    conn.exec_params(
      "INSERT INTO redborder_objects (name, value, type, created_at, updated_at, user_id, object_type)
      VALUES ($1, $2, $3, $4, $5, $6, $7)",
      [resolved_name, ip_address, 'NetObject', current_time, current_time, 1, nil]
    )
  end
end

# Main execution block
begin
  Logger.info("Start - INVENTORY JOB...")

  # Get data sources from command line arguments
  data_sources = ARGV

  # Create an instance of MAC and IP inventory
  inventory = MacIpInventory.new

  # Establish connection to the PostgreSQL database
  conn = inventory.connect_to_db

  if conn
    # Process MAC addresses and IPs for specified data sources
    total_count = inventory.process_mac_addresses(conn, data_sources)
    Logger.break_line
    Logger.info("A total of #{total_count} records (MACs and IPs) have been added to the database.")
  else
    Logger.error("No database connection was established.")
  end
rescue PG::Error => e
  Logger.error("Database error: #{e.message}")
rescue RestClient::ExceptionWithResponse => e
  Logger.error("RestClient error: #{e.message}")
rescue JSON::ParserError => e
  Logger.error("JSON parsing error: #{e.message}")
rescue StandardError => e
  Logger.error("Error: #{e.message}")
ensure
  conn&.close
end
