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

require 'optparse'
require 'chef'
require 'net/http'
require 'json'
require 'logger'

# How to use:
#   Register:
#     ./rb_consul_service.rb -r -s SERVICE_NAME -i IP_ADDRESS [-p PORT]
#   Unregister:
#     ./rb_consul_service.rb -u -s SERVICE_NAME

CHEF_KNIFE = '/root/.chef/knife.rb'
CONSUL_HOST = 'localhost'
CONSUL_PORT = 8500

logger = Logger.new($stdout)
logger.level = Logger::DEBUG
logger.formatter = proc do |severity, _datetime, _progname, msg|
  "#{severity}: #{msg}\n"
end

options = { port: 5432 }

OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [-r|-u] -s SERVICE_NAME [-i IP_ADDRESS] [-p PORT]"
  opts.on('-r', '--register',    'Register service')       { options[:action] = :register }
  opts.on('-u', '--unregister',  'Unregister service')     { options[:action] = :unregister }
  opts.on('-s NAME', '--service', 'Service name')          { |v| options[:service] = v }
  opts.on('-i IP',  '--ip',       'IP address to register') { |v| options[:ip] = v }
  opts.on('-p PORT','--port', Integer, 'Port to register')  { |v| options[:port] = v }
  opts.on('-h', '--help',         'Show this help')         { puts opts; exit }
end.parse!

unless options[:action] && options[:service]
  logger.error("Must specify -r or -u and -s SERVICE_NAME")
  exit 1
end

if options[:action] == :register && !options[:ip]
  logger.error("Registration requires -i IP_ADDRESS")
  exit 1
end

Chef::Config.from_file(CHEF_KNIFE)
node_name = `hostname`.strip.split('.').first
node = Chef::Node.load(node_name)

service = options[:service]
node.normal[service] ||= {}
registered = node.normal.dig(service, 'registered') == true
consul_id = "#{service}-#{node_name}"
base_url  = "http://#{CONSUL_HOST}:#{CONSUL_PORT}/v1/agent"

def consul_put(url, payload, logger)
  uri = URI(url)
  req = Net::HTTP::Put.new(uri)
  if payload
    req['Content-Type'] = 'application/json'
    req.body = JSON.dump(payload)
  end
  res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }
  unless res.is_a?(Net::HTTPSuccess)
    logger.error("Consul API error #{res.code}: #{res.body}")
    exit 2
  end
  logger.debug("Consul API call to #{url} succeeded")
end

case options[:action]
when :register
  if registered
    logger.debug("#{consul_id} already registered; skipping")
    exit 0
  end

  payload = {
    'ID'      => consul_id,
    'Name'    => service,
    'Address' => options[:ip],
    'Port'    => options[:port]
  }

  logger.info("Registering #{consul_id} in Consul")
  consul_put("#{base_url}/service/register", payload, logger)

  node.normal[service]['registered'] = true
  node.save
  logger.info("Registration successful; set node.normal['#{service}']['registered']=true")

when :unregister
  unless registered
    logger.debug("#{consul_id} not registered; skipping")
    exit 0
  end

  logger.info("Deregistering #{consul_id} from Consul")
  consul_put("#{base_url}/service/deregister/#{consul_id}", nil, logger)

  node.normal[service]['registered'] = false
  node.save
  logger.info("Deregistration successful; set node.normal['#{service}']['registered']=false")
end

