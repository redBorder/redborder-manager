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
Chef::Config[:http_retry_count] = 5

hostname = `hostname -s`.strip
node = Chef::Node.load(hostname)
role = Chef::Role.load(hostname)
  
if !node.nil? and !role.nil?
  if node["redBorder"] and node["redBorder"]["manager"] and node["redBorder"]["manager"]["mode"]=="master"
    now_utc = 0
  else
    now_utc = Time.now.getutc
  end

  role.override_attributes[:rb_time] = now_utc.to_i
  if role.save
    printf("Time '%s' saved into role[%s]\n", now_utc, hostname)
  else
    printf("ERROR: cannot save %s (UTC) saved\n", now_utc)
  end
end

