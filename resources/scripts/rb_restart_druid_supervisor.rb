#!/usr/bin/env ruby
# frozen_string_literal: true

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
require 'net/http'
require 'uri'
require 'json'
require 'optparse'

def usage
  puts 'rb_restart_druid_supervisor.rb [-h] -s <supervisor_name>'
  puts '   -h                     : show help'
  puts '   -s <supervisor_name>   : rb_monitor | rb_monitor_<UUID> | rb_vault | ...'
  puts 'To list active supervisors, run: rb_get_druid_supervisors'
end

# ----------------------------------------------------------
#  Resolve a Druid Router host/port from ZooKeeper
# ----------------------------------------------------------
def resolve_druid_router
  begin
    zk_hosts = 'zookeeper.service:2181'
    zk = ZK.new(zk_hosts)

    druid_router_path = '/druid/discoveryPath/druid:router'
    raise "Router path '#{druid_router_path}' does not exist in Zookeeper" unless zk.exists?(druid_router_path)

    routers = zk.children(druid_router_path)
    raise 'ERROR: No routers found. Please enable druid router at least in one node.' if routers.empty?

    # Pick one router randomly
    router_id = routers.sample
    data, _stat = zk.get("#{druid_router_path}/#{router_id}")

    router_info = JSON.parse(data) || {}
    raise 'ERROR on restart supervisor' unless router_info['address'] && router_info['port']

    router_info
  rescue => e
    puts "ERROR on restart supervisor: #{e.message}"
    exit 0
  ensure
    zk&.close
  end
end

# ----------------------------------------------------------
#  POST action to supervisor via Druid Router
# ----------------------------------------------------------
def post_to_supervisor(supervisor_name, action)
  r = resolve_druid_router
  address = r['address'] # druid api address
  port = r['port'] # druid api port

  puts "Performing '#{action}' on supervisor '#{supervisor_name}' via #{address}:#{port}"

  uri = URI("http://#{address}:#{port}/druid/indexer/v1/supervisor/#{supervisor_name}/#{action}")

  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = { feed: supervisor_name }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }

  unless response.is_a?(Net::HTTPSuccess)
    raise "HTTP #{response.code} #{response.message} - #{response.body}"
  end

  puts "✔ Action '#{action}' completed successfully."
rescue => e
  puts "✖ ERROR performing '#{action}' on supervisor '#{supervisor_name}': #{e.message}"
end

# ----------------------------------------------------------
#  MAIN
# ----------------------------------------------------------
options = {}
OptionParser.new do |opts|
  opts.on('-s VALUE', 'Supervisor name') { |v| options[:s] = v }
  opts.on('-h', 'Help') { options[:h] = true }
end.parse!

if options[:h]
  usage
  exit 0
end

if options[:s].nil?
  usage
  exit 0
end

supervisor_name = options[:s]

post_to_supervisor(supervisor_name, 'suspend')
post_to_supervisor(supervisor_name, 'reset')
post_to_supervisor(supervisor_name, 'resume')
