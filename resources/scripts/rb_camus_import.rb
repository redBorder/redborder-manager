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

require 'zk'
require 'getopt/std'
require 'socket'
require 'yaml'

opt = Getopt::Std.getopts("t:h")

def logit(text)
  printf("%s\n", text)
end

if(opt["h"].nil? && opt["t"].nil?)
  exit 1
end

if opt["h"]
  logit "rb_camus_import.rb -t topic [-h]"
  logit "    -t topic [rb_event|rb_event_post|rb_flow|rb_flow_post|rb_loc|rb_nmsp|rb_monitor|rb_loc_post|rb_monitor_post|all] -> topic to import"
  logit "    -h       -> print this help"
  exit 1
end

topic=opt["t"]
dir="/var/camus"
classpath="/var/camus/app/camus.jar:/var/hadoop/etc/hadoop:/var/hadoop/share/hadoop/common/lib/*:/var/hadoop/share/hadoop/common/*:/var/hadoop/share/hadoop/hdfs:/var/hadoop/share/hadoop/hdfs/lib/*:/var/hadoop/share/hadoop/hdfs/*:/var/hadoop/share/hadoop/yarn/lib/*:/var/hadoop/share/hadoop/yarn/*:/var/hadoop/share/hadoop/mapreduce/lib/*:/var/hadoop/share/hadoop/mapreduce/*:/var/hadoop/contrib/capacity-scheduler/*.jar"

zk=nil
zk_host="localhost:2181"
config=YAML.load_file('/etc/managers.yml')
if !config["zookeeper"].nil? or !config["zookeeper2"].nil?
  zk_host=((config["zookeeper"].nil? ? [] : config["zookeeper"].map{|x| "#{x}:2181"}) + (config["zookeeper2"].nil? ? [] : config["zookeeper2"].map{|x| "#{x}:2182"})).join(",") 
  zk = ZK.new(zk_host)
end

topicsBarrier=nil

if zk.exists?("/camus")
   topicsBarrier=zk.children("/camus").map{|k| k.to_s}.sort.uniq
else
   zk.create("/camus")
end

if !topicsBarrier.nil? and (topicsBarrier.include? topic or topicsBarrier.include? 'all')
   if topicsBarrier.include? 'all'
      topic='all'
   end
   anotherHost,stat=zk.get("/camus/#{topic}")
   logit "The camus importer daemon [topic: #{topic}] is running in #{anotherHost}"
   exit 0
else
   zk.create("/camus/#{topic}",data: Socket.gethostname.to_s, ephemeral: true)
end

if (topic == 'rb_event' or topic == 'rb_event_post' or topic == 'rb_flow' or topic == 'rb_flow_post' or topic == 'rb_monitor' or topic == 'rb_monitor_post' or topic == 'rb_loc' or topic == 'rb_loc_post' or topic == 'rb_nmsp' or topic == 'all')
    if(topic == 'all')
       system("java -cp #{classpath} com.linkedin.camus.etl.kafka.CamusJob -P #{dir}/conf/camus.properties")
       zk.delete("/camus/#{topic}")
       exit 0 
    else
       system("java -cp #{classpath} com.linkedin.camus.etl.kafka.CamusJob -P #{dir}/conf/camus.properties -D kafka.whitelist.topics=#{topic}")
       zk.delete("/camus/#{topic}")
       exit 0  
    end
else
   logit "topic must be [rb_event|rb_event_post|rb_flow|rb_flow_post|rb_monitor|rb_monitor_post|all]"
   exit 1
end


