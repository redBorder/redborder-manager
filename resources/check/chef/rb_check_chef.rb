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
require_relative 'rb_check_chef_functions.rb'

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
nodes = get_nodes_with_service("chef-client")

title_ok("Chef",colorless, quiet)

nodes.each do |node|
  status = 0
  subtitle("Services status", colorless, quiet)

  %w[chef-client opscode-rabbitmq opscode-expander
     opscode-oc_id opscode-redis_lb opscode-chef-mover opscode-nginx
     opscode-solr4 opscode-erchef opscode-oc_bifrost].each do | service |
    # opscode-bookshelf  is inactive
    # opscode-postgresql is inactive

    status_service = get_service_status(service,node)
    print_service_status(service, node, status_service, colorless, quiet)
    status = 1 if status_service != 0

  end

  if status == 0

    subtitle("Chef\'s last time execution", colorless, quiet)
    return_value, seconds_from_last_run, interval, splay = check_last_chef_run(node)
    if return_value == 0
      text = "Chef\'s last run was #{seconds_from_last_run}s ago"
    else
      text = "Chef\'s last run was #{seconds_from_last_run}s ago, when its interval and splay are #{interval} and #{splay}"
      has_errors = true
    end
    print_command_output(text, return_value, colorless, quiet)

    subtitle("knife commands", colorless, quiet)
    %w[node client].each do |command|
      if system("knife #{command} list &> /dev/null")
        return_value = 0
      else
        return_value = 1
        has_errors = true
      end
      print_command_output("knife #{command} list", return_value, colorless, quiet)
    end

    subtitle("Rabbitmq commands", colorless, quiet)
    %w[status list_users].each do |command|
      if system("rabbitmqctl #{command} &> /dev/null")
        return_value = 0
      else
        return_value = 1
        has_errors = true
      end
      print_command_output("rabbitmqctl #{command}", return_value, colorless, quiet)
    end


  else
    has_errors = true
  end
end

exit 1 if has_errors
