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

require 'yaml'
require 'zk'
require "getopt/std"

CONTROLLERPATH="/controller"
opt = Getopt::Std.getopts("hnt:")

def logit(text)
  printf("%s\n", text)
end

def topic_path(topic)
  return "/brokers/topics/#{topic}"
end

def partitions_path(topic)
  return "#{topic_path(topic)}/partitions"
end

def partition_path(topic, partition)
  return "#{partition_path(topic)}/#{partition}"
end

def partition_path_state(topic, partition)
  return "#{partition_path(topic, partition)}/state"
end

def get_partitions(zk, topic)
  return zk.children(partitions_path(topic)).map{|k| k.to_i}.sort.uniq
end

if opt["h"]
  logit "rb_get_topics.rb [-n][-h][-t topic]"
  logit "    -n    -> do not resolve names"
  logit "    -h    -> print this help"
  logit "    -t <topic> -> only this topic"
  exit 0
end

zk_host="zookeeper.service:2181"
print_header=false
begin
  broker_names={}
  zk = ZK.new(zk_host)
  if zk.nil?
    logit "Cannot connect with #{zk_host}"
  else
    unless print_header
      logit "============================================================ Kafka Topics ==========================================================================="
      printf("%-43s %-3s %-17s %-30s %-30s %-30s", "Topic", "P", "Leader", "Replicas", "In-Sync-Replicas", "Consumer")
      printf("\n")

      logit "-----------------------------------------------------------------------------------------------------------------------------------------------------"
      print_header=true
    end

    brokerids = zk.children("/brokers/ids").map{|k| k.to_i}.sort.uniq

    if zk.exists?CONTROLLERPATH
      zktdata,stat = zk.get(CONTROLLERPATH)
      zktdata = YAML.load(zktdata)
      controller_id=zktdata["brokerid"]
    else
      controller_id=-1
    end

    if brokerids.size>0
      brokerids.each do |brid|
        zkdata,stat = zk.get("/brokers/ids/#{brid}")
        zkdata = YAML.load(zkdata)
        broker_names[brid]=zkdata["host"].split(".")[0]
      end
    else
      logit "There are no available brokers on #{zk_host}"
    end

    if opt["t"].nil?
      topics=zk.children("/brokers/topics").sort.uniq
    else
      topics=opt["t"].to_s.split(",")
    end

    topics.each do |topic|
      next if topic=="rb_alarm" or topic=="__consumer_offsets" or topic=="app"

      index=0
      if zk.exists?("#{topic_path(topic)}")
        partitions = zk.children(partitions_path(topic)).map{|k| k.to_i}.sort.uniq
        zkdata,stat = zk.get(topic_path(topic))
        zkdata = YAML.load(zkdata)
        partitions.each do |p|
          replicas = zkdata["partitions"][p.to_s]
          if zk.exists?("#{topic_path(topic)}/partitions/#{p}/state")
            #druid realtime
            druid_rt=""
            if zk.exists?"/consumers/rb-group/owners/#{topic}/#{p}"
                zkdata2,stat = zk.get("/consumers/rb-group/owners/#{topic}/#{p}")
                match_re = zkdata2.match /rb-group_([a-zA-Z\d\.-]*)-[\d]*-.*/
                if match_re.nil? or match_re.size<2
                    druid_rt="?" if topic!="rb_alarm"
                else
                    druid_rt="#{match_re[1]} (rt)"
                end
            elsif zk.exists?"/consumers/rb-storm/owners/#{topic}/#{p}"
                zkdata2,stat = zk.get("/consumers/rb-storm/owners/#{topic}/#{p}")
                match_re = zkdata2.match /rb-storm_([^:]*):.*/
                if match_re.nil? or match_re.size<2
                    druid_rt="?" if topic!="rb_alarm"
                else
                    druid_rt="#{match_re[1]} (storm)"
                end
            else
                druid_rt="-" if topic!="rb_alarm"
            end

            pdata,stat = zk.get("#{topic_path(topic)}/partitions/#{p}/state")
            pdata = YAML.load(pdata)
            if opt["n"]
                printf("%-43s %-3s %-17s %-30s %-30s %-30s",index==0 ? topic : " ", p, pdata["leader"], replicas.join(","), pdata["isr"].join(","), (druid_rt.nil? ? "" : druid_rt))
            else
                printf("%-43s %-3s %-17s %-30s %-30s %-30s",index==0 ? topic : " ", p, (broker_names[pdata["leader"]].nil? ? "-" : broker_names[pdata["leader"]]), replicas.map{|x| (broker_names[x].nil? ? "-" : broker_names[x])}.join(","), pdata["isr"].map{|x| (broker_names[x].nil? ? "-" : broker_names[x])}.join(","), (druid_rt.nil? ? "" : druid_rt))
            end
            printf("\n")
          else
            printf("%-43s %-10s %-s", index==0 ? topic : " ", p, "partition with errors!! (#{topic_path(topic)}/partitions/#{p}/state doesn't exists on #{zk_host})\n")
          end
          index=index+1
        end
        logit "-----------------------------------------------------------------------------------------------------------------------------------------------------"
      else
          printf("ERROR: The topic %s doesn't exist (%s)\n", topic, topic_path(topic));
          logit "-----------------------------------------------------------------------------------------------------------------------------------------------------"
      end
    end
  end
rescue => e
  logit "ERROR: Exception on #{zk_host}"
  puts "#{e}\n\t#{e.backtrace.join("\n\t")}"
ensure
  if !zk.nil? and !zk.closed?
    zk.close
  end
end
