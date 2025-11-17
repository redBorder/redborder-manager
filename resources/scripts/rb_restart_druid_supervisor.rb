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

def usage
  printf "rb_restart_druid_supervisor.rb [-h] -s <supervisor_name>\n"
  printf "   -h             : print this help\n"
  printf '   -s <supervisor_name>: rb_monitor | rb_monitor_<UUID> | rb_vault (etc)'
  printf ' To get full list of active supervisors, execute rb_get_druid_supervisors'
end

def post_to_supervisor(supervisor_name, action)
  url = 'http://localhost:8090/druid/indexer/v1/supervisor'
  uri = URI("#{url}/#{supervisor_name}/#{action}")

  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = {}.to_json # Druid expects valid JSON body for POST

  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end
  puts response.body
end

opt = Getopt::Std.getopts('s:h')

if opt['h']
  usage
  exit 0
elsif opt['s'].nil?
  usage
  exit 1
else
  supervisor_name = opt['s']
  post_to_supervisor(supervisor_name, 'suspend')
  post_to_supervisor(supervisor_name, 'reset')
  post_to_supervisor(supervisor_name, 'resume')

  # `curl -X POST -H 'Content-Type: application/json' "http://localhost:8090/druid/indexer/v1/supervisor/#{supervisor_name}/suspend"`

  # `curl -X POST -H 'Content-Type: application/json' "http://localhost:8090/druid/indexer/v1/supervisor/#{supervisor_name}/reset`

  # `curl -X POST -H 'Content-Type: application/json' "http://localhost:8090/druid/indexer/v1/supervisor/#{supervisor_name}/resume"`
end
