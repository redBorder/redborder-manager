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

require 'rubygems'
require 'chef'
require 'json'

def usage
  printf "Usage: rb_set_darklist_key.rb <key>\n"
end

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef/admin.pem"
Chef::Config[:http_retry_count] = 5

hostname = `hostname -s`.strip

if ARGV.length == 1
  role = Chef::Role.load("manager")
  role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?
  role.override_attributes["redborder"]["manager"] = {} if role.override_attributes["redborder"]["manager"].nil?
  role.override_attributes["redborder"]["manager"]["darklist"] = {} if role.override_attributes["redborder"]["manager"]["darklist"].nil?
  role.override_attributes["redborder"]["manager"]["darklist"]["apikey"] = ARGV[0]

  if role.save
    printf "role[#{hostname}] saved successfully\n"
  else
    printf "ERROR: role[#{hostname}] cannot be saved!\n"
  end
else
  usage
end

