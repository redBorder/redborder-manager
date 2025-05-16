#!/usr/bin/env ruby

require 'dalli'
require 'getopt/std'
require 'yaml'

def print_usage
  puts <<~USAGE
    Usage: ruby check_memcached_key.rb -k KEY [-h HOST] [-p PORT]

    Options:
      -k KEY     Key to search for (required)
      -h HOST    Memcached server host (optional). If not provided, uses production servers from /root/rb-rails/config/memcached_config.yml
      -p PORT    Memcached server port (optional, default: 11211; ignored if using YAML-configured servers)
  USAGE
end

def load_servers_from_config
  config_path = "/root/rb-rails/config/memcached_config.yml"
  begin
    config = YAML.load_file(config_path)
    servers = config.dig("production", "servers")
    if servers.nil? || !servers.is_a?(Array) || servers.empty?
      raise "No servers found under 'production -> servers'"
    end
    servers
  rescue => e
    puts "Error loading servers from config file: #{e.message}"
    exit 1
  end
end

# Parse command-line options
opts = {}
opts.merge!(Getopt::Std.getopts('k:h:p:'))

if opts.empty? || opts['k'].nil?
  print_usage
  exit 1
end

key = opts['k']

# Use YAML servers if no host is passed
servers = if opts['h']
             port = (opts['p'] || '11211').to_i
             ["#{opts['h']}:#{port}"]
          else
             load_servers_from_config
          end

begin
  client = Dalli::Client.new(servers)
  value = client.get(key)

  if value.nil?
    puts "The key '#{key}' does NOT exist in Memcached (#{servers.join(', ')})."
  else
    puts "The key '#{key}' EXISTS in Memcached (#{servers.join(', ')})."
    puts "Value: #{value.inspect}"
  end
rescue => e
  puts "Error connecting to or querying Memcached: #{e.message}"
end
