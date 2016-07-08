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
  printf "Usage: rb_set_topic.rb [<topic1>:[realtime|both|rb-enrich|samza|none]|<topic2>:[realtime|samza|both|rb-enrich|none]]\n"
  printf "topics: rb_event, rb_flow, rb_monitor, rb_state, rb_social, rb_loc, rb_nmsp, rb_meraki\n"
end

def get_status s
  if s=="r" or s=="re" or s=="rea" or s=="real" or s=="realt" or s=="realti" or s=="realtim" or s=="realtime"
    return "realtime"
  elsif s=="n" or s=="no" or s=="non" or s=="none" or s=="0"
    return "none"
  elsif s=="b" or s=="bo" or s=="bot" or s=="both" or s=="1"
    return "both"
  elsif s=="r" or s=="rb" or s=="rb-" or s=="rb-e" or s=="rb-en"
    return "rb-enrich"
  elsif s=="sa" or s=="sam" or s=="samz" or s=="samza"
    return "samza"
  else
    return s
  end
end

def get_topic s
  if s=="m" or s=="mo" or s=="mon" or s=="moni" or s=="monit" or s=="monito" or s=="monitor"
    return "rb_monitor"
  elsif s=="e" or s=="ev" or s=="eve" or s=="even" or s=="event"
    return "rb_event"
  elsif s=="f" or s=="fl" or s=="flo" or s=="flow"
    return "rb_flow"
  elsif s=="so" or s=="soc" or s=="soci" or s=="socia" or s=="social"
    return "rb_social"
  elsif s=="s" or s=="st" or s=="stat" or s=="state"
    return "rb_state"
  elsif s=="p" or s=="pm" or s=="pms"
    return "rb_pms"
  elsif s=="l" or s=="lo" or s=="loc"
    return "rb_loc"
  elsif s=="n" or s=="nm" or s=="nms" or s=="nmsp"
    return "rb_nmsp"
  elsif s=="me" or s=="mer" or s=="mera" or s=="merak" or s=="meraki"
    return "rb_meraki"
  elsif s=="i" or s=="io" or s=="iot"
    return "rb_iot"
  else
    return s
  end
end

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/chef-server/admin.pem"
Chef::Config[:http_retry_count] = 5

anyselected = {}

if ARGV.length >= 1 
  role = Chef::Role.load("manager")

  must_save=true
  ARGV.each do |x|
    xv=x.split(":")
    if xv.length >= 2
      topic_name=get_topic(xv[0])
      topic_status=get_status(xv[1])

      anyselected[topic_status] = true

      if ((topic_status=="realtime" or topic_status=="both" or topic_status=="rb-enrich" or topic_status=="samza" or topic_status=="none" ) and (topic_name=="rb_event" or topic_name=="rb_flow" or topic_name=="rb_monitor" or topic_name=="rb_state" or topic_name=="rb_social" or topic_name=="rb_pms" or topic_name=="rb_loc" or topic_name=="rb_meraki" or topic_name=="rb_nmsp" or topic_name=="rb_iot" or topic_name=="all"))
        if topic_name=="all"
          alltopics = []
          alltopics<<"rb_monitor" unless alltopics.include?"rb_monitor"
          alltopics<<"rb_flow" unless alltopics.include?"rb_flow"
          alltopics<<"rb_event" unless alltopics.include?"rb_event"
          alltopics<<"rb_state" unless alltopics.include?"rb_state"
          alltopics<<"rb_social" unless alltopics.include?"rb_social"
          alltopics<<"rb_loc" unless alltopics.include?"rb_loc"
          alltopics<<"rb_meraki" unless alltopics.include?"rb_meraki"
          alltopics<<"rb_nmsp" unless alltopics.include?"rb_nmsp"
          alltopics<<"rb_iot" unless alltopics.include?"rb_iot"
        else
          alltopics = [ topic_name ] 
        end

        alltopics.each do |s|
          if s!="rb_flow" and s!="rb_event" and s!="rb_monitor" and s!="rb_state" and s!="rb_social" and s!="rb_pms" and s!="rb_loc" and s!="rb_meraki" and s!="rb_nmsp" and s!="rb_iot"
            printf "The topic \"#{s}\" is not valid\n"
            must_save=false
          else
            role.override_attributes["redBorder"] = {} if role.override_attributes["redBorder"].nil?
            role.override_attributes["redBorder"]["manager"] = {} if role.override_attributes["redBorder"]["manager"].nil?
            role.override_attributes["redBorder"]["manager"]["topics"] = {} if role.override_attributes["redBorder"]["manager"]["topics"].nil?
            role.override_attributes["redBorder"]["manager"]["topics"][s]= topic_status
            printf "Topic #{s} processed by \"#{topic_status}\"\n"
          end
        end
      else
        must_save=false
      end
    else
      must_save=false
    end
  end
  if must_save
    if role.save
      printf "role[manager] saved successfully\n"
      printf "INFO: remember you have to have enabled hadoop at the cluster on any available node\n" if anyselected["samza"]
    else
      printf "ERROR: role[manager] cannot be saved!!!\n"
    end
  else
    usage
  end
else
  usage
end

