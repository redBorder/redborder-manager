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

def usage
  printf "Usage: rb_set_modules.rb <module_name>:0|1\n"
  printf "Example: rb_set_modules.rb flow:1 ips:0 monitor:1 api:1 location:0 social:1\n"
  printf "Available modules: ips, flow, monitor, api, location, malware, social, correlation_engine_rule, policy_enforcer, vault, bi, scanner"
end

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
Chef::Config[:http_retry_count] = 5

if ARGV.length >= 1 
  role = Chef::Role.load("manager")

  must_save=true
  ARGV.each do |x|
    status=false
    xv=x.split(":")
    if xv.length >= 2
      name=xv[0]
      status=(xv[1]==true or xv[1].to_i==1 or xv[1].to_s=="true" or xv[1].to_s=="t" )
    else
      name=xv[0]
      status=true
    end

    if name=="ips" or name=="flow" or name=="monitor" or name=="api" or name=="all" or name=="location" or name=="malware" or name=="social" or name=="correlation_engine_rule" or name=="policy_enforcer" or name=="vault" or name=="bi" or name=="scanner"
      role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?
      role.override_attributes["redborder"]["manager"] = {} if role.override_attributes["redborder"]["manager"].nil?
      role.override_attributes["redborder"]["manager"]["modules"] = {} if role.override_attributes["redborder"]["manager"]["modules"].nil?
      role.override_attributes["redborder"]["manager"]["modules"][name] = status
      printf "Module #{name} #{status ? "enabled" : "disabled"}\n"
    else
      printf "ERROR: Unknown module name: #{name}\n"
      must_save=false
    end   

  end
  if must_save
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

