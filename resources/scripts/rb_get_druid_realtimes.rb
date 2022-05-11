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

require 'zk'
require 'yaml'
require 'json'
require "getopt/std"

CONTROLLERPATH="/controller"
opt = Getopt::Std.getopts("ht:r")

def logit(text)
  printf("%s\n", text)
end

if opt["h"]
  logit "rb_get_druid_realtimes.rb [-h]"
  logit "    -r       -> pick one random"
  logit "    -h       -> print this help"
  exit 0
end

random=(opt["r"] ? true : false)

zk_host="zookeeper.service:2181"

p_value=true

zk = ZK.new(zk_host)
array = zk.children("/druid/announcements").map{|k| k.to_s}.sort.uniq
array.each do |x|
  if p_value
    if x.end_with?":8084"
      logit "#{x}"
      p_value=false if random
    end
  end
end
