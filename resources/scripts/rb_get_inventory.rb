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

# Initialize flag to track if insert/update message has been printed for each data_source
@messages_printed = Hash.new(false)

# Function to print insert/update message if not already printed for the specific data_source
def print_insert_message(data_source)
  unless @messages_printed[data_source]
    puts "[INFO]: Inserting/Updating MACs for data source #{data_source}."
    @messages_printed[data_source] = true
  end
end

puts "Start MAC INVENTORY JOB..."

# Load database configuration from YAML file
def load_db_config
  YAML.load_file("/var/www/rb-rails/config/database.yml")["production"]
end

# Establish connection to the PostgreSQL database
def connect_to_db(config)
  puts "Connecting to the database..."
  PG.connect(
    dbname: config["database"],
    user: config["username"],
    password: config["password"],
    port: config["port"],
    host: config["host"]
  )
end

# Resolve the name associated with an IP address using the database and DNS
def resolve_ip(ip, conn)
  # puts "Resolved ip..."
  result = conn.exec("SELECT name FROM redborder_objects WHERE value = '#{ip}'")
  return result[0]['name'] unless result.num_tuples.zero?

  # If no name found in the database, perform DNS resolution
  name = Resolv.getname(ip)
  return name
rescue PG::Error => e
  # Log database error
  # puts "Database error: #{e.message}"
rescue Resolv::ResolvError => e
  # Log DNS resolution error
  # puts "DNS resolution error: #{e.message}"
ensure
  return "unknown" unless defined?(name)
end

# Check if the given IP address is a private IP
def is_private_ip?(ip)
  private_ip_regex = /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/
  !!ip.match(private_ip_regex)
end

# Calculate the 1-hour interval from the current time
def calculate_time_interval
  current_time = Time.now
  one_hour_ago = current_time - 3600
  start_time = one_hour_ago.strftime("%Y-%m-%dT%H:%M:%S.000Z")
  end_time = current_time.strftime("%Y-%m-%dT%H:%M:%S.999Z")
  [start_time, end_time]
end

# Detect the device type
def detect_device_type(conn)
  query = <<~SQL
    SELECT MAX(SUBSTRING(object_type, 8)::INTEGER) + 1 AS next_num 
    FROM redborder_objects 
    WHERE object_type LIKE 'device#%' AND type = 'MacObject'
  SQL

  result = conn.exec(query).first
  next_num = result&.fetch('next_num', '0').to_i

  "device##{next_num}"
end

# Fetch MAC addresses from curl query
def fetch_mac_addresses(conn, data_source)
  start_time, end_time = calculate_time_interval

  intervals = ["#{start_time}/#{end_time}"]

  curl_response = RestClient.post(
    "http://localhost:8080/druid/v2",
    {
      queryType: "groupBy",
      dataSource: data_source,
      granularity: "all",
      dimensions: ["client_mac", "lan_ip"],
      context: {timeout: 90000, skipEmptyBuckets: true},
      limitSpec: {type: "default", limit: 10000, columns: [{dimension: "client_mac", direction: "ascending"}]},
      intervals: intervals,
      aggregations: [{type: "count", name: "event_count"}]
    }.to_json,
    {content_type: :json}
  )

  response_json = JSON.parse(curl_response)

  # If no MAC addresses found, return an empty array
  if response_json.empty?
    puts "[INFO]: No MAC addresses found in this time range."
    return []
  else

    # Extract MAC address information from the response
    response_json.map do |item|
      [item['event']['client_mac'], item['event']['lan_ip']]
    end
  end
end

# Insert or update a MAC address in the database
def insert_mac_address(conn, mac_address, resolved_ip, device_type)
  return false if invalid_mac_name?(resolved_ip)

  existing_mac = conn.exec_params("SELECT * FROM redborder_objects WHERE value = $1", [mac_address])
  if existing_mac.num_tuples.zero?
    insert_new_mac(conn, mac_address, resolved_ip, device_type)
    true
  else
    update_mac_name(conn, mac_address, resolved_ip) if existing_mac[0]['name'] != resolved_ip
    false
  end
end

# Insert a new MAC address into the database
def insert_new_mac(conn, mac_address, resolved_ip, device_type)
  # Ensure resolved_ip is not invalid
  return if invalid_mac_name?(resolved_ip)

  current_time = Time.now.strftime("%Y-%m-%d %H:%M:%S")

  # Insert the MAC address into redborder_objects
  insert_query = <<~SQL
    INSERT INTO redborder_objects (name, value, type, object_type, created_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6)
  SQL

  conn.exec_params(insert_query, [resolved_ip, mac_address, 'MacObject', device_type, current_time, current_time])
end

# Helper function to check if MAC name is invalid
def invalid_mac_name?(name)
  name.nil? || name.empty? || name == 'Unknown Mac Name'
end

# Update the name of the MAC address in the database
def update_mac_name(conn, mac_address, resolved_ip)
  update_query = "UPDATE redborder_objects SET name = $1 WHERE value = $2"
  conn.exec_params(update_query, [resolved_ip, mac_address])
end

# Process MAC addresses obtained from the curl query
def process_mac_addresses(conn, data_sources)
  puts "Processing..."
  total_mac_count = 0
  data_sources.unshift('rb_flow')

  data_sources.each do |data_source|
    actual_data_source = data_source == 'rb_flow' ? 'rb_flow' : "rb_flow_#{data_source}"
    puts "Searching in data source: #{actual_data_source}"
    mac_count = 0

    mac_addresses = fetch_mac_addresses(conn, actual_data_source)

    unless mac_addresses.empty?
      print_insert_message(actual_data_source)

      mac_addresses.each do |mac_address, lan_ip|
        if is_private_ip?(lan_ip)
          insert_result = insert_mac_address(conn, mac_address, resolve_ip(lan_ip, conn), detect_device_type(conn))
          mac_count += 1 if insert_result
        end
      end
    end

    puts "MACs added/updated from #{actual_data_source}: #{mac_count}"
    puts "--------------------------------------------------------------"
    total_mac_count += mac_count
  end

  total_mac_count
end

# Main execution - Execute the script
begin
  data_sources = ARGV
  db_config = load_db_config
  conn = connect_to_db(db_config)
  total_mac_count = process_mac_addresses(conn, data_sources)
  puts "A total of #{total_mac_count} MAC addresses have been added in the database."
rescue => e
  puts "Error: #{e.message}"
ensure
  conn.close if conn
end
