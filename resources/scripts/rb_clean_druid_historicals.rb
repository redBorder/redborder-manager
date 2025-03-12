#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2025 ENEO Tecnología S.L.
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
require 'optparse'
require 'chef'
require 'shellwords'

CHEF_KNIFE = '/root/.chef/knife.rb'
NEED_TO_STOP_AND_START = %w(chef-client druid-historical)

COLORS = {
  success: "\e[32mSUCCESS\e[0m",
  fail: "\e[31mFAIL\e[0m",
  info: "\e[34mINFO\e[0m"
}

def logit(type, message)
  puts "[#{COLORS[type.to_sym]}] #{message}"
end

def load_node
  knife = Chef::Config.from_file(CHEF_KNIFE)
  node = Chef::Node.load(`hostname`.split('.')[0])
end

def get_historicals(silent=false)
  historicals = []
  node = load_node
  historicals = node["redborder"]["managers_per_services"]["druid-historical"].map(&:strip).map { |h| h.split(".").first(1).join(".") }
  if historicals.empty?
    logit(:fail, "No historical nodes found!") if !silent
  else
    logit(:success, "Found #{historicals.size} historical nodes.") if !silent
  end
  historicals
end

def service_running?(node, service)
  status = `rbcli node execute #{node} "service #{service} status" 2>&1`

  if status.include?("is running") || status.include?("active (running)")
    logit(:success, "Service #{service} is running on #{node}.")
    return true
  elsif status.include?("inactive") || status.include?("not running")
    logit(:fail, "Service #{service} is not running on #{node}.")
    return false
  else
    logit(:fail, "Unable to determine the status of service #{service} on #{node}. Output was: #{status}")
    return false
  end
end

def manage_service(node, service, action)
  logit(:info, "#{action.capitalize} service #{service} on node #{node}...")
  return unless ['start', 'stop'].include?(action)

  if system("rbcli node execute #{node} \"service #{service} #{action}\" > /dev/null 2>&1")
    actionstd = "stopped"
    actionstd = "started" if action == "start"
    logit(:success, "Service #{service} #{actionstd} successfully on #{node}.")
  else
    logit(:fail, "Failed to #{action} service #{service} on #{node}.")
  end
end

def clean_index_cache(node)
  logit(:info, "Cleaning index cache on node #{node}...")

  if system("rbcli node execute #{node} \"rm \\-rf /var/druid/historical/indexCache/*\" > /dev/null 2>&1")
    lsnode = "rbcli node execute #{node} \"ls /var/druid/historical/indexCache/\""
    lsout = `#{lsnode}`
    
    if $?.success?
      if lsout.split("\n").length <= 3
        logit(:success, "Index cache cleaned on #{node}.")
      else
        logit(:fail, "Index cache not fully cleaned on #{node}.")
      end
    else
      logit(:fail, "Failed to execute 'ls' command to check index cache on #{node}. Error: #{lsout}")
    end
  else
    logit(:fail, "Failed to clean index cache on #{node}.")
  end
end

def print_help
  puts "Usage: rb_clean_druid_historicals.rb [options]"
  puts "Options:"
  puts "  -n, --nodes NODE1,NODE2  Execute only on specified nodes"
  puts "  -c, --cluster            Execute on all druid-historical cluster nodes"
  puts "  -h, --help               Show this help message"
  exit
end

def prompt_for_confirmation(nodes)
  print "WARNING: This will clean cached Druid (Cache) data on the following node(s): #{nodes.join(', ')}. Do you want to proceed? (y/n): "
  confirmation = gets.chomp.downcase

  unless confirmation == 'y'
    logit(:info, "Operation aborted. No changes will be made.")
    exit
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: rb_clean_druid_historicals.rb [options]"
  opts.on("-n", "--nodes NODES", "Execute only on specified nodes (comma-separated)") do |n|
    options[:nodes] = n.split(",").map(&:strip)
  end
  opts.on("-c", "--cluster", "Execute on all cluster nodes") do
    options[:cluster] = true
  end
  opts.on("-h", "--help", "Print help message") do
    print_help
  end
end.parse!

if options[:nodes]
  nodes = get_historicals(true)
  demand_nodes = options[:nodes].map(&:strip)

  missing_nodes = demand_nodes.reject { |node| nodes.include?(node) }

  if missing_nodes.empty?
    nodes = demand_nodes
  else
    logit(:fail, "There was an error with nodes; the following nodes could not be found: #{missing_nodes.join(', ')}")
    exit
  end
elsif options[:cluster]
  nodes = get_historicals
else
  logit(:info, "No nodes specified. Use -n for specific nodes or -c for all cluster nodes.")
  exit
end

prompt_for_confirmation(nodes)

nodes.each do |node|
  node = Shellwords.escape(node) # Do not trust nodes
  NEED_TO_STOP_AND_START.each do |service|
    if service_running?(node, service)
      manage_service(node, service, 'stop')
    else
      logit(:info, "Service #{service} is not running on #{node}.")
    end
  end

  clean_index_cache(node)

  NEED_TO_STOP_AND_START.each do |service|
    manage_service(node, service, 'start')
  end
end
