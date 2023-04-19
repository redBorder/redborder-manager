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

require 'json'
require "getopt/std"
require 'net/http'
require 'socket'

opt = Getopt::Std.getopts("hlt:")

def usage 
  printf("USAGE: rb_get_tasks.rb [-h][-t <tiername>][-l]\n")
  printf("  * -h -> show this help\n")
  printf("  * -l -> only by leader\n")
  printf("  * -t -> filter by this tier\n")
end

coordinator=`/usr/lib/redborder/bin/rb_get_druid_coordinators`.chomp

if opt["h"]
  usage
else
  getdata=true

  if !opt["l"].nil?
    leader=Net::HTTP.get(URI.parse("http://#{coordinator}/druid/coordinator/v1/leader"))
    getdata=(leader.split(':').first == Socket.gethostbyname(Socket.gethostname).first)
  end

  if getdata
    data=JSON.parse(Net::HTTP.get(URI.parse("http://#{coordinator}/druid/coordinator/v1/tiers?simple")))
    if opt["t"].nil?
      printf("%-20s %20s %20s %20s\n", "Name", "CurrentSize", "MaxSize", "%")
      printf("-----------------------------------------------------------------------------------------------------\n")
      data.each do |name, value|
        printf("%-20s %20s %20s %20.4f\n", name, value["currSize"], value["maxSize"], 100.0 * value["currSize"]/value["maxSize"])
      end
    else
      value=data[opt["t"].to_s]
      printf("%.0f", [(100.0 * value["currSize"]/value["maxSize"]).ceil, 100].min) if !value.nil? and !value["currSize"].nil? and !value["maxSize"].nil? and value["maxSize"]>0
    end
  end
end

