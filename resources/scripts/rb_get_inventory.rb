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

# Load connection 
db_config = YAML.load_file("/var/www/rb-rails/config/database.yml")

# Establish connection to PostgreSQL database
conn = PG.connect(
  dbname: db_config["production"]["database"],
  user: db_config["production"]["username"],
  password: db_config["production"]["password"],
  port: db_config["production"]["port"],
  host: db_config["production"]["host"]
)

# Resolve the name associated with an IP address using the database and DNS.
# If the IP address is in the database, it returns the associated name.
# If it's not in the database, it attempts to resolve the DNS name.
# If the DNS name resolution fails or any error occurs, it returns "unknown".
#
# Arguments:
# - ip: The IP address to resolve.
# - conn: The connection to the PostgreSQL database.
#
# Returns:
# The name associated with the IP address or "unknown" if it cannot be determined.
def resolv_ip(ip, conn)
  begin
    result = conn.exec("SELECT name FROM redborder_objects WHERE value = '#{ip}'")
    return result[0]['name'] unless result.num_tuples.zero?

    name = Resolv.getname(ip)
    return name
  rescue PG::Error
  rescue Resolv::ResolvError
  ensure
    return "unknown" unless defined?(name)
  end
end

# Get the 1-hour interval from the current time
def calculate_time_interval
  current_time = Time.now
  one_hour_ago = current_time - 3600
  start_time = one_hour_ago.strftime("%Y-%m-%dT%H:%M:%S.000Z")
  end_time = current_time.strftime("%Y-%m-%dT%H:%M:%S.999Z")
  [start_time, end_time]
end

def detect_device_type(lan_ip, client_mac_vendor, app)
  # Analizar el user agent para obtener información sobre el navegador y el sistema operativo


  # Lógica para determinar el tipo de dispositivo basado en el user agent, las direcciones IP y el fabricante de la dirección MAC
  case user_agent
  when /Mobile Safari|Android/, /iOS/
    'Smartphone'
  when /Firefox|Chrome|Safari/
    'Laptop/Desktop'
  when /SmartTV/
    'Smart TV'
  when /\b192\.168\./, /\b10\./
    'Router'
  when /playstation|xbox/
    'Game Console'
  when /VMware/i
    'Virtual Machine'
  when /curl|wget/i
    'Server'
  when /bot|crawler/i
    'Web Crawler'
  when /print|scan/i
    'Printer'
  when /tablet/i
    'Tablet'
  else
    'Unknown'
  end
end

# Get objects
def resolv_obj(mac, lan_ip, user_agent, client_mac_vendor)
  start_time, end_time = calculate_time_interval

  intervals = ["#{start_time}/#{end_time}"]

  curl_response = RestClient.post(
    'http://localhost:8080/druid/v2',
    {
      queryType: "groupBy",
      dataSource: "rb_flow",
      granularity: "all",
      dimensions: ["client_mac", "client_mac_vendor", "lan_ip", "application_id_name"],
      filter: nil,
      context: {timeout: 90000, skipEmptyBuckets: true},
      limitSpec: {type: "default", limit: 10000, columns: [{dimension: "client_mac", direction: "ascending"}]},
      intervals: intervals,
      aggregations: [{type: "count", name: "event_count"}]
    }.to_json,
    {content_type: :json}
  )

  response_json = JSON.parse(curl_response)

  mac_addresses = response_json.map do |item|
    mac_address = item['event']['client_mac']
    vendor = item['event']['client_mac_vendor']
    lan_ip = item['event']['lan_ip']
    app = item['event']['application_id_name']


    # Llamamos a la función detect_device_type para obtener el tipo de dispositivo
    device_type = detect_device_type(lan_ip, client_mac_vendor, app)

    # Aquí puedes hacer lo que necesites con el tipo de dispositivo detectado
    # Por ejemplo, podrías almacenarlo en una estructura de datos o realizar alguna otra acción
    puts "El dispositivo con MAC #{mac_address} y proveedor #{vendor} es un #{device_type}"

    # Insertar el tipo de dispositivo en la base de datos junto con la dirección MAC
    insert_mac_address_to_database(conn, mac_address, nil, device_type)
  end
end

# Fetch MAC addresses from curl query
def fetch_mac_addresses_from_curl(conn)
  start_time, end_time = calculate_time_interval

  intervals = ["#{start_time}/#{end_time}"]

  curl_response = RestClient.post(
    'http://localhost:8080/druid/v2',
    {
      queryType: "groupBy",
      dataSource: "rb_flow",
      granularity: "all",
      dimensions: ["client_mac", "lan_ip"],
      filter: nil,
      context: {timeout: 90000, skipEmptyBuckets: true},
      limitSpec: {type: "default", limit: 10000, columns: [{dimension: "client_mac", direction: "ascending"}]},
      intervals: intervals,
      aggregations: [{type: "count", name: "event_count"}]
    }.to_json,
    {content_type: :json}
  )

  response_json = JSON.parse(curl_response)

  mac_addresses = response_json.map do |item|
    mac_address = item['event']['client_mac']
    lan_ip = item['event']['lan_ip']
    resolved_ip = nil
    if is_private_ip?(lan_ip)
      resolved_ip = resolv_ip(lan_ip, conn)
    end
    [mac_address, lan_ip, resolved_ip]
  end

  mac_addresses
end

# Checks if the given IP address is a private IP.
# 
# Arguments:
# - ip: The IP address to check.
# 
# Returns:
# - true if the IP address is a private IP (belongs to a private IP range), false otherwise.
def is_private_ip?(ip)
  private_ip_regex = /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/
  !!ip.match(private_ip_regex)
end

# Insert MAC address into redborder_objects table in PostgreSQL database
def insert_mac_address_to_database(conn, mac_address, resolved_ip, device_type)
  total_mac_count = 0

  begin
    result = conn.exec_params('SELECT * FROM redborder_objects WHERE value = $1', [mac_address])

    if result.count == 0
      # Si la MAC no existe, la insertamos como una nueva entrada
      default_name = resolved_ip.nil? || resolved_ip.empty? ? "unknown" : resolved_ip
      current_time = Time.now.strftime("%Y-%m-%d %H:%M:%S")

      insert_query = <<~SQL
        INSERT INTO redborder_objects (name, value, type, object_type, created_at, updated_at, user_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
      SQL

      conn.exec_params(insert_query, [default_name, mac_address, 'MacObject', device_type, current_time, current_time, 1])
      total_mac_count += 1

      # Verifica si el tipo de dispositivo ya está en la tabla object_types
      type_result = conn.exec_params('SELECT * FROM object_types WHERE name = $1', [device_type])

      if type_result.count == 0
        # Si el tipo de dispositivo no existe, lo insertamos en la tabla object_types
        insert_type_query = <<~SQL
          INSERT INTO object_types (name, created_at, updated_at)
          VALUES ($1, $2, $3)
        SQL

        conn.exec_params(insert_type_query, [device_type, current_time, current_time])
      end
    else
      # Si la MAC ya existe, actualizamos su nombre si es necesario
      existing_mac = result[0]
      if (resolved_ip && existing_mac['name'] != resolved_ip) || (existing_mac['name'] == 'unknown' && resolved_ip)
        update_query = <<~SQL
          UPDATE redborder_objects
          SET name = $1, updated_at = $2
          WHERE value = $3
        SQL

        conn.exec_params(update_query, [resolved_ip, Time.now.strftime("%Y-%m-%d %H:%M:%S"), mac_address])
      end
    end
  rescue PG::Error => e
    puts "Error: #{e.message}"
  end

  total_mac_count
end

# Initialize total MAC address counter
total_mac_count = 0

# Retrieve MAC addresses from curl query
mac_addresses_from_curl = fetch_mac_addresses_from_curl(conn)

# Iterate over each MAC address and add it to PostgreSQL database
mac_addresses_from_curl.each do |mac_address, lan_ip, resolved_ip, user_agent, client_mac_vendor|
  device_type = detect_device_type(lan_ip, user_agent, client_mac_vendor)
  total_mac_count += insert_mac_address_to_database(conn, mac_address, resolved_ip, device_type)
end

# Close connection to PostgreSQL database
conn.close if conn

# Print total number of MAC addresses added to PostgreSQL database
puts "A total of #{total_mac_count} MAC addresses have been added to the database."
