#!/usr/bin/ruby
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


require 'rubygems'
require 'chef'
require 'json'

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
Chef::Config[:http_retry_count]=5

hostname = `hostname -s`.strip
node = Chef::Node.load(hostname)

if !node.nil? and node.run_list.include?"role[manager]" 
  if !Chef::Role.list.keys.include?(node.name)
    role_json = {"name" => node.name, "redBorder" => { "cluster" => {"services" => [] } } }
    role = Chef::Role.json_create(role_json)
    if role.create
      printf "Created role[#{node.name}]\n"
    else
      printf "Error creating role[#{node.name}] !!\n"
    end
  else
    printf "role[#{node.name}] already exists\n"
  end
else
  printf "This host is not a valid redBorder manager\n"
end
