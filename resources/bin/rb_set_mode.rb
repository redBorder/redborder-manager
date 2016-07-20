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

#require 'rubygems'
require 'chef'
require 'json'

load '/usr/lib/redborder/bin/rb_manager_functions.rb'

managers=[]

if ARGV.length > 0
  mode=ARGV[0]
  managers=ARGV[1..ARGV.length-1]
else
  mode="unknown"
end

managers=[`hostname -s`.chomp] if managers.size==0

managers.each do |hostname|
  if hostname.split(":").size>1
    set_mode(hostname.split(":")[0], hostname.split(":")[1])
  else
    set_mode(hostname, mode)
  end
end
