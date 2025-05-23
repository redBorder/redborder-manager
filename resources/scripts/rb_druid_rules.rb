#!/usr/bin/env ruby
# frozen_string_literal: true

########################################################################
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

require 'getopt/std'
require 'net/http'
require 'json'
require 'yaml'
require 'zk'
require 'iso8601'


def usage
  puts 'rb_druid_rules.rb [-t datasource -p hotperiod -r hotreplicants -d defaultperiod -i defaultreplicants] [-t datasource -l] [-h]'
  puts '       -t datasource          -> datasource to modify segments from (_default for the default datasource)'
  puts '       -p hot period          -> config for the hot tier'
  puts '       -r hot replicants      -> replicants for the hot tier'
  puts '       -d default period      -> config for the default tier'
  puts '       -i default replicants  -> replicants for the default tier'
  puts '       -l list                -> asks for the current rules of a given datasource'
  puts '       -h                     -> print this help'
  puts ''
  puts "period values: any iso 8601 period (i.e. p1m) plus 'none' and 'forever'"
  puts 'Replicants values: Any integer greater than zero'
  puts 'Examples: rb_druid_rules.rb -t rb_flow -p p1m -r 1 -d forever -i 1'
  puts '          rb_druid_rules.rb -t _default -p pt12h -r 2 -d p1m -i 2'
  puts '          rb_druid_rules.rb -t rb_event -p pt6h -r 2 -d p1y -i 1'
  exit 0
end

def parse_period(period)
  if period.nil?
    puts "Periods can't be null. You need to specify -p and -d params."
    exit 1
  end

  if period != 'none' && period != 'forever'
    begin
      ISO8601::Duration.new period.upcase
      period.upcase
    rescue ISO8601::Errors::UnknownPattern
      puts 'You specified a non-valid period.'
      exit 1
    end
  else
    period
  end
end

def calculate_payload(hot_period, default_period, hot_replicants, default_replicants)
  if hot_period == 'none' && default_period == 'forever'
    [
      { type: :loadForever,
        tieredReplicants: { '_default_tier' => default_replicants } }
    ]
  elsif hot_period != 'none' && default_period == 'forever'
    [
      { type: :loadByPeriod, period: hot_period,
        tieredReplicants: { hot: hot_replicants, '_default_tier' => 0 } },
      { type: :loadForever,
        tieredReplicants: { hot: 0, '_default_tier' => default_replicants } }
    ]
  elsif hot_period == 'none' && default_period != 'forever'
    [
      { type: :loadByPeriod, period: default_period,
        tieredReplicants: { '_default_tier' => default_replicants } },
      { type: :dropForever }
    ]
  else # hot_period != 'none' && default_period != 'forever'
    [
      { type: :loadByPeriod, period: hot_period,
        tieredReplicants: { hot: hot_replicants, '_default_tier' => 0 } },
      { type: :loadByPeriod, period: default_period,
        tieredReplicants: { hot: 0, '_default_tier' => default_replicants } },
      { type: :dropForever }
    ]
  end
end

opt = Getopt::Std.getopts('t:p:r:d:i:lh')

usage if opt['h']

datasource = opt['t']
if datasource.nil? && opt['l'].nil?
  puts 'You need to specify a datasource in order to set rules'
  exit 1
end

zk_host = 'zookeeper.service:2181'

begin
  zk = ZK.new(zk_host)

  if zk
    coordinator = zk.children('/druid/discoveryPath/druid:coordinator').map(&:to_s).uniq.shuffle
    zktdata,stat = zk.get("/druid/discoveryPath/druid:coordinator/#{coordinator.first}")
    zktdata = YAML.load(zktdata)
    node = "#{zktdata['address']}:#{zktdata['port']}" if zktdata['address'] && zktdata['port']
    uri = URI("http://#{node}/druid/coordinator/v1/rules/#{datasource}")
  
    if opt['l'] # list rules
      res = Net::HTTP.get(uri)
      puts JSON.pretty_generate(JSON.parse(res))
    else # set a rule
      hot_replicants = opt['r'].to_i
      default_replicants = opt['i'].to_i
      hot_period = parse_period opt['p']
      default_period = parse_period opt['d']
    
      # Build the request
      req = Net::HTTP::Post.new(uri)
      req.content_type = 'application/json'
      payload = calculate_payload(hot_period, default_period, hot_replicants, default_replicants)
      req.body = JSON.generate payload
    
      # Get the response
      res = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end
    end
  end
  
rescue ZK::Exceptions::ConnectionLoss, StandardError => e
  puts "Failed to connect to ZooKeeper: #{e.message}"
  exit 1
end