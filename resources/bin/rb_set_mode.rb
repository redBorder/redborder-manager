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
      printf("INFO: %-50s %s\n", "#{hostname} passed to mode: #{mode}")
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
