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
require 'yaml'


Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
Chef::Config[:http_retry_count] = 5

if ARGV.length > 0
  if ARGV.length == 1
    value=ARGV[0]
    hostname = `hostname -s`.strip
  else
    hostname=ARGV[0]
    value=ARGV[1]
  end
else
  hostname = `hostname -s`.strip
  value=""
end

node = Chef::Node.load(hostname)
role = Chef::Role.load(hostname)

if node.nil? 
  printf "ERROR: node #{hostname} not found\n"
  exit 1
elsif role.nil?
  printf "ERROR: role[#{hostname}] not found\n"
  exit 1
end

last_value=node["redBorder"]["riak_joined"] unless node["redBorder"].nil?
last_value=false if last_value.nil?
 
if value!="" and (value=="true" or value=="false" or value=="1" or value=="0" or value=="enabled" or value=="disabled" or value=="enable" or value=="disable" or value=="associated" or value=="disassociated" or value=="joined")
  new_value=(value=="true" or value=="1" or value=="enabled" or value=="enable" or value=="associated" or value=="join")
  if new_value!=last_value
    role.override_attributes["redBorder"] = {} if role.override_attributes["redBorder"].nil?
    role.override_attributes["redBorder"]["riak_joined"] = new_value
    node.override!["redBorder"] = {} if node["redBorder"].nil?
    node.override!["redBorder"]["riak_joined"] = new_value
    if role.save and node.save
        printf "INFO: role[#{hostname}] has been marked as (#{new_value ? "associated" : "disassociated"})\n"
        ret=0
    else
        printf "ERROR: cannot change riak association\n"
        ret=1
    end 
  else
    printf "INFO: #{hostname} node has this value already (#{new_value ? "associated" : "disassociated"})\n"
    ret=0
  end
else
  #printf "Usage: rb_riak_status.rb [node] [enable|disable]\n"
  if last_value
    if system("service riak status &>/dev/null")
      system('riak-admin member-status 2>&1| grep -v "Attempting to restart script through sudo -H -u riak"')
      printf "\n"
      system('riak-admin ring-status 2>&1| grep -v "Attempting to restart script through sudo -H -u riak"')
      printf "\n"
      system('riak-admin transfers 2>&1')
    else
      printf "ERROR: riak is marked to belong a cluster but it is not running\n"
    end
  else
    printf "INFO: #{hostname} node is not joined with any S3 cluster!!\n"
    riak_enabled=File.read("/etc/redborder/mode/riak").chop if File.exists?("/etc/redborder/mode/riak")
    riak_enabled=(riak_enabled=="enabled")
    if riak_enabled
      if system("service riak status &>/dev/null")
        system('riak-admin member-status 2>&1| grep -v "Attempting to restart script through sudo -H -u riak"')
        printf "\n"
        system('riak-admin ring-status 2>&1| grep -v "Attempting to restart script through sudo -H -u riak"')
        printf "\n"
        system('riak-admin transfers 2>&1')
      else
        printf "ERROR: riak is enabled (/etc/redborder/mode/riak) but the service is not running\n"
      end
    else
      mdat = YAML.load_file("/etc/redborder/manager.yml")
      mdat["DOMAIN"] = "redborder.cluster" if mdat["DOMAIN"].nil?
      system("rb_manager_ssh.sh riak.#{ mdat["DOMAIN"] } rb_riak_status.rb")
    end
  end
  ret=0
end
  
exit ret

