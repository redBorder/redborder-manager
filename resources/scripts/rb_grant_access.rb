#!/usr/bin/env ruby

########################################################################    
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
require 'netaddr'
require "getopt/std"
require 'netaddr'


def usage() 
  printf "rb_grant_access [ -h ] [ [ -n <network> ] [ -n <network2> ] [ ...] ] [ -m trust|md5 ]\n"
  printf "    -h: print this help\n"
  printf "    -n <network>: Grant access to this network. Format: <cidr_net>[:mode]    (The mode is optional. If not present it will take the default one)\n"
  printf "    -m trust|md5: Default md5\n"
  exit 1
end

def add_net(networks, net, default_mode) 
  begin 
    netsplit = net.split(":")
    if netsplit.size>1
      net=netsplit[0]
      default_mode=netsplit[1]
    end
    default_mode="md5" if (default_mode!="trust" and default_mode!="md5")
    networks << {"network" => NetAddr::CIDR.create(net), "mode" => default_mode }
  rescue 
    printf("ERROR: #{net}:#{default_mode} is not valid\n")
  end
end

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef/admin.pem"
Chef::Config[:http_retry_count] = 5

opt = Getopt::Std.getopts("hn:m:")
ret=0

if opt["h"]
  usage
else
  mode = opt["m"]
  networks=[]

  if opt["n"]
    if opt["n"].class==Array
      keys=[]
      opt["n"].each do |x|
        add_net(networks, x, mode)
      end
    elsif opt["n"].respond_to?"split"
      opt["n"].split(",").each do |x|
        add_net(networks, x, mode)
      end
    end
  end

  usage if networks.size==0 

  begin 
    role = Chef::Role.load("manager")

    role.override_attributes["redborder"] = {} if role.override_attributes["redborder"].nil?
    role.override_attributes["redborder"]["manager"] = {} if role.override_attributes["redborder"]["manager"].nil?
    role.override_attributes["redborder"]["manager"]["database"] = {} if role.override_attributes["redborder"]["manager"]["database"].nil?

    role.override_attributes["redborder"]["manager"]["database"]["grant"] = networks

    if role.save
      printf "INFO: Role manager saved successfully\n"
    else
      printf "ERROR: Role manager can not be saved\n"
    end

  rescue => e
    printf "ERROR: cannot contact chef-server #{Chef::Config[:chef_server_url]}\n"
    puts "#{e}\n\t#{e.backtrace.join("\n\t")}"
    ret=1
  end
end

exit ret

