#!/usr/bin/env ruby

require 'chef'
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: rb_airflow [options]'

  opts.on('--show-creds', 'Show Airflow username and password') do
    options[:show_creds] = true
  end

  opts.on('--create-user', 'Create an admin user in Airflow with credentials from the data bag') do
    options[:create_user] = true
  end

  opts.on('--reset-password', 'Reset the Airflow password using the value from the data bag') do
    options[:reset_password] = true
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

# Chef configuration
Chef::Config.from_file('/etc/chef/client.rb')
Chef::Config[:node_name]  = 'admin'
Chef::Config[:client_key] = '/etc/chef/admin.pem'
Chef::Config[:http_retry_count] = 5

# Load secrets from the data bag
begin
  airflow_secrets = Chef::DataBagItem.load('passwords', 'airflow')
rescue
  puts "Error: could not load data bag 'passwords/airflow'"
  exit 1
end

airflow_user = airflow_secrets['user'] || 'admin'
airflow_pass = airflow_secrets['pass']

if options[:show_creds]
  puts "Username: #{airflow_user}"
  puts "Password: #{airflow_pass}"

elsif options[:create_user]
  system("airflow users create \
    --username #{airflow_user} \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password #{airflow_pass}")

elsif options[:reset_password]
  system("airflow users reset-password \
    --username #{airflow_user} \
    --password #{airflow_pass}")

else
  puts "Usage: rb_airflow --show-creds | --create-user | --reset-password"
end
