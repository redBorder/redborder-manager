#!/usr/bin/env ruby

#######################################################################
## Copyright (c) 2024 ENEO Tecnología S.L.
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
  printf "Usage: rb_set_journald_storage.rb auto|volatile|persistent|none\n"
  printf "Example: rb_set_journald_storage.rb volatil\n"
end

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef/admin.pem"
Chef::Config[:http_retry_count] = 5

if ARGV.length == 1 
  storage = ARGV[0]

  must_save = ["auto", "volatile", "persistent", "none"].include? storage

  if must_save
    role = Chef::Role.load("manager")
    role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?
    role.override_attributes["redborder"]["manager"] = {} if role.override_attributes["redborder"]["manager"].nil?
    role.override_attributes["redborder"]["manager"]["journald"] = {} if role.override_attributes["redborder"]["manager"]["journald"].nil?
    role.override_attributes["redborder"]["manager"]["journald"]["storage"] = storage
    printf "journald storage passed to #{storage}\n"

    if role.save
      printf "role[manager] saved successfully\n"
    else
      printf "ERROR: role[manager] cannot be saved!!!\n"
    end
  else
    usage
  end
else
  usage
end

