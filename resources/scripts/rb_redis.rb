#!/usr/bin/env ruby

require 'chef'
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: rb_redis [options]'

  opts.on('--terminal', 'Open redis-cli (terminal)') do
    options[:terminal] = true
  end

  opts.on('--list-incident-keys', 'List all incident keys in database 0') do
    options[:list_incident_keys] = true
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

Chef::Config.from_file('/etc/chef/client.rb')
Chef::Config[:node_name]  = 'admin'
Chef::Config[:client_key] = '/etc/chef/admin.pem'
Chef::Config[:http_retry_count] = 5

hostname = `hostname -s`.strip
node = Chef::Node.load(hostname)

redis_secrets = {}

begin
  redis_secrets = Chef::DataBagItem.load('passwords', 'redis')
rescue
  redis_secrets = {}
end

redis_master = node['redborder']['managers_per_services']['redis'].first
redis_port = node['redis']['port']
redis_password = redis_secrets['pass']

if options[:terminal]
  exec("redis-cli -h #{redis_master} -p #{redis_port} -a '#{redis_password}'")
elsif options[:list_incident_keys]
  system("redis-cli -h #{redis_master} -p #{redis_port} -a '#{redis_password}' --scan")
else
  puts OptionParser.new { |opts|
    opts.banner = 'Usage: rb_redis [options]'

    opts.on('--terminal', 'Open redis-cli (terminal)')
    opts.on('--list-incident-keys', 'List all keys in database 0')
    opts.on('-h', '--help', 'Show this help message')
  }
end
