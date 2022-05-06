#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2014 ENEO Tecnología S.L.
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

require "net/telnet"
require "dalli"
require "yaml"
require "json"

MEMCACHED_CONFIG_FILE="/var/www/rb-rails/config/memcached_config.yml" unless defined? MEMCACHED_CONFIG_FILE

def servers
  servers = []
  if File.exist?(MEMCACHED_CONFIG_FILE)
    production_config = YAML.load_file(MEMCACHED_CONFIG_FILE)
    servers = production_config["production"]["servers"]
  end
  servers.push("localhost:11211") if servers.empty?
  return servers
end

@memcached_server = servers
@darklist_path = "/usr/share/darklist.json"
@memcached = Dalli::Client.new(@memcached_server, {:expires_in => 0, :value_max_bytes => 4000000})

begin
  @memcached_server.each do |server|
    memhost_ip = server.split(":").first
    memhost_port = server.split(":").last
    host = Net::Telnet::new("Host" => memhost_ip, "Port" => memhost_port.to_i, "Timeout" => 5)
    matches   = host.cmd("String" => "stats items", "Match" => /^END/).scan(/STAT items:(\d+):number (\d+)/)
    slabs = matches.inject([]) { |items, item| items << Hash[*['id','items'].zip(item).flatten]; items }

    longest_key_len = 0

    slabs.each do |slab|
      begin
        host.cmd("String" => "stats cachedump #{slab['id']} #{slab['items']}", "Match" => /^END/) do |c|
          matches = c.scan(/^ITEM (.+?) \[(\d+) b; (\d+) s\]$/).each do |key_data|
            cache_key, bytes, expires_time = key_data
            @memcached.delete(cache_key) if cache_key.start_with?"darklist-"
          end
        end
      rescue
      end
    end
    host.close
  end
  #load keys from file
  if File.exist?(@darklist_path) then
    begin
      puts "Loading .."
      JSON.parse(File.read(@darklist_path)).map { |n| @memcached.set("darklist-#{n['ip']}", n['enrich_with']) }
      puts "OK."
    rescue
      STDERR.puts "Darklist load failed"
    end
  end
rescue StandardError => e
  STDERR.puts e.message
end
