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

require 'json'
require "getopt/std"
require 'net/http'

opt = Getopt::Std.getopts("hcelmnupvwz")

pipelines=["rbwindow-pipeline", "apstate-pipeline", "intrusion-pipeline", "bi-pipeline", "scanner-pipeline", "nmsp-pipeline", "radius-pipeline", "vault-pipeline", "netflow-pipeline", "sflow-pipeline", "meraki-pipeline", "monitor-pipeline", "location-pipeline", "mobility-pipeline", "redfish-pipeline", "bulkstats-pipeline", "ips-pipeline", "mailgw-pipeline", "scores-pipeline", "malware-pipeline"]

logstash="localhost:9600"

def usage
  printf("USAGE: rb_get_logstash_stats.sh [-h][-c][-l][-m][-n][-u][-p][-v][-w][-z]\n")
  printf("  * -h -> get this help\n")
  printf("  * -c -> get logstash cpu percent\n")
  printf("  * -l -> get logstash load average 1m\n")
  printf("  * -m -> get logstash load average 5m\n")
  printf("  * -n -> get logstash load average 15m\n")
  printf("  * -u -> get logstash heap used percent\n")
  printf("  * -v -> get logstash memory\n")
  printf("  * -e [<pipeline>] -> get logstash in events\n")
  printf("  * -w <pipeline> -> get the number of events in queue\n")
  printf("  * -z <pipeline> -> get the number of events in queue in bytes\n")
  printf("  * pipelines: rbwindow-pipeline apstate-pipeline intrusion-pipeline bi-pipeline scanner-pipeline nmsp-pipeline radius-pipeline vault-pipeline netflow-pipeline sflow-pipeline meraki-pipeline monitor-pipeline location-pipeline mobility-pipeline redfish-pipeline bulkstats-pipeline ips-pipeline mailgw-pipeline scores-pipeline malware-pipeline \n")
end


def get_size(node, url)
  return JSON.parse(Net::HTTP.get(URI.parse("http://#{node}/#{url}"))).size
end

def get_elements(node, url)
  return Net::HTTP.get(URI.parse("http://#{node}/#{url}"))
end

if opt["h"] or opt.empty?
  usage
elsif opt["c"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["percent"]
  printf("\n")
elsif opt["e"]
  pipeline = ARGV[0] rescue nil
  unless pipelines.include? pipeline
    print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/events?pretty")))["events"]["in"]
    printf("\n")
  else
    print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/pipelines/#{pipeline}?pretty")))["pipelines"]["#{pipeline}"]["events"]["in"] rescue print 0
  end
elsif opt["l"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["load_average"]["1m"]
  printf("\n")
elsif opt["m"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["load_average"]["5m"]
  printf("\n")
elsif opt["n"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["load_average"]["15m"]
  printf("\n")
elsif opt["u"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/jvm?pretty")))["jvm"]["mem"]["heap_used_percent"]
  printf("\n")
elsif opt["w"]
  pipeline = ARGV[0] rescue nil
  unless pipelines.include? pipeline
    print 0
  else
    print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/pipelines/#{pipeline}?pretty")))["pipelines"]["#{pipeline}"]["queue"]["events_count"] rescue print 0
  end
elsif opt["z"]
  pipeline = ARGV[0] rescue nil
  unless pipelines.include? pipeline
    print 0
  else
    print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/pipelines/#{pipeline}?pretty")))["pipelines"]["#{pipeline}"]["queue"]["queue_size_in_bytes"] rescue print 0
  end
elsif opt["v"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["mem"]["total_virtual_in_bytes"]
end
