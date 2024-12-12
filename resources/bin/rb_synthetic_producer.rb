#!/usr/bin/env ruby
##
#########################################################################
#### Coopyright (c) 2014 ENEO Tecnología S.L.
### This file is part of redBorder.
#### redBorder is free software: you can redistribute it and/or modify
#### it under the terms of the GNU Affero General Public License License as published by
#### the Free Software Foundation, either version 3 of the License, or
#### (at your option) any later version.
#### redBorder is distributed in the hope that it will be useful,
#### but WITHOUT ANY WARRANTY; without even the implied warranty of
#### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#### GNU Affero General Public License License for more details.
#### You should have received a copy of the GNU Affero General Public License License
#### along with redBorder. If not, see <http://www.gnu.org/licenses/>.
##########################################################################

require "getopt/std"
require "yaml"

opt = Getopt::Std.getopts("t:c:p:r:h")

def logit(text)
  printf("%s\n", text)
end

def usage
  logit "Usage: rb_synthetic_producer.rb -p threads -r rate [-t topic] [-c config file] [-h]"
  logit "           -t topic         -> topic to produce"
  logit "           -c config file   -> config file with message schema (overwrites -t)"
  logit "           -p threads       -> producer threads"
  logit "           -r rate          -> messages per second"
  logit "           -h               -> print this help"
  logit "Example: rb_synthetic_producer.rb -t rb_flow -p 2 -r 10000"
  exit 0
end

def implemented_topics(topic)
  paths = Dir["/etc/synthetic-producer/config/*.yml"]
  puts "Topic " + '"'  +  topic + '"' + " has not default configuration file. You have to import it using flag -c \n"
  puts "Only the following topics has default configuration file:"
  paths.each_with_index { |path, i| puts File.basename(path,".yml")}
  exit 0
end

begin
  raise("Synthetic Producer is not installed") if (!File.exist?("/usr/share/synthetic-producer/synthetic-producer.jar"))
rescue RuntimeError => e
  puts "[ERROR] " + e.message
  exit 0
end


usage if opt["h"] || (opt["t"].nil? && opt["c"].nil?) || opt["p"].nil? || opt["r"].nil?

topic = opt["t"].to_s.strip unless opt["t"].nil?
config_file = opt["c"] || "/etc/synthetic-producer/config/#{topic}.yml"
rate = opt["r"].to_s.strip
threads = opt["p"].to_s.strip
if topic == "rb_vault"
  unless File.exist?("/etc/synthetic_producer/python/vault_scan.py")
    puts "[ERROR] vault_scan.py script not found"
    exit 1
  end
  system("/etc/synthetic_producer/python/vault_scan.py")
  exit 0
end

implemented_topics("#{topic}") if (!File.exist?(config_file) && opt["c"].nil?)

begin
  raise("Consul is not installed") if (!system(`consul &>/dev/null`).nil?)
rescue RuntimeError => e
  puts "[ERROR] " + e.message
  exit 0
end

begin
  zk = `consul catalog services | grep -i zookeeper`
  raise("Something went wrong with Consul. Zookeeper service is not registered.") if (zk.eql? "")
rescue RuntimeError => e
  puts "[ERROR] " + e.message
  puts
  puts "These services are registered in Consul:"
  puts `consul catalog services`
  exit 0
end

zk_host="kafka.service:2181"

begin
  system("/bin/java -jar /usr/share/synthetic-producer/synthetic-producer.jar -r #{rate} -t #{threads} -c #{config_file} -z #{zk_host}")
rescue SignalException => e
rescue StandardError => e
rescue Exception => e
end

sleep 1
printf "\n"