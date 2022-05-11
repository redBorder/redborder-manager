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
require_relative '/usr/lib/redborder/lib/check_functions.rb'
require_relative 'rb_check_kafka-messages_functions.rb'

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
service = "kafka"
nodes = get_nodes_with_service(service)

title_ok("Kafka-Messages",colorless, quiet)

nodes.each do |node|
  %w[rb_monitor rb_flow rb_event rb_loc rb_social].each do | topic |
    output, return_value = `/usr/lib/redborder/bin/rb_manager_utils.sh -e -n #{node} -s "/usr/lib/redborder/scripts/rb_check_topic.rb -t #{topic} -q"`
    has_errors = true if return_value == 1
    print_command_output(output, return_value, colorless, quiet)
  end
end

return 1 if has_errors
