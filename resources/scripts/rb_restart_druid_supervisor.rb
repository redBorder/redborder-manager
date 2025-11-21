#!/usr/bin/env ruby
# frozen_string_literal: true

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

require 'net/http'
require 'uri'
require 'json'
require 'optparse'

def usage
  p 'rb_restart_druid_supervisor.rb [-h] -s <supervisor_name>'
  p '   -h             : print this help'
  p '   -s <supervisor_name>: rb_monitor | rb_monitor_<UUID> | rb_vault (etc)'
  p ' To get full list of active supervisors, execute rb_get_druid_supervisors'
end

def post_to_supervisor(supervisor_name, action)
  puts "On #{action} to supervisor #{supervisor_name}..."

  druid_port = 8081
  url = "http://localhost:#{druid_port}/druid/indexer/v1/supervisor"
  begin
    uri = URI("#{url}/#{supervisor_name}/#{action}")

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = { feed: supervisor_name }.to_json

    _response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    # puts response.body
    puts "Action: #{action} to supervisor #{supervisor_name} done."
  rescue e
    puts "ERROR: #{action} to supervisor #{supervisor_name} failed."
  end
end

options = {}
OptionParser.new do |opts|
  opts.on('-s VALUE', 'Specify supervisor name') { |v| options[:s] = v }
  opts.on('-h', 'Display help') { options[:h] = true }
end.parse!

if options[:h]
  usage
elsif options[:s].nil?
  usage
  exit 1
else
  supervisor_name = options[:s]
  post_to_supervisor(supervisor_name, 'suspend')
  post_to_supervisor(supervisor_name, 'reset')
  post_to_supervisor(supervisor_name, 'resume')
end
