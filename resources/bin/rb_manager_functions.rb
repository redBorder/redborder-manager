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

MASTER_MODE="master"
COMPUTE_MODE="compute"
SLAVE_MODE="slave"
STORAGE_MODE="storage"
S3_MODE="s3"
HADOOP_MODE="hadoop"
HISTORICAL="historical"
REALTIME="realtime"
STORM_SUPERVISOR="storm_supervisor"
REALTIMEPLUS="realtimeplus"
KAFKA_MODE="kafka"
WEB_MODE="web"
DATABASE_MODE="database"
CUSTOM="custom"
WEB_FULL="web_full"
STORM_NIMBUS="storm_nimbus"
NPROBE="nprobe"
ZOO_KAFKA="zoo_kafka"
ZOO_WEB="zoo_web"
CORE="core"
COREPLUS="coreplus"
COREZK="corezk"
CONSUMER="consumer"
NGINX="nginx"
KAFKACONSUMER="kafkaconsumer"
BROKERWEB="brokerweb"
ENRICHMENT="enrichment"
MIDDLEMANAGER="middleManager"
SAMZA="samza"
WEBDRUID="webdruid"
BROKER="broker"
K2HTTP="k2http"
HTTP2K="http2k"
DATANODE="datanode"
NMSPD="nmspd"

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
Chef::Config[:http_retry_count] = 5

def is_valid_mode(mode)
  return (mode==MASTER_MODE or mode==SLAVE_MODE or mode==COMPUTE_MODE or mode==STORAGE_MODE or mode==HISTORICAL or mode==CUSTOM or mode==S3_MODE or mode==HADOOP_MODE or mode==WEB_MODE or mode==DATABASE_MODE or mode==KAFKA_MODE or mode==REALTIME or mode==WEB_FULL or mode==STORM_NIMBUS or mode==STORM_SUPERVISOR or mode==NPROBE or mode==ZOO_KAFKA or mode==NGINX or mode==ZOO_WEB or mode==CORE or mode==COREPLUS or mode==COREZK or mode==CONSUMER or mode==REALTIMEPLUS or mode==KAFKACONSUMER or mode==BROKERWEB or mode==ENRICHMENT or mode==MIDDLEMANAGER or mode==SAMZA or mode==WEBDRUID or mode==BROKER or mode==K2HTTP or mode==HTTP2K or mode==DATANODE or mode==NMSPD)
end

def set_mode( hostname, mode, services=[] )
  if is_valid_mode(mode) or mode.nil?
    node = Chef::Node.load(hostname)
    role = Chef::Role.load(hostname)
  
    last_mode = "new"
    role.override_attributes["redBorder"] = {} if role.override_attributes["redBorder"].nil?
    role.override_attributes["redBorder"]["manager"] = {} if role.override_attributes["redBorder"]["manager"].nil?
    role.override_attributes["redBorder"]["manager"]["services"] = {} if role.override_attributes["redBorder"]["manager"]["services"].nil?
    role.override_attributes["redBorder"]["manager"]["services"]["overwrite"] = {} if role.override_attributes["redBorder"]["manager"]["services"]["overwrite"].nil?
  
    node.override!["redBorder"] = {} if node["redBorder"].nil?
    node.override!["redBorder"]["manager"] = {} if node["redBorder"]["manager"].nil?
    node.set["redBorder"] = {} if node["redBorder"].nil?
    node.set["redBorder"]["manager"] = {} if node["redBorder"]["manager"].nil?
  
    last_mode = role.override_attributes["redBorder"]["manager"]["mode"] 
    last_mode = node["redBorder"]["manager"]["mode"] if (last_mode.nil? or last_mode=="")
    last_mode = "new" if (last_mode.nil? or last_mode=="")

#    if mode==MASTER_MODE
#      count=0
#      master_node = nil
#      search=Chef::Search::Query.new.search(:node, "roles:manager")
#      if !search.nil? and search.size>0
#        search[0].each do |node|
#          if !node.nil? and !node["redBorder"].nil? and !node["redBorder"]["manager"].nil?
#            if node["redBorder"]["manager"]["mode"]==MASTER_MODE
#              master_node=node
#              break
#            end
#          end
#        end
#      end
#  
#      if !master_node.nil?
#        printf "ERROR: There is other #{MASTER_MODE} node configured at the cluster. (#{master_node["hostname"]})\n"
#        return 1
#      end
#    end
#    if (last_mode==MASTER_MODE or last_mode==SLAVE_MODE) and (mode!=MASTER_MODE and mode!=SLAVE_MODE)
#      search=Chef::Search::Query.new.search(:node, "roles:manager")
#      count=0
#      if !search.nil? and search.size>0
#        search[0].each do |node|
#          if !node.nil? and !node["redBorder"].nil? and !node["redBorder"]["manager"].nil?
#            if node["redBorder"]["manager"]["mode"]==MASTER_MODE or node["redBorder"]["manager"]["mode"]==SLAVE_MODE
#              count=count+1
#            end
#          end
#        end
#      end
#   
#      if count<=1
#        printf "ERROR: It is necessary at least one #{MASTER_MODE} or #{SLAVE_MODE} node at the cluster\n"
#        return 1
#      end
#    end
        
    unless mode.nil?
      role.override_attributes["redBorder"]["manager"]["mode"] = mode
      role.override_attributes["redBorder"]["manager"]["services"]["overwrite"]={} 

      node.override!["redBorder"]["manager"]["mode"] = mode
      node.override!["redBorder"]["manager"]["services"] = {} if node["redBorder"]["manager"]["services"].nil?
      node.override!["redBorder"]["manager"]["services"]["overwrite"]={}
      node.override!["redBorder"]["manager"]["services"]["current"]  ={} if node["redBorder"]["manager"]["services"]["current"].nil?

      node.set["redBorder"]["manager"]["mode"] = mode
      node.set["redBorder"]["manager"]["services"]["overwrite"]={} if !node["redBorder"]["manager"]["services"].nil?
    end

    #Configuring services if it is specified
    if !services.nil? and services.size>0
      services.each do |s|
        if !s.nil?
          if s.split(':').size>1
            service_name=s.split(':')[0]
            if s.split(':')[1]=="0" or s.split(':')[1]=="disabled" or s.split(':')[1]=="disable" or s.split(':')[1]=="d" or s.split(':')[1]=="false"
              service_status_boolean=false
            end
          else
            service_name=s
            service_status_boolean=true
          end

          if service_name=="hadoop"
            allservices = ["hadoop_namenode", "hadoop_datanode", "hadoop_nodemanager", "hadoop_resourcemanager", "hadoop_historyserver" ]
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
            allservices<<"nginx" unless allservices.include?"nginx"
            allservices<<"erchef" unless allservices.include?"erchef"
            allservices<<"chef-solr" unless allservices.include?"chef-solr"
            allservices<<"chef-expander" unless allservices.include?"chef-expander"
            allservices<<"rabbitmq" unless allservices.include?"rabbitmq"
          end

          allservices.each do |s2|
            if s2=="darklist_update"
              role.override_attributes["redBorder"]["manager"]["darklist"] = {} if role.override_attributes["redBorder"]["manager"]["darklist"].nil?
              role.override_attributes["redBorder"]["manager"]["darklist"]["update"] = service_status_boolean
            else
              role.override_attributes["redBorder"]["manager"]["services"]["overwrite"][s2]=service_status_boolean
            end
            node.override!["redBorder"] = {} if node["redBorder"].nil?
            node.override!["redBorder"]["manager"] = {} if node["redBorder"]["manager"].nil?
            if s2=="darklist_update"
              node.override!["redBorder"]["manager"]["darklist"] = {} if node["redBorder"]["manager"]["darklist"].nil?
              node.override!["redBorder"]["manager"]["darklist"]["update"] = service_status_boolean
            else
              node.override!["redBorder"]["manager"]["services"]["overwrite"][s2] = service_status_boolean
              node.override!["redBorder"]["manager"]["services"]["current"][s2]   = service_status_boolean
            end
          end
        end
      end
    end

    if role.save and node.save
      if mode.nil?
        if !services.nil? and services.size>0
          printf("INFO: %-50s %s\n", "#{hostname} conserve mode #{last_mode}", ( !services.nil? and services.size>0 ) ? "    (#{services.join(",")})" : "")
        else
          printf("INFO: Nothing to do on #{hostname}\n")
        end
      else
        printf("INFO: %-50s %s\n", "#{hostname} passed from #{last_mode} to #{mode}", ( !services.nil? and services.size>0 ) ? "    (#{services.join(",")})" : "")
      end
    else
      printf "ERROR: #{hostname} cannot pass from #{last_mode} to #{mode} mode\n"
    end
  else
    printf "Usage: rb_set_mode.rb #{MASTER_MODE}|#{SLAVE_MODE}|#{COMPUTE_MODE}|#{STORAGE_MODE}|#{HISTORICAL}|#{REALTIME}|#{REALTIMEPLUS}|#{S3_MODE}|#{WEB_MODE}|#{DATABASE_MODE}|#{HADOOP_MODE}|#{KAFKA_MODE}|#{CUSTOM}|#{WEB_FULL}|#{STORM_NIMBUS}|#{STORM_SUPERVISOR}|#{NPROBE}|#{ZOO_KAFKA}|#{ZOO_WEB}|#{NGINX}|#{CONSUMER}|#{CORE}|#{COREPLUS}|#{COREZK}|#{KAFKACONSUMER}|#{BROKERWEB}|#{ENRICHMENT}|#{MIDDLEMANAGER}|#{SAMZA}|#{WEBDRUID}|#{BROKER}|#{HTTP2K}|#{K2HTTP}|#{DATANODE}|#{NMSPD} [manager1] [manager2] [....]\n"
  end
end


