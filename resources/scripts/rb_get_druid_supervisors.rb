#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2025 ENEO Tecnología S.L.
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

require 'zk'
require 'json'
require 'net/http'
require 'uri'

ZOOKEEPER_HOSTS = 'zookeeper.service:2181'
ROUTER_PATH = '/druid/discoveryPath/druid:router'

begin
  zk = ZK.new(ZOOKEEPER_HOSTS)

  if zk.exists?(ROUTER_PATH)
    routers = zk.children(ROUTER_PATH)

    if routers.empty?
      puts "No routers found."
    else
      router_id = routers.sample
      path = "#{ROUTER_PATH}/#{router_id}"
      data, _stat = zk.get(path)
      router_info = JSON.parse(data) rescue {"error" => "Invalid JSON"}

      if router_info["address"] && router_info["port"]
        druid_router = "http://#{router_info["address"]}:#{router_info["port"]}/druid/indexer/v1/supervisor"

        uri = URI(druid_router)
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          supervisors = JSON.parse(response.body)
          if supervisors.empty?
            puts "No supervisors found."
          else
            # Create header with padding
            puts "+--------------------+"
            puts "| Supervisors        |"
            puts "+--------------------+"

            supervisors.each do |supervisor|
              puts "| #{supervisor.ljust(18)} |"
            end

            puts "+--------------------+"
          end
        else
          puts "Failed to fetch supervisors: #{response.code} #{response.message}"
        end
      else
        puts "Invalid router information received."
      end
    end
  else
    puts "Router path does not exist in ZooKeeper."
  end

rescue => e
  puts "Error: #{e.message}"
ensure
  zk.close if zk
end