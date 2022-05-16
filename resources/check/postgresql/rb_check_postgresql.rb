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
require_relative 'rb_check_postgresql_functions.rb'

opt = Getopt::Std.getopts("cq")

opt["c"] ? colorless = true : colorless = false
opt["q"] ? quiet = true : quiet = false

has_errors = false
service = "postgresql"
nodes = get_nodes_with_service(service)

title("Postgresql",colorless, quiet)

nodes.each do |node|
  subtitle("Services status", colorless, quiet)

  status = 0

  status_postgres = get_service_status(service,node)
  print_service_status(service, node, status_postgres, colorless, quiet)
  status = 1 if status_postgres != 0

  status_redborder_postgres = get_service_status(service,node)
  print_service_status("redborder-postgresql", node, status_postgres, colorless, quiet)
  status = 1 if status_redborder_postgres != 0

  if status == 0
    subtitle("Databases", colorless, quiet)
    %w[druid opscode_chef radius redborder].each do |database|
      return_value = check_postgres_database(node,database)
      has_errors = true if return_value != 0
      print_command_output("Database #{database} in node #{node}", return_value, colorless, quiet)
    end
  else
    has_errors = true
  end
end

exit 1 if has_errors
