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

require 'zk'
require 'yaml'
require 'json'

CONTROLLERPATH="/controller"

def distance_of_time_in_days_hours_and_minutes(from_time, to_time)
  from_time = from_time.to_time if from_time.respond_to?(:to_time)
  to_time = to_time.to_time if to_time.respond_to?(:to_time)
  distance_in_days    = (((to_time - from_time).abs) / 86400).round
  distance_in_hours   = ((((to_time - from_time).abs) % 86400)/ 3600).round
  distance_in_minutes = ((((to_time - from_time).abs) % 3600) / 60).round
  difference_in_words = ''
  difference_in_words << "#{distance_in_days} #{distance_in_days > 1 ? 'days' : 'day' }, " if distance_in_days > 0
  difference_in_words << "#{distance_in_hours} #{distance_in_hours > 1 ? 'hours' : 'hour' } and " if distance_in_hours > 0
  difference_in_words << "#{distance_in_minutes} #{distance_in_minutes == 1 ? 'minute' : 'minutes' }"
end

def logit(text)
  printf("%s\n", text)
end

zk_host="zookeeper.service:2181"

logit "================================ Kafka Brokers ================================"
printf("%-20s %-7s %-4s %-12s %-25s\n", "Hostname", "Port", "ID", "Controller", "Joined Time")
logit "-------------------------------------------------------------------------------"

begin
  zk = ZK.new(zk_host)
  if zk.nil?
    logit "Cannot connect with #{zk_host}"
  else
    brokerids = zk.children("/brokers/ids").map{|k| k.to_i}.sort.uniq

    if zk.exists?CONTROLLERPATH
      zktdata, _ = zk.get(CONTROLLERPATH)
      zktdata = YAML.load(zktdata)
      controller_id=zktdata["brokerid"]
    else
      controller_id=-1
    end

    if brokerids.size>0
      brokerids.each do |brid|
        zkdata,stat = zk.get("/brokers/ids/#{brid}")
        zkdata = YAML.load(zkdata)
        printf("%-20s %-7s %-4s %-12s %-25s\n", zkdata["host"], zkdata["port"], brid, (brid==controller_id ? "yes" : "-"),
               distance_of_time_in_days_hours_and_minutes(Time.at(zkdata["timestamp"].to_i/1000), Time.now))
      end
    else
      logit "There are no available brokers on #{zk_host}"
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
