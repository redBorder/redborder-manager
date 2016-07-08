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
require 'colorize'

def usage
  printf "Usage: rb_set_service.rb [<service_name1>:[enable|disable|default]|<service_name2>:[enable|disable|default]]\n"
end

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
Chef::Config[:http_retry_count] = 5

hostname = `hostname -s`.strip
indexes  = nil

if ARGV.length >= 1 
  nodes = {}
  roles = {}

  printf "Proccessing services:\n"
  must_save=true
  ARGV.each do |x|
    xv=x.split(":")
    if xv.length >= 2
      if xv.length>=3
        nodehost=xv[0]
        service_name=xv[1]
        service_status=xv[2]
      else 
        nodehost=hostname
        service_name=xv[0]
        service_status=xv[1]
      end

      if nodehost=="all"
        nodehosts = []
        managers_keys = Chef::Node.list.keys.sort
        managers_keys.each do |m_key|
          m = Chef::Node.load m_key
          begin
            m_roles = m.roles
          rescue NoMethodError
            begin
              m_roles = m.run_list
            rescue
              m_roles = []
            end
          end
          if m_roles.include?("manager")
            nodehosts << m_key
          end
        end
      else
        nodehosts=nodehost.split(",")
      end    

      nodehosts.each do |nodehost|
        if nodehost.to_i.to_s == nodehost
          if indexes.nil?
            node = Chef::Node.load(hostname)
            indexes = node["redBorder"]["manager"]["indexes"]
          end
          if indexes.size<nodehost.to_i
            printf "    * Node index #{nodehost} not known on #{hostname}\n"
            nodehost=nil
          else
            nodehost = indexes[nodehost.to_i]
          end
        end
  
        unless nodehost.nil?
          if nodes[nodehost].nil?
            node = Chef::Node.load(nodehost)
            nodes[nodehost] = node
          else
            node = nodes[nodehost]
          end 
          if roles[nodehost].nil?
            role = Chef::Role.load(nodehost)
            roles[nodehost] = role
          else
            role = roles[nodehost]
          end 
          if node["redBorder"] and node["redBorder"]["manager"] and node["redBorder"]["manager"]["services"] and node["redBorder"]["manager"]["mode"] and node["redBorder"]["manager"]["services"][node["redBorder"]["manager"]["mode"]]
            manager_services = node["redBorder"]["manager"]["services"][node["redBorder"]["manager"]["mode"]]
          else
            manager_services = nil
          end

          service_status_boolean=( (service_status=="enable" or  service_status=="true" or service_status=="1" or service_status=="enabled" or service_status=="e" or service_status=="en") ? true : false )
          if service_status=="enable" or service_status=="disable" or service_status=="false" or service_status=="true" or service_status=="default" or service_status=="0" or service_status=="1"
            service_name="druid_realtime" if service_name=="realtime"
            service_name="druid_broker" if service_name=="broker"
            service_name="druid_coordinator" if service_name=="coordinator"
            service_name="druid_historical" if service_name=="historical"
            service_name="hadoop_nodemanager" if service_name=="nodemanager"
            service_name="hadoop_datanode" if service_name=="datanode"
            service_name="hadoop_namenode" if service_name=="namenode"
            service_name="hadoop_historyserver" if service_name=="historyserver"
            service_name="hadoop_resourcemanager" if service_name=="resourcemanager"

            if service_name=="hadoop"
              allservices = ["hadoop_datanode", "hadoop_nodemanager" ]
            elsif service_name=="storm"
              allservices = ["storm_nimbus", "storm_supervisor"]
            elsif service_name=="druid"
              allservices = ["druid_coordinator", "druid_realtime", "druid_historical", "druid_broker"]
            else
              allservices = [ service_name ]
            end
            allservices<<"riak-cs" if service_name=="riak" 
            allservices<<"riak" if service_name=="riak-cs"
            allservices<<"nginx" if service_name=="riak" or service_name=="riak-cs" and service_status_boolean
            allservices<<"nginx" if service_name=="rb-webui" and service_status_boolean

            allservices<<"rb-workers" if service_name=="rb-webui"
            allservices<<"rb-webui" if service_name=="rb-workers"
            if service_name=="erchef" or service_name=="chef-solr" or service_name=="chef-expander" or service_name=="rabbitmq"
              allservices<<"nginx" if !allservices.include?"nginx" and service_status_boolean
              allservices<<"erchef" unless allservices.include?"erchef"
              allservices<<"chef-solr" unless allservices.include?"chef-solr"
              allservices<<"chef-expander" unless allservices.include?"chef-expander"
              allservices<<"rabbitmq" unless allservices.include?"rabbitmq"
            end
            
            allservices.sort.uniq.each do |s|
              if !manager_services.nil? and manager_services[s].nil? and s!="darklist_update"
                printf "    * The service \"#{s}\" is not known for this node\n"
                must_save=false
              else
                role.override_attributes["redBorder"] = {} if role.override_attributes["redBorder"].nil?
                role.override_attributes["redBorder"]["manager"] = {} if role.override_attributes["redBorder"]["manager"].nil?
                if s=="darklist_update"
                  role.override_attributes["redBorder"]["manager"]["darklist"] = {} if role.override_attributes["redBorder"]["manager"]["darklist"].nil?
                  role.override_attributes["redBorder"]["manager"]["darklist"]["update"] = service_status_boolean
                else
                  role.override_attributes["redBorder"]["manager"]["services"] = {} if role.override_attributes["redBorder"]["manager"]["services"].nil?
                  role.override_attributes["redBorder"]["manager"]["services"]["overwrite"] = {} if role.override_attributes["redBorder"]["manager"]["services"]["overwrite"].nil?
                  role.override_attributes["redBorder"]["manager"]["services"]["overwrite"][s]=( (service_status == "enable" or  service_status == "true" or service_status=="1") ? true : false )
                end

                # saving info at node too
                node.override!["redBorder"] = {} if node["redBorder"].nil?
                node.override!["redBorder"]["manager"] = {} if node["redBorder"]["manager"].nil?
                if s=="darklist_update"
                  node.override!["redBorder"]["manager"]["darklist"] = {} if node["redBorder"]["manager"]["darklist"].nil?
                  node.override!["redBorder"]["manager"]["darklist"]["update"] = service_status_boolean
                else
                  node.override!["redBorder"]["manager"]["services"] = {} if node["redBorder"]["manager"]["services"].nil?
                  node.override!["redBorder"]["manager"]["services"]["overwrite"] = {} if node["redBorder"]["manager"]["services"]["overwrite"].nil?
                  node.override!["redBorder"]["manager"]["services"]["overwrite"][s] = ( (service_status == "enable" or  service_status == "true" or service_status=="1") ? true : false )
                  node.override!["redBorder"]["manager"]["services"]["current"] = {} if node["redBorder"]["manager"]["services"]["current"].nil?
                  node.override!["redBorder"]["manager"]["services"]["current"][s] = ( (service_status == "enable" or  service_status == "true" or service_status=="1") ? true : false )
                end
                printf "    * Service on #{nodehost}: #{s} #{service_status_boolean ? "enabled" : "disabled" }\n"
              end
            end
          else
            must_save=false
          end
        end
      end
    else
      must_save=false
    end
  end

  if must_save
    printf "Saving role information\n"
    roles.each do |host, role|
      if role.save
        printf "    * role[#{role.name}] saved successfully\n"
      else
        printf "    * ERROR: role[#{role.name}] cannot be saved!!!\n"
      end
    end

    printf "Saving node information\n"
    nodes.each do |host, node|
      if node.save
        printf "    * node[#{node.name}] saved successfully\n"
      else
        printf "    * ERROR: node[#{node.name}] cannot be saved!!!\n"
      end
    end
  else
    usage
  end
else
  node = Chef::Node.load(hostname)
  out = "#{"all cluster:".colorize(:light_blue)} rb_set_service.rb"

  if node["redBorder"] and node["redBorder"]["manager"] and node["redBorder"]["manager"]["indexes"]
    node["redBorder"]["manager"]["indexes"].each_with_index do |x, index|
      node = Chef::Node.load(x)
      out_individual="#{x} (#{index}): ".colorize(:light_blue)
      out_individual="#{out_individual}rb_set_service.rb"
      if node["redBorder"] and node["redBorder"]["manager"] and node["redBorder"]["manager"]["services"]["current"]
        manager_services = node["redBorder"]["manager"]["services"]["current"]
        manager_services.each do |service, value|
          if value
            v="1"
          else
            v="0"
          end
          out = "#{out} #{index}:#{service}:#{v}" 
          out_individual = "#{out_individual} #{service}:#{v}" 
        end
        printf "#{out_individual}\n"
      end
    end
  end

  printf "#{out}\n"
end

