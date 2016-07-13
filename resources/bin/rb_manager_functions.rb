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
    node = Chef::Node.load(hostname)
    role = Chef::Role.load(manager)

    last_mode = "new"
    role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?
    role.override_attributes["redborder"]["manager"] = {} if role.override_attributes["redborder"]["manager"].nil?
    role.override_attributes["redborder"]["manager"]["services"] = {} if role.override_attributes["redborder"]["manager"]["services"].nil?
    role.override_attributes["redborder"]["manager"]["services"]["overwrite"] = {} if role.override_attributes["redborder"]["manager"]["services"]["overwrite"].nil?

    node.override!["redborder"] = {} if node["redborder"].nil?
    node.override!["redborder"]["manager"] = {} if node["redborder"]["manager"].nil?
    node.set["redborder"] = {} if node["redborder"].nil?
    node.set["redborder"]["manager"] = {} if node["redborder"]["manager"].nil?

    last_mode = role.override_attributes["redborder"]["manager"]["mode"]
    last_mode = node["redborder"]["manager"]["mode"] if (last_mode.nil? or last_mode=="")
    last_mode = "new" if (last_mode.nil? or last_mode=="")

    unless mode.nil?
      role.override_attributes["redborder"]["manager"]["mode"] = mode
      role.override_attributes["redborder"]["manager"]["services"]["overwrite"]={}

      node.override!["redborder"]["manager"]["mode"] = mode
      node.override!["redborder"]["manager"]["services"] = {} if node["redborder"]["manager"]["services"].nil?
      node.override!["redborder"]["manager"]["services"]["overwrite"]={}
      node.override!["redborder"]["manager"]["services"]["current"]  ={} if node["redborder"]["manager"]["services"]["current"].nil?

      node.set["redborder"]["manager"]["mode"] = mode
      node.set["redborder"]["manager"]["services"]["overwrite"]={} if !node["redborder"]["manager"]["services"].nil?
    end

    #TODO: Configure services
end
