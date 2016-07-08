#!/usr/bin/ruby

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

require 'colorize'

service = ARGV[0]
service_file = "/etc/redborder/#{service}.list"
role_file = "/etc/redborder/role-#{service}.list"

nodes=[]

# If /etc/redborder/service.list exists, use it.
# If not, lets parse rb_get_services
if File.exists?(service_file) or File.exists?(role_file)
  if File.exists?(service_file)
    file = File.open service_file, 'r'
    file.each_line do |line|
      nodes<<line
    end
  elsif File.exists?(role_file)
    file = File.open role_file, 'r'
    file.each_line do |line|
      nodes<<line if !nodes.include?line
    end
  end
else
  # Execute the command and split in lines
  output = `rb_set_service.rb`.uncolorize
  lines = output.split(/\n/);

  # Get the nodes where the service is activated
  lines.each do |line|
    next if line.include? 'all cluster:'
    aux = line.split(/ \(\d+\): /)
    node_name = aux[0]
    node_services = aux[1]
    nodes << node_name if node_services.include? "#{service}:1"
  end
end
  
puts nodes.sort.uniq
