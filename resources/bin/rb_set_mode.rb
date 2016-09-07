#!/usr/bin/env ruby

require 'chef'
require 'json'
require '/usr/lib/redborder/bin/rb_config_utils.rb'

def set_mode(hostname, mode)

  if Config_utils.check_mode(mode)
    # Load Chef configuration
    Chef::Config.from_file("/etc/chef/client.rb")
    Chef::Config[:node_name]  = "admin"
    Chef::Config[:client_key] = "/etc/chef/admin.pem"
    Chef::Config[:http_retry_count] = 5

    # Load role
    role = Chef::Role.load(hostname)

    # Override redborder attribute
    role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?

    unless mode.nil?
      # Set mode in role
      role.override_attributes["redborder"]["mode"] = mode
    end

    # Save changes in role
    if role.save
      printf "INFO: Node #{hostname} passed to mode #{mode}\n"
    else
      printf "Usage: rb_set_mode.rb master|custom [manager1] [manager2] [....]\n"
    end
  end

end

##################
# MAIN EXECUTION #
##################

managers=[]

if ARGV.length > 0
  mode=ARGV[0]
  managers=ARGV[1..ARGV.length-1]
else
  mode="custom"
end

# Only one manager to configure
managers=[`hostname -s`.chomp] if managers.size==0

managers.each do |hostname|
  if hostname.split(":").size>1
    set_mode(hostname.split(":")[0], hostname.split(":")[1])
  else
    set_mode(hostname, mode)
  end
end
