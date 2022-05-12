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
require_relative 'rb_check_netflow_functions.rb'

#command = "tcpdump -ni bond0 port 2055 -c 1 2>&1 | grep captured | awk '{print $1}'" #TODO
command = "timeout 10s tcpdump -ni ens192 port 2055 -c 1 2>&1 | grep captured | awk '{print $1}'"

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
service = "f2k"
nodes = get_nodes_with_service(service)

title_ok("Netflow (f2k)",colorless, quiet)

nodes.each do |node|
  status = get_service_status(service,node)
  print_service_status(service, node, status, colorless, quiet)

  if status == 0
    execute_command_on_node(node,command)
    return_value = $?.to_s.split(" ")[3].to_i
    if return_value == 0
      output = "#{node} is receiving data from netflow"
    else
      output = "#{node} is not receiving data from netflow"
      has_errors = true
    end
    print_command_output(output, return_value, colorless, quiet)
  else
    has_errors = true
  end
end

exit 1 if has_errors
