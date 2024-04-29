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

require 'resolv'
require 'rest-client'
require 'json'
require 'pg'
require 'yaml'
require 'time'

puts "Start MAC INVENTORY JOB..."

# Load database configuration from YAML file
def load_db_config
  YAML.load_file("/var/www/rb-rails/config/database.yml")["production"]
end

# Establish connection to the PostgreSQL database
def connect_to_db(config)
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
  result = conn.exec("SELECT name FROM redborder_objects WHERE value = '#{ip}'")
    return result[0]['name'] unless result.num_tuples.zero?

    name = Resolv.getname(ip)
  return name
rescue PG::Error
rescue Resolv::ResolvError
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

# Detect the device type based on the MAC address vendor and application name
def detect_device_type(client_mac_vendor, app_name)
  case [client_mac_vendor, app_name]
  when [/^(Google)/, /google-services/]
    'Android'
  when [/^(Apple)/, /apple-services/]
    'iOS'
  when [/^(Microsoft)/, /active-directory/]
    'Windows Server'
  when [/^(Microsoft)/, /VMware/]
    'Virtual Machine'
  else
    'Unknown Device'
  end
end

# Get the name of the application
def get_application_name(app_value, conn)
  result = conn.exec_params("SELECT name FROM application_objects WHERE value = $1", [app_value])
  result.num_tuples.zero? ? "Unknown App Name" : result[0]['name']
end

# Fetch MAC addresses from curl query
def fetch_mac_addresses(conn)
  start_time, end_time = calculate_time_interval

  intervals = ["#{start_time}/#{end_time}"]

  curl_response = RestClient.post(
    'http://localhost:8080/druid/v2',
    {
      queryType: "groupBy",
      dataSource: "rb_flow",
      granularity: "all",
      dimensions: ["client_mac", "client_mac_vendor", "lan_ip", "application_id_name"],
      context: {timeout: 90000, skipEmptyBuckets: true},
      limitSpec: {type: "default", limit: 10000, columns: [{dimension: "client_mac", direction: "ascending"}]},
      intervals: intervals,
      aggregations: [{type: "count", name: "event_count"}]
    }.to_json,
    {content_type: :json}
  )

  response_json = JSON.parse(curl_response)

  if response_json.empty?
    puts "No se encontraron MAC en este rango de tiempo."
    return []
  else
    response_json.map do |item|
      [item['event']['client_mac'], item['event']['lan_ip'], item['event']['application_id_name'], item['event']['client_mac_vendor']]
    end
  end
end

# Insert MAC address into the redborder_objects table in the PostgreSQL database
def insert_mac_address(conn, mac_address, resolved_ip, device_type)
  # Si el nombre de la MAC está vacío, establecer un nombre predeterminado
  resolved_ip = "Unknown MAC Name" if resolved_ip.nil? || resolved_ip.empty?
  
  result = conn.exec_params("SELECT * FROM redborder_objects WHERE value = $1", [mac_address])

  if result.num_tuples.zero?
    insert_new_mac(conn, mac_address, resolved_ip, device_type)
    true
  else
    update_mac_name(conn, mac_address, resolved_ip, device_type)
    false
  end
end

# Insert a new MAC address into the database
def insert_new_mac(conn, mac_address, resolved_ip, device_type)
  default_name = resolved_ip.nil? || resolved_ip.empty? ? "Unknown Mac Name" : resolved_ip
  current_time = Time.now.strftime("%Y-%m-%d %H:%M:%S")

  insert_query = <<~SQL
    INSERT INTO redborder_objects (name, value, type, object_type, created_at, updated_at, user_id)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
  SQL

  conn.exec_params(insert_query, [default_name, mac_address, 'MacObject', device_type, current_time, current_time, 1])

  update_object_types(conn, device_type, current_time)
end

# Update the name of the MAC address in the database
def update_mac_name(conn, mac_address, resolved_ip, device_type)
  update_query = "UPDATE redborder_objects SET name = $1, object_type = $2, updated_at = $3 WHERE value = $4"
  conn.exec_params(update_query, [resolved_ip, device_type, Time.now.strftime("%Y-%m-%d %H:%M:%S"), mac_address])
end

# Insert the device type into the object_types table if it doesn't exist
def update_object_types(conn, device_type, current_time)
  result = conn.exec_params("SELECT * FROM object_types WHERE name = $1", [device_type])

  if result.num_tuples.zero?
    insert_type_query = "INSERT INTO object_types (name, created_at, updated_at) VALUES ($1, $2, $3)"
    conn.exec_params(insert_type_query, [device_type, current_time, current_time])
  end
end

# Process MAC addresses obtained from the curl query
def process_mac_addresses(conn)
  total_mac_count = 0
  fetch_mac_addresses(conn).each do |mac_address, lan_ip, app_name, client_mac_vendor|
    device_type = detect_device_type(client_mac_vendor, app_name)
    if is_private_ip?(lan_ip)
      insert_result = insert_mac_address(conn, mac_address, resolve_ip(lan_ip, conn), device_type)
      total_mac_count += 1 if insert_result
    end
  end
  total_mac_count
end

# Execute the script
begin
  db_config = load_db_config
  conn = connect_to_db(db_config)
  total_mac_count = process_mac_addresses(conn)
  puts "A total of #{total_mac_count} MAC addresses have been added in the database."
rescue => e
  puts "Error: #{e.message}"
ensure
  conn.close if conn
end
