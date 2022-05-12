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
require_relative 'rb_check_memcached_functions.rb'

red = "/usr/lib/redborder/scripts/red.rb"

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
service = "webui"
nodes = get_nodes_with_service(service)

title_ok("Webui",colorless, quiet)

nodes.each do |node|
  status = 0

  #Webui
  status_web = get_service_status(service,node)
  print_service_status(service, node, status, colorless, quiet)
  status = 1 if status_web != 0

  #Workers
  status_workers = get_service_status("rb-workers",node)
  print_service_status(service, node, status, colorless, quiet)
  status = 1 if status_workers != 0


  if status == 0

    command = "curl -m 10 -s #{node}:8001 | grep -q '^You need to sign in or sign up before continuing.'"

    logit "Check login"
    _, return_value = execute_command_on_node(node,command).split("\n")
    print_command_output(node, return_value, colorless, quiet)
    has_errors = true if return_value == 1

  else
    has_errors = true
  end
end

exit 1 if has_errors
