#!/usr/bin/ruby

#######################################################################
## Copyright (c) 2014 ENEO Tecnología S.L.
## This file is part of redborder.
## redborder is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
## redborder is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License License for more details.
## You should have received a copy of the GNU Affero General Public License License
## along with redborder. If not, see <http://www.gnu.org/licenses/>.
########################################################################

#require 'rubygems'
require 'chef'
require 'json'

MASTER_MODE="master"
SLAVE_MODE="slave"

# For master
Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/opscode/admin.pem"
Chef::Config[:http_retry_count] = 5

def is_valid_mode(mode)
  return (mode==MASTER_MODE or mode==SLAVE_MODE)
end

def set_mode( hostname, mode, services=[] )
  if is_valid_mode(mode) or mode.nil?

    # Load role and node
    node = Chef::Node.load(hostname)
    role = Chef::Role.load(hostname)

    # Attribute SERVICES in ROLE
    role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?
    role.override_attributes["redborder"]["services"] = {} if role.override_attributes["redborder"]["services"].nil?
    role.override_attributes["redborder"]["services"]["overwrite"] = {} if role.override_attributes["redborder"]["services"]["overwrite"].nil?

    # Creating attributes template for NODE
    # Override attributes
    node.override!["redborder"] = {} if node["redborder"].nil?
    # Normal attributes
    node.set["redborder"] = {} if node["redborder"].nil?

    # Before set the new mode, check if there was a previous mode
    last_mode = role.override_attributes["redborder"]["mode"]
    last_mode = node["redborder"]["mode"] if (last_mode.nil? or last_mode=="")
    last_mode = "new" if (last_mode.nil? or last_mode=="")

    # Set mode in role
    unless mode.nil?
      role.override_attributes["redborder"]["mode"] = mode
      role.override_attributes["redborder"]["services"]["overwrite"]={}

      node.override!["redborder"]["mode"] = mode
      node.override!["redborder"]["services"] = {} if node["redborder"]["services"].nil?
      node.override!["redborder"]["services"]["overwrite"]={}
      node.override!["redborder"]["services"]["current"]  ={} if node["redborder"]["services"]["current"].nil?

      node.set["redborder"]["mode"] = mode
      node.set["redborder"]["services"]["overwrite"]={} if !node["redborder"]["services"].nil?
    end

    #Configuring services if it is specified
    # TODO

    # Save changes y role and node
    if role.save and node.save
      if mode.nil?
        if !services.nil? and services.size>0
          printf("INFO: %-50s %s\n", "#{hostname} conserve mode #{last_mode}", ( !services.nil? and services.size>0 ) ? "    (#{services.join(",")})" : "")
        else
          printf("INFO: Nothing to do on #{hostname}\n")
        end
      else
        printf("INFO: %-50s %s\n", "#{hostname} passed from #{last_mode} to #{mode}", ( !services.nil? and services.size>0 ) ? "    (#{services.join(",")})" : "")
      end
    else
      printf "ERROR: #{hostname} cannot pass from #{last_mode} to #{mode} mode\n"
    end
  else
    printf "Usage: rb_set_mode.rb #{MASTER_MODE}|#{SLAVE_MODE} [manager1] [manager2] [....]\n"
  end
end
