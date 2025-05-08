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

require 'json'
require "getopt/std"
require 'net/http'
require 'zookeeper'
require 'chef'

opt = Getopt::Std.getopts("hwprcoudn")

def usage
  printf("USAGE: rb_get_tasks.rb [-h][-w][-p][-r][-c][-o][-u][-d][-n]\n")
  printf("  * -h -> get this help\n")
  printf("  * -w -> get all waiting tasks\n")
  printf("  * -p -> get all pending tasks\n")
  printf("  * -r -> get all running tasks\n")
  printf("  * -c -> get all capacity (always integer)\n")
  printf("  * -o -> get all running capacity used in %% (always integer)\n")
  printf("  * -d -> get all desired capacity used in %% (always integer)\n")
  printf("  * -u -> get current indexer running tasks\n")
  printf("  * -n -> show only num\n")
end

def load_node
  Chef::Config.from_file('/etc/chef/client.rb')
  Chef::Config[:node_name] = 'admin'
  Chef::Config[:client_key] = '/etc/chef/admin.pem'
  Chef::Config[:http_retry_count] = 5

  Chef::Node.load(`hostname`.split('.')[0])
end

def get_size(node, url)
  return JSON.parse(Net::HTTP.get(URI.parse("http://#{node}/#{url}"))).size
end

def get_elements(node, url)
  return Net::HTTP.get(URI.parse("http://#{node}/#{url}"))
end

def get_router_from_zk(zookeeper_host = 'zookeeper.service:2181')
  zk = Zookeeper.new(zookeeper_host)
  base_path = '/druid/discoveryPath/druid:router'
  children = zk.get_children(path: base_path)[:children]

  return 'localhost:8888' if children.nil? || children.empty?

  data = zk.get(path: "#{base_path}/#{children.first}")[:data]
  info = JSON.parse(data)
  zk.close

  "#{info['address']}:#{info['port']}"
end

def get_all_zk_nodes
  node = load_node
  node['redborder']['managers_per_services']['zookeeper']
    .map(&:strip)
    .map { |h| h.split('.').first + ".node." + node['redborder']['cdomain'] + ":" + node['redborder']['zookeeper']['port'].to_s }
    .join(',')
end

router = get_router_from_zk(get_all_zk_nodes)

if opt["h"]
  usage
elsif opt["c"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{router}/druid/indexer/v1/workers"))).map{|x| x["worker"]["capacity"]}.inject{|sum,x| sum + x }
  printf("\n")
elsif opt["o"]
  worker=JSON.parse(Net::HTTP.get(URI.parse("http://#{router}/druid/indexer/v1/workers")))
  print (100.0 * (worker.map{|x| x["currCapacityUsed"]}.inject{|sum,x| sum + x } + get_size(router, "druid/indexer/v1/pendingTasks") )/worker.map{|x| x["worker"]["capacity"]}.inject{|sum,x| sum + x }).ceil
  printf("\n")
elsif opt["d"]
  worker=JSON.parse(Net::HTTP.get(URI.parse("http://#{router}/druid/indexer/v1/workers")))
  tasks = JSON.parse(get_elements(router, "druid/indexer/v1/pendingTasks")) + JSON.parse(get_elements(router, "druid/indexer/v1/runningTasks")) + JSON.parse(get_elements(router, "druid/indexer/v1/waitingTasks"))
  current=0
  other=0
  t = Time.now
  str="_#{t.year}-#{t.month<10?"0":""}#{t.month}-#{t.day<10?"0":""}#{t.day}T#{t.hour<10?"0":""}#{t.hour}:"
  tasks.each do |t| #TODO: define another name for the variable
    if !t["id"].nil? and t["id"].include?str
      current=current+1
    else
      other=other+1
    end
  end
  print (100.0 * ( (other>0 ? 1 : 2) * current + other )/worker.map{|x| x["worker"]["capacity"]}.inject{|sum,x| sum + x }).ceil
  printf("\n")
elsif opt["n"]
  if opt["w"]
    print get_size(router, "druid/indexer/v1/waitingTasks")
  elsif opt["p"]
    print get_size(router, "druid/indexer/v1/pendingTasks")
  elsif opt["r"]
    print get_size(router, "druid/indexer/v1/runningTasks")
  elsif opt["u"]
    print get_size(router, "druid/indexer/v1/tasks")
  end
  printf("\n")
elsif opt["w"]
  print get_elements(router, "druid/indexer/v1/waitingTasks")
  printf("\n")
elsif opt["p"]
  print get_elements(router, "druid/indexer/v1/pendingTasks")
  printf("\n")
elsif opt["r"]
  print get_elements(router, "druid/indexer/v1/runningTasks")
  printf("\n")
elsif opt["u"]
  print get_elements(router, "druid/indexer/v1/tasks")
  printf("\n")
end