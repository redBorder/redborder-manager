#!/usr/bin/env ruby
#######################################################################
# Copyright (c) 2025 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# You should have received a copy of the GNU Affero General Public License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

require 'zlib'

DRUID_INDEXER_LOG_PATH = "/var/log/druid/indexer/"
DRUID_INDEXER          = "druid-indexer"

def remote_cmd(node, cmd)
  `ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o StrictHostKeyChecking=no -i /var/www/rb-rails/config/rsa root@#{node} "#{cmd}"`.strip
end

def get_nodes
  `serf members | awk '{print $1}'`.split("\n").map(&:strip)
end

def is_in_node(service, node)
  output = `consul catalog services -node=#{node}`.strip
  output.match?(/^#{Regexp.escape(service)}$/)
end

def get_indexers
  indexers = []
  nodes = get_nodes

  return indexers unless nodes.is_a?(Array) && !nodes.empty?

  nodes.each do |node|
    if is_in_node(DRUID_INDEXER, node)
      indexers.push(node)
    end
  end
  indexers
end

def parse_log(line, task_id)
  return line.strip if line.include?(task_id)
  ""
end

def get_logs(indexer, task_id)
  list_cmd = "ls #{DRUID_INDEXER_LOG_PATH}*"
  files_output = remote_cmd(indexer, list_cmd)
  return "" if files_output.nil? || files_output.empty?

  files = files_output.split("\n").map(&:strip).select { |f| f.end_with?(".log", ".gz") }

  results = files.map do |file|
    reader = file.end_with?('.gz') ? "zcat #{file}" : "cat #{file}"
    begin
      raw = remote_cmd(indexer, reader)
      raw.each_line.map { |line| parse_log(line, task_id) }.reject(&:empty?).join("\n")
    rescue => e
      warn "Error reading #{file} on #{indexer}: #{e.message}"
      ""
    end
  end

  results.reject(&:empty?).join("\n")
end

def main
  if ARGV.length < 1
    puts "Usage: #{$0} <task_id> [target_node]"
    exit 1
  end

  task_id = ARGV[0]

  unless task_id =~ /\Aindex_kafka_rb_[\w]+_[\w]+\z/
    warn "Invalid task ID format."
    exit 1
  end

  target = ARGV[1] || 'all'
  indexer_nodes = (target != 'all') ? [target] : get_indexers

  if indexer_nodes.empty?
    warn "No indexer nodes found."
    exit 1
  end

  begin
    indexer_nodes.each do |indexer|
      logs = get_logs(indexer, task_id)
      puts "#{"=" * 90}"
      puts "Logs for task #{task_id} on indexer #{indexer}"
      puts "#{"=" * 90}"
      puts logs.empty? ? "(No logs found for this task)" : logs
      puts "\n"
    end
  rescue StandardError => e
    warn "An error occurred while processing logs: #{e.message}"
    exit 2
  end
end

main
