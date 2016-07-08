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

require "getopt/std"

def distance_of_time_in_hours_and_minutes(from_time, to_time)
  from_time = from_time.to_time if from_time.respond_to?(:to_time)
  to_time = to_time.to_time if to_time.respond_to?(:to_time)
  distance_in_hours   = (((to_time - from_time).abs) / 3600).round
  distance_in_minutes = ((((to_time - from_time).abs) % 3600) / 60).round
  difference_in_words = ''
  difference_in_words << "#{distance_in_hours} #{distance_in_hours > 1 ? 'hours' : 'hour' } and " if distance_in_hours > 0
  difference_in_words << "#{distance_in_minutes} #{distance_in_minutes == 1 ? 'minute' : 'minutes' }"
end

opt = Getopt::Std.getopts("s:fholca")

if opt["h"]
  printf "rb_get_managers.rb [-s service][-f][-h][-o][-l]\n"
  printf "    -s service_name   -> printf information only about this service\n"
  printf "    -f                -> printf full information: managers and services\n"
  printf "    -h                -> print this help\n"
  printf "    -o                -> print services per manager instead of managers per service (only with -f option)\n"
  printf "    -l                -> print managers list on single line\n"
  printf "    -c                -> print managers list on single line readed from cache\n"
  printf "    -a                -> sort the managers list alphabetically\n"
  exit 0
end   

if opt["c"] and File.exists?"/etc/redborder/managers.list"
  if opt["a"]
    printf `cat /etc/redborder/managers.list | sort | tr '\n' ' '`
  else
    printf `cat /etc/redborder/managers.list | tr '\n' ' '`
  end
else
  require 'rubygems'
  require 'chef'
  require 'json'

  Chef::Config.from_file("/etc/chef/client.rb")
  Chef::Config[:node_name]  = "admin"
  Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
  Chef::Config[:http_retry_count] = 5
  
  filter_service=opt["s"]
  full_info=opt["f"]
  opposite=opt["o"]
  
  managers      = []
  managers_keys = Chef::Node.list.keys.sort
  managers_keys.each do |m|
    node = Chef::Node.load m
    managers << node if node.run_list?"role[manager]"
  end
  
  if !opt["a"]
    managers = managers.sort{|a,b| (a["rb_time"]||999999999999999999999) <=> (b["rb_time"]||999999999999999999999)}
  end
 
  if opt["l"]
    managers.each do |m|
      printf("%s ", m.name)
    end
    printf("\n")
  else
    if !managers.nil? and managers.size>0 and filter_service.nil?
      printf("======================================= Managers Mode =======================================\n")
      printf("%-22s %7s  %-15s %-15s %-10s %-25s\n", "Hostname", "Index", "Mode", "IP", "Status", "Last seen")
      printf("---------------------------------------------------------------------------------------------\n")
      managers.each do |node|
        if !node.nil? 
          mode="unknown"
          if !node["redBorder"].nil? and !node["redBorder"]["manager"].nil? and !node["redBorder"]["manager"]["mode"].nil?
            printf("%-22s %7s  %-15s %-15s %-10s %s\n", node.name, node["redBorder"]["manager"]["index"].nil? ? "-" : node["redBorder"]["manager"]["index"].to_s, node["redBorder"]["manager"]["mode"], node["ipaddress"].nil? ? "---" : node["ipaddress"] , node["redBorder"]["manager"]["status"].nil? ? "disabled" : node["redBorder"]["manager"]["status"], node["ohai_time"].nil? ? "-" : distance_of_time_in_hours_and_minutes(Time.at(node["ohai_time"]), Time.now))
          end
        end
      end
    end
    
    if full_info or !filter_service.nil? or !opposite.nil?
      if (opposite and managers.size>0) or !filter_service.nil?
        print_header=true
        printf("\n") if full_info
        printf("\n") if full_info
        printf("===================================================================================== Services/Managers =====================================================================================\n")
        printf("%-16s   " , "Service Name")
        managers.each do |node|
          printf("%15s   " , node.name[0...15])
        end
        printf "\n"
        printf("---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n")
    
        if filter_service.nil? and managers.size>0 and !managers[0]["redBorder"].nil? and !managers[0]["redBorder"]["cluster"].nil? and !managers[0]["redBorder"]["cluster"]["services"].nil?
          services=managers[0]["redBorder"]["cluster"]["services"]
        else
          services= filter_service.split(",").map{|x| {"name" => x}}
        end
    
        services.each do |s|
          printf("%-16s   " , s["name"])
          managers.each do |node|
            service_state=nil
            if !node["redBorder"].nil? and !node["redBorder"]["cluster"].nil? and !node["redBorder"]["cluster"]["services"].nil?
              node["redBorder"]["cluster"]["services"].each do |s2|
                if s2.name == s["name"]
                  service_state=s2
                  break
                end
              end
              if service_state.nil?
                printf("%14s %-3s" , "unknown", "!!")
              else
                printf("%14s %-3s" , service_state.status ? "up" : "down", service_state.ok ? "" : "!!")
              end
            end
          end
          printf "\n"
        end  
      else
        print_header=true
        printf("\n")
        printf("\n")
        printf("===================================================================================== Managers/Services =====================================================================================\n")
        managers.each do |node|
          if !node.nil? 
            if !node["redBorder"].nil? and !node["redBorder"]["manager"].nil? and !node["redBorder"]["cluster"].nil? and !node["redBorder"]["cluster"]["services"].nil?
              if print_header
                printf("%-16s " , "Name")
                node["redBorder"]["cluster"]["services"].each do |s|
                  printf("%-10s " , s.name[0...10])
                end
                printf("\n")
                printf("---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n")
                print_header=false
              end
     
              printf("%-16s " , node.name)
              node["redBorder"]["cluster"]["services"].each do |s|
                printf("%5s %-3s  " , s.status ? "up" : "down", s.ok ? "" : "!!")
              end
              printf("\n")
            end
          end
        end
        printf("\n")
      end
    end
  end  
end
  
