#!/usr/bin/env ruby

require 'json'
require 'chef'
require "getopt/std"

def usage
  printf("rb_node_services [-h] [-s <service>]\n")
  printf("  -h         -> print this help\n")
  printf("  -l         -> Get all services enabled in the current node\n")
  printf("  -s service -> Check if the service is enabled in the current node\n")
  printf("  -n service -> Get all nodes with the specified service enabled\n")
  exit 1
end

opt = Getopt::Std.getopts("hs:ln:")
usage if opt["h"]

if !opt["s"].nil? or !opt["l"].nil?

  hostname = `hostname -s`.chomp

  # Load Chef configuration
  Chef::Config.from_file("/etc/chef/client.rb")
  Chef::Config[:node_name]  = "admin"
  Chef::Config[:client_key] = "/etc/chef/admin.pem"
  Chef::Config[:http_retry_count] = 5

  node = Chef::Node.load(hostname)
  node_services = node.default["redborder"]["services"]

  if !opt["s"].nil?
    # Check if the service is enabled in the current node
    service = opt["s"]
    if !node_services.nil?
      if node_services[service].is_a?(TrueClass) || node_services[service].is_a?(FalseClass)
        if node_services[service]
          #Service enabled
          printf "Service: #{service} is ENABLED in this node\n"
          exit 0
        else
          #Service disabled
          printf "Service: #{service} is DISABLED in this node\n"
          exit 1
        end
      else
        #Service not exists
        printf "Service: #{service} DON'T EXISTS in this node\n"
        exit 1
      end
    end
  elsif !opt["l"].nil?
    if !node_services.nil?
      enabled_services = {}
      node_services.each do |k,v|
        enabled_services[k] = v if v
      end
      puts enabled_services.to_json
      exit 0
    end
  end
elsif !opt["n"].nil?
  nodes = []
  service = opt["n"]
  consul_response = JSON.parse(`curl -X PUT http://localhost:8500/v1/catalog/service/#{service} 2>/dev/null`)
  consul_response.each_with_index do |n,i|
    nodes[i] = n["Node"]
  end
  puts nodes
else
  usage
end
