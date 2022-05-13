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
require 'getopt/std'
require_relative '/usr/lib/redborder/lib/check/check_functions.rb'
require_relative 'rb_check_kafka_functions.rb'

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
service = "kafka"
nodes = get_nodes_with_service(service)

title_ok("Kafka",colorless, quiet)

nodes.each do |node|
  subtitle("Service status", colorless, quiet)
  status = get_service_status(service,node)
  print_service_status(service, node, status, colorless, quiet)

  if status == 0
    subtitle("Brokers status", colorless, quiet)
    output = `timeout 10s /usr/lib/redborder/scripts/rb_get_brokers.rb | grep 9092`.gsub("\n","")
    return_value = $?.exitstatus
    has_errors = true if return_value != 0
    print_command_output(output, return_value, colorless, quiet)

    subtitle("Topics creation", colorless, quiet)
    %w[rb_monitor rb_flow rb_event rb_loc rb_social].each do | topic |
      command = `timeout 10s /usr/lib/redborder/scripts/rb_get_topics.rb -t #{topic} | grep #{topic}`
      return_value = $?.exitstatus

      if return_value == 0
        output = "Topic " + topic
      else
        has_errors = true
        output = "Topic " + topic + " did not found"
      end

      print_command_output(output, return_value, colorless, quiet)
    end
  else
    has_errors = true
  end
end

exit 1 if has_errors
