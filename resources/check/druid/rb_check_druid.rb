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
require_relative 'rb_check_druid_functions.rb'

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
title_ok("Druid",colorless, quiet)

%w[druid-broker druid-coordinator druid-historical druid-realtime].each do | service |
  nodes = get_nodes_with_service(service)
  status = 0

  nodes.each do |node|

    service_name = service[6..-1] # Removing druid-
    subtitle("Druid #{service_name} status", colorless, quiet)

    status_service = get_service_status(service,node)
    print_service_status(service, node, status_service, colorless, quiet)
    status = 1 if status_service != 0

    if status == 0
      output = execute_command_on_node(node,"/usr/lib/redborder/scripts/rb_get_druid_#{service_name}s.rb").gsub("\n","")
      return_value = $?.exitstatus
      has_errors = true if return_value != 0
      print_command_output(output, return_value, colorless, quiet)
    else
      has_errors = true
    end
  end
end

exit 1 if has_errors
