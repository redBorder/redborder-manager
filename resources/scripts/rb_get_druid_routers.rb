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

def print_router(zk, zk_id)
  zktdata,stat = zk.get("/druid/discoveryPath/druid:router/#{zk_id}")
  zktdata = YAML.load(zktdata)
  if zktdata["address"] and zktdata["port"]
    logit "#{zktdata["address"]}:#{zktdata["port"]}"
  end
end

if opt["h"]
  logit "rb_get_druid_routers.rb [-h]"
  logit "    -r       -> pick one random"
  logit "    -h       -> print this help"
  exit 0
end

random=(opt["r"] ? true : false)

zk_host="zookeeper.service:2181"

zk = ZK.new(zk_host)
routers = zk.children("/druid/discoveryPath/druid:router").map{|k| k.to_s}.sort.uniq

if random
  print_router zk, routers.shuffle.first
else
    routers.each do |b|
        print_router zk, b
  end
end
